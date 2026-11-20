defmodule World.Labour.Restore do
  @moduledoc """
  The parts of the store of the queue (`World.Labour.Store`) back in the
  queue after a start of the VM (`World.Labour.restore/1`): at the start,
  and each 10 seconds. The runtime of the edge starts a new VM from a
  memory image of the first VM of its deploy, so a look at the start only
  is not enough (as `World.Shift.Passes`). A part that has its process
  now is not touched.
  """
  use GenServer

  @look 10_000

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @impl true
  def init(opts) do
    send(self(), :look)
    {:ok, %{look: Keyword.get(opts, :look, @look), labour: Keyword.get(opts, :labour, [])}}
  end

  @impl true
  def handle_info(:look, s) do
    _ = World.Labour.restore(s.labour)
    Process.send_after(self(), :look, s.look)
    {:noreply, s}
  end
end
