defmodule World.Labour do
  @moduledoc """
  The labour of the parts of the models (`World.Elements`, W24 to W28):
  where a part builds.

  The edge has 128 MB for a VM and a limit of CPU time for each request
  (`limits.cpu_ms`, 5 minutes at most). A construction shift has neither
  (`World.Shift`, `docs/factory.md`, "Construction shifts"): a workflow
  of the repository on a runner of GitHub Actions, whose node joins the
  node of the edge (`World.Crew`) for some hours. Then:

  - A part that fits the edge (`fits?/1`: a person at mid or far) builds
    here.
  - The edge with shifts (the application environment `:shifts`,
    `WORLD_SHIFTS=true`) builds no other part. A part of an order of a
    project (a request with a project token: the option `project`) waits
    in the queue for a node of a shift (`waiting/0`). Then the edge gives
    it, by its key, to the node with the fewest parts in work for its
    workers, when that node has a free core: a node builds at most one
    part for each of its cores at a time (`World.Crew` gives a node 2
    workers for each core), and the parts take the free cores in the
    order that they came to the queue. The node builds it from its recipe (`World.Elements.part/1`),
    puts its GLB in the store itself (R2), and gives back only the key
    (`make/1`): the GLB does not go over the link. A part whose node goes
    away goes back to the queue. A part that fails on 3 tries gives
    the error. The queue, its order and the node of each part in work
    are also in a store (`World.Labour.Store`, the SQLite of the Durable
    Object): a new VM (a deploy, the limit of the memory) takes them
    back (`restore/1`), so no part goes and the order stays. A part of a
    public order (no project) gives an error: the shifts are for the
    projects of the owner only.
  - With no shifts (a server on a computer, or native nodes that join
    it), a part goes to the nodes that take parts (on the next node when
    its node goes away), and builds here when no node is left.
  """

  alias World.{Crew, Elements, Line, Shift}
  alias World.Elements.Store
  alias World.Labour.Store, as: Queue

  @tries 3

  @doc """
  The list of the parts in work on each node and of the parts in the
  queue, which `build/3` reads, the GLBs that this node built and the
  store did not take yet (`make/2`), and the projects of the parts with
  no store of the queue (`World.Labour.Store.ask/2`) (`World.Supervisor`).
  """
  def children,
    do: [
      {Registry, keys: :duplicate, name: __MODULE__},
      %{id: __MODULE__.Kept, start: {Agent, :start_link, [fn -> %{} end, [name: __MODULE__.Kept]]}},
      %{id: __MODULE__.Projects, start: {Agent, :start_link, [fn -> %{} end, [name: __MODULE__.Projects]]}},
      World.Labour.Restore
    ]

  @doc """
  Build the part `key` with its recipe (a map): here, or on another node.
  `{:ok, glb}` when it was built here, `:stored` when another node built
  it and put it in the store, `:none` or `{:error, errors}` as
  `World.Elements.part/1`. The options:

  - `nodes`: the nodes that take parts, each `{supervisor of the tasks,
    workers}`, or a function that gives them now (`World.Crew.parts/0`
    by default).
  - `shifts`: true at the edge with construction shifts (the application
    environment `:shifts` by default).
  - `project`: true for a part of an order of a project.
  - `poll` (1,000 ms): the wait between two looks for a node, and `most`
    (6 hours): the longest wait in the queue.
  """
  def build(key, recipe, opts) do
    shifts = Keyword.get_lazy(opts, :shifts, fn -> Application.get_env(:world, :shifts, false) end)

    cond do
      fits?(recipe) -> here(key)
      shifts and opts[:project] -> queue(key, opts)
      shifts -> {:error, public()}
      true -> away(key, nodes(opts))
    end
  end

  @doc """
  True for a part that the edge builds itself in its memory and its CPU
  limit: a person of a group at mid or far (about 100 MB and 10 s at the
  edge). A part of a sculpture and a person at near do not fit.
  """
  def fits?(%{"piece" => _, "level" => level}) when level in ["mid", "far"], do: true
  def fits?(_recipe), do: false

  @doc """
  True at the edge with shifts for the key of a part with a recipe that
  does not fit the edge: a part of a project of that key waits for a
  shift. (The Worker asks the VM only for a part that R2 does not have.)
  """
  def needs_shift?(key) do
    with true <- Application.get_env(:world, :shifts, false),
         {:ok, json} <- Store.recipe(key),
         {:ok, recipe} <- JSON.decode(json) do
      not fits?(recipe)
    else
      _ -> false
    end
  end

  @doc """
  A project asked for the part `key`, which waits for a shift: the
  summary of the shift gives the parts of each project (`World.Shift`).
  A part keeps the place of its first request in the queue, whatever
  project asks for it again.
  """
  def asked(key, project), do: Queue.ask(key, project)

  @doc """
  The part of a key, on the node that gives it the work: `:stored` when
  the store has it already (a part in R2 does not build again), else
  built from its recipe and put in the store (in the record of the shift,
  `World.Shift.work/3`, with `projects`: the projects that asked for it).
  `:stored`, or the error of
  `World.Elements.part/1`. The GLB stays on this node. When this node
  builds the key already (the edge gave it again: a VM of the edge that
  started again asks again), the make waits for that build and does not
  build the part a second time. When the store does not take the GLB (a
  VM of the edge that started again does not know that it gave the key
  to this node), the GLB stays on this node and the make raises: the
  edge gives the key again, and the next make puts that GLB, with no new
  build.
  """
  def make(key, projects \\ []) do
    if Store.has?(key) do
      :stored
    else
      case :global.trans({__MODULE__, {:make, key}}, fn -> claim(key) end, [node()]) do
        :mine ->
          try do
            Shift.work(key, fn -> built(key) end, projects)
          after
            Registry.unregister(__MODULE__, {:make, key})
          end

        maker ->
          ref = Process.monitor(maker)

          receive do
            {:DOWN, ^ref, :process, _, _} -> make(key, projects)
          end
      end
    end
  end

  # The part of a key in the store: the GLB that this node kept, else a
  # new build. `:stored`, or the error of `World.Elements.part/1`.
  defp built(key) do
    case kept(key) || Elements.part(key) do
      {:ok, glb} ->
        if Store.has?(key) or Store.put(key, glb) == :ok do
          Agent.update(__MODULE__.Kept, &Map.delete(&1, key))
          :stored
        else
          Agent.update(__MODULE__.Kept, &Map.put(&1, key, glb))
          raise "the store did not take the part #{key}: its GLB stays on this node for the next try"
        end

      other ->
        other
    end
  end

  defp kept(key) do
    case Agent.get(__MODULE__.Kept, &Map.get(&1, key)) do
      nil -> nil
      glb -> {:ok, glb}
    end
  end

  # The process that builds the key on this node, or :mine (this process
  # builds it now).
  defp claim(key) do
    case Registry.lookup(__MODULE__, {:make, key}) do
      [{maker, _} | _] ->
        maker

      [] ->
        {:ok, _} = Registry.register(__MODULE__, {:make, key}, nil)
        :mine
    end
  end

  @doc "The count of the parts in work on a node (its supervisor of the tasks)."
  def busy(tasks), do: length(Registry.lookup(__MODULE__, tasks))

  @doc "The count of the parts that wait in the queue for a node of a shift (not the parts in work on a node)."
  def waiting, do: length(Registry.lookup(__MODULE__, :queue))

  @doc "The error of a part of a public order that does not fit the edge."
  def public,
    do: [
      %{
        "path" => "",
        "message" =>
          "this part does not fit the memory and the CPU time of the edge, and a construction shift builds only the orders of the projects of the owner (docs/factory.md, \"Construction shifts\")"
      }
    ]

  defp here(key), do: Line.run(:now, fn -> Elements.part(key) end)

  defp nodes(opts) do
    case Keyword.get(opts, :nodes, &Crew.parts/0) do
      fun when is_function(fun, 0) -> fun.()
      nodes -> nodes
    end
  end

  # With no shifts: the node with the fewest parts in work for its
  # workers; then the next ones when it goes away; then here.
  defp away(key, []), do: here(key)

  defp away(key, nodes) do
    {tasks, _} = pick(nodes)

    case try_on(key, tasks) do
      {:ok, done} -> done
      _ -> away(key, List.keydelete(nodes, tasks, 0))
    end
  end

  # A part of a project at the edge with shifts: in the queue until a
  # node of a shift has a free core for it, and until that node builds
  # it. Its ticket keeps its place in the queue: first come, first served.
  defp queue(key, opts) do
    ticket = Queue.wait(key, ticket())
    wait(key, ticket)
    until = System.monotonic_time(:millisecond) + Keyword.get(opts, :most, 6 * 3_600_000)

    try do
      turn(key, opts, 0, until, ticket)
    after
      Registry.unregister(__MODULE__, :queue)
      Queue.done(key)
    end
  end

  # A ticket of the queue: the time of the clock (µs) and a count, so the
  # tickets of a VM that starts again come after the tickets before it.
  defp ticket, do: System.os_time(:microsecond) * 1000 + rem(System.unique_integer([:positive, :monotonic]), 1000)

  @doc """
  The parts of the store (`World.Labour.Store`) that have no process
  now, after a start of the VM: each part goes back to the queue at its
  place, in the process of its key (`World.Elements.start/2`: a request
  of the key joins it), one part after the other. A part that a VM before gave to a node is
  in the work of that node at once, so the store takes its GLB, and goes
  to that node again when the node is there: the node waits for its build,
  or puts the GLB that it kept (`make/1`). The options are those of
  `build/3`. `:ok`, or `:error` when the store fails.
  """
  def restore(opts \\ []) do
    with {:ok, rows} <- Queue.all(), do: Enum.each(rows, &restart(&1, opts))
  end

  # A part of the store in a process of its key, one part after the
  # other: each part is in the queue (or in the work of its node) before
  # the next part starts, so no part takes a core before a part of an
  # older ticket. A part that has its process now is not touched.
  defp restart(row, opts) do
    {me, ref} = {self(), make_ref()}

    case Elements.start({:part, row.key}, fn -> resume(row, opts, fn -> send(me, {ref, :ready}) end) end) do
      {:new, pid} ->
        watch = Process.monitor(pid)

        receive do
          {^ref, :ready} -> Process.demonitor(watch, [:flush])
          # (A part that the store has ends at once.)
          {:DOWN, ^watch, :process, ^pid, _} -> true
        end

      {:joined, _} ->
        true
    end
  end

  # A part of the store, in the queue again; `ready` when it is there.
  defp resume(%{key: key, ticket: ticket, node: node}, opts, ready) do
    until = System.monotonic_time(:millisecond) + Keyword.get(opts, :most, 6 * 3_600_000)

    try do
      cond do
        # (A VM before put it in the store and had no time to say so.)
        Store.has?(key) ->
          :stored

        node == nil ->
          wait(key, ticket)
          ready.()
          turn(key, opts, 0, until, ticket)

        true ->
          again(key, node, opts, until, ticket, ready)
      end
    after
      Registry.unregister(__MODULE__, :queue)
      Queue.done(key)
    end
  end

  # A part in work on `node` when the VM before stopped: in the work of
  # that node at once, and to that node when it is there; else, after
  # `back` ms (2.5 minutes: a node with no connection for 2 minutes joins
  # again with a new name), back to the queue at its place.
  defp again(key, node, opts, until, ticket, ready) do
    away = {Crew.Tasks, node}
    {:ok, _} = Registry.register(__MODULE__, away, key)
    ready.()
    there = there(node, opts, System.monotonic_time(:millisecond) + Keyword.get(opts, :back, 150_000))
    Registry.unregister(__MODULE__, away)

    case there do
      {tasks, _} ->
        {:ok, _} = Registry.register(__MODULE__, tasks, key)
        after_run(key, run_on(key, tasks), opts, 0, until, ticket)

      :none ->
        wait(key, ticket)
        Queue.back(key)
        turn(key, opts, 0, until, ticket)
    end
  end

  # The node that takes parts with the name `node`, when it is there
  # before `stop`; else :none.
  defp there(node, opts, stop) do
    case Enum.find(nodes(opts), fn {tasks, _} -> node_of(tasks) == node end) do
      nil ->
        if System.monotonic_time(:millisecond) > stop do
          :none
        else
          Process.sleep(Keyword.get(opts, :poll, 1_000))
          there(node, opts, stop)
        end

      found ->
        found
    end
  end

  defp node_of({_, node}) when is_atom(node), do: node
  defp node_of(pid) when is_pid(pid), do: node(pid)

  defp wait(key, ticket), do: {:ok, _} = Registry.register(__MODULE__, :queue, {ticket, key})

  defp turn(key, opts, tries, until, ticket) do
    poll = Keyword.get(opts, :poll, 1_000)

    case take(nodes(opts), key, ticket) do
      nil ->
        if System.monotonic_time(:millisecond) > until do
          {:error, [%{"path" => "", "message" => "no construction shift came for this part: send the request again"}]}
        else
          Process.sleep(poll)
          turn(key, opts, tries, until, ticket)
        end

      tasks ->
        Queue.give(key, node_of(tasks))
        after_run(key, run_on(key, tasks), opts, tries, until, ticket)
    end
  end

  defp after_run(key, result, opts, tries, until, ticket) do
    case result do
      {:ok, done} ->
        done

      # (The node went away, or its shift ended: the part goes back to
      # the queue, at its place. It is in the queue again before the
      # store hears of it: no part of a later ticket takes its core in
      # that time.)
      :gone ->
        wait(key, ticket)
        Queue.back(key)
        Process.sleep(Keyword.get(opts, :poll, 1_000))
        turn(key, opts, tries, until, ticket)

      {:failed, _} when tries + 1 >= @tries ->
        {:error, [%{"path" => "", "message" => "the part failed on #{@tries} nodes of a construction shift"}]}

      {:failed, _} ->
        wait(key, ticket)
        Queue.back(key)
        turn(key, opts, tries + 1, until, ticket)
    end
  end

  # A free core of a node for the part of `ticket`, or nil: the parts
  # that came to the queue before it take the free cores first. The part
  # goes into the work of the node in the lock, so two parts do not take
  # one core.
  defp take(nodes, key, ticket) do
    :global.trans(
      {__MODULE__, :take},
      fn ->
        free = for {tasks, workers} <- nodes, room(tasks, workers) > 0, do: {tasks, workers}
        before = Enum.count(Registry.lookup(__MODULE__, :queue), fn {_, {t, _}} -> t < ticket end)

        if before < Enum.sum(for {tasks, workers} <- free, do: room(tasks, workers)) do
          {tasks, _} = pick(free)
          Registry.unregister(__MODULE__, :queue)
          {:ok, _} = Registry.register(__MODULE__, tasks, key)
          tasks
        end
      end,
      [node()]
    )
  end

  # The parts that a node can take now: one for each of its cores (2
  # workers of `World.Crew`), at least one, less its parts in work.
  defp room(tasks, workers), do: max(div(workers, 2), 1) - busy(tasks)

  defp pick(nodes), do: Enum.min_by(nodes, fn {tasks, workers} -> busy(tasks) / workers end)

  defp try_on(key, tasks) do
    {:ok, _} = Registry.register(__MODULE__, tasks, key)
    run_on(key, tasks)
  end

  # The make of a part on a node, which has the part in its work (its
  # registration): `{:ok, result}`, `:gone` when the node went away or
  # stopped its tasks (the end of a shift), or `{:failed, reason}` when
  # the make raised there.
  defp run_on(key, tasks) do
    try do
      task = Task.Supervisor.async_nolink(tasks, __MODULE__, :make, [key, Queue.projects(key)])

      case Task.yield(task, :infinity) do
        {:ok, done} -> {:ok, done}
        {:exit, reason} -> if gone?(reason), do: :gone, else: {:failed, reason}
      end
    catch
      # (The supervisor of the node is not there: the node went away.)
      :exit, _ -> :gone
    after
      Registry.unregister(__MODULE__, tasks)
    end
  end

  defp gone?(reason),
    do:
      reason in [:noconnection, :noproc, :shutdown, :killed] or
        match?({tag, _} when tag in [:shutdown, :nodedown], reason)
end
