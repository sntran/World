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
    assert part.shapes == World.Sculpt.model(Skill.edits(data()["edits"]), level: :mid, budget: 2_000)

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
      {edit.(Map.merge(ball, %{"mode" => "cut", "blend" => -1, "material" => "gold!"})),
       ["#{p}.edits.0.mode", "#{p}.edits.0.blend", "#{p}.edits.0.material"]}
    ]

    for {d, expected} <- cases, do: assert(paths.(d) == expected, inspect({expected, paths.(d)}))
    assert paths.(drawing(data())) == []
    assert Skill.check(5, "x") == [{"x", "must be an object"}]
  end

  test "the example of docs/format.md is a node that the check passes, and a sculptor makes it" do
    [_, json] = Regex.run(~r/## A sculpture.*?```json\n(.*?)```/s, File.read!("docs/format.md"))
    node = JSON.decode!(json)
    d = %{"name" => "stone", "kind" => "item", "nodes" => [node]}
    assert {:ok, _} = Orders.check(order(d))
    assert [{"stone", %World.Part{shapes: [_ | _]}, _}] = Detail.with(:mid, fn -> Drawing.build(d) end).nodes
  end
end
