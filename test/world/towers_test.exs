defmodule World.TowersTest do
  use ExUnit.Case, async: true

  alias World.{Build, Check, Detail, Mass, Mesh, Orders, Scene, Towers}

  doctest World.Sizes

  defp at(level, fun), do: Detail.with(level, fun)
  defp scene(item, level), do: Build.scene(item, level: level)
  defp roles(s), do: for(n <- s.nodes, p <- n.primitives, uniq: true, do: p.material)
  defp part(item, name), do: item.nodes |> List.keyfind(name, 0) |> elem(1)

  test "the lighthouse of Vũng Tàu: 18 m to the dome, the pilasters, the gallery, the lantern, the house, the checks" do
    for level <- [:near, :mid, :far] do
      item = at(level, &Towers.vung_tau/0)
      assert item.kind == :tower and Check.model(item) == :ok, "#{level}"
    end

    near = at(:near, &Towers.vung_tau/0)
    s = scene(near, :near)
    assert :glass in roles(s) and :roof_clay in roles(s) and :brick in roles(s)
    tower = part(near, "hai_dang_vung_tau")

    {{_, _, z0}, {_, _, z1}} =
      tower.shapes |> Enum.reject(&(&1.material == :steel)) |> Enum.flat_map(& &1.points) |> World.Vec.bounds()

    assert_in_delta z0, 0.0, 1.0e-9
    # The dome (its top at 18 m) and the ball on it, the rod to 21 m.
    assert_in_delta z1, 18.15, 0.01
    {_, {_, _, rod}} = Scene.bounds(s)
    assert_in_delta rod, 21.1, 0.01

    # The four pilasters out to 5.1 m, flared to 6.4 m at the foot.
    pilasters = Enum.filter(tower.shapes, &(length(&1.points) == 10))
    assert length(pilasters) == 4

    {{x0, _, _}, {x1, _, _}} =
      pilasters |> Enum.flat_map(& &1.points) |> Enum.filter(&(elem(&1, 2) < 0.31)) |> World.Vec.bounds()

    assert_in_delta x1 - x0, 6.4 * :math.cos(:math.pi() / 4) + 0.7 * :math.sin(:math.pi() / 4), 0.05

    # Hollow at near: the stair of 55 steps, the wall with the door; the
    # far form in at most 300 triangles.
    stair = part(near, "cau_thang")
    assert length(stair.shapes) == 56 and stair.params["steps"] == 55
    mid = at(:mid, &Towers.vung_tau/0)
    assert Mass.of(mid).mass > Mass.of(near).mass
    assert Scene.triangles(scene(at(:far, &Towers.vung_tau/0), :far)) <= 300

    # The house to the north-west of the tower, its door to the outside.
    house = part(near, "nha_quan_dang")
    {{hx0, hy0, _}, {hx1, hy1, hz}} = house.shapes |> Enum.flat_map(& &1.points) |> World.Vec.bounds()
    assert hx1 < 0.5 and hx0 < -4.0 and hy0 > 2.0 and hy1 > 8.0 and hz > 4.0
    assert [_, _, _] = house.shapes

    # The sizes and their sources, the light, the ports, the collision.
    sizes = Map.new(near.extras["sizes"], &{&1["name"], &1})
    assert sizes["height"]["value"] == 18.0 and sizes["height"]["source"] =~ "18 m"
    assert sizes["lantern"]["value"] == [15.4, 17.3, 2.2] and sizes["lantern"]["source"] =~ "measured on the photo"
    assert sizes["door"]["source"] == "estimate (no source)"
    assert sizes["pilasters"] |> Map.has_key?("unit") == false
    assert near.extras["light"] == %{"color" => "white", "flashes" => 2, "period" => 10.0, "range" => 23}
    assert ~w(door light view) == Enum.map(near.extras["ports"], & &1["kind"]) |> Enum.sort()
    assert length(near.extras["collision"]) == 6
  end

  test "a tower of other options: no pilasters, no house, solid, no light" do
    item = at(:near, fn -> Towers.tower(pilasters: 0, bands: [], platform: {4.0, 0.2}) end)
    assert Check.model(item) == :ok
    assert [_] = item.nodes
    refute Map.has_key?(Map.new(item.extras["sizes"], &{&1["name"], &1}), "house")
    assert item.extras["light"] == nil
    assert length(item.extras["collision"]) == 5
    assert Enum.all?(part(item, "thap").shapes, &(Mesh.volume(&1.points, &1.faces) > 0))
    assert Scene.triangles(scene(at(:far, fn -> Towers.tower() end), :far)) <= 300
  end

  test "the blueprint tower: an order, its receipt, the errors of its house, its light and its sources" do
    order = %{
      "blueprint" => "tower",
      "options" => %{
        "house" => %{"outline" => [[3, 3], [6, 3], [6, 6], [3, 6]], "height" => 3},
        "light" => %{"color" => "red", "flashes" => 1, "period" => 4, "range" => 8},
        "sources" => %{"height" => "A drawing."}
      }
    }

    assert {:ok, full} = Orders.check(order)
    assert full["options"]["pilasters"] == 4
    assert {:ok, receipt} = Orders.build(order, "far", "receipt")
    sizes = JSON.decode!(receipt)["sizes"]
    assert Enum.find(sizes, &(&1["name"] == "height"))["source"] == "A drawing."
    assert Enum.find(sizes, &(&1["name"] == "light"))["value"]["color"] == "red"

    for {options, path} <- [
          {%{"house" => %{"outline" => [[0, 0], [1, 0]], "height" => 3}}, "options.house"},
          {%{"house" => %{"outline" => [[0, 0], [100, 0], [0, 1]], "height" => 3}}, "options.house.outline"},
          {%{"light" => %{"color" => "red"}}, "options.light"},
          {%{"sources" => %{"colour" => "x"}}, "options.sources.colour"},
          {%{"height" => 1.0}, "options.height"}
        ] do
      assert {:error, [%{"path" => ^path} | _]} = Orders.check(%{"blueprint" => "tower", "options" => options})
    end
  end
end
