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
  A job with a drawing (`drawing`, `World.Orders.Blueprints.drawing/1`)
  has one task for each node of the drawing (`World.Plan.of_drawing/1`):
  the person makes the node (the skill of the node, `World.Skill`, with
  the data of its nodes `from`), and the elements of the nodes go to the
  watchers in the order of the nodes.

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
  default), `level` (`:near` by default), `pose`, `budget` (a map),
  `drawing` (nil, or the drawing of the item: the people make it node by
  node), and `reply` (the process that gets the result).
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
      |> Map.put_new(:drawing, nil)
      |> Map.put_new(:haul, nil)
      |> Map.put_new(:place, nil)
      |> Map.put_new(:geo, nil)

    budget = job.budget
    clock = Clock.world()
    Process.set_label({:construction, job.id})
    urgent = :erlang.alias([:priority])
    # The alias is the value of the name: World.pause/1 and the others send
    # to it.
    {_, _} = Registry.update_value(World.Names, job.id, fn _ -> urgent end)
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
      over: false,
      paused: false,
      stale: %{}
    }

    workers = Map.get(budget, "workers", Map.get(job, :workers, @workers))
    s = record(s, "requested", nil, %{"budget" => budget, "level" => Atom.to_string(job.level), "workers" => workers})
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
        drawing = s.job.drawing
        plan = if drawing, do: Plan.of_drawing(drawing), else: Plan.flat(item)
        elements = if drawing, do: [], else: Build.elements(item, level, s.job.pose)

        s =
          Map.merge(s, %{
            level: level,
            item: item,
            plan: plan,
            elements: Enum.group_by(elements, &elem(&1, 0), &Tuple.delete_at(&1, 0)),
            made: %{},
            placed: MapSet.new(),
            hauls: %{},
            waiting: plan.tasks,
            done: MapSet.new(),
            running: %{},
            workers: %{},
            idle: [],
            requests: %{},
            triangles: %{},
            glbs: %{},
            cured: %{},
            days: %{},
            built: [],
            stages: Map.get(s.job, :stages, []),
            stage: nil,
            last_stage: nil,
            allowed: :all,
            fit: 1.0,
            origin: Clock.at(s.log.clock),
            age: 0.0,
            pause_from: 0.0,
            workers_limit: Map.get(s.job.budget, "workers", Map.get(s.job, :workers, @workers))
          })

        s = record(s, "plan_made", nil, Map.put(Plan.to_data(plan), "level", Atom.to_string(level)))
        {:noreply, s |> next_stage() |> assign()}

      {:error, triangles} ->
        stop(s, %{"reason" => "triangles", "triangles" => triangles})
    end
  end

  # The item at the level of the job, or at a lower level, with no more
  # triangles than the budget: `{:ok, level, item}`, or the triangles of
  # the far level. The item of a drawing is not made yet (nil): the
  # estimate of the drawing counts.
  defp fit(%{drawing: nil} = job, limit) do
    each_level(job, limit, fn level ->
      item = job.item.(level)
      {item, estimate(item, level, job.pose)}
    end)
  end

  defp fit(job, limit), do: each_level(job, limit, &{nil, World.Drawing.estimate(job.drawing, &1)})

  defp each_level(job, limit, fun) do
    levels = Enum.drop_while(@levels, &(&1 != job.level))

    Enum.reduce_while(levels, nil, fn level, _ ->
      {item, n} = if limit, do: fun.(level), else: {if(job.drawing, do: nil, else: job.item.(level)), 0}
      if limit == nil or n <= limit, do: {:halt, {:ok, level, item}}, else: {:cont, {:error, n}}
    end)
  end

  @doc "The key of the GLB of an element: a hash of the meshes that it shows."
  def key(shown),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(shown)) |> binary_part(0, 8) |> Base.encode16(case: :lower)

  @doc "The triangles of the meshes of an item at a level: each face of n corners is n - 2."
  def estimate(item, level, pose \\ %{}) do
    for {_, _, _, {shapes, _}} <- Build.elements(item, level, pose), m <- shapes, f <- m.faces, reduce: 0 do
      n -> n + length(f) - 2
    end
  end

  @impl true
  def handle_call({:join, pid}, _from, s), do: {:reply, :ok, %{s | replies: Enum.uniq(s.replies ++ [pid])}}

  # A change of the job in a pause: the nodes of the new drawing are the
  # nodes of the old one, and each node whose key is the same stays made
  # (World.Drawing.keys/1). The nodes that change are made again; a
  # person that works on one ends it for nobody (task_dropped).
  def handle_call({:change, _job}, _from, %{paused: false} = s), do: {:reply, {:error, :not_paused}, s}

  def handle_call({:change, job}, _from, s) when s.job.drawing == nil or job.drawing == nil,
    do: {:reply, {:error, :not_a_drawing}, s}

  def handle_call({:change, job}, _from, s) do
    {old, new} = {s.job.drawing, job.drawing}
    names = Enum.map(new["nodes"], & &1["name"])

    if names != Enum.map(old["nodes"], & &1["name"]) do
      {:reply, {:error, :other_nodes}, s}
    else
      {:reply, :ok, change(s, job, names)}
    end
  end

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

    if trade != nil and not s.paused and Enum.any?(ready(s), &(&1.trade == trade)) and
         not Enum.any?(s.idle, &(s.workers[&1] == trade)) do
      watched = Map.put(s.watched, p, :erlang.monitor(:process, p, [:priority]))
      s = %{s | workers: Map.put(s.workers, p, trade), idle: s.idle ++ [p], watched: watched}
      {:noreply, s |> record("hired", p, %{"trade" => Atom.to_string(trade)}) |> assign()}
    else
      # A person that the construction does not need now goes back.
      Person.release(p)
      {:noreply, assign(s)}
    end
  end

  # The result of a task that a change made again: it goes to nobody, and
  # the person is free.
  def handle_info({result, p, id, _}, s) when result in [:done, :failed] and is_map_key(s.stale, p) do
    s = %{s | stale: Map.delete(s.stale, p), idle: s.idle ++ [p]}
    s = record(s, "task_dropped", p, %{"task" => id})
    finish(assign(s))
  end

  # The result of a person that stopped after it sent it: its DOWN (a
  # message of priority) came first and gave the task back, so another
  # person makes it.
  def handle_info({:done, p, _id, _result}, s) when not is_map_key(s.running, p), do: {:noreply, s}

  def handle_info({:done, p, id, result}, s) do
    task = s.running[p]

    s = %{
      s
      | running: Map.delete(s.running, p),
        idle: s.idle ++ [p],
        done: MapSet.put(s.done, id),
        triangles: Map.merge(s.triangles, result.triangles),
        glbs: Map.merge(s.glbs, result.glbs),
        made: if(result[:made], do: Map.put(s.made, id, result.made), else: s.made),
        cured: Map.put(s.cured, id, Clock.wall() + Clock.to_wall(s.log.clock, round(task.wait * Clock.day())))
    }

    # The tasks after it wait for the cure (plan 0006, D2).
    if task.wait > 0,
      do: Process.send_after(self(), :cured, Clock.to_wall(s.log.clock, round(task.wait * Clock.day())) + 1)

    s = record(s, "task_done", p, task_data(task))
    # A task that takes down a part: the part goes (plan 0006, D7).
    s = if task.action == :remove, do: record(s, "element_removed", p, %{"task" => task.item}), else: s
    s = downs(s, p, id)
    s = if s.job.drawing, do: place(s, p), else: elements(s, p, id, Map.get(s.elements, id, []))
    finish(assign(s))
  end

  # The materials of a task are at the place of the construction.
  def handle_info({:hauled, ref}, s) do
    case Enum.find(Map.get(s, :hauls, %{}), fn {_, h} -> h == {:asked, ref} end) do
      {id, _} ->
        %{s | hauls: Map.put(s.hauls, id, :here)} |> record("parts_here", nil, %{"task" => id}) |> assign() |> finish()

      nil ->
        {:noreply, s}
    end
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
        watched: Map.delete(s.watched, p),
        stale: Map.delete(s.stale, p)
    }

    finish(assign(s))
  end

  # A client pauses the construction: it gives no task, and its free
  # people go; the people end the tasks in hand. A pause, a resume and a
  # cancel are messages of priority (`World.pause/1`).
  def handle_info(:pause, %{over: false, paused: false} = s) do
    s = record(%{s | paused: true}, "paused", nil, %{"in_hand" => map_size(s.running)})
    {:noreply, assign(s)}
  end

  def handle_info(:pause, s), do: {:noreply, s}

  def handle_info(:resume, %{over: false, paused: true} = s),
    do: %{s | paused: false} |> record("resumed", nil, %{}) |> assign() |> finish()

  def handle_info(:resume, s), do: {:noreply, s}

  def handle_info(:cancel, %{over: true} = s), do: {:noreply, s}
  def handle_info(:cancel, s), do: stop(s, %{"reason" => "cancelled", "done" => MapSet.size(s.done)})

  # The plan comes before any message, so the deadline finds it.
  def handle_info(:deadline, %{over: true} = s), do: {:noreply, s}
  def handle_info(:deadline, s), do: stop(s, %{"reason" => "seconds", "done" => MapSet.size(s.done)})

  def handle_info(:close, s), do: {:stop, :normal, s}

  # The concrete of a task has set: the tasks after it can start.
  def handle_info(:cured, s), do: s |> assign() |> finish()

  # The day of the next stage of the site, and the end of a pause.
  def handle_info(:stage, s), do: s |> next_stage() |> assign() |> finish()

  def handle_info(:pause_over, s) do
    days = day(s) - s.pause_from
    s = age(s, days)
    %{s | age: s.age + days} |> stage_done() |> finish()
  end

  # A year of a pause: the site gets old (plan 0006, D8).
  def handle_info({:age, days}, %{stage: %{work: "pause"}} = s), do: {:noreply, age(s, days)}
  def handle_info({:age, _}, s), do: {:noreply, s}

  defp elements(s, p, id, elements) do
    Enum.reduce(elements, s, fn {frame, part, shown}, s ->
      data = %{"task" => id, "part" => part.name, "glb" => key(shown), "matrix" => Frame.matrix(GLB.gl_frame(frame))}
      record(s, "element", p, data)
    end)
  end

  # The elements of the nodes of a drawing, each node when it is made, in
  # the model of the nodes so far (with the nodes that are temporary). The
  # root must be known first: each node up to the first with a part is
  # made.
  defp place(s, p) do
    nodes = s.job.drawing["nodes"]
    {before, root} = Enum.split_while(nodes, &(not part?(s.made[&1["name"]], &1)))
    known = root != [] and Enum.all?(before ++ [hd(root)], &Map.has_key?(s.made, &1["name"]))
    ready = for n <- nodes, Map.has_key?(s.made, n["name"]), not MapSet.member?(s.placed, n["name"]), do: n["name"]

    if not known or ready == [] do
      s
    else
      elements = Build.elements(World.Drawing.assemble(s.job.drawing, s.made, stream: true), s.level, s.job.pose)

      own = fn name ->
        for {path, f, part, shown} <- elements,
            path == name or String.starts_with?(path, name <> "/"),
            do: {f, part, shown}
      end

      s = Enum.reduce(ready, s, fn name, s -> elements(s, p, name, own.(name)) end)
      # The nodes with an element stand on the site (a change takes them down).
      built = for name <- ready, own.(name) != [], do: name
      %{s | placed: MapSet.union(s.placed, MapSet.new(ready)), built: s.built ++ built}
    end
  end

  # A node made with a part, that is not temporary: a root of the model.
  defp part?({thing, data, _}, node),
    do: thing != nil and not Map.get(node, "temporary", false) and not Map.get(data, "temporary", false)

  defp part?(nil, _node), do: false

  defp stop(s, data) do
    s = record(s, "stopped", nil, data)
    reply(s, {:stopped, s.id, data["reason"]})
    {:stop, :normal, s}
  end

  # The tasks that can start now: not given, each task they wait for is
  # done, and their materials are at the place.
  defp ready(%{job: %{haul: haul, drawing: d}} = s) when haul == nil or d == nil, do: waits_done(s)
  defp ready(s), do: Enum.filter(waits_done(s), &(s.hauls[&1.id] == :here))

  defp waits_done(s) do
    now = Clock.wall()

    Enum.filter(s.waiting, fn t ->
      allowed?(s, t.id) and Enum.all?(t.waits, &(MapSet.member?(s.done, &1) and Map.get(s.cured, &1, 0) <= now))
    end)
  end

  defp allowed?(%{allowed: :all}, _id), do: true
  defp allowed?(s, id), do: MapSet.member?(s.allowed, id)

  # A construction with a haul (`World.Haul`) and a place asks for the
  # takeoff of each task whose waits are done (World.Drawing.materials/3):
  # the trucks bring it to the place, and the task starts after it.
  defp ask(%{job: %{haul: haul, drawing: d}} = s) when haul == nil or d == nil, do: s

  defp ask(s) do
    drawing = s.job.drawing

    Enum.reduce(waits_done(s), s, fn t, s ->
      if Map.has_key?(s.hauls, t.id) do
        s
      else
        wants = World.Drawing.materials(drawing, t.id, World.Drawing.inputs(drawing, t.id, s.made))

        if wants == %{} do
          %{s | hauls: Map.put(s.hauls, t.id, :here)}
        else
          ref = make_ref()
          World.Haul.ask(s.job.haul, ref, s.id <> "|" <> t.id, s.job.place, wants)
          s = %{s | hauls: Map.put(s.hauls, t.id, {:asked, ref})}
          record(s, "parts_asked", nil, %{"task" => t.id, "place" => s.job.place, "materials" => wants})
        end
      end
    end)
  end

  # Give each task that can start to a free person of its trade; hire for
  # the trades with no free person, in the budget.
  defp assign(%{paused: true} = s), do: Enum.reduce(s.idle, s, &let_go(&2, &1))

  defp assign(s) do
    s = ask(s)

    {s, wanted} =
      Enum.reduce(ready(s), {s, []}, fn t, {s, wanted} ->
        case Enum.find(s.idle, &(s.workers[&1] == t.trade)) do
          nil -> {s, wanted ++ [t.trade]}
          p -> {give(s, p, t), wanted}
        end
      end)

    hire(s, wanted)
  end

  # The heap of a person for one task, in words: its part of the memory of
  # the budget (`"memory_mb"`), or no limit.
  defp heap(%{job: %{budget: %{"memory_mb" => mb}}, workers_limit: n}),
    do: div(mb * 1_048_576, n * :erlang.system_info(:wordsize))

  defp heap(_s), do: nil

  # A task takes the days of its work on the site (plan 0006, D1,
  # `World.Site`): the person does the work of the computer at once, and
  # is busy until the end of its days on the clock of the world.
  defp give(s, p, task) do
    {days, wait} = days(s, task)
    {days, wait} = {days * s.fit, wait * s.fit}
    task = Map.merge(task, %{days: days, wait: wait})
    waiting = Enum.reject(s.waiting, &(&1.id == task.id))
    s = %{s | idle: List.delete(s.idle, p), running: Map.put(s.running, p, task), waiting: waiting}
    s = %{s | days: Map.put(s.days, task.id, days)}
    s = record(s, "task_started", p, Map.merge(task_data(task), %{"days" => days, "wait" => wait}))
    due = Clock.wall() + Clock.to_wall(s.log.clock, round(days * Clock.day()))
    Person.work(p, task.id, until(work(s, task), due), heap(s))
    s
  end

  # To take down a part takes a part of the days to make it (`remove`).
  defp days(s, %{action: :remove, item: item}), do: {World.Site.days(%{"remove" => s.days[item]}, method(s)), 0.0}

  defp days(%{job: %{drawing: nil}} = s, _task), do: {World.Site.days(%{"task" => 1}, method(s)), 0.0}

  defp days(s, task) do
    d = s.job.drawing
    World.Site.task(d, task.id, World.Drawing.inputs(d, task.id, s.made), method(s))
  end

  defp method(s), do: Map.get(s.job, :method, "today")

  # The work, then the rest of the days of the task.
  defp until(work, due) do
    fn ->
      result = work.()
      Process.sleep(max(due - Clock.wall(), 0))
      result
    end
  end

  # The work of a task: the triangles of the meshes of its element that
  # nobody made yet, and the GLB of each part of the element that is new.
  # For a node of a drawing, the person makes the node first.
  # The parts that a task takes down (`down` of their nodes, plan 0006,
  # D9): the formwork at its strip, the scaffold at its fall, the rough
  # concrete under the render.
  defp downs(%{job: %{drawing: nil}} = s, _p, _id), do: s

  defp downs(s, p, id) do
    gone = for n <- s.job.drawing["nodes"], n["down"] == id, n["name"] in s.built, do: n["name"]
    s = Enum.reduce(gone, s, &record(&2, "element_removed", p, %{"task" => &1}))
    %{s | built: s.built -- gone}
  end

  # To take down a part needs no work of the computer.
  defp work(_s, %{action: :remove}), do: fn -> %{triangles: %{}, glbs: %{}} end

  defp work(%{job: %{drawing: nil}} = s, task) do
    elements = Map.get(s.elements, task.id, [])
    meshes = for {_, _, {shapes, _}} <- elements, m <- shapes, not Map.has_key?(s.triangles, m), uniq: true, do: m
    parts = for {_, part, shown} <- elements, not Map.has_key?(s.glbs, key(shown)), uniq: true, do: {key(shown), part}
    known = Map.take(s.triangles, for({_, _, {shapes, _}} <- elements, m <- shapes, do: m))
    {level, lean} = {s.level, lean?(s)}

    fn ->
      World.Detail.lean(lean, fn ->
        triangles = Map.new(meshes, &{&1, Mesh.triangles(&1)})
        all = Map.merge(known, triangles)
        glbs = Map.new(parts, fn {key, part} -> {key, Build.glb(part, level: level, triangles: all)} end)
        %{triangles: triangles, glbs: glbs}
      end)
    end
  end

  defp work(s, task) do
    {drawing, level, made, lean} = {s.job.drawing, s.level, s.made, lean?(s)}

    fn ->
      World.Detail.lean(lean, fn ->
        {thing, _, _} =
          result =
          World.Detail.with(level, fn ->
            World.Drawing.make(drawing, task.id, World.Drawing.inputs(drawing, task.id, made))
          end)

        elements = if thing, do: Build.elements(thing, level), else: []
        meshes = for {_, _, _, {shapes, _}} <- elements, m <- shapes, uniq: true, do: m
        triangles = Map.new(meshes, &{&1, Mesh.triangles(&1)})

        glbs =
          Map.new(elements, fn {_, _, part, shown} ->
            {key(shown), Build.glb(part, level: level, triangles: triangles)}
          end)

        %{triangles: triangles, glbs: glbs, made: result}
      end)
    end
  end

  # A full collection after each big step (World.Detail.collect/1) only
  # with a limit of memory: with no limit, the people do not wait for it.
  defp lean?(s), do: Map.has_key?(s.job.budget, "memory_mb")

  # A change of the lot drops each node; each built element that a change
  # drops comes down first, the last built first (plan 0006, D7): a task
  # `remove/NODE` of the trade of the node, and the node waits for it.
  defp change(s, job, names) do
    {old, new} = {World.Drawing.keys(s.job.drawing), World.Drawing.keys(job.drawing)}
    lot? = Map.get(job, :lot) != Map.get(s.job, :lot)
    changed = if lot?, do: names, else: for(n <- names, old[n] != new[n], do: n)
    gone = for n <- Enum.reverse(s.built), n in changed, do: n
    trades = Map.new(s.plan.tasks, &{&1.id, &1.trade})

    removes =
      for {n, i} <- Enum.with_index(gone) do
        waits = if i == 0, do: [], else: ["remove/" <> Enum.at(gone, i - 1)]
        %Plan.Task{id: "remove/" <> n, action: :remove, item: n, trade: trades[n], waits: waits}
      end

    started = MapSet.union(s.done, MapSet.new(Map.values(s.running), & &1.id))
    # The tasks that wait for a task are made again before it.
    redo = for n <- Enum.reverse(World.Drawing.order(job.drawing)), n in changed, MapSet.member?(started, n), do: n
    stale = for {p, t} <- s.running, t.id in changed, into: %{}, do: {p, t.id}
    running = Map.drop(s.running, Map.keys(stale))
    plan = Plan.of_drawing(job.drawing)
    tasks = for t <- plan.tasks, do: if(t.id in gone, do: %{t | waits: t.waits ++ ["remove/" <> t.id]}, else: t)
    plan = %{plan | tasks: removes ++ tasks}
    done = MapSet.difference(s.done, MapSet.new(changed))
    in_hand = for {_, t} <- running, do: t.id
    waiting = for t <- plan.tasks, not MapSet.member?(done, t.id), t.id not in in_hand, do: t
    placed = MapSet.difference(s.placed, MapSet.new(changed))
    keep = Map.take(job, [:drawing, :item, :scene, :pose, :hash, :lot, :geo])

    s = %{
      s
      | job: Map.merge(s.job, keep),
        plan: plan,
        done: done,
        running: running,
        waiting: waiting,
        stale: Map.merge(s.stale, stale),
        made: Map.drop(s.made, changed),
        hauls: Map.drop(s.hauls, changed),
        placed: placed,
        built: s.built -- changed
    }

    # A change in a stage of a site: the tasks that take down are of it.
    allowed = if s.allowed == :all, do: :all, else: MapSet.union(s.allowed, MapSet.new(removes, & &1.id))
    s = %{s | allowed: allowed}

    remove =
      for t <- removes,
          do: %{"id" => t.id, "action" => "remove", "waits" => t.waits, "trade" => Atom.to_string(t.trade)}

    data = %{"redo" => redo, "keep" => names -- changed, "remove" => remove}
    record(s, "changed", nil, if(lot?, do: Map.put(data, "lot", job.lot), else: data))
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

  # A model on a lot of a terrain has its place in the game (plan 0006, D5).
  defp geo(scene, %{geo: nil}), do: scene
  defp geo(scene, %{geo: geo}), do: %{scene | extras: Map.put(scene.extras, "geo", geo)}

  defp let_go(s, p) do
    Process.demonitor(s.watched[p], [:flush])
    Person.release(p)
    s = %{s | workers: Map.delete(s.workers, p), idle: List.delete(s.idle, p), watched: Map.delete(s.watched, p)}
    record(s, "released", p, %{})
  end

  # The end: each task done, the people go, and the model is joined.
  # The end of a stage of the site: each task of a build or a change is
  # done.
  defp finish(%{stage: %{work: work}, running: running} = s) when work != "pause" and running == %{} do
    if Enum.any?(s.waiting, &allowed?(s, &1.id)), do: {:noreply, s}, else: s |> stage_done() |> finish()
  end

  defp finish(%{stage: %{}} = s), do: {:noreply, s}
  defp finish(%{stages: [_ | _]} = s), do: {:noreply, s}

  defp finish(%{waiting: [], running: running, stale: stale} = s) when running == %{} and stale == %{} do
    s = Enum.reduce(s.idle, s, &let_go(&2, &1))
    s = if s.job.drawing, do: %{s | item: World.Drawing.assemble(s.job.drawing, s.made)}, else: s
    scene = fn -> geo(s.job.scene.(s.item, level: s.level, triangles: s.triangles, parallel: true), s.job) end
    glb = World.Detail.lean(lean?(s), fn -> GLB.encode(scene.()) end)
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
        {:noreply, %{s | item: nil, triangles: %{}, elements: %{}, made: %{}, over: true}}

      {:error, {:already_registered, _}} ->
        {:stop, :normal, s}
    end
  end

  defp finish(s), do: {:noreply, s}

  # --- The stages of a site (plan 0006, D6; World.Method) ---------------------------

  defp next_stage(%{stages: []} = s), do: s

  defp next_stage(%{stages: [st | rest]} = s) do
    s = %{s | stages: rest, stage: st}

    case st.work do
      "build" ->
        s = if st.repair, do: repair(s), else: s
        names = closure(s.job.drawing, st.until) -- MapSet.to_list(s.done)
        span = World.Site.span(World.Site.schedule(s.job.drawing, method(s), names))
        s = %{s | allowed: MapSet.new(names), fit: fit(s, st, span)}
        record(s, "stage_started", nil, stage_data(s, st))

      "pause" ->
        s = Enum.reduce(s.idle, %{s | allowed: MapSet.new(), fit: 1.0}, &let_go(&2, &1))
        # The days that are left of the pause (a late stage has fewer).
        days = st.to - max(day(s), st.from)

        for y <- 1..max(floor(days / 365), 1),
            y * 365 < days,
            do: Process.send_after(self(), {:age, y * 365.0}, wall(s, y * 365.0))

        Process.send_after(self(), :pause_over, wall(s, max(st.to - day(s), 0)))
        record(%{s | pause_from: day(s)}, "stage_started", nil, stage_data(s, st))

      "change" ->
        # The place of the model in the game on its new lot (World.Yard).
        job = Map.merge(st.job, %{lot: st.lot, geo: Map.get(Map.get(s.job, :geos, %{}), st.lot)})
        # The new statue is new: it has no age.
        s = change(%{s | age: 0.0}, job, Enum.map(job.drawing["nodes"], & &1["name"]))
        removes = for t <- s.waiting, t.action == :remove, do: t
        span = Enum.sum([0.0 | for(t <- removes, do: elem(days(s, t), 0))])
        s = %{s | allowed: MapSet.new(removes, & &1.id), fit: fit(s, st, span)}
        record(s, "stage_started", nil, stage_data(s, st))
    end
  end

  # The end of a stage: the next starts at its day (or now when it is
  # late), and no task starts before it.
  defp stage_done(%{stage: st} = s) do
    allowed = if s.stages == [], do: :all, else: MapSet.new()
    s = %{s | stage: nil, allowed: allowed, fit: 1.0, last_stage: st.name}
    s = record(s, "stage_done", nil, %{"name" => st.name, "work" => st.work})

    case s.stages do
      [next | _] -> Process.send_after(self(), :stage, wall(s, max(next.from - day(s), 0)))
      [] -> :ok
    end

    s
  end

  # The days of the tasks of a stage, fitted to the days between its dates.
  defp fit(_s, %{to: nil}, _span), do: 1.0
  defp fit(s, st, span), do: max(st.to - max(day(s), st.from), 1) / max(span, 1.0e-6)

  # The nodes of a build: the nodes of `until` and the nodes they wait for.
  defp closure(drawing, "all"), do: Enum.map(drawing["nodes"], & &1["name"])

  defp closure(drawing, until) do
    root = hd(drawing["nodes"])["name"]
    by_name = Map.new(drawing["nodes"], &{&1["name"], &1})

    walk = fn walk, name, seen ->
      Enum.reduce(World.Drawing.waits(by_name[name], root), MapSet.put(seen, name), &walk.(walk, &1, &2))
    end

    until |> Enum.reduce(MapSet.new(), &walk.(walk, &1, &2)) |> MapSet.to_list()
  end

  defp stage_data(s, st) do
    tasks = if s.allowed == :all, do: [], else: Enum.sort(MapSet.to_list(s.allowed))

    data = %{
      "name" => st.name,
      "work" => st.work,
      "from" => st.from,
      "to" => st.to,
      "fit" => s.fit,
      "text" => st.text,
      "date" => st.date,
      "means" => st.means,
      "after" => s.last_stage,
      "tasks" => tasks
    }

    data = if st.path, do: Map.put(data, "path", st.path), else: data
    if st.lot, do: Map.put(data, "lot", st.lot), else: data
  end

  # The day of the site now, from the start of the construction.
  defp day(s), do: (Clock.at(s.log.clock) - s.origin) / Clock.day()
  defp wall(s, days), do: Clock.to_wall(s.log.clock, round(days * Clock.day()))

  # A pause: the built model gets old with the days (plan 0006, D8): each
  # year of the pause and at its end. The concrete gets darker and weeds
  # grow on the base (an estimate of a rate); in the year of the middle
  # of the pause a part can go (`lost`).
  defp age(s, days) do
    st = s.stage
    half = (st.to - st.from) / 2
    lost = if days >= half and days - 365 < half, do: st.lost, else: []
    years = (s.age + days) / 365

    record(s, "aged", nil, %{
      "days" => s.age + days,
      "dirt" => Float.round(1 - :math.exp(-years / 8), 3),
      "weeds" => Float.round(min(years / 5, 1.0), 3),
      "lost" => lost
    })
  end

  # A repair at the start of a build after a pause: the model is clean.
  defp repair(s) do
    lost = for st <- Map.get(s.job, :stages, []), st.work == "pause", l <- st.lost, do: l
    record(%{s | age: 0.0}, "repaired", nil, %{"parts" => lost})
  end

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
