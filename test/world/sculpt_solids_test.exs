defmodule World.Sculpt.SolidsTest do
  # The mesh of a level of a sculpture from the solids of its edits (#44 and the roofs of the blocks of Vũng Tàu).
  use ExUnit.Case, async: true

  alias World.{Frame, SDF, Vec}
  alias World.Sculpt.Solids

  # Each edge of a closed mesh is in two faces, one time in each direction: the points of one place are one point.
  defp closed?(mesh) do
    at = List.to_tuple(mesh.points)
    key = fn i -> elem(at, i) |> Tuple.to_list() |> Enum.map(&Float.round(&1, 6)) end
    edges = for [a, b, c] <- mesh.faces, {p, q} <- [{a, b}, {b, c}, {c, a}], do: {key.(p), key.(q)}
    counts = Enum.frequencies(edges)
    Enum.all?(edges, fn {p, q} -> counts[{p, q}] == 1 and counts[{q, p}] == 1 end)
  end

  # The volume of a closed mesh with its faces to the outside (more than 0).
  defp volume(mesh) do
    at = List.to_tuple(mesh.points)

    Enum.sum(for [a, b, c] <- mesh.faces, do: Vec.dot(elem(at, a), Vec.cross(elem(at, b), elem(at, c)))) / 6
  end

  defp one(edit) do
    [mesh] = Solids.meshes([edit])
    mesh
  end

  test "each shape is a closed solid of few faces, with its faces to the outside, its volume and the color of its edit" do
    {n, pi} = {8, :math.pi()}
    # (The area of a polygon of n sides round a circle of radius r: its points on the circle.)
    ring = fn r -> n / 2 * r * r * :math.sin(2 * pi / n) end

    cases = [
      {SDF.edit(:box, {1.0, 2.0, 3.0}), 12, 48.0},
      {SDF.edit(:cylinder, {1.0, 2.0}), 28, ring.(1.0) * 4},
      # (A cone with two radii: a frustum; with a point at the top.)
      {SDF.edit(:cone, {2.0, 1.0, 1.5}), 28, 3.0 / 3 * (ring.(2.0) + ring.(1.0) + :math.sqrt(ring.(2.0) * ring.(1.0)))},
      {SDF.edit(:cone, {2.0, 0.0, 1.5}), 14, 3.0 / 3 * ring.(2.0)},
      {SDF.edit(:wedge, {1.0, 2.0, 3.0}), 8, 2.0 * (4.0 * 6.0 / 2)},
      # (A V of 6 points that is not convex.)
      {SDF.edit(:extrude, {[{-3.0, 0.0}, {-2.0, -1.0}, {0.0, 1.0}, {2.0, -1.0}, {3.0, 0.0}, {0.0, 3.0}], 0.5, 0.0}), 20,
       10.0}
    ]

    for {edit, faces, v} <- cases do
      mesh = one(%{edit | color: {0.5, 0.25, 0.0}})
      assert length(mesh.faces) == faces, inspect(edit.shape)
      assert closed?(mesh), inspect(edit.shape)
      assert_in_delta volume(mesh), v, 1.0e-6 * v + 1.0e-9
      assert Solids.count([edit]) == faces
      # (Each face with its own three points and its normal; the color of the edit in sRGB.)
      assert length(mesh.points) == 3 * faces and length(mesh.normals) == 3 * faces
      assert Enum.uniq(mesh.colors) == [{188, 137, 0}]
    end

    # A ball and an ellipsoid: 8 sides and 4 rows, with their points on the surface.
    egg = one(SDF.edit(:ellipsoid, {1.0, 3.0, 2.0}))
    assert length(egg.faces) == 48 and closed?(egg) and volume(egg) > 0.6 * 4 / 3 * pi * 6
    assert Enum.all?(egg.points, fn {x, y, z} -> abs(x * x + y * y / 9 + z * z / 4 - 1) < 1.0e-9 end)
    assert length(one(SDF.edit(:ball, {1.0})).faces) == 48
  end

  test "the frame of an edit: its place, its turn and a mirror; the faces stay to the outside; each material a mesh" do
    turn = Frame.new({1.0, 2.0, 3.0}, {0.0, 0.0, 1.0}, {0.0, 1.0, 0.0})
    mirror = %Frame{x: {-1.0, 0.0, 0.0}, at: {5.0, 0.0, 0.0}}

    edits = [
      SDF.edit(:box, {1.0, 1.0, 1.0}, frame: turn, material: :glass),
      SDF.edit(:wedge, {1.0, 2.0, 3.0}, frame: mirror, material: :paint),
      # (An edit that paints or takes away has no solid.)
      SDF.edit(:box, {0.5, 0.5, 0.5}, mode: :paint, material: :paint),
      SDF.edit(:box, {0.5, 0.5, 0.5}, mode: :subtract, material: :paint)
    ]

    [glass, paint] = Solids.meshes(edits)
    assert {glass.material, paint.material} == {:glass, :paint}
    assert closed?(glass) and closed?(paint)
    assert_in_delta volume(glass), 8.0, 1.0e-9
    assert_in_delta volume(paint), 24.0, 1.0e-9
    assert Solids.count(edits) == 20
    # (An edit with no color: white.)
    assert Enum.uniq(glass.colors) == [{255, 255, 255}]
  end

  test "the shapes that a solid can have, and the errors of the others" do
    assert Solids.shapes() == ~w(ball box cone cylinder ellipsoid extrude wedge)
    assert Solids.error(SDF.edit(:box, {1.0, 1.0, 1.0})) == nil
    assert Solids.error(SDF.edit(:box, {1.0, 1.0, 1.0}, mode: :paint)) == nil
    assert Solids.error(SDF.edit(:capsule, {1.0, 1.0})) =~ "has no solid"
    assert Solids.error(SDF.edit(:box, {1.0, 1.0, 1.0}, mode: :subtract)) =~ "takes away"
    assert Solids.error(SDF.edit(:box, {1.0, 1.0, 1.0}, mode: :crop)) =~ "takes away"
  end

  test "the key solids of a sculpture: its levels, the shapes and the modes of its edits there, and its budget" do
    box = %{"shape" => "box", "size" => [1, 1, 1], "color" => "#808080"}
    data = %{"edits" => [box], "solids" => ["far"], "budget" => %{"far" => 12}}
    path = fn data -> for {p, m} <- World.Skills.Sculpt.check(data, "s"), do: {p, m} end

    assert path.(data) == []
    assert World.Skills.Sculpt.faces(data, :far) == 12

    assert [{"s.solids", "at far the solids have 24 triangles, more than the budget of 12"}] =
             path.(%{data | "edits" => [box, Map.put(box, "at", [3, 0, 0])]})

    assert [{"s.solids", "at far: the shape capsule has no solid" <> _}] =
             path.(%{data | "edits" => [%{"shape" => "capsule", "size" => [1, 0.5]}]})

    assert [{"s.solids", "at far: an edit that takes away has no solid"}] =
             path.(%{data | "edits" => [box, Map.put(box, "mode", "subtract")]})

    assert [{"s.solids", "must be a list of near, mid and far"}] = path.(%{data | "solids" => "far"})
    # (An edit that is not right gives its own error, and the solids give none.)
    wrong = path.(%{data | "edits" => [%{"shape" => "blob"}]})
    assert wrong != [] and Enum.all?(wrong, fn {p, _} -> String.starts_with?(p, "s.edits.0.") end)
  end
end
