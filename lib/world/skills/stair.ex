defmodule World.Skills.Stair do
  @moduledoc """
  The skill `stair` of a mason: the spiral stair inside a hollow statue,
  at near, in the cells of its cast (the nodes `figure` and `shell`). By
  eye from the photo of its inside: `steps` treads of 30 degrees (12 to a
  turn) round an open well of `well` m with a rail at its edge, each from
  the well to the wall and 0.1 m into the wall, from the plinth to the
  floor of the shoulders, its feet `feet` m over the ground. With
  `base_room` (`World.Skills.Base`), the stair starts on the floor of the
  room in the base (0.6 m over the ground) and goes up through the plinth:
  the people go in at the door of the base and up to the arms. The part
  `cau_thang` (nil when the statue is not hollow, or not at near).
  """
  @behaviour World.Skill
  alias World.{Cast, Frame, Mesh, Part, Shape}
  alias World.Skills.Statue

  @names ~w(hollow steps well feet base_room)

  @impl true
  def name, do: "stair"

  @impl true
  def trade, do: :mason

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  # Each tread a prism of 16 triangles, a post of 6 sides for each third,
  # and the rail.
  @impl true
  def estimate(data, :near), do: if(data["hollow"], do: 26 * Map.get(data, "steps", 133) + 300, else: 0)
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, %{"figure" => %{"figure" => fig}, "shell" => %{"grid" => grid}}, %{level: level}) do
    o = Statue.o(data, @names)

    if o.hollow and level == :near do
      part = stair_part(fig, o, grid)
      up = Frame.move({0.0, 0.0, o.feet})
      {%{part | shapes: Enum.map(part.shapes, &Mesh.transform(&1, up))}, %{}, %{}}
    else
      {nil, %{}, %{}}
    end
  end

  defp stair_part(%{marks: m, scale: s}, o, grid) do
    r = o.well / 2
    top = elem(m["upperarm_l"], 2) - 0.5
    # The floor of the first step: the plinth, or the floor of the room.
    from = if o.base_room, do: 0.6 - o.feet, else: 0.0
    rise = (top - from) / o.steps
    yc = 0.01 * s
    pt = fn rr, a, z -> {rr * :math.cos(a), yc + rr * :math.sin(a), z} end

    wall = fn a, z ->
      Enum.find(Enum.map(1..120, &(r + 0.05 * &1)), r + 1.0, &Cast.inside?(grid, pt.(&1, a, z))) + 0.1
    end

    treads =
      for i <- 0..(o.steps - 1) do
        {a0, a1, z} = {i * :math.pi() / 6, (i + 1) * :math.pi() / 6, from + (i + 1) * rise}
        out = Enum.min(for a <- [a0, (a0 + a1) / 2, a1], do: wall.(a, z - 0.04))

        loop =
          for {rr, a} <- [{r, a0}, {out, a0}, {out, (a0 + a1) / 2}, {out, a1}, {r, a1}],
              do: Tuple.delete_at(pt.(rr, a, 0.0), 2)

        Shape.prism(loop, 0.08, :concrete, frame: Frame.move({0.0, 0.0, z - 0.08})) |> Mesh.matter(:concrete)
      end

    # The rail at the edge of the well: a post on each third tread and a
    # rail on the posts, 0.9 m over the treads.
    posts =
      for i <- 0..(o.steps - 1)//3 do
        {x, y, z} = pt.(r + 0.05, (i + 0.5) * :math.pi() / 6, from + (i + 1) * rise)
        Shape.cylinder(0.02, 0.9, :steel, sides: 6, frame: Frame.move({x, y, z})) |> Mesh.matter(:steel)
      end

    line = for i <- 0..o.steps, do: pt.(r + 0.05, (i + 0.5) * :math.pi() / 6, from + (i + 1) * rise + 0.9)
    rail = Shape.sweep(line, 0.025, :steel, sides: 6) |> Mesh.matter(:steel)

    Part.new("cau_thang", :statue, treads ++ [rail | posts], [Statue.port()],
      params: %{"steps" => o.steps, "rise" => Float.round(rise, 3)},
      sources: [
        "The stair: #{o.steps} steps of #{Float.round(rise * 100, 1)} cm, 12 to a turn, round an open well of #{o.well} m with a rail (by eye from the photo of the inside)."
      ]
    )
  end
end
