defmodule World.Skills.Slab do
  @moduledoc """
  The skill `slab` of a concreter: the beams and the slab over a floor of
  a house (`World.Skills.House`), poured at one time as on a real site:
  the slab of `slab` m over the plan, with the well of the stair of the
  floor (not over the top floor), the balcony at the front (`balcony` m,
  not over the top floor), and the beams of `beam` m under it along the
  lines of the columns. At far only the slab of the roof.
  """
  @behaviour World.Skill
  alias World.Buildings.Panel
  alias World.Skills.{Flight, House}

  @names ~w(floor)

  @impl true
  def name, do: "slab"

  @impl true
  def trade, do: :concreter

  @impl true
  def check(data, path), do: House.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 300

  @impl true
  def make(data, %{"plan" => %{"plan" => plan}} = inputs, %{level: :far} = ctx) do
    if House.o(data, @names).floor >= plan.floors, do: make(data, inputs, %{ctx | level: :mid}), else: {nil, %{}, %{}}
  end

  def make(data, %{"plan" => %{"plan" => plan}}, %{name: name}) do
    o = House.o(data, @names)
    {hw, hd, c, z} = {plan.width / 2, plan.depth / 2, plan.column, House.top(plan, o.floor)}
    last = o.floor >= plan.floors

    holes =
      if last do
        []
      else
        {x0, x1, y0, y1} = Flight.well(plan, o.floor)
        [{x0 + hw, y0 + hd, x1 + hw, y1 + hd, 0.0}]
      end

    slab =
      Panel.sheet({-hw, -hd, z}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, plan.width, plan.depth, holes, :concrete,
        skin: {plan.slab, :concrete}
      )

    {zb, zs} = {z - plan.beam, z - plan.slab}
    ys = Enum.uniq(for {_, y} <- House.columns(plan), do: y)

    sides =
      for x <- [-(hw - c / 2), hw - c / 2],
          do: House.box({x - c / 2, -hd, zb}, {x + c / 2, hd, zs}, :concrete, :concrete)

    across = for y <- ys, do: House.box({-hw + c, y - c / 2, zb}, {hw - c, y + c / 2, zs}, :concrete, :concrete)

    balcony =
      if last or plan.balcony <= 0,
        do: [],
        else: [House.box({-hw, hd, z - plan.slab}, {hw, hd + plan.balcony, z}, :concrete, :concrete)]

    sources = [
      "The slab: #{round(plan.slab * 1000)} mm, on beams of #{round(plan.beam * 1000)} mm (TCVN 5574:2018 is the code of the design; the sizes are an estimate of a tube house)."
    ]

    {House.part(name, [slab | sides ++ across ++ balcony], sources), %{}, %{}}
  end
end
