defmodule World.Sculpt.Live do
  @moduledoc """
  A live sculpture (`docs/plans/0008-model-from-edits.md`, D11, R8): a
  process that keeps the edits of a sculpture and the pieces of the
  surface of its bricks, and takes a change of one edit at a time.

  An edit comes as a message of priority (`edit/3`), so it goes before
  the pieces in the mailbox. Each change starts a work: a process with
  the tree of the bricks (`World.Sculpt.bricks/3`, with the cache of the
  node), so only the bricks that the change reaches are made again; the
  others come from the cache. Each brick that is made sends its piece as
  soon as it is made, and the sculpture sends each new piece to each
  watcher (`watch/1`); a brick of the cache with a new key comes at the
  end of the work. A change while a work is in progress stops that work and
  its tree at once (an exit signal), and starts a new work from the
  newest edits: the newest edit wins.

  The events to a watcher, `{:sculpture, name, event}`:

  - `{:piece, at, piece}`: the new piece of the brick `at`;
  - `{:gone, at}`: the brick `at` has no surface now;
  - `{:done, version}`: the pieces are those of the edits of the version;
  - `{:failed, version, reason}`: the work of the version stopped.
  """

  use GenServer, restart: :temporary

  alias World.Sculpt
  alias World.Sculpt.Surface

  @doc """
  Start a live sculpture of the name `name` (any term) with its edits,
  under the supervisor of the sculptures. The options: `step` (the size
  of the cells, m), or `level` (`:near` by default).
  """
  def start(name, edits, opts \\ []),
    do: DynamicSupervisor.start_child(World.Sculptures, {__MODULE__, {name, edits, opts}})

  @doc false
  def start_link({name, edits, opts}), do: GenServer.start_link(__MODULE__, {name, edits, opts})

  @doc """
  Change the edit `i` (from 0) to `edit`: a new edit at the end when `i`
  is the count of the edits, and no edit (the edits after it go one
  place down) when `edit` is nil. A message of priority. Gives `{:ok,
  version}` (the version of the change), or `{:error, :index}` or
  `{:error, :none}`.
  """
  def edit(name, i, edit), do: call(name, {:edit, i, edit})

  @doc "The edits, the version, the size of the cells and the count of the bricks of a live sculpture, or `{:error, :none}`."
  def info(name), do: call(name, :info)

  @doc """
  The pieces of the surface of a live sculpture, each with its brick:
  `[{at, piece}]`, in the order of the bricks; or `{:error, :none}`.
  """
  def pieces(name), do: call(name, :pieces)

  @doc """
  The meshes of the surface of a live sculpture (`World.Sculpt.Surface.meshes/2`,
  with its options; with no piece less than two cells across, as
  `World.Sculpt.model/2`), from the pieces that it has; or `{:error, :none}`.
  """
  def meshes(name, opts \\ []) do
    with %{step: step} <- info(name),
         pieces when is_list(pieces) <- pieces(name) do
      Surface.meshes(Enum.map(pieces, &elem(&1, 1)), Keyword.put_new(opts, :small, 2 * step))
    end
  end

  @doc "Send each event of a live sculpture to the process that calls."
  def watch(name) do
    {:ok, _} = Registry.register(World.Events, {:sculpture, name}, nil)
    :ok
  end

  @doc "Stop a live sculpture and its work: `:ok`, or `{:error, :none}`."
  def stop(name) do
    with [{pid, _}] <- Registry.lookup(World.Names, {:sculpture, name}),
         :ok <- DynamicSupervisor.terminate_child(World.Sculptures, pid) do
      :ok
    else
      _ -> {:error, :none}
    end
  end

  # A call by the alias of priority of the sculpture.
  defp call(name, message) do
    case Registry.lookup(World.Names, {:sculpture, name}) do
      [{pid, alias}] ->
        ref = Process.monitor(pid)
        :erlang.send(alias, {:"$gen_call", {self(), ref}, message}, [:priority])

        receive do
          {^ref, reply} ->
            Process.demonitor(ref, [:flush])
            reply

          {:DOWN, ^ref, _, _, _} ->
            {:error, :none}
        end

      [] ->
        {:error, :none}
    end
  end

  @impl true
  def init({name, edits, opts}) do
    {:ok, _} = Registry.register(World.Names, {:sculpture, name}, :erlang.alias([:priority]))
    Process.set_label({:sculpture, name})
    step = opts[:step] || Sculpt.step(Keyword.get(opts, :level, :near))
    {:ok, work(%{name: name, edits: edits, step: step, version: 0, bricks: %{}, work: nil})}
  end

  @impl true
  def handle_call({:edit, i, edit}, _from, s) do
    n = length(s.edits)

    edits =
      cond do
        not is_integer(i) or i < 0 or i > n or (i == n and edit == nil) -> nil
        edit == nil -> List.delete_at(s.edits, i)
        i == n -> s.edits ++ [edit]
        true -> List.replace_at(s.edits, i, edit)
      end

    if edits do
      s = %{halt(s) | edits: edits, version: s.version + 1}
      {:reply, {:ok, s.version}, work(s)}
    else
      {:reply, {:error, :index}, s}
    end
  end

  def handle_call(:info, _from, s),
    do:
      {:reply, %{edits: s.edits, version: s.version, step: s.step, bricks: map_size(s.bricks), busy: s.work != nil}, s}

  def handle_call(:pieces, _from, s),
    do: {:reply, s.bricks |> Enum.sort() |> Enum.map(fn {at, {_, piece}} -> {at, piece} end), s}

  @impl true
  def handle_info({:piece, v, at, key, piece}, %{version: v} = s), do: {:noreply, put(s, at, key, piece)}

  # The pieces of a work, all of them: each brick that did not come before,
  # and the bricks that have no surface now.
  def handle_info({:built, v, keys, pieces}, %{version: v, work: {_, ref, _}} = s) do
    Process.demonitor(ref, [:flush])
    s = Enum.reduce(pieces, s, fn {at, {key, piece}}, s -> put(s, at, key, piece) end)

    gone = for at <- Map.keys(s.bricks), not Map.has_key?(keys, at), do: at
    for at <- gone, do: notify(s, {:gone, at})
    notify(s, {:done, v})
    {:noreply, %{s | bricks: Map.drop(s.bricks, gone), work: nil}}
  end

  def handle_info({:DOWN, ref, :process, _, reason}, %{work: {_, ref, v}} = s) do
    notify(s, {:failed, v, reason})
    {:noreply, %{s | work: nil}}
  end

  # A piece of a work that a newer edit stopped.
  def handle_info(_message, s), do: {:noreply, s}

  defp put(s, at, key, piece) do
    case s.bricks[at] do
      {^key, _} ->
        s

      _ ->
        notify(s, {:piece, at, piece})
        %{s | bricks: Map.put(s.bricks, at, {key, piece})}
    end
  end

  defp notify(s, event) do
    Registry.dispatch(World.Events, {:sculpture, s.name}, fn watchers ->
      for {pid, _} <- watchers, do: send(pid, {:sculpture, s.name, event})
    end)
  end

  # A work of the edits of the version: the tree of the bricks, with the
  # cache; each brick with a new key sends its piece when it is made.
  defp work(%{edits: edits, step: step, version: v} = s) do
    live = self()
    known = Map.new(s.bricks, fn {at, {key, _}} -> {at, key} end)
    sink = fn b -> send(live, {:piece, v, b.at, b.key, b.piece}) end

    {pid, ref} =
      spawn_monitor(fn ->
        Process.set_label({:sculpture_work, s.name, v})
        %{bricks: bricks} = Sculpt.bricks(edits, step, each: &Surface.piece(&1, step), cache: :keys, sink: sink)
        keys = Map.new(bricks, &{&1.at, &1.key})

        pieces =
          for b <- bricks, known[b.at] != b.key, into: %{} do
            {b.at, {b.key, Sculpt.piece(b, step)}}
          end

        send(live, {:built, v, keys, pieces})
      end)

    %{s | work: {pid, ref, v}}
  end

  # The work of the last edit stops, with its tree.
  defp halt(%{work: nil} = s), do: s

  defp halt(%{work: {pid, ref, _}} = s) do
    Process.demonitor(ref, [:flush])
    Process.exit(pid, :kill)
    %{s | work: nil}
  end
end
