defmodule World.HouseTest do
  # The people build a tube house as on a real site (plan 0002, D4).
  use ExUnit.Case, async: true

  alias World.{Build, BuildSpec, Check, Detail, Drawing, Log, Orders, Scene}
  alias World.Orders.Blueprints

  @moduletag :tmp_dir

  defp house(level, options) do
    {:ok, full} = Orders.check(%{"blueprint" => "tube_house", "options" => options})
    {:ok, b} = Blueprints.fetch("tube_house")
    Detail.with(level, fn -> b.build.(full["options"]) end)
  end

  defp names(item), do: Enum.map(item.nodes, &elem(&1, 0))
  defp triangles(item, level), do: Scene.triangles(Build.scene(item, level: level))
  defp part(item, name), do: item.nodes |> List.keyfind(name, 0) |> elem(1)

  test "a tube house of three floors: the frame, the walls, the finish, the openings, the roof, at each level" do
    near = house(:near, %{})
    assert near.kind == :house and Check.model(near) == :ok
    assert ~w(slab_0 col_1 slab_1 col_2 slab_2 col_3 slab_3) -- names(near) == []
    # The bricks of a wall with a render are temporary; a bare wall keeps them.
    refute "wall_front_1_1" in names(near)
    assert "wall_left_2_3" in names(near)
    # The plaster of a painted wall is under its paint; a plastered wall keeps it.
    refute "plaster_front_1" in names(near)
    assert ~w(paint_front_1 plaster_back_1 opening_front_1 flight_1 flight_2 iron_1 iron_2 roof) -- names(near) == []
    refute "flight_3" in names(near) or "iron_3" in names(near) or "paint_back_1" in names(near)

    # The columns, 220 mm, at each side at each end of the four bays.
    assert length(part(near, "col_1").shapes) == 10
    # The stair: risers of at most 0.17 m.
    assert part(near, "flight_1").sources |> hd() =~ "22 risers"

    mid = house(:mid, %{})
    far = house(:far, %{})
    assert Check.model(mid) == :ok and Check.model(far) == :ok
    assert triangles(near, :near) > triangles(mid, :mid) and triangles(mid, :mid) > triangles(far, :far)
    assert triangles(far, :far) <= 300
    refute "flight_1" in names(mid) or "col_1" in names(far) or "wall_left_1_1" in names(far)
    {{x0, y0, z0}, {x1, y1, z1}} = Scene.bounds(Build.scene(far, level: :far))
    assert_in_delta x1 - x0, 4.03, 0.05
    # The balconies are not in the far form: the render at each end.
    assert_in_delta y1 - y0, 16.03, 0.01
    assert_in_delta z0, -0.1, 1.0e-6
    assert_in_delta z1, 3.6 + 2 * 3.3 + 1.0, 1.0e-6
  end

  test "a house of other options: one floor, a metal roof, no balcony, bare and plastered walls, a door" do
    options = %{
      "floors" => 1,
      "roof" => "metal",
      "balcony" => 0.0,
      "finish_front" => "bare",
      "finish_left" => "plaster",
      "openings" => [
        %{"side" => "front", "floor" => 1, "kind" => "door", "x" => 0.5, "width" => 0.9, "height" => 2.2, "sill" => 0.0}
      ]
    }

    near = house(:near, options)
    assert Check.model(near) == :ok
    assert "wall_front_1_1" in names(near) and "plaster_left_1" in names(near)
    refute "flight_1" in names(near) or "iron_1" in names(near) or "opening_back_1" in names(near)
    assert Enum.any?(part(near, "roof").shapes, &(&1.material == :roof_corrugated))
    assert triangles(house(:far, options), :far) <= 300

    # A terrace with no parapet: no roof at all.
    d = %{
      "nodes" => [
        %{"name" => "plan", "skill" => %{"house_plan" => %{"floors" => 1, "parapet" => 0.0}}},
        %{"name" => "slab_0", "skill" => %{"footing" => %{}}, "from" => ["plan"]},
        %{"name" => "roof", "skill" => %{"roof" => %{}}, "from" => ["plan"]}
      ]
    }

    assert names(Detail.with(:near, fn -> Drawing.build(d) end)) == ["slab_0"]
  end

  test "the people build a tube house: the bytes of a build with no world, the bricks in the stream, the replay",
       %{tmp_dir: dir} do
    {:ok, job} = Orders.job(%{"blueprint" => "tube_house", "options" => %{}}, "near")
    {:ok, id} = World.build(Map.put(job, :budget, %{"workers" => 16}))
    assert {:ok, r} = World.await(id, 120_000)
    assert r.glb == World.GLB.encode(job.scene.(job.item.(:near), []))
    assert Log.check(r.log) == :ok
    assert BuildSpec.replay([r.log], dir) == :ok

    elements = for %{kind: "element", data: d} <- Log.events(r.log), do: d["task"]
    assert "wall_front_1_1" in elements and "plaster_front_1" in elements
    trades = for %{kind: "hired", data: %{"trade" => t}} <- Log.events(r.log), uniq: true, do: t
    assert ~w(concreter engineer joiner mason painter plasterer roofer smith) -- trades == []
    assert Drawing.estimate(job.drawing, :near) > 0
  end

  test "the errors of the data of the skills of a house" do
    d = %{
      "nodes" => [
        %{"name" => "plan", "skill" => %{"house_plan" => %{"width" => 99}}},
        %{"name" => "w", "skill" => %{"course" => %{"side" => "top"}}, "temporary" => 3}
      ]
    }

    assert {:error, errors} = Orders.check(%{"blueprint" => "drawing", "options" => %{"drawing" => d}})

    assert Enum.map(errors, & &1["path"]) == [
             "options.drawing.nodes.0.skill.house_plan.width",
             "options.drawing.nodes.1.temporary",
             "options.drawing.nodes.1.skill.course.side"
           ]
  end
end
