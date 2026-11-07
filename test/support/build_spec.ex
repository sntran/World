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
  @invariants ~w(OneWorkerOneTask WaitsFirst MadeOnce OnePlace InBudget)

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

    events
    |> Enum.reduce_while({:ok, init}, fn e, {:ok, states} ->
      case action(e) do
        nil -> {:cont, {:ok, states}}
        {name, args} -> step(m, states, name, args, e)
      end
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

  # The action of an event, with its arguments.
  defp action(%{kind: "hired", order: b, who: p}), do: {"Hire", [b, p]}
  defp action(%{kind: "task_started", order: b, who: p, data: d}), do: {"Start", [b, p, task(b, d["task"])]}
  defp action(%{kind: "task_done", order: b, who: p, data: d}), do: {"Finish", [p, task(b, d["task"])]}
  defp action(%{kind: "released", order: b, who: p}), do: {"Release", [b, p]}
  defp action(%{kind: "done", order: b}), do: {"Done", [b]}
  defp action(%{kind: "stopped", order: b}), do: {"Deadline", [b]}
  defp action(_), do: nil

  # A task of the specification: the construction and the id of the task.
  defp task(b, id), do: b <> "|" <> id

  defp module(events) do
    plans = for %{kind: "plan_made", order: b, data: d} <- events, t <- d["tasks"], do: {b, t}
    builds = events |> Enum.map(& &1.order) |> Enum.uniq()
    hires = for %{kind: "hired", who: p, data: d} <- events, into: %{}, do: {p, d["trade"]}

    budgets =
      for %{kind: "requested", order: b, data: d} <- events, into: %{}, do: {b, get_in(d, ["budget", "workers"]) || 4}

    """
    ---- MODULE Run ----
    EXTENDS Build, TLC
    RunBuilds == #{set(builds)}
    RunTasks == #{set(for {b, t} <- plans, do: task(b, t["id"]))}
    RunBuildOf == #{fun(Map.new(plans, fn {b, t} -> {task(b, t["id"]), b} end), &str/1)}
    RunWaits == #{fun(Map.new(plans, fn {b, t} -> {task(b, t["id"]), Enum.map(t["waits"], &task(b, &1))} end), &set/1)}
    RunTrade == #{fun(Map.new(plans, fn {b, t} -> {task(b, t["id"]), t["trade"]} end), &str/1)}
    RunPeople == #{set(Map.keys(hires))}
    RunSkill == #{fun(hires, &str/1)}
    RunBudget == #{fun(budgets, &Integer.to_string/1)}
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
        Guard = #{if guard, do: "TRUE", else: "FALSE"}
        HireGuard = TRUE
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
