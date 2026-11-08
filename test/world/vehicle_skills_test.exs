defmodule World.VehicleSkillsTest do
  # The skills of the vehicle trades (plan 0002, D5): each gives the part
  # of its function for the numbers of its spec sheet or its shapes.
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Drawing, Scene}
  alias World.Skills.{Fastener, Glass, Knuckle, Spring, Vehicle, Wheel}
  alias World.Vehicles.{Corners, Wheels}

  defp tris(item, level \\ :near), do: Scene.triangles(Build.scene(item, level: level))
  defp made(mod, data, name \\ "x"), do: elem(mod.make(data, %{}, %{level: :near, name: name}), 0)

  test "a wheel of each build from its spec sheet: the wheels of the bicycle, the scooter, the motorcycle, the car and the van" do
    for {data, wheel} <- [
          {%{"tire" => "37-622", "build" => "spoked", "spokes" => 36}, Wheels.spoked_wheel("37-622", spokes: 36)},
          {%{"tire" => "80/90-14", "build" => "cast", "disc" => 0.19}, Wheels.cast_wheel("80/90-14", disc: true)},
          {%{"tire" => "90/90-14", "build" => "cast"}, Wheels.cast_wheel("90/90-14")},
          {%{
             "tire" => "90/90-21",
             "build" => "spoked",
             "spokes" => 36,
             "rim_depth" => 0.018,
             "hub_width" => 0.11,
             "rim" => "black",
             "disc" => 0.3
           },
           Wheels.spoked_wheel("90/90-21",
             spokes: 36,
             rim_depth: 0.018,
             hub_width: 0.11,
             rim_material: :black,
             disc: 0.3
           )},
          {%{"tire" => "215/50R17", "build" => "car", "pcd" => 0.105, "rim" => "aluminum"},
           Wheels.car_wheel("215/50R17", pcd: 0.105, rim_material: :aluminum)},
          {%{
             "tire" => "235/65R16",
             "build" => "car",
             "face" => "disc",
             "holes" => 10,
             "pcd" => 0.18,
             "lugs" => 5,
             "rim" => "steel",
             "sides" => 40
           },
           Wheels.car_wheel("235/65R16", face: :disc, holes: 10, pcd: 0.18, lugs: 5, rim_material: :steel, sides: 40)}
        ] do
      assert Wheel.check(data, "w") == []
      assert tris(made(Wheel, data)) == tris(wheel), inspect(data)
    end

    assert Wheel.estimate(%{}, :near) > Wheel.estimate(%{}, :mid) and
             Wheel.estimate(%{}, :mid) > Wheel.estimate(%{}, :far)

    assert Enum.map(Wheel.check(%{"tire" => "big", "build" => "wooden", "spokes" => 0}, "w"), &elem(&1, 0)) ==
             ["w.tire", "w.build", "w.spokes"]

    # The contents of a wheel (an inner tube) add their mass to the wheel.
    tube = %{"tire" => "90/90-21", "build" => "spoked", "contents" => [%{"name" => "inner tube", "mass" => 1.0}]}
    plain = Map.delete(tube, "contents")
    assert Wheel.check(tube, "w") == []
    assert_in_delta World.Mass.of(made(Wheel, tube)).mass, World.Mass.of(made(Wheel, plain)).mass + 1.0, 1.0e-9
    assert [{"w.contents[0].mass", _}] = Wheel.check(Map.put(tube, "contents", [%{"name" => "x", "mass" => 0}]), "w")
  end

  test "a knuckle of a corner, with its disc or with none" do
    k = made(Knuckle, %{"at" => [0.75, 3.381, 0.3234], "disc" => 0.276}, "front_right_knuckle")
    assert k == Corners.knuckle("front_right_knuckle", {0.75, 3.381, 0.3234}, 1.0, 0.276)
    assert made(Knuckle, %{"at" => [-0.75, 0.78, 0.3234]}).ports["axle"].axis == {-1.0, 0.0, 0.0}
    assert Knuckle.check(%{"at" => [1, 2]}, "k") == [{"k.at", "must be a point [x, y, z]"}]
    assert [{"k.disc", _}] = Knuckle.check(%{"at" => [1, 2, 3], "disc" => 3}, "k")
    assert Knuckle.estimate(%{}, :far) > 0
  end

  test "a corner in a drawing: the knuckle on the body steers, the wheel on the knuckle turns" do
    body = %{
      "shapes" => [%{"box" => %{"from" => [-0.9, 0, 0.3], "to" => [0.9, 4, 1.4]}}],
      "ports" => %{"corner_front_right" => %{"at" => [0.75, 3.3, 0.32]}}
    }

    d = %{
      "kind" => "vehicle",
      "parts" => %{"body" => body},
      "nodes" => [
        %{"name" => "body", "part" => "body"},
        %{
          "name" => "front_right_knuckle",
          "skill" => %{"knuckle" => %{"at" => [0.75, 3.3, 0.32], "disc" => 0.27}},
          "at" => "corner_front_right",
          "port" => "steer",
          "joint" => %{"kind" => "hinge", "role" => "steer", "limits" => [-38, 38]}
        },
        %{
          "name" => "front_right_wheel",
          "skill" => %{"wheel" => %{"tire" => "215/50R17", "build" => "car"}},
          "to" => "front_right_knuckle",
          "at" => "axle",
          "port" => "hub",
          "joint" => %{"kind" => "hinge", "role" => "wheel"}
        }
      ]
    }

    assert {:ok, _} = Drawing.check(d, "d")
    car = Detail.with(:far, fn -> Drawing.build(d) end)
    assert Build.scene(car, level: :far).extras["joints"] == ["front_right_knuckle", "front_right_wheel"]
  end

  test "a part from shape data: its shapes, its ports, its mass, its sources, its detail, its contents, and the errors" do
    data = %{
      "shapes" => [%{"tube" => %{"line" => [[0, 0, 0], [0, 1, 0]], "radius" => 0.02}, "material" => "black"}],
      "ports" => %{"pivot" => %{"at" => [0, 0.5, 0], "axis" => [1, 0, 0], "up" => [0, 0, 1]}},
      "mass" => 12,
      "sources" => ["A tube of 40 mm (an estimate)."],
      "detail" => "always",
      "inside" => true
    }

    assert Vehicle.check_part(data, "p") == []
    p = Vehicle.part(data, "arm", :swingarm)

    assert {p.kind, p.params["mass"], p.detail, p.inside, Map.keys(p.ports)} ==
             {:swingarm, 12.0, :always, true, ["pivot"]}

    assert Vehicle.estimate(data, :near) > 0 and Vehicle.estimate(%{}, :near) == 0

    # The contents add their mass to the mass of the shapes: a tank of
    # steel with the fuel in it.
    tank = %{
      "shapes" => [%{"box" => %{"from" => [0, 0, 0], "to" => [0.1, 0.1, 0.1]}, "material" => "steel"}],
      "contents" => [%{"name" => "fuel", "mass" => 3.5, "source" => "4.8 L of gasoline at 0.74 kg/L."}]
    }

    assert Vehicle.check_part(tank, "t") == []
    assert_in_delta World.Mass.part(Vehicle.part(tank, "tank", :tank)).mass, 7.82 + 3.5, 1.0e-6
    assert_in_delta World.Mass.part(Vehicle.part(Map.delete(tank, "contents"), "tank", :tank)).mass, 7.82, 1.0e-6
    assert_in_delta World.Mass.part(Vehicle.part(Map.put(tank, "mass", 2), "tank", :tank)).mass, 5.5, 1.0e-6

    bad = %{
      "shapes" => [],
      "ports" => 1,
      "mass" => -1,
      "sources" => [1],
      "detail" => "far",
      "inside" => 2,
      "contents" => [1, %{"name" => 2, "mass" => 0, "source" => nil, "y" => 1}, %{}],
      "x" => 1
    }

    assert Enum.map(Vehicle.check_part(bad, "p"), &elem(&1, 0)) ==
             ~w(p.x p.shapes p.ports p.mass p.sources p.detail p.inside p.contents[0] p.contents[1].y p.contents[1].name p.contents[1].mass p.contents[1].source p.contents[2].name p.contents[2].mass)

    assert Vehicle.check_part(%{"shapes" => [], "contents" => 1}, "p") |> Enum.map(&elem(&1, 0)) ==
             ~w(p.shapes p.contents)

    assert Vehicle.check_part(3, "p") == [{"p", "must be an object"}]
  end

  test "a fastener, a spring and the glass: their parts and the errors of their data" do
    assert made(Fastener, %{"kind" => "washer", "thread" => "M12"}).ports["face"]
    assert made(Fastener, %{"kind" => "bolt", "thread" => "M8", "length" => 0.04}).ports["tip"]
    assert [{"f.thread", _}] = Fastener.check(%{"kind" => "nut", "thread" => "M7.5"}, "f")
    assert Fastener.estimate(%{}, :far) > 0

    shock =
      made(Spring, %{"diameter" => 0.05, "wire" => 0.006, "length" => 0.25, "turns" => 7, "inside" => true}, "shock")

    assert shock.inside and shock.name == "shock" and Map.keys(shock.ports) == ["end_a", "end_b"]

    # A spring and a rim of a color are of steel and of aluminum for their mass.
    painted =
      made(Spring, %{"diameter" => 0.05, "wire" => 0.006, "length" => 0.25, "turns" => 7, "material" => "paint"})

    assert_in_delta World.Mass.part(painted).mass, World.Mass.part(shock).mass, 1.0e-9
    rim = &World.Mass.part(World.Vehicles.Wheels.rim(0.432, 0.066, material: &1)).mass
    assert_in_delta rim.(:black), rim.(:aluminum), 1.0e-9

    assert Enum.map(Spring.check(%{"diameter" => 2, "turns" => 1}, "s"), &elem(&1, 0)) ==
             ~w(s.diameter s.wire s.length s.turns)

    assert Spring.estimate(%{}, :near) > 0

    glass = %{
      "shapes" => [
        %{
          "loft" => %{"rows" => [[1.12, 1.62, 1.64, 0.15, 4], [1.32, 1.5, 1.52, 0.13, 4]], "along" => "z"},
          "material" => "glass"
        }
      ]
    }

    assert Glass.check(glass, "g") == [] and made(Glass, glass).kind == :glass
    assert Glass.estimate(glass, :far) > 0
  end
end
