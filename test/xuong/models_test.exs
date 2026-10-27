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
