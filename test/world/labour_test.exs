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
  # (the key of a part has the hash of its order).
  defp fresh(n) do
    [{key, recipe} | _] = parts("near", put_in(@group, ["options", "count"], n))
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

  test "the parts that fit the edge: a person at mid or far; the others need a shift at the edge with shifts" do
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
    refute Labour.fits?(%{"node" => "wall", "level" => "far", "tile" => nil})
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
