defmodule World.Skills.Lantern do
  @moduledoc """
  The skill `lantern` of a smith: the top of a tower (`World.Skills.Towers`):
  the drum with its door, the lantern with its panes in frames and its
  lens, the dome, the ball, the lightning rod, and the rail of the
  gallery (posts and two rails at near, one low wall at mid). Only the
  drum, the glass and the dome at far. Its data: `meshes`.
  """
  @behaviour World.Skill
  alias World.{Frame, Mesh, Shape}
  alias World.Skills.Towers

  @names ~w(height gallery gallery_width rail drum lantern_from lantern_to lantern_width panes rod)

  @impl true
  def name, do: "lantern"

  @impl true
  def trade, do: :smith

  @impl true
  def check(data, path), do: Towers.check(data, path, @names)

  @impl true
  def estimate(data, level) do
    sides = %{near: 32, mid: 16, far: 8}[level]
    panes = Map.get(data, "panes", 10)
    rest = %{near: 24 * panes + 1_200, mid: 24 * panes + 400, far: 0}[level]
    16 * sides + rest
  end

  @impl true
  def make(data, _inputs, %{level: level}), do: {nil, %{"meshes" => top(Towers.o(data, @names), level)}, %{}}

  defp top(o, level) do
    sides = %{near: 32, mid: 16, far: 8}[level]
    {la, lb, ld} = o.lantern
    {rg, rd, rl} = {o.gallery_width / 2, o.drum / 2, ld / 2}
    z = o.gallery

    drum = Shape.cylinder(rd, la - z, :white, sides: sides, frame: Frame.move({0.0, 0.0, z})) |> Mesh.matter(:concrete)

    glass =
      Shape.cylinder(rl - 0.03, lb - la, :glass, sides: max(o.panes, 6), frame: Frame.move({0.0, 0.0, la}))
      |> Mesh.matter(:glass)

    dome =
      Shape.lathe(
        [{rl + 0.12, lb}, {rl + 0.12, lb + 0.08}] ++
          for(
            i <- 1..6,
            t = i / 6 * :math.pi() / 2,
            do: {(rl + 0.05) * :math.cos(t) + 0.001, lb + 0.08 + (o.height - lb - 0.08) * :math.sin(t)}
          ) ++
          [{0.0, o.height}],
        :white,
        sides: sides
      )
      |> Mesh.matter(:steel)

    rest =
      if level == :far do
        []
      else
        frames =
          for k <- 0..(o.panes - 1) do
            a = 2 * :math.pi() * (k + 0.5) / o.panes
            {x, y} = {rl * :math.cos(a), rl * :math.sin(a)}
            Shape.cylinder(0.035, lb - la, :white, sides: 6, frame: Frame.move({x, y, la})) |> Mesh.matter(:steel)
          end

        ball =
          Shape.sphere(0.15, :white, rings: 6, sides: 12)
          |> Mesh.transform(Frame.move({0.0, 0.0, o.height}))
          |> Mesh.matter(:steel)

        rod =
          Shape.cylinder(0.02, o.rod - o.height, :steel, sides: 6, frame: Frame.move({0.0, 0.0, o.height + 0.1}))
          |> Mesh.matter(:steel)

        lens =
          Shape.cylinder(0.45, 1.0, :glass, sides: 12, frame: Frame.move({0.0, 0.0, la + 0.4})) |> Mesh.matter(:glass)

        door = Shape.box({-0.35, rd - 0.02, z}, {0.35, rd + 0.03, z + 1.8}, :dark) |> Mesh.matter(:steel)
        frames ++ [ball, rod, lens, door] ++ rail(o, rg - 0.1, z, level)
      end

    [drum, glass, dome | rest]
  end

  defp rail(o, r, z, :mid) do
    [
      Shape.lathe([{r - 0.06, z}, {r, z}, {r, z + o.rail}, {r - 0.06, z + o.rail}], :white, kind: :ring, sides: 24)
      |> Mesh.matter(:steel)
    ]
  end

  defp rail(o, r, z, _near) do
    n = round(2 * :math.pi() * r / 0.6)

    posts =
      for k <- 0..(n - 1) do
        a = 2 * :math.pi() * k / n
        Shape.cylinder(0.025, o.rail, :white, sides: 6, frame: Frame.move({r * :math.cos(a), r * :math.sin(a), z}))
      end

    tube = for k <- 0..7, a = 2 * :math.pi() * k / 8, do: {r + 0.025 * :math.cos(a), 0.025 * :math.sin(a)}

    rails =
      for h <- [o.rail * 0.5, o.rail] do
        Shape.lathe(Enum.map(tube, fn {rr, zz} -> {rr, zz + z + h} end), :white, kind: :ring, sides: 48)
      end

    Enum.map(posts ++ rails, &Mesh.matter(&1, :steel))
  end
end
