defmodule World.OSMTest do
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Scene}
  alias World.Places.OSM

  doctest OSM

  test "the street of Ba Cu: its buildings, its roads and its trees, with the attribution of OpenStreetMap" do
    assert OSM.tiles() == ["ba_cu"]
    t = OSM.tile("ba_cu")
    s = Detail.with(:far, fn -> OSM.street("ba_cu") end)
    assert s.kind == :street and s.extras["attribution"] == "© OpenStreetMap contributors"
    assert World.Check.model(s) == :ok
    assert Enum.count(s.nodes, fn {n, _, _} -> String.starts_with?(n, "tree_") end) == length(t["trees"])
    {_, buildings, _} = List.keyfind(s.nodes, "buildings", 0)
    assert length(buildings.shapes) == length(t["buildings"])

    # The box of the street is the box of the tile, about 200 m.
    [w, l, h] = Build.scene(s, level: :far).extras["size"]
    assert w > 190 and w < 260 and l > 190 and l < 260
    assert_in_delta h, 5 * 3.5 + 0.1, 25
    assert_raise ArgumentError, fn -> OSM.tile("nope") end
  end

  test "the height of a building and the width of a road from their tags" do
    assert OSM.height(%{"height" => "12.5"}) == 12.5
    assert OSM.height(%{"building:levels" => "4"}) == 14.0
    assert OSM.height(%{"building:levels" => "four"}) == 7.0
    assert OSM.height(%{}) == 7.0
    assert OSM.width(%{"width" => "26"}) == 26.0
    assert OSM.width(%{"highway" => "residential"}) == 7.0
    assert OSM.width(%{"highway" => "track"}) == 5.0
  end

  test "the levels of the street stay under their limits" do
    for {level, limit} <- [near: 200_000, mid: 60_000, far: 20_000] do
      tris = Scene.triangles(Build.scene(Detail.with(level, fn -> OSM.street("ba_cu") end), level: level))
      assert tris < limit, "#{level}: #{tris}"
    end
  end
end
