defmodule World.Skills.Flight do
  @moduledoc """
  The skill `flight` of a concreter: the straight stair of a floor of a
  house to the floor over it (`World.Skills.House`), along the left wall
  from the back, inside the line of the columns: risers of at most 0.17
  m and treads of 0.26 m (TCVN 4451:2012 gives the risers and the treads
  of a stair of a house), `stair_width` m wide, each step solid, with a
  rail of steel at the open side. None on the top floor, and only at near (it is inside).
  """
  @behaviour World.Skill
  alias World.{Frame, Mesh, Shape}
  alias World.Skills.House

  @names ~w(floor)
  @tread 0.26

  @impl true
  def name, do: "flight"

  @impl true
  def trade, do: :concreter

  @impl true
  def check(data, path), do: House.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 12 * 22 + 200

  @doc "The well of the stair of a floor in the slab over it: `{x0, x1, y0, y1}`."
  def well(plan, floor) do
    {x0, x1, y0, n, _} = steps(plan, floor)
    {x0, x1, y0 + max(n - 11, 0) * @tread, y0 + n * @tread}
  end

  defp steps(plan, floor) do
    {z0, z1} = {House.bottom(plan, floor), House.top(plan, floor)}
    n = ceil((z1 - z0) / 0.17)
    x0 = -plan.width / 2 + plan.column
    {x0, x0 + plan.stair_width, -plan.depth / 2 + plan.column + 0.4, n, (z1 - z0) / n}
  end

  @impl true
  def make(data, %{"plan" => %{"plan" => plan}}, %{name: name, level: level}) do
    o = House.o(data, @names)

    if o.floor >= plan.floors or level != :near do
      {nil, %{}, %{}}
    else
      {x0, x1, y0, n, rise} = steps(plan, o.floor)
      z0 = House.bottom(plan, o.floor)

      treads =
        for i <- 0..(n - 1) do
          House.box({x0, y0 + i * @tread, z0}, {x1, y0 + (i + 1) * @tread, z0 + (i + 1) * rise}, :concrete, :concrete)
        end

      line = for i <- [0, n], do: {x1 - 0.05, y0 + i * @tread, z0 + i * rise + 0.9}

      posts =
        for i <- 0..n//3,
            do:
              Shape.cylinder(0.015, 0.9, :iron,
                sides: 6,
                frame: Frame.move({x1 - 0.05, y0 + (i + 0.5) * @tread, z0 + (i + 1) * rise})
              )

      rail = Enum.map([Shape.sweep(line, 0.02, :iron, sides: 6) | posts], &Mesh.matter(&1, :steel))

      sources = ["The stair: #{n} risers of #{Float.round(rise * 100, 1)} cm and treads of 26 cm (TCVN 4451:2012)."]
      {House.part(name, treads ++ rail, sources), %{}, %{}}
    end
  end
end
