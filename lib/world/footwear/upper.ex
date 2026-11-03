defmodule World.Footwear.Upper do
  @moduledoc """
  The upper of a shoe on its last: the paths of its straps on the foot,
  and the parts that fix them. Each path is a list of points for
  `World.Materials.Webbing.strap/4` (a strap of webbing, leather or
  rubber); `top` is the height of the top of the sole at y
  (`World.Footwear.Sole.stack/3`).

  - `over/4`: a strap over the foot at a part of its length, its ends on
    the sole; with `closure: true` its outside end goes straight down, for
    a closure (`closure/5`).
  - `heel/4`: a strap round the back of the heel, between two points.
  - `thong/2`: the Y of a thong: a post between the first two toes and a
    strap from it to each side.
  - `cross/3`: two straps that cross over the front of the foot.
  - `band/4`: one wide strap over the front of the foot, its ends on the
    sides of the sole.
  - `closure/5`: a D-ring, hook and loop and the end of the strap folded
    back, or a pin buckle, at the outside end of a strap.
  - `nails/3` and `plugs/3`: the nails that fix a strap to the side of a
    sole of wood, and the plugs of a molded strap through the sole.
  """
  alias World.{Frame, Mesh, Part, Shape}
  alias World.Footwear.Last
  alias World.Materials.Webbing

  @doc """
  A strap over the foot at a part of its length, 3 mm out from the sides
  of the foot and 4 mm over its top. The options: `high` (the most height
  of its top over the ground: the front of the ankle) and `closure` (the
  outside end straight down, from 35 to 12 mm over the sole).
  """
  def over(%Last{} = last, part, top, opts \\ []) do
    {y, xa, xb, foot} = Last.at(last, part)
    z0 = top.(y)
    peak = min(foot, Keyword.get(opts, :high, foot)) + 0.004

    if Keyword.get(opts, :closure, false) do
      xo = xb + 0.003
      (arch(y, xa - 0.003, xo, peak, z0) |> Enum.drop(-3)) ++ [{xo, y, z0 + 0.035}, {xo, y, z0 + 0.012}]
    else
      arch(y, xa - 0.003, xb + 0.003, peak, z0)
    end
  end

  @doc """
  A strap round the back of the heel, `height` over the sole, 4 mm out
  from the foot, from the point `from` (on the outside) to the point `to`
  (on the inside).
  """
  def heel(%Last{} = last, top, {from, to}, height) do
    back = Last.back(last, 0.12)
    zh = top.(0.0) + height
    {_, ba, bb, _} = hd(back)
    outside = for {y, _, b, _} <- Enum.reverse(back), do: {b + 0.004, y, zh}
    inside = for {y, a, _, _} <- back, do: {a - 0.004, y, zh}
    [from] ++ outside ++ [{(ba + bb) / 2, 0.0, zh}] ++ inside ++ [to]
  end

  @doc """
  The Y of a thong: `%{post: path, straps: [inside, outside]}`. The post
  goes up 18 mm from the sole at the gap of the toes; each strap goes from
  the top of the post over the foot to a side of the sole at 55% of the
  length of the foot (by eye from the photos). The options: `at` (the
  place `{x, y}` of the post) and `to` (the part of the length of the
  foot where the straps end).
  """
  def thong(%Last{} = last, top, opts \\ []) do
    {gx, gy} = Keyword.get_lazy(opts, :at, fn -> Last.toe_gap(last) end)
    {y, xa, xb, foot} = Last.at(last, Keyword.get(opts, :to, 0.55))
    z = top.(gy)
    knot = {gx, gy, z + 0.018}

    # Each strap is a smooth curve (a quadratic Bézier) from the knot, over
    # the foot, to its side.
    side = fn x ->
      {kx, ky, kz} = knot
      {mx, my, mz} = {(gx + x) / 2, (gy + y) / 2, min(foot, z + 0.03) + 0.006}
      {ex, ey, ez} = {x, y, top.(y) + 0.004}

      for i <- 0..8, s = i / 8 do
        b = fn a, m, e -> (1 - s) ** 2 * a + 2 * (1 - s) * s * m + s ** 2 * e end
        {b.(kx, mx, ex), b.(ky, my, ey), b.(kz, mz, ez)}
      end
    end

    %{post: [{gx, gy, z - 0.004}, knot], straps: [side.(xa - 0.002), side.(xb + 0.002)]}
  end

  @doc """
  Two straps that cross over the front of the foot: one from the inside
  at 60% of the length of the foot to the outside at 82%, and one from
  the outside at 60% to the inside at 82%; each end goes through a slit
  in the sole, `depth` down from its top.
  """
  def cross(%Last{} = last, top, depth) do
    {y0, a0, b0, _} = Last.at(last, 0.6)
    {y1, a1, b1, _} = Last.at(last, 0.82)
    {_, _, _, foot} = Last.at(last, 0.71)

    strap = fn {x0, ya}, {x1, yb} ->
      for i <- 0..10, s = i / 10 do
        y = ya + (yb - ya) * s
        z0 = top.(y)

        {x0 + (x1 - x0) * s, y,
         z0 - depth * (1 - :math.sin(:math.pi() * s) ** 0.2) + (foot + 0.004 - z0) * :math.sin(:math.pi() * s) ** 0.5}
      end
    end

    [strap.({a0 - 0.002, y0}, {b1 + 0.002, y1}), strap.({b0 + 0.002, y0}, {a1 - 0.002, y1})]
  end

  @doc """
  A lattice over the front of the foot, from the part `p0` to the part
  `p1` of its length: rods of the radius `r` in two families of diagonal
  lines (`n` of each) and a rod round its edge, on a surface 4 mm over the
  foot (and `high` over the ground at most), its ends on the sides of the
  sole. The holes are diamonds (the honeycomb of a dép tổ ong, by eye). A
  list of paths.
  """
  def lattice(%Last{} = last, {p0, p1}, top, n, high \\ :infinity) do
    point = fn s, part ->
      {y, xa, xb, foot} = Last.at(last, part)
      z0 = top.(y)
      peak = min(foot, high) + 0.004
      {xa - 0.003 + (xb - xa + 0.006) * s, y, z0 + (peak - z0) * :math.sin(:math.pi() * s) ** 0.5}
    end

    line = fn f -> for i <- 0..12, t = i / 12, do: f.(t) end
    span = fn t -> p0 + (p1 - p0) * t end

    diagonals =
      for k <- -n..n, sign <- [1, -1] do
        line.(fn t -> {min(max((k + t * n) / n, 0.0), 1.0), t} end)
        |> Enum.map(fn {s, t} -> if(sign > 0, do: {s, t}, else: {1 - s, t}) end)
        |> Enum.dedup()
      end
      |> Enum.filter(fn pts -> length(pts) > 2 end)
      |> Enum.map(fn pts -> Enum.map(pts, fn {s, t} -> point.(s, span.(t)) end) end)

    edges = [
      line.(&point.(&1, p0)),
      line.(&point.(&1, p1)),
      line.(&point.(0.0, span.(&1))),
      line.(&point.(1.0, span.(&1)))
    ]

    edges ++ diagonals
  end

  @doc """
  One wide strap over the front of the foot at a part of its length:
  from the side of the sole on the inside, over the foot 4 mm over its
  top, to the side of the sole on the outside, its ends `drop` down the
  side of the sole from its top (where the nails go).
  """
  def band(%Last{} = last, part, top, {side, drop}) do
    {y, xa, xb, foot} = Last.at(last, part)
    z0 = top.(y)
    ends = fn x -> {x, y, z0 - drop} end
    [ends.(xa - side)] ++ arch(y, xa - side + 0.001, xb + side - 0.001, foot + 0.004, z0) ++ [ends.(xb + side)]
  end

  @doc """
  The closure of a strap at the end of the path `path` (straight down the
  outside, `over/4` with `closure: true`): `[{name, part, port}]`, the
  parts and the ports of the strap they go on. With `leather: true`, a
  pin buckle; else a D-ring, a patch of hook and loop and the end of the
  strap folded back on it (`strap` makes the end of the strap). `t` is
  the thickness of the strap and `w` its width.
  """
  def closure(name, path, {w, t}, leather, strap) do
    [{xo, y, za}, {_, _, zb}] = Enum.take(path, -2)
    z0 = zb - 0.012

    if leather do
      down = Frame.new({xo + t / 2 + 0.0015, y, za}, {1, 0, 0}, {0, 1, 0})
      [{"buckle_#{name}", Webbing.pin_buckle("buckle_#{name}", w, frame: down)}]
    else
      ring = Frame.new({xo - 0.004, y, z0 + 0.01}, {0, 0, 1}, {0, 1, 0})
      patch = Frame.new({xo + t / 2 + 0.0005, y, za}, {1, 0, 0}, {0, 1, 0})
      x_fold = xo + t + 0.0035

      [
        {"ring_#{name}", Webbing.d_ring("ring_#{name}", w, frame: ring)},
        {"patch_#{name}", Webbing.hook_loop("patch_#{name}", w, 0.02, frame: patch)},
        {"fold_#{name}", strap.("fold_#{name}", [{x_fold, y, zb}, {x_fold, y, za + 0.001}])}
      ]
    end
  end

  @doc "The port of a part of a closure that goes on the strap."
  def port_of(%Part{kind: :strap}), do: "a"
  def port_of(_), do: "o"

  @doc """
  The nails that fix the ends of a strap of the width `w` and the
  thickness `t` to the sides of a sole: `n` nails on each end, 2 mm
  across and 12 mm long, into the sole, with a head of 4 mm (by eye from
  the photos). The ends are the first and the last point of `path`. The
  meshes go into the part of the strap: the nails join the strap to the
  sole.
  """
  def nails(path, {w, t}, n) do
    heads =
      for {{x, y, z}, sign} <- [{hd(path), -1}, {List.last(path), 1}], i <- 1..n do
        p = {x + sign * t / 2, y - w / 2 + w * i / (n + 1), z}
        Shape.cylinder(0.002, 0.0015, :steel, sides: 8, frame: Frame.new(p, {sign, 0, 0}, {0, 0, 1}))
      end

    shanks =
      for {{x, y, z}, sign} <- [{hd(path), -1}, {List.last(path), 1}], i <- 1..n do
        p = {x, y - w / 2 + w * i / (n + 1), z}
        Shape.cylinder(0.001, 0.012, :steel, sides: 6, frame: Frame.new(p, {-sign, 0, 0}, {0, 0, 1}))
      end

    Enum.map(heads ++ shanks, &Mesh.matter(&1, :steel))
  end

  @doc """
  The plugs of a molded strap: a round plug of 8 mm, `depth` down into
  the sole from each point (and 1 mm over the ground at most), of the
  material of the strap.
  """
  def plugs(points, depth, {role, matter}) do
    for {x, y, z} <- points do
      bottom = max(z - depth, 0.001)

      Shape.cylinder(0.004, z - bottom, role, sides: 12, frame: Frame.new({x, y, bottom}, {0, 0, 1}, {0, 1, 0}))
      |> Mesh.matter(matter)
    end
  end

  # A strap over the foot at y, from x0 to x1, its top at `peak`, its ends
  # on the sole (z0).
  defp arch(y, x0, x1, peak, z0) do
    for i <- 0..10, s = i / 10, do: {x0 + (x1 - x0) * s, y, z0 + (peak - z0) * :math.sin(:math.pi() * s) ** 0.5}
  end
end
