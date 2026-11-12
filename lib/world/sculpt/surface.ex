defmodule World.Sculpt.Surface do
  @moduledoc """
  The surface of the bricks of a sculpture
  (`docs/plans/0008-model-from-edits.md`, D7): dual contouring in each
  brick, and one mesh from the pieces of the bricks.

  A quad goes across each edge of the grid that the surface cuts, from
  the points of the four cells round the edge. Each edge belongs to one
  brick: the brick of the point where it starts (each axis of the point
  from 0 to 7 in the brick). The cells round an edge at a face of a brick
  are in its border, and the next brick has the same field there (to the
  bit: `World.SDF.prune/3`), so the points of those cells are the same in
  each brick, and the pieces join with no gap.

  A cell has one point for each part of the surface in it: the inside
  corners of the cell that share an edge or a face of the cell are one
  part (not through the center of the cell). The rule of a face takes its
  four corners only, so the two cells of the face agree, and each edge of
  the mesh is in two faces (or, at a face of a cell whose inside
  corners are on its diagonal, in four: two sheets of the surface touch
  there; the mesh stays closed). The point of a part is at the least squared
  distance to the planes of the cuts of its edges (each plane through the
  cut, with the normal of the field there), with a little pull to the
  mean of the cuts, and stays in its cell: so a sharp edge of hard edits
  stays sharp.

  The material of a quad is the material of the field at the cut of its
  edge. The mesh has a `World.Mesh` for each material.
  """

  import Bitwise
  alias World.{Mesh, SDF, Sculpt, Vec}

  @edges [{0, 1}, {2, 3}, {4, 5}, {6, 7}, {0, 2}, {1, 3}, {4, 6}, {5, 7}, {0, 4}, {1, 5}, {2, 6}, {3, 7}]
  # The pull to the mean of the cuts, for each cut: small, so it moves a
  # point only along the ways that the planes do not hold (along a sharp
  # edge, in a flat face), not off a corner.
  @pull 1.0e-3

  @doc """
  The piece of the surface of a brick (`World.Sculpt.bricks/3`): its quads
  (`{keys, material}`: the keys of the points of the four cells, in turn
  round the edge, the outside to the right hand) and its points (a key of
  a cell and of a part of its surface to the place of its point). A key
  is `{cell, part}`: the index of the cell in the grid, and the least
  corner of the part.
  """
  def piece(%{at: {bi, bj, bk}, edits: edits, limit: limit} = brick, step) do
    n = Sculpt.cells()
    base = {bi * n, bj * n, bk * n}
    v = fn {i, j, k} -> Sculpt.at(brick, {i, j, k}) end

    crossed =
      for i <- 0..(n - 1),
          j <- 0..(n - 1),
          k <- 0..(n - 1),
          axis <- 0..2,
          start = {i, j, k},
          v0 = v.(start),
          v1 = v.(Vec.add(start, unit(axis))),
          v0 < 0 != v1 < 0,
          do: {start, axis, v0, v1}

    # The cells of the quads, and each edge of those cells that the
    # surface cuts: its cut and the normal there, found once.
    cells = for {start, axis, _, _} <- crossed, c <- around(axis, start), uniq: true, do: c
    cuts = cuts(cells, base, step, &SDF.field(edits, &1, limit), v)

    quads =
      for {start, axis, v0, v1} <- crossed do
        inside = if v0 < 0, do: start, else: Vec.add(start, unit(axis))
        keys = for c <- around(axis, start), do: {Vec.add(base, c), part(c, inside, v)}
        {_cut, _normal, material} = cuts[{start, axis}]
        {if(v1 > v0, do: keys, else: Enum.reverse(keys)), material}
      end

    points =
      for key <- quads |> Enum.flat_map(&elem(&1, 0)) |> Enum.uniq(), into: %{} do
        {key, point(key, base, step, cuts, v)}
      end

    %{quads: quads, points: points}
  end

  @doc """
  The meshes of the pieces of a sculpture: one `World.Mesh` for each
  material, with its quads in two triangles. With the option `budget`
  (faces), fewer faces for all the materials together, with their shape
  (`World.Simplify.collapse/3`).
  """
  def meshes(pieces, opts \\ []) do
    points = Enum.reduce(pieces, %{}, &Map.merge(&2, &1.points))
    quads = Enum.flat_map(pieces, & &1.quads)
    keys = quads |> Enum.flat_map(&elem(&1, 0)) |> Enum.uniq()
    ids = keys |> Enum.with_index() |> Map.new()
    tris = for {q, m} <- quads, [a, b, c, d] = Enum.map(q, &ids[&1]), f <- [[a, b, c], [a, c, d]], do: {f, m}
    pts = Enum.map(keys, &points[&1])
    {pts, tris} = if opts[:budget], do: World.Simplify.collapse(pts, tris, opts[:budget]), else: {pts, tris}
    all = List.to_tuple(pts)

    tris
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.sort_by(fn {material, _} -> inspect(material) end)
    |> Enum.map(fn {material, faces} ->
      used = faces |> Enum.concat() |> Enum.uniq()
      local = used |> Enum.with_index() |> Map.new()
      Mesh.new(Enum.map(used, &elem(all, &1)), Enum.map(faces, fn f -> Enum.map(f, &local[&1]) end), material || :paint)
    end)
  end

  # The part of the surface of a cell that the inside corner `inside` is
  # in: its least corner.
  defp part(cell, inside, v) do
    solid = for c <- 0..7, v.(Vec.add(cell, corner(c))) < 0, do: c
    corner = index(Vec.sub(inside, cell))
    Enum.min(component(solid, [corner], [corner]))
  end

  # The inside corners joined to some corners: by an edge or a face of the
  # cell (one bit or two bits apart), not by its center.
  defp component(_solid, [], seen), do: seen

  defp component(solid, [c | rest], seen) do
    next = for d <- solid, d not in seen, popcount(bxor(c, d)) in [1, 2], do: d
    component(solid, rest ++ next, seen ++ next)
  end

  defp popcount(x), do: band(x, 1) + band(bsr(x, 1), 1) + band(bsr(x, 2), 1)

  # The point of a part of a cell: dual contouring of the cuts of its
  # edges, kept in the cell.
  defp point({global, part}, base, step, cuts, v) do
    cell = Vec.sub(global, base)
    solid = for c <- 0..7, v.(Vec.add(cell, corner(c))) < 0, do: c
    mine = component(solid, [part], [part])

    {points, normals} =
      for {c0, c1} <- @edges,
          p0 = Vec.add(cell, corner(c0)),
          v0 = v.(p0),
          v1 = v.(Vec.add(cell, corner(c1))),
          v0 < 0 != v1 < 0,
          if(v0 < 0, do: c0, else: c1) in mine do
        {cut, normal, _} = cuts[{p0, axis(c0, c1)}]
        {cut, normal}
      end
      |> Enum.unzip()

    lo = place(base, cell, step)
    clamp(qef(points, normals, Vec.mean(points)), lo, Vec.add(lo, {step, step, step}))
  end

  # Each edge of the cells that the surface cuts (`{start, axis}`): its
  # cut, the normal of the field there, and the material there.
  defp cuts(cells, base, step, field, v) do
    for cell <- cells,
        {c0, c1} <- @edges,
        p0 = Vec.add(cell, corner(c0)),
        p1 = Vec.add(cell, corner(c1)),
        v0 = v.(p0),
        v1 = v.(p1),
        v0 < 0 != v1 < 0,
        uniq: true do
      {p0, p1, v0, v1}
    end
    |> Map.new(fn {p0, p1, v0, v1} ->
      cut = cut(place(base, p0, step), place(base, p1, step), v0, v1, field, step)
      {_, material} = field.(cut)
      {{p0, axis(p0, p1)}, {cut, gradient(field, cut, step), material}}
    end)
  end

  defp axis({x, _, _}, {x1, _, _}) when x != x1, do: 0
  defp axis({_, y, _}, {_, y1, _}) when y != y1, do: 1
  defp axis({_, _, _}, {_, _, _}), do: 2
  defp axis(c0, c1) when is_integer(c0), do: axis(corner(c0), corner(c1))

  # The cut of an edge of the grid: where the field of the edits is 0 on
  # it, from the values at its ends (regula falsi, the Illinois way, in 8
  # steps or fewer): near a sharp edge the field is not a line along an edge of
  # the grid, so a line between the two values is not the cut.
  defp cut(p0, p1, v0, v1, field, step), do: falsi(p0, p1, field, {0.0, v0}, {1.0, v1}, 8, nil, step * 1.0e-6)

  defp falsi(p0, p1, _field, {a, fa}, {b, fb}, 0, _side, _tol), do: Vec.lerp(p0, p1, a - fa * (b - a) / (fb - fa))

  defp falsi(p0, p1, field, {a, fa}, {b, fb}, n, side, tol) do
    t = a - fa * (b - a) / (fb - fa)
    {ft, _} = field.(Vec.lerp(p0, p1, t))

    cond do
      abs(ft) <= tol -> Vec.lerp(p0, p1, t)
      ft < 0 == fa < 0 -> falsi(p0, p1, field, {t, ft}, {b, if(side == :a, do: fb / 2, else: fb)}, n - 1, :a, tol)
      true -> falsi(p0, p1, field, {a, if(side == :b, do: fa / 2, else: fa)}, {t, ft}, n - 1, :b, tol)
    end
  end

  # The least squares of the planes of the cuts, with a pull to the mean:
  # (sum n n^T + w I) x = sum n (n . p) + w m.
  defp qef(cuts, normals, mean) do
    w = @pull * length(cuts)

    {a, b} =
      Enum.zip(cuts, normals)
      |> Enum.reduce({{w, 0.0, 0.0, w, 0.0, w}, Vec.scale(mean, w)}, fn {p, {x, y, z} = n},
                                                                        {{xx, xy, xz, yy, yz, zz}, b} ->
        d = Vec.dot(n, p)
        {{xx + x * x, xy + x * y, xz + x * z, yy + y * y, yz + y * z, zz + z * z}, Vec.add(b, Vec.scale(n, d))}
      end)

    solve(a, b)
  end

  # The solution of a symmetric 3 × 3 system (with the pull, it has one).
  defp solve({a, b, c, d, e, f}, {p, q, r}) do
    det = a * (d * f - e * e) - b * (b * f - c * e) + c * (b * e - c * d)

    {(p * (d * f - e * e) - b * (q * f - e * r) + c * (q * e - d * r)) / det,
     (a * (q * f - e * r) - p * (b * f - c * e) + c * (b * r - q * c)) / det,
     (a * (d * r - q * e) - b * (b * r - q * c) + p * (b * e - c * d)) / det}
  end

  defp clamp({x, y, z}, {a, b, c}, {d, e, f}), do: {min(max(x, a), d), min(max(y, b), e), min(max(z, c), f)}

  # The normal of the field at a point (central differences of the field
  # of the edits).
  defp gradient(field, {x, y, z}, step) do
    h = step * 1.0e-3
    f = &elem(field.(&1), 0)

    Vec.norm(
      {f.({x + h, y, z}) - f.({x - h, y, z}), f.({x, y + h, z}) - f.({x, y - h, z}),
       f.({x, y, z + h}) - f.({x, y, z - h})}
    )
  end

  defp place(base, p, step), do: Vec.scale(Vec.add(base, p), step) |> Vec.float()
  defp corner(c), do: {band(c, 1), band(bsr(c, 1), 1), bsr(c, 2)}
  defp index({x, y, z}), do: x + 2 * y + 4 * z

  defp unit(0), do: {1, 0, 0}
  defp unit(1), do: {0, 1, 0}
  defp unit(2), do: {0, 0, 1}

  # The four cells round the edge from the point {a, b, c} along an axis,
  # in turn about the axis (the right hand).
  defp around(0, {a, b, c}), do: [{a, b - 1, c - 1}, {a, b, c - 1}, {a, b, c}, {a, b - 1, c}]
  defp around(1, {a, b, c}), do: [{a - 1, b, c - 1}, {a - 1, b, c}, {a, b, c}, {a, b, c - 1}]
  defp around(2, {a, b, c}), do: [{a - 1, b - 1, c}, {a, b - 1, c}, {a, b, c}, {a - 1, b, c}]
end
