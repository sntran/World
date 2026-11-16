defmodule World.Haul do
  @moduledoc """
  The haul of the yard (plan 0002, D6 and D8; `specs/Haul.tla`): the
  materials of the tasks, from the warehouse or the gate of a supplier to
  the place of their construction, by truck.

  A construction asks for the takeoff of a task (`ask/5`). When the
  warehouse is open (`open/1`) and has the materials, they come from its
  stock; else a supplier brings them from the gate. The takeoff goes into
  the loads of a truck (`World.Stock.loads/3`), each at most the load of
  a truck. Each load goes to a free truck of the yard (`join/3`): the
  truck drives to the source, takes the load, drives to the place, and
  puts it down (`World.Truck`). While the yard has no truck of its own,
  the haul rents a truck of a supplier with its driver for each load; it
  goes back after the load. When each load of the task is at its place,
  the haul tells the construction (`{:hauled, ref}`).

  The log of the haul (the order `haul`): `haul_asked` (the task, its
  place, its source and its loads), `loaded` and `unloaded` (a truck and
  a load), `hauled`, and `truck_joined`. It replays in `specs/Haul.tla`.
  """
  use GenServer
  alias World.{Clock, Log, Places, Stock, Truck}

  @doc """
  Start the haul. The options: `name` (`World.Haul` by default), `clock`,
  `stock` (`World.Stock.new/0` by default) and `load_kg` (the load of a
  truck, from `priv/places.json` by default).
  """
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc """
  Ask for the takeoff `wants` of the task `task` (a text: the id of the
  construction and of the task) at the place `to`. The haul sends
  `{:hauled, ref}` to the caller when each load is at its place.
  """
  def ask(haul \\ __MODULE__, ref, task, to, wants), do: GenServer.cast(haul, {:ask, self(), ref, task, to, wants})

  @doc "A truck of the yard (a van that the people made) joins the haul at the place `at`."
  def join(haul \\ __MODULE__, name, at), do: GenServer.call(haul, {:join, name, at})

  @doc "The warehouse is open: the materials come from its stock."
  def open(haul \\ __MODULE__), do: GenServer.call(haul, :open)

  @doc "The log of the haul, and its stock."
  def log(haul \\ __MODULE__), do: GenServer.call(haul, :log)
  def stock(haul \\ __MODULE__), do: GenServer.call(haul, :stock)

  @impl true
  def init(opts) do
    clock = Keyword.get_lazy(opts, :clock, &Clock.world/0)

    {:ok,
     %{
       clock: clock,
       log: Log.new(clock),
       stock: Keyword.get_lazy(opts, :stock, &Stock.new/0),
       load_kg: Keyword.get_lazy(opts, :load_kg, fn -> Places.trucks()["load_kg"] end),
       open: false,
       # A truck by its name: its pid, its load (or nil), and whether it is rented.
       trucks: %{},
       rented: 0,
       queue: [],
       loads: %{},
       asks: %{},
       next: 1
     }}
  end

  @impl true
  def handle_call({:join, name, at}, _from, s) do
    {:ok, pid} = Truck.start_link(name: name, at: at, haul: self(), clock: s.clock)
    s = %{s | trucks: Map.put(s.trucks, name, %{pid: pid, load: nil, rented: false})}
    {:reply, :ok, s |> record("truck_joined", %{"truck" => name, "at" => at}) |> dispatch()}
  end

  def handle_call(:open, _from, s), do: {:reply, :ok, %{s | open: true}}
  def handle_call(:log, _from, s), do: {:reply, s.log, s}
  def handle_call(:stock, _from, s), do: {:reply, s.stock, s}

  @impl true
  def handle_cast({:ask, pid, ref, task, to, wants}, s) do
    {from, stock} =
      case s.open && Stock.take(s.stock, wants) do
        {:ok, stock} -> {"warehouse", stock}
        _ -> {"gate", s.stock}
      end

    loads = Stock.loads(s.stock, wants, s.load_kg)
    ids = for i <- 0..(length(loads) - 1)//1, do: "L#{s.next + i}"

    data =
      for {id, load} <- Enum.zip(ids, loads),
          do: %{"id" => id, "items" => load, "mass" => Stock.mass(s.stock, load)}

    s = %{
      s
      | stock: stock,
        next: s.next + length(ids),
        queue: s.queue ++ ids,
        loads: Enum.reduce(ids, s.loads, &Map.put(&2, &1, %{task: task, from: from, to: to})),
        asks: Map.put(s.asks, task, %{pid: pid, ref: ref, left: MapSet.new(ids)})
    }

    s = record(s, "haul_asked", %{"for" => task, "to" => to, "from" => from, "loads" => data})
    {:noreply, s |> hauled(task) |> dispatch()}
  end

  @impl true
  def handle_info({:loaded, name, id}, s),
    do: {:noreply, record(s, "loaded", %{"truck" => name, "load" => id, "at" => s.loads[id].from})}

  def handle_info({:unloaded, name, id}, s) do
    %{task: task, to: to} = s.loads[id]
    s = record(s, "unloaded", %{"truck" => name, "load" => id, "at" => to})

    trucks =
      case s.trucks[name] do
        %{rented: true, pid: pid} ->
          # The rented truck goes back to its supplier.
          GenServer.stop(pid)
          Map.delete(s.trucks, name)

        truck ->
          Map.put(s.trucks, name, %{truck | load: nil})
      end

    asks = Map.update!(s.asks, task, &%{&1 | left: MapSet.delete(&1.left, id)})
    {:noreply, %{s | trucks: trucks, asks: asks, loads: Map.delete(s.loads, id)} |> hauled(task) |> dispatch()}
  end

  # Each load of the task is at its place: the haul tells its construction.
  defp hauled(s, task) do
    %{left: left, pid: pid, ref: ref} = s.asks[task]

    if MapSet.size(left) == 0 do
      send(pid, {:hauled, ref})
      record(%{s | asks: Map.delete(s.asks, task)}, "hauled", %{"for" => task})
    else
      s
    end
  end

  # Each load in the queue goes to a free truck of the yard; with no truck
  # of the yard, to a truck that the haul rents at the gate.
  defp dispatch(%{queue: []} = s), do: s

  defp dispatch(%{queue: [id | rest]} = s) do
    own = for {name, %{load: nil, rented: false}} <- Enum.sort(s.trucks), do: name

    cond do
      own != [] ->
        s |> give(hd(own), id, rest) |> dispatch()

      Enum.any?(s.trucks, fn {_, t} -> not t.rented end) ->
        s

      true ->
        name = "rented_#{s.rented + 1}"
        {:ok, pid} = Truck.start_link(name: name, at: "gate", haul: self(), clock: s.clock)
        s = %{s | rented: s.rented + 1, trucks: Map.put(s.trucks, name, %{pid: pid, load: nil, rented: true})}
        s |> give(name, id, rest) |> dispatch()
    end
  end

  defp give(s, name, id, rest) do
    %{from: from, to: to} = s.loads[id]
    Truck.carry(s.trucks[name].pid, id, from, to)
    %{s | queue: rest, trucks: Map.update!(s.trucks, name, &%{&1 | load: id})}
  end

  defp record(s, kind, data) do
    last = List.first(s.log.events)
    wall = max(Clock.wall(), if(last, do: last.wall, else: 0))
    {:ok, log} = Log.add(s.log, kind, wall: wall, order: "haul", data: data)
    World.Log.Server.publish(hd(log.events))
    %{s | log: log}
  end
end
