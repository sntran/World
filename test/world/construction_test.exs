defmodule World.ConstructionTest do
  use ExUnit.Case, async: true

  alias World.{Assembly, Build, BuildSpec, Catalog, Construction, Detail, Log, Mesh, Part, Port}

  @moduletag :tmp_dir

  # A job of a model of the catalog, with an id of its own.
  defp job(name, opts) do
    {:ok, fun} = Catalog.fetch(name)
    id = "#{name}-#{System.unique_integer([:positive])}"
    Map.merge(%{id: id, item: fn level -> Detail.with(level, fun) end}, Map.new(opts))
  end

  defp glb(name, level) do
    {:ok, fun} = Catalog.fetch(name)
    Detail.with(level, fun) |> Build.glb(level: level)
  end

  defp kinds(log), do: Enum.map(Log.events(log), & &1.kind)

  # The most tasks that ran at one time in a log.
  defp most(log) do
    {_, most} =
      Enum.reduce(Log.events(log), {0, 0}, fn
        %{kind: "task_started"}, {n, m} -> {n + 1, max(m, n + 1)}
        %{kind: "task_done"}, {n, m} -> {n - 1, m}
        _, acc -> acc
      end)

    most
  end

  test "the people build the wall of bricks element by element: the bytes of a build with no world, with one worker and with eight",
       %{tmp_dir: dir} do
    expected = glb("wall_brick_sample", :near)
    {:ok, fun} = Catalog.fetch("wall_brick_sample")
    elements = length(Build.elements(fun.(), :near))

    for workers <- [1, 8] do
      {:ok, id} = World.build(job("wall_brick_sample", budget: %{"workers" => workers}))
      assert {:ok, r} = World.await(id)
      assert r.glb == expected and r.level == :near
      assert Log.check(r.log) == :ok
      kinds = kinds(r.log)
      assert hd(kinds) == "requested" and Enum.take(kinds, -2) == ["done", "run_done"]
      assert Enum.count(kinds, &(&1 == "element")) == elements
      assert Enum.count(kinds, &(&1 == "task_done")) == length(r.plan.tasks)
      assert Enum.count(kinds, &(&1 == "hired")) in 1..workers
      assert most(r.log) <= workers
      # Each part of the wall has its GLB once: the bricks share one.
      assert map_size(r.glbs) < elements
      assert BuildSpec.replay([r.log], Path.join(dir, "#{workers}")) == :ok
    end
  end

  test "the replay fails on a log with an event less, and on a task made again in the fault model", %{tmp_dir: dir} do
    {:ok, id} = World.build(job("wall_brick_sample", budget: %{"workers" => 1}))
    {:ok, %{log: log}} = World.await(id)
    events = Log.events(log)
    with_events = fn list -> %{log | events: Enum.reverse(list)} end

    # With no end of the first task, its person is still busy at its next task.
    first = Enum.find_index(events, &(&1.kind == "task_done"))

    assert {:error, {:diverged, %{kind: "task_started"}}} =
             BuildSpec.replay([with_events.(List.delete_at(events, first))], Path.join(dir, "less"))

    # The first task again, after its end: the fault model lets it start.
    # The copies have the wall time of the end that they follow: the
    # replay takes the events in the order of their wall time.
    at = Enum.at(events, first)

    again =
      for e <- Enum.take(Enum.filter(events, &(&1.kind in ["task_started", "task_done"])), 2),
          do: %{e | wall: at.wall, at: at.at}

    {head, tail} = Enum.split(events, first + 1)
    twice = with_events.(head ++ again ++ tail)
    assert {:error, {:violated, "MadeOnce", _}} = BuildSpec.replay([twice], Path.join(dir, "twice"), guard: false)
  end

  test "with a budget of one person, a construction gives back its free person for a task of another trade", %{
    tmp_dir: dir
  } do
    o = Port.new("o", {0, 0, 0}, {0, 0, 1})
    box = fn name -> Part.new(name, :part, [World.Shape.box({0, 0, 0}, {0.1, 0.1, 0.1}, :steel)], [o]) end
    wheel = %{Assembly.new("wheel", box.("rim"), root: "rim") | kind: :wheel}

    van =
      %{Assembly.new("van", box.("body"), root: "body") | kind: :vehicle}
      |> Assembly.add("wheel", wheel, at: "o", port: "o")
      |> Assembly.add("door", box.("door"), at: "o", port: "o")

    {:ok, id} =
      World.build(%{id: "van-#{System.unique_integer([:positive])}", item: fn _ -> van end, budget: %{"workers" => 1}})

    assert {:ok, r} = World.await(id)
    assert r.glb == Build.glb(van)

    # The mechanic, then the wheelwright in its place, then a mechanic again.
    trades = for %{kind: "hired", data: %{"trade" => t}} <- Log.events(r.log), do: t
    assert trades == ["mechanic", "wheelwright", "mechanic"]
    assert "released" in kinds(r.log)
    assert BuildSpec.replay([r.log], dir) == :ok
  end

  test "two constructions at one time share the people, and each gives its bytes", %{tmp_dir: dir} do
    expected = glb("wall_brick_sample", :near)
    jobs = for _ <- 1..2, do: job("wall_brick_sample", budget: %{"workers" => 2})
    ids = for j <- jobs, do: elem(World.build(j), 1)

    for {id, i} <- Enum.with_index(ids) do
      assert {:ok, r} = World.await(id)
      assert r.glb == expected
      assert BuildSpec.replay([r.log], Path.join(dir, "#{i}")) == :ok
    end
  end

  @tag timeout: 300_000
  test "the statue on Núi Nhỏ at the level far: the bytes of a build with no world" do
    {:ok, id} = World.build(job("tuong_chua_kito_vua", level: :far))
    assert {:ok, r} = World.await(id)
    assert r.glb == glb("tuong_chua_kito_vua", :far)
  end

  test "the budget of triangles: the level that fits, or a stop" do
    {:ok, fun} = Catalog.fetch("wall_brick_sample")
    near = Construction.estimate(Detail.with(:near, fun), :near)
    mid = Construction.estimate(Detail.with(:mid, fun), :mid)
    assert mid < near

    {:ok, id} = World.build(job("wall_brick_sample", budget: %{"triangles" => near - 1}))
    assert {:ok, %{level: :mid} = r} = World.await(id)
    assert r.glb == glb("wall_brick_sample", :mid)

    {:ok, id} = World.build(job("wall_brick_sample", budget: %{"triangles" => 1}))
    assert World.await(id) == {:error, {:stopped, "triangles"}}
  end

  test "the budget of seconds: the construction stops at its deadline, with no model, and its log replays",
       %{tmp_dir: dir} do
    World.watch(:world)
    {:ok, id} = World.build(job("wall_brick_sample", budget: %{"seconds" => 0}))
    assert World.await(id) == {:error, {:stopped, "seconds"}}

    # The events of the construction from the stream of the world, as a log.
    events = collect(id, [])
    assert %{kind: "stopped", data: %{"reason" => "seconds"}} = List.last(events)
    log = %Log{clock: World.Clock.new(), events: Enum.reverse(events)}
    assert BuildSpec.replay([log], dir) == :ok
  end

  # The events of a construction from the stream of the world, to its stop.
  defp collect(id, events) do
    receive do
      {:world, %{"order" => ^id, "id" => n} = e} when is_integer(n) ->
        events =
          events ++
            [%Log.Event{at: e["at"], wall: e["wall"], kind: e["kind"], order: id, who: e["who"], data: e["data"]}]

        if e["kind"] == "stopped", do: events, else: collect(id, events)
    after
      5_000 -> flunk("no stop")
    end
  end

  test "a task that fails stops the construction with its message" do
    bad = %Mesh{points: [], faces: [[0, 1, 2]], material: :paint}
    o = Port.new("o", {0, 0, 0}, {0, 0, 1})

    item =
      Assembly.new("bad", Part.new("base", :part, [], [o]), root: "base")
      |> Assembly.add("p", Part.new("p", :part, [bad], [o]), at: "o", port: "o")

    {:ok, id} = World.build(%{id: "bad-#{System.unique_integer()}", item: fn _ -> item end})
    assert {:error, {:failed, message}} = World.await(id)
    assert is_binary(message)
  end

  test "a person that stops gives its task back, and another person makes it" do
    j = job("wall_brick_sample", budget: %{"workers" => 1})
    World.watch(j.id)
    {:ok, id} = World.build(j)
    assert_receive {:world, %{"kind" => "task_started", "who" => who}}
    Process.exit(:erlang.list_to_pid(String.to_charlist(who)), :kill)
    assert {:ok, r} = World.await(id)
    assert r.glb == glb("wall_brick_sample", :near)
  end

  test "a second job of the same build gets the same result; a person that it does not need goes back" do
    j = job("wall_brick_sample", budget: %{"workers" => 1})
    {:ok, id} = World.build(j)
    [{pid, _}] = Registry.lookup(World.Names, id)
    assert Process.get_label(pid) == {:construction, id}
    me = self()
    spawn(fn -> send(me, {:second, World.build(j), World.await(id)}) end)

    # A person that comes with no request goes back to the census.
    ref = World.Person.hire(:joiner)
    assert_receive {:hired, ^ref, p}
    send(pid, {:hired, make_ref(), p})

    assert {:ok, r} = World.await(id)
    assert_receive {:second, {:ok, ^id}, {:ok, ^r}}, 10_000
    World.Person.release(p)
  end

  test "a build whose construction ends at the join is built again" do
    id = "gone-#{System.unique_integer([:positive])}"
    me = self()

    # A process with the name of the build that ends when the job asks to join.
    spawn(fn ->
      Registry.register(World.Names, id, nil)
      send(me, :named)

      receive do
        {:"$gen_call", _, _} -> exit(:normal)
      end
    end)

    assert_receive :named
    {:ok, fun} = Catalog.fetch("wall_brick_sample")
    assert {:ok, ^id} = World.build(%{id: id, item: fn level -> Detail.with(level, fun) end})
    assert {:ok, _} = World.await(id)
  end

  test "after its end, a construction keeps its elements for a time, and a deadline then changes nothing" do
    Application.put_env(:world, Construction, linger: 1_500)
    on_exit(fn -> Application.delete_env(:world, Construction) end)
    {:ok, id} = World.build(job("wall_brick_sample", level: :far, budget: %{"seconds" => 1}))
    assert {:ok, %{glbs: glbs}} = World.await(id)
    [{pid, _}] = Registry.lookup(World.Names, {:elements, id})
    assert Construction.element(id, 0) == {:ok, glbs[0]}
    assert Construction.element(id, 999) == :none

    # The deadline comes after the end: the construction keeps going until its time.
    ref = Process.monitor(pid)
    Process.sleep(1_100)
    assert Process.alive?(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
    assert Construction.element(id, 0) == :none
  end

  test "a second build of the same id ends at once when the first one keeps the elements" do
    # At near, with one worker: the second build still runs at its lookup.
    j = job("wall_brick_sample", level: :near, budget: %{"workers" => 1})
    {:ok, id} = World.build(j)
    assert {:ok, first} = World.await(id)
    [{keeper, _}] = Registry.lookup(World.Names, {:elements, id})

    {:ok, ^id} = World.build(j)
    [{second, _}] = Registry.lookup(World.Names, id)
    ref = Process.monitor(second)
    assert {:ok, again} = World.await(id)
    assert again.glb == first.glb
    assert_receive {:DOWN, ^ref, :process, ^second, :normal}
    assert [{^keeper, _}] = Registry.lookup(World.Names, {:elements, id})
  end

  test "an element of a construction that ends at the request is not there" do
    id = "ends-#{System.unique_integer([:positive])}"
    me = self()

    spawn(fn ->
      Registry.register(World.Names, id, nil)
      send(me, :named)

      receive do
        {:"$gen_call", _, _} -> exit(:normal)
      end
    end)

    assert_receive :named
    assert Construction.element(id, 0) == :none
  end

  test "await gives a timeout when no result comes" do
    assert World.await("nothing", 0) == {:error, :timeout}
  end
end
