defmodule World.Skills.Halo do
  @moduledoc """
  The skill `halo` of a smith: the halo of a statue behind the head of
  its figure (the node `figure`): a ring with the three arms of a cross
  to the head, and the metal rays out of it round the top half (one up,
  the lightning rod, when their count is odd; the rest to each side, 10
  degrees apart from 10 under the level; by eye from the photos). No arms
  and no rays at far. Its data: `meshes` (none with `halo` false).

  With `ring` (plan 0005), the halo is where the measures put it: the
  center of the ring at `center` [y, z] (m, over the feet), its radius and
  the radius of its tube, leaning `lean` degrees to the front (its top
  over the head), with a cross of four arms that get wider to the ring,
  `rods` upright rods on its top and the other rays at its two sides.
  """
  @behaviour World.Skill
  alias World.{Frame, Mesh, Shape, Vec}
  alias World.Skills.Statue

  @names ~w(material halo rays ring)

  @impl true
  def name, do: "halo"

  @impl true
  def trade, do: :smith

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  # The ring of 8 sides round its tube, the arms, and the rays of 6 sides.
  @impl true
  def estimate(data, level) do
    sides = %{near: 24, mid: 12, far: 8}[level]
    rays = if level == :far, do: 0, else: 24 * Map.get(data, "rays", 9) + 36
    16 * sides + rays
  end

  @impl true
  def make(data, %{"figure" => %{"figure" => fig}}, %{level: level}) do
    o = Statue.o(data, @names)

    meshes =
      cond do
        not o.halo -> []
        o.ring -> measured(o, level)
        true -> halo(fig, o, level)
      end

    {nil, %{"meshes" => meshes}, %{}}
  end

  # The halo of the measures: built in the plane x-z round its center,
  # then turned to the front by its lean.
  defp measured(%{ring: %{"center" => [y, z], "radius" => r, "tube" => t, "lean" => lean, "rods" => n}} = o, level) do
    {look, matter} = Statue.material(o.material)
    a = lean * :math.pi() / 180
    place = Frame.new({0.0, y / 1, z / 1}, {0.0, :math.sin(a), :math.cos(a)}, {0.0, :math.cos(a), -:math.sin(a)})
    sides = %{near: 48, mid: 16, far: 8}[level]
    tube = for k <- 0..7, b = 2 * :math.pi() * k / 8, do: {r - t + t * :math.cos(b), t * :math.sin(b)}
    flat = Frame.new({0.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0})
    ring = Shape.lathe(tube, look, kind: :ring, sides: sides, frame: flat)

    # Each arm: from 0.3 of the radius, 0.5 m wide, to the ring, 1.5 m wide.
    arms =
      for {dx, dz} <- [{1.0, 0.0}, {-1.0, 0.0}, {0.0, 1.0}, {0.0, -1.0}], level != :far do
        {r0, r1, w0, w1} = {0.3 * r, r - t, 0.25, 0.75}
        loop = [{r0, -w0}, {r1, -w1}, {r1, w1}, {r0, w0}]
        # In the frame below, local x is -x: the loop goes in with -u.
        pts = for {u, v} <- loop, do: {-(dx * u - dz * v), dz * u + dx * v}
        Shape.prism(pts, 2 * t, look, frame: Frame.new({0.0, -t, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}))
      end

    stone = Enum.map([ring | arms], &(&1 |> Mesh.transform(place) |> Mesh.matter(matter)))
    top = Frame.point(place, {0.0, 0.0, r})
    left = Frame.point(place, {-r, 0.0, 0.0})
    right = Frame.point(place, {r, 0.0, 0.0})
    stone ++ metal(o.rays, n, top, left, right, level)
  end

  # The rods upright on the top, 0.4 m apart, the middle one the longest;
  # the other rays out of the two sides, spread over 24 degrees.
  defp metal(_rays, _n, _top, _left, _right, :far), do: []

  defp metal(rays, n, top, left, right, _level) do
    rod = fn at, len ->
      Shape.cylinder(0.05, len, :steel, sides: 6, frame: Frame.new(at, {0.0, 0.0, 1.0}, {0.0, 1.0, 0.0}))
    end

    rods =
      for i <- 0..(n - 1)//1 do
        off = (i - (n - 1) / 2) * 0.4
        rod.(Vec.add(top, {off, 0.0, -0.05}), if(off == 0.0, do: 1.5, else: 1.1))
      end

    per = div(max(rays - n, 0), 2)

    side =
      for {at, sx} <- [{left, -1.0}, {right, 1.0}], i <- 0..(per - 1)//1 do
        deg = if per == 1, do: 0.0, else: -12.0 + 24.0 * i / (per - 1)
        b = deg * :math.pi() / 180
        d = {sx * :math.cos(b), 0.0, :math.sin(b)}
        Shape.cylinder(0.04, 1.6, :steel, sides: 6, frame: Frame.new(at, d, {0.0, 1.0, 0.0}))
      end

    Enum.map(rods ++ side, &Mesh.matter(&1, :steel))
  end

  defp halo(%{halo: {r, {_, y, zc}}, scale: s}, o, level) do
    {look, matter} = Statue.material(o.material)
    t = 0.016 * s
    sides = %{near: 24, mid: 12, far: 8}[level]
    frame = Frame.new({0.0, y - t, zc}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0})
    tube = for k <- 0..7, a = 2 * :math.pi() * k / 8, do: {r - t + t * :math.cos(a), t * :math.sin(a)}
    ring = Shape.lathe(tube, look, kind: :ring, sides: sides, frame: frame) |> Mesh.matter(matter)

    arms =
      for {dx, dz} <- [{-1.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}], level != :far do
        {a, b} = {0.45 * r, r - t}
        p0 = {dx * a - abs(dz) * t, y - 2 * t, zc + dz * a - abs(dx) * t}
        p1 = {dx * b + abs(dz) * t, y, zc + dz * b + abs(dx) * t}
        {{x0, y0, z0}, {x1, y1, z1}} = Vec.bounds([p0, p1])
        Shape.box({x0, y0, z0}, {x1, y1, z1}, look) |> Mesh.matter(matter)
      end

    arms ++ [ring | rays(r, {0.0, y - t, zc}, s, o.rays, level)]
  end

  defp rays(_, _, _, _, :far), do: []

  defp rays(r, c, s, n, _level) do
    up = if rem(n, 2) == 1, do: [{90.0, 0.12}], else: []
    side = for i <- 0..(div(n, 2) - 1)//1, a = -10.0 + 10.0 * i, deg <- [a, 180.0 - a], do: {deg, 0.08}

    for {deg, len} <- up ++ side do
      a = deg * :math.pi() / 180
      d = {:math.cos(a), 0.0, :math.sin(a)}

      Shape.cylinder(0.0016 * s, len * s, :steel,
        sides: 6,
        frame: Frame.new(Vec.add(c, Vec.scale(d, r)), d, {0.0, 1.0, 0.0})
      )
      |> Mesh.matter(:steel)
    end
  end
end
