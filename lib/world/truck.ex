defmodule World.Truck do
  @moduledoc """
  A truck of the yard with its driver (plan 0002, D6): a process with its
  name, its place and its haul (`World.Haul`). The haul gives it one load
  at a time: the truck drives to the source of the load (the warehouse, or
  the gate of a supplier), takes the load (`{:loaded, name, id}` to the
  haul), drives to the place of the load, and puts it down there
  (`{:unloaded, name, id}`). A drive takes its world time
  (`World.Places.drive/2`) over the scale of the clock (`World.Clock`).
  """
  use GenServer, restart: :temporary
  alias World.{Clock, Places}

  @doc "Start a truck: the options `name`, `at` (its place), `haul` (a pid) and `clock`."
  def start_link(opts), do: GenServer.start_link(__MODULE__, Map.new(opts))

  @doc "Carry the load `id` from the place `from` to the place `to`."
  def carry(truck, id, from, to), do: GenServer.cast(truck, {:carry, id, from, to})

  @impl true
  def init(opts) do
    Process.set_label({:truck, opts.name})
    {:ok, opts}
  end

  @impl true
  def handle_cast({:carry, id, from, to}, s) do
    Process.send_after(self(), {:source, id, from, to}, wait(s, s.at, from))
    {:noreply, s}
  end

  @impl true
  def handle_info({:source, id, from, to}, s) do
    send(s.haul, {:loaded, s.name, id})
    Process.send_after(self(), {:place, id, to}, wait(s, from, to))
    {:noreply, %{s | at: from}}
  end

  def handle_info({:place, id, to}, s) do
    send(s.haul, {:unloaded, s.name, id})
    {:noreply, %{s | at: to}}
  end

  # The wall time of the drive between two places.
  defp wait(_s, a, a), do: 0
  defp wait(s, a, b), do: Clock.to_wall(s.clock, Places.drive(a, b))
end
