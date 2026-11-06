defmodule World.Buildings.LotTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.{Build, Check, Detail, GLB, Orders, Scene, Surface}
  alias World.Buildings.Lot

  # The limits of the triangles of a whole house (Vũng Tàu, W22).
  @limits %{near: 40_000, mid: 3_000, far: 300}

  defp scene(opts, level), do: Detail.with(level, fn -> Build.scene(Lot.house(opts), level: level) end)

  defp roles(scene), do: for(n <- scene.nodes, p <- n.primitives, uniq: true, do: p.material)

  test "a tube house: its parts, its roles, its extras, a check that passes" do
    house = Lot.house()
    assert house.kind == :house and house.name == "nha_ong"
    assert World.Places.family_of(house) == :houses
    assert Check.model(house) == :ok
    assert %{"surface" => %{"corners" => corners}, "lot" => lot, "house" => info} = house.extras
    assert lot == %{"width" => 4.0, "depth" => 16.0}
    assert corners == [[-2.0, 8.0], [2.0, 8.0], [-2.0, -8.0], [2.0, -8.0]]
    assert info["floors"] == 3 and info["ground"] == "cua_cuon"
    # Three floors and a parapet: 0.2 + 3.8 + 3.4 * 2 + 1.1 m.
    assert_in_delta info["height"], 11.9, 1.0e-9
    assert house.extras["paint_age"] == 0.3 and house.extras["seed"] == 1

    near = scene([], :near)

    assert Enum.sort(roles(near)) ==
             Enum.sort([:aluminum, :concrete, :glass, :iron, :plaster, :tile_granite, :metal_shutter])

    {{_, _, z0}, {_, _, z1}} = Scene.bounds(near)
    assert_in_delta z0, 0.0, 1.0e-6
    assert_in_delta z1, 11.9, 1.0e-6
  end

  test "the roll-up shutter is a slide up into its box, at near and mid only" do
    house = Lot.house()
    {_, _, joint} = List.keyfind(house.nodes, "shutter_nha_ong", 0)
    assert joint.kind == :slide and joint.role == :open
    assert joint.limits == [0.0, 3.0]
    far = Detail.with(:far, fn -> Lot.house() end)
    refute List.keymember?(far.nodes, "shutter_nha_ong", 0)
  end

  test "each level is in the limits of a town, and the far level keeps the roof" do
    for opts <- [
          [],
          [floors: 8, style: :old, roof: :clay, ground: :cua_xep, left: :free, right: :free, extension: true]
        ] do
      for level <- [:near, :mid, :far] do
        s = scene(opts, level)
        assert Scene.triangles(s) <= @limits[level], "#{inspect(opts)} #{level}: #{Scene.triangles(s)}"
      end

      far = scene(opts, :far)
      if opts != [], do: assert(:roof_clay in roles(far))
    end
  end

  test "the same order gives the same bytes; the seed changes the details, the paint age only the extras" do
    glb = fn opts -> GLB.encode(scene(opts, :near)) end
    assert glb.(seed: 5) == glb.(seed: 5)
    refute glb.(seed: 5) == glb.(seed: 6)

    young = scene([paint_age: 0.1], :near)
    old = scene([paint_age: 0.9], :near)
    assert young.nodes == old.nodes
    assert young.extras["paint_age"] == 0.1 and old.extras["paint_age"] == 0.9
  end

  test "the walls have UVs in meters and the height and the distance to a corner in their data" do
    s = scene([], :mid)
    prims = for n <- s.nodes, p <- n.primitives, do: p
    assert Enum.all?(prims, &(&1.uvs != nil and &1.uvs2 != nil and &1.data != nil))

    # Each point of the data: red is the height over 32 m, green the
    # distance to a corner over 4 m.
    for p <- prims, {{h, d}, {r, g, b, a}} <- Enum.zip(p.uvs2, p.data) do
      assert_in_delta r, min(max(h, 0.0) / Surface.height_scale(), 1.0), 1.0e-9
      assert_in_delta g, min(d / Surface.reach_scale(), 1.0), 1.0e-9
      assert b == 0.0 and a == 1.0
    end

    # A side wall has points at its corners, 4 m from them, and at its
    # middle.
    plaster = Enum.filter(prims, &(&1.material == :plaster))
    ds = for p <- plaster, {_, d} <- p.uvs2, uniq: true, do: Float.round(d, 3)
    assert 0.0 in ds and 4.0 in ds and 8.0 in ds

    # The GLB has the two sets and the data.
    json = s |> GLB.encode() |> glb_json()
    attrs = for m <- json["meshes"], p <- m["primitives"], do: p["attributes"]
    assert Enum.all?(attrs, &Map.has_key?(&1, "TEXCOORD_1")) and Enum.all?(attrs, &Map.has_key?(&1, "COLOR_0"))
  end

  test "the surface data of a point, and a node with instances keeps none" do
    assert Surface.point({1.0, 2.0, 8.0}, {1.0, 0.0, 0.0}, []) == {{2.0, 8.0}, {8.0, 0.0}, {0.25, 0.0, 0.0, 1.0}}
    assert {{1.0, 2.0}, _, _} = Surface.point({1.0, 2.0, -3.0}, {0.0, 0.0, -1.0}, [{0.0, 0.0}])
    assert {_, _, {+0.0, 1.0, +0.0, 1.0}} = Surface.point({20.0, 0.0, -1.0}, {0.0, 1.0, 0.0}, [{0.0, 0.0}])

    prim = %Scene.Primitive{positions: [{0.0, 0.0, 1.0}], normals: [{0.0, 1.0, 0.0}], indices: [0, 0, 0]}
    copies = %Scene.Node{name: "bricks", primitives: [prim], instances: [%World.Frame{}]}
    one = %Scene.Node{name: "wall", primitives: [prim]}
    s = Surface.apply(%Scene{nodes: [copies, one]}, [[0, 0]])
    assert [%{primitives: [%{data: nil}]}, %{primitives: [%{data: [{_, +0.0, +0.0, 1.0}]}]}] = s.nodes
  end

  test "the sides: shared, free with windows, bare brick; the front of patterned tiles" do
    s = scene([left: :bare, right: :free, finish: :pattern, floors: 4, depth: 20.0], :near)
    assert :brick_ong in roles(s) and :tile_pattern in roles(s)
    refute :tile_granite in roles(s)
    # The far level: one front sheet of the tiles.
    assert :tile_pattern in roles(scene([finish: :pattern], :far))
    assert :tile_granite in roles(scene([floors: 1], :far))
  end

  test "the old style: wood shutters, rails of bars, a cửa xếp with a room behind it, rebar on the terrace" do
    house = Detail.with(:near, fn -> Lot.house(style: :old, ground: :cua_xep, seed: 2) end)
    assert Check.model(house) == :ok
    s = Build.scene(house, level: :near)
    assert :wood in roles(s) and :tile_granite in roles(s)
    {_, iron, _} = List.keyfind(house.nodes, "iron_nha_ong", 0)
    # The rebar goes 0.8 m over the parapet.
    top = iron.shapes |> Enum.map(fn m -> m |> World.Mesh.bounds() |> elem(1) |> elem(2) end) |> Enum.max()
    assert_in_delta top, house.extras["house"]["height"] + 0.8, 1.0e-6
  end

  test "a door with a gate, a narrow lot, one floor, a room at the back and a room on the terrace" do
    for opts <- [
          [ground: :door_gate, width: 3.0, depth: 8.0, floors: 1, extension: true, terrace_room: true],
          [ground: :door_gate, width: 5.0, roof: :clay, left: :free, extension: true, terrace_room: true],
          [ground: :open_shop, roof: :corrugated, width: 3.5, style: :old, seed: 9]
        ],
        level <- [:near, :mid, :far] do
      house = Detail.with(level, fn -> Lot.house(opts) end)
      assert Check.model(house) == :ok, "#{inspect(opts)} #{level}: #{inspect(Check.model(house))}"
      s = Build.scene(house, level: level)
      assert Scene.triangles(s) <= @limits[level]
    end

    ext = Detail.with(:mid, fn -> Lot.house(extension: true, terrace_room: true, depth: 10.0) end)
    assert List.keymember?(ext.nodes, "extension_nha_ong", 0)
    assert List.keymember?(ext.nodes, "terrace_room_nha_ong", 0)
    assert length(ext.extras["surface"]["corners"]) == 6
    # A room on the terrace needs a flat roof.
    pitched = Lot.house(terrace_room: true, roof: :clay)
    refute List.keymember?(pitched.nodes, "terrace_room_nha_ong", 0)
  end

  property "each choice of the options gives a house that passes the checks" do
    c = Lot.choices()

    check all(
            style <- member_of(c.style),
            roof <- member_of(c.roof),
            ground <- member_of(c.ground),
            finish <- member_of(c.finish),
            left <- member_of(c.side),
            right <- member_of(c.side),
            floors <- integer(1..8),
            width <- float(min: 3.0, max: 6.0),
            depth <- float(min: 8.0, max: 25.0),
            extension <- boolean(),
            seed <- integer(0..1000),
            level <- member_of([:mid, :far]),
            max_runs: 12
          ) do
      opts = [
        style: style,
        roof: roof,
        ground: ground,
        finish: finish,
        left: left,
        right: right,
        floors: floors,
        width: width,
        depth: depth,
        extension: extension,
        terrace_room: true,
        seed: seed
      ]

      house = Detail.with(level, fn -> Lot.house(opts) end)
      assert Check.model(house) == :ok, "#{inspect(opts)} #{level}"
      assert Scene.triangles(Build.scene(house, level: level)) <= @limits[level]
    end
  end

  test "the options are in their limits" do
    for {opts, message} <- [
          {[width: 2.5], "width"},
          {[depth: 30], "depth"},
          {[floors: 9], "floors"},
          {[style: :modern], "style"},
          {[left: :open], "left"},
          {[kind: :villa], "kind"}
        ] do
      assert_raise ArgumentError, ~r/#{message}/, fn -> Lot.house(opts) end
    end
  end

  test "the blueprint lot_house: an order of a house, its levels, the errors of its options" do
    order = %{"blueprint" => "lot_house", "options" => %{"floors" => 2, "seed" => 3, "ground" => "open_shop"}}
    assert {:ok, full} = Orders.check(order)
    assert full["options"]["width"] == 4.0 and full["options"]["kind"] == "tube"
    assert {:ok, far} = Orders.build(order, "far", "glb")
    assert {:ok, ^far} = Orders.build(order, "far", "glb")
    assert hd(glb_json(far)["scenes"])["extras"]["house"]["ground"] == "open_shop"

    assert {:error, [%{"path" => "options.width"}]} =
             Orders.check(%{"blueprint" => "lot_house", "options" => %{"width" => 7}})
  end

  test "the ports of the small parts: on the front, on the roof, and the wires, in the axes of the GLB" do
    file = Build.parts_file("h", Lot.house(floors: 3, seed: 1))
    ports = file["ports"]
    kinds = ports |> Enum.map(& &1["kind"]) |> Enum.uniq() |> Enum.sort()
    assert kinds -- Lot.port_kinds() == []
    assert ~w(ac altar antenna dish laundry number sign water_tank wire) -- kinds == []
    assert Enum.all?(ports, &(is_list(&1["position"]) and is_list(&1["size"]) and not Map.has_key?(&1, "at")))

    # One AC unit for each floor over the ground floor, on the face of the
    # front wall (z of glTF is y of World: the front at 8 m), looking out.
    acs = Enum.filter(ports, &(&1["kind"] == "ac"))
    assert Enum.map(acs, & &1["floor"]) == [1, 2]
    assert Enum.all?(acs, &(Enum.at(&1["position"], 2) == 8.0 and &1["normal"] == [0.0, 0.0, 1.0]))

    # The text of the sign is in the sign; the roof ports look up.
    [sign] = Enum.filter(ports, &(&1["kind"] == "sign"))
    [tw, th] = sign["text"]
    [sw, sh, _] = sign["size"]
    assert tw < sw and th < sh

    for p <- ports,
        p["kind"] in ~w(water_tank dish antenna laundry pot altar),
        do: assert(p["normal"] == [0.0, 1.0, 0.0])

    [altar] = Enum.filter(ports, &(&1["kind"] == "altar"))
    assert altar["facing"] == [0.0, 0.0, 1.0]

    # Each balcony has a rail and two pots at its edge.
    house = Lot.house(seed: 1)
    balconies = Enum.count(Enum.filter(ports, &(&1["kind"] == "rail")))
    assert Enum.count(ports, &(&1["kind"] == "pot")) == 2 * balconies

    # The GLB has no ports; the list of the parts of an order has them.
    refute Map.has_key?(Build.scene(house).extras, "ports")
    {:ok, json} = Orders.build(%{"blueprint" => "lot_house", "options" => %{"roof" => "clay"}}, "far", "parts")
    pitched = JSON.decode!(json)["ports"]
    refute Enum.any?(pitched, &(&1["kind"] == "laundry"))
    [tank] = Enum.filter(pitched, &(&1["kind"] == "water_tank"))
    assert Enum.at(tank["position"], 1) > house.extras["house"]["height"] - 1.1

    # On a room on the terrace the tank is on its roof; one floor has no AC.
    [roomy] =
      for p <- Build.parts_file("h", Lot.house(terrace_room: true, floors: 1))["ports"],
          p["kind"] == "water_tank",
          do: p

    assert_in_delta Enum.at(roomy["position"], 1), 0.2 + 3.8 + 2.7, 1.0e-6
    refute Enum.any?(Build.parts_file("h", Lot.house(floors: 1))["ports"], &(&1["kind"] == "ac"))
    refute Map.has_key?(Build.parts_file("b", World.Buildings.brick_vn()), "ports")
  end

  test "the houses of the catalog" do
    for {name, fun} <- Lot.models() do
      house = fun.()
      assert house.name == name and house.kind == :house
    end
  end

  defp glb_json(<<"glTF", 2::little-32, _::little-32, len::little-32, "JSON", json::binary-size(len), _::binary>>),
    do: JSON.decode!(json)
end
