defmodule World.VehicleSkillsTest do
  # The skills of the vehicle trades (plan 0002, D5): each gives the part
  # of its function for the numbers of its spec sheet or its shapes.
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Drawing, Scene}
  alias World.Skills.{Knuckle, Vehicle, Wheel}
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

  test "a part from shape data: its shapes, its ports, its mass, its sources, its detail, and the errors" do
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

    bad = %{"shapes" => [], "ports" => 1, "mass" => -1, "sources" => [1], "detail" => "far", "inside" => 2, "x" => 1}

    assert Enum.map(Vehicle.check_part(bad, "p"), &elem(&1, 0)) ==
             ~w(p.x p.shapes p.ports p.mass p.sources p.detail p.inside)

    assert Vehicle.check_part(3, "p") == [{"p", "must be an object"}]
  end
end
