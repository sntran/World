defmodule World.Sculpt.SurfaceTest do
  # The surface of a sculpture: dual contouring in each brick, and one
  # mesh from the pieces (plan 0008, D7; R3).
  use ExUnit.Case, async: true

  alias World.{Frame, Mesh, SDF, Sculpt, Vec}
  alias World.Sculpt.Surface

  defp pieces(edits, step) do
    %{bricks: bricks} = Sculpt.bricks(edits, step)
    Enum.map(bricks, &Surface.piece(&1, step))
  end

  # Each edge of the quads of all the pieces is in as many quads one way
  # as the other: the surface is closed, with no gap between bricks. (At
  # a face of a cell whose inside corners are on its diagonal, an edge is
  # in two quads each way: two sheets touch there.)
  defp closed?(pieces) do
    edges =
      pieces |> Enum.flat_map(& &1.quads) |> Enum.flat_map(fn {[a, b, c, d], _} -> [{a, b}, {b, c}, {c, d}, {d, a}] end)

    count = Enum.frequencies(edges)
    Enum.all?(count, fn {{a, b}, n} -> count[{b, a}] == n end)
  end

  # Each edge in one quad each way: two faces.
  defp manifold?(pieces) do
    pieces
    |> Enum.flat_map(& &1.quads)
    |> Enum.flat_map(fn {[a, b, c, d], _} -> [{a, b}, {b, c}, {c, d}, {d, a}] end)
    |> Enum.frequencies()
    |> Map.values()
    |> Enum.all?(&(&1 == 1))
  end

  defp volume(meshes), do: meshes |> Enum.map(&(Mesh.volume(&1.points, &1.faces) / 6)) |> Enum.sum()

  test "a ball: closed, its faces to the outside, its volume, its points on its surface" do
    ball = [SDF.edit(:ball, {0.5}, material: :stone)]
    ps = pieces(ball, 0.05)
    assert length(ps) > 1 and closed?(ps) and manifold?(ps)
    [mesh] = Surface.meshes(ps)
    assert mesh.material == :stone
    assert_in_delta volume([mesh]), 4 / 3 * :math.pi() * 0.125, 0.02 * 4 / 3 * :math.pi() * 0.125
    for p <- mesh.points, do: assert(abs(Vec.len(p) - 0.5) < 0.005)
  end

  test "a box of hard edits keeps its sharp edges and its corners" do
    box = [SDF.edit(:box, {0.42, 0.31, 0.27}, frame: Frame.move({0.013, 0.007, 0.004}))]
    ps = pieces(box, 0.05)
    assert closed?(ps) and manifold?(ps)
    [mesh] = Surface.meshes(ps)
    assert_in_delta volume([mesh]), 0.84 * 0.62 * 0.54, 1.0e-3
    {{lx, ly, lz}, {hx, hy, hz}} = Mesh.bounds(mesh)

    for {a, b} <- [{lx, -0.407}, {hx, 0.433}, {ly, -0.303}, {hy, 0.317}, {lz, -0.266}, {hz, 0.274}],
        do: assert_in_delta(a, b, 1.0e-6)

    # Each face is in a face of the box: its normal along an axis.
    t = List.to_tuple(mesh.points)

    for [a, b, c] <- mesh.faces do
      n = Vec.cross(Vec.sub(elem(t, b), elem(t, a)), Vec.sub(elem(t, c), elem(t, a)))

      if Vec.len(n) > 1.0e-9,
        do: assert(Enum.max(Tuple.to_list(n) |> Enum.map(&abs/1)) / Vec.len(n) > :math.cos(:math.pi() / 180))
    end
  end

  test "a stone of many bricks and materials: closed across its bricks, a mesh for each material" do
    :rand.seed(:exsss, {3, 3, 3})

    edits =
      [SDF.edit(:ellipsoid, {0.8, 0.6, 0.5}, material: :stone)] ++
        for i <- 1..40 do
          dir = Vec.norm({:rand.normal(), :rand.normal(), :rand.normal()})
          at = {elem(dir, 0) * 0.8, elem(dir, 1) * 0.6, elem(dir, 2) * 0.5}
          mode = Enum.at([:add, :add, :subtract, :paint], rem(i, 4))

          SDF.edit(:ball, {0.05 + :rand.uniform() * 0.1},
            frame: Frame.move(at),
            mode: mode,
            blend: 0.03,
            material: if(mode == :paint, do: :moss)
          )
        end

    ps = pieces(edits, 0.04)
    assert length(ps) > 20 and closed?(ps)
    meshes = Surface.meshes(ps)
    assert Enum.map(meshes, & &1.material) |> Enum.sort() == [:moss, :paint, :stone]
    assert volume(meshes) > 0.8
  end
end
