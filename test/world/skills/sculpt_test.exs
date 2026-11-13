defmodule World.Skills.SculptTest do
  # The skill sculpt: a part from a list of edits in a node of a drawing
  # (plan 0008, D9, R6).
  use ExUnit.Case, async: true

  alias World.{Detail, Drawing, Mesh, Orders, Plan, Sculpt, Skills}
  alias World.Skills.Sculpt, as: Skill

  # A stone with a hole, a band of moss, and a handle of a tube.
  defp data do
    %{
      "edits" => [
        %{"shape" => "ellipsoid", "size" => [0.4, 0.3, 0.25], "material" => "stone_wash"},
        %{
          "shape" => "cylinder",
          "size" => [0.08, 0.4],
          "axis" => [1, 0, 0],
          "up" => [0, 0, 1],
          "mode" => "subtract",
          "blend" => 0.02
        },
        %{"shape" => "ring", "size" => [0.3, 0.04], "mode" => "paint", "blend" => 0.01, "material" => "gray"},
        %{
          "shape" => "tube",
          "size" => %{"points" => [[-0.2, 0, 0.2], [0, 0, 0.4], [0.2, 0, 0.2]], "radii" => [0.03, 0.03, 0.03]},
          "blend" => 0.03
        },
        %{"shape" => "box", "size" => [0.1, 0.1, 0.02], "at" => [0, 0, -0.25]},
        %{"shape" => "round_box", "size" => [0.1, 0.1, 0.05, 0.02], "at" => [0.35, 0, 0], "blend" => 0.02},
        %{"shape" => "capsule", "size" => [0.1, 0.03], "at" => [-0.35, 0, 0]},
        %{"shape" => "cone", "size" => [0.05, 0, 0.08], "at" => [0, 0.3, 0], "axis" => [0, 1, 0]},
        %{"shape" => "superellipsoid", "size" => [0.05, 0.05, 0.05, 4], "at" => [0, -0.3, 0]},
        %{"shape" => "ball", "size" => [0.05], "at" => [0, 0, 0.3]}
      ],
      "ports" => %{"base" => %{"at" => [0, 0, -0.27], "axis" => [0, 0, -1]}},
      "sources" => ["A test."],
      "budget" => %{"near" => 20_000, "mid" => 2_000}
    }
  end

  defp drawing(data),
    do: %{"name" => "stone", "kind" => "item", "nodes" => [%{"name" => "stone", "skill" => %{"sculpt" => data}}]}

  defp order(d), do: %{"blueprint" => "drawing", "options" => %{"drawing" => d}}

  test "a sculptor makes the part of the edits at each level, in its budget, with its materials and its ports" do
    assert "sculpt" in Skills.names() and Skill.trade() == :sculptor
    assert [%{trade: :sculptor}] = Plan.of_drawing(drawing(data())).tasks
    mid = Detail.with(:mid, fn -> Drawing.build(drawing(data())) end)
    {"stone", part, _} = hd(mid.nodes)
    faces = part.shapes |> Enum.map(&length(&1.faces)) |> Enum.sum()
    assert faces <= 2_000 and faces > 500
    assert Enum.map(part.shapes, & &1.material) |> Enum.sort() == [:gray, :paint, :stone_wash]
    assert Map.has_key?(part.ports, "base") and part.sources == ["A test."]
    # With a budget and no cells, the cells that fit the budget.
    edits = Skill.edits(data()["edits"])
    assert part.shapes == Sculpt.model(edits, step: Sculpt.fit(edits, 2_000), budget: 2_000)

    # Smaller cells: more faces.
    fine = Detail.with(:far, fn -> Drawing.build(drawing(Map.put(data(), "cells", %{"far" => 0.1}))) end)
    {"stone", fine_part, _} = hd(fine.nodes)
    assert fine_part.shapes == Sculpt.model(Skill.edits(data()["edits"]), step: 0.1)
    assert Skill.estimate(Map.put(data(), "cells", %{"far" => 0.1}), :far) > Skill.estimate(data(), :far)

    # Far has no budget: all the faces of its cells.
    far = Detail.with(:far, fn -> Drawing.build(drawing(data())) end)
    {"stone", far_part, _} = hd(far.nodes)
    assert far_part.shapes == Sculpt.model(Skill.edits(data()["edits"]), level: :far)
    assert Enum.all?(far_part.shapes, &(Mesh.bounds(&1) != nil))
  end

  test "an edit with no turn has the axes of the sculpture: the long side of an ellipsoid stays on its axis" do
    [long_y, along_y] =
      Skill.edits([
        %{"shape" => "ellipsoid", "size" => [0.1, 0.5, 0.2]},
        %{"shape" => "cylinder", "size" => [0.1, 0.5], "axis" => [0, 1, 0]}
      ])

    assert {{lx, ly, lz}, {hx, hy, hz}} = World.SDF.bounds([long_y])
    assert_in_delta hx - lx, 0.2, 1.0e-9
    assert_in_delta hy - ly, 1.0, 1.0e-9
    assert_in_delta hz - lz, 0.4, 1.0e-9
    {{_, ly, lz}, {_, hy, hz}} = World.SDF.bounds([along_y])
    assert_in_delta hy - ly, 1.0, 1.0e-9
    assert_in_delta hz - lz, 0.2, 1.0e-9
  end

  test "an edit with a color: the part has the color of each point" do
    data = %{"edits" => [%{"shape" => "ball", "size" => [0.2], "color" => "#a88840"}], "cells" => %{"far" => 0.05}}
    far = Detail.with(:far, fn -> Drawing.build(drawing(data)) end)
    {"stone", part, _} = hd(far.nodes)
    assert [%{colors: [{168, 136, 64} | _], normals: [_ | _]}] = part.shapes
  end

  test "the estimate of the triangles: in the budget, and none for data with errors" do
    near = Skill.estimate(data(), :near)
    assert near > 2_000 and near <= 20_000
    assert Skill.estimate(put_in(data(), ["budget", "near"], 1_000), :near) == 1_000
    assert Skill.estimate(data(), :far) in 10..300
    assert Skill.estimate(%{"edits" => []}, :near) == 0
    assert Skill.estimate(%{"edits" => [%{"shape" => "ball", "size" => [1], "mode" => "subtract"}]}, :near) == 0
  end

  test "the errors of the data of a sculpture, each with its path" do
    p = "options.drawing.nodes.0.skill.sculpt"
    edit = fn e -> drawing(%{"edits" => [e]}) end

    paths = fn d ->
      case Orders.check(order(d)) do
        {:error, errors} -> Enum.map(errors, & &1["path"])
        {:ok, _} -> []
      end
    end

    ball = %{"shape" => "ball", "size" => [0.1]}

    cases = [
      {drawing(%{}), ["#{p}.edits"]},
      {drawing(%{"edits" => [], "more" => 1}), ["#{p}.more", "#{p}.edits"]},
      {drawing(%{"edits" => List.duplicate(ball, 10_001)}), ["#{p}.edits"]},
      {drawing(%{"edits" => [ball], "budget" => %{"near" => 5, "high" => 100}}),
       ["#{p}.budget.high", "#{p}.budget.near"]},
      {drawing(%{"edits" => [ball], "budget" => 5}), ["#{p}.budget"]},
      {drawing(%{"edits" => [ball], "cells" => %{"near" => 0, "low" => 0.1}}), ["#{p}.cells.low", "#{p}.cells.near"]},
      {drawing(%{"edits" => [ball], "cells" => [0.1]}), ["#{p}.cells"]},
      {drawing(%{"edits" => [ball], "sources" => "no"}), ["#{p}.sources"]},
      {drawing(%{"edits" => [ball], "ports" => %{"a" => %{}}}), ["#{p}.ports.a.at"]},
      {edit.(5), ["#{p}.edits.0"]},
      {edit.(%{"size" => [1]}), ["#{p}.edits.0.shape"]},
      {edit.(%{"shape" => "egg", "size" => [1]}), ["#{p}.edits.0.shape"]},
      {edit.(%{"shape" => "ball", "size" => [1, 2]}), ["#{p}.edits.0.size"]},
      {edit.(%{"shape" => "ball", "size" => [0]}), ["#{p}.edits.0.size"]},
      {edit.(%{"shape" => "round_box", "size" => [0.1, 0.1, 0.1, 0.2]}), ["#{p}.edits.0.size"]},
      {edit.(%{"shape" => "superellipsoid", "size" => [0.1, 0.1, 0.1, 1]}), ["#{p}.edits.0.size"]},
      {edit.(%{"shape" => "cone", "size" => [0, 0, 0.1]}), ["#{p}.edits.0.size"]},
      {edit.(%{"shape" => "tube", "size" => %{"points" => [[0, 0, 0]], "radii" => [0.1]}}), ["#{p}.edits.0.size"]},
      {edit.(%{"shape" => "tube", "size" => %{"points" => [[0, 0, 0], [0, 0]], "radii" => [0.1, 0]}}),
       ["#{p}.edits.0.size.points.1", "#{p}.edits.0.size.radii.1"]},
      {edit.(Map.merge(ball, %{"at" => [0, 0], "axis" => [0, 0, 0], "up" => "z"})),
       ["#{p}.edits.0.at", "#{p}.edits.0.axis", "#{p}.edits.0.up"]},
      {edit.(Map.merge(ball, %{"mode" => "cut", "blend" => -1, "material" => "gold!", "color" => "red"})),
       ["#{p}.edits.0.mode", "#{p}.edits.0.blend", "#{p}.edits.0.material", "#{p}.edits.0.color"]}
    ]

    for {d, expected} <- cases, do: assert(paths.(d) == expected, inspect({expected, paths.(d)}))
    assert paths.(drawing(data())) == []
    assert Skill.check(5, "x") == [{"x", "must be an object"}]
  end

  test "the examples of docs/format.md pass the check, and a sculptor makes them" do
    [_, section] = Regex.run(~r/## A sculpture(.*?)\n## /s, File.read!("docs/format.md"))
    [data, node, baked, worm] = for [_, json] <- Regex.scan(~r/```json\n(.*?)```/s, section), do: JSON.decode!(json)

    # The first one is the data of a sculpture with a group and copies; the second one a node; then a node with maps, and a node with bones.
    for n <- [%{"name" => "stone", "skill" => %{"sculpt" => Map.put(data, "cells", %{"mid" => 0.004})}}, node] do
      d = %{"name" => "stone", "kind" => "item", "nodes" => [n]}
      assert {:ok, _} = Orders.check(order(d))
      assert [{"stone", %World.Part{shapes: [_ | _]}, _}] = Detail.with(:mid, fn -> Drawing.build(d) end).nodes
    end

    assert length(Skill.edits(data["edits"], data["groups"])) == 1 + 4 + 6

    d = %{"name" => "stone", "kind" => "item", "nodes" => [baked]}
    assert {:ok, _} = Orders.check(order(d))
    far = Detail.with(:far, fn -> Drawing.build(d) end)
    assert [{"stone", %World.Part{shapes: [%{uvs: [[_, _, _] | _], colors: nil} | _]}, _}] = far.nodes
    # The maps of the node are on its material in the model.
    assert %{"image" => {"image/png", _}, "normal_image" => {"image/png", _}, "atlas" => true} =
             far.materials[:stone_wash]

    d = %{"name" => "worm", "kind" => "item", "nodes" => [worm]}
    assert {:ok, _} = Orders.check(order(d))

    assert [{"worm", %World.Figure{animations: [%{name: "look"}]}, _}] =
             Detail.with(:mid, fn -> Drawing.build(d) end).nodes
  end

  # Points round the origin, for the fields of two lists of edits.
  defp samples do
    :rand.seed(:exsss, {9, 9, 9})
    for _ <- 1..300, do: {:rand.uniform() * 2 - 1, :rand.uniform() * 2 - 1, :rand.uniform() * 2 - 1}
  end

  defp same_field?(a, b), do: Enum.all?(samples(), &(abs(World.SDF.value(a, &1) - World.SDF.value(b, &1)) < 1.0e-9))

  test "a mirror gives the copies across the planes of the sculpture: the same field as the copies by hand (R4)" do
    ball = %{"shape" => "ball", "size" => [0.1], "at" => [0.3, 0.1, 0.2]}

    assert same_field?(
             Skill.edits([Map.put(ball, "mirror", "x")]),
             Skill.edits([ball, %{ball | "at" => [-0.3, 0.1, 0.2]}])
           )

    four = for x <- [0.3, -0.3], z <- [0.2, -0.2], do: %{ball | "at" => [x, 0.1, z]}
    assert same_field?(Skill.edits([Map.put(ball, "mirror", ["x", "z"])]), Skill.edits(four))

    # A shape with a turn, and a tube: the field of the copy at a point is the field of the shape at the mirror of the point.
    cone = %{
      "shape" => "cone",
      "size" => [0.1, 0.02, 0.2],
      "at" => [0.3, 0.1, 0.0],
      "axis" => [1, 2, 3],
      "up" => [0, 1, -1]
    }

    tube = %{
      "shape" => "tube",
      "size" => %{"points" => [[0.1, 0, 0], [0.3, 0.2, 0.1], [0.2, 0.4, 0.3]], "radii" => [0.05, 0.03, 0.02]},
      "at" => [0.1, 0, 0],
      "axis" => [1, 0, 1]
    }

    for e <- [cone, tube], plane <- ~w(x y z) do
      [one, copy] = Skill.edits([Map.put(e, "mirror", plane)])
      flip = fn {x, y, z} -> %{"x" => {-x, y, z}, "y" => {x, -y, z}, "z" => {x, y, -z}}[plane] end
      for p <- samples(), do: assert_in_delta(World.SDF.distance(copy, flip.(p)), World.SDF.distance(one, p), 1.0e-9)
    end
  end

  test "a repeat gives a ring or a row of copies: the same field as the copies by hand (R4)" do
    ball = %{"shape" => "ball", "size" => [0.1], "at" => [0.5, 0, 0.1]}
    ring = for {x, y} <- [{0.5, 0}, {0, 0.5}, {-0.5, 0}, {0, -0.5}], do: %{ball | "at" => [x, y, 0.1]}
    assert same_field?(Skill.edits([Map.put(ball, "repeat", %{"count" => 4})]), Skill.edits(ring))

    row = for k <- 0..2, do: %{ball | "at" => [0.5, 0, 0.1 + 0.2 * k]}
    assert same_field?(Skill.edits([Map.put(ball, "repeat", %{"count" => 3, "move" => [0, 0, 0.2]})]), Skill.edits(row))

    # A turn and a move: a stair round an axis through a center. Then a mirror of each copy.
    box = %{"shape" => "box", "size" => [0.2, 0.05, 0.02], "at" => [0.3, 0, 0]}

    stair =
      Skill.edits([
        Map.put(box, "repeat", %{
          "count" => 3,
          "axis" => [0, 0, 1],
          "angle" => 90,
          "move" => [0, 0, 0.1],
          "center" => [0.1, 0, 0]
        })
      ])

    hand = [
      box,
      %{box | "at" => [0.1, 0.2, 0.1]} |> Map.put("axis", [0, 0, 1]) |> Map.put("up", [-1, 0, 0]),
      %{box | "at" => [-0.1, 0, 0.2]}
    ]

    assert same_field?(stair, Skill.edits(hand))
    both = Skill.edits([Map.merge(ball, %{"repeat" => %{"count" => 4}, "mirror" => "z"})])

    assert length(both) == 8 and
             same_field?(
               both,
               Skill.edits(ring ++ Enum.map(ring, fn e -> %{e | "at" => List.replace_at(e["at"], 2, -0.1)} end))
             )
  end

  test "a group is used at a place and a scale, with copies: the same field as its edits by hand; the people make it (R4)" do
    groups = %{
      "eye" => [
        %{"shape" => "ball", "size" => [0.1], "blend" => 0.02},
        %{
          "shape" => "capsule",
          "size" => [0.1, 0.02],
          "at" => [0, 0.1, 0],
          "axis" => [0, 1, 0],
          "blend" => 0.02,
          "mirror" => "x"
        }
      ]
    }

    use = %{"shape" => "group", "group" => "eye", "at" => [0.3, 0, 0.2], "scale" => 2, "mirror" => "x"}

    hand =
      for x <- [0.3, -0.3] do
        [%{"shape" => "ball", "size" => [0.2], "at" => [x, 0, 0.2], "blend" => 0.04}] ++
          List.duplicate(
            %{"shape" => "capsule", "size" => [0.2, 0.04], "at" => [x, 0.2, 0.2], "axis" => [0, 1, 0], "blend" => 0.04},
            2
          )
      end

    assert same_field?(Skill.edits([use], groups), Skill.edits(List.flatten(hand)))
    # A superellipsoid keeps its power at a scale; a tube has its points and its radii at the scale.
    more = %{
      "g" => [
        %{"shape" => "superellipsoid", "size" => [0.1, 0.1, 0.1, 4]},
        %{"shape" => "tube", "size" => %{"points" => [[0, 0, 0], [0.1, 0, 0]], "radii" => [0.02, 0.01]}}
      ]
    }

    [s, t] = Skill.edits([%{"shape" => "group", "group" => "g", "scale" => 3}], more)
    {x, _, _, power} = s.size
    {[_, {far, _, _}], [r0, r1]} = t.size
    assert power == 4.0
    for {have, want} <- [{x, 0.3}, {far, 0.3}, {r0, 0.06}, {r1, 0.03}], do: assert_in_delta(have, want, 1.0e-12)

    data = %{"groups" => groups, "edits" => [%{"shape" => "ball", "size" => [0.25]}, use], "cells" => %{"far" => 0.04}}
    assert paths(drawing(data)) == []
    far = Detail.with(:far, fn -> Drawing.build(drawing(data)) end)
    assert [{"stone", %World.Part{shapes: [_ | _]}, _}] = far.nodes
    assert Skill.estimate(data, :far) > 0
  end

  defp paths(d) do
    case Orders.check(order(d)) do
      {:error, errors} -> Enum.map(errors, & &1["path"])
      {:ok, _} -> []
    end
  end

  test "a paint with a raise: the errors with their paths, and the raise of a group at its scale" do
    ball = %{"shape" => "ball", "size" => [0.3]}

    paint = %{
      "shape" => "ball",
      "size" => [0.1],
      "at" => [0, 0, 0.3],
      "mode" => "paint",
      "blend" => 0.02,
      "raise" => 0.01
    }

    assert paths(drawing(%{"edits" => [ball, paint]})) == []
    at = "options.drawing.nodes.0.skill.sculpt.edits.1.raise"
    bad = fn change -> paths(drawing(%{"edits" => [ball, change.(paint)]})) end
    assert bad.(&Map.put(&1, "raise", "high")) == [at]
    assert bad.(&Map.put(&1, "raise", 0.5)) == [at]
    assert bad.(&Map.put(&1, "mode", "add")) == [at]
    assert bad.(&Map.delete(&1, "mode")) == [at]
    # More than the blend: the border of the relief would be a step.
    assert bad.(&Map.put(&1, "raise", -0.03)) == [at]
    assert bad.(&Map.delete(&1, "blend")) == [at]

    [_, one] = Skill.edits([ball, paint])
    assert one.raise == 0.01
    [scaled] = Skill.edits([%{"shape" => "group", "group" => "g", "scale" => 3}], %{"g" => [paint]})
    assert_in_delta scaled.raise, 0.03, 1.0e-12
  end

  test "the errors of a mirror, a repeat and a group, each with its path; the count of the copies" do
    p = "options.drawing.nodes.0.skill.sculpt"
    ball = %{"shape" => "ball", "size" => [0.1]}
    with_edit = fn e -> drawing(%{"edits" => [Map.merge(ball, e)]}) end
    groups = %{"g" => [ball]}

    cases = [
      {with_edit.(%{"mirror" => "w"}), ["#{p}.edits.0.mirror"]},
      {with_edit.(%{"mirror" => ["x", "x"]}), ["#{p}.edits.0.mirror"]},
      {with_edit.(%{"mirror" => []}), ["#{p}.edits.0.mirror"]},
      {with_edit.(%{"repeat" => 4}), ["#{p}.edits.0.repeat"]},
      {with_edit.(%{
         "repeat" => %{"count" => 1, "axis" => [0, 0, 0], "angle" => 400, "move" => "up", "center" => [0], "more" => 1}
       }),
       [
         "#{p}.edits.0.repeat.more",
         "#{p}.edits.0.repeat.count",
         "#{p}.edits.0.repeat.axis",
         "#{p}.edits.0.repeat.angle",
         "#{p}.edits.0.repeat.move",
         "#{p}.edits.0.repeat.center"
       ]},
      {with_edit.(%{"repeat" => %{"angle" => 10}}), ["#{p}.edits.0.repeat.count"]},
      {drawing(%{"edits" => [%{"shape" => "group", "group" => "nobody"}]}), ["#{p}.edits.0.group"]},
      {drawing(%{"groups" => groups, "edits" => [%{"shape" => "group"}]}), ["#{p}.edits.0.group"]},
      {drawing(%{
         "groups" => groups,
         "edits" => [%{"shape" => "group", "group" => "g", "scale" => 0, "size" => [1], "at" => [0]}]
       }), ["#{p}.edits.0.size", "#{p}.edits.0.scale", "#{p}.edits.0.at"]},
      {drawing(%{"groups" => %{"g" => [%{"shape" => "group", "group" => "g"}]}, "edits" => [ball]}),
       ["#{p}.groups.g.0.shape"]},
      {drawing(%{"groups" => %{"A b" => [ball], "e" => [], "f" => [%{"shape" => "ball"}]}, "edits" => [ball]}),
       ["#{p}.groups.A b", "#{p}.groups.e", "#{p}.groups.f.0.size"]},
      {drawing(%{"groups" => [ball], "edits" => [ball]}), ["#{p}.groups"]},
      # 8 mirrors of 1,000 copies, and 2,001 more: 10,001 edits.
      {drawing(%{
         "edits" => [
           Map.merge(ball, %{"repeat" => %{"count" => 1_000}, "mirror" => ~w(x y z)}),
           Map.put(ball, "repeat", %{"count" => 1_000}),
           Map.put(ball, "repeat", %{"count" => 1_000}),
           ball
         ]
       }), ["#{p}.edits"]},
      {drawing(%{
         "groups" => %{"g" => List.duplicate(ball, 1_000)},
         "edits" => [%{"shape" => "group", "group" => "g", "repeat" => %{"count" => 11}}]
       }), ["#{p}.edits"]}
    ]

    for {d, expected} <- cases, do: assert(paths(d) == expected, inspect({expected, paths(d)}))

    assert paths(
             drawing(%{
               "edits" => [
                 Map.merge(ball, %{"repeat" => %{"count" => 1_000}, "mirror" => ~w(x y z)}),
                 Map.put(ball, "repeat", %{"count" => 1_000}),
                 Map.put(ball, "repeat", %{"count" => 1_000})
               ]
             })
           ) == []
  end
end
