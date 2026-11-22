defmodule World.LabourTest do
  # The labour of the parts: here, on a node of a construction shift, or
  # on another node (in these tests, a supervisor of tasks of this node
  # is in the place of the other node). (Not async: the line of the
  # builds and the store.)
  use ExUnit.Case

  import ExUnit.CaptureLog
  alias World.{Elements, Labour}
  alias World.Elements.Store

  @moduletag timeout: 600_000

  setup_all do
    # The parts of the tests before (the store keeps a part: its key is its data).
    dir =
      Keyword.get(
        Application.get_env(:world, World.Orders.Store, []),
        :dir,
        System.get_env("WORLD_ORDER_DIR", "tmp/orders")
      )

    File.rm_rf!(Path.join(dir, "parts"))
    :ok
  end

  # A group of two people: each person is a part with a recipe.
  @group %{"blueprint" => "exercise", "options" => %{"count" => 1}}

  defp parts(level, group \\ @group) do
    {:ok, list} = Elements.list(group, level)
    for p <- list["parts"], do: {p["key"], JSON.decode!(elem(Store.recipe(p["key"]), 1))}
  end

  # A part at near that is not in the store: a person of a group of `n`
  # (the key of a part has the hash of its order). A group has 12 people
  # at most, so `n` above 12 is a group of `n - 12` with another seed, and
  # above 24 a group of `n - 24` with a third seed.
  defp fresh(n) do
    options =
      cond do
        n > 24 -> %{"count" => n - 24, "seed" => 3}
        n > 12 -> %{"count" => n - 12, "seed" => 2}
        true -> %{"count" => n}
      end

    [{key, recipe} | _] = parts("near", %{@group | "options" => options})
    refute Store.has?(key)
    {key, recipe}
  end

  # A function of the nodes now: each call gives the next list, and the last one again.
  defp turns(lists) do
    {:ok, agent} = Agent.start_link(fn -> lists end)

    fn ->
      Agent.get_and_update(agent, fn
        [one] -> {one, [one]}
        [one | rest] -> {one, rest}
      end)
    end
  end

  test "the parts that fit the edge: a person at mid or far, a part of a sculpture under the limit of faces; the others need a shift at the edge with shifts" do
    [{near, _} | _] = parts("near")
    [{far, _} | _] = parts("far")
    refute Labour.needs_shift?(near)
    Application.put_env(:world, :shifts, true)

    try do
      assert Labour.needs_shift?(near)
      refute Labour.needs_shift?(far)
      refute Labour.needs_shift?(String.duplicate("9", 32))
    after
      Application.delete_env(:world, :shifts)
    end

    assert Labour.fits?(%{"piece" => "leader", "level" => "far"})
    assert Labour.fits?(%{"piece" => "leader", "level" => "mid"})
    refute Labour.fits?(%{"piece" => "leader", "level" => "near"})
    # (A sculpture in one part, and a part of a sculpture at most at the limit of the cut, fit.)
    assert Labour.fits?(%{"node" => "wall", "level" => "far", "tile" => nil})
    # (A part of more faces than a step of the cut fits too: the edge builds it in steps, as a whole
    # model; the two parts of the helicopter of issue #42 have 17,200 and 36,296 faces.)
    assert Labour.edge_faces() == 150_000 and Labour.edge_faces() > Elements.most()
    assert Labour.fits?(%{"node" => "body", "level" => "mid", "tile" => %{"faces" => 36_296}})
    assert Labour.fits?(%{"node" => "wall", "level" => "mid", "tile" => %{"faces" => Labour.edge_faces()}})
    refute Labour.fits?(%{"node" => "wall", "level" => "mid", "tile" => %{"faces" => Labour.edge_faces() + 1}})
    # (A large part of the body of Hải Âu at mid does not fit.)
    refute Labour.fits?(%{"node" => "than", "level" => "mid", "tile" => %{"faces" => 216_190}})
    refute Labour.fits?(%{"order" => "x", "level" => "far"})
  end

  test "with no shifts: a node builds a part by its key, puts it in the store, and gives back only the key" do
    [{key, recipe} | _] = parts("near")
    {:ok, a} = Task.Supervisor.start_link()
    {:ok, b} = Task.Supervisor.start_link()
    assert Labour.build(key, recipe, nodes: [{a, 2}, {b, 2}]) == :stored
    assert Store.has?(key)
    assert Labour.busy(a) == 0 and Labour.busy(b) == 0

    # A node that went away: the part builds on the next node; with no node left, here.
    gone = spawn(fn -> :ok end)
    Process.sleep(10)
    assert Labour.build(key, recipe, nodes: [{gone, 8}, {b, 2}]) == :stored
    assert {:ok, <<"glTF", _::binary>>} = Labour.build(key, recipe, nodes: [{gone, 8}])
    # A person at far fits the edge: here.
    [{far, far_recipe} | _] = parts("far")
    assert {:ok, <<"glTF", _::binary>>} = Labour.build(far, far_recipe, nodes: [{a, 2}])
    assert {:ok, _} = Labour.build(far, far_recipe, nodes: [])
    # (A node builds no part that the store has: it gives the key at once.)
    assert Labour.make(key) == :stored
  end

  test "with shifts: a part of a project waits in the queue for a node, and goes back to the queue when its node goes away" do
    {key, recipe} = fresh(2)
    {:ok, a} = Task.Supervisor.start_link()
    me = self()

    # No node at first: the part waits in the queue; then a node of a shift comes.
    nodes = fn ->
      send(me, {:waiting, Labour.waiting()})
      []
    end

    waiter =
      Task.async(fn ->
        Labour.build(key, recipe, shifts: true, project: true, poll: 5, nodes: turns([[], [], [{a, 2}]]))
      end)

    assert Task.await(waiter, 600_000) == :stored
    assert Labour.waiting() == 0

    # The queue counts the part that waits.
    [{other, other_recipe} | _] = parts("near")

    waiter =
      Task.async(fn ->
        Labour.build(other, other_recipe, shifts: true, project: true, poll: 5, most: 50, nodes: nodes)
      end)

    assert_receive {:waiting, 1}
    assert {:error, [%{"message" => "no construction shift came" <> _}]} = Task.await(waiter)

    # The node of a shift goes away while it builds (the end of its shift stops its tasks): the part goes back to the queue, and the next node builds it.
    {key, recipe} = fresh(3)
    {:ok, b} = Task.Supervisor.start_link()
    {:ok, c} = Task.Supervisor.start_link()
    gone = spawn(fn -> :ok end)

    waiter =
      Task.async(fn ->
        Labour.build(key, recipe, shifts: true, project: true, poll: 5, nodes: turns([[{gone, 4}], [{b, 2}], [{c, 2}]]))
      end)

    wait = fn wait -> if Labour.busy(b) == 1, do: :ok, else: Process.sleep(5) && wait.(wait) end
    wait.(wait)
    [task] = Task.Supervisor.children(b)
    Process.exit(task, :shutdown)
    assert Task.await(waiter, 600_000) == :stored
  end

  test "with shifts: a node builds one part for each of its cores at a time, and the parts take the free cores in the order of the queue" do
    {:ok, n} = Task.Supervisor.start_link()
    {:ok, open} = Agent.start_link(fn -> false end)
    # (The node comes when the three parts wait: 4 workers, so 2 cores.)
    nodes = fn -> if Agent.get(open, & &1), do: [{n, 4}], else: [] end
    me = self()

    # The most parts in work on the node at one time.
    {:ok, most} = Agent.start_link(fn -> 0 end)
    watch = spawn_link(fn -> watch(most, n) end)

    waiters =
      for {count, i} <- Enum.with_index([4, 5, 6], 1) do
        {key, recipe} = fresh(count)

        waiter =
          Task.async(fn ->
            result = Labour.build(key, recipe, shifts: true, project: true, poll: 5, nodes: nodes)
            send(me, {:done, count, Labour.busy(n)})
            result
          end)

        wait_for(fn -> Labour.waiting() == i end)
        waiter
      end

    Agent.update(open, fn _ -> true end)
    assert Enum.map(waiters, &Task.await(&1, 600_000)) == [:stored, :stored, :stored]
    Process.unlink(watch)
    Process.exit(watch, :kill)
    assert Agent.get(most, & &1) == 2

    # The third part waited for a free core: the first two ended before it.
    assert_receive {:done, first, _}
    assert_receive {:done, second, _}
    assert_receive {:done, 6, 0}
    assert Enum.sort([first, second]) == [4, 5]
    assert Labour.waiting() == 0 and Labour.busy(n) == 0
  end

  defp watch(most, tasks) do
    Agent.update(most, &max(&1, Labour.busy(tasks)))
    Process.sleep(1)
    watch(most, tasks)
  end

  defp wait_for(fun), do: if(fun.(), do: :ok, else: Process.sleep(5) && wait_for(fun))

  test "a node builds a key one time: a second make of the key waits for the first one" do
    {key, _recipe} = fresh(7)
    first = Task.async(fn -> Labour.make(key) end)
    wait_for(fn -> Registry.lookup(Labour, {:make, key}) != [] end)
    second = Task.async(fn -> Labour.make(key) end)
    wait_for(fn -> {:process, first.pid} in elem(Process.info(second.pid, :monitors), 1) end)
    # (One make builds the key; the other waits for it.)
    assert [{pid, _}] = Registry.lookup(Labour, {:make, key})
    assert pid == first.pid
    assert Task.await(first, 600_000) == :stored
    assert Task.await(second, 600_000) == :stored
    assert Registry.lookup(Labour, {:make, key}) == []
  end

  test "a GLB that the store does not take stays on the node, and the next make puts it with no new build" do
    {key, _recipe} = fresh(8)
    config = Application.get_env(:world, World.Orders.Store, [])
    dir = Keyword.get(config, :dir, System.get_env("WORLD_ORDER_DIR", "tmp/orders"))
    tmp = Path.join(System.tmp_dir!(), "labour-refuse-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    flag = Path.join(tmp, "refuse")
    File.write!(flag, "")
    # (A store that refuses the GLB of this key while the flag is there, as
    # the edge refuses a key that its VM did not give: the other keys go to
    # the store of the tests.)
    script = Path.join(tmp, "store.sh")
    real = Path.expand("../../scripts/order-store.mjs", __DIR__)

    File.write!(script, """
    #!/bin/sh
    if [ "$1" = put ] && [ "$2" = "parts/#{key}.glb" ] && [ -f "#{flag}" ]; then exit 1; fi
    exec node "#{real}" "$@"
    """)

    File.chmod!(script, 0o755)
    Application.put_env(:world, World.Orders.Store, Keyword.put(config, :program, script))

    on_exit(fn ->
      Application.put_env(:world, World.Orders.Store, config)
      File.rm_rf!(tmp)
    end)

    capture_log(fn ->
      assert_raise RuntimeError, ~r/the store did not take the part/, fn -> Labour.make(key) end
    end)

    refute Store.has?(key)
    assert %{^key => <<"glTF", _::binary>>} = Agent.get(Labour.Kept, & &1)

    # The next make puts the kept GLB: with no recipe, a new build would give :none.
    File.rm!(flag)
    File.rm!(Path.join([dir, "parts", "#{key}.json"]))
    assert Labour.make(key) == :stored
    assert Store.has?(key)
    refute Map.has_key?(Agent.get(Labour.Kept, & &1), key)
  end

  # The store of the queue on this computer (scripts/labour-store.mjs),
  # with no restore of the application while the test runs: the test
  # starts the restore itself.
  defp use_store(program \\ Path.expand("../../scripts/labour-store.mjs", __DIR__)) do
    file = Path.join(System.tmp_dir!(), "labour-#{System.unique_integer([:positive])}.json")
    Application.put_env(:world, World.Labour.Store, program: program, file: file)
    :ok = Supervisor.terminate_child(World.Supervisor, World.Labour.Restore)

    on_exit(fn ->
      Application.delete_env(:world, World.Labour.Store)
      Supervisor.restart_child(World.Supervisor, World.Labour.Restore)
      File.rm(file)
    end)
  end

  # The keys in work on a node, in the order that they came to it.
  defp record(order, tasks, most \\ nil) do
    work = Registry.lookup(Labour, tasks)
    for {_, key} <- work, do: Agent.update(order, &if(key in &1, do: &1, else: &1 ++ [key]))
    # (With `most`, the most parts in work on the node at one time.)
    if most, do: Agent.update(most, &max(&1, length(work)))
    Process.sleep(1)
    record(order, tasks, most)
  end

  test "a start of the VM in the middle of a shift loses no part, and the order of the queue stays: the parts of C before the parts of D" do
    use_store()
    # C: two parts, then D: two parts, in the queue with no node.
    parts = for n <- [9, 10, 11, 12], do: fresh(n)
    keys = Enum.map(parts, &elem(&1, 0))
    nobody = fn -> [] end

    waiters =
      for {{key, recipe}, i} <- Enum.with_index(parts, 1) do
        pid = spawn(fn -> Labour.build(key, recipe, shifts: true, project: true, poll: 5, nodes: nobody) end)
        wait_for(fn -> Labour.waiting() == i end)
        pid
      end

    {:ok, rows} = World.Labour.Store.all()
    assert Enum.map(rows, & &1.key) == keys and Enum.all?(rows, &(&1.node == nil))
    # (The VM stops: its processes go, and the store stays.)
    for pid <- waiters, do: Process.exit(pid, :kill)
    wait_for(fn -> Labour.waiting() == 0 end)

    # A new VM, and a node with one core: the parts build one at a time.
    {:ok, n} = Task.Supervisor.start_link()
    {:ok, order} = Agent.start_link(fn -> [] end)
    watcher = spawn_link(fn -> record(order, n) end)
    assert Labour.restore(nodes: fn -> [{n, 2}] end, poll: 5) == :ok
    # (A second look while the parts are in the queue starts nothing more.)
    assert Labour.restore(nodes: fn -> [{n, 2}] end, poll: 5) == :ok
    wait_for(fn -> Enum.all?(keys, &Store.has?/1) end)
    wait_for(fn -> World.Labour.Store.all() == {:ok, []} end)
    Process.unlink(watcher)
    Process.exit(watcher, :kill)
    assert Agent.get(order, & &1) == keys
  end

  test "a part whose node goes away is in the queue again before the store hears of it: a later part does not take its core" do
    # (A store that is slow to hear that a part waits again.)
    dir = Path.join(System.tmp_dir!(), "labour-slow-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    slow = Path.join(dir, "slow-store")
    real = Path.expand("../../scripts/labour-store.mjs", __DIR__)
    File.write!(slow, "#!/bin/sh\n[ \"$1\" = back ] && sleep 1\nexec node #{real} \"$@\"\n")
    File.chmod!(slow, 0o755)
    on_exit(fn -> File.rm_rf(dir) end)
    use_store(slow)

    {a, a_recipe} = fresh(16)
    {b, b_recipe} = fresh(17)
    {:ok, n} = Task.Supervisor.start_link()
    {:ok, order} = Agent.start_link(fn -> [] end)
    watcher = spawn_link(fn -> record(order, n) end)
    gone = spawn(fn -> :ok end)
    me = node()

    # A first, on a node that goes away at once; then only n, with one core.
    first =
      Task.async(fn ->
        Labour.build(a, a_recipe, shifts: true, project: true, poll: 5, nodes: turns([[{gone, 2}], [{n, 2}]]))
      end)

    wait_for(fn -> match?({:ok, [%{key: ^a, node: ^me}]}, World.Labour.Store.all()) end)
    # B comes while the store hears that A waits again.
    second =
      Task.async(fn -> Labour.build(b, b_recipe, shifts: true, project: true, poll: 5, nodes: fn -> [{n, 2}] end) end)

    assert Task.await(first, 600_000) == :stored
    assert Task.await(second, 600_000) == :stored
    Process.unlink(watcher)
    Process.exit(watcher, :kill)
    assert Agent.get(order, & &1) == [a, b]
  end

  test "after a start of the VM, a part in work stays in the work of its node, and goes to that node when it is there" do
    use_store()
    {key, _recipe} = fresh(13)
    me = node()
    _ = World.Labour.Store.wait(key, 1)
    :ok = World.Labour.Store.give(key, me)
    # (The tasks of the node by their name, as World.Crew gives them.)
    n = {World.Crew.Tasks, me}
    {:ok, there} = Agent.start_link(fn -> [] end)
    assert Labour.restore(nodes: fn -> Agent.get(there, & &1) end, poll: 5) == :ok
    # In the work of its node at once (the store of the Worker takes its GLB, World.Shift.Passes.allowed?/4).
    wait_for(fn -> Registry.lookup(Labour, {World.Crew.Tasks, me}) != [] end)
    assert [{_, ^key}] = Registry.lookup(Labour, {World.Crew.Tasks, me})
    Agent.update(there, fn _ -> [{n, 2}] end)
    wait_for(fn -> Store.has?(key) end)
    wait_for(fn -> World.Labour.Store.all() == {:ok, []} end)
    assert Registry.lookup(Labour, {World.Crew.Tasks, me}) == []
  end

  test "after a start of the VM, a part whose node does not come back goes back to the queue at its place; a part in the store is done" do
    use_store()
    {key, _recipe} = fresh(14)
    _ = World.Labour.Store.wait(key, 1)
    :ok = World.Labour.Store.give(key, :gone@nowhere)
    {:ok, n} = Task.Supervisor.start_link()
    {:ok, there} = Agent.start_link(fn -> [] end)
    assert Labour.restore(nodes: fn -> Agent.get(there, & &1) end, poll: 5, back: 20) == :ok
    wait_for(fn -> World.Labour.Store.all() == {:ok, [%{key: key, ticket: 1, node: nil}]} end)
    wait_for(fn -> Labour.waiting() == 1 end)
    Agent.update(there, fn _ -> [{n, 2}] end)
    wait_for(fn -> Store.has?(key) end)
    wait_for(fn -> World.Labour.Store.all() == {:ok, []} end)

    # A part that a VM before put in the store, with its row still there
    # (after the end of the process of the key: a process that ends waits
    # 1 s for late requests, and a restore joins it; the next look takes the row).
    wait_for(fn -> Registry.lookup(World.Names, {:build, {:part, key}}) == [] end)
    _ = World.Labour.Store.wait(key, 2)
    assert Labour.restore(nodes: fn -> [] end) == :ok
    wait_for(fn -> World.Labour.Store.all() == {:ok, []} end)
  end

  @tag :tmp_dir
  test "the parts of three projects in one shift keep the order of their requests, and the summary gives the projects of each part",
       %{tmp_dir: dir} do
    use_store()
    me = self()
    summary = Path.join(dir, "summary.md")

    # Three projects ask, one after the other; the second part is asked again by the first project.
    asks = [{25, ["vung_tau"]}, {26, ["tre", "vung_tau"]}, {27, ["humans-must-die"]}]
    parts = for {n, projects} <- asks, do: {fresh(n), projects}
    keys = for {{key, _}, _} <- parts, do: key
    nobody = fn -> [] end

    waiters =
      for {{{key, recipe}, projects}, i} <- Enum.with_index(parts, 1) do
        Labour.asked(key, hd(projects))
        pid = spawn(fn -> Labour.build(key, recipe, shifts: true, project: true, poll: 5, nodes: nobody) end)
        wait_for(fn -> Labour.waiting() == i end)
        for p <- tl(projects), do: Labour.asked(key, p)
        pid
      end

    assert World.Labour.Store.projects(Enum.at(keys, 1)) == ["tre", "vung_tau"]
    # (A new VM: the queue and the projects come back from the store.)
    for pid <- waiters, do: Process.exit(pid, :kill)
    wait_for(fn -> Labour.waiting() == 0 end)
    # (A shift on this node: its record of each part, and its summary when it goes home with no work.)
    start_supervised!(
      {World.Shift,
       until: System.system_time(:millisecond) + 3_600_000,
       idle: 3_000,
       tick: 10,
       summary: summary,
       stop: &send(me, {:stop, &1})}
    )

    {:ok, n} = Task.Supervisor.start_link()
    {:ok, order} = Agent.start_link(fn -> [] end)
    {:ok, most} = Agent.start_link(fn -> 0 end)
    watcher = spawn_link(fn -> record(order, n, most) end)
    assert Labour.restore(nodes: fn -> [{n, 2}] end, poll: 5) == :ok
    wait_for(fn -> Enum.all?(keys, &Store.has?/1) end)
    assert_receive {:stop, 0}, 60_000
    Process.unlink(watcher)
    Process.exit(watcher, :kill)
    # The order of the requests, whatever project asked, one part at a time on the core of the
    # node; the projects of a part go when it is done.
    assert Agent.get(most, & &1) == 1
    assert Agent.get(order, & &1) == keys
    assert Enum.all?(keys, &(World.Labour.Store.projects(&1) == []))

    text = File.read!(summary)
    rows = for line <- String.split(text, "\n"), key <- keys, String.contains?(line, key), do: {key, line}
    assert Enum.map(rows, &elem(&1, 0)) == keys
    assert [{_, a}, {_, b}, {_, c}] = rows
    assert a =~ ~r/^\| vung_tau \|/ and b =~ ~r/^\| tre, vung_tau \|/ and c =~ ~r/^\| humans-must-die \|/

    assert text =~ ~r/\| vung_tau \| 2 \| 2 \|/ and text =~ ~r/\| tre \| 1 \| 1 \|/ and
             text =~ ~r/\| humans-must-die \| 1 \| 1 \|/
  end

  test "the projects of a part with no store of the queue are in the memory of the VM" do
    key = String.duplicate("d", 32)
    assert World.Labour.Store.ask(key, "vung_tau") == :ok and World.Labour.Store.ask(key, "tre") == :ok
    assert World.Labour.Store.ask(key, "vung_tau") == :ok
    assert World.Labour.Store.projects(key) == ["vung_tau", "tre"]
    assert World.Labour.Store.done(key) == :ok and World.Labour.Store.projects(key) == []
    use_store("/bin/false")
    assert World.Labour.Store.ask(key, "tre") == :error and World.Labour.Store.projects(key) == []
  end

  test "the store of the queue: no program, and a program that fails" do
    key = String.duplicate("e", 32)
    assert World.Labour.Store.wait(key, 7) == 7 and World.Labour.Store.give(key, :a@b) == :ok
    assert World.Labour.Store.back(key) == :ok and World.Labour.Store.done(key) == :ok
    assert World.Labour.Store.all() == {:ok, []} and not World.Labour.Store.on?()
    use_store("/bin/false")
    assert World.Labour.Store.wait(key, 7) == 7 and World.Labour.Store.give(key, :a@b) == :error
    assert World.Labour.Store.all() == :error and Labour.restore() == :error
  end

  test "the restore looks at the store each time of its look" do
    use_store()
    {:ok, pid} = World.Labour.Restore.start_link(name: :labour_restore_test, look: 5, labour: [nodes: fn -> [] end])
    {key, _} = fresh(15)

    on_exit(fn ->
      for {builder, _} <- Registry.lookup(World.Names, {:build, {:part, key}}), do: Process.exit(builder, :kill)
    end)

    _ = World.Labour.Store.wait(key, 3)
    wait_for(fn -> Labour.waiting() == 1 end)
    GenServer.stop(pid)
    assert [_] = Registry.lookup(World.Names, {:build, {:part, key}})
  end

  test "with shifts: a part of a public order that does not fit the edge gives an error; a part that fits builds here" do
    [{key, recipe} | _] = parts("near")
    assert {:error, [%{"message" => "this part does not fit" <> _}]} = Labour.build(key, recipe, shifts: true)
    [{far, far_recipe} | _] = parts("far")
    assert {:ok, _} = Labour.build(far, far_recipe, shifts: true)
  end

  test "a part that raises on a node builds on the next one; it gives an error after 3 tries on the nodes of shifts" do
    [{_key, recipe} | _] = parts("near")
    # (A recipe of a person that the group does not have: its make raises.)
    bad = String.duplicate("b", 32)
    :ok = Store.put_recipe(bad, JSON.encode!(%{recipe | "piece" => "nobody"}))
    {:ok, a} = Task.Supervisor.start_link()

    capture_log(fn ->
      assert_raise MatchError, fn -> Labour.build(bad, %{recipe | "piece" => "nobody"}, nodes: [{a, 2}]) end

      assert {:error, [%{"message" => "the part failed on 3 nodes" <> _}]} =
               Labour.build(bad, %{recipe | "piece" => "nobody"}, shifts: true, project: true, nodes: [{a, 2}])
    end)

    # A key with no recipe: nothing to build.
    assert Labour.make(String.duplicate("c", 32)) == :none
  end
end
