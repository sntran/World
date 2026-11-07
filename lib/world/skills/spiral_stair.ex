defmodule World.Skills.SpiralStair do
  @moduledoc """
  The skill `spiral_stair` of a mason: the spiral stair inside a hollow
  tower at near (`World.Skills.Towers`): a column and `steps` treads, 10
  to a turn, from the platform to the floor of the gallery (an estimate:
  the stair of a lighthouse of this size). The part `cau_thang`, or nil.
  """
  @behaviour World.Skill
  alias World.{Frame, Mesh, Part, Shape}
  alias World.Skills.Towers

  @names ~w(hollow body wall gallery steps platform_height)

  @impl true
  def name, do: "spiral_stair"

  @impl true
  def trade, do: :mason

  @impl true
  def check(data, path), do: Towers.check(data, path, @names)

  @impl true
  def estimate(data, :near), do: if(data["hollow"], do: 16 * Map.get(data, "steps", 55) + 48, else: 0)
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, _inputs, %{level: level}) do
    o = Towers.o(data, @names)
    {if(o.hollow and level == :near, do: stair(o, o.platform_height)), %{}, %{}}
  end

  defp stair(o, z0) do
    ri = o.body / 2 - o.wall
    rise = (o.gallery - z0) / o.steps

    column =
      Shape.cylinder(0.12, o.gallery - z0, :concrete, sides: 12, frame: Frame.move({0.0, 0.0, z0}))
      |> Mesh.matter(:concrete)

    treads =
      for i <- 0..(o.steps - 1) do
        {a0, a1} = {i * :math.pi() / 5, (i + 1) * :math.pi() / 5}
        p = fn rr, a -> {rr * :math.cos(a), rr * :math.sin(a)} end
        loop = [p.(0.12, a0), p.(ri, a0), p.(ri, (a0 + a1) / 2), p.(ri, a1), p.(0.12, a1)]

        Shape.prism(loop, 0.06, :concrete, frame: Frame.move({0.0, 0.0, z0 + (i + 1) * rise - 0.06}))
        |> Mesh.matter(:concrete)
      end

    Part.new("cau_thang", :tower, [column | treads], [Towers.port()],
      params: %{"steps" => o.steps, "rise" => Float.round(rise, 3)},
      sources: ["The stair: #{o.steps} steps of #{Float.round(rise * 100, 1)} cm round a column, 10 to a turn."]
    )
  end
end
