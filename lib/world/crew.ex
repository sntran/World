defmodule World.Crew do
  @moduledoc """
  The crews of the sites of the node
  (`docs/plans/0012-a-world-of-sites.md`, D6 to D8).

  A site is a process with work in many small jobs: the hand of a
  sculptor that makes a sculpture. The node has workers (processes; as
  many as two for each scheduler by default: a worker waits at times
  for memory or for the collector). A site gives its jobs with `map/3`,
  and the workers of its crew do them: no stage of a sculpture starts
  processes of its own.

  The node gives its workers to the sites that have jobs now, in equal
  parts: with one site, all the workers are its crew; with two sites,
  half each; and so on. A site with fewer jobs than its part takes only
  as many workers as it has jobs, and the others get the rest. A change
  of the sites moves a worker when it ends its job.

  ## How a job goes

  - The site tells the crews how many jobs it has (`map/3`). The crews
    tell some workers to serve it.
  - A worker that serves a site asks the site for a job, does it, gives
    the result to the site and asks again. The function of the jobs goes
    to a worker one time for each `map/3`. So the items do not go
    through a third process, and a site has no more than its jobs in
    work.
  - When the site has no more jobs to give, the worker tells the crews,
    which give it to another site.
  - A job that raises stops the `map/3` of its site, which raises there.
    A worker that stops (its node went away) gives its job back: the
    site gives the job to the next worker.
  - A site that stops (a stop of its person) stops its jobs in work at
    once: the crews stop the workers that serve it, and start new ones.

  ## More nodes

  A node can join the crews of another node (`join/1`): its workers
  then serve the sites of that node as its own workers do, and its own
  sites get workers from there. The two nodes must have the same code
  (`version/0`): the function of a job goes to a worker of the other
  node, so it must be a function of a module that both have. When the
  other node goes away, the node has its own crews again.

  The options (`config :world, World.Crew, ...`, or the options of
  `start_link/1`):

  - `workers`: the count of workers of this node.
  - `node`: the name of this VM as an Erlang node (with a host), and
    `cookie`: the crews start the node (`World.Epmd` has its port).
  - `join`: the name of another node. The crews join the crews of that
    node, try again each `retry` ms (3,000) while it does not answer,
    and join again when it comes back.
  """
  use GenServer

  @doc false
  def start_link(opts) do
    opts = Keyword.merge(Application.get_env(:world, __MODULE__, []), opts)
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  `fun` of each item, in the order of the items, done by the workers of
  the crew of this process (its site). With no crews (the node does not
  run), or in a worker (a job with jobs of its own), the items are done
  here, one after the other.

  A job that raises (or exits, or throws) stops the others, and `map/3`
  raises the same.
  """
  def map(items, fun, crews \\ __MODULE__) do
    items = Enum.to_list(items)
    pid = GenServer.whereis(crews)

    cond do
      items == [] -> []
      pid == nil or Process.get(:world_crew_worker) -> Enum.map(items, fun)
      true -> site(pid, items, fun)
    end
  end

  @doc """
  The crews now: `%{workers: count, nodes: [node], sites: [%{site: pid,
  jobs: count, workers: count, crew: [pid]}]}`. `jobs` is the count of
  jobs of the `map/3` of a site now, `crew` the workers that serve it.
  """
  def state(crews \\ __MODULE__), do: GenServer.call(crews, :state)

  @doc """
  Join the crews of another node: the workers of this node serve the
  sites of that node, and the sites of this node get their workers from
  there. `:ok`, or `{:error, reason}` (`:code` when the two nodes do not
  have the same code, `:down` when the node does not answer).
  """
  def join(node, crews \\ __MODULE__), do: GenServer.call(crews, {:join, node}, 30_000)

  @doc """
  The crews for the census of the node (`World.census/0`), as data:
  `%{"workers" => count, "nodes" => [name], "sites" => [%{"site" =>
  name, "jobs" => count, "workers" => count}]}`.
  """
  def census(crews \\ __MODULE__) do
    %{workers: workers, nodes: nodes, sites: sites} = state(crews)

    %{
      "workers" => workers,
      "nodes" => Enum.map(nodes, &Atom.to_string/1),
      "sites" =>
        for(
          s <- sites,
          do: %{"site" => s.site |> :erlang.pid_to_list() |> to_string(), "jobs" => s.jobs, "workers" => s.workers}
        )
    }
  end

  @doc "Leave the crews of the other node: this node has its own crews again."
  def leave(crews \\ __MODULE__), do: GenServer.call(crews, :leave)

  @doc "A hash of the code of World on this node: two nodes with the same hash can share their crews."
  def version do
    {:ok, modules} = :application.get_key(:world, :modules)
    :erlang.md5(for m <- Enum.sort(modules), do: m.module_info(:md5))
  end

  # --- A site: the process that calls map/3 ------------------------------------

  defp site(crews, items, fun) do
    ref = make_ref()
    count = length(items)
    lead = GenServer.call(crews, {:demand, self(), ref, count}, :infinity)

    # The jobs that wait, the jobs in work (a worker to its job) and the results.
    s = %{
      ref: ref,
      fun: fun,
      crews: crews,
      lead: lead,
      watch: Process.monitor(lead),
      queue: Enum.with_index(items),
      out: %{},
      done: %{},
      left: count
    }

    try do
      give(s)
    after
      GenServer.cast(lead, {:demand, self(), ref, 0})
    end
  end

  defp give(%{left: 0, done: done, watch: watch}) do
    Process.demonitor(watch, [:flush])
    done |> Enum.sort() |> Enum.map(&elem(&1, 1))
  end

  defp give(%{ref: ref, watch: watch} = s) do
    receive do
      # A worker asks for a job (`new?`: it does not have the function of this map).
      {:ready, ^ref, worker, new?} when not is_map_key(s.out, worker) ->
        case s.queue do
          [{item, i} | rest] ->
            send(worker, {:job, self(), ref, i, item, if(new?, do: s.fun)})
            give(%{s | queue: rest, out: Map.put(s.out, worker, {i, item, Process.monitor(worker)})})

          [] ->
            send(worker, {:none, ref})
            give(s)
        end

      # (A worker asks one time for each job: a second time has no answer.)
      {:ready, ^ref, _worker, _new?} ->
        give(s)

      # A worker asks for a job of a map that is done.
      {:ready, old, worker, _new?} ->
        send(worker, {:none, old})
        give(s)

      {:done, ^ref, worker, i, result} ->
        {{^i, _, mon}, out} = Map.pop!(s.out, worker)
        Process.demonitor(mon, [:flush])
        give(%{s | out: out, done: Map.put(s.done, i, result), left: s.left - 1})

      {:failed, ^ref, _worker, kind, reason, stack} ->
        Process.demonitor(watch, [:flush])
        :erlang.raise(kind, reason, stack)

      # The worker has another site now: the job waits again.
      {:back, ^ref, worker, i, :moved} ->
        {{^i, item, mon}, out} = Map.pop!(s.out, worker)
        Process.demonitor(mon, [:flush])
        again(%{s | out: out, queue: [{item, i} | s.queue]})

      # The worker does not have the function (its crews changed): the job again, with the function.
      {:back, ^ref, worker, i, :function} ->
        {^i, item, _mon} = Map.fetch!(s.out, worker)
        send(worker, {:job, self(), ref, i, item, s.fun})
        give(s)

      # (Words about a map that is done: a map that a job stopped.)
      {:done, _old, _worker, _i, _result} ->
        give(s)

      {:failed, _old, _worker, _kind, _reason, _stack} ->
        give(s)

      {:back, _old, _worker, _i, _why} ->
        give(s)

      {:DOWN, ^watch, :process, _, _} ->
        # The crews that had the site went away (another node): the crews of this node have it now.
        lead = GenServer.call(s.crews, {:demand, self(), ref, length(s.queue) + map_size(s.out)}, :infinity)
        give(%{s | lead: lead, watch: Process.monitor(lead)})

      # The worker went away with a job: the job waits again.
      {:DOWN, mon, :process, worker, _} when is_map_key(s.out, worker) ->
        {{i, item, ^mon}, out} = Map.pop!(s.out, worker)
        again(%{s | out: out, queue: [{item, i} | s.queue]})
    end
  end

  # A job waits again: the crews know that the site has jobs to give.
  defp again(s) do
    GenServer.cast(s.lead, {:demand, self(), s.ref, length(s.queue)})
    give(s)
  end

  # --- A worker ------------------------------------------------------------------

  @doc false
  def worker(crews) do
    Process.put(:world_crew_worker, true)
    Process.set_label({:crew, node()})
    work(%{lead: crews, site: nil, ref: nil, fun: nil})
  end

  # A worker does the orders of its crews and the jobs of its site, as
  # they come: an order moves it to a site (it asks that site for a
  # job); a job of its site is done, and it asks again; a job of a site
  # that it left goes back to that site.
  defp work(s) do
    receive do
      {:serve, site, ref, lead} when ref != s.ref ->
        send(site, {:ready, ref, self(), true})
        work(%{lead: lead, site: site, ref: ref, fun: nil})

      {:serve, _site, _ref, _lead} ->
        work(s)

      {:job, site, ref, i, _item, nil} when ref == s.ref and s.fun == nil ->
        send(site, {:back, ref, self(), i, :function})
        work(s)

      {:job, site, ref, i, item, new} when ref == s.ref ->
        fun = new || s.fun

        try do
          send(site, {:done, ref, self(), i, fun.(item)})
        catch
          kind, reason -> send(site, {:failed, ref, self(), kind, reason, __STACKTRACE__})
        end

        send(site, {:ready, ref, self(), false})
        work(%{s | fun: fun})

      {:job, site, ref, i, _item, _new} ->
        send(site, {:back, ref, self(), i, :moved})
        work(s)

      {:none, ref} when ref == s.ref ->
        send(s.lead, {:free, self(), ref})
        work(%{s | site: nil, ref: nil, fun: nil})

      {:none, _ref} ->
        work(s)

      {:crews, lead} ->
        work(%{lead: lead, site: nil, ref: nil, fun: nil})
    end
  end

  # --- The crews -------------------------------------------------------------------

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    count = Keyword.get(opts, :workers, 2 * System.schedulers_online())

    {:ok,
     %{
       count: count,
       # The workers of this node, and all the workers that these crews
       # give to sites (with those of the nodes that joined): each to
       # the site that it serves, or nil.
       own: for(_ <- 1..count//1, do: spawn_link(__MODULE__, :worker, [self()])),
       workers: %{},
       # The sites with jobs: each to its map now (a reference) and its count of jobs; in the order that they came.
       sites: %{},
       order: [],
       # The crews of another node that these crews joined, and the crews that joined these.
       lead: nil,
       guests: %{},
       # The hash of the code (an option for a test of two codes).
       version: Keyword.get_lazy(opts, :version, &version/0),
       # The node to join, and the wait before the next try.
       join: opts[:join],
       retry: Keyword.get(opts, :retry, 3_000)
     }
     |> own(), {:continue, {:node, opts[:node], opts[:cookie], Keyword.get(opts, :distribution, &Node.start/2)}}}
  end

  # This VM as an Erlang node, then the crews of the other node.
  @impl true
  def handle_continue({:node, name, cookie, start}, s) do
    if name, do: {:ok, _} = start.(name, :longnames)
    if cookie != nil and Node.alive?(), do: Node.set_cookie(cookie)

    if s.join, do: send(self(), :join)
    {:noreply, s}
  end

  # The workers of this node serve these crews.
  defp own(s), do: %{s | workers: Map.merge(s.workers, Map.new(s.own, &{&1, nil}))}

  @impl true
  def handle_call({:demand, site, ref, count}, from, %{lead: lead} = s) when lead != nil do
    # The crews of the other node have the sites of this node.
    GenServer.reply(from, lead)
    send(lead, {:demand, site, ref, count})
    {:noreply, s}
  end

  def handle_call({:demand, site, ref, count}, _from, s), do: {:reply, self(), share(demand(s, site, ref, count))}

  def handle_call(:state, _from, s) do
    sites =
      for site <- s.order, {_ref, jobs} = s.sites[site] do
        crew = for {w, ^site} <- s.workers, do: w
        %{site: site, jobs: jobs, workers: length(crew), crew: Enum.sort(crew)}
      end

    nodes = s.workers |> Map.keys() |> Enum.map(&node/1) |> Enum.uniq() |> Enum.sort()
    {:reply, %{workers: map_size(s.workers), nodes: nodes, sites: sites}, s}
  end

  def handle_call({:join, node}, _from, s) do
    {result, s} = joined(s, node)
    {:reply, result, s}
  end

  def handle_call({:guest, crews, workers, version}, _from, s) do
    if version == s.version do
      Process.monitor(crews)
      for w <- workers, do: Process.monitor(w)
      s = %{s | guests: Map.put(s.guests, crews, workers), workers: Map.merge(s.workers, Map.new(workers, &{&1, nil}))}
      {:reply, {:ok, self()}, share(s)}
    else
      {:reply, {:error, :code}, s}
    end
  end

  def handle_call(:leave, _from, %{lead: nil} = s), do: {:reply, :ok, s}

  def handle_call(:leave, _from, s) do
    send(s.lead, {:gone, self()})
    # (A node that leaves does not join again by itself.)
    {:reply, :ok, home(%{s | join: nil})}
  end

  @impl true
  def handle_cast({:demand, site, ref, count}, s), do: {:noreply, share(demand(s, site, ref, count))}

  @impl true
  def handle_info({:demand, site, ref, count}, s), do: {:noreply, share(demand(s, site, ref, count))}

  # The crews of the node of the options: a try now, and the next try later with no answer.
  def handle_info(:join, %{lead: nil, join: node} = s) when node != nil do
    case joined(s, node) do
      {:ok, s} ->
        {:noreply, s}

      {{:error, _}, s} ->
        Process.send_after(self(), :join, s.retry)
        {:noreply, s}
    end
  end

  def handle_info(:join, s), do: {:noreply, s}

  # A worker with no more jobs at its site: it is free for another site.
  def handle_info({:free, worker, ref}, s) do
    with %{^worker => site} when site != nil <- s.workers,
         %{^site => {^ref, _}} <- s.sites do
      # (The site has no more jobs to give for this map: it needs no more workers.)
      {:noreply, share(%{s | workers: Map.put(s.workers, worker, nil), sites: Map.put(s.sites, site, {ref, 0})})}
    else
      # (A word about a map that is done.)
      _ -> {:noreply, s}
    end
  end

  def handle_info({:gone, crews}, s), do: {:noreply, share(without(s, crews))}

  # A new worker of crews that joined (in the place of one that stopped).
  def handle_info({:new, crews, worker}, s) do
    case s.guests do
      %{^crews => workers} ->
        Process.monitor(worker)
        s = %{s | guests: Map.put(s.guests, crews, [worker | workers]), workers: Map.put(s.workers, worker, nil)}
        {:noreply, share(s)}

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:DOWN, _, :process, pid, _}, s) do
    cond do
      pid == s.lead ->
        {:noreply, share(home(s))}

      is_map_key(s.guests, pid) ->
        {:noreply, share(without(s, pid))}

      is_map_key(s.sites, pid) ->
        # The site stopped (a stop of its person): its jobs in work stop
        # now, with their workers. New workers take their places.
        for {w, ^pid} <- s.workers, do: Process.exit(w, :kill)
        {:noreply, share(demand(s, pid, nil, 0))}

      true ->
        {:noreply, share(%{s | workers: Map.delete(s.workers, pid)})}
    end
  end

  # A worker of this node stopped: a new one takes its place.
  def handle_info({:EXIT, pid, _reason}, s) do
    if pid in s.own do
      new = spawn_link(__MODULE__, :worker, [s.lead || self()])
      s = %{s | own: [new | List.delete(s.own, pid)]}
      # (The crews of the other node get the new worker in the place of the old one.)
      if s.lead, do: send(s.lead, {:new, self(), new})
      s = if s.lead, do: s, else: %{s | workers: s.workers |> Map.delete(pid) |> Map.put(new, nil)}
      {:noreply, share(s)}
    else
      {:noreply, s}
    end
  end

  @impl true
  def terminate(_reason, s), do: for(w <- s.own, do: Process.exit(w, :kill))

  # The crews of this node again, after the crews of another node. (With
  # a node to join in the options, the next try comes.)
  defp home(s) do
    for w <- s.own, do: send(w, {:crews, self()})
    if s.join, do: Process.send_after(self(), :join, s.retry)
    own(%{s | lead: nil})
  end

  # Join the crews of a node: `{:ok, state}` or `{{:error, reason}, state}`.
  defp joined(s, node) do
    # (The crews of a node by its name; in a test, crews of this node by their process.)
    crews = if is_atom(node), do: {__MODULE__, node}, else: node

    answer =
      try do
        GenServer.call(crews, {:guest, self(), s.own, s.version}, 10_000)
      catch
        :exit, _ -> {:error, :down}
      end

    case answer do
      {:ok, lead} ->
        Process.monitor(lead)
        for w <- s.own, do: send(w, {:crews, lead})
        # (The sites of this node go on with the crews of the other node at their next map.)
        {:ok, %{s | lead: lead, workers: Map.drop(s.workers, s.own)}}

      {:error, reason} ->
        {{:error, reason}, s}
    end
  end

  # The crews of a node that joined went away: its workers too.
  defp without(s, crews) do
    {workers, guests} = Map.pop(s.guests, crews, [])
    %{s | guests: guests, workers: Map.drop(s.workers, workers)}
  end

  # The jobs of a site now: a new map, or (with a count of 0) no map.
  defp demand(s, site, ref, 0) do
    case s.sites do
      # (The end of a map that is not the map of the site now.)
      %{^site => {other, _}} when ref != nil and other != ref ->
        s

      _ ->
        workers = Map.new(s.workers, fn {w, at} -> {w, if(at == site, do: nil, else: at)} end)
        %{s | sites: Map.delete(s.sites, site), order: List.delete(s.order, site), workers: workers}
    end
  end

  defp demand(s, site, ref, count) do
    unless is_map_key(s.sites, site), do: Process.monitor(site)
    order = if site in s.order, do: s.order, else: s.order ++ [site]

    # (The workers of the map before this one of the site get the new one.)
    workers =
      case s.sites do
        %{^site => {^ref, _}} -> s.workers
        _ -> Map.new(s.workers, fn {w, at} -> {w, if(at == site, do: nil, else: at)} end)
      end

    %{s | sites: Map.put(s.sites, site, {ref, count}), order: order, workers: workers}
  end

  # The workers to the sites, in equal parts: each site has a part of
  # the workers (the first sites one more when the workers do not go
  # evenly), but not more than its jobs; the workers that are left go to
  # the sites with more jobs. A worker of a site with too many goes to a
  # site with too few (at the end of its job); then the free workers go.
  defp share(s) do
    wanted = s.order |> Enum.map(&{&1, elem(s.sites[&1], 1)}) |> Enum.filter(&(elem(&1, 1) > 0))
    parts = parts(wanted, map_size(s.workers), %{})
    has = Enum.frequencies(for {_, site} <- s.workers, site != nil, do: site)

    # The sites with too few workers, each as many times as it needs one.
    need = for {site, _jobs} <- wanted, _ <- 1..max(parts[site] - Map.get(has, site, 0), 0)//1, do: site

    # The workers that can go: the free ones first, then those of the sites with too many.
    free = for {w, nil} <- s.workers, do: w

    extra =
      for {site, count} <- has,
          over = count - Map.get(parts, site, 0),
          over > 0,
          w <-
            s.workers |> Enum.filter(&(elem(&1, 1) == site)) |> Enum.map(&elem(&1, 0)) |> Enum.sort() |> Enum.take(over),
          do: w

    workers =
      Enum.zip(Enum.sort(free) ++ extra, need)
      |> Enum.reduce(s.workers, fn {w, site}, workers ->
        send(w, {:serve, site, elem(s.sites[site], 0), self()})
        Map.put(workers, w, site)
      end)

    %{s | workers: workers}
  end

  # The part of each site: the workers by the sites, at most its jobs,
  # and the rest again to the sites that can take more.
  defp parts([], _workers, parts), do: parts

  defp parts(wanted, workers, parts) do
    each = div(workers, length(wanted))
    more = rem(workers, length(wanted))

    given =
      wanted
      |> Enum.with_index()
      |> Enum.map(fn {{site, jobs}, i} -> {site, jobs, min(jobs, each + if(i < more, do: 1, else: 0))} end)

    parts = Enum.reduce(given, parts, fn {site, _, n}, parts -> Map.update(parts, site, n, &(&1 + n)) end)
    left = workers - Enum.sum(for {_, _, n} <- given, do: n)
    open = for {site, jobs, n} <- given, jobs > n, do: {site, jobs - n}

    if left > 0 and open != [], do: parts(open, left, parts), else: parts
  end
end
