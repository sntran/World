defmodule World.Cast do
  @moduledoc """
  A solid cast from surfaces: the body and the clothes of a figure (or
  any shapes) become one closed shell with no gaps, as a statue of
  concrete or stone is one piece (Vũng Tàu, W13).

  The cast is on a grid of cells of `step` m. Each triangle of the
  surfaces marks the cells that it goes through (and their neighbors),
  and gives each cell near it the distance to its plane, with the sign of
  its normal (less than 0 under the surface). The outside is each cell
  that a fill from the edges of the grid reaches through the cells with
  no mark; the rest is the solid, so a body in a robe is full, with no
  gap between them. The field of the grid is the signed distance near
  the outer surface (each cell of the outside has a distance of at least
  0, each cell deep in the solid less than 0), and its surface comes by
  surface nets: one point in each cell of 8 values that the surface goes
  through, a quad across each edge of the grid that it cuts. A thin part
  (a hand) stays when it is thicker than one cell.

  A hollow cast (`hollow/3`) keeps a wall of a given thickness and
  empties the rest; openings (boxes) go through the wall.
  """
  alias World.{Mesh, Vec}

  defstruct [:lo, :step, :dims, :cells, :field]

  @doc """
  The cast of `surfaces` (a list of `{points, triangles}`, each triangle
  a list of three indices, or `World.Mesh` structs, their faces to the
  outside) on a grid of `step` m. Gives the grid: `cells` is a tuple of
  0 (outside) and 1 (solid), `field` the signed distance (m) at the
  center of each cell.
  """
  def solid(surfaces, step) do
    tris = Enum.flat_map(surfaces, &triangles/1)
    {lo, hi} = tris |> Enum.flat_map(&Tuple.to_list/1) |> Vec.bounds()
    # Three cells of room round the solid (its marks go one cell out), so
    # the fill goes all round it.
    lo = Vec.sub(lo, {3 * step, 3 * step, 3 * step})
    {sx, sy, sz} = Vec.sub(hi, lo)
    dims = {ceil(sx / step) + 4, ceil(sy / step) + 4, ceil(sz / step) + 4}
    {nx, ny, nz} = dims
    size = nx * ny * nz
    marks = :atomics.new(size, [])
    # For each cell: the distance to the plane of the nearest triangle
    # that its foot falls in (true, with its sign), and else the distance
    # to the nearest sample with the vote of the samples near it for its
    # side (out of the edge or the corner of a face); in micrometers.
    near = :atomics.new(size, [])
    plane = :atomics.new(size, [])
    loose = :atomics.new(size, [])
    # The sum of the normals of the samples near a loose cell, and its
    # nearest sample (micrometers): their pseudo-normal gives the side.
    normals = :atomics.new(3 * size, [])
    nearest = :atomics.new(3 * size, [])
    index = fn {i, j, k} -> (i * ny + j) * nz + k + 1 end

    # The samples of each triangle: a point each `gap` m over it, its
    # normal, and a test that a point of its plane is in it.
    samples = fn gap, f ->
      for {a, b, c} <- tris, n = normal(a, b, c), n != nil do
        longest = Enum.max([Vec.len(Vec.sub(b, a)), Vec.len(Vec.sub(c, a)), Vec.len(Vec.sub(c, b))])
        m = max(1, ceil(longest / gap))
        inside = within(a, b, c)

        for u <- 0..m, v <- 0..(m - u) do
          f.(a |> Vec.add(Vec.scale(Vec.sub(b, a), u / m)) |> Vec.add(Vec.scale(Vec.sub(c, a), v / m)), n, inside)
        end
      end
    end

    cell = fn p ->
      {x, y, z} = Vec.sub(p, lo)
      {floor(x / step), floor(y / step), floor(z / step)}
    end

    # The eight cells whose centers are round a point: as many on each side.
    around = fn p ->
      {x, y, z} = Vec.sub(p, lo)
      {i, j, k} = {floor(x / step - 0.5), floor(y / step - 0.5), floor(z / step - 0.5)}
      for a <- 0..1, b <- 0..1, c <- 0..1, do: {i + a, j + b, k + c}
    end

    # The 27 cells round the nearest center of a point.
    block = fn p ->
      {x, y, z} = Vec.sub(p, lo)
      {i, j, k} = {round(x / step - 0.5), round(y / step - 0.5), round(z / step - 0.5)}
      for a <- -1..1, b <- -1..1, c <- -1..1, do: {i + a, j + b, k + c}
    end

    # Each sample marks the cells round it (so the marks have no hole for
    # the fill).
    samples.(step / 2, fn p, _, _ -> for x <- around.(p), do: :atomics.put(marks, index.(x), 1) end)
    outside = fill(marks, dims)
    out? = fn x -> :atomics.get(outside, x) == 1 end

    # The distances come only from the samples of the outer surface: a
    # point out along the normal is outside. The surface of a shape in
    # another (a robe in a sleeve) gives none.
    # (A sample each cell is enough: each marked cell gets the samples of
    # the 27 cells round it.)
    samples.(step, fn p, n, inside ->
      outer? = Enum.any?([1.5, 2.5], fn t -> out?.(index.(cell.(Vec.add(p, Vec.scale(n, t * step))))) end)

      if outer? do
        for x <- block.(p), i = index.(x), :atomics.get(marks, i) == 1 do
          c = center(lo, step, x)
          d = Vec.sub(c, p)
          side = Vec.dot(d, n)
          best = :atomics.get(near, i)

          if (best == 0 or abs(side) * 1.0e6 < best) and inside.(Vec.sub(c, Vec.scale(n, side))) do
            keep(near, plane, i, abs(side), side)
          else
            if keep(loose, nil, i, Vec.len(d), nil), do: put3(nearest, i, p)
            w = 1.0 / (Vec.dot(d, d) + 0.01 * step * step)
            {nx1, ny1, nz1} = Vec.scale(n, w * step * step * 1.0e3)
            for {v, k} <- [{nx1, 0}, {ny1, 1}, {nz1, 2}], do: :atomics.add(normals, 3 * (i - 1) + k + 1, round(v))
          end
        end
      end
    end)

    # The band: each marked cell next to the outside, or next to one that
    # is; the surface goes through it. Deeper cells are in the solid.
    band1 = band(marks, dims, out?)
    band2 = band(marks, dims, fn x -> out?.(x) or :atomics.get(band1, x) == 1 end)
    far = 1.5 * step

    field =
      for x <- 1..size do
        d =
          cond do
            :atomics.get(near, x) > 0 ->
              :atomics.get(plane, x) / 1.0e6

            :atomics.get(loose, x) > 0 ->
              c = center(lo, step, cell_of(x - 1, dims))
              n = for k <- 0..2, do: :atomics.get(normals, 3 * (x - 1) + k + 1)
              side = Vec.dot(Vec.sub(c, get3(nearest, x)), List.to_tuple(n))
              (:atomics.get(loose, x) - 1) / 1.0e6 * sign(side)

            true ->
              nil
          end

        cond do
          out?.(x) -> if d, do: abs(d), else: far
          :atomics.get(band2, x) == 1 and d != nil -> d
          :atomics.get(band1, x) == 1 -> 0.5 * step
          true -> if d, do: -abs(d), else: -far
        end
      end
      |> List.to_tuple()

    field = alone(field, dims, step)
    %__MODULE__{lo: lo, step: step, dims: dims, cells: signs(field), field: field}
  end

  # The field with no solid cell alone (with no solid neighbor): near the
  # corner of a face, one cell can take the wrong side.
  defp alone(field, {nx, ny, nz}, step) do
    value = fn i, j, k ->
      if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz, do: 1.0, else: elem(field, (i * ny + j) * nz + k)
    end

    List.to_tuple(
      for i <- 0..(nx - 1), j <- 0..(ny - 1), k <- 0..(nz - 1) do
        v = value.(i, j, k)
        if v < 0 and Enum.all?(neighbors(i, j, k), fn {a, b, c} -> value.(a, b, c) >= 0 end), do: 0.5 * step, else: v
      end
    )
  end

  # The smallest distance of a cell so far (+1, so 0 is none), and its
  # signed value: true when it is a new smallest.
  defp keep(best, value, i, dist, signed) do
    um = round(dist * 1.0e6) + 1
    old = :atomics.get(best, i)

    if old == 0 or um < old do
      :atomics.put(best, i, um)
      if value, do: :atomics.put(value, i, round(signed * 1.0e6))
      true
    else
      false
    end
  end

  defp put3(a, i, {x, y, z}) do
    for {v, k} <- [{x, 0}, {y, 1}, {z, 2}], do: :atomics.put(a, 3 * (i - 1) + k + 1, round(v * 1.0e6))
  end

  defp get3(a, i), do: List.to_tuple(for(k <- 0..2, do: :atomics.get(a, 3 * (i - 1) + k + 1) / 1.0e6))

  defp cell_of(x, {_, ny, nz}), do: {div(div(x, nz), ny), rem(div(x, nz), ny), rem(x, nz)}

  # A test that a point of the plane of a triangle is in it (to a small
  # part of its size over its edges).
  defp within(a, b, c) do
    {v0, v1} = {Vec.sub(b, a), Vec.sub(c, a)}
    {d00, d01, d11} = {Vec.dot(v0, v0), Vec.dot(v0, v1), Vec.dot(v1, v1)}
    den = d00 * d11 - d01 * d01

    fn p ->
      v2 = Vec.sub(p, a)
      {d20, d21} = {Vec.dot(v2, v0), Vec.dot(v2, v1)}
      v = (d11 * d20 - d01 * d21) / den
      w = (d00 * d21 - d01 * d20) / den
      v >= -1.0e-3 and w >= -1.0e-3 and v + w <= 1.001
    end
  end

  defp sign(v) when v < 0, do: -1
  defp sign(_), do: 1

  defp signs(field), do: field |> Tuple.to_list() |> Enum.map(&if(&1 < 0, do: 1, else: 0)) |> List.to_tuple()

  defp normal(a, b, c) do
    n = Vec.cross(Vec.sub(b, a), Vec.sub(c, a))
    if Vec.len(n) < 1.0e-12, do: nil, else: Vec.norm(n)
  end

  defp center(lo, s, {i, j, k}), do: Vec.add(lo, {(i + 0.5) * s, (j + 0.5) * s, (k + 0.5) * s})

  defp triangles(%Mesh{points: ps, faces: faces}) do
    t = List.to_tuple(ps)
    for [a | rest] <- faces, [b, c] <- Enum.chunk_every(rest, 2, 1, :discard), do: {elem(t, a), elem(t, b), elem(t, c)}
  end

  defp triangles({points, tris}) do
    t = List.to_tuple(points)
    for [a, b, c] <- tris, do: {elem(t, a), elem(t, b), elem(t, c)}
  end

  # The cells that a fill from the corner reaches through the cells with
  # no mark (6 neighbors): 1 in the result.
  defp fill(marks, {nx, ny, nz}) do
    out = :atomics.new(nx * ny * nz, [])
    index = fn i, j, k -> (i * ny + j) * nz + k + 1 end
    :atomics.put(out, index.(0, 0, 0), 1)
    walk(:queue.from_list([{0, 0, 0}]), marks, out, {nx, ny, nz}, index)
    out
  end

  defp walk(queue, marks, out, {nx, ny, nz} = dims, index) do
    case :queue.out(queue) do
      {:empty, _} ->
        :ok

      {{:value, {i, j, k}}, queue} ->
        queue =
          for {a, b, c} <- neighbors(i, j, k),
              a >= 0 and b >= 0 and c >= 0 and a < nx and b < ny and c < nz,
              x = index.(a, b, c),
              :atomics.get(out, x) == 0 and :atomics.get(marks, x) == 0,
              reduce: queue do
            q ->
              :atomics.put(out, x, 1)
              :queue.in({a, b, c}, q)
          end

        walk(queue, marks, out, dims, index)
    end
  end

  # The marked cells with a neighbor (6) that `next?` takes: 1 in the result.
  defp band(marks, {nx, ny, nz}, next?) do
    b = :atomics.new(nx * ny * nz, [])
    index = fn i, j, k -> (i * ny + j) * nz + k + 1 end

    for i <- 0..(nx - 1), j <- 0..(ny - 1), k <- 0..(nz - 1), x = index.(i, j, k), :atomics.get(marks, x) == 1 do
      near? =
        Enum.any?(neighbors(i, j, k), fn {a, c, d} ->
          a >= 0 and c >= 0 and d >= 0 and a < nx and c < ny and d < nz and next?.(index.(a, c, d))
        end)

      if near?, do: :atomics.put(b, x, 1)
    end

    b
  end

  @doc "The value of a cell of the grid (0 outside the grid)."
  def at(%__MODULE__{dims: {nx, ny, nz}, cells: cells}, i, j, k) do
    if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz, do: 0, else: elem(cells, (i * ny + j) * nz + k)
  end

  @doc "The point is in a solid cell of the grid."
  def inside?(%__MODULE__{lo: lo, step: s} = g, p) do
    {x, y, z} = Vec.sub(p, lo)
    at(g, floor(x / s), floor(y / s), floor(z / s)) == 1
  end

  @doc "The cells of the grid with `n` layers of the solid less (each solid cell next to the outside becomes outside)."
  def erode(grid, 0), do: grid

  def erode(%__MODULE__{dims: {nx, ny, nz}} = g, n) do
    cells =
      for i <- 0..(nx - 1), j <- 0..(ny - 1), k <- 0..(nz - 1) do
        if at(g, i, j, k) == 1 and Enum.all?(neighbors(i, j, k), fn {a, b, c} -> at(g, a, b, c) == 1 end),
          do: 1,
          else: 0
      end

    erode(%{g | cells: List.to_tuple(cells)}, n - 1)
  end

  defp neighbors(i, j, k),
    do: [{i + 1, j, k}, {i - 1, j, k}, {i, j + 1, k}, {i, j - 1, k}, {i, j, k + 1}, {i, j, k - 1}]

  @doc """
  The grid hollow: a wall of `wall` m (to the nearest cell) and the rest
  empty, and each opening (`{min, max}` boxes in the axes of the cast)
  empty through the wall. The inner surface is the edge of the eroded
  cells, smoothed once.
  """
  def hollow(%__MODULE__{step: step, dims: dims} = g, wall, openings \\ []) do
    inner = erode(g, max(round(wall / step), 1))

    empty =
      for {v, i} <- Enum.with_index(Tuple.to_list(g.cells)) do
        if elem(inner.cells, i) == 1 or (v == 1 and opening?(g, i, openings)), do: 1.0, else: 0.0
      end
      |> List.to_tuple()
      |> blur(dims, 0)
      |> blur(dims, 1)
      |> blur(dims, 2)

    field =
      for {f, e} <- Enum.zip(Tuple.to_list(g.field), Tuple.to_list(empty)), do: max(f, (e - 0.5) * 2 * step)

    field = List.to_tuple(field)
    %{g | field: field, cells: signs(field)}
  end

  defp opening?(%__MODULE__{dims: {_, ny, nz}, lo: lo, step: s}, i, openings) do
    k = rem(i, nz)
    j = rem(div(i, nz), ny)
    i = div(div(i, nz), ny)
    {x, y, z} = center(lo, s, {i, j, k})

    Enum.any?(openings, fn {{x0, y0, z0}, {x1, y1, z1}} ->
      x >= x0 and x <= x1 and y >= y0 and y <= y1 and z >= z0 and z <= z1
    end)
  end

  @doc "The number of solid cells and their volume (m3)."
  def volume(%__MODULE__{cells: cells, step: s}) do
    n = cells |> Tuple.to_list() |> Enum.sum()
    {n, n * s * s * s}
  end

  @doc """
  The closed surface of the solid of the grid: a `World.Mesh` of the
  role `material` (each face a triangle, its outside away from the
  solid).
  """
  def mesh(%__MODULE__{dims: {nx, ny, nz} = dims, step: s, lo: lo, field: field}, material) do
    field = manifold(field, dims, s)

    value = fn i, j, k ->
      if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz, do: 1.5 * s, else: elem(field, (i * ny + j) * nz + k)
    end

    # A quad across each edge of the grid of values that the surface cuts
    # (the solid is never at the edge of the grid), from the points of the
    # four cells round it; its outside to the larger value.
    quads =
      for a <- 0..(nx - 2),
          b <- 0..(ny - 2),
          c <- 0..(nz - 2),
          axis <- 0..2,
          {da, db, dc} = unit(axis),
          v0 = value.(a, b, c),
          v1 = value.(a + da, b + db, c + dc),
          v0 < 0 != v1 < 0 do
        round = around(axis, {a, b, c})
        if v1 > v0, do: round, else: Enum.reverse(round)
      end

    keys = quads |> Enum.concat() |> Enum.uniq()
    ids = keys |> Enum.with_index() |> Map.new()

    # A point in each cell of 8 values that the surface goes through: the
    # mean of the cuts on its edges.
    points =
      for {i, j, k} <- keys do
        corners =
          for c <- 0..7, do: {i + Bitwise.band(c, 1), j + Bitwise.band(Bitwise.bsr(c, 1), 1), k + Bitwise.bsr(c, 2)}

        vs = corners |> Enum.map(fn {a, b, c} -> value.(a, b, c) end) |> List.to_tuple()
        cs = List.to_tuple(corners)

        cuts =
          for {c0, c1} <- edges(), v0 = elem(vs, c0), v1 = elem(vs, c1), v0 < 0 != v1 < 0 do
            Vec.lerp(center(lo, s, elem(cs, c0)), center(lo, s, elem(cs, c1)), v0 / (v0 - v1))
          end

        Vec.mean(cuts)
      end

    faces = for q <- quads, [a, b, c, d] = Enum.map(q, &ids[&1]), f <- [[a, b, c], [a, c, d]], do: f
    Mesh.new(points, faces, material)
  end

  # The field with no saddle: where two solid values touch only at an
  # edge or at a corner of a cell of 8 values, a value next to them goes
  # just into the solid (it only grows), so that the surface is one sheet
  # in each cell and each edge of the mesh is in two faces.
  defp manifold(field, {nx, ny, nz}, s) do
    sign = :atomics.new(tuple_size(field), [])
    index = fn {i, j, k} -> (i * ny + j) * nz + k + 1 end
    for x <- 0..(tuple_size(field) - 1), elem(field, x) < 0, do: :atomics.put(sign, x + 1, 1)
    blocks = for i <- 0..(nx - 2), j <- 0..(ny - 2), k <- 0..(nz - 2), do: {i, j, k}
    repair(blocks, sign, index, {nx, ny, nz})

    for x <- 0..(tuple_size(field) - 1) do
      v = elem(field, x)
      if v >= 0 and :atomics.get(sign, x + 1) == 1, do: -0.001 * s, else: v
    end
    |> List.to_tuple()
  end

  defp repair([], _, _, _), do: :ok

  defp repair(blocks, sign, index, {nx, ny, nz} = dims) do
    flips =
      for {i, j, k} <- Enum.uniq(blocks),
          corners =
            for(c <- 0..7, do: {i + Bitwise.band(c, 1), j + Bitwise.band(Bitwise.bsr(c, 1), 1), k + Bitwise.bsr(c, 2)}),
          solid = List.to_tuple(Enum.map(corners, &(:atomics.get(sign, index.(&1)) == 1))),
          c = flip(solid),
          c != nil,
          do: Enum.at(corners, c)

    for p <- flips, do: :atomics.put(sign, index.(p), 1)

    for {a, b, c} <- Enum.uniq(flips),
        di <- -1..0,
        dj <- -1..0,
        dk <- -1..0,
        {i, j, k} = {a + di, b + dj, c + dk},
        i >= 0 and j >= 0 and k >= 0 and i <= nx - 2 and j <= ny - 2 and k <= nz - 2 do
      {i, j, k}
    end
    |> repair(sign, index, dims)
  end

  # The corner of a cell of 8 values that goes into the solid, or nil: a
  # face with its solid corners on one diagonal and its empty corners on
  # the other, or a cell with two solid (or two empty) corners at the ends
  # of one diagonal of the cell and the rest the other way.
  defp flip(solid) do
    face =
      Enum.find_value([[0, 2, 6, 4], [1, 3, 7, 5], [0, 1, 5, 4], [2, 3, 7, 6], [0, 1, 3, 2], [4, 5, 7, 6]], fn [
                                                                                                                 a,
                                                                                                                 b,
                                                                                                                 c,
                                                                                                                 d
                                                                                                               ] ->
        if elem(solid, a) == elem(solid, c) and elem(solid, b) == elem(solid, d) and elem(solid, a) != elem(solid, b),
          do: if(elem(solid, a), do: b, else: a)
      end)

    face || corner(solid)
  end

  defp corner(solid) do
    ins = for c <- 0..7, elem(solid, c), do: c
    outs = for c <- 0..7, not elem(solid, c), do: c

    case {ins, outs} do
      {[a, b], _} when Bitwise.bxor(a, b) == 7 -> Bitwise.bxor(a, 1)
      {_, [a, b]} when Bitwise.bxor(a, b) == 7 -> a
      _ -> nil
    end
  end

  defp unit(0), do: {1, 0, 0}
  defp unit(1), do: {0, 1, 0}
  defp unit(2), do: {0, 0, 1}

  # The four cells of 8 values round the edge from the value {a, b, c}
  # along an axis, in turn about the axis (the right hand).
  defp around(0, {a, b, c}), do: [{a, b - 1, c - 1}, {a, b, c - 1}, {a, b, c}, {a, b - 1, c}]
  defp around(1, {a, b, c}), do: [{a - 1, b, c - 1}, {a - 1, b, c}, {a, b, c}, {a, b, c - 1}]
  defp around(2, {a, b, c}), do: [{a - 1, b - 1, c}, {a, b - 1, c}, {a, b, c}, {a - 1, b, c}]

  defp edges do
    [{0, 1}, {2, 3}, {4, 5}, {6, 7}, {0, 2}, {1, 3}, {4, 6}, {5, 7}, {0, 4}, {1, 5}, {2, 6}, {3, 7}]
  end

  # A blur 1-2-1 along an axis.
  defp blur(field, {nx, ny, nz}, axis) do
    get = fn i, j, k ->
      {i, j, k} = {min(max(i, 0), nx - 1), min(max(j, 0), ny - 1), min(max(k, 0), nz - 1)}
      elem(field, (i * ny + j) * nz + k)
    end

    {a, b, c} = unit(axis)

    List.to_tuple(
      for i <- 0..(nx - 1), j <- 0..(ny - 1), k <- 0..(nz - 1) do
        (get.(i - a, j - b, k - c) + 2 * get.(i, j, k) + get.(i + a, j + b, k + c)) / 4
      end
    )
  end
end
