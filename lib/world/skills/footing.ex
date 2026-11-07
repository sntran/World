defmodule World.Skills.Footing do
  @moduledoc """
  The skill `footing` of a concreter: the footings of a house and the
  slab of its ground floor (`World.Skills.House`, the node `plan`; the
  parts under the ground only at near): a pad
  of 0.9 by 0.9 m and 0.3 m under each column (an estimate of a house of
  two to four floors on firm ground, TCVN 9362:2012 is the code of the
  design), its neck up to the ground beams, the ground beams of 0.3 m
  along the lines of the columns, and the slab of 0.1 m over them. The
  root of a house.
  """
  @behaviour World.Skill
  alias World.Skills.House

  @impl true
  def name, do: "footing"

  @impl true
  def trade, do: :concreter

  @impl true
  def check(data, path), do: World.Skill.keys(data, path, [])

  @impl true
  def estimate(_data, _level), do: 600

  @impl true
  def make(_data, %{"plan" => %{"plan" => plan}}, %{level: level, name: name}) do
    {hw, hd, c} = {plan.width / 2, plan.depth / 2, plan.column}
    slab = [House.box({-hw, -hd, -0.1}, {hw, hd, 0.0}, :concrete, :concrete)]

    under =
      if level != :near do
        []
      else
        pads =
          for {x, y} <- House.columns(plan) do
            [
              House.box({x - 0.45, y - 0.45, -1.2}, {x + 0.45, y + 0.45, -0.9}, :concrete, :concrete),
              House.box({x - c / 2, y - c / 2, -0.9}, {x + c / 2, y + c / 2, -0.4}, :concrete, :concrete)
            ]
          end

        sides =
          for x <- [-(hw - c / 2), hw - c / 2],
              do: House.box({x - c / 2, -hd, -0.4}, {x + c / 2, hd, -0.1}, :concrete, :concrete)

        List.flatten(pads) ++ sides
      end

    sources = ["The footings: pads of 0.9 by 0.9 m under the columns, an estimate of a house of two to four floors."]

    {House.part(name, slab ++ under, sources), %{},
     %{"surface" => %{"corners" => [[-hw, -hd], [hw, -hd], [-hw, hd], [hw, hd]]}}}
  end
end
