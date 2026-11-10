defmodule World.SiteTest do
  # One clock for the world in days of a site (plan 0006, D1 and D2; R1):
  # the rates of the crews, the days of a task and the wait after it, and
  # a construction whose tasks end at their days on the clock.
  use ExUnit.Case, async: true

  alias World.{Clock, Detail, Drawing, Log, Orders, Site, Standards}

  doctest Site

  test "the clock of the world: one start for the node, the scale of the application" do
    a = Clock.world()
    assert Clock.world().start == a.start and a.scale == Application.get_env(:world, :scale)
    # In the tests, 1,000 days in one second of the wall clock.
    assert a.scale == 86_400_000 and Clock.to_wall(a, 1000 * Clock.day()) == 1000
    assert World.Supervisor.scale(%{}) == :ok
  end

  test "WORLD_SCALE sets the scale of the clock of the world" do
    old = Application.get_env(:world, :scale)
    World.Supervisor.scale(%{"WORLD_SCALE" => "86400"})
    assert Clock.world().scale == 86_400
    Application.put_env(:world, :scale, old)
  end

  test "each rate and each cure has its source or is an estimate, for each method" do
    for w <- Site.works(), m <- Site.methods() do
      r = Site.rate(w, m)
      assert r.rate > 0 and r.crew >= 1 and is_binary(r.unit) and r.source =~ ~r/estimate|ACI|TCVN/, w
    end

    for c <- Site.cures(), m <- Site.methods(), do: assert(Site.cure(c, m) > 0)
    assert Site.cure("strip") == 1.0 and Site.cure("lift", "1974") == 4.0
    assert Site.work_of(%{}) == %{}
    assert Standards.names({"site", "takeoff"}) -- ~w(brick cement mortar paint rebar roof_sheet steel) == []
  end

  test "the schedule of the statue on Núi Nhỏ: each band after the cure of the band under it" do
    {:ok, job} = Orders.job(Drawing.raw("tuong_chua_kito_vua"), "near")
    d = job.drawing
    today = Site.schedule(d)
    old = Site.schedule(d, "1974")
    last = fn sc -> sc |> Map.values() |> Enum.map(&elem(&1, 1)) |> Enum.max() end
    # About a year with the machines of today; more than two years by hand.
    assert last.(today) > 300 and last.(today) < 420
    assert last.(old) > 2 * last.(today)

    for i <- 2..8 do
      {_, under} = today["pour_#{i - 1}"]
      {form, _} = today["form_#{i}"]
      {pour, _} = today["pour_#{i}"]
      # The form of a band waits for the cure of the band under it (2 days).
      assert_in_delta form, under + 2.0, 1.0e-9
      assert pour >= elem(today["form_#{i}"], 1)
    end

    # The work of the nodes: the concrete of the base, a band of the cast.
    be = Enum.find(d["nodes"], &(&1["name"] == "be"))
    assert_in_delta be["work"]["concrete"], 0.334 * 14.5 * 14.5 * 7.7, 1.0e-6
    assert {days, 2.0} = Site.task(d, "pour_3", %{})
    assert_in_delta days, 0.123 * 27.5 * 27.5 * 0.3 / 25 + 9.84 * 27.5 * 27.5 * 0.3 / 600, 1.0e-9
    # A node with no work in its data and no takeoff: one hour.
    plain = %{"nodes" => [%{"name" => "a", "skill" => %{"note" => %{}}}]}
    assert Site.task(plain, "a", %{}) == {0.125, 0.0}
    assert Site.schedule(plain) == %{"a" => {0.0, 0.125}}
  end

  test "the work of a node is checked: a work of the rates and its amount, a cure of the table" do
    node = fn more -> %{"nodes" => [Map.merge(%{"name" => "a", "skill" => %{"note" => %{}}}, more)]} end
    assert {:ok, _} = Drawing.check(node.(%{"work" => %{"concrete" => 2.0}, "cure" => "lift"}), "d")
    assert {:error, e} = Drawing.check(node.(%{"work" => %{"gold" => 1, "concrete" => -1}, "cure" => "dry"}), "d")
    msgs = Enum.map_join(e, "; ", &elem(&1, 1))
    assert msgs =~ "is not a work of a site" and msgs =~ "must be a number" and msgs =~ "must be one of"
    assert {:error, [{"d.nodes.0.work", "must be an object" <> _}]} = Drawing.check(node.(%{"work" => 3}), "d")
  end

  test "a construction: each task ends at its days on the clock, and the task after a cure waits for it" do
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

    id = "site-#{System.unique_integer([:positive])}"
    job = %{id: id, item: fn level -> Detail.with(level, fn -> Drawing.build(d) end) end, drawing: d}
    {:ok, ^id} = World.build(job)
    assert {:ok, %{log: log}} = World.await(id, 30_000)
    assert Log.check(log) == :ok
    at = fn kind, task -> Enum.find(Log.events(log), &(&1.kind == kind and &1.data["task"] == task)) end
    day = Clock.day()
    # 250 m3 of concrete: 10 days of a crew with a pump; then 7 days to set.
    assert at.("task_started", "slab").data["days"] == 10.0 and at.("task_started", "slab").data["wait"] == 7.0
    slab = at.("task_done", "slab").at - at.("task_started", "slab").at
    assert slab >= 10 * day and slab < 10 * day + 200 * Clock.world().scale
    assert at.("task_started", "wall").at - at.("task_done", "slab").at >= 7 * day
    # The wall: no work and no takeoff, one hour.
    assert at.("task_started", "wall").data["days"] == 0.125
  end
end
