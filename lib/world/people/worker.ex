defmodule World.People.Worker do
  @moduledoc """
  A worker (`World.People.Person`, job `:worker`) as a process: it does
  one task of a plan at a time. The work of a task is real: the worker
  makes the mesh of the part of the task (`World.Build.scene/2`), and the
  time of the task is the time of that code. A task with no part (the
  end of a smaller assembly) has no work. When the task is done, the
  worker tells the foreman.
  """
  use GenServer

  alias World.Build
  alias World.Log.Server

  @doc "Start a worker. The options: `name`, `place` (the factory), `log`."
  def start_link(opts), do: GenServer.start_link(__MODULE__, Map.new(opts))

  @doc "Do a task (`World.Plan.Task`) of an order, and tell `foreman`: `{:done, worker, task_id}`."
  def work(worker, order, task, foreman), do: GenServer.cast(worker, {:work, order, task, foreman})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:work, order, task, foreman}, w) do
    record(w, "task_started", order, task)
    if task.work, do: Build.scene(task.work)
    record(w, "task_done", order, task)
    send(foreman, {:done, w.name, task.id})
    {:noreply, w}
  end

  defp record(w, kind, order, task) do
    data = %{"task" => task.id, "station" => task.station, "uses" => task.uses}
    Server.record(w.log, kind, order: order, place: w.place, who: w.name, data: data)
  end
end
