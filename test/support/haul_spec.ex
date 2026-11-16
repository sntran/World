defmodule World.HaulSpec do
  @moduledoc """
  The replay of the log of the haul (`World.Haul`), with the logs of the
  constructions that asked it, as a behavior of `specs/Haul.tla`: the
  asks of the log, their loads and their masses, and the trucks, are the
  constants of a module `Run.tla`; each event is one action, in the order
  of the wall clock (the haul first at one time), and the invariants hold
  after each step.
  """
  alias Accord.TLA.Checker.Machine

  @specs Path.expand("../../specs", __DIR__)

  @doc """
  Replay the log of the haul and the logs of constructions in the folder
  `dir`: `:ok`, `{:error, {:diverged, event}}` or `{:error, {:violated,
  invariant, event}}`. With `guard: false`, the replay uses the fault
  model where a truck takes a load while it holds one.
  """
  def replay(haul, logs, dir, opts \\ []) do
    events = [haul | logs] |> Enum.flat_map(&World.Log.events/1) |> Enum.sort_by(& &1.wall)
    asks = for %{kind: "haul_asked", data: d} <- events, do: d
    tasks = MapSet.new(asks, & &1["for"])
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "Run.tla"), module(events, asks))
    File.write!(Path.join(dir, "Run.cfg"), config(Keyword.get(opts, :guard, true)))
    {:ok, m} = Machine.load(Path.join(dir, "Run.tla"), paths: [@specs])
    {:ok, init} = Machine.init_states(m)

    events
    |> Enum.reduce_while({:ok, init}, fn e, {:ok, states} ->
      case action(e, tasks) do
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

  defp action(%{kind: "haul_asked", data: d}, _), do: {"Ask", [d["for"]]}
  defp action(%{kind: "loaded", data: d}, _), do: {"Take", [d["truck"], d["load"]]}
  defp action(%{kind: "unloaded", data: d}, _), do: {"Drop", [d["truck"], d["load"]]}
  defp action(%{kind: "hauled", data: d}, _), do: {"Tell", [d["for"]]}

  defp action(%{kind: "task_started", order: b, data: %{"task" => t}}, tasks) do
    if MapSet.member?(tasks, b <> "|" <> t), do: {"Start", [b <> "|" <> t]}
  end

  defp action(_, _), do: nil

  defp module(events, asks) do
    loads = for d <- asks, l <- d["loads"], do: {l["id"], d["for"], round(l["mass"])}
    trucks = for %{kind: k, data: %{"truck" => t}} <- events, k in ~w(loaded truck_joined), uniq: true, do: t
    cap = Enum.max([1 | for({_, _, m} <- loads, do: m)])

    """
    ---- MODULE Run ----
    EXTENDS Haul, TLC
    RunTasks == #{set(Enum.uniq(for d <- asks, do: d["for"]))}
    RunLoads == #{set(for {l, _, _} <- loads, do: l)}
    RunOf == #{fun(Map.new(loads, fn {l, t, _} -> {l, t} end), &str/1)}
    RunMass == #{fun(Map.new(loads, fn {l, _, m} -> {l, m} end), &Integer.to_string/1)}
    RunTrucks == #{set(trucks)}
    RunCap == #{max(cap, round(World.Places.trucks()["load_kg"]))}
    ====
    """
  end

  defp config(guard) do
    """
    SPECIFICATION Spec
    CONSTANTS
        Tasks <- RunTasks
        Loads <- RunLoads
        Of <- RunOf
        Mass <- RunMass
        Trucks <- RunTrucks
        Cap <- RunCap
        Guard = #{if guard, do: "TRUE", else: "FALSE"}
        Count = TRUE
    INVARIANT InLoad OnePlace PartsFirst
    """
  end

  defp str(s), do: ~s("#{s}")
  defp set(names), do: "{" <> Enum.map_join(Enum.sort(names), ", ", &str/1) <> "}"

  defp fun(map, _value) when map == %{}, do: "[x \\in {} |-> 0]"
  defp fun(map, value), do: map |> Enum.sort() |> Enum.map_join(" @@ ", fn {k, v} -> "(#{str(k)} :> #{value.(v)})" end)
end
