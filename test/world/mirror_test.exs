defmodule World.MirrorTest do
  use ExUnit.Case, async: true

  alias World.{Assembly, Frame, Mesh, Mirror, Part, Port, Shape}

  doctest Mirror

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  test "a part: its points and its ports go to the other side, and the mesh stays closed and outside" do
    box = Shape.box({0.1, 0.0, 0.0}, {0.3, 0.2, 0.1}, :steel)
    p = Part.new("a", :part, [box], [@o, Part.port("side", {0.3, 0.1, 0.05}, {1, 0, 0}, {0, 0, 1})])
    m = Mirror.part(p, "b")
    assert m.name == "b" and Mirror.part(p).name == "a"
    assert Part.port!(m, "side").at == {-0.3, 0.1, 0.05}
    assert Part.port!(m, "side").axis == {-1.0, 0.0, 0.0}
    [mesh] = m.shapes
    assert_in_delta Mesh.volume(mesh.points, mesh.faces), Mesh.volume(box.points, box.faces), 1.0e-12
    assert length(Mesh.triangles(mesh, 0)) == length(Mesh.triangles(box, 0))
  end

  test "a frame stays a turn: its axes are a right hand, and a point in it goes to the mirror" do
    f = Frame.new({0.1, 0.2, 0.3}, {1, 1, 0}, {0, 0, 1})
    g = Mirror.frame(f)
    assert_in_delta World.Vec.dot(World.Vec.cross(g.x, g.y), g.z), 1.0, 1.0e-9
    {x, y, z} = Frame.point(f, {0.0, 0.05, 0.02})
    {mx, my, mz} = Frame.point(g, {0.0, 0.05, 0.02})
    assert_in_delta mx, -x, 1.0e-9
    assert_in_delta my, y, 1.0e-9
    assert_in_delta mz, z, 1.0e-9
  end

  test "an assembly: each node at the mirror of its place, a hinge that turns the other way, and its clips" do
    base =
      Part.new("base", :part, [Shape.box({0.0, 0.0, 0.0}, {0.2, 0.1, 0.05}, :steel)], [
        @o,
        Part.port("pin", {0.2, 0.05, 0.05}, {0, 0, 1}, {0, 1, 0})
      ])

    arm = Part.new("arm", :part, [Shape.box({0.0, -0.01, 0.0}, {0.1, 0.01, 0.01}, :steel)], [@o])

    a =
      Assembly.new("a", base, root: "base", clips: [%{name: "swing", length: 1.0, keys: [{0.0, %{"arm" => 30.0}}]}])
      |> Assembly.add("arm", arm, at: "pin", port: "o", kind: :hinge, role: :swing, turn: 20, limits: [0, 90])
      |> Assembly.add("tip", arm, at: Port.new("tip", {0.1, 0.0, 0.05}, {0, 0, 1}, {0, 1, 0}), port: "o", to: "base")

    m = Mirror.assembly(a, "b")
    assert m.name == "b"
    {_, _, conn} = List.keyfind(m.nodes, "arm", 0)
    assert conn.turn == -20.0 and conn.limits == [-90, 0]
    assert [%{keys: [{t, %{"arm" => -30.0}}]}] = m.clips
    assert t == 0
    {_, _, tip} = List.keyfind(m.nodes, "tip", 0)
    assert tip.at.at == {-0.1, 0.0, 0.05}

    # Each placed point is the mirror of a placed point of the first.
    points = fn x ->
      x
      |> World.Build.placed()
      |> Enum.flat_map(fn {_, p} -> Enum.flat_map(p.shapes, & &1.points) end)
      |> MapSet.new(&round6/1)
    end

    assert points.(m) == MapSet.new(points.(a), fn {x, y, z} -> round6({-x, y, z}) end)

    # A slide keeps its limits; an assembly in an assembly is mirrored too.
    s =
      Assembly.new("s", base, root: "base")
      |> Assembly.add("arm", arm, at: "pin", port: "o", kind: :slide, role: :reach, limits: [0, 0.1])

    {_, _, slide} = List.keyfind(Mirror.assembly(s).nodes, "arm", 0)
    assert slide.limits == [0, 0.1]
    outer = Assembly.new("outer", base, root: "base") |> Assembly.add("inner", s, at: "pin", port: "o")
    assert %Assembly{} = elem(List.keyfind(Mirror.assembly(outer).nodes, "inner", 0), 1)
  end

  test "a person has no mirror here" do
    figure = %World.Figure{name: "p"}
    a = %Assembly{name: "a", nodes: [{"root", figure, nil}]}
    assert_raise ArgumentError, ~r/no mirror of World.Figure/, fn -> Mirror.assembly(a) end
  end

  defp round6({x, y, z}), do: {Float.round(x / 1, 6) + 0.0, Float.round(y / 1, 6) + 0.0, Float.round(z / 1, 6) + 0.0}
end
