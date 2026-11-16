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

  test "a slab, its cure and a wall: the days of the world in the log, and no wait (one day in a second of the wall)" do
    Application.put_env(:world, :scale, 86_400)

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
    # days of the world (17 s of the wall on the world clock).
    assert at(log, "task_done", "slab") - at(log, "task_started", "slab") == 10 * day
    assert at(log, "task_started", "wall") - at(log, "task_done", "slab") == 7 * day
    assert at(log, "task_done", "wall") - at(log, "task_started", "wall") == div(day, 8)
    assert ms < 5_000
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
end
