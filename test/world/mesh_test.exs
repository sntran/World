defmodule World.MeshTest do
  use ExUnit.Case, async: true

  alias World.Frame

  alias World.Mesh

  alias World.Shape

  alias World.Vec
  # Each edge of a closed mesh is in two triangles, once in each direction.
  defp closed?(corners) do
    edges =
      corners
      |> Enum.map(fn {p, _} -> Enum.map(Tuple.to_list(p), &Float.round(&1, 6)) end)
      |> Enum.chunk_every(3)
      |> Enum.flat_map(fn [a, b, c] -> [{a, b}, {b, c}, {c, a}] end)
      |> MapSet.new()

    Enum.all?(edges, fn {a, b} -> MapSet.member?(edges, {b, a}) end)
  end

  # Six times the volume of a mesh from its triangles.
  defp volume(corners) do
    corners
    |> Enum.map(&elem(&1, 0))
    |> Enum.chunk_every(3)
    |> Enum.map(fn [a, b, c] -> Vec.dot(a, Vec.cross(b, c)) end)
    |> Enum.sum()
  end

  test "a box has 12 triangles, a volume, and hard normals" do
    tris = Mesh.triangles(Shape.box({0, 0, 0}, {1, 2, 3}, :paint))
    assert length(tris) == 36
    assert closed?(tris)
    assert_in_delta volume(tris), 6 * 6.0, 1.0e-9

    for {_, n} <- tris, do: assert(Enum.count(Tuple.to_list(n), &(abs(&1) > 0.99)) == 1)
  end

  test "a round box with smooth steps is closed, and smooth" do
    m = Shape.box({0, 0, 0}, {1, 1, 1}, :white, round: 0.1, smooth: 2)
    tris = Mesh.triangles(m)
    assert closed?(tris)
    assert length(tris) > 36 * 9
    assert Mesh.triangles(m, 0) |> length() == 54 * 2 * 3
  end

  test "each shape is closed, with its faces to the outside" do
    shapes = [
      Shape.cylinder(0.5, 1.0, :steel),
      Shape.prism([{0, 0}, {1, 0}, {1, 0.2}, {0.2, 0.2}, {0.2, 1}, {0, 1}], 0.5, :wood),
      Shape.lathe([{0, 0}, {0.5, 0}, {0.5, 1}, {0, 1.2}], :copper),
      Shape.lathe([{0.4, 0}, {0.5, 0}, {0.5, 1}, {0.4, 1}], :steel, kind: :ring),
      Shape.lathe([{0.4, 0}, {0.5, 0.2}, {0.3, 1}], :steel),
      Shape.sphere(1.0, :chrome),
      Shape.loft([{{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, 1, 1, 4}, {{0, 0, 1}, {1, 0, 0}, {0, 1, 0}, 0.5, 0.5, 2}], :seat),
      Shape.sweep([{0, 0, 0}, {0, 0, 1}, {1, 0, 1}, {1, 1, 1}], 0.1, :black),
      Shape.sweep([{0, 0, 0}, {0, 0, 1}, {0, 0, 2}], 0.1, :black)
    ]

    for s <- shapes do
      tris = Mesh.triangles(s)
      assert closed?(tris), "#{inspect(s.material)} is not closed"
      assert volume(tris) > 0
    end
  end

  test "outside turns the faces of a mesh with a volume less than 0" do
    points = [{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, 0, 1}]
    inward = [[0, 1, 2], [0, 1, 3], [0, 3, 2], [1, 2, 3]]
    out = Mesh.outside(points, inward)
    assert Mesh.volume(points, out) > 0
    assert Mesh.outside(points, out) == out
  end

  test "transform and bounds" do
    m = Shape.box({0, 0, 0}, {1, 1, 1}, :paint) |> Mesh.transform(Frame.move({1, 2, 3}))
    assert Mesh.bounds(m) == {{1.0, 2.0, 3.0}, {2.0, 3.0, 4.0}}
    assert Shape.cylinder(1, 1, :x, frame: Frame.move({0, 0, 5})) |> Mesh.bounds() |> elem(0) |> elem(2) == 5.0
  end

  test "a mesh that the core of Wings refuses raises an error" do
    # Two faces with the same edge in the same direction.
    bad = Mesh.new([{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, 0, 1}], [[0, 1, 2], [0, 1, 3]], :paint)
    assert_raise ArgumentError, ~r/the core of Wings refused the mesh/, fn -> Mesh.triangles(bad) end
  end

  test "an open mesh gives only its visible faces" do
    open = Mesh.new([{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}], [[0, 1, 2, 3], [3, 2, 1, 0]], :paint)
    assert length(Mesh.triangles(open)) == 12
  end

  test "a cage of 8 corners" do
    corners = [{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}, {0, 0, 1}, {1, 0, 1}, {1, 1, 1}, {0, 1, 1}]
    assert length(Mesh.triangles(Shape.cage(corners, :paint))) == 36
  end

  test "a polygon" do
    assert length(Shape.polygon(1.0, 6)) == 6
    [{x, y} | _] = Shape.polygon(1.0, 4, 90.0)
    assert_in_delta x, 0.0, 1.0e-12
    assert_in_delta y, 1.0, 1.0e-12
  end
end
