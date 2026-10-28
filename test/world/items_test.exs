defmodule World.ItemsTest do
  use ExUnit.Case, async: true

  alias World.Build

  alias World.Detail

  alias World.Scene
  alias World.Materials.Fasteners

  @limits %{near: 50_000, mid: 12_000, far: 5_000}

  # Each item of DIY: its size {width, depth, height} in meters (the size
  # of its source; the handles, the pipes and the vents add to it), the
  # tolerance, and the roles of its joints.
  @items %{
    "fridge_lg_lrfxs2503s" => {{0.832, 0.838, 1.775}, 0.01, ~w(door door drawer)},
    "washer_lg_wm4000hwa" => {{0.686, 0.768, 0.991}, 0.01, ~w(spin door knob drawer)},
    "dryer_lg" => {{0.686, 0.823, 0.991}, 0.01, ~w(spin door knob)},
    "dishwasher_24in" => {{0.6, 0.65, 0.864}, 0.01, ~w(spin door drawer drawer)},
    "range_30in" => {{0.762, 0.763, 1.194}, 0.01, ~w(door drawer knob knob knob knob knob)},
    "microwave_panasonic_nn_sn966s" => {{0.606, 0.526, 0.356}, 0.01, ~w(spin door)},
    "freezer_frigidaire_ffcl1542aw" => {{1.416, 0.781, 0.826}, 0.01, ~w(lid)},
    "water_heater_rheem_prog50" => {{0.656, 0.666, 1.774}, 0.01, ~w(knob)},
    "ac_goodman_gsx140361" => {{0.767, 0.737, 0.836}, 0.01, ~w(spin)},
    "mini_split_mitsubishi_msz_gl12na" => {{0.798, 0.272, 0.295}, 0.01, ~w(lid vane)},
    "ceiling_fan_52in" => {{1.236, 1.299, 0.305}, 0.01, ~w(spin)},
    "tv_samsung_un50cu7000" => {{1.118, 0.262, 0.719}, 0.01, []},
    "power_station_pecron_f5000lfp" => {{0.631, 0.422, 0.492}, 0.01, ~w(wheel wheel handle)},
    "power_station_pecron_e3800lfp" => {{0.451, 0.321, 0.418}, 0.01, []},
    "power_station_ecoflow_delta_pro" => {{0.344, 0.654, 0.447}, 0.01, ~w(wheel wheel handle)},
    "power_station_ecoflow_delta_pro_3" => {{0.401, 0.712, 0.44}, 0.01, ~w(wheel wheel handle)},
    "power_station_ecoflow_delta_pro_ultra" => {{0.69, 0.491, 0.459}, 0.01, []},
    "power_station_anker_solix_f3800" => {{0.429, 0.405, 0.713}, 0.01, ~w(wheel wheel handle)},
    "power_station_anker_solix_f3800_plus" => {{0.429, 0.405, 0.713}, 0.01, ~w(wheel wheel handle)},
    "battery_battle_born_bb10012" => {{0.341, 0.18, 0.253}, 0.01, []},
    "victron_multiplus_ii_12_3000" => {{0.295, 0.152, 0.566}, 0.01, []},
    "victron_smartshunt_500a" => {{0.12, 0.056, 0.046}, 0.01, []},
    "victron_lynx_distributor" => {{0.17, 0.082, 0.29}, 0.01, ~w(lid)},
    "victron_orion_xs_12_12_50" => {{0.123, 0.046, 0.143}, 0.01, []},
    "battery_switch_blue_sea_6006" => {{0.07, 0.07, 0.065}, 0.01, ~w(knob)},
    "fridge_dometic_cfx3_45" => {{0.435, 0.716, 0.476}, 0.01, ~w(lid)},
    "roof_fan_maxxair_7500k" => {{0.419, 0.572, 0.187}, 0.01, ~w(spin lid)},
    "heater_webasto_air_top_2000_stc" => {{0.35, 0.122, 0.168}, 0.01, []},
    "water_tank_20gal" => {{0.64, 0.356, 0.386}, 0.01, []},
    "solar_panel_rich_solar_mega_400" => {{1.135, 1.722, 0.03}, 0.01, []},
    "redarc_bcdc1250d" => {{0.227, 0.121, 0.037}, 0.01, []},
    "second_alternator_250a" => {{0.154, 0.201, 0.187}, 0.01, ~w(spin)},
    "van_bed_platform" => {{1.778, 1.524, 0.965}, 0.01, []},
    "van_galley" => {{1.245, 0.557, 1.229}, 0.01, ~w(knob drawer drawer drawer door)}
  }

  @through ~w(roof_fan_maxxair_7500k heater_webasto_air_top_2000_stc)

  for {name, fun} <- World.Catalog.models(), Map.has_key?(@items, name) do
    @name name
    @fun fun

    test "#{name}: the size, the levels, the joints and the parts" do
      scenes = for level <- [:near, :mid, :far], do: {level, Build.scene(Detail.with(level, @fun), level: level)}

      for {level, scene} <- scenes do
        tris = Scene.triangles(scene)
        assert tris > 0 and tris <= @limits[level], "#{@name} has #{tris} triangles at #{level}"
      end

      [{:near, near}, {:mid, mid}, {:far, far}] = scenes
      assert Scene.triangles(near) >= Scene.triangles(mid) and Scene.triangles(mid) >= Scene.triangles(far)

      {{w, d, h}, tol, roles} = @items[@name]
      [sw, sd, sh] = near.extras["size"]
      assert abs(sw - w) <= tol and abs(sd - d) <= tol and abs(sh - h) <= tol, "#{@name}: #{inspect([sw, sd, sh])}"

      # The model stands on the ground; a roof fan and a heater go through
      # the surface that they stand on.
      {{_, _, z}, _} = Scene.bounds(near)
      assert abs(z) < 0.002 or @name in @through, "#{@name} starts at z = #{z}"

      assert Enum.sort(for n <- near.nodes, r = n.extras["role"], do: r) == Enum.sort(roles)
      assert near.extras["sources"] != []
      assert Build.parts(@fun.()) != []
    end
  end

  test "the list of the parts of the bed counts the lumber and the screws" do
    parts = Map.new(Build.parts(World.Furniture.VanBuilds.bed_platform()), &{&1["name"], &1["count"]})

    assert parts == %{
             "lumber_2x3x1448" => 5,
             "lumber_2x3x1778" => 2,
             "lumber_2x3x889" => 6,
             "sheet_889x1524x13" => 2,
             "wood_screw_10x102" => 12,
             "wood_screw_8x32" => 25,
             "wood_screw_8x64" => 20
           }
  end

  test "the terminals of the electrical parts have their bolts" do
    names = fn model -> for p <- Build.parts(model), do: {p["name"], p["count"]} end
    assert {"bolt_m8x25", 2} in names.(World.Gear.Camper.battery())
    assert {"bolt_m10x20", 2} in names.(World.Gear.Camper.smartshunt())
    assert {"cap_screw_m4x12", 4} in names.(World.Gear.Camper.multiplus())
  end

  test "a wood screw" do
    screw = Fasteners.wood_screw("#8", 0.0635)
    assert screw.name == "wood_screw_8x64" and screw.kind == :wood_screw
    {{_, _, z0}, {x1, _, z1}} = World.Part.bounds(screw)
    assert_in_delta z0, -0.0635, 1.0e-9
    assert_in_delta z1, 0.0, 1.0e-9
    # The head: 0.332 in across.
    assert_in_delta 2 * x1, 0.332 * 0.0254, 0.0005
    assert_raise KeyError, fn -> Fasteners.wood_screw("#99", 0.05) end
  end

  test "a shape of a box takes its frame" do
    box = World.Shape.box({0, 0, 0}, {1, 1, 1}, :paint, frame: World.Frame.move({2, 0, 0}))
    assert {{2.0, 0.0, 0.0}, {3.0, 1.0, 1.0}} = World.Vec.bounds(box.points)
  end

  test "the root part of a small model stays at far" do
    scene = Build.scene(Detail.with(:far, &World.Gear.Camper.battery_switch/0), level: :far)
    assert Scene.triangles(scene) > 0
    # The knob and the bolts are too small for far.
    refute Enum.any?(scene.nodes, &(&1.name == "knob" and &1.primitives != []))
  end
end
