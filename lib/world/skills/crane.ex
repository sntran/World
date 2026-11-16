defmodule World.Skills.Crane do
  @moduledoc """
  The skill `crane` of a rigger (plan 0006, D6 and D9): the tower crane of
  a site of today, which lifts the forms, the steel and the concrete to
  each band. A lattice mast of 1.6 m on a foundation block at `at` (`[x,
  y]`, m, in the frame of the lot), its jib `height` m over the ground
  (over the top of the model), a jib of `jib` m and a counter jib of a
  third of it with its counterweight, the cab at the top, the trolley
  and the line of the hook; the jib turns `turn` degrees from +x. The
  sizes are those of a small flat top tower crane (an estimate). The part
  is temporary: the stream shows it, the model leaves it out.
  """
  @behaviour World.Skill
  alias World.{Part, Shape}
  alias World.Orders.Blueprint
  import Blueprint, only: [option: 3]

  @mast 1.6
  @panel 2.0
  @chord 0.08
  @brace 0.05

  defp options do
    [
      option("height", :number, default: 45.0, min: 10.0, max: 120.0, unit: "m"),
      option("jib", :number, default: 40.0, min: 10.0, max: 80.0, unit: "m"),
      option("at", :data, default: [0.0, 0.0], check: &point/2),
      option("turn", :number, default: 0.0, min: -360.0, max: 360.0, unit: "deg")
    ]
  end

  defp point([x, y], _path) when is_number(x) and is_number(y), do: {:ok, [x / 1, y / 1]}
  defp point(_v, path), do: {:error, [{path, "must be a point [x, y] in m"}]}

  @impl true
  def name, do: "crane"

  @impl true
  def trade, do: :rigger

  @impl true
  def check(data, path) do
    case Blueprint.check_options(options(), data, path) do
      {:ok, _} -> []
      {:error, errors} -> errors
    end
  end

  @impl true
  def estimate(_data, :far), do: 0
  def estimate(_data, _level), do: 3_000

  @impl true
  def make(data, _inputs, %{name: name}) do
    {:ok, o} = Blueprint.check_options(options(), data, "")
    [x, y] = o["at"]
    h = o["height"]
    a = o["turn"] * :math.pi() / 180
    {c, s} = {:math.cos(a), :math.sin(a)}
    # A point of the crane: `u` along the jib, `v` across it, `z` up.
    at = fn u, v, z -> {x + u * c - v * s, y + u * s + v * c, z} end
    half = @mast / 2

    corners = [{-half, -half}, {half, -half}, {half, half}, {-half, half}]
    chords = for {u, v} <- corners, do: tube(at.(u, v, 0.0), at.(u, v, h), @chord)

    braces =
      for k <- 0..(floor(h / @panel) - 1),
          {{u0, v0}, {u1, v1}} <- Enum.zip(corners, tl(corners) ++ [hd(corners)]) do
        {z0, z1} = {k * @panel, min((k + 1) * @panel, h)}

        if rem(k, 2) == 0,
          do: tube(at.(u0, v0, z0), at.(u1, v1, z1), @brace),
          else: tube(at.(u1, v1, z0), at.(u0, v0, z1), @brace)
      end

    {jib, counter} = {o["jib"], o["jib"] / 3}

    block = box(at, {-2.5, -2.5, -1.5}, {2.5, 2.5, 0.0}, :concrete)
    weight = box(at, {-counter, -1.0, h - 2.0}, {-counter + 3.0, 1.0, h}, :concrete)
    cab = box(at, {half, half, h - 2.2}, {half + 2.0, half + 2.0, h - 0.2}, :white)
    trolley = jib * 0.6
    line = tube(at.(trolley, 0.0, h - 0.6), at.(trolley, 0.0, h * 0.55), 0.03)

    shapes = [block, weight, cab, line] ++ chords ++ braces ++ boom(at, 0.0, jib, h) ++ boom(at, -counter, 0.0, h)
    {Part.new(name, :part, shapes, [Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})]), %{"temporary" => true}, %{}}
  end

  # A jib of a triangle of chords along u from `from` to `to`, at the
  # height `h` (its foot), with a brace each panel.
  defp boom(at, from, to, h) do
    w = 0.6
    bottom = fn u -> [at.(u, -w, h), at.(u, w, h)] end
    top = fn u -> at.(u, 0.0, h + 1.2) end
    n = max(1, ceil((to - from) / @panel))
    us = for k <- 0..n, do: from + (to - from) * k / n
    [[l0, r0], [l1, r1]] = [bottom.(from), bottom.(to)]

    [tube(l0, l1, @chord), tube(r0, r1, @chord), tube(top.(from), top.(to), @chord)] ++
      for [u0, u1] <- Enum.chunk_every(us, 2, 1, :discard),
          [l, r] = bottom.(u0),
          t <- [tube(l, top.(u1), @brace), tube(r, top.(u1), @brace)],
          do: t
  end

  defp tube(a, b, r), do: Shape.sweep([a, b], r, :orange, sides: 4)

  # A box between two points of the crane (its sides on the axes: a small
  # block).
  defp box(at, {u0, v0, z0}, {u1, v1, z1}, material) do
    {{ax, ay, az}, {bx, by, bz}} = {at.(u0, v0, z0), at.(u1, v1, z1)}
    Shape.box({min(ax, bx), min(ay, by), min(az, bz)}, {max(ax, bx), max(ay, by), max(az, bz)}, material)
  end
end
