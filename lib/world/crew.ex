defmodule World.Crew do
  @moduledoc """
  The crews of the sites of the node
  (`docs/plans/0012-a-world-of-sites.md`, D6 to D8).

  A site is a process with work in many small jobs: the hand of a
  sculptor that makes a sculpture. Each stage of that work is a stream
  of tasks (`Task.Supervisor.async_stream/4`): one light process for
  each job, and some of them at one time. `map/3` is that stream. The
  tasks of a site are its crew.

  The node has workers: the tasks that it runs at one time for all its
  sites (two for each scheduler by default: a task waits at times for
  memory or for the collector). A stream of a site runs its part of
  them at one time: all the workers with one site, half with two sites,
  and so on. The part is counted at the start of each stream (a stage
  is short), from the sites with a stream then.

  The tasks of a stream are linked to its site: a site that stops (a
  stop of its person) stops its tasks at once, and a task that raises
  stops its site, as in each stream of tasks.

  ## More nodes

  This VM can be an Erlang node (the option `node`), and connect to
  another node (the option `join`, or `join/2`). Two nodes that are
  connected, with the same code (`version/0`), share their workers: a
  stream of a site gives a part of its jobs to tasks of the supervisor
  of the other node (`Task.Supervisor.async_nolink/4` with
  `{World.Crew.Tasks, node}`), by the workers of each node. The function
  of a job goes to the other node, so it must be a function of a module
  that both have. A job that the other node does not end (the node went
  away) is done on this node: the result of the stream is the same.

  The options (`config :world, World.Crew, ...`, or the options of
  `start_link/1`):

  - `workers`: the count of workers of this node.
  - `node`: the name of this VM as an Erlang node (with a host), and
    `cookie`: the crews start the node (`World.Epmd` has its port).
  - `join`: the name of another node. The crews connect to it, try
    again each `retry` ms (3,000) while it does not answer, and connect
    again when it comes back.
  """
  use GenServer

  @tasks World.Crew.Tasks
  @sites World.Crew.Sites
  # The mark of a process that is a task of a stream: its own streams are done in it.
  @task :world_crew_task

  @doc "The supervisor of the tasks and the list of the sites, which the crews need (`World.Supervisor`)."
  def children, do: [{Task.Supervisor, name: @tasks}, {Registry, keys: :duplicate, name: @sites}]

  @doc false
  def start_link(opts) do
    opts = Keyword.merge(Application.get_env(:world, __MODULE__, []), opts)
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  `fun` of each item, in the order of the items: a stream of tasks of
  the crew of this process (its site). With no crews (the node does not
  run), or in a task (a job with jobs of its own), the items are done
  here, one after the other.

  The options: `crews` (the name of the crews, `World.Crew` by default),
  `workers` (the workers of this node, in place of those of the crews)
  and `others` (the task supervisors of other nodes, each `{supervisor,
  workers}`, in place of those of the crews).
  """
  def map(items, fun, opts \\ []) do
    items = Enum.to_list(items)

    cond do
      items == [] -> []
      Process.get(@task) || Process.whereis(@tasks) == nil -> Enum.map(items, fun)
      true -> site(items, fun, opts)
    end
  end

  @doc """
  The crews now: `%{workers: count, nodes: [node], sites: count}`: the
  workers of this node, this node and the nodes that share their workers
  with it, and the sites with a stream now.
  """
  def state(crews \\ __MODULE__) do
    %{workers: workers, others: others} = shared(crews)
    nodes = Enum.sort([node() | for({{_, node}, _} <- others, do: node)])
    %{workers: workers, nodes: nodes, sites: Registry.count(@sites)}
  end

  @doc "The crews for the census of the node (`World.census/0`), as data: `state/1` with the names of the nodes as text."
  def census(crews \\ __MODULE__) do
    %{workers: workers, nodes: nodes, sites: sites} = state(crews)
    %{"workers" => workers, "nodes" => Enum.map(nodes, &Atom.to_string/1), "sites" => sites}
  end

  @doc """
  Connect to another node and share the workers with it: `:ok`, or
  `{:error, reason}` (`:code` when the two nodes do not have the same
  code, `:down` when the node does not answer).
  """
  def join(node, crews \\ __MODULE__), do: GenServer.call(crews, {:join, node}, 30_000)

  @doc "Share no more workers with a node (and connect no more to it, when it is the node of the options)."
  def leave(node, crews \\ __MODULE__), do: GenServer.call(crews, {:leave, node})

  @doc "A hash of the code of World on this node: two nodes with the same hash can share their workers."
  def version do
    {:ok, modules} = :application.get_key(:world, :modules)
    :erlang.md5(for m <- Enum.sort(modules), do: m.module_info(:md5))
  end

  @doc """
  The answer of this node to a node that asks to share workers:
  `{:ok, workers}` when the code is the same and the crews run here.
  """
  def hello(version, crews \\ __MODULE__) do
    case shared(crews) do
      %{version: ^version, workers: workers} -> {:ok, workers}
      _ -> {:error, :code}
    end
  end

  # What a stream reads of its crews, with no message: the workers of
  # this node, the supervisors of the other nodes, and the hash of the code.
  defp shared(crews), do: :persistent_term.get({__MODULE__, crews}, %{workers: workers(), others: [], version: nil})
  defp workers, do: 2 * System.schedulers_online()

  # --- A stream of a site -----------------------------------------------------------

  defp site(items, fun, opts) do
    # (A site is in the list while it has a stream.)
    new? = Registry.keys(@sites, self()) == []
    if new?, do: {:ok, _} = Registry.register(@sites, :site, nil)

    try do
      crews = shared(Keyword.get(opts, :crews, __MODULE__))
      sites = max(Registry.count(@sites), 1)
      part = fn workers -> max(div(workers, sites), 1) end
      jobs = Enum.with_index(items)

      # A job in a task: the mark of a task, and the place of the item with its result.
      job = fn {item, i} ->
        Process.put(@task, true)
        {i, fun.(item)}
      end

      here = part.(Keyword.get(opts, :workers, crews.workers))

      done =
        case Keyword.get(opts, :others, crews.others) do
          [] -> local(jobs, job, here)
          others -> spread(jobs, job, here, for({tasks, workers} <- others, do: {tasks, part.(workers)}))
        end

      done |> Enum.sort() |> Enum.map(&elem(&1, 1))
    after
      if new?, do: Registry.unregister(@sites, :site)
    end
  end

  # The jobs as a stream of tasks of this node, `part` of them at one
  # time, in any order (a long job does not keep the others back).
  defp local(jobs, job, part) do
    @tasks
    |> Task.Supervisor.async_stream(jobs, job, max_concurrency: part, ordered: false, timeout: :infinity)
    |> Enum.map(fn {:ok, done} -> done end)
  end

  # The jobs to this node and to the other nodes, by the workers of
  # each, all at the same time. The jobs that another node did not end
  # are done here.
  defp spread(jobs, job, here, others) do
    # (The jobs in turn: `here` of them to this node, the next ones to the first other node, and so on.)
    owners = List.to_tuple(List.duplicate(:here, here) ++ for({tasks, part} <- others, _ <- 1..part, do: tasks))
    by = Enum.group_by(jobs, fn {_, i} -> elem(owners, rem(i, tuple_size(owners))) end)
    far = for {tasks, part} <- others, lane <- lanes(Map.get(by, tasks, []), part), do: {remote(tasks, lane, job), lane}
    mine = local(Map.get(by, :here, []), job, here)

    {done, again} =
      Enum.reduce(far, {[], []}, fn {task, lane}, {done, again} ->
        case task && ended(task) do
          {:ok, results} -> {results ++ done, again}
          _ -> {done, lane ++ again}
        end
      end)

    mine ++ done ++ local(again, job, here)
  end

  # The results of a task of another node: `{:ok, results}`, or nil when
  # it did not end (it raised, or its node went away). The task sends
  # its results with its reference, which is its monitor too.
  defp ended(%Task{ref: ref}) do
    receive do
      {^ref, results} ->
        Process.demonitor(ref, [:flush])
        {:ok, results}

      {:DOWN, ^ref, :process, _, _} ->
        nil
    end
  end

  # The jobs of another node in `part` lanes: each lane is a task there,
  # which does its jobs one after the other.
  defp lanes(jobs, part) do
    jobs |> Enum.with_index() |> Enum.group_by(fn {_, k} -> rem(k, part) end, &elem(&1, 0)) |> Map.values()
  end

  # A task of the supervisor of another node for a lane of jobs, or nil
  # when the supervisor is not there. The task is not linked to this
  # process: a node that goes away does not stop the site.
  defp remote(tasks, lane, job) do
    Task.Supervisor.async_nolink(tasks, Enum, :map, [lane, job])
  catch
    :exit, _ -> nil
  end

  # --- The nodes that share their workers -----------------------------------------------

  @impl true
  def init(opts) do
    # (At the end, the crews take away what the streams read.)
    Process.flag(:trap_exit, true)

    s = %{
      name: Keyword.get(opts, :name, __MODULE__),
      workers: Keyword.get(opts, :workers, workers()),
      # The hash of the code (an option for a test of two codes).
      version: Keyword.get_lazy(opts, :version, &version/0),
      # Each node that shares its workers, to the count of them.
      nodes: %{},
      # The node to connect to, the wait before the next try, and the connect of Erlang (an option for a test).
      join: opts[:join],
      retry: Keyword.get(opts, :retry, 3_000),
      connect: Keyword.get(opts, :connect, &Node.connect/1)
    }

    start = Keyword.get(opts, :distribution, &Node.start/2)
    {:ok, share(s), {:continue, {:node, opts[:node], opts[:cookie], start}}}
  end

  # This VM as an Erlang node, then the node of the options.
  @impl true
  def handle_continue({:node, name, cookie, start}, s) do
    if name, do: {:ok, _} = start.(name, :longnames)
    if cookie != nil and Node.alive?(), do: Node.set_cookie(cookie)
    # (The nodes that come and go, from now on.)
    if Node.alive?(), do: :net_kernel.monitor_nodes(true)
    if s.join, do: send(self(), :join)
    {:noreply, s}
  end

  @impl true
  def handle_call({:join, node}, _from, s) do
    {result, s} = if s.connect.(node) == true, do: greet(s, node), else: {{:error, :down}, s}
    {:reply, result, s}
  end

  def handle_call({:leave, node}, _from, s) do
    join = if s.join == node, do: nil, else: s.join
    {:reply, :ok, share(%{s | nodes: Map.delete(s.nodes, node), join: join})}
  end

  # The node of the options: a try now, and the next try later with no answer.
  @impl true
  def handle_info(:join, %{join: node} = s) when node != nil and not is_map_key(s.nodes, node) do
    case s.connect.(node) == true && greet(s, node) do
      {:ok, s} ->
        {:noreply, s}

      _ ->
        Process.send_after(self(), :join, s.retry)
        {:noreply, s}
    end
  end

  def handle_info(:join, s), do: {:noreply, s}

  # A node comes: it shares its workers when it has the same code.
  def handle_info({:nodeup, node}, s), do: {:noreply, elem(greet(s, node), 1)}

  # A node goes: no more of its workers. (The node of the options: the next try comes.)
  def handle_info({:nodedown, node}, s) do
    if node == s.join, do: Process.send_after(self(), :join, s.retry)
    {:noreply, share(%{s | nodes: Map.delete(s.nodes, node)})}
  end

  def handle_info(_other, s), do: {:noreply, s}

  @impl true
  def terminate(_reason, s), do: :persistent_term.erase({__MODULE__, s.name})

  # Ask a node for its workers: `{:ok, state}` or `{{:error, reason}, state}`.
  defp greet(s, node) do
    answer =
      try do
        :erpc.call(node, __MODULE__, :hello, [s.version], 5_000)
      catch
        _, _ -> {:error, :down}
      end

    case answer do
      {:ok, workers} -> {:ok, share(%{s | nodes: Map.put(s.nodes, node, workers)})}
      {:error, reason} -> {{:error, reason}, s}
    end
  end

  # The streams read the crews with no message.
  defp share(s) do
    others = for {node, workers} <- Enum.sort(s.nodes), do: {{@tasks, node}, workers}
    :persistent_term.put({__MODULE__, s.name}, %{workers: s.workers, others: others, version: s.version})
    s
  end
end
