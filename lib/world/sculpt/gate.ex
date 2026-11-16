defmodule World.Sculpt.Gate do
  @moduledoc """
  The gate of the sculptures of the node
  (`docs/plans/0011-any-model.md`, D7): how many builds of sculptures
  work at one time.

  The build of one sculpture gives its work to each scheduler. So many
  builds at one time do not make the node faster: each waits for the
  others, and all of them have their memory at the same time (the
  measure of the plan: 8 models at one time take 25.0 s and 1.1 GB, 2 at
  a time take 23.1 s and 0.7 GB, 1 at a time takes 27.6 s). The gate
  lets some builds in, and the others wait in their order.

  The options (`config :world, World.Sculpt.Gate, ...`, or the options
  of `start_link/1`):

  - `room`: the builds at one time. By default half of the schedulers,
    and 1 at least.
  - `memory_mb`: a build waits also while the VM has more memory than
    this (`World.memory/0`), until a build goes out. With no build in
    work, a build goes in: the gate does not stop the node. By default
    no limit.

  A build that stops (its process ends) goes out of the gate.
  """
  use GenServer

  @doc false
  def start_link(opts) do
    opts = Keyword.merge(Application.get_env(:world, __MODULE__, []), opts)
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Do `fun` in the gate: wait for room, do it, and go out (also when it
  raises). With no gate (the node does not run), do it now.
  """
  def with(fun, gate \\ __MODULE__) do
    case GenServer.whereis(gate) do
      nil ->
        fun.()

      pid ->
        :ok = GenServer.call(pid, :enter, :infinity)

        try do
          fun.()
        after
          # (The heap of this process has the waste of the build: it goes
          # back to the node before the next build comes in.)
          :erlang.garbage_collect()
          GenServer.cast(pid, {:leave, self()})
        end
    end
  end

  @doc "The builds in work and the builds that wait: `%{in: count, waiting: count, room: count}`."
  def state(gate \\ __MODULE__), do: GenServer.call(gate, :state)

  @impl true
  def init(opts) do
    {:ok,
     %{
       room: Keyword.get(opts, :room, max(div(System.schedulers_online(), 2), 1)),
       limit: Keyword.get(opts, :memory_mb),
       memory: Keyword.get(opts, :memory, &World.memory/0),
       # The builds in work and the builds that wait: each with the monitor of its process.
       in: %{},
       waiting: []
     }}
  end

  @impl true
  def handle_call(:enter, {pid, _} = from, s),
    do: {:noreply, admit(%{s | waiting: s.waiting ++ [{pid, Process.monitor(pid), from}]})}

  def handle_call(:state, _from, s),
    do: {:reply, %{in: map_size(s.in), waiting: length(s.waiting), room: s.room}, s}

  @impl true
  def handle_cast({:leave, pid}, s), do: {:noreply, admit(out(s, pid))}

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _}, s), do: {:noreply, admit(out(s, pid))}

  # A process goes out: of the builds in work, or of the builds that wait.
  defp out(s, pid) do
    case Map.pop(s.in, pid) do
      {nil, _} ->
        %{s | waiting: Enum.reject(s.waiting, &(elem(&1, 0) == pid))}

      {ref, rest} ->
        Process.demonitor(ref, [:flush])
        %{s | in: rest}
    end
  end

  # The first builds that wait go in, while the gate has room.
  defp admit(%{waiting: [{pid, ref, from} | rest]} = s) do
    if room?(s) do
      GenServer.reply(from, :ok)
      admit(%{s | in: Map.put(s.in, pid, ref), waiting: rest})
    else
      s
    end
  end

  defp admit(s), do: s

  defp room?(%{in: builds}) when map_size(builds) == 0, do: true
  defp room?(%{in: builds, room: room}) when map_size(builds) >= room, do: false
  defp room?(%{limit: nil}), do: true
  defp room?(s), do: elem(s.memory.(), 1) <= s.limit * 1_048_576
end
