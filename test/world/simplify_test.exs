defmodule World.SimplifyTest do
  # Fewer triangles for a mesh, with its shape: edge collapse by quadric
  # error metrics (plan 0008, D8).
  use ExUnit.Case, async: true

  alias World.{Frame, Mesh, SDF, Sculpt, Simplify, Vec}
  alias World.Sculpt.Surface

  # The triangles of a sculpture with their materials, before the meshes.
  defp triangles(edits, step) do
    %{bricks: bricks} = Sculpt.bricks(edits, step)
    pieces = Enum.map(bricks, &Surface.decode(Surface.piece(&1, step)))
    points = Enum.reduce(pieces, %{}, &Map.merge(&2, &1.points))
    quads = Enum.flat_map(pieces, & &1.quads)
    keys = quads |> Enum.flat_map(&elem(&1, 0)) |> Enum.uniq()
    ids = keys |> Enum.with_index() |> Map.new()
    tris = for {q, m} <- quads, [a, b, c, d] = Enum.map(q, &ids[&1]), f <- [[a, b, c], [a, c, d]], do: {f, m}
    {Enum.map(keys, &points[&1]), tris}
  end

  # Each edge in one face each way.
  defp closed?(faces) do
    faces
    |> Enum.flat_map(fn {[a, b, c], _} -> [{a, b}, {b, c}, {c, a}] end)
    |> Enum.frequencies()
    |> then(fn count -> Enum.all?(count, fn {{a, b}, n} -> n == 1 and count[{b, a}] == 1 end) end)
  end

  defp volume(points, faces), do: Mesh.volume(points, Enum.map(faces, &elem(&1, 0))) / 6

  test "a ball of many faces, to 500: closed, its volume, its points near its surface" do
    {points, faces} = triangles([SDF.edit(:ball, {0.5})], 0.025)
    assert length(faces) > 5_000 and closed?(faces)
    {ps, fs} = Simplify.collapse(points, faces, 500)
    assert length(fs) <= 500 and closed?(fs)
    assert_in_delta volume(ps, fs), 4 / 3 * :math.pi() * 0.125, 0.04 * 4 / 3 * :math.pi() * 0.125
    for p <- ps, do: assert(abs(Vec.len(p) - 0.5) < 0.03)
  end

  test "a box, to 100 faces: its faces stay flat, its volume and its bounds stay" do
    box = [SDF.edit(:box, {0.42, 0.31, 0.27}, frame: Frame.move({0.013, 0.007, 0.004}))]
    {points, faces} = triangles(box, 0.05)
    {ps, fs} = Simplify.collapse(points, faces, 100)
    assert length(fs) <= 100 and closed?(fs)
    assert_in_delta volume(ps, fs), 0.84 * 0.62 * 0.54, 1.0e-3
    {{lx, ly, lz}, {hx, hy, hz}} = Vec.bounds(ps)

    for {a, b} <- [{lx, -0.407}, {hx, 0.433}, {ly, -0.303}, {hy, 0.317}, {lz, -0.266}, {hz, 0.274}],
        do: assert_in_delta(a, b, 1.0e-5)
  end

  test "a stone of three materials, to a budget: closed, each material in its faces, its borders on their lines" do
    :rand.seed(:exsss, {5, 5, 5})

    edits =
      [SDF.edit(:ellipsoid, {0.6, 0.5, 0.4}, material: :stone)] ++
        for i <- 1..12 do
          dir = Vec.norm({:rand.normal(), :rand.normal(), :rand.normal()})
          at = {elem(dir, 0) * 0.6, elem(dir, 1) * 0.5, elem(dir, 2) * 0.4}

          SDF.edit(:ball, {0.12},
            frame: Frame.move(at),
            mode: :paint,
            material: if(rem(i, 2) == 0, do: :moss, else: :clay)
          )
        end

    {points, faces} = triangles(edits, 0.04)

    # The points of a mesh where `n` materials or more meet.
    meet = fn ps, fs, n ->
      fs
      |> Enum.flat_map(fn {f, m} -> Enum.map(f, &{&1, m}) end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.filter(fn {_, ms} -> length(Enum.uniq(ms)) >= n end)
      |> Enum.map(fn {v, _} -> Enum.at(ps, v) end)
    end

    {ps, fs} = Simplify.collapse(points, faces, 400)
    assert length(fs) <= 400 and closed?(fs)
    assert fs |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort() == [:clay, :moss, :stone]
    # A point where three materials meet stays; a point of a border is near a border of before.
    assert MapSet.subset?(MapSet.new(meet.(ps, fs, 3)), MapSet.new(meet.(points, faces, 3)))
    before = meet.(points, faces, 2)

    for p <- meet.(ps, fs, 2),
        do: assert(Enum.min(Enum.map(before, &Vec.len(Vec.sub(&1, p)))) < 0.04, inspect(p))

    meshes = Surface.meshes(Enum.map(Sculpt.bricks(edits, 0.04).bricks, &Surface.piece(&1, 0.04)), budget: 400)
    assert meshes |> Enum.map(&length(&1.faces)) |> Enum.sum() == length(fs)
  end

  test "a face with no area (its points on a line) does not stop the collapse" do
    # A tetrahedron with the point m at the middle of the edge from a to b:
    # the face a b d becomes a m d and m b d, and a b m has no area.
    points = [{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, 0, 1}, {0.5, 0, 0}]
    faces = [{[0, 2, 1], :a}, {[0, 3, 2], :a}, {[1, 2, 3], :a}, {[0, 4, 3], :a}, {[4, 1, 3], :a}, {[0, 1, 4], :a}]
    assert closed?(faces)
    {_ps, fs} = Simplify.collapse(points, faces, 4)
    assert length(fs) <= 6 and closed?(fs)

    # A tetrahedron has no edge to collapse: its four faces stay.
    tetra = [{[0, 2, 1], :a}, {[0, 3, 2], :a}, {[1, 2, 3], :a}, {[0, 1, 3], :a}]
    assert {_, ^tetra} = Simplify.collapse(Enum.take(points, 4), tetra, 2)
  end

  test "a pin keeps a point at its place: the cost of a move from there" do
    # A flat sheet of 10 x 10 squares: each collapse in it costs nothing.
    points = for j <- 0..10, i <- 0..10, do: {i * 0.1, j * 0.1, 0.0}
    at = fn i, j -> j * 11 + i end

    faces =
      for j <- 0..9,
          i <- 0..9,
          f <- [[at.(i, j), at.(i + 1, j), at.(i + 1, j + 1)], [at.(i, j), at.(i + 1, j + 1), at.(i, j + 1)]],
          do: {f, :m}

    marks = [at.(2, 3), at.(5, 5), at.(7, 2), at.(3, 8), at.(8, 7)]
    pins = for i <- 0..120, do: if(i in marks, do: 100.0, else: 0.0)
    here = fn result -> Enum.count(marks, &(Enum.at(points, &1) in result.points)) end

    pinned = Simplify.collapse(points, faces, 50, pins: pins)
    assert length(pinned.faces) <= 50 and here.(pinned) == 5
    assert here.(Simplify.collapse(points, faces, 50, [])) < 5
    assert Simplify.collapse(points, faces, 50, pins: nil) == Simplify.collapse(points, faces, 50, [])
  end

  test "a budget of more faces than the mesh has: the same mesh" do
    {points, faces} = triangles([SDF.edit(:ball, {0.3})], 0.1)
    assert Simplify.collapse(points, faces, length(faces)) == {points, faces}
  end
end
