defmodule Xuong.Models.Hull do
  @moduledoc """
  The hull of a van: its body from a side profile, a plan and a section.

  - **The side profile** comes from traces of drawings and of photos: the
    front line (from the bottom of the front bumper, up the nose, over
    the hood and the windshield to the roof) and the back line (from the
    roof down the back to the bottom of the back bumper). A point of the
    front line is `{d, z}`: `d` back from the front, `z` up from the
    ground. A point of the back line is `{e, z}`, with `e` from the back.
    Between them the roof is flat, and under the body the sill is flat,
    with an arch over each wheel.
  - **The plan**: the nose and the tail are round when you look from
    above (a superellipse of a depth and a power).
  - **The section**: the sides are upright to the belt, then lean in to
    the round edge of the roof. The edge of the top is more round at the
    nose (the crown), so the hood falls to the lamps at its sides.

  `ring/3` gives the section at a distance `d` from the front, and
  `skin/4` a solid over a range of `d`: the body, or a skin on a region
  of it (a window, a bumper, a band), out from the body by an offset.
  The model is in the axes of Xưởng with its back at y = 0: a point at
  `d` is at y = length - d.
  """
  alias Xuong.{Detail, Shape}

  defstruct length: 0.0,
            width: 0.0,
            top: 0.0,
            front_upper: [],
            front_lower: [],
            back_upper: [],
            back_lower: [],
            sill: 0.38,
            arches: [],
            belt: 1.2,
            lean: 0.0,
            edge: 0.1,
            crown: {0.1, 1.0},
            nose: {0.3, 2.2},
            tail: {0.1, 4.0},
            bottom: 0.04

  @doc """
  A hull from its numbers:

  - `length`, `width`, `top` (the height of the roof);
  - `front` and `back`: the two lines of the side profile (`{d, z}` and
    `{e, z}`), each from the bottom of its bumper over to the roof, or
    from the roof down to the bottom of the bumper;
  - `sill`: the bottom of the body between the wheels;
  - `arches`: `{d, z, radius}` of each wheel, with `d` of its axle;
  - `belt`, `lean`, `edge`: the section (`lean` is how far each side is
    in at the edge of the roof);
  - `crown`: `{radius, length}`: the edge of the top at the front is this
    radius, and it is `edge` at `length` back from the front;
  - `nose`, `tail`: `{depth, power}` of the plan.
  """
  def new(opts) do
    {fu, fl} = split_front(Keyword.fetch!(opts, :front))
    {bu, bl} = split_back(Keyword.fetch!(opts, :back))

    struct!(
      %__MODULE__{front_upper: fu, front_lower: fl, back_upper: bu, back_lower: bl},
      Keyword.drop(opts, [:front, :back])
    )
  end

  # The front line goes forward from the bottom of the bumper to the
  # front of the nose (its lower branch), then back over the hood (its
  # upper branch).
  defp split_front(line) do
    i = line |> Enum.with_index() |> Enum.min_by(fn {{d, _}, _} -> d end) |> elem(1)
    {Enum.drop(line, i), Enum.take(line, i + 1)}
  end

  # The back line goes down from the roof to the back of the bumper (its
  # upper branch), then forward under it (its lower branch).
  defp split_back(line) do
    i = line |> Enum.with_index() |> Enum.min_by(fn {{e, _}, _} -> e end) |> elem(1)
    {Enum.take(line, i + 1), Enum.drop(line, i)}
  end

  # The z of a line at a distance, with the most (or the least) of its
  # segments over it, or nil.
  defp at(line, d, pick) do
    zs =
      for [{d1, z1}, {d2, z2}] <- Enum.chunk_every(line, 2, 1, :discard),
          d >= min(d1, d2) - 1.0e-9 and d <= max(d1, d2) + 1.0e-9,
          z <- if(abs(d2 - d1) < 1.0e-9, do: [z1, z2], else: [z1 + (z2 - z1) * (d - d1) / (d2 - d1)]),
          do: z

    if zs == [], do: nil, else: apply(Enum, pick, [zs])
  end

  @doc "The first and the last `d` of the hull: the front of its nose and the back of its tail."
  def span(%__MODULE__{} = h) do
    {h.front_upper |> Enum.map(&elem(&1, 0)) |> Enum.min(),
     h.length - (h.back_upper |> Enum.map(&elem(&1, 0)) |> Enum.min())}
  end

  @doc "The top of the hull at `d`, on its center line."
  def z_high(%__MODULE__{} = h, d) do
    at(h.front_upper, d, :max) || at(h.back_upper, h.length - d, :max) || h.top
  end

  @doc "The bottom of the hull at `d`: the bumpers, the sill and the arches."
  def z_low(%__MODULE__{} = h, d, arches \\ true) do
    base = at(h.front_lower, d, :min) || at(h.back_lower, h.length - d, :min) || h.sill
    arch = if arches, do: arch(h, d), else: nil
    if arch, do: max(base, arch), else: base
  end

  @doc "The top of the arch of a wheel at `d`, or nil away from the wheels."
  def arch(%__MODULE__{} = h, d) do
    zs = for {ad, az, r} <- h.arches, abs(d - ad) < r, do: az + :math.sqrt(r * r - (d - ad) * (d - ad))
    if zs == [], do: nil, else: Enum.max(zs)
  end

  @doc """
  The back face at the height `z`: its distance from the back end (the
  smallest, when the back has more than one face there), or nil.
  """
  def back(%__MODULE__{} = h, z) do
    h.back_upper |> Enum.map(fn {u, z} -> {z, u} end) |> at(z, :min)
  end

  @doc "Half the width of the hull at `d`: the plan of the nose and of the tail."
  def half_width(%__MODULE__{width: w, length: l, nose: {nd, np}, tail: {td, tp}}, d) do
    w / 2 * min(plan(d, nd, np), plan(l - d, td, tp))
  end

  defp plan(u, depth, _p) when u >= depth, do: 1.0
  defp plan(u, depth, p), do: :math.pow(1 - :math.pow((depth - max(u, 0.0)) / depth, p), 1 / p)

  @doc """
  The section of the hull at `d`: a convex loop of points `{x, z}`,
  counterclockwise when you look from the front. Each section has the
  same points in the same places: the bottom, its round corners, the
  sides, the round edges of the top, the top. So the sections of a body
  join with no twist.
  """
  def section(%__MODULE__{} = h, d, delta \\ 0.0) do
    right = half(h, d, delta)
    left = for {x, z} <- right |> Enum.reverse() |> Enum.drop(1) |> Enum.drop(-1), do: {-x, z}
    right ++ left
  end

  @doc """
  The right half of the section at `d`: from the middle of the bottom,
  around the right side, to the middle of the top. A `delta` under 0
  gives the inner face of a sheet of that thickness.
  """
  def half(%__MODULE__{} = h, d, delta \\ 0.0, arches \\ true, arc \\ %{near: 8, mid: 2, far: 1}) do
    {zl, zh, hw} = grown(h, d, delta, arches)
    {cr, cl} = h.crown
    height = zh - zl
    rb = max(min(h.bottom, height * 0.2), 0.004)
    rt = h.edge + (cr - h.edge) * max(0.0, 1 - d / cl)
    rt = max(min(rt, min(hw * 0.9, height * 0.45)), 0.004)
    span = h.top - h.edge - h.belt
    lean = if zh > h.belt and span > 0, do: h.lean * min(1.0, (zh - h.belt) / span), else: 0.0
    zb = min(max(zl + rb + 0.002, min(h.belt, zh - rt - 0.002)), zh - rt - 0.001)
    n = arc[Detail.level()]

    [{0.0, zl}] ++
      arc({hw - rb, zl + rb}, rb, -90, 0, n) ++
      [{hw, zb}] ++ arc({hw - lean - rt, zh - rt}, rt, 0, 90, n) ++ [{0.0, zh}]
  end

  # The bottom, the top and the half width at `d` of the hull grown by
  # `delta` in each direction: the most of each within `delta` along the
  # length, and `delta` more. So a skin covers a face of the body that
  # looks to the front or to the back, as a face that looks to a side.
  defp grown(h, d, delta, arches) when delta == 0, do: {z_low(h, d, arches), z_high(h, d), half_width(h, d)}

  # The inner face of a sheet: the least of each within `-delta` along
  # the length, and `-delta` less. So the back, which stands almost
  # upright, has the thickness of the sheet too.
  defp grown(h, d, delta, arches) when delta < 0 do
    {d0, d1} = span(h)
    ds = for i <- -2..2, e = d - delta * i / 2, e >= d0 and e <= d1, do: e
    ds = if ds == [], do: [min(max(d, d0), d1)], else: ds

    {Enum.max(Enum.map(ds, &z_low(h, &1, arches))) - delta, Enum.min(Enum.map(ds, &z_high(h, &1))) + delta,
     Enum.min(Enum.map(ds, &half_width(h, &1))) + delta}
  end

  defp grown(h, d, delta, arches) do
    {d0, d1} = span(h)
    ds = for i <- -2..2, e = d + delta * i / 2, e >= d0 and e <= d1, do: e
    ds = if ds == [], do: [min(max(d, d0), d1)], else: ds

    {Enum.min(Enum.map(ds, &z_low(h, &1, arches))) - delta, Enum.max(Enum.map(ds, &z_high(h, &1))) + delta,
     Enum.max(Enum.map(ds, &half_width(h, &1))) + delta}
  end

  defp arc({cx, cz}, r, a0, a1, n) do
    for i <- 0..n, a = (a0 + (a1 - a0) * i / n) * :math.pi() / 180, do: {cx + r * :math.cos(a), cz + r * :math.sin(a)}
  end

  @doc """
  The part of a loop on one side of a line (Sutherland and Hodgman):
  `{:x_min, v}` keeps x >= v, and so `:x_max`, `:z_min`, `:z_max`;
  `{:le, a, b, c}` keeps a * x + b * z <= c.
  """
  def clip(loop, []), do: loop
  def clip([], _), do: []
  def clip(loop, [plane | rest]), do: clip(cut(loop, plane), rest)

  # A point is `{x, z}`, or `{x, z, s}` with its place `s` along the
  # loop of a sheet; a new point on a line gets its place between the two
  # places.
  defp cut(loop, plane) do
    f =
      case plane do
        {:x_min, v} -> fn p -> v - elem(p, 0) end
        {:x_max, v} -> fn p -> elem(p, 0) - v end
        {:z_min, v} -> fn p -> v - elem(p, 1) end
        {:z_max, v} -> fn p -> elem(p, 1) - v end
        {:le, a, b, c} -> fn p -> a * elem(p, 0) + b * elem(p, 1) - c end
      end

    loop
    |> Enum.zip(tl(loop) ++ [hd(loop)])
    |> Enum.flat_map(fn {a, b} ->
      {fa, fb} = {f.(a), f.(b)}

      cross = fn ->
        t = fa / (fa - fb)

        a
        |> Tuple.to_list()
        |> Enum.zip(Tuple.to_list(b))
        |> Enum.map(fn {u, v} -> u + (v - u) * t end)
        |> List.to_tuple()
      end

      cond do
        fa <= 0 and fb <= 0 -> [b]
        fa <= 0 -> [cross.()]
        fb <= 0 -> [cross.(), b]
        true -> []
      end
    end)
  end

  @doc """
  A loop with `k` points, from its lowest point (the outer one, when two
  are as low). A loop of `k` points or fewer keeps its corners: each side
  gets new points in the measure of its length. A longer loop gets `k`
  points at equal steps along it.
  """
  def resample(loop, k) do
    loop = from_lowest(loop)
    sides = Enum.zip(loop, tl(loop) ++ [hd(loop)])
    lens = for {{x1, z1}, {x2, z2}} <- sides, do: :math.sqrt((x2 - x1) ** 2 + (z2 - z1) ** 2)
    total = Enum.sum(lens)

    if length(loop) <= k,
      do: split(sides, lens, k - length(loop), total),
      else: walk(Enum.zip(sides, lens), for(i <- 0..(k - 1), do: total * i / k), 0.0, [])
  end

  defp from_lowest(loop) do
    zmin = loop |> Enum.map(&elem(&1, 1)) |> Enum.min()

    start =
      loop
      |> Enum.with_index()
      |> Enum.filter(fn {{_, z}, _} -> z - zmin < 1.0e-6 end)
      |> Enum.max_by(fn {{x, _}, _} -> x end)
      |> elem(1)

    Enum.drop(loop, start) ++ Enum.take(loop, start)
  end

  defp walk(_, [], _, acc), do: Enum.reverse(acc)

  defp walk([{{{x1, z1}, {x2, z2}}, len} | rest] = sides, [s | more] = ss, at, acc) do
    if s <= at + len or rest == [] do
      t = if len < 1.0e-12, do: 0.0, else: min((s - at) / len, 1.0)
      walk(sides, more, at, [{x1 + (x2 - x1) * t, z1 + (z2 - z1) * t} | acc])
    else
      walk(rest, ss, at + len, acc)
    end
  end

  # Each side gets `extra` new points in the measure of its length: the
  # whole part of its share, then one more for the sides with the largest
  # rest.
  defp split(sides, lens, extra, total) do
    shares = for len <- lens, do: extra * len / max(total, 1.0e-12)
    whole = Enum.map(shares, &trunc/1)
    left = extra - Enum.sum(whole)

    more =
      shares
      |> Enum.with_index()
      |> Enum.sort_by(fn {s, i} -> {-(s - trunc(s)), i} end)
      |> Enum.take(left)
      |> MapSet.new(&elem(&1, 1))

    sides
    |> Enum.with_index()
    |> Enum.flat_map(fn {{{x1, z1}, {x2, z2}}, i} ->
      n = Enum.at(whole, i) + if(MapSet.member?(more, i), do: 1, else: 0)
      for j <- 0..n, do: {x1 + (x2 - x1) * j / (n + 1), z1 + (z2 - z1) * j / (n + 1)}
    end)
  end

  @doc """
  The distances of the sections from `d0` to `d1`: steps of `step`
  (`Xuong.Detail.step/1`), each point of the side profile, points around
  each arch, and points in the round plan of the nose and of the tail,
  at least `Xuong.Detail.step(0.02)` apart. Between them the section
  changes in a straight line, so a long flat side needs few sections.
  """
  def stations(%__MODULE__{} = h, d0, d1, step, arch \\ 1) do
    n = max(round((d1 - d0) / Detail.step(step)), 1)
    even = for i <- 0..n, do: d0 + (d1 - d0) * i / n

    profile =
      Enum.map(h.front_upper ++ h.front_lower, &elem(&1, 0)) ++
        Enum.map(h.back_upper ++ h.back_lower, &(h.length - elem(&1, 0)))

    coarse = %{near: 1, mid: 2, far: 4}[Detail.level()]
    arches = for {ad, _, r} <- h.arches, k <- -12..12//(coarse * arch), do: ad + r * :math.sin(k * :math.pi() / 24)
    {{nd, _}, {td, _}, {_, cl}} = {h.nose, h.tail, h.crown}
    n = div(8, coarse)
    plan = for(i <- 0..n, do: nd * i / n) ++ for(i <- 0..n, do: h.length - td * i / n) ++ [cl]

    (even ++ profile ++ arches ++ plan)
    |> Enum.filter(&(&1 >= d0 and &1 <= d1))
    |> Enum.map(&Float.round(&1 / 1, 4))
    |> Enum.uniq()
    |> Enum.sort()
    |> apart(Detail.step(0.02), d1)
  end

  # The sections at least `gap` apart: the first and the last stay.
  defp apart([first | rest], gap, last) do
    kept =
      Enum.reduce(rest, [first], fn d, [prev | _] = acc -> if d - prev >= gap or d == last, do: [d | acc], else: acc end)

    Enum.reverse(kept)
  end

  @doc """
  A solid of the hull from `d0` to `d1`. The options:

  - `offset`: out from the body (a skin on it), 0 by default; the skin
    can start `offset` before the front of the hull and end `offset` after
    its back;
  - `clip`: a function of `d` to the lines that cut each section
    (`clip/2`), for a region of the body;
  - `sides`: the points of each section of a region (`clip`) (40); the
    sections of the whole body keep the points of `section/2`;
  - `step`: the most step of the sections (0.25 m, `stations/4`);
  - the options of `Xuong.Shape.rings/3`.
  """
  def skin(%__MODULE__{} = h, d0, d1, material, opts \\ []) do
    k = Detail.sides(Keyword.get(opts, :sides, 40))
    delta = Keyword.get(opts, :offset, 0.0)
    planes = Keyword.get(opts, :clip, fn _ -> [] end)

    rings =
      for d <- stations(h, d0, d1, Keyword.get(opts, :step, 0.25)),
          loop = section(h, d, delta),
          cut = planes.(d),
          loop = if(cut == [], do: loop, else: loop |> clip(cut) |> resample_if(k)),
          area(loop) > 1.0e-7 do
        for {x, z} <- loop, do: {x, h.length - d, z}
      end

    Shape.rings(rings, material, Keyword.drop(opts, [:offset, :clip, :sides, :step]))
  end

  @doc """
  A sheet of the hull from `d0` to `d1`, at its right side (`side: 1`)
  or its left side (`side: -1`): the outer face of the hull, and an inner
  face `thickness` (0.03 m) in; with `offset`, the sheet is that far out
  from the hull (a door over a closed body). The `clip` lines (`clip/2`, for the right
  side; the left side takes them in the mirror) cut each section, so a
  sheet is a panel of the body: a side, the roof, a pillar. A door or a
  window is a hole between panels: `holes` is a function of `d` to the
  holes there, each a list of lines; `edges` are the `d` where a hole
  starts or ends. The arches of the wheels are holes at each side,
  `well` (0.3 m) wide. The other options are those of `skin/5`.
  """
  def shell(%__MODULE__{} = h, d0, d1, material, opts \\ []) do
    t = Keyword.get(opts, :thickness, 0.03)
    o = Keyword.get(opts, :offset, 0.0)
    s = Keyword.get(opts, :side, 1)
    planes = Keyword.get(opts, :clip, fn _ -> [] end)
    holes = Keyword.get(opts, :holes, fn _ -> [] end)
    well = Keyword.get(opts, :well, 0.3)
    edges = Keyword.get(opts, :edges, []) ++ for({ad, _, r} <- h.arches, e <- [ad - r, ad + r], do: e)

    # Each piece of a section has a key (which side of which hole it is
    # on), so the same piece joins the same piece at the next section.
    # A piece that is not at a section ends there, with a cap.
    sections =
      for d <- with_edges(stations(h, d0, d1, Keyword.get(opts, :step, 0.25), 2), edges, d0, d1) do
        {loop, n} = sheet(h, d, o, t)
        loop = loop |> Enum.with_index(fn {x, z}, i -> {x, z, i / 1} end) |> clip(planes.(d))
        a = arch(h, d)
        wheel = if a, do: [[{:x_min, half_width(h, d) - well}, {:z_max, a}]], else: []
        mid = h.top / 2
        pieces = for {j, piece} <- split(loop, n, mid), do: {[j], piece}

        for {key, piece} <- cut_holes(pieces, {n, mid}, wheel ++ holes.(d)),
            piece != [],
            piece = from_first(piece),
            area(piece) > 1.0e-7,
            into: %{},
            do: {key, {d, piece}}
      end

    # The sections of a run of one piece join by the places of their
    # points along the sheet (`Xuong.Shape.stitch/3`), so each keeps its
    # corners, and a piece with more points at one section has no twist.
    sections
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.flat_map(fn key ->
      sections
      |> Enum.chunk_by(&Map.has_key?(&1, key))
      |> Enum.filter(&Map.has_key?(hd(&1), key))
      |> Enum.map(fn run -> Enum.map(run, & &1[key]) end)
    end)
    |> Enum.filter(&(length(&1) > 1))
    |> Enum.map(fn run ->
      rings = for {d, piece} <- run, do: for({x, z, p} <- piece, do: {{s * x, h.length - d, z}, p})

      Shape.stitch(
        rings,
        material,
        Keyword.drop(opts, [:thickness, :offset, :side, :clip, :holes, :well, :edges, :step])
      )
    end)
  end

  # The points of each round edge of a sheet, at each level.
  @sheet_arc %{near: 4, mid: 2, far: 1}

  # A piece of a sheet from its point with the least place along the
  # loop of the sheet: so the sections of a piece start at the same place
  # and join with no twist.
  defp from_first(piece) do
    i = piece |> Enum.with_index() |> Enum.min_by(fn {{_, _, s}, _} -> s end) |> elem(1)
    Enum.drop(piece, i) ++ Enum.take(piece, i)
  end

  # The section of a sheet at `d`: the right half of the outer face and
  # of the inner face, with the count of the points of the outer face.
  # Where the hull is thinner than the sheet (at its ends), the sheet is
  # the whole right half, with no inner face (`nil`).
  defp sheet(h, d, o, t) do
    inner = half(h, d, o - t, false, @sheet_arc)
    {_, zl} = hd(inner)
    {_, zh} = List.last(inner)
    {hw, _} = Enum.max_by(inner, &elem(&1, 0))
    outer = half(h, d, o, false, @sheet_arc)
    if zh - zl > 0.002 and hw > 0.002, do: {outer ++ Enum.reverse(inner), length(outer)}, else: {outer, nil}
  end

  # The pieces of a section out of each hole. A hole is a list of lines
  # (`clip/2`); out of it is out of its first line, or in its first line
  # and out of the next, and so on.
  defp cut_holes(pieces, _, []), do: pieces

  defp cut_holes(pieces, {n, mid}, [hole | rest]) do
    pieces
    |> Enum.flat_map(fn {key, loop} ->
      for {line, i} <- Enum.with_index(hole),
          {j, piece} <- split(clip(loop, Enum.take(hole, i) ++ [flip(line)]), n, mid),
          do: {key ++ [i, j], piece}
    end)
    |> cut_holes({n, mid}, rest)
  end

  # A clip of the loop of a sheet keeps the parts of the sheet in the
  # lines, but it joins two parts that a line separates with an edge
  # along that line, from a new point of one face to a new point of the
  # same face (the edge from the sill to the roof across the opening of
  # a door). Here each part is a piece of its own: those edges go, and an
  # end of a part joins the nearest new point of the other face, as the
  # end of a cut sheet does. The key of a piece is its band (`:low` when
  # its lowest point is under `mid`, else `:high`) and its index in the
  # band, so a piece has the same key at the next section also when a
  # piece of the other band is not there.
  defp split(loop, n, mid), do: loop |> split(n) |> Enum.group_by(&band(&1, mid)) |> Enum.flat_map(&keys/1)

  defp band(piece, mid), do: if(piece |> Enum.map(&elem(&1, 1)) |> Enum.min() < mid, do: :low, else: :high)

  defp keys({band, pieces}), do: for({piece, k} <- Enum.with_index(pieces), do: {{band, k}, piece})

  defp split([], _), do: []
  defp split(loop, nil), do: [loop]

  defp split(loop, n) do
    outer? = fn {_, _, p} -> p < n - 0.5 end
    new? = fn {_, _, p} -> p != Float.floor(p) end

    false_edge? = fn {a, b} ->
      new?.(a) and new?.(b) and outer?.(a) == outer?.(b) and
        Float.floor(elem(a, 2)) != Float.floor(elem(b, 2))
    end

    edges = Enum.zip(loop, tl(loop) ++ [hd(loop)])

    case Enum.find_index(edges, false_edge?) do
      nil ->
        [loop]

      i ->
        # The chains between the false edges, from the point after one.
        {before, rest} = Enum.split(edges, i + 1)

        chains =
          (rest ++ before)
          |> Enum.chunk_while(
            [],
            fn {a, _} = e, chain ->
              if false_edge?.(e), do: {:cont, Enum.reverse([a | chain]), []}, else: {:cont, [a | chain]}
            end,
            fn chain -> {:cont, Enum.reverse(chain), []} end
          )
          |> Enum.reject(&(&1 == []))

        chains
        |> join_chains(outer?, [])
        |> Enum.sort_by(fn piece -> piece |> Enum.map(&elem(&1, 2)) |> Enum.min() end)
    end
  end

  # Join each chain to the chain that starts nearest to its end on the
  # other face, until a piece closes.
  defp join_chains([], _, pieces), do: pieces

  defp join_chains([first | _] = chains, outer?, pieces) do
    {piece, left} = close(first, chains -- [first], first, outer?)
    join_chains(left, outer?, [piece | pieces])
  end

  defp close(piece, chains, first, outer?) do
    {x, z, _} = last = List.last(piece)
    far = fn {u, w, _} -> (u - x) ** 2 + (w - z) ** 2 end
    other = Enum.filter(chains, &(outer?.(hd(&1)) != outer?.(last)))

    next =
      case other ++ [first] do
        [_] -> first
        list -> Enum.min_by(list, &far.(hd(&1)))
      end

    if next == first, do: {piece, chains}, else: close(piece ++ next, chains -- [next], first, outer?)
  end

  defp flip({:x_min, v}), do: {:x_max, v}
  defp flip({:x_max, v}), do: {:x_min, v}
  defp flip({:z_min, v}), do: {:z_max, v}
  defp flip({:z_max, v}), do: {:z_min, v}
  defp flip({:le, a, b, c}), do: {:le, -a, -b, -c}

  # The sections just before and just after the ends of the holes, so a
  # piece ends where its hole starts.
  defp with_edges(ds, edges, d0, d1) do
    (ds ++ Enum.flat_map(edges, &[&1 - 1.0e-4, &1 + 1.0e-4]))
    |> Enum.filter(&(&1 >= d0 and &1 <= d1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp resample_if(loop, k), do: if(area(loop) > 1.0e-7, do: resample(loop, k), else: loop)

  @doc "The area of a loop."
  def area(loop) when length(loop) < 3, do: 0.0

  def area(loop) do
    loop
    |> Enum.zip(tl(loop) ++ [hd(loop)])
    |> Enum.reduce(0.0, fn {a, b}, acc -> acc + elem(a, 0) * elem(b, 1) - elem(b, 0) * elem(a, 1) end)
    |> Kernel./(2)
    |> abs()
  end
end
