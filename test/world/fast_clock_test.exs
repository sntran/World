defmodule World.FastClockTest do
  # The fast clock (plan 0007, D4 and R4): the log keeps the days of each
  # task on the world clock, and the people do not wait for them. The
  # tests set the scale of the world clock, so they do not run with the
  # others.
  use ExUnit.Case, async: false

  alias World.{Clock, Detail, Drawing, Log}

  setup do
    old = Application.get_env(:world, :scale)
    on_exit(fn -> Application.put_env(:world, :scale, old) end)
    :ok
  end

  defp build(job, clock) do
    id = "fast-#{System.unique_integer([:positive])}"
    t0 = System.monotonic_time(:millisecond)
    {:ok, ^id} = World.build(Map.merge(job, %{id: id, budget: %{"workers" => 4, "clock" => clock}}))
    {:ok, result} = World.await(id, 120_000)
    {result, System.monotonic_time(:millisecond) - t0}
  end

  defp at(log, kind, task), do: Enum.find(Log.events(log), &(&1.kind == kind and &1.data["task"] == task)).at

  test "a slab, its cure and a wall: the days of the world in the log, and no wait (one day in 10 s of the wall)" do
    Application.put_env(:world, :scale, 8_640)

    d = %{
      "name" => "slab_and_wall",
      "nodes" => [
        %{
          "name" => "slab",
          "skill" => %{"block" => %{"size" => 1.0}},
          "work" => %{"concrete" => 250.0},
          "cure" => "set"
        },
        %{
          "name" => "wall",
          "skill" => %{"block" => %{"size" => 0.5}},
          "from" => ["slab"],
          "to" => "slab",
          "at" => "top"
        }
      ]
    }

    job = %{item: fn level -> Detail.with(level, fn -> Drawing.build(d) end) end, drawing: d}
    {%{log: log}, ms} = build(job, "fast")
    assert Log.check(log) == :ok
    day = Clock.day()
    # 10 days of the slab, 7 days of its cure, the wall of one hour: 17
    # days of the world (170 s of the wall on the world clock).
    assert at(log, "task_done", "slab") - at(log, "task_started", "slab") == 10 * day
    assert at(log, "task_started", "wall") - at(log, "task_done", "slab") == 7 * day
    assert at(log, "task_done", "wall") - at(log, "task_started", "wall") == div(day, 8)
    # (No wait: less than half of the 170 s, also on a busy computer.)
    assert ms < 85_000
    # The log says that its times are of the fast clock, in its JSON too.
    assert log.clock.fast and {:ok, log} == Log.from_json(Log.to_json(log))
    assert Log.to_json(log) =~ ~r/^\{[^\n]*"fast":true/
    # A log on the world clock with a wrong time is still an error.
    [first | _] = Log.events(log)
    slow = %{log | clock: %{log.clock | fast: false}, events: [%{first | at: first.at + 1}]}
    assert {:error, {:wrong_time, _}} = Log.check(slow)
  end

  test "a wall of bricks: the same days of each task and the same model on the two clocks" do
    item = fn level -> Detail.with(level, fn -> World.Buildings.masonry_wall("row", "brick_vn", 1.0, 1.5) end) end
    {world, _} = build(%{item: item}, "world")
    {fast, _} = build(%{item: item}, "fast")
    assert fast.glb == world.glb

    days = fn log ->
      events = Log.events(log)
      started = for e <- events, e.kind == "task_started", into: %{}, do: {e.data["task"], {e.at, e.data["days"]}}

      for e <- events, e.kind == "task_done" do
        {start, days} = started[e.data["task"]]
        {e.data["task"], days, e.at - start}
      end
      |> Enum.sort()
    end

    on_world = days.(world.log)
    on_fast = days.(fast.log)
    assert length(on_fast) > 20
    assert Enum.map(on_fast, fn {task, d, _} -> {task, d} end) == Enum.map(on_world, fn {task, d, _} -> {task, d} end)
    # On the fast clock, each task takes its days exactly; on the world
    # clock, its days or more.
    assert Enum.all?(on_fast, fn {_, d, span} -> span == round(d * Clock.day()) end)
    assert Enum.all?(on_world, fn {_, d, span} -> span >= round(d * Clock.day()) end)
  end

  test "on the fast clock, a slow hire takes no days of the site: the same days of each task" do
    # A slab, then three walls on it (one short, two long), and a rail of another trade after the short
    # wall: the smith is hired while the two long walls are in work.
    wall = fn name, work ->
      %{"name" => name, "skill" => %{"block" => %{"size" => 0.3}}, "to" => "slab", "work" => %{"concrete" => work}}
    end

    d = %{
      "name" => "two_trades",
      "nodes" => [
        %{"name" => "slab", "skill" => %{"block" => %{"size" => 1.0}}, "work" => %{"concrete" => 50.0}},
        wall.("wall_1", 5.0),
        wall.("wall_2", 40.0),
        wall.("wall_3", 40.0),
        %{
          "name" => "rail",
          "skill" => %{"block" => %{"size" => 0.2}},
          "to" => "slab",
          "trade" => "smith",
          "after" => ["wall_1"]
        }
      ]
    }

    job = %{item: fn level -> Detail.with(level, fn -> Drawing.build(d) end) end, drawing: d}
    {quick, _} = build(job, "fast")

    # The census of the node answers each hire late: it stops for 30 ms, then goes on for 2 ms, while the site works.
    slow =
      spawn_link(fn ->
        Stream.repeatedly(fn ->
          :sys.suspend(World.Census)
          Process.sleep(30)
          :sys.resume(World.Census)
          Process.sleep(2)
        end)
        |> Stream.run()
      end)

    {late, _} = build(job, "fast")
    Process.unlink(slow)
    Process.exit(slow, :kill)
    :sys.resume(World.Census)

    assert Enum.sort(days(late.log)) == Enum.sort(days(quick.log))
    # (The rail starts when the short wall is done, before the long walls.)
    assert at(quick.log, "task_started", "rail") == at(quick.log, "task_done", "wall_1")
  end

  test "on the fast clock, a hire that waits for a person of another construction does not stop the site" do
    d = %{
      "name" => "two_walls",
      "nodes" => [
        %{"name" => "slab", "skill" => %{"block" => %{"size" => 1.0}}, "work" => %{"concrete" => 50.0}},
        %{"name" => "wall", "skill" => %{"block" => %{"size" => 0.3}}, "to" => "slab", "trade" => "smith"}
      ]
    }

    job = %{item: fn level -> Detail.with(level, fn -> Drawing.build(d) end) end, drawing: d}
    {quick, _} = build(job, "fast")

    # No person can go to a hire now: the census has a limit of 0, and each free person is held.
    holder = spawn(fn -> Process.sleep(:infinity) end)
    limit = :sys.get_state(World.Census).limit

    hold = fn from, to ->
      &Map.new(&1, fn {p, info} -> {p, if(info.by == from, do: %{info | by: to}, else: info)} end)
    end

    :sys.replace_state(World.Census, &%{&1 | limit: 0, people: hold.(nil, holder).(&1.people)})

    id = "fast-#{System.unique_integer([:positive])}"
    {:ok, ^id} = World.build(Map.merge(job, %{id: id, budget: %{"workers" => 4, "clock" => "fast"}}))
    # (The site has a hire in the census: it waits there, queued.)
    wait = fn wait -> if World.Census.people()["waiting"] == [], do: Process.sleep(10) && wait.(wait) end
    wait.(wait)

    # The people are free again; a hire of the test makes the census give each hire its person.
    :sys.replace_state(World.Census, &%{&1 | limit: limit, people: hold.(holder, nil).(&1.people)})
    ref = World.Person.hire(:fast_clock_test)
    assert_receive {:hired, ^ref, person}
    World.Person.release(person)
    Process.exit(holder, :kill)

    assert {:ok, late} = World.await(id, 120_000)
    assert Enum.sort(days(late.log)) == Enum.sort(days(quick.log))
  end

  defp days(log) do
    events = Log.events(log)
    start = hd(events).at
    for e <- events, e.kind in ["task_started", "task_done"], do: {e.data["task"], e.kind, e.at - start}
  end

  test "the stages of a site: in their order on the world clock, and at their days on the fast clock" do
    d = %{"name" => "two_stages", "nodes" => [%{"name" => "slab", "skill" => %{"block" => %{"size" => 1.0}}}]}

    stage = fn name, work, from, to ->
      %{
        name: name,
        work: work,
        text: nil,
        place: nil,
        date: nil,
        from: from,
        to: to,
        until: "all",
        options: nil,
        lot: nil,
        repair: false,
        lost: [],
        means: [],
        takes: [],
        again: [],
        path: nil
      }
    end

    # A build, then a pause of 2 days to the day 30 of the site.
    stages = [stage.("build", "build", 0, nil), stage.("rest", "pause", 28, 30)]
    job = %{item: fn level -> Detail.with(level, fn -> Drawing.build(d) end) end, drawing: d, stages: stages}

    for clock <- ["world", "fast"] do
      {%{log: log}, _} = build(job, clock)
      assert Log.check(log) == :ok
      events = for e <- Log.events(log), e.kind in ["stage_started", "stage_done"], do: {e.kind, e.data["name"], e.at}

      assert [
               {"stage_started", "build", _},
               {"stage_done", "build", _},
               {"stage_started", "rest", started},
               {"stage_done", "rest", done}
             ] =
               events

      origin = hd(Log.events(log)).at
      # On the world clock the days come after the wall time (so at their day or later); on the fast
      # clock the pause starts at its day 28 and ends at its day 30, with no wait.
      if clock == "fast" do
        assert {started - origin, done - origin} == {28 * Clock.day(), 30 * Clock.day()}
      else
        assert done - origin >= 30 * Clock.day()
      end
    end
  end
end
