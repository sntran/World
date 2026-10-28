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
  def z_low(%__MODULE__{} = h, d) do
    base = at(h.front_lower, d, :min) || at(h.back_lower, h.length - d, :min) || h.sill

    Enum.reduce(h.arches, base, fn {ad, az, r}, acc ->
      dd = abs(d - ad)
      if dd < r, do: max(acc, az + :math.sqrt(r * r - dd * dd)), else: acc
    end)
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
    {zl, zh, hw} = grown(h, d, delta)
    {cr, cl} = h.crown
    height = zh - zl
    rb = max(min(h.bottom, height * 0.2), 0.004)
    rt = h.edge + (cr - h.edge) * max(0.0, 1 - d / cl)
    rt = max(min(rt, min(hw * 0.9, height * 0.45)), 0.004)
    span = h.top - h.edge - h.belt
    lean = if zh > h.belt and span > 0, do: h.lean * min(1.0, (zh - h.belt) / span), else: 0.0
    zb = min(max(zl + rb + 0.002, min(h.belt, zh - rt - 0.002)), zh - rt - 0.001)
    n = %{near: 8, mid: 2, far: 1}[Detail.level()]

    right =
      [{0.0, zl}] ++
        arc({hw - rb, zl + rb}, rb, -90, 0, n) ++
        [{hw, zb}] ++ arc({hw - lean - rt, zh - rt}, rt, 0, 90, n) ++ [{0.0, zh}]

    left = for {x, z} <- right |> Enum.reverse() |> Enum.drop(1) |> Enum.drop(-1), do: {-x, z}
    right ++ left
  end

  # The bottom, the top and the half width at `d` of the hull grown by
  # `delta` in each direction: the most of each within `delta` along the
  # length, and `delta` more. So a skin covers a face of the body that
  # looks to the front or to the back, as a face that looks to a side.
  defp grown(h, d, delta) when delta == 0, do: {z_low(h, d), z_high(h, d), half_width(h, d)}

  defp grown(h, d, delta) do
    {d0, d1} = span(h)
    ds = for i <- -2..2, e = d + delta * i / 2, e >= d0 and e <= d1, do: e
    ds = if ds == [], do: [min(max(d, d0), d1)], else: ds

    {Enum.min(Enum.map(ds, &z_low(h, &1))) - delta, Enum.max(Enum.map(ds, &z_high(h, &1))) + delta,
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

  defp cut(loop, plane) do
    f =
      case plane do
        {:x_min, v} -> fn {x, _} -> v - x end
        {:x_max, v} -> fn {x, _} -> x - v end
        {:z_min, v} -> fn {_, z} -> v - z end
        {:z_max, v} -> fn {_, z} -> z - v end
        {:le, a, b, c} -> fn {x, z} -> a * x + b * z - c end
      end

    loop
    |> Enum.zip(tl(loop) ++ [hd(loop)])
    |> Enum.flat_map(fn {{x1, z1} = a, {x2, z2} = b} ->
      {fa, fb} = {f.(a), f.(b)}
      cross = fn -> {x1 + (x2 - x1) * fa / (fa - fb), z1 + (z2 - z1) * fa / (fa - fb)} end

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
    zmin = loop |> Enum.map(&elem(&1, 1)) |> Enum.min()

    start =
      loop
      |> Enum.with_index()
      |> Enum.filter(fn {{_, z}, _} -> z - zmin < 1.0e-6 end)
      |> Enum.max_by(fn {{x, _}, _} -> x end)
      |> elem(1)

    loop = Enum.drop(loop, start) ++ Enum.take(loop, start)
    sides = Enum.zip(loop, tl(loop) ++ [hd(loop)])
    lens = for {{x1, z1}, {x2, z2}} <- sides, do: :math.sqrt((x2 - x1) ** 2 + (z2 - z1) ** 2)
    total = Enum.sum(lens)

    if length(loop) <= k,
      do: split(sides, lens, k - length(loop), total),
      else: walk(Enum.zip(sides, lens), for(i <- 0..(k - 1), do: total * i / k), 0.0, [])
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
  def stations(%__MODULE__{} = h, d0, d1, step) do
    n = max(round((d1 - d0) / Detail.step(step)), 1)
    even = for i <- 0..n, do: d0 + (d1 - d0) * i / n

    profile =
      Enum.map(h.front_upper ++ h.front_lower, &elem(&1, 0)) ++
        Enum.map(h.back_upper ++ h.back_lower, &(h.length - elem(&1, 0)))

    coarse = %{near: 1, mid: 2, far: 4}[Detail.level()]
    arches = for {ad, _, r} <- h.arches, k <- -12..12//coarse, do: ad + r * :math.sin(k * :math.pi() / 24)
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

  defp resample_if(loop, k), do: if(area(loop) > 1.0e-7, do: resample(loop, k), else: loop)

  @doc "The area of a loop."
  def area(loop) when length(loop) < 3, do: 0.0

  def area(loop) do
    loop
    |> Enum.zip(tl(loop) ++ [hd(loop)])
    |> Enum.reduce(0.0, fn {{x1, z1}, {x2, z2}}, acc -> acc + x1 * z2 - x2 * z1 end)
    |> Kernel./(2)
    |> abs()
  end
end
