defmodule World.Log do
  @moduledoc """
  The log of the world (`docs/world.md`, "The events and the log"): the
  events in the order of their time. The log is the truth of the world:
  the replay and the statistics read it only.

  Each event has its world time (`at`) and its wall time (`wall`), in
  milliseconds, its kind, its order (the id of its construction), its
  person (`who`: the name of its process), and the data of its kind. The
  log keeps the scale and the start of its clock. In JSON, the log is one
  line for the clock, then one line for each event.
  """
  alias World.Clock

  @kinds ~w(requested plan_made hired released task_started task_done task_dropped element paused resumed changed done stopped failed run_done parts_asked parts_here haul_asked loaded unloaded hauled truck_joined place_raised place_open place_held place_started truck_made element_removed stage_started stage_done aged repaired)

  defmodule Event do
    @moduledoc "One thing that happened: its world time, wall time, kind, order, person and data."
    defstruct at: 0, wall: 0, kind: nil, order: nil, who: nil, data: %{}
  end

  defstruct clock: nil, events: []

  @doc "The kinds of an event."
  def kinds, do: @kinds

  @doc "An empty log with its clock."
  def new(%Clock{} = clock), do: %__MODULE__{clock: clock}

  @doc """
  Add an event of a kind. The options: `wall` (the wall time, now by
  default), `order`, `who`, `data`. The log refuses an unknown
  kind, and an event before the last one: `{:error, reason}`.
  """
  def add(%__MODULE__{clock: clock, events: events} = log, kind, opts \\ []) do
    wall = Keyword.get_lazy(opts, :wall, &Clock.wall/0)

    event = %Event{
      at: Clock.at(clock, wall),
      wall: wall,
      kind: kind,
      order: opts[:order],
      who: opts[:who],
      data: Keyword.get(opts, :data, %{})
    }

    cond do
      kind not in @kinds -> {:error, {:unknown_kind, kind}}
      events != [] and event.at < hd(events).at -> {:error, {:before_last, event}}
      true -> {:ok, %{log | events: [event | events]}}
    end
  end

  @doc "The events, in the order of their time."
  def events(%__MODULE__{events: events}), do: Enum.reverse(events)

  @doc "The log in JSON: one line for the clock, then one line for each event."
  def to_json(%__MODULE__{clock: clock} = log) do
    head = JSON.encode!(%{"scale" => clock.scale, "start" => clock.start})

    lines = for e <- events(log), do: JSON.encode!(data(e))
    Enum.join([head | lines], "\n") <> "\n"
  end

  @doc "An event as data, for JSON: its time, wall time, kind, order, person and data."
  def data(%Event{} = e),
    do: %{"at" => e.at, "wall" => e.wall, "kind" => e.kind, "order" => e.order, "who" => e.who, "data" => e.data}

  @doc "A log from its JSON, then checked (`check/1`): `{:ok, log}` or `{:error, reason}`."
  def from_json(json) do
    [head | lines] = String.split(json, "\n", trim: true)
    %{"scale" => scale, "start" => start} = JSON.decode!(head)

    events =
      for line <- lines, e = JSON.decode!(line) do
        %Event{
          at: e["at"],
          wall: e["wall"],
          kind: e["kind"],
          order: e["order"],
          who: e["who"],
          data: e["data"]
        }
      end

    log = %__MODULE__{clock: %Clock{scale: scale, start: start}, events: Enum.reverse(events)}
    with :ok <- check(log), do: {:ok, log}
  end

  @doc """
  Check a log: each event has a known kind, a world time from its wall
  time and the clock, and no event comes before the last one. For each
  order, a task starts once, after the plan of the order (`plan_made`),
  after each task it waits for is done; and a task is done after its
  start. `:ok`, or `{:error, {reason, event}}`.
  """
  def check(%__MODULE__{clock: clock} = log) do
    log
    |> events()
    |> Enum.reduce_while({nil, %{}}, fn e, {last, orders} ->
      case step(e, last, orders, clock) do
        {:ok, orders} -> {:cont, {e.at, orders}}
        {:error, reason} -> {:halt, {:error, {reason, e}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      _ -> :ok
    end
  end

  defp step(e, last, orders, clock) do
    cond do
      e.kind not in @kinds -> {:error, :unknown_kind}
      e.at != Clock.at(clock, e.wall) -> {:error, :wrong_time}
      last != nil and e.at < last -> {:error, :before_last}
      true -> task(e, orders)
    end
  end

  # The state of an order: the waits of each task, and the tasks that
  # started and that are done.
  defp task(%Event{kind: "plan_made", order: order, data: %{"tasks" => tasks}}, orders) do
    waits = Map.new(tasks, &{&1["id"], &1["waits"]})
    {:ok, Map.put(orders, order, %{waits: waits, started: MapSet.new(), done: MapSet.new()})}
  end

  defp task(%Event{kind: kind, order: order, data: %{"task" => id}}, orders) when kind in ~w(task_started task_done) do
    with {:ok, o} <- Map.fetch(orders, order) |> plan(),
         {:ok, waits} <- Map.fetch(o.waits, id) |> known() do
      case kind do
        "task_started" -> start(orders, order, o, id, waits)
        "task_done" -> finish(orders, order, o, id)
      end
    end
  end

  # A change makes its tasks again: they did not start, and are not done.
  # The tasks that take down what it drops (`remove`) are new tasks.
  defp task(%Event{kind: "changed", order: order, data: %{"redo" => redo} = d}, orders) do
    with {:ok, o} <- Map.fetch(orders, order) |> plan() do
      removes = Map.new(Map.get(d, "remove", []), &{&1["id"], &1["waits"]})

      o = %{
        o
        | waits: Map.merge(o.waits, removes),
          started: MapSet.difference(o.started, MapSet.new(redo)),
          done: MapSet.difference(o.done, MapSet.new(redo))
      }

      {:ok, Map.put(orders, order, o)}
    end
  end

  defp task(_, orders), do: {:ok, orders}

  defp plan(:error), do: {:error, :no_plan}
  defp plan(ok), do: ok

  defp known(:error), do: {:error, :unknown_task}
  defp known(ok), do: ok

  defp start(orders, order, o, id, waits) do
    cond do
      MapSet.member?(o.started, id) -> {:error, :started_twice}
      not Enum.all?(waits, &MapSet.member?(o.done, &1)) -> {:error, :waits_not_done}
      true -> {:ok, Map.put(orders, order, %{o | started: MapSet.put(o.started, id)})}
    end
  end

  defp finish(orders, order, o, id) do
    cond do
      not MapSet.member?(o.started, id) -> {:error, :not_started}
      MapSet.member?(o.done, id) -> {:error, :done_twice}
      true -> {:ok, Map.put(orders, order, %{o | done: MapSet.put(o.done, id)})}
    end
  end
end
