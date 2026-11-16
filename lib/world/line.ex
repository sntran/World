defmodule World.Line do
  @moduledoc """
  The line of the builds of a request
  (`docs/plans/0019-world-serves-the-projects.md`, 4.3). Some builds
  work at one time (the application environment `:builds`, from
  `WORLD_BUILDS`; 1 by default: the edge has 128 MB), and the others
  wait in two classes: a build of the class `:now` (a person waits for
  it) goes before each build of the class `:batch` (the files of a
  release of a project). In a class, the first to come is the first to
  go.
  """
  use GenServer

  @doc "Start the line. The option `slots` is the count of builds at one time."
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc """
  Run `fun` when the line has room for it, in the process of the call,
  and give its result. `class` is `:now` or `:batch`.
  """
  def run(class \\ :now, fun, line \\ __MODULE__) when class in [:now, :batch] do
    ref = make_ref()
    :ok = GenServer.call(line, {:enter, class, ref}, :infinity)

    try do
      fun.()
    after
      GenServer.cast(line, {:leave, ref})
    end
  end

  @doc "The state of the line: `%{slots, working, now, batch}` (counts)."
  def state(line \\ __MODULE__), do: GenServer.call(line, :state)

  @impl true
  def init(opts) do
    slots = Keyword.get(opts, :slots, Application.get_env(:world, :builds, 1))
    {:ok, %{slots: slots, working: %{}, now: :queue.new(), batch: :queue.new()}}
  end

  @impl true
  def handle_call({:enter, class, ref}, {pid, _} = from, s) do
    # (A build that stops with no word leaves the line too.)
    monitor = Process.monitor(pid)
    {:noreply, next(Map.update!(s, class, &:queue.in({from, ref, monitor}, &1)))}
  end

  def handle_call(:state, _from, s) do
    {:reply, %{slots: s.slots, working: map_size(s.working), now: :queue.len(s.now), batch: :queue.len(s.batch)}, s}
  end

  @impl true
  def handle_cast({:leave, ref}, s), do: {:noreply, leave(s, ref)}

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, s) do
    # A build in work that stopped, or a build that stopped in the line.
    case Enum.find(s.working, fn {_, m} -> m == monitor end) do
      {ref, _} -> {:noreply, leave(s, ref)}
      nil -> {:noreply, %{s | now: drop(s.now, monitor), batch: drop(s.batch, monitor)}}
    end
  end

  defp leave(s, ref) do
    {monitor, working} = Map.pop!(s.working, ref)
    Process.demonitor(monitor, [:flush])
    next(%{s | working: working})
  end

  defp drop(queue, monitor), do: :queue.filter(fn {_, _, m} -> m != monitor end, queue)

  # Give each free place to the next build of the line: the class `:now` first.
  defp next(%{slots: slots, working: working} = s) when map_size(working) >= slots, do: s

  defp next(s) do
    case {:queue.out(s.now), :queue.out(s.batch)} do
      {{{:value, item}, rest}, _} -> start(%{s | now: rest}, item)
      {_, {{:value, item}, rest}} -> start(%{s | batch: rest}, item)
      _ -> s
    end
  end

  defp start(s, {from, ref, monitor}) do
    GenServer.reply(from, :ok)
    next(%{s | working: Map.put(s.working, ref, monitor)})
  end
end
