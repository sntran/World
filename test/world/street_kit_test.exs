defmodule World.Places.StreetKitTest do
  use ExUnit.Case, async: true

  alias World.{Build, Check, Detail, Mesh, Scene}
  alias World.Places.StreetKit

  defp scene(fun, level), do: Detail.with(level, fn -> Build.scene(fun.(), level: level) end)
  defp roles(s), do: for(n <- s.nodes, p <- n.primitives, uniq: true, do: p.material)
  defp ports(item), do: Build.parts_file("k", item)["ports"]
  defp top(item), do: item |> Build.scene() |> Scene.bounds() |> elem(1) |> elem(2)

  test "each piece of the kit: the kind street, three levels, the checks, the data of the surface" do
    for {name, fun} <- StreetKit.models() do
      item = fun.()
      assert item.kind == :street and item.name == name
      assert Check.model(item) == :ok, name
      [near, mid, far] = for l <- [:near, :mid, :far], do: Scene.triangles(scene(fun, l))
      assert near >= mid and mid >= far and far > 0, name
      assert World.Places.family_of(item) == :houses
    end

    assert length(StreetKit.models()) == 15
  end

  test "the sidewalk: a curb and tiles of 40 cm at near, one slab at mid; the joins of each shape" do
    item = Detail.with(:near, fn -> StreetKit.sidewalk(:straight) end)
    assert_in_delta top(item), 0.15, 1.0e-9
    {_, part, _} = hd(item.nodes)
    tiles = Enum.filter(part.shapes, &(&1.material == :tile_pattern))
    # 2 m by 2.82 m: 5 by 8 tiles.
    assert length(tiles) == 40
    {{x0, _, _}, {x1, _, _}} = Mesh.bounds(hd(tiles))
    assert_in_delta x1 - x0, 0.396, 1.0e-9

    assert length(Enum.filter(elem(hd(StreetKit.sidewalk(:straight).nodes), 1).shapes, &(&1.material == :tile_pattern))) ==
             40

    mid = Detail.with(:mid, fn -> StreetKit.sidewalk(:straight) end)
    assert length(Enum.filter(elem(hd(mid.nodes), 1).shapes, &(&1.material == :tile_pattern))) == 1

    joins = fn fun -> for p <- ports(fun.()), p["kind"] == "join", do: p["normal"] end
    assert length(joins.(fn -> StreetKit.sidewalk(:straight) end)) == 2
    assert length(joins.(fn -> StreetKit.sidewalk(:corner) end)) == 2
    assert length(joins.(fn -> StreetKit.hem(:junction) end)) == 3
    assert length(joins.(fn -> StreetKit.sidewalk(:straight, width: 4.0) end)) == 2
  end

  test "the ramp cut: the curb 3 cm over the street, a slope up to the sidewalk" do
    item = StreetKit.ramp_cut()
    {_, part, _} = hd(item.nodes)
    curb = Enum.find(part.shapes, &(&1.material == :concrete))
    {_, {_, _, z}} = Mesh.bounds(curb)
    assert_in_delta z, 0.03, 1.0e-9
    assert_in_delta top(item), 0.15, 1.0e-9
  end

  test "the gutter: a channel under covers, a grate of iron at near only" do
    assert :iron in roles(scene(fn -> StreetKit.gutter(:straight) end, :near))
    refute :iron in roles(scene(fn -> StreetKit.gutter(:straight) end, :mid))
    {{_, _, z0}, _} = StreetKit.gutter(:corner) |> Build.scene() |> Scene.bounds()
    assert_in_delta z0, -0.4, 1.0e-9
  end

  test "the hẻm: cracks and a patch by its seed; at far the slab only" do
    a = Detail.with(:near, fn -> StreetKit.hem(:straight, seed: 1) end)
    b = Detail.with(:near, fn -> StreetKit.hem(:straight, seed: 2) end)
    assert a == Detail.with(:near, fn -> StreetKit.hem(:straight, seed: 1) end)
    refute a == b
    assert :asphalt in roles(Build.scene(a)) or :asphalt in roles(Build.scene(b))
    assert Scene.triangles(scene(fn -> StreetKit.hem(:corner, width: 2.0) end, :far)) == 12
  end

  test "the pole: 10 m over the ground, the wires of its insulators and its clamp, the ports for its things" do
    item = StreetKit.pole()
    assert_in_delta top(item), 10.0, 1.0e-6
    ports = ports(item)
    high = Enum.filter(ports, &(&1["kind"] == "wire" and &1["line"] == "high"))
    low = Enum.filter(ports, &(&1["kind"] == "wire" and &1["line"] == "low"))
    assert length(high) == 16 and length(low) == 2
    assert ~w(lamp meter transformer) -- Enum.map(ports, & &1["kind"]) == []
    # The coil of cables only at near and mid.
    assert :rubber in roles(scene(&StreetKit.pole/0, :mid))
    refute :rubber in roles(scene(&StreetKit.pole/0, :far))
  end

  test "the transformer, the meter boxes, the lamp and the bin" do
    t = StreetKit.transformer()
    assert t.extras["site"] and World.Mass.of(t).mass == 400.0
    assert Enum.count(ports(t), &(&1["kind"] == "wire")) == 3

    m = StreetKit.meter_box()
    assert Enum.count(ports(m), &(&1["line"] == "house")) == 4
    assert World.Mass.of(m).mass < 15

    assert_in_delta top(StreetKit.lamp()), 8.18, 0.01
    assert Enum.any?(ports(StreetKit.lamp()), &(&1["kind"] == "light"))

    bin = StreetKit.bin()
    {_, _, joint} = List.keyfind(bin.nodes, "nap_thung_rac", 0)
    assert joint.kind == :hinge and joint.role == :open and joint.limits == [0.0, 180.0]
    assert_in_delta top(bin), 1.07, 1.0e-6
    assert bin.materials.plastic["color"] == [34, 120, 64]
  end
end
