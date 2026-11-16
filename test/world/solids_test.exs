defmodule World.SolidsTest do
  # The simple solids of a model, for a project that draws boxes or SVG (plan 0019, 4.2).
  use ExUnit.Case, async: true

  alias World.{Frame, Orders, Scene, Solids}

  @drawing %{
    "name" => "thing",
    "nodes" => [
      %{
        "name" => "thing_body",
        "skill" => %{
          "sculpt" => %{
            "groups" => %{"knob" => [%{"shape" => "ball", "size" => [0.02], "color" => "#000a10"}]},
            "edits" => [
              %{
                "shape" => "box",
                "size" => [0.3, 0.2, 0.5],
                "at" => [0, 0, 0.5],
                "color" => "#f1dc86",
                "material" => "part_01"
              },
              %{
                "shape" => "box",
                "size" => [0.2, 0.05, 0.3],
                "at" => [0, 0.2, 0.5],
                "axis" => [0, 1, 0],
                "up" => [0, 0, 1],
                "mode" => "subtract",
                "blend" => 0.01
              },
              %{
                "shape" => "cylinder",
                "size" => [0.01, 0.1],
                "at" => [0.25, 0.22, 0.5],
                "mirror" => "x",
                "color" => "#c0c0c0"
              },
              %{"shape" => "group", "group" => "knob", "at" => [0, 0.21, 0.9]},
              %{
                "shape" => "box",
                "size" => [0.1, 0.05, 0.1],
                "at" => [0, 0.2, 0.8],
                "mode" => "paint",
                "raise" => -0.005,
                "blend" => 0.005,
                "color" => "#55707c"
              },
              %{"shape" => "tube", "size" => %{"points" => [[0, 0, 1], [0, 0, 1.2]], "radii" => [0.01, 0.02]}},
              %{
                "shape" => "extrude",
                "size" => %{"outline" => [[0, 0], [0.1, 0], [0, 0.1]], "depth" => 0.4, "round" => 0.01},
                "at" => [0, 0, 1.3]
              },
              %{"shape" => "revolve", "size" => %{"profile" => [[0, 0], [0.1, 0], [0, 0.2]]}, "at" => [0, 0, 1.5]}
            ],
            "details" => [
              %{
                "edits" => [%{"shape" => "capsule", "size" => [0.2, 0.005], "at" => [0, 0.3, 0.5]}],
                "levels" => ["near"]
              }
            ]
          }
        }
      },
      %{
        "name" => "thing_foot",
        "skill" => %{"sculpt" => %{"edits" => [%{"shape" => "box", "size" => [0.3, 0.2, 0.02], "at" => [0, 0, -0.02]}]}}
      }
    ]
  }

  test "the solids of a drawing from edits: each edit with its copies, in the axes of the model, with no build" do
    assert Solids.edits?(@drawing)
    refute Solids.edits?(%{"nodes" => [%{"name" => "a", "part" => "wheel"} | @drawing["nodes"]]})
    refute Solids.edits?(%{"nodes" => []}) or Solids.edits?(nil)

    s = Solids.of(@drawing)
    assert %{"name" => "thing", "units" => "m", "up" => "z", "box" => [[x0, _, z0], [x1, _, z1]]} = s
    assert x0 < -0.29 and x1 > 0.29 and z0 < -0.03 and z1 > 1.6
    assert [%{"name" => "thing_body", "solids" => body}, %{"name" => "thing_foot", "solids" => [foot]}] = s["parts"]
    # Eight edits: the mirror gives two cylinders, and the group gives its ball.
    assert Enum.map(body, & &1["shape"]) == ~w(box box cylinder cylinder ball box tube extrude revolve)

    assert hd(body) == %{
             "shape" => "box",
             "size" => [0.3, 0.2, 0.5],
             "at" => [+0.0, +0.0, 0.5],
             "x" => [1.0, +0.0, +0.0],
             "y" => [+0.0, 1.0, +0.0],
             "z" => [+0.0, +0.0, 1.0],
             "mode" => "add",
             "role" => "part_01",
             "color" => "#f1dc86"
           }

    # An edit with an axis has its three axes; a blend and a raise are there when they are not 0.
    assert %{"mode" => "subtract", "blend" => 0.01, "z" => [+0.0, 1.0, +0.0], "color" => nil, "role" => nil} =
             Enum.at(body, 1)

    assert [%{"at" => [0.25, 0.22, 0.5]}, %{"at" => [-0.25, 0.22, 0.5]}] = Enum.slice(body, 2, 2)
    assert %{"shape" => "ball", "at" => [+0.0, 0.21, 0.9], "color" => "#000a10"} = Enum.at(body, 4)
    assert %{"mode" => "paint", "raise" => -0.005, "color" => "#55707c"} = Enum.at(body, 5)
    # The sizes of a tube, an extrude and a revolve are as in the data of an edit.
    assert %{"size" => %{"points" => [[+0.0, +0.0, 1.0], [+0.0, +0.0, 1.2]], "radii" => [0.01, 0.02]}} =
             Enum.at(body, 6)

    assert %{"size" => %{"outline" => [[+0.0, +0.0], [0.1, +0.0], [+0.0, 0.1]], "depth" => 0.4, "round" => 0.01}} =
             Enum.at(body, 7)

    assert %{"size" => %{"profile" => [[+0.0, +0.0], [0.1, +0.0], [+0.0, 0.2]]}} = Enum.at(body, 8)
    refute Map.has_key?(foot, "blend") or Map.has_key?(foot, "detail")

    # The details come with the option, each with its mark.
    assert [%{"solids" => with_details} | _] = Solids.of(@drawing, details: true)["parts"]
    assert length(with_details) == 10
    assert %{"shape" => "capsule", "detail" => true} = List.last(with_details)
    # A drawing with no shape that adds has no box.
    assert Solids.of(%{"name" => "none", "nodes" => [%{"name" => "a", "skill" => %{"sculpt" => %{"edits" => []}}}]})[
             "box"
           ] == nil

    assert JSON.decode!(JSON.encode!(s)) == s
  end

  test "the boxes of a scene: one box for each node and each material, at each instance, and no collision box" do
    square = fn material, z ->
      %Scene.Primitive{
        material: material,
        positions: [{+0.0, +0.0, z}, {1.0, +0.0, z}, {1.0, 2.0, z + 0.5}],
        normals: [],
        indices: [0, 1, 2]
      }
    end

    scene = %Scene{
      name: "pair",
      nodes: [
        %Scene.Node{name: "base", primitives: [square.(:steel, 0.0), square.(:no_such_role, 1.0)]},
        %Scene.Node{
          name: "arm",
          parent: 0,
          frame: Frame.move({10.0, +0.0, +0.0}),
          primitives: [square.(:glass, 0.0)],
          instances: [%Frame{}, Frame.move({+0.0, 5.0, +0.0})]
        },
        %Scene.Node{name: "hit", parent: 0, primitives: [square.(:steel, 0.0)], extras: %{"collision" => "box"}},
        %Scene.Node{name: "empty", parent: 0}
      ]
    }

    s = Solids.boxes(scene)
    assert %{"name" => "pair", "units" => "m", "up" => "z", "box" => [[+0.0, +0.0, +0.0], [11.0, 7.0, 1.5]]} = s

    assert [%{"name" => "base", "solids" => [steel, other]}, %{"name" => "arm", "solids" => [first, second]}] =
             s["parts"]

    assert %{
             "shape" => "box",
             "size" => [0.5, 1.0, 0.25],
             "at" => [0.5, 1.0, 0.25],
             "mode" => "add",
             "role" => "steel",
             "color" => "#" <> _
           } = steel

    # A role that the palette does not have has no color. The node of the arm is 10 m along x, two times.
    assert %{"role" => "no_such_role", "color" => nil, "at" => [0.5, 1.0, 1.25]} = other
    assert first["at"] == [10.5, 1.0, 0.25] and second["at"] == [10.5, 6.0, 0.25]
  end

  test "the file solids of an order: the shapes of a drawing from edits, and the boxes of a model of a rule" do
    assert "solids" in Orders.files()
    {:ok, json} = Orders.build(%{"blueprint" => "drawing", "options" => %{"drawing" => @drawing}}, "far", "solids")
    assert JSON.decode!(json) == Solids.of(@drawing)

    {:ok, json} = Orders.build(%{"blueprint" => "l_track", "options" => %{"length" => 0.2}}, "far", "solids")

    assert %{
             "units" => "m",
             "box" => [[_, _, _], [_, _, _]],
             "parts" => [%{"solids" => [%{"shape" => "box", "role" => role} | _]} | _]
           } = JSON.decode!(json)

    assert is_binary(role)
  end
end
