defmodule World.Skills.Halo do
  @moduledoc """
  The skill `halo` of a smith: the halo of a statue behind the head of
  its figure (the node `figure`): a ring with the three arms of a cross
  to the head, and the metal rays out of it round the top half (one up,
  the lightning rod, when their count is odd; the rest to each side, 10
  degrees apart from 10 under the level; by eye from the photos). No arms
  and no rays at far. Its data: `meshes` (none with `halo` false).
  """
  @behaviour World.Skill
  alias World.{Frame, Mesh, Shape, Vec}
  alias World.Skills.Statue

  @names ~w(material halo rays)

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
    {nil, %{"meshes" => if(o.halo, do: halo(fig, o, level), else: [])}, %{}}
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
