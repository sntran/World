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
  center of each cell. It is the steps of a cast in one: `survey/2`, the
  `marks/2` and the `distances/4` of all the triangles, `outside/2` and
  `field/4`. People can do the marks and the distances of the bands of
  `bands/2` at the same time, in any order: `merge/1` gives one result.
  """
  def solid(surfaces, step) do
    s = survey(surfaces, step)
    all = Enum.to_list(0..(tuple_size(s.tris) - 1)//1)
    marks = marks(s, all)
    outside = outside(s, marks)
    field(s, marks, outside, distances(s, marks, outside, all))
  end

  @doc """
  The survey of a cast: its triangles (a tuple of `{a, b, c}`), the
  corner `lo` of the grid, its `step` and its `dims`, with three cells of
  room round the solid (its marks go one cell out), so that the fill
  goes all round it.
  """
  def survey(surfaces, step) do
    tris = Enum.flat_map(surfaces, &triangles/1)
    {lo, hi} = tris |> Enum.flat_map(&Tuple.to_list/1) |> Vec.bounds()
    lo = Vec.sub(lo, {3 * step, 3 * step, 3 * step})
    {sx, sy, sz} = Vec.sub(hi, lo)

    %{
      tris: List.to_tuple(tris),
      lo: lo,
      step: step,
      dims: {ceil(sx / step) + 4, ceil(sy / step) + 4, ceil(sz / step) + 4}
    }
  end

  @doc """
  The bands of a cast from the feet up: the indices of its triangles in
  `n` groups by the height of their centers, as the pours of a real cast,
  each with about the same work (the samples of its triangles: a long
  triangle has more of them).
  """
  def bands(%{tris: tris, step: step}, n) do
    sorted =
      tris
      |> Tuple.to_list()
      |> Enum.with_index()
      |> Enum.sort_by(fn {{{_, _, a}, {_, _, b}, {_, _, c}}, i} -> {a + b + c, i} end)
      |> Enum.map(fn {t, i} -> {i, work(t, step)} end)

    total = sorted |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    share = max(total / n, 1)

    sorted
    |> Enum.chunk_while(
      {[], 0},
      fn {i, w}, {band, sum} ->
        if sum + w > share and band != [],
          do: {:cont, Enum.reverse(band), {[i], w}},
          else: {:cont, {[i | band], sum + w}}
      end,
      fn {band, _} -> {:cont, Enum.reverse(band), nil} end
    )
    |> Enum.reject(&(&1 == []))
  end

  # The samples of a triangle each `step` m: its work in a pour.
  defp work({a, b, c}, step) do
    m = max(1, ceil(Enum.max([Vec.len(Vec.sub(b, a)), Vec.len(Vec.sub(c, a)), Vec.len(Vec.sub(c, b))]) / step))
    div((m + 1) * (m + 2), 2)
  end

  @doc """
  The marks of the triangles `indices` of a survey: the cells round each
  sample of each triangle (a sample each half cell), so that the marks
  have no hole for the fill. A set of the indices of the cells; the marks
  of the bands merge as a union.
  """
  def marks(s, indices) do
    for i <- indices,
        {p, _, _} <- samples(elem(s.tris, i), s.step / 2),
        x <- eight(s, p),
        into: MapSet.new(),
        do: index(s, x)
  end

  @doc """
  The cells outside the cast: a fill from the corner of the grid through
  the cells with no mark (6 neighbors). A binary of a byte for each cell
  (1 outside).
  """
  def outside(%{dims: {nx, ny, nz}} = s, marks) do
    m = :atomics.new(nx * ny * nz, [])
    for x <- marks, do: :atomics.put(m, x, 1)
    out = fill(m, s.dims)
    for x <- 1..(nx * ny * nz), into: <<>>, do: <<:atomics.get(out, x)>>
  end

  @doc """
  The distances of the triangles `indices` near the outer surface: only
  the samples (one a cell) whose point out along the normal is outside
  give one. For each marked cell round a sample: the distance to the
  plane of the triangle when its foot falls in it (with its sign), else
  the distance to the sample and the normal of the sample, weighted by
  the distance, for the side. Each record has a key (the distance in
  micrometers, the index of the triangle, the index of the sample), and
  the least key wins: the result does not depend on the order of the
  triangles or of the bands (`merge/1`).
  """
  def distances(s, marks, outside, indices) do
    step = s.step
    out? = fn x -> :binary.at(outside, x - 1) == 1 end

    Enum.reduce(indices, %{near: %{}, loose: %{}, normals: %{}}, fn i, acc ->
      {a, b, c} = elem(s.tris, i)
      inside = within(a, b, c)

      for {p, n, k} <- samples({a, b, c}, step),
          Enum.any?([1.5, 2.5], fn t -> out?.(index(s, cell(s, Vec.add(p, Vec.scale(n, t * step))))) end),
          x <- block(s, p),
          ix = index(s, x),
          MapSet.member?(marks, ix),
          reduce: acc do
        acc ->
          c = center(s.lo, step, x)
          d = Vec.sub(c, p)
          side = Vec.dot(d, n)

          if inside.(Vec.sub(c, Vec.scale(n, side))) do
            least(acc, :near, ix, {round(abs(side) * 1.0e6), i, k}, round(side * 1.0e6))
          else
            w = 1.0 / (Vec.dot(d, d) + 0.01 * step * step)
            {wx, wy, wz} = Vec.scale(n, w * step * step * 1.0e3)
            sum = {round(wx), round(wy), round(wz)}
            acc = least(acc, :loose, ix, {round(Vec.len(d) * 1.0e6), i, k}, p)
            %{acc | normals: Map.update(acc.normals, ix, sum, &add(&1, sum))}
          end
      end
    end)
  end

  defp least(acc, kind, ix, key, value) do
    Map.update!(acc, kind, fn m ->
      Map.update(m, ix, {key, value}, fn {old, _} = was -> if key < old, do: {key, value}, else: was end)
    end)
  end

  defp add({a, b, c}, {d, e, f}), do: {a + d, b + e, c + f}

  @doc "The distances of the bands of a cast as one: the least key of each cell, the sums of the normals."
  def merge(parts) do
    pick = fn _ix, {k1, _} = a, {k2, _} = b -> if k1 <= k2, do: a, else: b end

    Enum.reduce(parts, %{near: %{}, loose: %{}, normals: %{}}, fn d, acc ->
      %{
        near: Map.merge(acc.near, d.near, pick),
        loose: Map.merge(acc.loose, d.loose, pick),
        normals: Map.merge(acc.normals, d.normals, fn _, x, y -> add(x, y) end)
      }
    end)
  end

  @doc """
  The grid of a cast from its marks, its outside and its distances. The
  band: each marked cell next to the outside, or next to one that is; the
  surface goes through it. Deeper cells are in the solid.
  """
  def field(%{dims: {nx, ny, nz} = dims, step: step, lo: lo}, marks, outside, d) do
    size = nx * ny * nz
    m = :atomics.new(size, [])
    for x <- marks, do: :atomics.put(m, x, 1)
    out? = fn x -> :binary.at(outside, x - 1) == 1 end
    band1 = band(m, dims, out?)
    band2 = band(m, dims, fn x -> out?.(x) or :atomics.get(band1, x) == 1 end)
    far = 1.5 * step

    field =
      for x <- 1..size do
        v =
          case {d.near[x], d.loose[x]} do
            {{_, plane}, _} ->
              plane / 1.0e6

            {nil, {{um, _, _}, p}} ->
              side = Vec.dot(Vec.sub(center(lo, step, cell_of(x - 1, dims)), p), d.normals[x])
              um / 1.0e6 * sign(side)

            _ ->
              nil
          end

        cond do
          out?.(x) -> if v, do: abs(v), else: far
          :atomics.get(band2, x) == 1 and v != nil -> v
          :atomics.get(band1, x) == 1 -> 0.5 * step
          true -> if v, do: -abs(v), else: -far
        end
      end
      |> List.to_tuple()

    field = alone(field, dims, step)
    %__MODULE__{lo: lo, step: step, dims: dims, cells: signs(field), field: field}
  end

  # The samples of a triangle each `gap` m over it: their point, the
  # normal of the triangle and their index; none for a triangle with no
  # area.
  defp samples({a, b, c}, gap) do
    case normal(a, b, c) do
      nil ->
        []

      n ->
        longest = Enum.max([Vec.len(Vec.sub(b, a)), Vec.len(Vec.sub(c, a)), Vec.len(Vec.sub(c, b))])
        m = max(1, ceil(longest / gap))

        for {{u, v}, k} <- Enum.with_index(for u <- 0..m, v <- 0..(m - u), do: {u, v}) do
          {a |> Vec.add(Vec.scale(Vec.sub(b, a), u / m)) |> Vec.add(Vec.scale(Vec.sub(c, a), v / m)), n, k}
        end
    end
  end

  defp index(%{dims: {_, ny, nz}}, {i, j, k}), do: (i * ny + j) * nz + k + 1

  defp cell(%{lo: lo, step: step}, p) do
    {x, y, z} = Vec.sub(p, lo)
    {floor(x / step), floor(y / step), floor(z / step)}
  end

  # The eight cells whose centers are round a point: as many on each side.
  defp eight(%{lo: lo, step: step}, p) do
    {x, y, z} = Vec.sub(p, lo)
    {i, j, k} = {floor(x / step - 0.5), floor(y / step - 0.5), floor(z / step - 0.5)}
    for a <- 0..1, b <- 0..1, c <- 0..1, do: {i + a, j + b, k + c}
  end

  # The 27 cells round the nearest center of a point.
  defp block(%{lo: lo, step: step}, p) do
    {x, y, z} = Vec.sub(p, lo)
    {i, j, k} = {round(x / step - 0.5), round(y / step - 0.5), round(z / step - 0.5)}
    for a <- -1..1, b <- -1..1, c <- -1..1, do: {i + a, j + b, k + c}
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
  solid). It is `surface/1`, the `quads/2` of all the grid, and `join/3`:
  people can make the quads of the slabs of `slabs/2` at the same time.
  """
  def mesh(%__MODULE__{dims: {nx, _, _}} = grid, material) do
    grid = surface(grid)
    join(grid, [quads(grid, {0, nx - 2})], material)
  end

  @doc "The grid with no saddle in its field: one sheet of the surface in each cell of 8 values."
  def surface(%__MODULE__{dims: dims, step: s, field: field} = grid), do: %{grid | field: manifold(field, dims, s)}

  @doc "The slabs of a grid along x for `n` people: ranges of the first index of a cell of 8 values."
  def slabs(%__MODULE__{dims: {nx, _, _}}, n) do
    last = nx - 2
    size = max(ceil((last + 1) / n), 1)
    for a <- 0..last//size, do: {a, min(a + size - 1, last)}
  end

  @doc """
  The quads of a slab of a grid after `surface/1`: a quad across each
  edge of the grid of values that the surface cuts (the solid is never at
  the edge of the grid), from the points of the four cells round it, its
  outside to the larger value; and the point of each of its cells: the
  mean of the cuts on the edges of the cell.
  """
  def quads(%__MODULE__{dims: {nx, ny, nz}, step: s, lo: lo, field: field}, {a0, a1}) do
    value = fn i, j, k ->
      if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz, do: 1.5 * s, else: elem(field, (i * ny + j) * nz + k)
    end

    quads =
      for a <- a0..a1//1,
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

    points =
      for {i, j, k} = key <- quads |> Enum.concat() |> Enum.uniq(), into: %{} do
        corners =
          for c <- 0..7, do: {i + Bitwise.band(c, 1), j + Bitwise.band(Bitwise.bsr(c, 1), 1), k + Bitwise.bsr(c, 2)}

        vs = corners |> Enum.map(fn {a, b, c} -> value.(a, b, c) end) |> List.to_tuple()
        cs = List.to_tuple(corners)

        cuts =
          for {c0, c1} <- edges(), v0 = elem(vs, c0), v1 = elem(vs, c1), v0 < 0 != v1 < 0 do
            Vec.lerp(center(lo, s, elem(cs, c0)), center(lo, s, elem(cs, c1)), v0 / (v0 - v1))
          end

        {key, Vec.mean(cuts)}
      end

    {quads, points}
  end

  @doc "The mesh of the quads of the slabs of a grid, in the order of the slabs."
  def join(_grid, pieces, material) do
    quads = Enum.flat_map(pieces, &elem(&1, 0))
    points = Enum.reduce(pieces, %{}, &Map.merge(&2, elem(&1, 1)))
    keys = quads |> Enum.concat() |> Enum.uniq()
    ids = keys |> Enum.with_index() |> Map.new()
    faces = for q <- quads, [a, b, c, d] = Enum.map(q, &ids[&1]), f <- [[a, b, c], [a, c, d]], do: f
    Mesh.new(Enum.map(keys, &points[&1]), faces, material)
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
