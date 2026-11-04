defmodule World.TiresTest do
  use ExUnit.Case, async: true

  alias World.Vehicles.Wheels

  doctest World.Vehicles.Wheels, only: [service: 1]
  doctest World.Openings, only: [standard: 2]

  test "the size of a tire: the rim of ISO 4000-1, the outer diameter of its data sheet" do
    # A tire of the data sheet: the 711 mm of Michelin, its mass.
    van = Wheels.tire_size("235/65R16")
    assert van.rim == 0.406 and van.diameter == 0.711
    assert Wheels.tire("235/65R16", profile: :flat).params["mass"] == 15.9

    # A tire with no data sheet: the rim and two section heights.
    other = Wheels.tire_size("205/55R16")
    assert_in_delta other.diameter, 0.406 + 2 * 0.205 * 0.55, 1.0e-9
    refute Map.has_key?(Wheels.tire("205/55R16").params, "mass")

    # A rim code that is not in the table: its inches.
    assert_in_delta Wheels.tire_size("215/85R16.5").rim, 16.5 * 0.0254, 1.0e-9

    # A load index and a speed symbol of the tables.
    assert Wheels.service("91H") == %{load: 615, speed: 210}
    assert_raise ArgumentError, fn -> Wheels.service("200Z") end
  end

  test "the doors and the windows of their standards" do
    {w, h} = World.Openings.standard("door_us", "3680")
    assert_in_delta w, 36 * 0.0254, 1.0e-9
    assert_in_delta h, 80 * 0.0254, 1.0e-9
    assert World.Openings.standard("door_vn", "exit_least") == {0.8, 2.0}
    assert_raise ArgumentError, fn -> World.Openings.standard("garage", "20x20") end
  end
end
