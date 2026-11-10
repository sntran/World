defmodule World.BuildSpec do
  @moduledoc """
  The replay of the logs of constructions (`World.Construction`) as a
  behavior of `specs/Build.tla`. A module for the replay (`Run.tla`)
  extends `Build` with the tasks, the trades, the people and the budgets
  of the logs as its constants. Then the machine of Accord
  (`Accord.TLA.Checker.Machine`) takes each event as an action of the
  specification, in the order of the wall clock, and checks the
  invariants after each step.
  """
  alias Accord.TLA.Checker.Machine

  @specs Path.expand("../../specs", __DIR__)
  @invariants ~w(OneWorkerOneTask WaitsFirst MadeOnce OnePlace InBudget QuietPause KeepsWhatIsSame PartsHere)

  @doc """
  Replay the logs (`World.Log`) of constructions, in the folder `dir`.
  With `guard: false`, the replay uses the fault model (a task can start
  again). It gives `:ok`, `{:error, {:diverged, event}}` when the
  specification has no step for an event, or `{:error, {:violated,
  invariant, event}}`.
  """
  def replay(logs, dir, opts \\ []) do
    events = logs |> Enum.flat_map(&World.Log.events/1) |> Enum.sort_by(& &1.wall)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "Run.tla"), module(events))
    File.write!(Path.join(dir, "Run.cfg"), config(Keyword.get(opts, :guard, true)))
    {:ok, m} = Machine.load(Path.join(dir, "Run.tla"), paths: [@specs])
    {:ok, init} = Machine.init_states(m)

    # The tasks of a stage of a site (plan 0006) arrive at its start, as
    # the materials of a task: a task of a later stage is not ready.
    {steps, _} =
      Enum.map_reduce(events, MapSet.new(), fn
        %{kind: "stage_started", order: b, data: d} = e, seen ->
          new = for t <- Map.get(d, "tasks", []), not MapSet.member?(seen, task(b, t)), do: task(b, t)
          {{e, actions(e) ++ for(t <- new, do: {"Arrive", [b, t]})}, MapSet.union(seen, MapSet.new(new))}

        e, seen ->
          {{e, actions(e)}, seen}
      end)

    steps
    |> Enum.reduce_while({:ok, init}, fn {e, actions}, {:ok, states} ->
      actions
      |> Enum.reduce_while({:cont, {:ok, states}}, fn {name, args}, {:cont, {:ok, states}} ->
        case step(m, states, name, args, e) do
          {:cont, _} = next -> {:cont, next}
          halt -> {:halt, halt}
        end
      end)
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp step(m, states, name, args, e) do
    next = for s <- states, {:ok, steps} = Machine.step(m, s, name, args), {n, _} <- steps, uniq: true, do: n

    violated = fn s ->
      case Machine.check_invariants(m, s) do
        {:violated, inv} -> inv
        :ok -> nil
      end
    end

    case Enum.find_value(next, violated) do
      _ when next == [] -> {:halt, {:error, {:diverged, e}}}
      nil -> {:cont, {:ok, next}}
      inv -> {:halt, {:error, {:violated, inv, e}}}
    end
  end

  # The actions of an event, with their arguments: a change is one Redo
  # for each task that it makes again, in the order of the event.
  defp actions(%{kind: "changed", order: b, data: d}), do: for(t <- d["redo"], do: {"Redo", [b, task(b, t)]})

  defp actions(e) do
    case action(e) do
      nil -> []
      a -> [a]
    end
  end

  defp action(%{kind: "hired", order: b, who: p}), do: {"Hire", [b, p]}
  defp action(%{kind: "task_started", order: b, who: p, data: d}), do: {"Start", [b, p, task(b, d["task"])]}
  defp action(%{kind: "task_done", order: b, who: p, data: d}), do: {"Finish", [p, task(b, d["task"])]}
  defp action(%{kind: "released", order: b, who: p}), do: {"Release", [b, p]}
  # Between two stages of a site (plan 0006), and in a stage of a pause,
  # the site is in a pause: no task starts.
  defp action(%{kind: "stage_done", order: b, data: %{"work" => w}}) when w != "pause", do: {"Pause", [b]}

  defp action(%{kind: "stage_started", order: b, data: %{"work" => w, "after" => a}}) when w != "pause" and a != nil,
    do: {"Resume", [b]}

  defp action(%{kind: "done", order: b}), do: {"Done", [b]}
  defp action(%{kind: "stopped", order: b}), do: {"Deadline", [b]}
  defp action(%{kind: "paused", order: b}), do: {"Pause", [b]}
  defp action(%{kind: "resumed", order: b}), do: {"Resume", [b]}
  defp action(%{kind: "task_dropped", who: p}), do: {"Drop", [p]}
  defp action(%{kind: "parts_here", order: b, data: d}), do: {"Arrive", [b, task(b, d["task"])]}
  defp action(_), do: nil

  # The waits of each task: of its plan, and the new waits of a change
  # (the parts made again first, plan 0006).
  defp waits(plans, events) do
    base = Map.new(plans, fn {b, t} -> {task(b, t["id"]), Enum.map(t["waits"], &task(b, &1))} end)

    for %{kind: "changed", order: b, data: %{"waits" => more}} <- events, {id, ws} <- more, reduce: base do
      acc ->
        Map.update(acc, task(b, id), Enum.map(ws, &task(b, &1)), &Enum.uniq(&1 ++ Enum.map(ws, fn w -> task(b, w) end)))
    end
  end

  # A task of the specification: the construction and the id of the task.
  defp task(b, id), do: b <> "|" <> id

  defp module(events) do
    # The tasks of the plans, and the tasks of the changes that take down
    # what they drop.
    plans =
      for %{kind: k, order: b, data: d} <- events,
          k in ~w(plan_made changed),
          t <- if(k == "plan_made", do: d["tasks"], else: Map.get(d, "remove", []) ++ Map.get(d, "add", [])),
          do: {b, t}

    builds = events |> Enum.map(& &1.order) |> Enum.uniq()
    hires = for %{kind: "hired", who: p, data: d} <- events, into: %{}, do: {p, d["trade"]}

    budgets =
      for %{kind: "requested", order: b, data: d} <- events,
          into: %{},
          do: {b, d["workers"] || get_in(d, ["budget", "workers"]) || 4}

    """
    ---- MODULE Run ----
    EXTENDS Build, TLC
    RunBuilds == #{set(builds)}
    RunTasks == #{set(for {b, t} <- plans, do: task(b, t["id"]))}
    RunBuildOf == #{fun(Map.new(plans, fn {b, t} -> {task(b, t["id"]), b} end), &str/1)}
    RunWaits == #{fun(waits(plans, events), &set/1)}
    RunTrade == #{fun(Map.new(plans, fn {b, t} -> {task(b, t["id"]), t["trade"]} end), &str/1)}
    RunPeople == #{set(Map.keys(hires))}
    RunSkill == #{fun(hires, &str/1)}
    RunBudget == #{fun(budgets, &Integer.to_string/1)}
    RunHauled == #{set(Enum.uniq(for(%{kind: "parts_asked", order: b, data: d} <- events, do: task(b, d["task"])) ++ for(%{kind: "stage_started", order: b, data: d} <- events, t <- Map.get(d, "tasks", []), do: task(b, t))))}
    ====
    """
  end

  defp config(guard) do
    """
    SPECIFICATION Spec
    CONSTANTS
        Builds <- RunBuilds
        Tasks <- RunTasks
        BuildOf <- RunBuildOf
        Waits <- RunWaits
        Trade <- RunTrade
        People <- RunPeople
        Skill <- RunSkill
        Budget <- RunBudget
        Pauses = 1000
        Guard = #{if guard, do: "TRUE", else: "FALSE"}
        HireGuard = TRUE
        PauseGuard = TRUE
        KeepGuard = TRUE
        Hauled <- RunHauled
        PartsGuard = TRUE
    INVARIANT #{Enum.join(@invariants, " ")}
    """
  end

  defp str(s), do: ~s("#{s}")
  defp set(names), do: "{" <> Enum.map_join(Enum.sort(names), ", ", &str/1) <> "}"

  # A function of TLA+; with no key, the function of the empty set.
  defp fun(map, _value) when map == %{}, do: "[x \\in {} |-> 0]"

  defp fun(map, value) do
    map
    |> Enum.sort()
    |> Enum.map_join(" @@ ", fn {k, v} -> "(#{str(k)} :> #{value.(v)})" end)
  end
end
