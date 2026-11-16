defmodule World.PlacesSpec do
  @moduledoc """
  The replay of the log of the yard (`World.Yard`), with the logs of the
  constructions that it starts, as a behavior of `specs/Places.tla`: the
  places of the yard, the buildings that it raises and the constructions
  that it holds or starts are the constants of a module `Run.tla`; each
  event is one action, in the order of the wall clock (the yard first at
  one time), and the invariants hold after each step.
  """
  alias Accord.TLA.Checker.Machine

  @specs Path.expand("../../specs", __DIR__)

  @doc """
  Replay the log of the yard and the logs of constructions in `dir`:
  `:ok` or `{:error, reason}`. With `guard: false`, the replay uses the
  fault model where a construction does not wait for its place.
  """
  def replay(yard, logs, dir, opts \\ []) do
    events = [yard | logs] |> Enum.flat_map(&World.Log.events/1) |> Enum.sort_by(& &1.wall)
    at = for %{kind: k, data: d} <- events, k in ~w(place_held place_started), into: %{}, do: {d["order"], d["place"]}
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "Run.tla"), module(events, at))
    File.write!(Path.join(dir, "Run.cfg"), config(Keyword.get(opts, :guard, true)))
    {:ok, m} = Machine.load(Path.join(dir, "Run.tla"), paths: [@specs])
    {:ok, init} = Machine.init_states(m)

    events
    |> Enum.reduce_while({:ok, init}, fn e, {:ok, states} ->
      case action(e, at) do
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

  defp action(%{kind: "place_raised", data: d}, _), do: {"Raise", [d["place"]]}
  defp action(%{kind: "place_open", data: d}, _), do: {"Open", [d["place"]]}
  defp action(%{kind: "place_held", data: d}, _), do: {"Hold", [d["order"]]}
  defp action(%{kind: "place_started", data: d}, _), do: {"Start", [d["order"]]}
  defp action(%{kind: "done", order: c}, at) when is_map_key(at, c), do: {"Done", [c]}
  defp action(_, _), do: nil

  defp module(events, at) do
    places = for p <- World.Places.all(), do: p["name"]
    built = for p <- World.Places.buildings(), do: p["name"]
    raised = for %{kind: "place_raised", data: d} <- events, uniq: true, do: d["place"]

    """
    ---- MODULE Run ----
    EXTENDS Places, TLC
    RunPlaces == #{set(places)}
    RunBuilt == #{set(built)}
    RunPlan == #{set(raised)}
    RunBuilds == #{set(Map.keys(at))}
    RunAt == #{fun(at)}
    ====
    """
  end

  defp config(guard) do
    """
    SPECIFICATION Spec
    CONSTANTS
        Places <- RunPlaces
        Built <- RunBuilt
        Plan <- RunPlan
        Builds <- RunBuilds
        At <- RunAt
        Guard = #{if guard, do: "TRUE", else: "FALSE"}
    INVARIANT AtOpen
    """
  end

  defp str(s), do: ~s("#{s}")
  defp set(names), do: "{" <> Enum.map_join(Enum.sort(names), ", ", &str/1) <> "}"
  defp fun(map) when map == %{}, do: "[x \\in {} |-> 0]"
  defp fun(map), do: map |> Enum.sort() |> Enum.map_join(" @@ ", fn {k, v} -> "(#{str(k)} :> #{str(v)})" end)
end
