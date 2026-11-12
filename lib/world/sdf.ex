defmodule World.SDF do
  @moduledoc """
  Fields of distances and the edits of a sculpture
  (`docs/plans/0008-model-from-edits.md`, D1, D2 and D10).

  An edit is a simple shape at a place, with a mode: `:add` (the shape
  joins the sculpture), `:subtract` (the shape is taken away) or
  `:paint` (the shape gives its material to the surface in it, and does
  not change the shape). Each edit has a `blend` (m): with 0, the edge
  between the edit and the sculpture is hard; with more, the joint is
  smooth, and the edit reaches `blend` past its shape and no more (the
  quadratic smooth minimum).

  The field of a sculpture at a point is the fold of its edits in their
  order: less than 0 inside, more than 0 outside, 0 on the surface. Each
  shape gives the exact distance to its surface, or a bound of it (the
  ellipsoid, the superellipsoid): a value that changes by at most the
  distance between two points (a Lipschitz constant of 1). The blend
  keeps that, so the value of the field at a point is never more than
  the distance to the surface: a cell whose field at its center is more
  than its half diagonal from 0 has no surface in it.

  The blend of an edit bends the field of the edits before it too, so
  the reach of an edit is not its shape and its blend only. A cell keeps
  the edits that can change the field in it (`prune/3`): an edit that,
  at its step, changes the field at no point of the cell goes, and the
  field of the rest is the same at each point of the cell (the ranges
  of the field over the cell, as M. Keeter, "Massively Parallel
  Rendering of Complex Closed-Form Implicit Surfaces", 2020).

  The shapes, in the axes of the edit (z up), with their sizes (m):

  - `:ball` `{r}`;
  - `:box` `{hx, hy, hz}` (the half sizes);
  - `:round_box` `{hx, hy, hz, r}` (the half sizes, and the radius of
    its edges);
  - `:capsule` `{h, r}` (a segment from z = -h to z = h, and its radius);
  - `:cylinder` `{r, h}` (from z = -h to z = h);
  - `:cone` `{r1, r2, h}` (the radius `r1` at z = -h, `r2` at z = h);
  - `:ring` `{big, r}` (a torus round z: the radius of its circle and of
    its tube);
  - `:ellipsoid` `{rx, ry, rz}` (a bound);
  - `:superellipsoid` `{rx, ry, rz, e}` (`|x/rx|^e + |y/ry|^e + |z/rz|^e
    = 1`, `e` from 2 (the ellipsoid) up, toward a box; a bound);
  - `:tube` `{points, radii}` (round cones through the points of a
    curve, with the radius at each point).

  The distances follow the formulas of Inigo Quilez
  (https://iquilezles.org/articles/distfunctions/).
  """

  alias World.{Frame, Vec}

  # The field of no edit: far outside.
  @far 1.0e30
  @shapes [:ball, :box, :round_box, :capsule, :cylinder, :cone, :ring, :ellipsoid, :superellipsoid, :tube]
  @modes [:add, :subtract, :paint]

  defmodule Edit do
    @moduledoc "An edit of a sculpture (`World.SDF.edit/3`)."
    defstruct shape: :ball,
              size: {0.5},
              frame: nil,
              back: nil,
              local: nil,
              mode: :add,
              blend: 0.0,
              material: nil,
              color: nil,
              box: nil
  end

  @doc "The shapes of an edit."
  def shapes, do: @shapes

  @doc "The modes of an edit."
  def modes, do: @modes

  @doc """
  An edit: a shape with its sizes (see the module), and the options
  `frame` (a `World.Frame`: the place and the turn of the shape; none
  by default), `mode` (`:add` by default), `blend` (m, 0 by default),
  `material` (a role of the palette) and `color` (`{r, g, b}`, 0 to 255:
  the color of the surface of the edit, `color/3`).
  """
  def edit(shape, size, opts \\ []) when shape in @shapes do
    frame = Keyword.get(opts, :frame, Frame.identity())
    mode = Keyword.get(opts, :mode, :add)
    blend = Keyword.get(opts, :blend, 0.0) / 1
    unless mode in @modes, do: raise(ArgumentError, "the mode of an edit is add, subtract or paint")
    size = floats(size)

    %Edit{
      shape: shape,
      size: size,
      frame: frame,
      back: Frame.invert(frame),
      local: local(Frame.invert(frame)),
      mode: mode,
      blend: blend,
      material: Keyword.get(opts, :material),
      color: linear(Keyword.get(opts, :color)),
      box: placed(local_bounds(shape, size), frame)
    }
  end

  defp floats({points, radii}) when is_list(points), do: {Enum.map(points, &Vec.float/1), Enum.map(radii, &(&1 / 1))}
  defp floats(size), do: size |> Tuple.to_list() |> Enum.map(&(&1 / 1)) |> List.to_tuple()

  @doc "The distance from a point (in the axes of the sculpture) to the shape of an edit, or a bound of it."
  def distance(%Edit{shape: shape, size: size, local: m}, p), do: local(shape, size, point(m, p))

  # The frame from the axes of the sculpture to the axes of an edit, as a
  # tuple of numbers (the hot path has no maps): a move only, or a turn
  # and a move.
  defp local(%Frame{x: x, y: y, z: z, at: {tx, ty, tz}})
       when x == {1.0, +0.0, +0.0} and y == {+0.0, 1.0, +0.0} and z == {+0.0, +0.0, 1.0},
       do: {:move, tx, ty, tz}

  defp local(%Frame{x: {a, b, c}, y: {d, e, f}, z: {g, h, i}, at: {tx, ty, tz}}),
    do: {:turn, a, b, c, d, e, f, g, h, i, tx, ty, tz}

  defp point({:move, tx, ty, tz}, {x, y, z}), do: {x + tx, y + ty, z + tz}

  defp point({:turn, a, b, c, d, e, f, g, h, i, tx, ty, tz}, {x, y, z}),
    do: {tx + a * x + d * y + g * z, ty + b * x + e * y + h * z, tz + c * x + f * y + i * z}

  @doc """
  The field of the edits at a point, and the material of the surface
  there: `{value, material}`. With no edit, the point is far outside.

  With a `limit` (m), the value stays from `-limit` to `limit` after each
  edit. Far from the surface each value is the limit, so an edit there
  changes nothing, and `prune/4` lets it go: the short list of a cell
  near the surface holds only the edits near it. The field stays a bound
  (Lipschitz 1), and near the surface it is the field with no limit
  where no blend takes values near the limit into it: a limit of a few
  blends keeps the surface.
  """
  def field(edits, p, limit \\ @far) do
    Enum.reduce(edits, {limit, nil}, fn e, acc ->
      {d, mat} = step(e, acc, distance(e, p))
      {clamp(d, limit), mat}
    end)
  end

  @doc "The value of the field only."
  def value(edits, p, limit \\ @far), do: elem(field(edits, p, limit), 0)

  defp clamp(d, limit), do: min(max(d, -limit), limit)

  # An edit on the field so far: the smooth union, the smooth cut, or the
  # paint of the surface in its shape.
  defp step(%Edit{mode: :add, blend: r, material: m}, {d, mat}, de), do: {smin(d, de, r), if(de < d, do: m, else: mat)}

  defp step(%Edit{mode: :subtract, blend: r, material: m}, {d, mat}, de),
    do: {smax(d, -de, r), if(m != nil and -de > d, do: m, else: mat)}

  # A paint with no material (a color only) keeps the material under it.
  defp step(%Edit{mode: :paint, material: m}, {d, mat}, de), do: {d, if(m != nil and de <= 0.0, do: m, else: mat)}

  @doc """
  The color of the surface of the edits at a point: `{r, g, b}`, 0 to
  255 (`docs/plans/0009-sculpture-finish.md`, D2). The color is the fold
  of the edits in their order, from white: an edit that adds takes the
  color to its own color by the weight of its smooth minimum (all of it
  where the edit is the surface, none where the sculpture so far is,
  and a mix across its blend); an edit with a color that takes away
  gives it to the surface that it cuts, in the same way; an edit with a
  color that paints gives it in its shape, with a smooth step across its
  border over its blend. An edit that adds with no color is white: the
  color of its material shows as it is.
  """
  def color(edits, p, limit \\ @far) do
    {_, {r, g, b}} =
      Enum.reduce(edits, {limit, {1.0, 1.0, 1.0}}, fn e, {d, col} ->
        de = distance(e, p)

        case e.mode do
          :add -> {clamp(smin(d, de, e.blend), limit), mix(col, e.color || {1.0, 1.0, 1.0}, weight(d - de, e.blend))}
          :subtract -> {clamp(smax(d, -de, e.blend), limit), mix(col, e.color, weight(-de - d, e.blend))}
          :paint -> {d, mix(col, e.color, smooth(weight(-2 * de, e.blend)))}
        end
      end)

    {srgb(r), srgb(g), srgb(b)}
  end

  # The weight of the second of two values in their smooth minimum: 1
  # when it is less by the blend or more, 0 when it is more by the blend,
  # a line between (a step with no blend).
  defp weight(more, r) when r <= 0.0, do: if(more > 0.0, do: 1.0, else: 0.0)
  defp weight(more, r), do: min(max(0.5 + 0.5 * more / r, 0.0), 1.0)

  defp smooth(w), do: w * w * (3.0 - 2.0 * w)

  defp mix(col, nil, _w), do: col
  defp mix(col, _to, w) when w == 0.0, do: col
  defp mix({a, b, c}, {d, e, f}, w), do: {a + (d - a) * w, b + (e - b) * w, c + (f - c) * w}

  # A color of sRGB (0 to 255) as linear light (0 to 1), and back: a mix
  # of two colors is a mix of their light.
  defp linear(nil), do: nil
  defp linear({r, g, b}), do: {linear(r), linear(g), linear(b)}

  defp linear(c) do
    c = c / 255
    if c <= 0.04045, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
  end

  defp srgb(c) do
    c = min(max(c, 0.0), 1.0)
    round(255 * if(c <= 0.0031308, do: 12.92 * c, else: 1.055 * :math.pow(c, 1 / 2.4) - 0.055))
  end

  @doc """
  The smooth minimum of two values with the blend `r` (Dave Smith, Media
  Molecule; the quadratic smooth minimum of Inigo Quilez): the minimum
  when they are `r` or more apart, and less near each other, by at most
  `r / 4`.
  """
  def smin(a, b, r) when r <= 0.0, do: min(a, b)

  def smin(a, b, r) do
    e = max(r - abs(a - b), 0.0)
    min(a, b) - e * e / (4 * r)
  end

  @doc "The smooth maximum: the mirror of `smin/3`."
  def smax(a, b, r), do: -smin(-a, -b, r)

  @doc """
  The bounds of the inside of a sculpture (`{lo, hi}`, in its axes), or
  `nil` with no edit that adds: the boxes of the shapes that add, grown
  by a quarter of the sum of the blends (each smooth minimum lowers the
  field by at most a quarter of its blend, so the field is less than 0
  only that near a shape that adds).
  """
  def bounds(edits) do
    case for(%Edit{mode: :add, box: box} <- edits, do: box) do
      [] -> nil
      boxes -> boxes |> Enum.reduce(&join/2) |> grow(Enum.sum(Enum.map(edits, & &1.blend)) / 4)
    end
  end

  @doc """
  The edits that can change the field in a cell: the ball of the radius
  `half` round the point `center` (the half diagonal of a box). The field
  of the edits that it gives is the field of all the edits at each point
  of the cell (with the same `limit`, `field/3`). An edit goes when, at
  its step, it changes the field at no point of the cell: by the ranges
  of the field over the cell (each value at the center, less and more
  `half`, folded edit by edit, in the limit). An edit that adds goes when
  its least value is at least the most value of the field so far and its
  blend; an edit that takes away, when its least value is at least its
  blend less the least value of the field so far; an edit that paints,
  when its shape, grown by half of its blend (the border of its color,
  `color/3`), does not reach the cell.
  """
  def prune(edits, center, half, limit \\ @far), do: elem(cell(edits, center, half, limit), 0)

  @doc """
  The edits of a cell (`prune/4`) and the range of their field over the
  cell: `{edits, {lo, hi}}`. With `lo` more than 0 or `hi` less than 0,
  the surface does not cross the cell.
  """
  def cell(edits, center, half, limit \\ @far) do
    {kept, range} =
      Enum.reduce(edits, {[], {limit, limit}}, fn e, {kept, {lo, hi} = range} ->
        d = distance(e, center)
        {dlo, dhi} = {d - half, d + half}

        case e.mode do
          :add when dlo >= hi + e.blend -> {kept, range}
          :add -> {[e | kept], {clamp(smin(lo, dlo, e.blend), limit), clamp(smin(hi, dhi, e.blend), limit)}}
          :subtract when dlo >= e.blend - lo -> {kept, range}
          :subtract -> {[e | kept], {clamp(smax(lo, -dhi, e.blend), limit), clamp(smax(hi, -dlo, e.blend), limit)}}
          :paint when dlo > e.blend / 2 -> {kept, range}
          :paint -> {[e | kept], range}
        end
      end)

    {Enum.reverse(kept), range}
  end

  defp join({{a, b, c}, {d, e, f}}, {{g, h, i}, {j, k, l}}),
    do: {{min(a, g), min(b, h), min(c, i)}, {max(d, j), max(e, k), max(f, l)}}

  defp grow({lo, hi}, r), do: {Vec.sub(lo, {r, r, r}), Vec.add(hi, {r, r, r})}

  # The bounds of the box of a shape once it is placed: the box of its
  # eight corners.
  defp placed({{a, b, c}, {d, e, f}}, frame) do
    corners = for x <- [a, d], y <- [b, e], z <- [c, f], do: Frame.point(frame, {x, y, z})
    Vec.bounds(corners)
  end

  defp local_bounds(:ball, {r}), do: cube(r)
  defp local_bounds(:box, {x, y, z}), do: {{-x, -y, -z}, {x, y, z}}
  defp local_bounds(:round_box, {x, y, z, _}), do: {{-x, -y, -z}, {x, y, z}}
  defp local_bounds(:capsule, {h, r}), do: {{-r, -r, -h - r}, {r, r, h + r}}
  defp local_bounds(:cylinder, {r, h}), do: {{-r, -r, -h}, {r, r, h}}
  defp local_bounds(:cone, {r1, r2, h}), do: (fn r -> {{-r, -r, -h}, {r, r, h}} end).(max(r1, r2))
  defp local_bounds(:ring, {big, r}), do: {{-big - r, -big - r, -r}, {big + r, big + r, r}}
  defp local_bounds(:ellipsoid, {x, y, z}), do: {{-x, -y, -z}, {x, y, z}}
  defp local_bounds(:superellipsoid, {x, y, z, _}), do: {{-x, -y, -z}, {x, y, z}}

  defp local_bounds(:tube, {points, radii}) do
    boxes = Enum.zip_with(points, radii, fn p, r -> {Vec.sub(p, {r, r, r}), Vec.add(p, {r, r, r})} end)
    Enum.reduce(boxes, &join/2)
  end

  defp cube(r), do: {{-r, -r, -r}, {r, r, r}}

  # The distance from a point in the axes of the shape.
  defp local(:ball, {r}, {x, y, z}), do: :math.sqrt(x * x + y * y + z * z) - r

  defp local(:box, {hx, hy, hz}, {x, y, z}), do: box(abs(x) - hx, abs(y) - hy, abs(z) - hz)

  defp local(:round_box, {hx, hy, hz, r}, {x, y, z}), do: box(abs(x) - hx + r, abs(y) - hy + r, abs(z) - hz + r) - r

  defp local(:capsule, {h, r}, {x, y, z}) do
    w = z - min(max(z, -h), h)
    :math.sqrt(x * x + y * y + w * w) - r
  end

  defp local(:cylinder, {r, h}, {x, y, z}) do
    {dx, dz} = {:math.sqrt(x * x + y * y) - r, abs(z) - h}
    min(max(dx, dz), 0.0) + :math.sqrt(sq(max(dx, 0.0)) + sq(max(dz, 0.0)))
  end

  defp local(:cone, {r1, r2, h}, {x, y, z}) do
    {qx, qy} = {:math.sqrt(x * x + y * y), z}
    {k1x, k1y} = {r2, h}
    {k2x, k2y} = {r2 - r1, 2 * h}
    ca = {qx - min(qx, if(qy < 0.0, do: r1, else: r2)), abs(qy) - h}
    t = min(max(((k1x - qx) * k2x + (k1y - qy) * k2y) / (k2x * k2x + k2y * k2y), 0.0), 1.0)
    cb = {qx - k1x + k2x * t, qy - k1y + k2y * t}
    s = if elem(cb, 0) < 0.0 and elem(ca, 1) < 0.0, do: -1.0, else: 1.0
    s * :math.sqrt(min(dot2(ca), dot2(cb)))
  end

  defp local(:ring, {big, r}, {x, y, z}), do: :math.sqrt(sq(:math.sqrt(x * x + y * y) - big) + z * z) - r

  # The ellipsoid: a bound (Inigo Quilez), with the center inside by its
  # least radius.
  defp local(:ellipsoid, {rx, ry, rz}, {x, y, z}) do
    {ax, ay, az} = {x / rx, y / ry, z / rz}
    {bx, by, bz} = {ax / rx, ay / ry, az / rz}
    k0 = :math.sqrt(ax * ax + ay * ay + az * az)
    k1 = :math.sqrt(bx * bx + by * by + bz * bz)
    if k1 == 0.0, do: -min(rx, min(ry, rz)), else: k0 * (k0 - 1.0) / k1
  end

  # The superellipsoid: its norm of the power `e`, less 1, times its least
  # radius. For `e` of 2 or more, its gradient is never longer than 1 over
  # the least radius, so the value is a bound.
  defp local(:superellipsoid, {rx, ry, rz, e}, {x, y, z}) do
    n = :math.pow(:math.pow(abs(x / rx), e) + :math.pow(abs(y / ry), e) + :math.pow(abs(z / rz), e), 1.0 / e)
    (n - 1.0) * Enum.min([rx, ry, rz])
  end

  defp local(:tube, {[a | rest], [ra | radii]}, p) do
    {d, _, _} =
      Enum.zip(rest, radii)
      |> Enum.reduce({@far, a, ra}, fn {b, rb}, {d, a, ra} -> {min(d, round_cone(p, a, b, ra, rb)), b, rb} end)

    if rest == [], do: Vec.len(Vec.sub(p, a)) - ra, else: d
  end

  defp box(qx, qy, qz) do
    :math.sqrt(sq(max(qx, 0.0)) + sq(max(qy, 0.0)) + sq(max(qz, 0.0))) + min(max(qx, max(qy, qz)), 0.0)
  end

  # The cone with round ends from `a` (radius `r1`) to `b` (radius `r2`)
  # (Inigo Quilez, exact).
  defp round_cone(p, a, b, r1, r2) do
    ba = Vec.sub(b, a)
    l2 = Vec.dot(ba, ba)
    rr = r1 - r2
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = Vec.sub(p, a)
    y = Vec.dot(pa, ba)
    z = y - l2
    x2 = pa |> Vec.scale(l2) |> Vec.sub(Vec.scale(ba, y)) |> then(&Vec.dot(&1, &1))
    y2 = y * y * l2
    z2 = z * z * l2
    k = sign(rr) * rr * rr * x2

    cond do
      sign(z) * a2 * z2 > k -> :math.sqrt(x2 + z2) * il2 - r2
      sign(y) * a2 * y2 < k -> :math.sqrt(x2 + y2) * il2 - r1
      true -> (:math.sqrt(x2 * a2 * il2) + y * rr) * il2 - r1
    end
  end

  defp sign(v) when v > 0.0, do: 1.0
  defp sign(v) when v < 0.0, do: -1.0
  defp sign(_), do: 0.0

  defp sq(v), do: v * v
  defp dot2({a, b}), do: a * a + b * b
end
