defmodule World.WorldTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.{Assembly, Clock, Log, Part, Plan, Shape}

  describe "the clock" do
    test "one second of the wall clock is one day of the world" do
      clock = Clock.new(start: 1_000)
      assert clock.scale == Clock.scale() and Clock.scale() == 86_400
      assert Clock.at(clock, 2_000) == 86_400_000
      assert Clock.to_world(clock, 460) == 39_744_000
      # A walk of 100 m at 1.4 m/s is 71 world seconds: less than one ms of the wall clock.
      assert Clock.to_wall(clock, round(100 / 1.4 * 1000)) == 1
      assert Clock.to_wall(clock, 0) == 0
      assert Clock.at(Clock.new(), Clock.wall() + 1) > 0
      assert_raise ArgumentError, fn -> Clock.new(scale: 0) end
    end

    test "a world time as people read it" do
      assert Clock.label(0) == "day 1, 00:00"
      assert Clock.label(411 * 86_400_000 + (14 * 60 + 5) * 60_000 + 59_999) == "day 412, 14:05"
    end

    property "the wall time of a world span is never less than the span over the scale" do
      check all world <- integer(0..10_000_000_000), scale <- integer(1..100_000) do
        clock = Clock.new(start: 0, scale: scale)
        wall = Clock.to_wall(clock, world)
        assert wall * scale >= world and (wall - 1) * scale < world
      end
    end
  end

  describe "the plan of an order" do
    # Each model of the catalog: one task for each node, and each task
    # waits for the task of its parent.
    for {name, _} <- World.Catalog.models() do
      @name name
      # (A large sculpture with maps takes minutes when the other tests work too.)
      @tag timeout: 1_800_000
      test "the plan of #{name}" do
        {:ok, fun} = World.Catalog.fetch(@name)
        item = fun.()
        plan = Plan.of(item)
        ids = Enum.map(plan.tasks, & &1.id)
        assert length(ids) == length(Enum.uniq(ids))

        case item do
          %Assembly{nodes: nodes} ->
            connects = for t <- plan.tasks, t.action != :order or t.id == elem(hd(nodes), 0), do: t.id
            assert connects == Enum.map(nodes, &elem(&1, 0))

            for {node, _, c} <- tl(nodes) do
              task = Enum.find(plan.tasks, &(&1.id == node and &1.action == :connect))
              assert c.to in task.waits
            end

          _ ->
            assert [%Plan.Task{action: :make}] = plan.tasks
        end

        # The tasks come in an order where each task waits only for the
        # tasks before it, in the plan and in its flat plan for one factory.
        for p <- [plan, Plan.flat(item)] do
          assert length(p.tasks) == length(Enum.uniq_by(p.tasks, & &1.id))

          Enum.reduce(p.tasks, MapSet.new(), fn t, before ->
            assert Enum.all?(t.waits, &MapSet.member?(before, &1))
            MapSet.put(before, t.id)
          end)
        end
      end
    end

    test "a sub-assembly is an order of its own, a joint keeps its role, and the station comes from the part" do
      box = fn name, station ->
        Part.new(name, :part, [Shape.box({0, 0, 0}, {1, 1, 1}, :steel)], [Part.port("p", {0, 0, 0}, {0, 0, 1})],
          params: %{"station" => station}
        )
      end

      mark = Part.new("origin", :part, [], [Part.port("p", {0, 0, 0}, {0, 0, 1})])
      wheel = Assembly.new("wheel", box.("rim", "wheels"), root: "rim")

      van =
        Assembly.new("van", mark, root: "origin")
        |> Assembly.add("body", box.("body", "body_shop"), at: "p", port: "p")
        |> Assembly.add("door", box.("door", "closures"), to: "body", at: "p", port: "p", kind: :hinge, role: :door)
        |> Assembly.add("wheel", wheel, to: "body", at: World.Port.new("axle", {0, 0, 0}, {1, 0, 0}), port: "p")

      plan = Plan.of(van)

      assert Enum.map(plan.tasks, &{&1.id, &1.action}) == [
               {"origin", :make},
               {"body", :connect},
               {"door", :connect},
               {"wheel/order", :order},
               {"wheel", :connect}
             ]

      door = Enum.find(plan.tasks, &(&1.id == "door"))
      assert door.joint == :door and door.station == "closures" and door.waits == ["body"] and door.at == "p"
      wheel_task = Enum.find(plan.tasks, &(&1.id == "wheel"))
      assert wheel_task.waits == ["body", "wheel/order"] and wheel_task.at == "axle" and wheel_task.item == "wheel"
      assert wheel_task.station == "wheels"
      # The mark of the origin is not a part to get; the wheel brings its own parts.
      assert plan.parts == %{"body" => 1, "door" => 1}

      data = Plan.to_data(plan)
      assert %{"id" => "wheel", "action" => "connect", "waits" => ["body", "wheel/order"]} = List.last(data["tasks"])
      assert Plan.of(box.("seat", nil)).parts == %{"seat" => 1}

      # The flat plan: the tasks of the wheel come first, then the end of
      # the wheel waits for each of them.
      flat = Plan.flat(van)
      assert Enum.map(flat.tasks, & &1.id) == ["origin", "body", "door", "wheel/rim", "wheel/order", "wheel"]
      assert Enum.find(flat.tasks, &(&1.id == "wheel/order")).waits == ["wheel/rim"]
      assert flat.parts == %{"body" => 1, "door" => 1, "rim" => 1}
      assert [%Plan.Task{id: "seat", uses: "seat"}] = Plan.flat(box.("seat", nil)).tasks
    end

    test "each task has the trade of the nearest assembly with one, else a builder" do
      part = fn name ->
        Part.new(name, :part, [Shape.box({0, 0, 0}, {1, 1, 1}, :steel)], [Part.port("p", {0, 0, 0}, {0, 0, 1})])
      end

      wheel = %{Assembly.new("wheel_x", part.("rim"), root: "rim") | kind: :wheel}

      corner =
        Assembly.new("corner", part.("knuckle"), root: "knuckle") |> Assembly.add("wheel", wheel, at: "p", port: "p")

      van =
        %{Assembly.new("van", part.("body"), root: "body") | kind: :vehicle}
        |> Assembly.add("corner", corner, at: "p", port: "p")

      assert Plan.trade(wheel) == :wheelwright and Plan.trade(van) == :mechanic and Plan.trade(corner) == nil
      assert Plan.trade(part.("x")) == nil
      assert Plan.trade(%{Assembly.new("door_x", part.("panel"), root: "panel") | kind: :door}) == :joiner

      assert Enum.map(Plan.flat(van).tasks, &{&1.id, &1.trade}) == [
               {"body", :mechanic},
               {"corner/knuckle", :mechanic},
               {"corner/wheel/rim", :wheelwright},
               {"corner/wheel/order", :mechanic},
               {"corner/wheel", :mechanic},
               {"corner/order", :mechanic},
               {"corner", :mechanic}
             ]

      assert %{"trade" => "wheelwright"} =
               Enum.find(Plan.to_data(Plan.flat(van))["tasks"], &(&1["id"] == "corner/wheel/rim"))

      assert [%Plan.Task{trade: :builder}] = Plan.flat(part.("seat")).tasks
    end
  end

  describe "the log" do
    defp plan_data do
      %{"tasks" => [%{"id" => "a", "waits" => []}, %{"id" => "b", "waits" => ["a"]}]}
    end

    defp run(steps) do
      Enum.reduce(steps, Log.new(Clock.new(start: 0)), fn {wall, kind, data}, log ->
        {:ok, log} = Log.add(log, kind, wall: wall, order: "o1", place: "vehicles", who: "binh", data: data)
        log
      end)
    end

    test "the events of an order, in the order of their time, and back from JSON" do
      log =
        run([
          {1, "requested", %{}},
          {2, "plan_made", plan_data()},
          {3, "task_started", %{"task" => "a"}},
          {5, "task_done", %{"task" => "a"}},
          {5, "task_started", %{"task" => "b"}},
          {9, "task_done", %{"task" => "b"}},
          {9, "done", %{}}
        ])

      assert Log.check(log) == :ok
      assert hd(Log.events(log)).at == 86_400 and List.last(Log.events(log)).kind == "done"
      assert "task_started" in Log.kinds()
      json = Log.to_json(log)
      assert {:ok, back} = Log.from_json(json)
      assert Log.events(back) == Log.events(log) and back.clock == log.clock
      assert {:ok, _} = Log.add(Log.new(Clock.new()), "requested")
    end

    test "the log refuses an unknown kind and an event before the last one" do
      log = run([{5, "requested", %{}}])
      assert {:error, {:unknown_kind, "lunch"}} = Log.add(log, "lunch", wall: 6)
      assert {:error, {:before_last, _}} = Log.add(log, "plan_made", wall: 4)
    end

    test "a log with a bad order of events is refused" do
      bad = fn steps -> run([{1, "plan_made", plan_data()} | steps]) |> Log.check() |> elem(1) |> elem(0) end

      assert bad.([{2, "task_started", %{"task" => "b"}}]) == :waits_not_done
      assert bad.([{2, "task_started", %{"task" => "a"}}, {3, "task_started", %{"task" => "a"}}]) == :started_twice
      assert bad.([{2, "task_done", %{"task" => "a"}}]) == :not_started

      assert bad.([
               {2, "task_started", %{"task" => "a"}},
               {3, "task_done", %{"task" => "a"}},
               {4, "task_done", %{"task" => "a"}}
             ]) == :done_twice

      assert bad.([{2, "task_started", %{"task" => "z"}}]) == :unknown_task

      no_plan = run([{2, "task_started", %{"task" => "a"}}])
      assert {:error, {:no_plan, _}} = Log.check(no_plan)

      # A log changed by hand: a wrong time, an event before the last, an unknown kind.
      log = run([{1, "requested", %{}}, {2, "done", %{}}])
      [first, second] = Log.events(log)
      assert {:error, {:wrong_time, _}} = Log.check(%{log | events: [%{second | at: 1}, first]})
      assert {:error, {:before_last, _}} = Log.check(%{log | events: [first, second]})
      assert {:error, {:unknown_kind, _}} = Log.check(%{log | events: [%{second | kind: "lunch"}, first]})

      json = Log.to_json(log) |> String.replace("done", "lunch")
      assert {:error, {:unknown_kind, _}} = Log.from_json(json)
    end
  end
end
