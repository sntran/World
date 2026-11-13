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
      pieces
      |> Enum.flat_map(&Surface.decode(&1).quads)
      |> Enum.flat_map(fn {[a, b, c, d], _} -> [{a, b}, {b, c}, {c, d}, {d, a}] end)

    count = Enum.frequencies(edges)
    Enum.all?(count, fn {{a, b}, n} -> count[{b, a}] == n end)
  end

  # Each edge in one quad each way: two faces.
  defp manifold?(pieces) do
    pieces
    |> Enum.flat_map(&Surface.decode(&1).quads)
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

  test "fewer faces: in one region, and in many regions with their shared points; small pieces go" do
    faces = fn meshes -> meshes |> Enum.map(&length(&1.faces)) |> Enum.sum() end
    # One region: a small ball.
    one = Surface.meshes(pieces([SDF.edit(:ball, {0.1})], 0.01), budget: 200)
    assert faces.(one) <= 200
    assert_in_delta volume(one), 4 / 3 * :math.pi() * 0.001, 0.0004
    # Many regions: a long capsule across them, to its budget, with its volume.
    long = [SDF.edit(:capsule, {1.0, 0.1}, frame: Frame.move({0.3, 0.3, 0.01}))]
    many = Surface.meshes(pieces(long, 0.01), budget: 4_000)
    assert faces.(many) <= 4_000
    assert_in_delta volume(many), :math.pi() * 0.01 * 2.0 + 4 / 3 * :math.pi() * 0.001, 0.001
    # A ball of 1 cm next to a ball of 10 cm, with cells of 1 cm: the small one goes.
    two = [SDF.edit(:ball, {0.1}), SDF.edit(:ball, {0.004}, frame: Frame.move({0.3, 0.0, 0.0}))]
    assert faces.(Surface.meshes(pieces(two, 0.01), small: 0.02)) == faces.(Surface.meshes(pieces([hd(two)], 0.01)))
    # A budget of more faces than the mesh has: the same mesh.
    assert Surface.meshes(pieces([hd(two)], 0.01), budget: 1_000_000) == Surface.meshes(pieces([hd(two)], 0.01))
  end

  test "fewer faces, with the cells: a flat part keeps few faces, and a small part keeps its corners" do
    # A slab of many regions with a small post on it (a roof with a chimney).
    slab = SDF.edit(:box, {0.8, 0.8, 0.1}, frame: Frame.move({0.003, 0.007, 0.001}))
    post = SDF.edit(:box, {0.06, 0.06, 0.15}, frame: Frame.move({0.213, 0.107, 0.2}))
    ps = pieces([slab, post], 0.02)
    [all] = Surface.meshes(ps)
    solid = 1.6 * 1.6 * 0.2 + 0.12 * 0.12 * 0.15

    corners =
      for(x <- [-0.797, 0.803], y <- [-0.793, 0.807], z <- [-0.099, 0.101], do: {x, y, z}) ++
        for x <- [0.153, 0.273], y <- [0.047, 0.167], do: {x, y, 0.35}

    here = fn mesh ->
      Enum.count(corners, fn c -> Enum.any?(mesh.points, &(Vec.len(Vec.sub(&1, c)) < 1.0e-3)) end)
    end

    assert here.(all) == 12

    # A budget that the mesh does not need: the flat parts go all the same.
    [rich] = Surface.meshes(ps, budget: 2_000, step: 0.02)
    assert length(rich.faces) < 700 and here.(rich) == 12
    assert_in_delta volume([rich]), solid, 2.0e-3
    # A small budget: the corners of the slab and of the post stay, with the volume.
    [poor] = Surface.meshes(ps, budget: 100, step: 0.02)
    assert length(poor.faces) <= 100 and here.(poor) == 12
    assert_in_delta volume([poor]), solid, 2.0e-3
    # With no cells, a region does not know which collapse is free: the budget only.
    [plain] = Surface.meshes(ps, budget: 2_000)
    assert length(plain.faces) in 1_900..2_000
    # Two times, the same mesh.
    assert Surface.meshes(ps, budget: 100, step: 0.02) == [poor]
    assert length(all.faces) > 30_000
  end

  test "a surface through a point of the grid is closed: the bricks give one place to the point" do
    # The base of the cone is at -1 cell, and its middle is at a corner of bricks.
    edits = [SDF.edit(:ball, {0.04}), SDF.edit(:cone, {0.04, 0.0, 0.154}, frame: Frame.move({0.0, 0.0, 0.111}))]
    ps = pieces(edits, 0.043)
    assert length(ps) == 8 and closed?(ps)
    # A face of a box at a border of bricks: the bricks on its outer side have its edges.
    box = [SDF.edit(:box, {0.04, 0.109, 0.04}, frame: Frame.move({0.0, -0.195, 0.0}))]
    ps = pieces(box, 0.038)
    assert length(ps) == 8 and closed?(ps) and manifold?(ps)
  end

  test "an outline of 32 points builds: closed, and each point of its mesh within a cell of it (plan 0012, R3)" do
    # The outline of a gear of 16 teeth, 0.1 deep, with round edges.
    points =
      for i <- 0..31,
          a = i * :math.pi() / 16,
          r = if(rem(i, 2) == 0, do: 0.3, else: 0.22),
          do: {r * :math.cos(a), r * :math.sin(a)}

    gear = SDF.edit(:extrude, {points, 0.05, 0.01}, frame: Frame.move({0.011, 0.007, 0.003}))
    ps = pieces([gear], 0.01)
    assert closed?(ps)
    [mesh] = Surface.meshes(ps)
    assert length(mesh.faces) > 5_000
    for p <- mesh.points, do: assert(abs(SDF.distance(gear, p)) < 0.01)
    # Its volume: the area of the outline times its depth, less the round edges.
    area = 16 * 0.3 * 0.22 * :math.sin(:math.pi() / 16)
    assert_in_delta volume([mesh]), area * 0.1, 0.004

    # A profile of 32 points turned round the axis (a bowl with a thick wall): closed too.
    outer = for i <- 0..15, a = i * :math.pi() / 30, do: {0.3 * :math.sin(a) + 0.001, -0.3 * :math.cos(a)}
    inner = for i <- 15..0//-1, a = i * :math.pi() / 30, do: {0.26 * :math.sin(a) + 0.001, -0.26 * :math.cos(a)}
    bowl = SDF.edit(:revolve, {outer ++ inner})
    ps = pieces([bowl], 0.01)
    assert closed?(ps)
    [mesh] = Surface.meshes(ps)
    for p <- mesh.points, do: assert(abs(SDF.distance(bowl, p)) < 0.01)
  end

  test "the collapse keeps the points where the colors change, when the budget keeps many of the faces" do
    # A ball with a dark spot (a paint: the shape is the same with no color).
    spot = SDF.edit(:ball, {0.15}, frame: Frame.move({0.0, 0.0, 0.5}), mode: :paint, blend: 0.01, color: {10, 10, 10})
    colored = [SDF.edit(:ball, {0.5}, color: {200, 160, 60}), spot]
    plain = Enum.map(colored, &%{&1 | color: nil})
    [piece | _] = with_colors = pieces(colored, 0.025)
    # A piece has three bytes for each point, and the same points as with no colors.
    assert byte_size(piece.colors) == 3 * div(byte_size(piece.points), 32)
    assert map_size(Surface.decode(piece).colors) == div(byte_size(piece.points), 32)
    assert Enum.map(with_colors, &Map.delete(&1, :colors)) == pieces(plain, 0.025)
    assert Surface.decode(hd(pieces(plain, 0.025))).colors == %{}

    # The points of a mesh at the border of the spot (a circle round the pole).
    faces = fn meshes -> meshes |> Enum.map(&length(&1.faces)) |> Enum.sum() end
    total = faces.(Surface.meshes(with_colors))

    at_border = fn meshes ->
      for m <- meshes, {x, y, z} <- m.points, z > 0, abs(Vec.len({x, y, 0.0}) - 0.15) < 0.02, do: 1
    end

    rich = div(total, 2)
    {kept, bare} = {Surface.meshes(with_colors, budget: rich), Surface.meshes(pieces(plain, 0.025), budget: rich)}
    assert faces.(kept) <= rich and faces.(bare) <= rich
    assert length(at_border.(kept)) > 1.5 * length(at_border.(bare))

    # A budget that keeps few of the faces: the pins count little, and the shape stays.
    few = Surface.meshes(with_colors, budget: div(total, 20))
    assert faces.(few) <= div(total, 20)
    assert_in_delta volume(few), 4 / 3 * :math.pi() * 0.125, 0.03
    # The pieces from the tree (with the lists of the eighths of each brick) have the same colors.
    %{bricks: bricks} = Sculpt.bricks(colored, 0.025, each: &Surface.piece(&1, 0.025))
    assert Enum.map(bricks, & &1.piece) == with_colors
  end

  test "a piece is binaries: its points with their keys, its quads; a cell too far from the origin has no key" do
    [piece | _] = pieces([SDF.edit(:ball, {0.1})], 0.02)
    assert is_binary(piece.points) and is_binary(piece.quads) and piece.materials == [nil]
    %{points: points, quads: quads} = Surface.decode(piece)
    assert map_size(points) == div(byte_size(piece.points), 32) and length(quads) == div(byte_size(piece.quads), 17)
    assert Surface.key({-3, 4, 5}, 2) != Surface.key({-3, 4, 5}, 3)
    assert_raise ArgumentError, fn -> Surface.key({200_000, 0, 0}, 0) end
  end
end
