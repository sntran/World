defmodule World.Skills.Iron do
  @moduledoc """
  The skill `iron` of a smith: the rail of the balcony over a floor of a
  house (`World.Skills.House`): 1.0 m high at the edge of the balcony,
  a top rail and a bottom rail of 40 by 20 mm, and bars of 16 mm 0.12 m
  apart (the clear gap under 0.1 m, an estimate of a safe rail). None
  over the top floor, with no balcony, or at far.
  """
  @behaviour World.Skill
  alias World.Skills.House

  @names ~w(floor)

  @impl true
  def name, do: "iron"

  @impl true
  def trade, do: :smith

  @impl true
  def check(data, path), do: House.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 500

  @impl true
  def make(data, %{"plan" => %{"plan" => plan}}, %{name: name, level: level}) do
    o = House.o(data, @names)

    if o.floor >= plan.floors or plan.balcony <= 0 or level == :far do
      {nil, %{}, %{}}
    else
      {hw, hd, z} = {plan.width / 2, plan.depth / 2, House.top(plan, o.floor)}
      y = hd + plan.balcony - 0.03
      box = fn a, b -> House.box(a, b, :iron, :steel) end

      rails = [
        box.({-hw, y - 0.01, z}, {hw, y + 0.01, z + 0.04}),
        box.({-hw, y - 0.01, z + 0.96}, {hw, y + 0.01, z + 1.0})
      ]

      n = round(plan.width / 0.12)

      bars =
        for k <- 1..(n - 1)//1,
            level == :near,
            x = -hw + k * plan.width / n,
            do: box.({x - 0.008, y - 0.008, z + 0.04}, {x + 0.008, y + 0.008, z + 0.96})

      ends = for x <- [-hw + 0.01, hw - 0.01], do: box.({x - 0.01, hd, z}, {x + 0.01, y, z + 1.0})
      sources = ["The rail: 1.0 m high, bars of 16 mm 0.12 m apart (estimates)."]
      {House.part(name, rails ++ bars ++ ends, sources), %{}, %{}}
    end
  end
end
