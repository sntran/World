defmodule World.Sheet do
  @moduledoc """
  The sheet metal shop of the world (`docs/world.md`, step P6): a part
  bent from one flat sheet, as a press brake bends it.

  A sheet is a base (`w` by `l`, the outside sizes, in the plane x, y,
  with its outside face at z = 0) and a flange on each edge that has one
  (`:left`, `:right`, `:front`, `:back`: x = 0, x = w, y = 0, y = l),
  bent up by 90 degrees to its outside height `h`. A flange can have a
  return lip at its top, bent in by 90 degrees (`lip`: its outside
  length). Each bend has the inside radius `radius` (the thickness by
  default). Where two flanges meet, the corner is cut away (a corner
  relief). The base can have rectangular holes (`hole/2`).

  The flat pattern (`flat/1`): the base, and each flange with its bend.
  The length of the sheet in a bend is the bend allowance

      BA = angle * (radius + k * t)

  (the angle in radians; the neutral line of the bend is `k * t` from the
  inside face). `k` is 0.44 by default: the common value for the air
  bending of mild steel at an inside radius of about the thickness
  (Durma, "K factor in sheet metal bending").

  `part/4` makes the part: a closed mesh for each flat region and for
  each bend, with the sizes of the flat pattern in its params.
  """
  alias World.{Frame, Mesh, Part, Shape}

  defstruct w: 0.0, l: 0.0, t: 0.0, radius: 0.0, k: 0.44, material: :steel, matter: nil, flanges: %{}, holes: []

  @edges [:left, :right, :front, :back]

  @doc """
  A sheet: a base of `w` by `l` and a thickness `t` (m). The options:
  `radius` (the inside radius of each bend, `t` by default), `k`,
  `material` (the role of its color, `:steel` by default) and `matter`
  (the material of its mass when the role is a color).
  """
  def new(w, l, t, opts \\ []) do
    %__MODULE__{
      w: w / 1,
      l: l / 1,
      t: t / 1,
      radius: Keyword.get(opts, :radius, t) / 1,
      k: Keyword.get(opts, :k, 0.44),
      material: Keyword.get(opts, :material, :steel),
      matter: Keyword.get(opts, :matter)
    }
  end

  @doc """
  A flange on an edge, of the outside height `h`, bent up by 90 degrees.
  The option `lip`: a return lip at its top, of that outside length.
  """
  def flange(%__MODULE__{} = s, edge, h, opts \\ []) when edge in @edges do
    lip = Keyword.get(opts, :lip)
    c = s.radius + s.t

    if h <= 2 * c or (lip != nil and lip <= c),
      do: raise(ArgumentError, "the flange #{edge} is too short for its bends")

    %{s | flanges: Map.put(s.flanges, edge, %{h: h / 1, lip: lip})}
  end

  @doc "A rectangular hole in the base: `{x0, y0, x1, y1}` (m)."
  def hole(%__MODULE__{} = s, {x0, y0, x1, y1}), do: %{s | holes: s.holes ++ [{x0 / 1, y0 / 1, x1 / 1, y1 / 1}]}

  @doc """
  The bend allowance of a bend of 90 degrees (m).

      iex> s = World.Sheet.new(0.1, 0.1, 0.0015)
      iex> Float.round(World.Sheet.allowance(s) * 1000, 3)
      3.393
  """
  def allowance(%__MODULE__{radius: r, k: k, t: t}), do: :math.pi() / 2 * (r + k * t)

  @doc """
  The flat pattern: `%{size: {x, y}, bends: n}`, the box of the pattern
  and its count of bends.

      iex> s = World.Sheet.new(0.3, 0.4, 0.0015) |> World.Sheet.flange(:left, 0.05) |> World.Sheet.flange(:right, 0.05)
      iex> %{size: {x, y}, bends: 2} = World.Sheet.flat(s)
      iex> {Float.round(x * 1000, 2), Float.round(y * 1000, 2)}
      {394.79, 400.0}
  """
  def flat(%__MODULE__{} = s) do
    along = fn a, b, total -> total - setback(s, a) - setback(s, b) + out(s, a) + out(s, b) end
    bends = s.flanges |> Map.values() |> Enum.map(fn f -> if f.lip, do: 2, else: 1 end) |> Enum.sum()
    %{size: {along.(:left, :right, s.w), along.(:front, :back, s.l)}, bends: bends}
  end

  # The part of the base that a bend takes on an edge with a flange.
  defp setback(s, edge), do: if(Map.has_key?(s.flanges, edge), do: s.radius + s.t, else: 0.0)

  # The flat length of a flange and its lip, with their bends.
  defp out(s, edge) do
    case s.flanges[edge] do
      nil -> 0.0
      %{h: h, lip: nil} -> allowance(s) + h - (s.radius + s.t)
      %{h: h, lip: lip} -> 2 * allowance(s) + h - 2 * (s.radius + s.t) + lip - (s.radius + s.t)
    end
  end

  @doc """
  The part of a sheet: its name, its kind, its ports, and the options
  `frame` (the place of the sheet in the axes of the part) and `sources`.
  """
  def part(%__MODULE__{} = s, name, kind, ports, opts \\ []) do
    f = Keyword.get(opts, :frame, Frame.identity())
    %{size: {fx, fy}, bends: n} = flat(s)

    Part.new(name, kind, Enum.map(meshes(s), &Mesh.transform(&1, f)), ports,
      params: %{"flat" => [fx, fy], "bends" => n, "thickness" => s.t, "radius" => s.radius, "k" => s.k},
      sources: Keyword.get(opts, :sources, [])
    )
  end

  # --- The meshes ------------------------------------------------------------------------------

  defp meshes(s) do
    {x0, x1, y0, y1} = {setback(s, :left), s.w - setback(s, :right), setback(s, :front), s.l - setback(s, :back)}

    base =
      for {a0, b0, a1, b1} <- cut({x0, y0, x1, y1}, s.holes), do: Shape.box({a0, b0, 0.0}, {a1, b1, s.t}, s.material)

    (base ++ Enum.flat_map(s.flanges, fn {edge, f} -> flange_meshes(s, edge, f, {x0, x1, y0, y1}) end))
    |> Enum.map(&if(s.matter, do: Mesh.matter(&1, s.matter), else: &1))
  end

  # The rectangles of a face less its holes: a band between each pair of
  # heights of the holes, cut at each hole in it.
  defp cut({x0, y0, x1, y1}, holes) do
    ys =
      ([y0, y1] ++ Enum.flat_map(holes, fn {_, a, _, b} -> [a, b] end))
      |> Enum.filter(&(&1 >= y0 and &1 <= y1))
      |> Enum.uniq()
      |> Enum.sort()

    for [a, b] <- Enum.chunk_every(ys, 2, 1, :discard),
        cuts = for({hx0, hy0, hx1, hy1} <- holes, hy0 < b and hy1 > a, do: {hx0, hx1}) |> Enum.sort(),
        {u0, u1} <- free(x0, x1, cuts),
        do: {u0, a, u1, b}
  end

  defp free(a, b, cuts) do
    {segs, last} = Enum.reduce(cuts, {[], a}, fn {c0, c1}, {acc, at} -> {acc ++ [{at, min(c0, b)}], max(at, c1)} end)
    Enum.filter(segs ++ [{last, b}], fn {u, v} -> v - u > 1.0e-9 end)
  end

  # A flange in the axes of its edge: `a` out from the base (0 at the
  # outside face of the flange), `b` up (0 at the outside face of the
  # base), `e` along the edge. Its bend, its flat, and its lip.
  defp flange_meshes(s, edge, %{h: h, lip: lip}, {x0, x1, y0, y1}) do
    {r, t} = {s.radius, s.t}
    c = r + t
    {origin, n, len} = edge_frame(s, edge, {x0, x1, y0, y1})
    piece = fn loop -> Shape.prism(loop, len, s.material, frame: Frame.new(origin, along(n), {0, 0, 1})) end
    top = if lip, do: h - c, else: h

    bend = piece.(arc({-c, c}, r, c, -90, 0))
    flat = piece.([{-t, c}, {0.0, c}, {0.0, top}, {-t, top}])

    lips =
      if lip,
        do: [piece.(arc({-c, h - c}, r, c, 0, 90)), piece.([{-lip, h - t}, {-c, h - t}, {-c, h}, {-lip, h}])],
        else: []

    [bend, flat | lips]
  end

  # The direction along an edge: n x z, so the axes of a piece are n (out
  # of the edge), z (up) and the edge.
  defp along(n), do: World.Vec.cross(World.Vec.float(n), {0.0, 0.0, 1.0})

  # The origin (at the start of the flange, on the outside of the edge),
  # the normal out of the edge, and the length of the flange.
  defp edge_frame(s, :right, {_, _, y0, y1}), do: {{s.w, y1, 0.0}, {1, 0, 0}, y1 - y0}
  defp edge_frame(_s, :left, {_, _, y0, y1}), do: {{0.0, y0, 0.0}, {-1, 0, 0}, y1 - y0}
  defp edge_frame(s, :back, {x0, x1, _, _}), do: {{x0, s.l, 0.0}, {0, 1, 0}, x1 - x0}
  defp edge_frame(_s, :front, {x0, x1, _, _}), do: {{x1, 0.0, 0.0}, {0, -1, 0}, x1 - x0}

  # The section of a bend: the band between the radii r and r + t around
  # a center, from the angle a0 to a1 (degrees from +a, toward +b).
  defp arc({ca, cb}, r, ro, a0, a1) do
    steps = 6

    at = fn rad, i ->
      ((a0 + (a1 - a0) * i / steps) * :math.pi() / 180) |> then(&{ca + rad * :math.cos(&1), cb + rad * :math.sin(&1)})
    end

    for(i <- 0..steps, do: at.(ro, i)) ++ for(i <- steps..0//-1, do: at.(r, i))
  end
end
