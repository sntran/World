defmodule World.WebbingTest do
  use ExUnit.Case, async: true

  alias World.Materials.Webbing
  alias World.{Mass, Part}

  test "a strap along a path: its ports at its ends, its length, and its mass of nylon" do
    path = [{0.0, 0.0, 0.0}, {0.0, 0.0, -0.1}, {0.05, 0.0, -0.2}]
    s = Webbing.strap("strap", path, 0.025, across: {0, 1, 0})
    assert s.kind == :strap
    assert Part.port!(s, "a").at == {0.0, 0.0, 0.0}
    assert Part.port!(s, "b").at == {0.05, 0.0, -0.2}

    length = 0.1 + :math.sqrt(0.05 ** 2 + 0.1 ** 2)
    assert_in_delta s.params["length"], length, 1.0e-4
    assert s.params["width"] == 0.025 and s.params["thickness"] == 0.001

    # A band of 25 by 1 mm of nylon (1140 kg/m3), within 8%: its section
    # is a box with round corners of 12 points, a little less than a box.
    box = 0.025 * 0.001 * length * 1140
    assert_in_delta Mass.part(s).mass, box, 0.08 * box
    assert Mass.part(s).mass < box

    # With no options: 1 mm thick.
    assert Webbing.strap("strap", [{0, 0, 0}, {0, 0, 1}], 0.02).params["thickness"] == 0.001

    # With no direction across, the strap takes one of its own.
    assert Webbing.strap("strap", [{0, 0, 0}, {0, 0, 1}], 0.02, thickness: 0.002).params["thickness"] == 0.002
  end

  test "a buckle for a width of webbing: its two ports, along x" do
    b = Webbing.buckle("buckle", 0.02)
    assert b.kind == :buckle and b.params["width"] == 0.02
    assert Part.port!(b, "female").at == {0.0, 0.0, 0.0}
    {x, y, z} = Part.port!(b, "male").at
    assert_in_delta x, 0.052, 1.0e-9
    assert y == 0 and z == 0
    assert Mass.part(b).mass > 0
  end
end
