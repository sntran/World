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

  @doc "The sag of the middle of a bed of `length` over a `span` (m, a positive number)."
  def sag(span, length) do
    {_, z} = Enum.min_by(catenary(span, length, 2), &elem(&1, 1))
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
  `width` (at its middle), `ends` (`:gathered`, `{:bar, b}` or
  `:spread`), `rise` (the edges over the middle line at the middle of the
  bed, m).
  """
  def surface(e1, e2, opts) do
    span = Vec.len(Vec.sub(e2, e1))
    x = Vec.norm(Vec.sub(e2, e1))
    y = Vec.norm(Vec.cross({0.0, 0.0, 1.0}, x))
    w = Keyword.fetch!(opts, :width)
    rise = Keyword.get(opts, :rise, 0.0)
    line = catenary(span, Keyword.fetch!(opts, :length), 64) |> List.to_tuple()
    width = width(Keyword.get(opts, :ends, :gathered), w)

    fn {u, v} ->
      {s, z} = at(line, u)
      half = width.(u) / 2
      lift = rise * v * v * (2 * half / w)
      e1 |> Vec.add(Vec.scale(x, s + span / 2)) |> Vec.add(Vec.scale(y, v * half)) |> Vec.add({0.0, 0.0, z + lift})
    end
  end

  defp width(:gathered, w), do: fn u -> max(w * :math.pow(:math.sin(:math.pi() * u), 0.75), 0.02) end
  defp width({:bar, b}, w), do: fn u -> b + (w - b) * :math.pow(:math.sin(:math.pi() * u), 0.75) end
  defp width(:spread, w), do: fn _ -> w end

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
  The bed as a sheet of cloth, `t` thick (option, 2 mm): one closed mesh
  over `rows` by `cols` points of the surface. Option `material`
  (`:fabric`).
  """
  def cloth(surface, opts \\ []) do
    t = Keyword.get(opts, :t, 0.002)
    {rows, cols} = {Detail.sides(Keyword.get(opts, :rows, 32)), Detail.sides(Keyword.get(opts, :cols, 12))}

    rings =
      for i <- 0..rows do
        u = i / rows
        top = for j <- 0..cols, do: surface.({u, -1 + 2 * j / cols})
        top ++ Enum.reverse(for p <- top, do: Vec.add(p, {0.0, 0.0, -t}))
      end

    Shape.rings(rings, Keyword.get(opts, :material, :fabric))
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
  zigzag of `knots` steps between its two lines across, its knots on the
  knots of the next cord. Options `strands` (24), `knots` (30), `d` (the
  cord, 2.4 mm), `material` (`:fabric`). At mid, half the cords; at far,
  a sheet of cloth.
  """
  def net(surface, opts \\ []) do
    case Detail.level() do
      :far ->
        [cloth(surface, Keyword.put(opts, :t, 0.002))]

      level ->
        k = if level == :mid, do: 2, else: 1
        strands = max(div(Keyword.get(opts, :strands, 24), k), 2)
        knots = max(div(Keyword.get(opts, :knots, 30), k), 4)
        material = Keyword.get(opts, :material, :fabric)
        r = Keyword.get(opts, :d, 0.0024) / 2

        for j <- 0..(strands - 1) do
          for(i <- 0..knots, do: surface.({i / knots, -1 + 2 * (j + rem(i, 2)) / strands}))
          |> Shape.sweep(r, material, sides: 4)
          |> Mesh.matter(Keyword.get(opts, :matter, :nylon))
        end
    end
  end
end
