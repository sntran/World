defmodule World.Skills.CastField do
  @moduledoc """
  The skill `cast_field` of a caster: the field of a cast from its pours
  (the nodes `from` with `distances`, `World.Cast.merge/1` and
  `World.Cast.field/4`). With `hollow`, at near, the walls of `wall` m
  (at the least two cells) and the openings: the `windows` in the front
  of the robe, a balcony at each shoulder, and the shaft of the stair
  round the well of `well` m (the node `figure` gives the marks). Its
  data: `grid` (the cells, for the stair) and `surface` (the grid with
  no saddle, for the slabs of the shell); nil with no survey.
  """
  @behaviour World.Skill
  alias World.Cast
  alias World.Skills.Statue

  @names ~w(hollow wall well windows)

  @impl true
  def name, do: "cast_field"

  @impl true
  def trade, do: :caster

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(_data, %{"survey" => %{"survey" => nil}}, _context), do: {nil, %{"grid" => nil, "surface" => nil}, %{}}

  def make(data, %{"survey" => %{"survey" => s}, "outside" => out, "figure" => %{"figure" => fig}} = inputs, ctx) do
    o = Statue.o(data, @names)
    pours = for name <- ctx.from, d = inputs[name]["distances"], do: d
    grid = Cast.field(s, out["marks"], out["outside"], Cast.merge(pours))

    grid =
      if o.hollow and ctx.level == :near,
        do: Cast.hollow(grid, max(o.wall, 2 * s.step), openings(fig, o, s.step)),
        else: grid

    {nil, %{"grid" => grid, "surface" => Cast.surface(grid)}, %{}}
  end

  # The openings of a hollow statue: the windows in the front of the robe,
  # a balcony in the top of each arm near the shoulder, and the shaft of
  # the stair down to the plinth.
  defp openings(%{marks: m, scale: s}, o, step) do
    xs = abs(elem(m["upperarm_l"], 0))
    za = elem(m["upperarm_l"], 2)
    r = o.well / 2 + 0.8

    windows = for {z, w, h} <- o.windows, do: {{-w / 2, 0.0, z - h / 2}, {w / 2, 50.0, z + h / 2}}

    balconies =
      for side <- [-1.0, 1.0] do
        {x0, x1} = {side * (xs + 1.0), side * (xs + 2.5)}
        {{min(x0, x1), -0.8, za}, {max(x0, x1), 0.8, za + 10.0}}
      end

    yc = 0.01 * s
    shaft = {{-r, yc - r, -2.0 * step}, {r, yc + r, 2.5 * step}}
    windows ++ balconies ++ [shaft]
  end
end
