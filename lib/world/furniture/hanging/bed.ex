defmodule World.Furniture.Hanging.Bed do
  @moduledoc """
  The beds of the hammock shop (`World.Furniture.Hanging`): a bed hangs
  between its two ends, and its middle line is a catenary of its length
  over the span between the ends (`catenary/3`), as a cloth or a net
  hangs by its weight.

  The shape of a bed (`surface/4`): a point at `u` along it (0 to 1) and
  `v` across it (-1 to 1). Its width at `u` comes from its `ends`:

  - `:gathered`: the cloth or the net is gathered to a point at each end
    (a võng of the cafés, a camping hammock); the width goes to the
    gathered bunch with `sin(pi u)`;
  - `{:bar, b}`: the end goes on a bar of the length `b` (the bar of
    wood of the net of a võng xếp);
  - `:spread`: a bar as wide as the bed holds each end open (a hammock
    with spreader bars); the bed is flat across.

  Across, the edges of a bed ride over its middle line by `rise` at the
  middle of the bed (a cloth that cups the body).

  - `cloth/3`: the bed as a sheet of cloth (a thin closed mesh);
  - `net/3`: the bed as a net of cords: each cord goes in a zigzag along
    the bed, and its knots are on the knots of the next cord (the meshes
    of a net of diamonds);
  - `area/2`: the area of a bed, for the mass of its cloth.
  """
  alias World.{Detail, Mesh, Shape, Vec}

  @doc """
  The middle line of a bed of `length` over a `span` (m, length > span):
  `n + 1` points `{x, z}` from x = -span/2 to x = span/2, with z = 0 at
  the ends and z < 0 in the middle. The catenary `z = a cosh(x/a) - a
  cosh(span/2a)`, with `a` from `2 a sinh(span/2a) = length`.

      iex> pts = World.Furniture.Hanging.Bed.catenary(2.0, 2.5, 40)
      iex> l = pts |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [{x0, z0}, {x1, z1}] -> :math.sqrt((x1 - x0) ** 2 + (z1 - z0) ** 2) end) |> Enum.sum()
      iex> abs(l - 2.5) < 0.005
      true
  """
  def catenary(span, length, n) when length > span do
    a = solve(span, length)
    top = a * :math.cosh(span / (2 * a))
    for i <- 0..n, x = -span / 2 + span * i / n, do: {x, a * :math.cosh(x / a) - top}
  end

  @doc """
  The middle line of a bed of `length` over a `span` with a person in it:
  the weight of the person on the middle `2 c` of the span (the body on
  the bed), the weight of the bed small next to it. Under the load the
  line is a parabola, and out of it straight to the ends (a line with no
  load between two loads is straight): `n + 1` points `{x, z}` as
  `catenary/3`.

      iex> pts = World.Furniture.Hanging.Bed.loaded(2.0, 2.5, 0.5, 40)
      iex> l = pts |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [{x0, z0}, {x1, z1}] -> :math.sqrt((x1 - x0) ** 2 + (z1 - z0) ** 2) end) |> Enum.sum()
      iex> abs(l - 2.5) < 0.01
      true
  """
  def loaded(span, length, c, n) when length > span and c < span / 2 do
    h = span / 2
    # The length of the line for the curve k (the load over the pull).
    len = fn k ->
      c * :math.sqrt(1 + (k * c) ** 2) + :math.asinh(k * c) / k + 2 * (h - c) * :math.sqrt(1 + (k * c) ** 2)
    end

    k =
      Enum.reduce(1..100, {1.0e-6, 1.0e3}, fn _, {lo, hi} ->
        mid = :math.sqrt(lo * hi)
        if len.(mid) < length, do: {mid, hi}, else: {lo, mid}
      end)
      |> then(fn {lo, hi} -> :math.sqrt(lo * hi) end)

    z0 = -(k * c * c / 2 + k * c * (h - c))
    z = fn x -> if abs(x) <= c, do: z0 + k * x * x / 2, else: z0 + k * c * c / 2 + k * c * (abs(x) - c) end
    for i <- 0..n, x = -h + span * i / n, do: {x, z.(x)}
  end

  @doc """
  The sag of the middle of a bed of `length` over a `span` (m, a positive
  number); with a load on its middle `2 c` (`load`, `loaded/4`), the sag
  with a person in it.
  """
  def sag(span, length, load \\ nil) do
    line = if load, do: loaded(span, length, load, 2), else: catenary(span, length, 2)
    {_, z} = Enum.min_by(line, &elem(&1, 1))
    -z
  end

  # The parameter of the catenary, by halves on a log scale: the length
  # 2 a sinh(span / 2a) gets less as `a` gets more.
  defp solve(span, length) do
    f = fn a -> 2 * a * :math.sinh(span / (2 * a)) - length end

    Enum.reduce(1..100, {:math.log(span / 1000), :math.log(span * 1000)}, fn _, {lo, hi} ->
      mid = (lo + hi) / 2
      if f.(:math.exp(mid)) > 0, do: {mid, hi}, else: {lo, mid}
    end)
    |> then(fn {lo, hi} -> :math.exp((lo + hi) / 2) end)
  end

  @doc """
  A bed between the ends `e1` and `e2` (at one height): a function of
  `{u, v}` to a point. Options: `length` (along its middle line),
  `width` (the cloth or the net flat, across), `ends` (`:gathered`,
  `{:bar, b}` or `:spread`), `load` (with a person in it: the half
  length of the body on the bed, `loaded/4`).

  The bed hangs as a real cloth hangs. Each thread along the bed has the
  full length of the bed: a thread near an edge goes out to the side, so
  it has less slack and sags less than the middle thread. The edges are
  almost taut, and the middle hangs deep. Across, the cloth is as wide as
  it is flat (`width`): at the middle of a bed with gathered ends, the
  edges come in until the curve across has that length. A bed on spreader
  bars is flat across.
  """
  # The points of the middle line, and the threads from the middle to an
  # edge.
  @n 32
  @threads 8

  def surface(e1, e2, opts) do
    span = Vec.len(Vec.sub(e2, e1))
    x = Vec.norm(Vec.sub(e2, e1))
    y = Vec.norm(Vec.cross({0.0, 0.0, 1.0}, x))
    {w, length} = {Keyword.fetch!(opts, :width), Keyword.fetch!(opts, :length)}

    line =
      case Keyword.get(opts, :load) do
        nil -> catenary(span, length, @n)
        c -> loaded(span, length, c, @n)
      end
      |> List.to_tuple()

    sag = -(line |> Tuple.to_list() |> Enum.map(&elem(&1, 1)) |> Enum.min())
    {half, drops} = hang_across(Keyword.get(opts, :ends, :gathered), w, span, length, sag, line)

    # A thread hangs in the shape of the middle line, by its own sag.
    fn {u, v} ->
      {s, z} = at(line, u)
      point = Vec.add(Vec.scale(x, s + span / 2), Vec.scale(y, v * half.(u)))
      e1 |> Vec.add(point) |> Vec.add({0.0, 0.0, z * drop(drops, abs(v)) / sag})
    end
  end

  # The half width at u, and the sag of each thread across (at |v| = k / 8).
  defp hang_across(:spread, w, _, _, sag, _), do: {fn _ -> w / 2 end, List.duplicate(sag, @threads + 1)}

  defp hang_across(ends, w, span, length, sag, line) do
    b = if ends == :gathered, do: 0.02, else: elem(ends, 1)
    shape = for i <- 0..@n, do: :math.pow(:math.sin(:math.pi() * i / @n), 0.75)
    curve = for {_, z} <- Tuple.to_list(line), do: z / -sag
    xs = for i <- 0..@n, do: span * i / @n

    ys = fn h, k -> for p <- shape, do: k / @threads * (b / 2 + (h - b / 2) * p) end
    sags = fn h -> for k <- 0..@threads, do: thread(xs, curve, ys.(h, k), length) end
    across = fn h -> arc(h, sags.(h)) end

    # The half width at the middle: the curve across is as long as the
    # cloth is wide, and an edge is not longer than the bed (a taut edge,
    # with no sag, is the widest).
    taut = bisect(b / 2, w / 2, fn h -> flat(xs, ys.(h, @threads)) < length end)
    h = bisect(b / 2, taut, fn h -> across.(h) < w end)
    {fn u -> b / 2 + (h - b / 2) * :math.pow(:math.sin(:math.pi() * min(max(u, 0.0), 1.0)), 0.75) end, sags.(h)}
  end

  # The sag of a thread of `length` along the path `ys` at the `xs`, in the
  # shape of the middle line (`curve`, 1 at the middle).
  defp thread(xs, curve, ys, length) do
    steps =
      Enum.zip([xs, ys, curve])
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{x0, y0, c0}, {x1, y1, c1}] -> {(x1 - x0) ** 2 + (y1 - y0) ** 2, (c1 - c0) ** 2} end)

    len = fn s -> steps |> Enum.map(fn {flat, dc} -> :math.sqrt(flat + s * s * dc) end) |> Enum.sum() end

    if len.(0.0) >= length, do: 0.0, else: bisect(0.0, length, fn s -> len.(s) < length end)
  end

  # The length of a path `ys` at the `xs` on the level.
  defp flat(xs, ys) do
    Enum.zip(xs, ys)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [{x0, y0}, {x1, y1}] -> :math.sqrt((x1 - x0) ** 2 + (y1 - y0) ** 2) end)
    |> Enum.sum()
  end

  # The length of the curve across at the middle: the threads at their
  # half widths and their sags, both sides.
  defp arc(h, sags) do
    sags
    |> Enum.with_index(fn s, k -> {k / @threads * h, -s} end)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [{y0, z0}, {y1, z1}] -> 2 * :math.sqrt((y1 - y0) ** 2 + (z1 - z0) ** 2) end)
    |> Enum.sum()
  end

  # The point where `below?` changes from true to false, by halves.
  defp bisect(lo, hi, below?) do
    Enum.reduce(1..40, {lo, hi}, fn _, {lo, hi} ->
      mid = (lo + hi) / 2
      if below?.(mid), do: {mid, hi}, else: {lo, mid}
    end)
    |> then(fn {lo, hi} -> (lo + hi) / 2 end)
  end

  # The sag of the thread at |v| (0 to 1), between two of the threads.
  defp drop(drops, v) do
    f = v * @threads
    k = min(floor(f), @threads - 1)
    {a, b} = {Enum.at(drops, k), Enum.at(drops, k + 1)}
    a + (b - a) * (f - k)
  end

  # The point of the middle line at u, between two of its points.
  defp at(line, u) do
    n = tuple_size(line) - 1
    f = min(max(u, 0.0), 1.0) * n
    i = min(floor(f), n - 1)
    {{x0, z0}, {x1, z1}} = {elem(line, i), elem(line, i + 1)}
    t = f - i
    {x0 + (x1 - x0) * t, z0 + (z1 - z0) * t}
  end

  @doc """
  The bed as a sheet of cloth, `t` thick (option, 2 mm): closed meshes
  over `rows` by `cols` points of the surface, one for each band across.
  Options `material` (`:fabric`) and `bands` (the bands across, from one
  edge to the other, as `{share, material}`: the stripes of a canvas, the
  hems of a cloth; one band of `material` by default).
  """
  def cloth(surface, opts) do
    t = Keyword.get(opts, :t, 0.002)
    {rows, cols} = {Detail.sides(Keyword.get(opts, :rows, 32)), Detail.sides(Keyword.get(opts, :cols, 12))}
    bands = Keyword.get(opts, :bands, [{1, Keyword.get(opts, :material, :fabric)}])
    total = bands |> Enum.map(&elem(&1, 0)) |> Enum.sum()

    bands
    |> Enum.map_reduce(0, fn {share, material}, from ->
      {{from / total, (from + share) / total, material}, from + share}
    end)
    |> elem(0)
    |> Enum.map(fn {a, b, material} ->
      n = max(round(cols * (b - a)), 1)

      rings =
        for i <- 0..rows do
          top = for j <- 0..n, do: surface.({i / rows, -1 + 2 * (a + (b - a) * j / n)})
          top ++ Enum.reverse(for p <- top, do: Vec.add(p, {0.0, 0.0, -t}))
        end

      Shape.rings(rings, material)
    end)
  end

  @doc """
  The area of a bed (m2), from a grid of its surface.

      iex> s = World.Furniture.Hanging.Bed.surface({0, 0, 0}, {2.0, 0, 0}, length: 2.0001, width: 1.0, ends: :spread)
      iex> abs(World.Furniture.Hanging.Bed.area(s) - 2.0) < 0.01
      true
  """
  def area(surface, n \\ 24) do
    for i <- 0..(n - 1), j <- 0..(n - 1), reduce: 0.0 do
      sum ->
        [a, b, c, d] =
          for {di, dj} <- [{0, 0}, {1, 0}, {1, 1}, {0, 1}], do: surface.({(i + di) / n, -1 + 2 * (j + dj) / n})

        sum + Vec.len(Vec.cross(Vec.sub(b, a), Vec.sub(d, a))) / 2 +
          Vec.len(Vec.cross(Vec.sub(b, c), Vec.sub(d, c))) / 2
    end
  end

  @doc """
  The bed as a net of cords: `strands` cords along the bed, each in a
  zigzag of `knots` steps between its two lines across; next cords meet
  at their knots, so the meshes are diamonds. A cord of twice the
  diameter along each edge (the edge cord of a net). Options `strands`
  (24), `knots` (30), `d` (the cord, 2.4 mm), `material` (`:fabric`),
  `matter` (`:nylon`). At mid, half the cords; at far, a sheet of cloth.
  """
  def net(surface, opts \\ []) do
    case Detail.level() do
      :far ->
        cloth(surface, Keyword.put(opts, :t, 0.002))

      level ->
        k = if level == :mid, do: 2, else: 1
        strands = max(div(Keyword.get(opts, :strands, 24), k), 2)
        knots = max(div(Keyword.get(opts, :knots, 30), k), 4)
        material = Keyword.get(opts, :material, :fabric)
        r = Keyword.get(opts, :d, 0.0024) / 2

        cord = fn points, r ->
          Shape.sweep(points, r, material, sides: 4) |> Mesh.matter(Keyword.get(opts, :matter, :nylon))
        end

        cords =
          for j <- 0..(strands - 1),
              do: cord.(for(i <- 0..knots, do: surface.({i / knots, -1 + 2 * (j + rem(i + j, 2)) / strands})), r)

        edges = for v <- [-1.0, 1.0], do: cord.(for(i <- 0..knots, do: surface.({i / knots, v})), 2 * r)
        cords ++ edges
    end
  end

  @doc """
  The whipping of a gathered end: a cord wound tight round the bunch of
  the cloth or the net, `len` long from the end `at` to the side `dir`
  (by eye: 6 cm, 2.4 cm across).
  """
  def whipping(at, dir, opts \\ []) do
    {len, r} = {Keyword.get(opts, :len, 0.06), Keyword.get(opts, :r, 0.012)}

    Shape.sweep([at, Vec.add(at, Vec.scale(Vec.norm(dir), len))], r, Keyword.get(opts, :material, :rope), sides: 10)
    |> Mesh.matter(:nylon)
  end
end
