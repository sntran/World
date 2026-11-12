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
  # The bricks of a region of the collapse, on each axis.
  @region 4
  # The least faces of a region, on the mean, for a collapse by regions.
  @least 500

  # A key of a point: its cell (18 bits for each axis, from -2^17) and its
  # part (3 bits), in one small integer.
  @bits 18
  @half 1 <<< (@bits - 1)
  @mask (1 <<< @bits) - 1

  @doc """
  The piece of the surface of a brick (`World.Sculpt.bricks/3`), as
  binaries that go from one process to another with no copy:
  `%{at: brick, points: binary, quads: binary, materials: list}`. Each
  point is its key (`key/2`, 64 bits) and its place (three floats of 64
  bits); each quad is the indices of its four points in the piece (in
  turn round its edge, the outside to the right hand; 32 bits each) and
  the index of its material in `materials` (8 bits). `decode/1` gives
  the quads and the points as terms.
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
    cuts = cuts(cells, base, step, field(brick, edits, limit, step), v)

    quads =
      for {start, axis, v0, v1} <- crossed do
        inside = if v0 < 0, do: start, else: Vec.add(start, unit(axis))
        keys = for c <- around(axis, start), do: {Vec.add(base, c), part(c, inside, v)}
        {_cut, _normal, material} = cuts[{start, axis}]
        {if(v1 > v0, do: keys, else: Enum.reverse(keys)), material}
      end

    keys = quads |> Enum.flat_map(&elem(&1, 0)) |> Enum.uniq()
    index = keys |> Enum.with_index() |> Map.new()
    materials = quads |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    mindex = materials |> Enum.with_index() |> Map.new()

    points =
      for {cell, part} = k <- keys, into: <<>> do
        {x, y, z} = point(k, base, step, cuts, v)
        <<key(cell, part)::64, x::float-64, y::float-64, z::float-64>>
      end

    quads =
      for {ks, m} <- quads, into: <<>> do
        [a, b, c, d] = Enum.map(ks, &index[&1])
        <<a::32, b::32, c::32, d::32, mindex[m]::8>>
      end

    %{at: {bi, bj, bk}, points: points, quads: quads, materials: materials}
  end

  @doc "The key of a point: its cell `{i, j, k}` and its part (0 to 7), in one integer."
  def key({i, j, k}, part) do
    for c <- [i, j, k],
        c + @half < 0 or c + @half > @mask,
        do: raise(ArgumentError, "a cell is too far from the origin")

    (i + @half) <<< (2 * @bits + 3) ||| (j + @half) <<< (@bits + 3) ||| (k + @half) <<< 3 ||| part
  end

  # The cell of a key.
  defp cell(key) do
    {(key >>> (2 * @bits + 3) &&& @mask) - @half, (key >>> (@bits + 3) &&& @mask) - @half,
     (key >>> 3 &&& @mask) - @half}
  end

  @doc """
  The quads and the points of a piece as terms: `%{quads: [{keys,
  material}], points: %{key => {x, y, z}}}`.
  """
  def decode(%{points: points, quads: quads, materials: materials}) do
    keys = for <<k::64, _::binary-size(24) <- points>>, do: k
    t = List.to_tuple(keys)
    m = List.to_tuple(materials)

    %{
      points: Map.new(for(<<k::64, x::float-64, y::float-64, z::float-64 <- points>>, do: {k, {x, y, z}})),
      quads:
        for(<<a::32, b::32, c::32, d::32, i::8 <- quads>>,
          do: {[elem(t, a), elem(t, b), elem(t, c), elem(t, d)], elem(m, i)}
        )
    }
  end

  @doc """
  The meshes of the pieces of a sculpture: one `World.Mesh` for each
  material, with its quads in two triangles. With the option `small`
  (m), no piece of the surface less than `small` across (a part thinner
  than the cells leaves such pieces); with the option `budget` (faces),
  fewer faces for all the materials together, with their shape
  (`World.Simplify.collapse/4`): first each region of 4 × 4 × 4 bricks
  in a process of its own, then the band of faces at the borders of the
  regions.
  """
  def meshes(pieces, opts \\ []) do
    budget = opts[:budget]
    groups = Enum.group_by(pieces, &region(&1.at))
    faces = fn ps -> ps |> Enum.map(&div(byte_size(&1.quads), 17)) |> Enum.sum() |> Kernel.*(2) end
    total = faces.(pieces)

    {pts, tris} =
      if budget && total > budget && map_size(groups) > 1 && total / map_size(groups) >= @least do
        groups
        |> Enum.sort()
        |> Task.async_stream(
          fn {r, ps} -> region_collapse(r, ps, max(round(1.1 * budget * faces.(ps) / total), div(faces.(ps), 4))) end,
          max_concurrency: System.schedulers_online(),
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, part} -> part end)
        |> join()
        |> last_pass(budget)
      else
        {_keys, pts, tris} = triangles(pieces)
        if budget, do: World.Simplify.collapse(pts, tris, budget), else: {pts, tris}
      end

    tris = if opts[:small], do: drop_small(List.to_tuple(pts), tris, opts[:small]), else: tris
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

  # The triangles of some pieces, on their points (one point for each key):
  # `{keys, points, triangles}`.
  defp triangles(pieces) do
    decoded = Enum.map(pieces, &decode/1)
    points = Enum.reduce(decoded, %{}, &Map.merge(&2, &1.points))
    quads = Enum.flat_map(decoded, & &1.quads)
    keys = quads |> Enum.flat_map(&elem(&1, 0)) |> Enum.uniq()
    ids = keys |> Enum.with_index() |> Map.new()
    tris = for {q, m} <- quads, [a, b, c, d] = Enum.map(q, &ids[&1]), f <- [[a, b, c], [a, c, d]], do: {f, m}
    {keys, Enum.map(keys, &points[&1]), tris}
  end

  # Fewer faces, in two passes: each region of bricks (4 on each axis) in
  # a process of its own, with its own pieces, to 1.1 times its share of
  # the budget or to a quarter of its faces (the more of the two: the
  # points at its borders, which the next regions share, stay where they
  # are, and must not take its budget); then the band of faces near the
  # borders of the regions to the budget, with the quadrics of the first
  # pass. With fewer than 500 faces for each region, one pass. A region
  # gives back only its fewer faces, and the last pass has only the band,
  # so no process has the whole mesh in a collapse.
  defp region_collapse(r, pieces, budget) do
    {keys, pts, tris} = triangles(pieces)
    {lo, hi} = cells(r)
    fixed = for {k, i} <- Enum.with_index(keys), border?(cell(k), lo, hi), do: i
    r = World.Simplify.collapse(pts, tris, budget, fixed: fixed)
    global = List.to_tuple(keys)
    {r.points, r.faces, Enum.map(r.ids, &elem(global, &1)), r.quadrics}
  end

  # A cell at a border of its region, or out of it: the next region can
  # have its point too.
  defp border?({i, j, k}, {li, lj, lk}, {hi, hj, hk}),
    do: i <= li or j <= lj or k <= lk or i >= hi or j >= hj or k >= hk

  # The regions together: a shared point (the same key) is one point,
  # with the sum of its quadrics in each region. Also the indices of the
  # shared points.
  defp join(parts) do
    {index, points, quadrics, shared} =
      for {pts, _, ids, qs} <- parts, {p, g, q} <- Enum.zip([pts, ids, qs]), reduce: {%{}, [], %{}, []} do
        {index, points, quadrics, shared} ->
          if Map.has_key?(index, g),
            do: {index, points, Map.update!(quadrics, g, &World.Simplify.add(&1, q)), [index[g] | shared]},
            else: {Map.put(index, g, map_size(index)), [p | points], Map.put(quadrics, g, q), shared}
      end

    faces =
      for {_, fs, ids, _} <- parts, ids = List.to_tuple(ids), {f, m} <- fs, do: {Enum.map(f, &index[elem(ids, &1)]), m}

    order = index |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&quadrics[elem(&1, 0)])
    {Enum.reverse(points), faces, order, MapSet.new(shared)}
  end

  # The last pass: only the faces near the borders of the regions (two
  # rings of faces round the shared points), with the points that they
  # share with the other faces where they are; the other faces are done.
  # When the band cannot reach the budget, the whole mesh.
  defp last_pass({pts, tris, quadrics, shared}, budget) do
    ring = fn set -> for {f, _} <- tris, Enum.any?(f, &MapSet.member?(set, &1)), v <- f, into: MapSet.new(), do: v end
    near = ring.(shared)
    {band, rest} = Enum.split_with(tris, fn {f, _} -> Enum.any?(f, &MapSet.member?(near, &1)) end)
    target = length(band) - (length(tris) - budget)
    outside = for {f, _} <- rest, v <- f, into: MapSet.new(), do: v

    with true <- target > 0,
         {used, r} = band_collapse(pts, quadrics, band, outside, target),
         true <- length(r.faces) <= target do
      join_band(pts, rest, used, r)
    else
      _ ->
        %{points: pts, faces: tris} = World.Simplify.collapse(pts, tris, budget, quadrics: quadrics)
        {pts, tris}
    end
  end

  # The band on its own points: the points that the other faces use stay.
  defp band_collapse(pts, quadrics, band, outside, target) do
    used = band |> Enum.flat_map(&elem(&1, 0)) |> Enum.uniq()
    local = used |> Enum.with_index() |> Map.new()
    {all, qs} = {List.to_tuple(pts), List.to_tuple(quadrics)}
    fixed = for v <- used, MapSet.member?(outside, v), do: local[v]
    faces = Enum.map(band, fn {f, m} -> {Enum.map(f, &local[&1]), m} end)

    {used,
     World.Simplify.collapse(Enum.map(used, &elem(all, &1)), faces, target,
       fixed: fixed,
       quadrics: Enum.map(used, &elem(qs, &1))
     )}
  end

  # The faces of the band after its collapse, with the other faces: the
  # points of the band that stay keep their index, and its moved points
  # take their new places.
  defp join_band(pts, rest, used, r) do
    used = List.to_tuple(used)
    global = Enum.map(r.ids, &elem(used, &1))
    moved = Map.new(Enum.zip(global, r.points))
    pts = pts |> Enum.with_index() |> Enum.map(fn {p, i} -> Map.get(moved, i, p) end)
    g = List.to_tuple(global)
    {pts, rest ++ Enum.map(r.faces, fn {f, m} -> {Enum.map(f, &elem(g, &1)), m} end)}
  end

  # The region of a brick, and the first and the last cells of a region.
  defp region({i, j, k}),
    do: {Integer.floor_div(i, @region), Integer.floor_div(j, @region), Integer.floor_div(k, @region)}

  defp cells({i, j, k}) do
    n = Sculpt.cells() * @region
    {{i * n, j * n, k * n}, {(i + 1) * n - 1, (j + 1) * n - 1, (k + 1) * n - 1}}
  end

  # The field of the edits of a brick at a point: with the short list of
  # the eighth of the brick that the point is in (the same values).
  defp field(%{eighths: eighths, at: at}, edits, limit, step) do
    corner = Sculpt.corner(at, step)

    fn p ->
      list =
        case Sculpt.eighth(Vec.scale(Vec.sub(p, corner), 1 / step)) do
          nil -> edits
          e -> elem(eighths, e)
        end

      SDF.field(list, p, limit)
    end
  end

  defp field(_brick, edits, limit, _step), do: &SDF.field(edits, &1, limit)

  # The faces of each piece of the surface (faces joined by their points)
  # whose box is at least `small` m across: a smaller piece is the noise of
  # a part thinner than the cells.
  defp drop_small(pts, tris, small) do
    near =
      Enum.reduce(tris, %{}, fn {[a, b, c], _}, acc -> acc |> link(a, [b, c]) |> link(b, [a, c]) |> link(c, [a, b]) end)

    {keep, _} =
      Enum.reduce(Map.keys(near), {MapSet.new(), MapSet.new()}, fn v, {keep, seen} ->
        if MapSet.member?(seen, v) do
          {keep, seen}
        else
          piece = flood(near, [v], MapSet.new([v]))
          {{x0, y0, z0}, {x1, y1, z1}} = piece |> Enum.map(&elem(pts, &1)) |> Vec.bounds()
          big = Vec.len({x1 - x0, y1 - y0, z1 - z0}) >= small
          {if(big, do: MapSet.union(keep, piece), else: keep), MapSet.union(seen, piece)}
        end
      end)

    Enum.filter(tris, fn {[a, _, _], _} -> MapSet.member?(keep, a) end)
  end

  defp link(acc, v, us), do: Map.update(acc, v, us, &(us ++ &1))

  defp flood(_near, [], seen), do: seen

  defp flood(near, [v | rest], seen) do
    next = for u <- near[v], not MapSet.member?(seen, u), uniq: true, do: u
    flood(near, next ++ rest, Enum.reduce(next, seen, &MapSet.put(&2, &1)))
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
