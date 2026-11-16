defmodule World.Log.Server do
  @moduledoc """
  The log of the node (`docs/plans/0001-people-build-on-demand.md`, D18):
  each event of each construction, in the order that it comes, with an id
  that grows by one (the id of the event in the stream, for
  `Last-Event-ID`). It sends each event to the watchers of its
  construction and of the world (`World.Events`): `{:world, event}`,
  with the event as data (`World.Log.data/1` and its `"id"`).

  It keeps the last #{2_000} events in its memory (a table, ETS, ordered by
  id: a publish adds one event and takes away the oldest one, so it takes
  the same work with 10 events in the log or 10,000; plan 0007, D7, R7),
  and each event in the
  store of the log when the node has one (`World.Log.Store`), in
  batches: so a watcher that comes later gets the events of the past
  (`history/2`). A stop of the VM loses the events of the batch (fewer
  than #{50}), so a new log leaves #{50} ids after the last id of the
  store, and puts its first id into the store at once (the event
  `started`): an id never names two events (`specs/LogStore.tla`).
  """
  use GenServer

  alias World.Log
  alias World.Log.Store

  @keep 2_000
  @batch 50
  @every 200
  @read 10_000

  @doc """
  Start the log of the node. The options: `name` (`World.Log.Server` by
  default) and `store` (keep the events in the store of the log;
  `World.Log.Store.on?/0` by default).
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "An event of a construction (a `World.Log.Event`) into the log of the node."
  def publish(event, server \\ __MODULE__), do: GenServer.cast(server, {:publish, event})

  @doc """
  The events after the id `after_id` (0: from the start), in the order of
  their ids: from the memory, or from the store for the events that the
  memory does not keep now.
  """
  def history(after_id, server \\ __MODULE__), do: GenServer.call(server, {:history, after_id})

  @doc "The id of the last event."
  def last(server \\ __MODULE__), do: GenServer.call(server, :last)

  @impl true
  def init(opts) do
    store = Keyword.get_lazy(opts, :store, &Store.on?/0)
    Process.set_label(:log)

    recent = :ets.new(:log_recent, [:ordered_set, :private])

    last =
      case store && Store.last() do
        {:ok, n} ->
          started = %{"id" => n + @batch, "kind" => "started", "at" => 0, "wall" => World.Clock.wall()}
          started = Map.merge(started, %{"order" => nil, "who" => nil, "data" => %{}})
          Store.append([JSON.encode!(started)])
          :ets.insert(recent, {n + @batch, started})
          n + @batch

        _ ->
          0
      end

    {:ok, %{last: last, recent: recent, buffer: [], timer: nil, store: store}}
  end

  @impl true
  def handle_cast({:publish, event}, s) do
    id = s.last + 1
    data = event |> Log.data() |> Map.put("id", id)

    for key <- [data["order"], :world] do
      Registry.dispatch(World.Events, key, fn watchers -> for {pid, _} <- watchers, do: send(pid, {:world, data}) end)
    end

    :ets.insert(s.recent, {id, data})
    if :ets.info(s.recent, :size) > @keep, do: :ets.delete(s.recent, :ets.first(s.recent))
    {:noreply, keep(%{s | last: id}, data)}
  end

  @impl true
  def handle_call({:history, after_id}, _from, s) do
    recent = :ets.select(s.recent, [{{:"$1", :"$2"}, [{:>, :"$1", after_id}], [:"$2"]}])

    oldest =
      case :ets.first(s.recent) do
        :"$end_of_table" -> s.last + 1
        id -> id
      end

    # The events that the memory does not keep come from the store, after
    # the events of the buffer go into it.
    {older, s} =
      if s.store and after_id + 1 < oldest do
        flush(s.buffer)

        case Store.read(after_id, @read) do
          {:ok, lines} -> {lines |> Enum.map(&JSON.decode!/1) |> Enum.filter(&(&1["id"] < oldest)), %{s | buffer: []}}
          :error -> {[], %{s | buffer: []}}
        end
      else
        {[], s}
      end

    {:reply, older ++ recent, s}
  end

  def handle_call(:last, _from, s), do: {:reply, s.last, s}

  @impl true
  def handle_info(:flush, s) do
    flush(s.buffer)
    {:noreply, %{s | buffer: [], timer: nil}}
  end

  # An event for the store: in a batch of #{@batch}, or after #{@every} ms.
  defp keep(s, data) do
    if s.store do
      s = %{s | buffer: [JSON.encode!(data) | s.buffer]}

      cond do
        length(s.buffer) >= @batch ->
          flush(s.buffer)
          %{s | buffer: []}

        s.timer == nil ->
          %{s | timer: Process.send_after(self(), :flush, @every)}

        true ->
          s
      end
    else
      s
    end
  end

  defp flush(buffer), do: Store.append(Enum.reverse(buffer))
end
