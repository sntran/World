defmodule World.Yard do
  @moduledoc """
  The yard of the node (plan 0002, D6 and D7; `specs/Places.tla`): the
  first start builds the places, then the models go to their places.

  1. The places with a building (the warehouse, the factories) are closed
     at the start; the gate and the site are open. The yard raises each
     building (`place_raised`): an order of a house that the people build
     on its lot, with its materials from the gate (`World.Haul`).
  2. When the building of a place is done, the place opens
     (`place_open`). When the warehouse opens, the haul takes the
     materials from its stock.
  3. When the factory of the vehicles opens, the people build the trucks
     there (each an order of a van); each truck joins the haul
     (`truck_made`), and the haul rents no more trucks.
  4. A construction of a model in data goes to the place of its kind
     (`World.Places.for_kind/1`): the yard starts it when the place is
     open (`place_started`), and holds it until then (`place_held`).

  A later start gives the places that are open (`open`): the yard raises
  only the others. `World.build/1` asks the yard when it runs.
  """
  use GenServer
  alias World.{Clock, Haul, Log, Orders, Places}

  @doc """
  Start the yard. The options: `name` (`World.Yard` by default), `haul`
  (`World.Haul` by default), `level` (of the buildings and the trucks,
  `"mid"` by default) and `open` (the places with a building that are
  open already).
  """
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc """
  The job at its place, for `World.build/1`: `{:start, job}` with its
  `place` and its `haul` when the place is open, `{:held, id}` when the
  yard holds it, or `{:start, job}` as it is (no yard, a job with a place,
  or a job with no drawing or no place for its kind).
  """
  def place(job, yard \\ __MODULE__) do
    kind = job[:drawing] && Map.get(job.drawing, "kind", "item")

    cond do
      Map.has_key?(job, :place) or kind == nil or Places.for_kind(kind) == nil -> {:start, job}
      GenServer.whereis(yard) == nil -> {:start, job}
      true -> GenServer.call(yard, {:place, job, Places.for_kind(kind)})
    end
  end

  @doc "The places that are open, the trucks of the yard, and the log of the yard."
  def state(yard \\ __MODULE__), do: GenServer.call(yard, :state)

  @impl true
  def init(opts) do
    clock = Clock.new()

    s = %{
      clock: clock,
      log: Log.new(clock),
      haul: Keyword.get(opts, :haul, World.Haul),
      level: Keyword.get(opts, :level, "mid"),
      open:
        MapSet.new(
          for(p <- Places.all(), not Map.has_key?(p, "building"), do: p["name"]) ++ Keyword.get(opts, :open, [])
        ),
      # The constructions of the yard by their ids: a building or a truck.
      own: %{},
      held: [],
      trucks: []
    }

    {:ok, s, {:continue, :raise}}
  end

  @impl true
  def handle_continue(:raise, s) do
    s = Enum.reduce(Places.buildings(), s, fn p, s -> if open?(s, p["name"]), do: s, else: raise_place(s, p) end)
    {:noreply, s |> opened("warehouse") |> trucks()}
  end

  @impl true
  def handle_call({:place, job, place}, {pid, _}, s) do
    job = job |> Map.merge(%{place: place, haul: s.haul, reply: Map.get(job, :reply, pid)}) |> lot()
    at = %{"order" => job.id, "place" => place} |> put_lot(job)

    if open?(s, place) do
      {:reply, {:start, job}, record(s, "place_started", at)}
    else
      s = record(%{s | held: s.held ++ [job]}, "place_held", at)
      {:reply, {:held, job.id}, s}
    end
  end

  def handle_call(:state, _from, s), do: {:reply, %{open: Enum.sort(s.open), trucks: s.trucks, log: s.log}, s}

  @impl true
  def handle_info({:built, id, _result}, s) do
    case Map.pop(s.own, id) do
      {{:building, place}, own} ->
        s = record(%{s | open: MapSet.put(s.open, place), own: own}, "place_open", %{"place" => place})
        {:noreply, s |> opened(place) |> trucks() |> release(place)}

      {{:truck, name}, own} ->
        :ok = Haul.join(s.haul, name, "vehicles")
        {:noreply, record(%{s | own: own, trucks: s.trucks ++ [name]}, "truck_made", %{"truck" => name, "order" => id})}
    end
  end

  # A construction of the yard that fails or stops: the yard raises it again.
  def handle_info({result, id, _}, s) when result in [:failed, :stopped] do
    case Map.pop(s.own, id) do
      {{:building, place}, own} -> {:noreply, raise_place(%{s | own: own}, elem(Places.fetch(place), 1))}
      {{:truck, name}, own} -> {:noreply, truck(%{s | own: own}, name)}
    end
  end

  defp open?(s, place), do: MapSet.member?(s.open, place)

  # A job at a place with a terrain goes to its first lot (plan 0006, D4),
  # and its model has its place in the game (D5).
  defp lot(job) do
    {:ok, p} = Places.fetch(job.place)

    case Places.lots(p) do
      [] -> job
      [l | _] -> Map.merge(job, %{lot: l["name"], geo: Places.geo(p, l["name"])})
    end
  end

  defp put_lot(data, %{lot: lot}), do: Map.put(data, "lot", lot)
  defp put_lot(data, _job), do: data

  # The building of a place: a house that the people build on its lot.
  defp raise_place(s, p) do
    {:ok, job} = Orders.job(p["building"], s.level)
    {:ok, id} = World.build(Map.merge(job, %{place: p["name"], haul: s.haul, reply: self()}))

    record(%{s | own: Map.put(s.own, id, {:building, p["name"]})}, "place_raised", %{
      "place" => p["name"],
      "order" => id
    })
  end

  defp opened(s, "warehouse") do
    if open?(s, "warehouse"), do: :ok = Haul.open(s.haul)
    s
  end

  defp opened(s, _place), do: s

  # The trucks of the yard, once, when the factory of the vehicles is open.
  defp trucks(s) do
    making = for {_, {:truck, n}} <- s.own, do: n

    if open?(s, "vehicles") and s.trucks == [] and making == [] do
      Enum.reduce(1..Places.trucks()["count"], s, &truck(&2, "truck_#{&1}"))
    else
      s
    end
  end

  defp truck(s, name) do
    order = put_in(Places.trucks()["order"], ["options", "name"], name)
    {:ok, job} = Orders.job(order, s.level)
    {:ok, id} = World.build(Map.merge(job, %{place: "vehicles", haul: s.haul, reply: self()}))
    s = record(%{s | own: Map.put(s.own, id, {:truck, name})}, "place_started", %{"order" => id, "place" => "vehicles"})
    s
  end

  # The constructions that the yard holds for a place that opens now.
  defp release(s, place) do
    {go, held} = Enum.split_with(s.held, &(&1.place == place))

    Enum.reduce(go, %{s | held: held}, fn job, s ->
      {:ok, _} = World.build(job)
      record(s, "place_started", %{"order" => job.id, "place" => place})
    end)
  end

  defp record(s, kind, data) do
    last = List.first(s.log.events)
    wall = max(Clock.wall(), if(last, do: last.wall, else: 0))
    {:ok, log} = Log.add(s.log, kind, wall: wall, order: "yard", data: data)
    World.Log.Server.publish(hd(log.events))
    %{s | log: log}
  end
end
