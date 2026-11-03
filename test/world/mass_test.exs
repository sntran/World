defmodule World.MassTest do
  use ExUnit.Case, async: true

  alias World.{Build, Mass, Turned}
  alias World.Materials.Fasteners

  doctest Mass

  test "each density has its source" do
    for {role, [d, source]} <- World.Standards.table("materials", "density")["sizes"] do
      assert d > 0 and is_binary(source), role
      assert Mass.density(String.to_atom(role)) == d
    end
  end

  test "the masses of parts next to their real masses" do
    # An ISO 4017 bolt M10x40: 0.033 kg (Keller & Kalmbach); the thread
    # of the real bolt takes some steel away.
    bolt = Mass.part(Fasteners.bolt("M10", 0.04)).mass
    assert abs(bolt - 0.033) / 0.033 < 0.1

    # A 12 oz amber longneck: 0.425 lb, 193 g (Kaufman Container).
    bottle = Mass.of(Turned.bottle()).mass
    assert abs(bottle - 0.193) / 0.193 < 0.1
  end

  test "the center of mass of a turned part is on its axis, under its middle" do
    %{center: {x, y, z}, unknown: []} = Mass.of(Turned.pot())
    assert abs(x) < 1.0e-9 and abs(y) < 1.0e-9
    assert z > 0 and z < Turned.pot().extras["height"] / 2
  end

  test "a part with an open mesh or a material with no density has no mass" do
    open = %World.Mesh{points: [{0, 0, 0}, {1, 0, 0}, {0, 1, 0}], faces: [[0, 1, 2]], material: :steel}
    assert Mass.mesh(open) == nil
    assert Mass.part(%World.Part{name: "open", shapes: [open]}) == nil
    painted = World.Shape.box({0, 0, 0}, {1, 1, 1}, :paint)
    assert Mass.part(%World.Part{name: "painted", shapes: [painted]}) == nil
    assert Mass.part(%World.Part{name: "mark", shapes: []}) == nil

    # A model with no known part: no mass, no center.
    assert %{mass: +0.0, center: nil, unknown: ["painted"]} =
             Mass.of(World.Assembly.new("a", %World.Part{name: "painted", shapes: [painted]}))
  end

  test "the mass of an assembly is the sum of its parts at their places; the list of parts has the mass of each" do
    a =
      World.Assembly.new("two", Fasteners.bolt("M8", 0.04))
      |> World.Assembly.add("nut", Fasteners.nut("M8"), at: "tip", port: "face")

    m = Mass.of(a)
    parts = Build.parts(a)
    assert abs(m.mass - Enum.sum(for p <- parts, do: p["mass"] * p["count"])) < 1.0e-3
    assert length(Build.placed(a)) == 2
    assert Enum.all?(parts, &is_float(&1["mass"]))
  end
end
