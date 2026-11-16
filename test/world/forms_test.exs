defmodule World.FormsTest do
  use ExUnit.Case, async: true

  alias World.{Forms, Mesh}

  @look {:stone_wash, :concrete}

  test "each kind of form makes a closed solid, and a mirror makes a second one" do
    forms = [
      %{"rings" => [%{"oct" => [2.0, -1.0, 1.0, 0.4, 0.0]}, %{"oct" => [2.5, -1.2, 1.2, 0.5, 4.0]}]},
      %{
        "rings" => [%{"rect" => [2.0, -1.0, 1.0, 5.0]}, %{"points" => [[-2, -1, 6], [2, -1, 6], [2, 1, 6], [-2, 1, 6]]}]
      },
      %{
        "rings" => [%{"xrect" => [2.0, -1.0, 1.0, 3.0, 4.0]}, %{"xrect" => [5.0, -0.8, 0.8, 3.4, 4.2]}],
        "mirror" => true
      },
      %{"loft" => [[0, 0, 5, 0.5, 0.5, 2.4], [0, 0, 6, 0.4, 0.4, 2.4]], "smooth" => 1, "sides" => 12},
      %{"loft" => [[0.6, 0.5, 0.3, 0.4, 0.3, 2.4], [0.6, 1.5, 0.3, 0.4, 0.3, 2.4]], "axis" => "y"},
      %{"lathe" => [[0, 0], [3, 0], [2, 1], [0, 1]], "sides" => 8, "turn" => 22.5},
      %{"box" => [[-0.3, 1.0, 2.0], [0.3, 1.1, 2.6]], "detail" => true, "material" => "dark"},
      %{"prism" => [[0, -0.3], [0.3, 0.2], [-0.3, 0.2]], "at" => [0, 1.0, 3.0], "length" => 0.2, "detail" => true},
      %{"sweep" => [[0, 0, 7], [1, 0, 7.5]], "radius" => 0.05, "material" => "steel"}
    ]

    assert {:ok, ^forms} = Forms.check(forms, "forms")
    {cast, detail} = Forms.meshes(forms, @look)
    assert length(cast) == 8 and length(detail) == 2

    for m <- cast ++ detail do
      assert Mesh.volume(m.points, m.faces) > 0
    end

    assert Enum.map(detail, & &1.material) == [:dark, :stone_wash]
    assert List.last(cast).material == :steel and hd(cast).matter == :concrete
    # The mirror of the sleeve is on -x.
    [_, _, sleeve, mirror | _] = cast
    {{x0, _, _}, _} = Mesh.bounds(sleeve)
    {_, {x1, _, _}} = Mesh.bounds(mirror)
    assert x0 > 1.9 and x1 < -1.9
    # The prism stands out of the front from y = 1.0, its u along +x.
    {{_, y0, _}, {px1, y1, _}} = Mesh.bounds(List.last(detail))
    assert_in_delta y0, 1.0, 1.0e-9
    assert_in_delta y1, 1.2, 1.0e-9
    assert_in_delta px1, 0.3, 1.0e-9
  end

  test "the errors of the data of forms, each with its path" do
    assert {:error, [{"f", "must be a list of forms"}]} = Forms.check(%{}, "f")

    bad = [
      3,
      %{},
      %{"box" => [[0, 0, 0], [1, 1, 1]], "lathe" => [[0, 0], [1, 1]]},
      %{"box" => [[0, 0, 0], [1, 1, 1]], "colour" => "red", "material" => "gold", "mirror" => 1},
      %{"box" => [[0, 0], [1, 1, 1]]},
      %{
        "rings" => [
          %{"rect" => [1, 0, 1]},
          %{"oct" => [1]},
          %{"xrect" => [1]},
          %{"points" => [[0, 0]]},
          %{"circle" => 1}
        ]
      },
      %{"rings" => [%{"rect" => [1, 0, 1, 0]}]},
      %{"rings" => [%{"rect" => [1, 0, 1, 0]}, %{"oct" => [1, 0, 1, 0.1, 1]}]},
      %{"loft" => [[0, 0, 0, 1, 1], [0, 0, 1, 1, 1, 2]], "axis" => "x", "smooth" => 3},
      %{"lathe" => [[0], [1, 1]], "sides" => 2},
      %{"prism" => [[0, 0], [1, 0], [1]]},
      %{"sweep" => [[0, 0, 0], [1, 1]], "radius" => 0}
    ]

    assert {:error, errors} = Forms.check(bad, "f")

    assert errors == [
             {"f.0", "must be an object"},
             {"f.1", "must have one of: rings, loft, lathe, box, prism, sweep"},
             {"f.2", "must have one of: rings, loft, lathe, box, prism, sweep"},
             {"f.3.colour", "is not a key of a form"},
             {"f.3.material", "must be dark or steel"},
             {"f.3.mirror", "must be true or false"},
             {"f.4.box", "must be two corners [x, y, z]"},
             {"f.5.rings.0.rect", "must be [w, y0, y1, z]"},
             {"f.5.rings.1.oct", "must be [w, y0, y1, c, z]"},
             {"f.5.rings.2.xrect", "must be [x, y0, y1, z0, z1]"},
             {"f.5.rings.3.points", "must be three or more points [x, y, z]"},
             {"f.5.rings.4", "must be a ring: rect, oct, xrect or points"},
             {"f.6.rings", "must be two or more rings"},
             {"f.7.rings", "must have the same number of points in each ring"},
             {"f.8.loft.0", "must be [x, y, z, a, b, p]"},
             {"f.8.axis", "must be z or y"},
             {"f.8.smooth", "must be an integer from 0 to 2"},
             {"f.9.lathe.0", "must be [r, z]"},
             {"f.9.sides", "must be an integer from 3 to 64"},
             {"f.10.prism.2", "must be [u, v]"},
             {"f.10.at", "must be [x, y, z]"},
             {"f.10.length", "must be a length over 0"},
             {"f.11.sweep.1", "must be [x, y, z]"},
             {"f.11.radius", "must be a radius over 0"}
           ]
  end
end
