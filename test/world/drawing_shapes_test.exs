defmodule World.DrawingShapesTest do
  # The shapes of a vehicle in a drawing (plan 0002, D5): each gives the
  # mesh of its function of World.Shape or World.Vehicles.Body.
  use ExUnit.Case, async: true

  alias World.{Drawing, Shape}
  alias World.Vehicles.Body

  @rows [[0.1, 0.8, 0.85, 0.08, 3], [0.5, 0.78, 0.875, 0.15, 4], [0.88, 0.72, 0.79, 0.08, 3]]

  defp same(a, b), do: assert({a.points, a.faces, a.material, a.smooth} == {b.points, b.faces, b.material, b.smooth})
  defp t(rows), do: Enum.map(rows, &List.to_tuple/1)

  test "a loft along y or z, a body with arches, an arc, rings, and the options of a shape" do
    same(
      Drawing.mesh(%{"loft" => %{"rows" => @rows}, "material" => "seat", "smooth" => 2}),
      Shape.loft(Shape.rows_y(t(@rows), 0.0), :seat, smooth: 2)
    )

    same(
      Drawing.mesh(%{
        "loft" => %{"rows" => @rows, "along" => "z", "x" => 0.6},
        "material" => "light_front",
        "sides" => 12
      }),
      Shape.loft(Shape.rows_z(t(@rows), 0.6), :light_front, sides: 12)
    )

    keys = [[0.0, 0.42, 0.92, 0.78, 3.0], [1.5, 0.24, 1.04, 0.88, 6.0], [4.1, 0.42, 0.7, 0.7, 3.0]]
    arches = [[0.78, 0.32, 0.375], [3.38, 0.32, 0.375]]

    same(
      Drawing.mesh(%{
        "body" => %{"rows" => keys, "arches" => arches, "step" => 0.4, "x" => 0.5},
        "material" => "paint",
        "sides" => 16
      }),
      Body.loft(t(keys), t(arches), :paint, sides: 16, step: 0.4, x0: 0.5)
    )

    arc = %{
      "center" => [1.5, 0.25],
      "radius" => 0.37,
      "from" => -15,
      "to" => -105,
      "steps" => 6,
      "half_width" => 0.03,
      "half_height" => 0.004
    }

    same(
      Drawing.mesh(%{"arc" => arc, "material" => "black", "smooth" => 1, "sides" => 8}),
      Shape.loft(Shape.arc({1.5, 0.25}, 0.37, -15, -105, 6, 0.03, 0.004), :black, smooth: 1, sides: 8)
    )

    rings = [[[0, 0, 0], [1, 0, 0], [0, 1, 0]], [[0, 0, 1], [1, 0, 1], [0, 1, 1]]]

    same(
      Drawing.mesh(%{"rings" => %{"rings" => rings}, "material" => "black"}),
      Shape.rings(Enum.map(rings, &t/1), :black)
    )

    profile = [[0.074, -0.002], [0.091, -0.002], [0.091, 0.002], [0.074, 0.002]]

    same(
      Drawing.mesh(%{"lathe" => %{"profile" => profile}, "ring" => true, "sides" => 44, "material" => "steel"}),
      Shape.lathe(t(profile), :steel, kind: :ring, sides: 44)
    )

    same(
      Drawing.mesh(%{
        "box" => %{"from" => [0, 0, 0], "to" => [1, 1, 1]},
        "round" => 0.2,
        "smooth" => 2,
        "material" => "trim"
      }),
      Shape.box({0, 0, 0}, {1, 1, 1}, :trim, round: 0.2, smooth: 2)
    )
  end

  test "the errors of the shapes of a vehicle, each with its path" do
    bad = [
      %{"loft" => %{"rows" => [[1, 2, 3]], "along" => "w"}, "sides" => 2},
      %{"body" => %{"rows" => [[0, 0, 1, 1, 0], [1, 0, 1, 1, 2]], "arches" => [[1, 2]], "step" => -1, "x" => 0.2}},
      %{
        "arc" => %{
          "center" => [1, 2],
          "radius" => 1,
          "from" => 0,
          "to" => 500,
          "steps" => 0,
          "half_width" => 1,
          "half_height" => 1,
          "power" => 99
        }
      },
      %{"rings" => %{"rings" => [[[0, 0, 0]]]}, "smooth" => 9, "round" => 0.9, "ring" => 1}
    ]

    assert Enum.map(Drawing.check_shapes(bad, "s"), &elem(&1, 0)) == [
             "s.0.sides",
             "s.0.loft.rows",
             "s.0.loft.along",
             "s.1.body.rows.0",
             "s.1.body.arches.0",
             "s.1.body.step",
             "s.2.arc.to",
             "s.2.arc.steps",
             "s.2.arc.power",
             "s.3.smooth",
             "s.3.round",
             "s.3.ring",
             "s.3.rings.rings"
           ]

    assert Drawing.check_shapes([], "s") == [{"s", "must be a list of 1 to 512 items"}]
  end
end
