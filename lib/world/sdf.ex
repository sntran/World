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
    curve, with the radius at each point);
  - `:wedge` `{hx, hy, hz}` (a box with a slope from its top edge at the
    back to its bottom edge at the front; a bound);
  - `:prism` `{r, h, n}` (`n` sides round z, each `r` from the axis, from
    z = -h to z = h; a bound);
  - `:pyramid` `{hx, hy, h}` (a base of `2 hx` by `2 hy` at z = -h, and
    its point at z = h; a bound);
  - `:extrude` `{points, h, r}` (a closed outline in the plane of x and
    y, a list of `{x, y}`, from z = -h to z = h, with round edges of the
    radius `r`: the side of a car, the section of a hull);
  - `:revolve` `{points}` (a closed profile, a list of `{r, z}` with `r`
    of 0 or more, turned round z: a bottle, a bowl, a baluster).

  The distances follow the formulas of Inigo Quilez
  (https://iquilezles.org/articles/distfunctions/).
  """

  alias World.{Frame, Vec}

  # The field of no edit: far outside.
  @far 1.0e30
  @shapes [
    :ball,
    :box,
    :round_box,
    :capsule,
    :cylinder,
    :cone,
    :ring,
    :ellipsoid,
    :superellipsoid,
    :tube,
    :wedge,
    :prism,
    :pyramid,
    :extrude,
    :revolve
  ]
  @modes [:add, :subtract, :paint, :crop]

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
              raise: 0.0,
              hard: false,
              opacity: 1.0,
              roughness: nil,
              metal: nil,
              glow: nil,
              surface: nil,
              box: nil,
              id: nil
  end

  @doc "The shapes of an edit."
  def shapes, do: @shapes

  @doc "The modes of an edit."
  def modes, do: @modes

  @doc """
  An edit: a shape with its sizes (see the module), and the options
  `frame` (a `World.Frame`: the place and the turn of the shape; none
  by default), `mode` (`:add` by default), `blend` (m, 0 by default),
  `material` (a role of the palette), `color` (`{r, g, b}`, 0 to 255:
  the color of the surface of the edit, `color/3`) and `raise` (m, for
  an edit that paints: the surface moves out by that much in its shape,
  or in with less than 0, with a smooth step across its border over its
  blend: a relief that follows the surface, as a scale or a groove),
  and the finish of its surface: `roughness`, `metal` and `glow` (each
  from 0 to 1, or nil; `finish/3`). `hard: true` makes the blend a flat
  slope between the two surfaces (`chamfer/3`), and `opacity` (0 to 1,
  for an edit that paints) is the part of its color and of its finish
  that the surface takes.
  """
  def edit(shape, size, opts \\ []) when shape in @shapes do
    frame = Keyword.get(opts, :frame, Frame.identity())
    mode = Keyword.get(opts, :mode, :add)
    blend = Keyword.get(opts, :blend, 0.0) / 1
    unless mode in @modes, do: raise(ArgumentError, "the mode of an edit is add, subtract, paint or crop")
    lift = Keyword.get(opts, :raise, 0.0) / 1
    if lift != 0.0 and mode != :paint, do: raise(ArgumentError, "only an edit that paints has a raise")
    size = floats(size)

    edit = %Edit{
      shape: shape,
      size: size,
      frame: frame,
      back: Frame.invert(frame),
      local: local(Frame.invert(frame)),
      mode: mode,
      blend: blend,
      material: Keyword.get(opts, :material),
      color: linear(Keyword.get(opts, :color)),
      raise: lift,
      hard: Keyword.get(opts, :hard, false),
      opacity: Keyword.get(opts, :opacity, 1.0) * 1.0,
      roughness: number(opts[:roughness]),
      metal: number(opts[:metal]),
      glow: number(opts[:glow]),
      surface: opts[:surface],
      box: placed(local_bounds(shape, size), frame)
    }

    # The id of the edit: a hash of what it is, made once. The keys of the
    # cache of a sculpture hash the ids of its edits, not the edits.
    identify(edit)
  end

  defp identify(%Edit{} = e) do
    what =
      {e.shape, e.size, e.frame, e.mode, e.blend, e.material, e.color, e.raise, e.roughness, e.metal, e.glow, e.hard,
       e.opacity}

    # (An edit with no surface has the id that it had before the surfaces.)
    what = if e.surface, do: Tuple.insert_at(what, tuple_size(what), e.surface), else: what
    %{e | id: :erlang.md5(:erlang.term_to_binary(what))}
  end

  defp number(nil), do: nil
  defp number(v), do: v * 1.0

  @doc """
  The edits for a mesh with cells of `step` m, when maps have the fine
  relief (`World.Sculpt.Bake`): a paint with a raise of less than half a
  cell has no raise (its relief is smaller than the mesh can show, and
  makes its points uneven).
  """
  def coarse(edits, step) do
    for e <- edits, do: if(e.raise != 0.0 and abs(e.raise) < step / 2, do: identify(%{e | raise: 0.0}), else: e)
  end

  @doc """
  The most that the paints of some edits move the surface (m): the sum
  of their raises, each as a length. With a relief the field is not a
  bound of the distance any more: it is at most this far from one.
  """
  def relief(edits), do: Enum.reduce(edits, 0.0, &(abs(&1.raise) + &2))

  @doc "The ids of some edits (`edit/3`), in their order."
  def ids(edits), do: Enum.map(edits, & &1.id)

  defp floats({points, radii}) when is_list(points) and is_list(radii),
    do: {Enum.map(points, &Vec.float/1), Enum.map(radii, &(&1 / 1))}

  # (An outline: its points in a plane, and for an extrude its half depth and the radius of its edges.)
  defp floats({points, h, r}) when is_list(points), do: {flat(points), h / 1, r / 1}
  defp floats({points}) when is_list(points), do: {flat(points)}
  defp floats(size), do: size |> Tuple.to_list() |> Enum.map(&(&1 / 1)) |> List.to_tuple()

  defp flat(points), do: for({x, y} <- points, do: {x / 1, y / 1})

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

  @doc """
  The value of the field only (the hot path of a sculpture: a loop of its
  own, with no material). The edits can be a list of `fast/1`: the same
  value, in a third of the time.
  """
  def value(edits, p, limit \\ @far)
  def value({:fast, list}, {x, y, z}, limit), do: run(list, x * 1.0, y * 1.0, z * 1.0, limit * 1.0, limit * 1.0)
  def value(edits, p, limit), do: fold(edits, p, limit, limit)

  @doc """
  The edits as a list for the hot loop of `value/3`
  (`docs/plans/0010-sculpture-maps.md`, D13): a tuple of numbers for
  each edit, with its shape, its frame and its mode in its tag. A paint
  with no raise is not in the list (it does not change the value). A
  tube and a superellipsoid have a call of `distance/2`; each other
  shape has its distance in the loop.
  """
  def fast(edits), do: {:fast, for(e <- edits, not (e.mode == :paint and e.raise == 0.0), do: pack(e))}

  @inline %{ball: 1, box: 3, round_box: 4, capsule: 2, cylinder: 2, ellipsoid: 3, ring: 2, cone: 3}

  defp pack(%Edit{shape: shape, size: size, local: local, mode: mode, blend: k, raise: up} = e) do
    if @inline[shape] do
      # The numbers of the frame (a move, or a turn), of the size, the blend and the raise.
      [kind | frame] = Tuple.to_list(local)
      List.to_tuple([:"#{shape}_#{kind}_#{mode}" | numbers(frame ++ Tuple.to_list(size) ++ [k, up, hard(e)])])
    else
      {:"any_#{mode}", e, k, up, hard(e)}
    end
  end

  defp numbers(list), do: Enum.map(list, &(&1 * 1.0))
  # A hard blend, as a number of the hot loop.
  defp hard(%Edit{hard: hard}), do: if(hard, do: 1.0, else: 0.0)

  require World.SDF.Inline, as: Inline

  defp run([], _x, _y, _z, d, _limit), do: d

  # A clause for each shape with its distance in the loop, each frame (a
  # move only, or a turn) and each mode. The steps of each distance are
  # the steps of `local/3`.
  distances = [
    ball: quote(do: :math.sqrt(lx * lx + ly * ly + lz * lz) - s1),
    box:
      quote do
        {qx, qy, qz} = {abs(lx) - s1, abs(ly) - s2, abs(lz) - s3}
        {px, py, pz} = {Inline.positive(qx), Inline.positive(qy), Inline.positive(qz)}
        most = if qy > qz, do: qy, else: qz
        most = if qx > most, do: qx, else: most
        :math.sqrt(px * px + py * py + pz * pz) + if(most < 0.0, do: most, else: 0.0)
      end,
    round_box:
      quote do
        {qx, qy, qz} = {abs(lx) - s1 + s4, abs(ly) - s2 + s4, abs(lz) - s3 + s4}
        {px, py, pz} = {Inline.positive(qx), Inline.positive(qy), Inline.positive(qz)}
        most = if qy > qz, do: qy, else: qz
        most = if qx > most, do: qx, else: most
        :math.sqrt(px * px + py * py + pz * pz) + if(most < 0.0, do: most, else: 0.0) - s4
      end,
    capsule:
      quote do
        on =
          cond do
            lz < -s1 -> -s1
            lz > s1 -> s1
            true -> lz
          end

        w = lz - on
        :math.sqrt(lx * lx + ly * ly + w * w) - s2
      end,
    cylinder:
      quote do
        {dx, dz} = {:math.sqrt(lx * lx + ly * ly) - s1, abs(lz) - s2}
        most = if dx > dz, do: dx, else: dz
        {px, pz} = {Inline.positive(dx), Inline.positive(dz)}
        if(most < 0.0, do: most, else: 0.0) + :math.sqrt(px * px + pz * pz)
      end,
    ring:
      quote(do: :math.sqrt((:math.sqrt(lx * lx + ly * ly) - s1) * (:math.sqrt(lx * lx + ly * ly) - s1) + lz * lz) - s2),
    ellipsoid:
      quote do
        {ax, ay, az} = {lx / s1, ly / s2, lz / s3}
        k0 = :math.sqrt(ax * ax + ay * ay + az * az)

        if k0 <= 1.0 do
          least = if s2 <= s3, do: s2, else: s3
          (k0 - 1.0) * if(s1 <= least, do: s1, else: least)
        else
          {ux, uy, uz} = {s1 * abs(lx), s2 * abs(ly), s3 * abs(lz)}
          {sx, sy, sz} = {s1 * s1, s2 * s2, s3 * s3}
          {from_x, from_y, from_z} = {ux - sx, uy - sy, Inline.positive(uz - sz)}
          from = if from_x >= from_y, do: from_x, else: from_y
          from = if from >= from_z, do: from, else: from_z
          t = Inline.root(from, ux, uy, uz, sx, sy, sz, 8)
          {dx, dy, dz} = {lx * t / (sx + t), ly * t / (sy + t), lz * t / (sz + t)}
          :math.sqrt(dx * dx + dy * dy + dz * dz)
        end
      end,
    cone:
      quote do
        # s1 and s2 are the radius at z = -s3 and at z = s3.
        qx = :math.sqrt(lx * lx + ly * ly)
        {k2x, k2y} = {s2 - s1, 2 * s3}
        end_r = if lz < 0.0, do: s1, else: s2
        {cax, cay} = {qx - if(qx <= end_r, do: qx, else: end_r), abs(lz) - s3}
        raw = ((s2 - qx) * k2x + (s3 - lz) * k2y) / (k2x * k2x + k2y * k2y)

        t =
          cond do
            raw < 0.0 -> 0.0
            raw > 1.0 -> 1.0
            true -> raw
          end

        {cbx, cby} = {qx - s2 + k2x * t, lz - s3 + k2y * t}
        {da, db} = {cax * cax + cay * cay, cbx * cbx + cby * cby}
        sign = if cbx < 0.0 and cay < 0.0, do: -1.0, else: 1.0
        sign * :math.sqrt(if(da <= db, do: da, else: db))
      end
  ]

  frames = [
    move:
      {~w(tx ty tz)a,
       quote do
         {lx, ly, lz} = {x + tx, y + ty, z + tz}
       end},
    turn:
      {~w(m1 m2 m3 m4 m5 m6 m7 m8 m9 tx ty tz)a,
       quote do
         {lx, ly, lz} = {tx + m1 * x + m4 * y + m7 * z, ty + m2 * x + m5 * y + m8 * z, tz + m3 * x + m6 * y + m9 * z}
       end}
  ]

  # The variables of the quoted steps get the context of the body of a
  # function, so the steps and the body share them.
  plain = fn ast ->
    Macro.prewalk(ast, fn
      {name, meta, context} when is_atom(name) and is_atom(context) -> {name, meta, nil}
      other -> other
    end)
  end

  steps = fn
    :paint -> plain.(quote(do: Inline.lift(d, de, k, up, limit)))
    mode -> plain.(quote(do: Inline.blend(unquote(mode), d, de, k, hd, limit)))
  end

  for {shape, distance} <- distances, {frame, {names, place}} <- frames, mode <- @modes do
    tag = :"#{shape}_#{frame}_#{mode}"
    names = names ++ Enum.map(1..@inline[shape], &:"s#{&1}") ++ [:k, :up, :hd]
    vars = Enum.map(names, &Macro.var(&1, nil))

    floats =
      Enum.reduce(names ++ ~w(x y z d limit)a, true, &quote(do: unquote(&2) and is_float(unquote(Macro.var(&1, nil)))))

    defp run([{unquote(tag), unquote_splicing(vars)} | rest], x, y, z, d, limit) when unquote(floats) do
      unquote(plain.(place))
      de = unquote(plain.(distance))
      _ = {up, hd}
      run(rest, x, y, z, unquote(steps.(mode)), limit)
    end
  end

  # Each other shape: its distance from `distance/2`.
  for mode <- @modes do
    defp run([{unquote(:"any_#{mode}"), edit, k, up, hd} | rest], x, y, z, d, limit) do
      de = distance(edit, {x, y, z})
      _ = {up, hd}
      run(rest, x, y, z, unquote(steps.(mode)), limit)
    end
  end

  defp fold([], _p, d, _limit), do: d

  defp fold([%Edit{mode: :add} = e | rest], p, d, limit),
    do: fold(rest, p, clamp(less(d, distance(e, p), e), limit), limit)

  defp fold([%Edit{mode: :subtract} = e | rest], p, d, limit),
    do: fold(rest, p, clamp(more(d, -distance(e, p), e), limit), limit)

  # A crop keeps what is inside its shape.
  defp fold([%Edit{mode: :crop} = e | rest], p, d, limit),
    do: fold(rest, p, clamp(more(d, distance(e, p), e), limit), limit)

  # A paint with a raise moves the surface in its shape; a paint with
  # none does not change the value.
  defp fold([%Edit{mode: :paint, raise: h, blend: r} = e | rest], p, d, limit) when h != 0.0,
    do: fold(rest, p, clamp(d - h * smooth(weight(-2 * distance(e, p), r)), limit), limit)

  defp fold([%Edit{mode: :paint} | rest], p, d, limit), do: fold(rest, p, d, limit)

  defp clamp(d, limit), do: min(max(d, -limit), limit)

  # An edit on the field so far: the smooth union, the smooth cut, or the
  # paint of the surface in its shape.
  defp step(%Edit{mode: :add, material: m} = e, {d, mat}, de), do: {less(d, de, e), if(de < d, do: m, else: mat)}

  defp step(%Edit{mode: :subtract, material: m} = e, {d, mat}, de),
    do: {more(d, -de, e), if(m != nil and -de > d, do: m, else: mat)}

  defp step(%Edit{mode: :crop, material: m} = e, {d, mat}, de),
    do: {more(d, de, e), if(m != nil and de > d, do: m, else: mat)}

  # A paint with no material (a color only) keeps the material under it.
  defp step(%Edit{mode: :paint, material: m, raise: h, blend: r}, {d, mat}, de),
    do: {d - h * smooth(weight(-2 * de, r)), if(m != nil and de <= 0.0, do: m, else: mat)}

  # The least and the most of two values in the blend of an edit: smooth,
  # or with a flat slope for a hard blend.
  defp less(a, b, %Edit{blend: r, hard: false}), do: smin(a, b, r)
  defp less(a, b, %Edit{blend: r}), do: chamfer(a, b, r)
  defp more(a, b, e), do: -less(-a, -b, e)

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
  def color(edits, p, limit \\ @far), do: elem(sample(edits, p, limit), 1)

  @doc """
  The value of the field and the color at a point, in one pass over the
  edits: `{value, {r, g, b}}` (`value/3`, `color/3`).
  """
  def sample(edits, p, limit \\ @far) do
    {d, {r, g, b}} = tint(edits, p, limit, @far, {1.0, 1.0, 1.0}, limit)
    {d, {srgb(r), srgb(g), srgb(b)}}
  end

  @doc """
  `sample/3` with the finish of the surface at the point too (`finish/3`,
  with the same `defaults`): `{value, color, finish}`. One fold of the
  edits gives the three: the weights of the color are the weights of the
  finish.
  """
  def sample(edits, p, limit, defaults) do
    {d, color, finish, _top} = seen(edits, p, limit, defaults)
    {d, color, finish}
  end

  @doc """
  `sample/4` with the edit of the surface at the point too: `{value,
  color, finish, edit}`. It is the last edit with more than half of the
  weight of the color there: an edit that adds, or an edit with a
  surface that takes away or paints (`World.Sculpt.Texture`). Nil with
  no edit there.
  """
  def seen(edits, p, limit, defaults) do
    {d, {r, g, b}, finish, top} =
      look(edits, p, {limit, @far}, {1.0, 1.0, 1.0}, {0.6, 0.0, 0.0}, limit, defaults, nil)

    {d, {srgb(r), srgb(g), srgb(b)}, finish, top}
  end

  # The fold of `tint/6` with the finish of `finish/3`.
  defp look([], _p, {d, _u}, col, fin, _limit, _defaults, top), do: {d, col, fin, top}

  defp look([%Edit{mode: :add, blend: r, color: c} = e | rest], p, {d, u}, col, fin, limit, defaults, top) do
    de = distance(e, p)
    w = weight(u - de, r)
    {rough, metal} = Map.get(defaults, e.material, {0.6, 0.0})
    own = {e.roughness || rough, e.metal || metal, e.glow || 0.0}

    look(
      rest,
      p,
      {clamp(less(d, de, e), limit), less(u, de, e)},
      mix(col, c || {1.0, 1.0, 1.0}, w),
      part(fin, own, w),
      limit,
      defaults,
      if(w > 0.5, do: e, else: top)
    )
  end

  defp look([%Edit{mode: :subtract, blend: r, color: c} = e | rest], p, {d, u}, col, fin, limit, defaults, top) do
    de = distance(e, p)
    w = weight(-de - u, r)

    look(
      rest,
      p,
      {clamp(more(d, -de, e), limit), more(u, -de, e)},
      mix(col, c, w),
      part(fin, {e.roughness, e.metal, e.glow}, w),
      limit,
      defaults,
      own(e, w, top)
    )
  end

  defp look([%Edit{mode: :crop, blend: r, color: c} = e | rest], p, {d, u}, col, fin, limit, defaults, top) do
    de = distance(e, p)
    w = weight(de - u, r)

    look(
      rest,
      p,
      {clamp(more(d, de, e), limit), more(u, de, e)},
      mix(col, c, w),
      part(fin, {e.roughness, e.metal, e.glow}, w),
      limit,
      defaults,
      own(e, w, top)
    )
  end

  defp look(
         [%Edit{mode: :paint, blend: r, color: c, raise: h, opacity: o} = e | rest],
         p,
         {d, u},
         col,
         fin,
         limit,
         defaults,
         top
       ) do
    w = smooth(weight(-2 * distance(e, p), r))

    look(
      rest,
      p,
      {clamp(d - h * w, limit), u - h * w},
      mix(col, c, w * o),
      part(fin, {e.roughness, e.metal, e.glow}, w * o),
      limit,
      defaults,
      own(e, w * o, top)
    )
  end

  # An edit that takes away or paints has the surface of a place when it
  # has a surface of its own and more than half of the weight there.
  defp own(%Edit{surface: surface} = e, w, _top) when surface != nil and w > 0.5, do: e
  defp own(_e, _w, top), do: top

  @doc """
  The finish of the surface of the edits at a point: `{roughness, metal,
  glow}`, each from 0 to 1 (`docs/plans/0010-sculpture-maps.md`, D10).
  It is the fold of the edits, with the weights of the fold of the
  colors (`color/3`): an edit that adds gives its finish to its surface
  (with none of its own, the finish of its material in `defaults`: a
  role to `{roughness, metal}`; with no role there, rough and no metal),
  and no glow with none of its own; an edit that takes away or paints
  gives the parts of the finish that it has, and keeps the others.
  """
  def finish(edits, p, defaults \\ %{}) do
    {_, finish} =
      Enum.reduce(edits, {@far, {0.6, 0.0, 0.0}}, fn e, {u, finish} ->
        de = distance(e, p)

        case e.mode do
          :add ->
            {rough, metal} = Map.get(defaults, e.material, {0.6, 0.0})
            own = {e.roughness || rough, e.metal || metal, e.glow || 0.0}
            {less(u, de, e), part(finish, own, weight(u - de, e.blend))}

          :subtract ->
            {more(u, -de, e), part(finish, {e.roughness, e.metal, e.glow}, weight(-de - u, e.blend))}

          :crop ->
            {more(u, de, e), part(finish, {e.roughness, e.metal, e.glow}, weight(de - u, e.blend))}

          :paint ->
            w = smooth(weight(-2 * de, e.blend))
            {u - e.raise * w, part(finish, {e.roughness, e.metal, e.glow}, w * e.opacity)}
        end
      end)

    finish
  end

  @doc "An edit of these has a finish of its own (`finish/3`)."
  def finished?(edits), do: Enum.any?(edits, &(&1.roughness || &1.metal || &1.glow))

  # Each part of a finish to the part of another one by a weight (a part
  # that the other one does not have stays). With a weight of 1, the part
  # is the part of the other one to the bit.
  defp part({a, b, c}, {d, e, f}, w), do: {part(a, d, w), part(b, e, w), part(c, f, w)}
  defp part(a, nil, _w), do: a
  defp part(a, b, w), do: a * (1 - w) + b * w

  @doc """
  The part of each edit that adds in the surface at a point, as the
  fold of the colors has it (`color/3`): `[{edit, share}]`, the shares
  add to 1 (an empty list with no edit that adds). The edit of the
  surface there has the share 1; across a smooth joint of two edits, the
  two have a share each.
  """
  def shares(edits, p) do
    {_, shares} =
      Enum.reduce(edits, {@far, []}, fn
        %Edit{mode: :add, blend: r} = e, {u, shares} ->
          de = distance(e, p)
          w = weight(u - de, r)
          {less(u, de, e), [{e, w} | for({o, s} <- shares, do: {o, s * (1 - w)})]}

        %Edit{mode: :subtract} = e, {u, shares} ->
          {more(u, -distance(e, p), e), shares}

        %Edit{mode: :crop} = e, {u, shares} ->
          {more(u, distance(e, p), e), shares}

        _, acc ->
          acc
      end)

    for {e, s} <- shares, s > 0.0, do: {e, s}
  end

  # The fold of the value and the color: its own loop (as `fold/4`), and
  # the color changes only where an edit has a weight. The weights come
  # from the value with no limit (`u`): at a place farther from each
  # shape than the limit, the color is still the color of the nearest
  # one (a texel of a map past the edge of a long triangle).
  defp tint([], _p, d, _u, col, _limit), do: {d, col}

  defp tint([%Edit{mode: :add, blend: r, color: c} = e | rest], p, d, u, col, limit) do
    de = distance(e, p)
    col = mix(col, c || {1.0, 1.0, 1.0}, weight(u - de, r))
    tint(rest, p, clamp(less(d, de, e), limit), less(u, de, e), col, limit)
  end

  defp tint([%Edit{mode: :subtract, blend: r, color: c} = e | rest], p, d, u, col, limit) do
    de = distance(e, p)
    tint(rest, p, clamp(more(d, -de, e), limit), more(u, -de, e), mix(col, c, weight(-de - u, r)), limit)
  end

  # A crop gives its color to the surface that it makes.
  defp tint([%Edit{mode: :crop, blend: r, color: c} = e | rest], p, d, u, col, limit) do
    de = distance(e, p)
    tint(rest, p, clamp(more(d, de, e), limit), more(u, de, e), mix(col, c, weight(de - u, r)), limit)
  end

  defp tint([%Edit{mode: :paint, blend: r, color: c, raise: h, opacity: o} = e | rest], p, d, u, col, limit) do
    w = smooth(weight(-2 * distance(e, p), r))
    tint(rest, p, clamp(d - h * w, limit), u - h * w, mix(col, c, w * o), limit)
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
  The minimum of two values with a flat slope across the blend `r` (the
  hard blend of Dreams): the minimum when the two values are `r` or more
  apart, and half of what is missing to `r` less than the minimum else.
  Between two flat faces at a right angle it makes a flat face at 45
  degrees, `r` from their edge on each. As `smin/3`, an edit reaches
  only `r` past its shape, and the field stays a bound (it lowers the
  minimum by at most `r / 2`).
  """
  def chamfer(a, b, r) when r <= 0.0, do: min(a, b)
  def chamfer(a, b, r), do: min(a, b) - max(r - abs(a - b), 0.0) / 2

  @doc """
  The bounds of the inside of a sculpture (`{lo, hi}`, in its axes), or
  `nil` with no edit that adds: the boxes of the shapes that add, grown
  by a quarter of the sum of the blends (each smooth minimum lowers the
  field by at most a quarter of its blend, so the field is less than 0
  only that near a shape that adds), and by the relief of the paints
  (`relief/1`).

  The field of a wedge, a prism, a pyramid or a superellipsoid is less
  than the distance at an edge, so a blend reaches farther there: the
  box of such a shape grows by more (the box of the points where its
  field is less than the reach).
  """
  def bounds(edits) do
    case for(%Edit{mode: :add} = e <- edits, do: e) do
      [] ->
        nil

      adds ->
        # A smooth minimum lowers the field by a quarter of its blend at the most, a hard one by a half.
        reach = Enum.sum(for e <- edits, do: if(e.hard, do: e.blend / 2, else: e.blend / 4)) + relief(edits)
        adds |> Enum.map(&reach(&1, reach)) |> Enum.reduce(&join/2)
    end
  end

  # The box of the points where the field of an edit is less than `c`
  # (0 or more). For a field that is the distance outside, the box of
  # the edit grown by `c`. For the most of the distances to some planes
  # (`local/3`), the box of the planes moved out by `c`: a sharp edge
  # goes out by more than `c`.
  defp reach(%Edit{shape: :wedge, size: {hx, hy, hz}, frame: frame}, c) do
    l = :math.sqrt(hz * hz + hy * hy)
    placed({{-hx - c, -hy - c, -hz - c}, {hx + c, hy + c * (l + hy) / hz, hz + c * (l + hz) / hy}}, frame)
  end

  defp reach(%Edit{shape: :pyramid, size: {hx, hy, h}, frame: frame}, c) do
    {lx, ly} = {:math.sqrt(4 * h * h + hx * hx), :math.sqrt(4 * h * h + hy * hy)}
    {x, y} = {hx + c * (lx + hx) / (2 * h), hy + c * (ly + hy) / (2 * h)}
    placed({{-x, -y, -h - c}, {x, y, h + c * min(lx / hx, ly / hy)}}, frame)
  end

  defp reach(%Edit{shape: :prism, size: {r, h, n}, frame: frame}, c),
    do: placed(local_bounds(:prism, {r + c, h + c, n}), frame)

  # (The norm of the shape less 1, times its least radius: the shape with each radius longer by the same part.)
  defp reach(%Edit{shape: :superellipsoid, size: {x, y, z, e}, frame: frame}, c) do
    k = 1 + c / Enum.min([x, y, z])
    placed(local_bounds(:superellipsoid, {x * k, y * k, z * k, e}), frame)
  end

  defp reach(%Edit{box: box}, c), do: grow(box, c)

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
          :add -> {[e | kept], {clamp(less(lo, dlo, e), limit), clamp(less(hi, dhi, e), limit)}}
          :subtract when dlo >= e.blend - lo -> {kept, range}
          :subtract -> {[e | kept], {clamp(more(lo, -dhi, e), limit), clamp(more(hi, -dlo, e), limit)}}
          # A crop whose shape holds the cell, deeper than the field so far and its blend, changes nothing.
          :crop when dhi <= lo - e.blend -> {kept, range}
          :crop -> {[e | kept], {clamp(more(lo, dlo, e), limit), clamp(more(hi, dhi, e), limit)}}
          :paint when dlo > e.blend / 2 -> {kept, range}
          # A raise lowers the field by its height at the most (or lifts it, with less than 0).
          :paint -> {[e | kept], {clamp(lo - max(e.raise, 0.0), limit), clamp(hi - min(e.raise, 0.0), limit)}}
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

  defp local_bounds(:wedge, {x, y, z}), do: {{-x, -y, -z}, {x, y, z}}
  defp local_bounds(:pyramid, {x, y, h}), do: {{-x, -y, -h}, {x, y, h}}
  # The corners of a prism are farther from its axis than its sides.
  defp local_bounds(:prism, {r, h, n}),
    do: (fn far -> {{-far, -far, -h}, {far, far, h}} end).(r / :math.cos(:math.pi() / n))

  defp local_bounds(:extrude, {points, h, _r}) do
    {xs, ys} = Enum.unzip(points)
    {{Enum.min(xs), Enum.min(ys), -h}, {Enum.max(xs), Enum.max(ys), h}}
  end

  defp local_bounds(:revolve, {points}) do
    {rs, zs} = Enum.unzip(points)
    far = Enum.max(rs)
    {{-far, -far, Enum.min(zs)}, {far, far, Enum.max(zs)}}
  end

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

  # The ellipsoid. Outside, the true distance: the nearest point x of
  # the surface has p = x + t x / r^2 on each axis, and t is the root of
  # sum((r p / (t + r^2))^2) = 1, by steps of Newton from below (the sum
  # falls and is convex, so each step is short of the root: 8 at most,
  # to 2 parts in a million). Inside, its norm less 1, times its least
  # radius: not the distance, but 0 at the surface, and with a slope of
  # at most 1, as the distance has. So the range of the values in a ball
  # is the value at its center, less and more its radius (`cell/4`): the
  # short formula of the first step of Newton has no such limit, and a
  # thin ellipsoid lost the cells with their centers in its middle plane.
  defp local(:ellipsoid, {rx, ry, rz}, {x, y, z}) do
    {ax, ay, az} = {x / rx, y / ry, z / rz}
    k0 = :math.sqrt(ax * ax + ay * ay + az * az)

    if k0 <= 1.0 do
      (k0 - 1.0) * min(rx, min(ry, rz))
    else
      {ux, uy, uz} = {rx * abs(x), ry * abs(y), rz * abs(z)}
      {sx, sy, sz} = {rx * rx, ry * ry, rz * rz}
      t = root(max(max(ux - sx, uy - sy), max(uz - sz, 0.0)), ux, uy, uz, sx, sy, sz, 8)
      {dx, dy, dz} = {x * t / (sx + t), y * t / (sy + t), z * t / (sz + t)}
      :math.sqrt(dx * dx + dy * dy + dz * dz)
    end
  end

  # The superellipsoid: its norm of the power `e`, less 1, times its least
  # radius. For `e` of 2 or more, its gradient is never longer than 1 over
  # the least radius, so the value is a bound.
  defp local(:superellipsoid, {rx, ry, rz, e}, {x, y, z}) do
    n = :math.pow(:math.pow(abs(x / rx), e) + :math.pow(abs(y / ry), e) + :math.pow(abs(z / rz), e), 1.0 / e)
    (n - 1.0) * Enum.min([rx, ry, rz])
  end

  # The wedge, the prism and the pyramid: the most of the distances to
  # the planes of their faces. Inside and at a face it is the distance; at
  # an edge or a corner it is less (a bound, with a slope of at most 1).

  # The wedge: a box with a slope from its top edge at the back (y = -hy)
  # to its bottom edge at the front (y = hy).
  defp local(:wedge, {hx, hy, hz}, {x, y, z}) do
    slope = (hz * y + hy * z) / :math.sqrt(hz * hz + hy * hy)
    Enum.max([abs(x) - hx, -y - hy, -z - hz, slope])
  end

  # The prism: `n` sides round z, each `r` from the axis, from z = -h to z = h.
  defp local(:prism, {r, h, n}, {x, y, z}) do
    sides = for i <- 0..(round(n) - 1), a = 2 * :math.pi() * i / n, do: x * :math.cos(a) + y * :math.sin(a) - r
    Enum.max([abs(z) - h | sides])
  end

  # The pyramid: a base of 2 hx by 2 hy at z = -h, and its point at z = h.
  defp local(:pyramid, {hx, hy, h}, {x, y, z}) do
    side = fn across, half -> (2 * h * abs(across) + half * (z - h)) / :math.sqrt(4 * h * h + half * half) end
    Enum.max([-z - h, side.(x, hx), side.(y, hy)])
  end

  # The extrude: the distance to the outline in its plane and the
  # distance to its two flat ends, as for a box; the outline and the
  # ends are in by the radius of the edges, and the shape is out by it.
  defp local(:extrude, {points, h, r}, {x, y, z}) do
    d = outline(points, x, y, false) + r
    w = abs(z) - h + r
    min(max(d, w), 0.0) + :math.sqrt(sq(max(d, 0.0)) + sq(max(w, 0.0))) - r
  end

  # The revolve: the distance to the profile in the half plane of the point.
  defp local(:revolve, {points}, {x, y, z}), do: outline(points, :math.sqrt(x * x + y * y), z, true)

  defp local(:tube, {[a | rest], [ra | radii]}, p) do
    {d, _, _} =
      Enum.zip(rest, radii)
      |> Enum.reduce({@far, a, ra}, fn {b, rb}, {d, a, ra} -> {min(d, round_cone(p, a, b, ra, rb)), b, rb} end)

    if rest == [], do: Vec.len(Vec.sub(p, a)) - ra, else: d
  end

  # The distance from a point of a plane to a closed outline (less than
  # 0 inside): the least distance to a side, and inside when a line from
  # the point to the right crosses an odd count of sides. With `axis?`
  # (a profile that turns round the axis), a side on the axis is not a
  # side of the shape: the inside goes through the axis.
  defp outline([first | _] = points, px, py, axis?) do
    {square, inside} = sides(points, first, px, py, {@far, false}, axis?)
    if inside, do: -:math.sqrt(square), else: :math.sqrt(square)
  end

  # (Each side from a point to the next one, and from the last to the first.)
  defp sides([a], first, px, py, so_far, axis?), do: side(a, first, px, py, so_far, axis?)

  defp sides([a, b | rest], first, px, py, so_far, axis?),
    do: sides([b | rest], first, px, py, side(a, b, px, py, so_far, axis?), axis?)

  defp side({ax, _}, {bx, _}, _px, _py, so_far, true) when ax == 0.0 and bx == 0.0, do: so_far

  defp side({ax, ay}, {bx, by}, px, py, {least, inside}, _axis?) do
    {ex, ey} = {bx - ax, by - ay}
    {wx, wy} = {px - ax, py - ay}
    long = ex * ex + ey * ey
    t = if long > 0.0, do: min(max((wx * ex + wy * ey) / long, 0.0), 1.0), else: 0.0
    {dx, dy} = {wx - ex * t, wy - ey * t}
    crosses = ay > py != by > py and px < ax + ex * (py - ay) / ey
    {min(least, dx * dx + dy * dy), if(crosses, do: not inside, else: inside)}
  end

  # A step of Newton for the root of the nearest point of an ellipsoid.
  defp root(t, _ux, _uy, _uz, _sx, _sy, _sz, 0), do: t

  defp root(t, ux, uy, uz, sx, sy, sz, steps) do
    {qx, qy, qz} = {t + sx, t + sy, t + sz}
    {a, b, c} = {ux / qx, uy / qy, uz / qz}
    f = a * a + b * b + c * c - 1.0

    if f <= 1.0e-12,
      do: t,
      else: root(t + f / (2.0 * (a * a / qx + b * b / qy + c * c / qz)), ux, uy, uz, sx, sy, sz, steps - 1)
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
