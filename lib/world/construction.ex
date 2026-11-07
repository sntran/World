defmodule World.Construction do
  @moduledoc """
  A construction: one build of a model by the people of the node
  (`docs/plans/0001-people-build-on-demand.md`, R3).

  1. The construction makes the item at the level of the job, or at a
     lower level when the triangles of the budget are fewer than the
     triangles of the item (`requested`; `stopped` when no level fits).
  2. It makes the plan from the tree of the item (`World.Plan.flat/1`):
     one task for each node, each with its trade (`plan_made`).
  3. For each task that can start, it gives the task to a free person of
     its trade that it holds, or hires one from the census in its budget
     of workers (`hired`). At its budget, it lets a free person of
     another trade go to make room (`released`).
  4. The work of a task is real: the person makes the triangles of the
     meshes of its element and the GLB of the element alone
     (`task_started`, `task_done`, `element`).
  5. When each task is done, it lets its people go and joins the model:
     one `World.Build.scene/2` with the triangles that the people made,
     so the file has the bytes of a build with no world (`done`,
     `run_done`).

  The deadline and the people that stop come first (priority messages,
  Erlang/OTP 28): the deadline goes to a priority alias of the
  construction, and it watches each person that it holds with a monitor
  of priority. So they do not wait behind the results of the people in
  the mailbox (thousands for a house of bricks).

  The budget (`budget`): `"workers"` (the most people at one time, #{4} by
  default), `"seconds"` (the time of the build: then `stopped`, and no
  model) and `"triangles"` (the most triangles of the model). Each event
  goes into the log of the construction and into the log of the node
  (`World.Log.Server`), which sends it to the watchers. The
  job gets `{:built, id, result}`, `{:failed, id, message}` or
  `{:stopped, id, reason}`.
  """
  use GenServer, restart: :temporary

  alias World.{Build, Clock, Frame, GLB, Log, Mesh, Person, Plan}

  @workers 4
  @levels [:near, :mid, :far]

  @doc """
  Start a construction under the node. The job: `id` (a text), `item` (a
  function of a level that gives the item), `scene` (a function of the
  item and the options of `World.Build.scene/2`; `World.Build.scene/2` by
  default), `level` (`:near` by default), `pose`, `budget` (a map), and
  `reply` (the process that gets the result).
  """
  def start(job), do: DynamicSupervisor.start_child(World.Constructions, {__MODULE__, job})

  @doc """
  The GLB of an element of the construction `id` (a key of its elements):
  `{:ok, glb}`, or `:none` when no construction of the id runs now or
  keeps its elements: a construction keeps them for 5 minutes after its
  end, for a watcher that comes late (`:linger` of the application
  environment for this module, in ms).
  """
  def element(id, key) do
    Enum.find_value([id, {:elements, id}], :none, fn name ->
      with [{pid, _}] <- Registry.lookup(World.Names, name),
           {:ok, glb} <- GenServer.call(pid, {:element, key}) do
        {:ok, glb}
      else
        _ -> nil
      end
    end)
  catch
    :exit, _ -> :none
  end

  @doc "Send the result of the construction `id` to `pid` too: a second job of the same build."
  def join(id, pid), do: GenServer.call({:via, Registry, {World.Names, id}}, {:join, pid})

  @doc false
  def start_link(job), do: GenServer.start_link(__MODULE__, job, name: {:via, Registry, {World.Names, job.id}})

  @impl true
  def init(job) do
    job =
      job
      |> Map.put_new(:scene, &Build.scene/2)
      |> Map.put_new(:level, :near)
      |> Map.put_new(:pose, %{})
      |> Map.put_new(:budget, %{})

    budget = job.budget
    clock = Clock.new()
    Process.set_label({:construction, job.id})
    urgent = :erlang.alias([:priority])
    # The memory of the VM, each 25 ms of the construction: its most.
    me = self()
    sampler = spawn_link(fn -> sample(me, World.memory()) end)

    s = %{
      job: job,
      id: job.id,
      log: Log.new(clock),
      start: System.monotonic_time(:millisecond),
      replies: [job.reply],
      sampler: sampler,
      urgent: urgent,
      watched: %{},
      over: false
    }

    s = record(s, "requested", nil, %{"budget" => budget, "level" => Atom.to_string(job.level)})
    # A timer cannot send to an alias: the timer server sends it.
    if budget["seconds"],
      do:
        {:ok, _} = :timer.apply_after(round(budget["seconds"] * 1000), :erlang, :send, [urgent, :deadline, [:priority]])

    {:ok, s, {:continue, :plan}}
  end

  @impl true
  def handle_continue(:plan, s) do
    case fit(s.job, s.job.budget["triangles"]) do
      {:ok, level, item} ->
        plan = Plan.flat(item)
        elements = Build.elements(item, level, s.job.pose)
        keys = elements |> Enum.map(&elem(&1, 3)) |> Enum.uniq() |> Enum.with_index() |> Map.new()

        s =
          Map.merge(s, %{
            level: level,
            item: item,
            plan: plan,
            elements: Enum.group_by(elements, &elem(&1, 0), &Tuple.delete_at(&1, 0)),
            keys: keys,
            waiting: plan.tasks,
            done: MapSet.new(),
            running: %{},
            workers: %{},
            idle: [],
            requests: %{},
            triangles: %{},
            glbs: %{},
            workers_limit: Map.get(s.job.budget, "workers", @workers)
          })

        s = record(s, "plan_made", nil, Map.put(Plan.to_data(plan), "level", Atom.to_string(level)))
        {:noreply, assign(s)}

      {:error, triangles} ->
        stop(s, %{"reason" => "triangles", "triangles" => triangles})
    end
  end

  # The item at the level of the job, or at a lower level, with no more
  # triangles than the budget: `{:ok, level, item}`, or the triangles of
  # the far level.
  defp fit(job, limit) do
    levels = Enum.drop_while(@levels, &(&1 != job.level))

    Enum.reduce_while(levels, nil, fn level, _ ->
      item = job.item.(level)
      n = estimate(item, level, job.pose)
      if limit == nil or n <= limit, do: {:halt, {:ok, level, item}}, else: {:cont, {:error, n}}
    end)
  end

  @doc "The triangles of the meshes of an item at a level: each face of n corners is n - 2."
  def estimate(item, level, pose \\ %{}) do
    for {_, _, _, {shapes, _}} <- Build.elements(item, level, pose), m <- shapes, f <- m.faces, reduce: 0 do
      n -> n + length(f) - 2
    end
  end

  @impl true
  def handle_call({:join, pid}, _from, s), do: {:reply, :ok, %{s | replies: Enum.uniq(s.replies ++ [pid])}}

  def handle_call({:element, key}, _from, s) do
    case Map.fetch(Map.get(s, :glbs, %{}), key) do
      {:ok, glb} -> {:reply, {:ok, glb}, s}
      :error -> {:reply, :none, s}
    end
  end

  @impl true
  def handle_info({:hired, ref, p}, s) do
    {trade, requests} = Map.pop(s.requests, ref)
    s = %{s | requests: requests}

    if trade != nil and Enum.any?(ready(s), &(&1.trade == trade)) and not Enum.any?(s.idle, &(s.workers[&1] == trade)) do
      watched = Map.put(s.watched, p, :erlang.monitor(:process, p, [:priority]))
      s = %{s | workers: Map.put(s.workers, p, trade), idle: s.idle ++ [p], watched: watched}
      {:noreply, s |> record("hired", p, %{"trade" => Atom.to_string(trade)}) |> assign()}
    else
      # A person that the construction does not need now goes back.
      Person.release(p)
      {:noreply, assign(s)}
    end
  end

  def handle_info({:done, p, id, result}, s) do
    task = s.running[p]

    s = %{
      s
      | running: Map.delete(s.running, p),
        idle: s.idle ++ [p],
        done: MapSet.put(s.done, id),
        triangles: Map.merge(s.triangles, result.triangles),
        glbs: Map.merge(s.glbs, result.glbs)
    }

    s = record(s, "task_done", p, task_data(task))

    s =
      Enum.reduce(Map.get(s.elements, id, []), s, fn {frame, part, shown}, s ->
        data = %{
          "task" => id,
          "part" => part.name,
          "glb" => s.keys[shown],
          "matrix" => Frame.matrix(GLB.gl_frame(frame))
        }

        record(s, "element", p, data)
      end)

    finish(assign(s))
  end

  def handle_info({:failed, _p, id, message}, s) do
    s = record(s, "failed", nil, %{"task" => id, "message" => message})
    reply(s, {:failed, s.id, message})
    {:stop, :normal, s}
  end

  # A person that stopped: its task goes back to the tasks that wait.
  def handle_info({:DOWN, _, :process, p, _}, s) do
    {task, running} = Map.pop(s.running, p)
    waiting = if task, do: [task | s.waiting], else: s.waiting

    s = %{
      s
      | running: running,
        waiting: waiting,
        workers: Map.delete(s.workers, p),
        idle: List.delete(s.idle, p),
        watched: Map.delete(s.watched, p)
    }

    {:noreply, assign(s)}
  end

  # The plan comes before any message, so the deadline finds it.
  def handle_info(:deadline, %{over: true} = s), do: {:noreply, s}
  def handle_info(:deadline, s), do: stop(s, %{"reason" => "seconds", "done" => MapSet.size(s.done)})

  def handle_info(:close, s), do: {:stop, :normal, s}

  defp stop(s, data) do
    s = record(s, "stopped", nil, data)
    reply(s, {:stopped, s.id, data["reason"]})
    {:stop, :normal, s}
  end

  # The tasks that can start now: not given, and each task they wait for is done.
  defp ready(s), do: Enum.filter(s.waiting, fn t -> Enum.all?(t.waits, &MapSet.member?(s.done, &1)) end)

  # Give each task that can start to a free person of its trade; hire for
  # the trades with no free person, in the budget.
  defp assign(s) do
    {s, wanted} =
      Enum.reduce(ready(s), {s, []}, fn t, {s, wanted} ->
        case Enum.find(s.idle, &(s.workers[&1] == t.trade)) do
          nil -> {s, wanted ++ [t.trade]}
          p -> {give(s, p, t), wanted}
        end
      end)

    hire(s, wanted)
  end

  defp give(s, p, task) do
    s = %{s | idle: List.delete(s.idle, p), running: Map.put(s.running, p, task), waiting: List.delete(s.waiting, task)}
    s = record(s, "task_started", p, task_data(task))
    Person.work(p, task.id, work(s, task))
    s
  end

  # The work of a task: the triangles of the meshes of its element that
  # nobody made yet, and the GLB of each part of the element that is new.
  defp work(s, task) do
    elements = Map.get(s.elements, task.id, [])
    meshes = for {_, _, {shapes, _}} <- elements, m <- shapes, not Map.has_key?(s.triangles, m), uniq: true, do: m

    parts =
      for {_, part, shown} <- elements, not Map.has_key?(s.glbs, s.keys[shown]), uniq: true, do: {s.keys[shown], part}

    known = Map.take(s.triangles, for({_, _, {shapes, _}} <- elements, m <- shapes, do: m))
    level = s.level

    fn ->
      triangles = Map.new(meshes, &{&1, Mesh.triangles(&1)})
      all = Map.merge(known, triangles)
      glbs = Map.new(parts, fn {key, part} -> {key, Build.glb(part, level: level, triangles: all)} end)
      %{triangles: triangles, glbs: glbs}
    end
  end

  # The trades that wait for a person: hire in the budget. When a trade
  # that a task needs has nobody here, the free people of the trades that
  # no task needs now go back: they make room in the budget, and in the
  # people of the node, so two constructions never wait for each other
  # (specs/Census.tla).
  defp hire(s, wanted) do
    wanted = Enum.uniq(wanted)
    missing = Enum.any?(wanted, &(&1 not in Map.values(s.workers)))
    spare = if missing, do: Enum.filter(s.idle, &(s.workers[&1] not in wanted)), else: []
    s = Enum.reduce(spare, s, &let_go(&2, &1))
    asked = Map.values(s.requests)

    Enum.reduce(wanted, s, fn trade, s ->
      if trade not in asked and map_size(s.workers) + map_size(s.requests) < s.workers_limit,
        do: %{s | requests: Map.put(s.requests, Person.hire(trade), trade)},
        else: s
    end)
  end

  defp let_go(s, p) do
    Process.demonitor(s.watched[p], [:flush])
    Person.release(p)
    s = %{s | workers: Map.delete(s.workers, p), idle: List.delete(s.idle, p), watched: Map.delete(s.watched, p)}
    record(s, "released", p, %{})
  end

  # The end: each task done, the people go, and the model is joined.
  defp finish(%{waiting: [], running: running} = s) when running == %{} do
    s = Enum.reduce(s.idle, s, &let_go(&2, &1))
    glb = GLB.encode(s.job.scene.(s.item, level: s.level, triangles: s.triangles))
    s = record(s, "done", nil, %{"bytes" => byte_size(glb), "level" => Atom.to_string(s.level)})
    send(s.sampler, :peak)
    {what, peak} = receive do: ({:peak, peak} -> peak)
    {_, now} = World.memory()

    s =
      record(s, "run_done", nil, %{
        "ms" => System.monotonic_time(:millisecond) - s.start,
        "memory_peak" => max(peak, now),
        "memory_end" => now,
        "memory" => what
      })

    reply(s, {:built, s.id, %{glb: glb, log: s.log, level: s.level, plan: s.plan, glbs: s.glbs}})

    # The construction keeps the GLBs of its elements for a while, under
    # a name of its own, so a new build of the same id can start. When an
    # earlier build of the id keeps them now, it has the same elements.
    Registry.unregister(World.Names, s.id)

    case Registry.register(World.Names, {:elements, s.id}, nil) do
      {:ok, _} ->
        linger = Keyword.get(Application.get_env(:world, __MODULE__, []), :linger, 300_000)
        Process.send_after(self(), :close, linger)
        {:noreply, %{s | item: nil, triangles: %{}, elements: %{}, over: true}}

      {:error, {:already_registered, _}} ->
        {:stop, :normal, s}
    end
  end

  defp finish(s), do: {:noreply, s}

  defp sample(owner, {what, peak}) do
    {_, now} = World.memory()

    receive do
      :peak -> send(owner, {:peak, {what, max(peak, now)}})
    after
      25 -> sample(owner, {what, max(peak, now)})
    end
  end

  defp reply(s, message), do: for(pid <- s.replies, do: send(pid, message))

  defp task_data(t), do: %{"task" => t.id, "trade" => Atom.to_string(t.trade), "station" => t.station}

  # An event into the log of the construction and to its watchers. The
  # wall clock of the system can go back a little: an event is never
  # before the last one.
  defp record(s, kind, who, data) do
    last = List.first(s.log.events)
    wall = max(Clock.wall(), if(last, do: last.wall, else: 0))
    who = who && Person.name(who)
    {:ok, log} = Log.add(s.log, kind, wall: wall, order: s.id, who: who, data: data)
    World.Log.Server.publish(hd(log.events))
    %{s | log: log}
  end
end
