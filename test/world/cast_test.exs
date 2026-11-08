defmodule World.CastTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.{Cast, Mesh, Shape}

  defp box(a, b), do: Shape.box(a, b, :concrete)
  defp volume(m), do: Mesh.volume(m.points, m.faces) / 6

  test "a box: the cells and the surface to the box, a closed mesh that the core of Wings takes" do
    g = Cast.solid([box({-1.0, -0.5, 0.0}, {1.0, 0.5, 3.0})], 0.1)
    assert elem(Cast.volume(g), 0) == 6000
    m = Cast.mesh(g, :stone)
    {{x0, y0, z0}, {x1, y1, z1}} = Mesh.bounds(m)

    for {a, b} <- [{x0, -1.0}, {x1, 1.0}, {y0, -0.5}, {y1, 0.5}, {z0, 0.0}, {z1, 3.0}],
        do: assert_in_delta(a, b, 1.0e-6)

    assert m.material == :stone
    assert_in_delta volume(m), 6.0, 0.1
    assert div(length(Mesh.triangles(m)), 3) == length(m.faces)
    assert Cast.at(g, -1, 0, 0) == 0 and Cast.at(g, 0, 0, 10_000) == 0
  end

  test "two shapes in one place are one solid, with no inner surface; a list of points and triangles is a surface" do
    a = box({0.0, 0.0, 0.0}, {2.0, 1.0, 1.0})
    b = box({1.0, 0.0, 0.0}, {3.0, 1.0, 1.0})
    m = Cast.mesh(Cast.solid([a, b], 0.1), :concrete)
    assert_in_delta volume(m), 3.0, 0.06
    {{x0, _, _}, {x1, _, _}} = Mesh.bounds(m)
    assert_in_delta x0, 0.0, 1.0e-6
    assert_in_delta x1, 3.0, 1.0e-6

    tris = for [p | rest] <- a.faces, [q, r] <- Enum.chunk_every(rest, 2, 1, :discard), do: [p, q, r]
    assert Cast.solid([{a.points, tris}], 0.1).cells == Cast.solid([a], 0.1).cells
  end

  test "a relaxed shell: the same faces, each edge in two faces, the steps of the cells gone, the volume within 2%" do
    g = Cast.solid([Shape.cylinder(1.0, 2.0, :concrete, sides: 48)], 0.1)
    grid = Cast.surface(g)
    pieces = for slab <- Cast.slabs(grid, 3), do: Cast.quads(grid, slab)
    plain = Cast.join(grid, pieces, :concrete)
    smooth = Cast.join(grid, pieces, :concrete, relax: 2)
    assert smooth.faces == plain.faces and length(smooth.points) == length(plain.points)

    edges =
      smooth.faces
      |> Enum.flat_map(fn [a, b, c] -> [{a, b}, {b, c}, {c, a}] end)
      |> Enum.frequencies_by(fn {a, b} -> {min(a, b), max(a, b)} end)

    assert Enum.all?(edges, fn {_, n} -> n == 2 end)
    assert_in_delta volume(smooth) / volume(plain), 1.0, 0.02

    # On the side of the cylinder, the points of the relaxed shell are
    # nearer to the circle than the steps of the cells.
    off = fn m ->
      side = for {x, y, z} <- m.points, z > 0.3 and z < 1.7, do: abs(:math.sqrt(x * x + y * y) - 1.0)
      Enum.sum(side) / length(side)
    end

    assert off.(smooth) < off.(plain)
  end

  test "a thin plate thicker than a cell stays, at its true thickness" do
    m = Cast.mesh(Cast.solid([box({0.0, 0.0, 0.0}, {2.0, 2.0, 0.15})], 0.1), :concrete)
    {{_, _, z0}, {_, _, z1}} = Mesh.bounds(m)
    assert_in_delta z1 - z0, 0.15, 0.02
  end

  test "two boxes that touch at an edge give a mesh with each edge in two faces" do
    m =
      Cast.mesh(
        Cast.solid([box({0.0, 0.0, 0.0}, {1.0, 1.0, 1.0}), box({1.0, 1.0, 0.0}, {2.0, 2.0, 1.0})], 0.1),
        :concrete
      )

    uses = Enum.frequencies(for [a, b, c] <- m.faces, {p, q} <- [{a, b}, {b, c}, {c, a}], do: {min(p, q), max(p, q)})
    assert uses |> Map.values() |> Enum.uniq() == [2]
    assert div(length(Mesh.triangles(m)), 3) == length(m.faces)
  end

  test "a hollow box: a wall, the rest empty, an opening through the wall; a degenerate triangle has no part" do
    g =
      Cast.solid(
        [box({0.0, 0.0, 0.0}, {2.0, 2.0, 2.0}), {[{0.5, 0.5, 0.5}, {0.5, 0.5, 0.5}, {0.6, 0.5, 0.5}], [[0, 1, 2]]}],
        0.1
      )

    h = Cast.hollow(g, 0.2)
    {n, _} = Cast.volume(h)
    assert n < elem(Cast.volume(g), 0) and n > 0
    m = Cast.mesh(h, :concrete)
    assert_in_delta volume(m), 8.0 - 1.6 * 1.6 * 1.6, 0.6

    door = Cast.hollow(g, 0.2, [{{0.8, -1.0, 0.0}, {1.2, 0.5, 1.0}}])
    assert elem(Cast.volume(door), 0) < n
    assert Cast.erode(g, 0) == g
  end

  property "the cast of a box is the box, to the cell" do
    check all x <- float(min: 0.3, max: 2.0),
              y <- float(min: 0.3, max: 2.0),
              z <- float(min: 0.3, max: 2.0),
              max_runs: 8 do
      m = Cast.mesh(Cast.solid([box({0.0, 0.0, 0.0}, {x, y, z})], 0.1), :concrete)
      {lo, hi} = Mesh.bounds(m)
      for {a, b} <- Enum.zip(Tuple.to_list(World.Vec.sub(hi, lo)), [x, y, z]), do: assert_in_delta(a, b, 0.02)
    end
  end

  property "the pours of a cast in any order, and the slabs of its mesh, give the cast of one pour" do
    check all boxes <-
                list_of(
                  tuple(
                    {float(min: -1.0, max: 1.0), float(min: -1.0, max: 1.0), float(min: 0.0, max: 1.0),
                     float(min: 0.2, max: 0.8)}
                  ),
                  min_length: 1,
                  max_length: 3
                ),
              n <- integer(1..5),
              seed <- integer(1..1_000),
              max_runs: 6 do
      shapes = for {x, y, z, w} <- boxes, do: box({x, y, z}, {x + w, y + w, z + w})
      whole = Cast.solid(shapes, 0.1)

      s = Cast.survey(shapes, 0.1)
      :rand.seed(:exsss, {seed, 1, 2})
      bands = s |> Cast.bands(n) |> Enum.shuffle()
      marks = bands |> Enum.map(&Cast.marks(s, &1)) |> Enum.reduce(&MapSet.union/2)
      outside = Cast.outside(s, marks)
      d = bands |> Enum.map(&Cast.distances(s, marks, outside, &1)) |> Enum.shuffle() |> Cast.merge()
      assert Cast.field(s, marks, outside, d) == whole

      grid = Cast.surface(whole)
      pieces = for slab <- Cast.slabs(grid, n), do: Cast.quads(grid, slab)
      assert Cast.join(grid, pieces, :concrete) == Cast.mesh(whole, :concrete)
    end
  end
end
