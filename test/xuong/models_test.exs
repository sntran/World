defmodule Xuong.ModelsTest do
  use ExUnit.Case, async: true

  alias Xuong.{Build, Detail, Scene}

  # The size of each vehicle from its data page: {width, length, height}
  # in meters, and the tolerance. The width of a model has its mirrors.
  @sizes %{
    "honda_vision_110" => {{0.686, 1.871, 1.101}, 0.03},
    "chevy_bolt_ev" => {{1.98, 4.145, 1.611}, 0.06},
    "ford_transit_148_camper" => {{2.4, 5.98, 2.87}, 0.1},
    "royal_enfield_himalayan" => {{0.84, 2.19, 1.37}, 0.08},
    "touring_bicycle" => {{0.44, 1.72, 1.04}, 0.05}
  }

  @limits %{near: 50_000, mid: 12_000, far: 5_000}

  for {name, fun} <- Xuong.Models.all(), Map.has_key?(@sizes, name) do
    @name name
    @fun fun

    test "#{name}: the size, the levels, the joints and the parts" do
      scenes = for level <- [:near, :mid, :far], do: {level, Build.scene(Detail.with(level, @fun), level: level)}

      for {level, scene} <- scenes do
        tris = Scene.triangles(scene)
        assert tris <= @limits[level], "#{@name} has #{tris} triangles at #{level}"
      end

      [{:near, near}, {:mid, mid}, {:far, far}] = scenes
      assert Scene.triangles(near) > Scene.triangles(mid) and Scene.triangles(mid) > Scene.triangles(far)

      {{w, l, h}, tol} = @sizes[@name]
      [sw, sl, sh] = near.extras["size"]
      assert abs(sw - w) <= tol and abs(sl - l) <= tol and abs(sh - h) <= tol, "#{@name}: #{inspect([sw, sl, sh])}"

      roles = for n <- near.nodes, r = n.extras["role"], do: r
      assert Enum.count(roles, &(&1 == "wheel")) >= 2
      assert "steer" in roles
      assert near.extras["kind"] == "vehicle"
      assert near.extras["sources"] != []
      assert Build.parts(@fun.()) != []
    end
  end

  # Each van has the size of Ford: the length and the height of the data,
  # and the width with its mirrors.
  for name <- Xuong.Models.Van.models() do
    @name name

    test "the van #{name}: its size, its levels and its doors" do
      m = Xuong.Models.Van.model(@name)
      fun = fn -> Xuong.Models.Van.build(@name) end
      scenes = for level <- [:near, :mid, :far], do: {level, Build.scene(Detail.with(level, fun), level: level)}

      # The windows all around fit in the limits too.
      passenger = fn -> Xuong.Models.Van.build(@name, windows: :passenger) end

      for level <- [:near, :mid, :far],
          scene <- [Keyword.fetch!(scenes, level), Build.scene(Detail.with(level, passenger), level: level)] do
        tris = Scene.triangles(scene)
        assert tris <= @limits[level], "#{@name} has #{tris} triangles at #{level}"
      end

      [{:near, near} | _] = scenes
      [sw, sl, sh] = near.extras["size"]
      assert abs(sl - m["length"]) <= 0.06 and abs(sh - m["height"]) <= 0.05, inspect(near.extras["size"])
      assert sw > m["width"] and sw < m["width"] + 0.5

      van = fun.()
      joints = for {name, _, %{kind: kind}} <- van.nodes, into: %{}, do: {name, kind}
      assert %{"sliding_door" => :slides, "rear_door_right" => :turns, "rear_door_left" => :turns} = joints
    end
  end

  test "the hull of a van: its span, its sections and its back" do
    alias Xuong.Models.Hull
    h = Xuong.Models.Van.hull("transit_148")
    {d0, d1} = Hull.span(h)
    assert d0 < 0.01 and abs(d1 - h.length) < 0.01
    assert Hull.z_high(h, 3.0) == h.top
    assert Hull.half_width(h, 3.0) == h.width / 2 and Hull.half_width(h, d1) < h.width / 2

    # The back steps to the front over the bumper, and has no face over the top.
    assert Hull.back(h, 0.7) < Hull.back(h, 1.6)
    assert Hull.back(h, h.top + 1.0) == nil

    # A section is a closed loop, and a wider skin is bigger.
    section = Hull.section(h, 3.0)
    assert length(section) > 8
    assert Hull.area(Hull.section(h, 3.0, 0.01)) > Hull.area(section)
  end

  test "the hood of the van opens on the engine bay, with the items of DIY in it" do
    van = Xuong.Models.FordTransit.model()
    assert {_, _, %{kind: :turns, role: :lid, limits: [0, 60]}} = List.keyfind(van.nodes, "hood", 0)

    parts = Map.new(Build.parts(van), &{&1["name"], &1["count"]})
    assert parts["redarc_bcdc1250d"] == 1 and parts["second_alternator_250a"] == 1
    assert parts["engine_ford_3_5_v6"] == 1 and parts["radiator_fan_transit"] == 1

    # The parts in the bay are only in the near level: at mid, the joint of
    # the fan stays, with no mesh.
    fan = fn level ->
      scene = Build.scene(Detail.with(level, &Xuong.Models.FordTransit.model/0), level: level)
      Enum.find(scene.nodes, &(&1.name == "radiator_fan")).primitives
    end

    assert fan.(:near) != [] and fan.(:mid) == []
  end

  test "the level of detail" do
    assert Detail.level() == :near

    assert Detail.with(:far, fn -> {Detail.level(), Detail.sides(24), Detail.smooth(2), Detail.step(0.1)} end) ==
             {:far, 6, 0, 0.4}

    assert Detail.with(:mid, fn -> {Detail.sides(4), Detail.smooth(2)} end) == {4, 1}
    assert Detail.with(:mid, fn -> Detail.with(:far, fn -> :ok end) && Detail.level() end) == :mid
    assert Detail.level() == :near
  end

  test "a body loft with arches is closed" do
    mesh = Xuong.Models.Body.loft([{0.0, 0.2, 1.0, 0.8, 4}, {2.0, 0.2, 1.0, 0.8, 4}], [{1.0, 0.3, 0.35}], :paint)
    tris = Xuong.Mesh.triangles(mesh)
    assert length(tris) > 100
    # The bottom over the axle is above the top of the wheel.
    low = for {{_, y, z}, _} <- tris, abs(y - 1.0) < 0.01, do: z
    assert Enum.min(low) >= 0.3 + 0.35 - 0.05
  end
end
