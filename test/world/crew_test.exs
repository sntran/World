defmodule World.CrewTest do
  # The crews of the sites of the node: streams of tasks (plan 0012, D6
  # to D8; R5). The test counts the sites of the node, so it does not
  # run with the others.
  use ExUnit.Case, async: false

  alias World.Crew

  @tasks World.Crew.Tasks

  # Each test starts with no site and no task of a test before it.
  setup do
    wait = fn wait ->
      if Crew.state().sites == 0 and Task.Supervisor.children(@tasks) == [], do: :ok, else: wait.(wait)
    end

    wait.(wait)
  end

  # The most tasks of a stream that work at one time: each job says when it starts and when it ends.
  defp counter, do: :counters.new(2, [:atomics])

  defp job(counter, ms) do
    fn i ->
      :counters.add(counter, 1, 1)
      now = :counters.get(counter, 1)
      # (The most so far: a job writes it when it sees more.)
      if now > :counters.get(counter, 2), do: :counters.put(counter, 2, now)
      Process.sleep(ms)
      :counters.sub(counter, 1, 1)
      i
    end
  end

  defp most(counter), do: :counters.get(counter, 2)

  # A site in a process of its own: it tells the test the result of its stream.
  defp site(name, fun) do
    test = self()
    spawn(fn -> send(test, {:mapped, name, fun.()}) end)
  end

  test "a stream: the results in the order of the items, each job in a task of the node; no items; a stream in a job" do
    me = self()
    assert Crew.map([], fn _ -> flunk("no job") end) == []
    done = Crew.map(1..200, fn i -> {i * i, self()} end)
    assert Enum.map(done, &elem(&1, 0)) == Enum.map(1..200, &(&1 * &1))
    tasks = done |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    # One light process for each job, not this one.
    assert length(tasks) == 200 and me not in tasks
    assert Crew.map([:a], &{&1, 1}) == [{:a, 1}]
    # A job with jobs of its own does them in its task, one after the other.
    [{inner, task}] = Crew.map([1], fn _ -> {Crew.map(1..3, fn i -> {i, self()} end), self()} end)
    assert inner == for(i <- 1..3, do: {i, task})
    # The crews after the streams: no site, and no task.
    assert Crew.state() == %{workers: 2 * System.schedulers_online(), nodes: [node()], sites: 0}

    assert Crew.census() == %{
             "workers" => 2 * System.schedulers_online(),
             "nodes" => [Atom.to_string(node())],
             "sites" => 0
           }

    assert Task.Supervisor.children(@tasks) == []
  end

  test "the tasks of a stream are linked to its site: a job that raises stops the site, and a site that stops, stops its tasks" do
    test = self()

    # A job raises: the site ends with that, and the other tasks of its stream end too.
    {raiser, ref} =
      spawn_monitor(fn ->
        Crew.map(1..50, fn i ->
          send(test, {:task, self()})
          if i == 7, do: raise(ArgumentError, "no"), else: Process.sleep(5_000)
        end)
      end)

    assert_receive {:DOWN, ^ref, :process, ^raiser, {%ArgumentError{message: "no"}, _}}, 2_000
    tasks = for _ <- 1..3, do: receive(do: ({:task, pid} -> pid))
    refs = for pid <- tasks, do: Process.monitor(pid)
    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, _})

    # A site with long jobs stops: its tasks stop at once.
    site =
      spawn(fn ->
        Crew.map(1..50, fn _ ->
          send(test, {:long, self()})
          Process.sleep(60_000)
        end)
      end)

    tasks = for _ <- 1..2, do: receive(do: ({:long, pid} -> pid))
    refs = Enum.map(tasks, &Process.monitor/1)
    Process.exit(site, :kill)
    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, _}, 100)
    # The node has no site and no task after that, and the next stream works.
    wait = fn wait ->
      if Crew.state().sites == 0 and Task.Supervisor.children(@tasks) == [], do: :ok, else: wait.(wait)
    end

    assert wait.(wait) == :ok
    assert Crew.map(1..10, &(&1 * 2)) == Enum.map(1..10, &(&1 * 2))
  end

  test "a stream has its part of the workers: all with one site, half with two, at least one (R5)" do
    # One site: all the workers at one time, and not more.
    alone = counter()
    assert Crew.map(1..40, job(alone, 20), workers: 8) == Enum.to_list(1..40)
    assert most(alone) == 8

    # Two sites at one time: the stream of each has half of the workers.
    {a, b} = {counter(), counter()}
    site(:a, fn -> Crew.map(1..40, job(a, 30), workers: 8) end)
    wait = fn wait -> if Crew.state().sites == 1, do: :ok, else: wait.(wait) end
    wait.(wait)
    # (The first site has all the workers for the stream that it has now; its next stream has half.)
    site(:b, fn -> Crew.map(1..24, job(b, 30), workers: 8) end)
    assert_receive {:mapped, :b, done_b}, 5_000
    assert done_b == Enum.to_list(1..24) and most(b) == 4
    assert_receive {:mapped, :a, done_a}, 5_000
    assert done_a == Enum.to_list(1..40) and most(a) == 8
    again = counter()
    site(:b2, fn -> Crew.map(1..400, job(again, 30), workers: 8) end)
    wait.(wait)
    # The first site starts its next stream while the other site works: half.
    next = counter()
    assert Crew.map(1..16, job(next, 20), workers: 8) == Enum.to_list(1..16)
    assert most(next) == 4
    assert_receive {:mapped, :b2, _}, 30_000

    # More sites than workers: one task at a time for each stream that starts with the others.
    few = counter()
    for i <- 1..3, do: site({:few, i}, fn -> Crew.map(1..10, job(few, 20), workers: 2) end)
    for i <- 1..3, do: assert_receive({:mapped, {:few, ^i}, _}, 5_000)
    # (The stream that starts first, alone, has the two workers.)
    assert most(few) in 2..4
  end

  # The supervisor of the task that a job runs in.
  defp parent(_item), do: hd(Process.get(:"$ancestors"))

  test "a stream gives jobs to the tasks of another supervisor by its workers; the jobs that it does not end are done here" do
    {:ok, other} = Task.Supervisor.start_link()
    here = Process.whereis(@tasks)
    # 3 workers here and 1 there: three of each four jobs here.
    done = Crew.map(1..400, &{&1, parent(&1)}, workers: 3, others: [{other, 1}])
    assert Enum.map(done, &elem(&1, 0)) == Enum.to_list(1..400)
    assert Enum.frequencies_by(done, &elem(&1, 1)) == %{here => 300, other => 100}
    # Fewer jobs than workers: the other supervisor has none.
    assert Crew.map(1..2, &{&1, parent(&1)}, workers: 3, others: [{other, 1}]) == [{1, here}, {2, here}]

    # The other supervisor stops in the middle: each job is done, in order.
    Process.flag(:trap_exit, true)
    spawn(fn -> Process.sleep(60) && Process.exit(other, :kill) end)

    done =
      Crew.map(1..60, fn i -> Process.sleep(10) && {i, parent(i)} end, workers: 2, others: [{other, 2}])

    assert Enum.map(done, &elem(&1, 0)) == Enum.to_list(1..60)
    assert Enum.all?(done, fn {_, sup} -> sup in [here, other] end)
    # A supervisor that is not there: all the jobs here.
    done = Crew.map(1..20, &{&1, parent(&1)}, workers: 2, others: [{:no_supervisor_with_this_name, 2}])
    assert done == for(i <- 1..20, do: {i, here})

    # A job that raises there is done again here, and raises here: the site ends with that.
    {:ok, other} = Task.Supervisor.start_link()

    {raiser, ref} =
      spawn_monitor(fn ->
        Crew.map(1..8, fn i -> if(i == 4, do: raise(ArgumentError, "no"), else: i) end,
          workers: 1,
          others: [{other, 3}]
        )
      end)

    assert_receive {:DOWN, ^ref, :process, ^raiser, {%ArgumentError{message: "no"}, _}}, 2_000
  end

  # Crews with a name of their own (the streams read the crews of a name).
  defp crews(name, opts), do: start_supervised!({Crew, [name: name] ++ opts}, id: name)

  test "the log of a join that fails says why: other code, or no answer" do
    me = node()

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        g = crews(:crew_test_g, join: me, retry: 10, version: "another code", connect: fn _ -> true end)
        h = crews(:crew_test_h, join: :nobody@nowhere, retry: 10, connect: fn _ -> true end)
        # (A crew that joins loads the code first: a wait until each try has its reason.)
        wait = fn wait ->
          if :sys.get_state(g).why == :code and :sys.get_state(h).why == :down,
            do: :ok,
            else: Process.sleep(5) && wait.(wait)
        end

        wait.(wait)
      end)

    assert log =~ "did not join #{me}: the other node has other code"
    assert log =~ "did not join nobody@nowhere: the other node did not answer"
  end

  test "the nodes that share their workers: a node with the same code, a try again, a node that goes and comes back" do
    me = node()
    assert byte_size(Crew.version()) == 16 and Crew.hello(Crew.version()) == {:ok, 2 * System.schedulers_online()}
    assert Crew.hello("another code") == {:error, :code}

    # (In the place of the connect of Erlang: this node is the other node of the test, and these crews have another name.)
    c = crews(:crew_test_a, workers: 3, connect: fn _ -> true end, me: fn -> :this@host end)
    assert Crew.state(:crew_test_a) == %{workers: 3, nodes: [me], sites: 0}
    assert Crew.join(me, :crew_test_a) == :ok
    assert Crew.state(:crew_test_a).nodes == [me, me]
    # A stream of these crews: its jobs go to the supervisor of the tasks here, and to the one of the other node.
    assert Crew.map(1..100, &(&1 + 1), crews: :crew_test_a) == Enum.to_list(2..101)
    assert Crew.leave(me, :crew_test_a) == :ok
    assert Crew.state(:crew_test_a).nodes == [me]

    # A node that does not connect, a node that does not answer, a node with another code.
    assert Crew.join(me, crews(:crew_test_b, connect: fn _ -> false end)) == {:error, :down}
    assert Crew.join(:nobody@nowhere, c) == {:error, :down}
    assert Crew.join(me, crews(:crew_test_c, version: "another code", connect: fn _ -> true end)) == {:error, :code}

    # A node of the options: no connect at first, then it comes; it goes away, and comes back.
    {:ok, tries} = Agent.start_link(fn -> 0 end)
    connect = fn _ -> Agent.get_and_update(tries, &{&1 >= 3, &1 + 1}) end
    wait = fn wait, done? -> if done?.(), do: :ok, else: Process.sleep(5) && wait.(wait, done?) end

    {d, log} =
      ExUnit.CaptureLog.with_log(fn ->
        d = crews(:crew_test_d, join: me, retry: 10, connect: connect)
        wait.(wait, fn -> Crew.state(:crew_test_d).nodes == [me, me] end)
        d
      end)

    assert Agent.get(tries, & &1) == 4
    # (The log says the reason of the tries that failed once, and the join.)
    assert length(String.split(log, "did not join")) == 2 and log =~ "no connection" and log =~ "joined #{me}"
    # (A node that joins has each module of World loaded before its first try: the atoms of the code exist.)
    {:ok, modules} = :application.get_key(:world, :modules)
    assert Enum.all?(modules, &:code.is_loaded/1)
    send(d, {:nodedown, me, node_type: :visible})
    wait.(wait, fn -> Agent.get(tries, & &1) == 5 end)
    wait.(wait, fn -> Crew.state(:crew_test_d).nodes == [me, me] end)
    # (A try when the node shares its workers already changes nothing; any other word too.)
    send(d, :join)
    send(d, :hello)
    assert Crew.state(:crew_test_d).nodes == [me, me]
    # Another node goes: nothing to try. A node comes by itself: it shares when it has the code.
    send(c, {:nodedown, :other@host, node_type: :visible})
    send(c, {:nodeup, me, node_type: :hidden})
    wait.(wait, fn -> Crew.state(:crew_test_a).nodes == [me, me] end)
    # (The start of the distribution of this node: it does not share with itself.)
    h = crews(:crew_test_h, me: fn -> me end, connect: fn _ -> true end)
    send(h, {:nodeup, me, node_type: :visible})
    assert Crew.state(:crew_test_h).nodes == [me]
    # A leave of the node of the options: no more tries.
    assert Crew.leave(me, :crew_test_d) == :ok
    Process.sleep(40)
    assert Crew.state(:crew_test_d).nodes == [me]

    # A node that greets these crews: they greet it too, and it shares its workers (once).
    assert Crew.hello(Crew.version(), :other@host, :crew_test_d) == {:ok, 2 * System.schedulers_online()}
    send(d, {:hello, me})
    wait.(wait, fn -> Crew.state(:crew_test_d).nodes == [me, me] end)
    send(d, {:hello, me})
    assert Crew.state(:crew_test_d).nodes == [me, me]

    # At their end, the crews take away what their streams read: the crews by default.
    stop_supervised!(:crew_test_d)
    assert Crew.state(:crew_test_d) == %{workers: 2 * System.schedulers_online(), nodes: [me], sites: 0}
  end

  test "the crews of the edge lend no workers and give no jobs: the nodes that join take whole parts" do
    me = node()
    e = crews(:crew_test_f, lend: false, borrow: false, connect: fn _ -> true end)
    # (This node answers for the crews by default, which lend their workers.)
    assert Crew.join(me, :crew_test_f) == :ok
    assert Crew.parts(:crew_test_f) == [{{World.Crew.Tasks, me}, 2 * System.schedulers_online()}]
    assert Crew.state(:crew_test_f).nodes == [me, me]
    # Its streams give no jobs to the other node: all are here.
    assert Crew.map(1..10, &(&1 * 2), crews: :crew_test_f) == Enum.to_list(2..20//2)
    # A node that joins these crews gets no workers: the edge takes no parts and no jobs.
    assert Crew.hello(Crew.version(), nil, :crew_test_f) == {:ok, 0}
    g = crews(:crew_test_g, connect: fn _ -> true end)
    send(g, {:hello, me})
    assert Crew.leave(me, :crew_test_g) == :ok
    assert Crew.parts(:crew_test_g) == []
    assert Process.alive?(e)
  end

  test "the options of the crews from the environment; the crews start the node with their name" do
    assert World.Supervisor.crews(%{}) == []

    assert World.Supervisor.crews(%{"WORLD_NODE" => "a4371@127.0.0.1", "WORLD_COOKIE" => "c", "WORLD_JOIN" => "b@h"}) ==
             [node: :"a4371@127.0.0.1", cookie: :c, join: :b@h]

    assert World.Supervisor.crews(%{"WORLD_LABOUR" => "parts"}) == [lend: false, borrow: false]

    # (Here: a function in the place of the start of a node.)
    me = self()

    started = fn name, kind ->
      send(me, {:node, name, kind})
      {:ok, me}
    end

    crews(:crew_test_e, workers: 1, node: :"a4371@127.0.0.1", cookie: Node.get_cookie(), distribution: started)
    assert_receive {:node, :"a4371@127.0.0.1", :longnames}
    assert Crew.state(:crew_test_e).workers == 1
    assert %{"crews" => %{"workers" => _, "nodes" => [_], "sites" => _}, "people" => _} = World.census()
  end
end
