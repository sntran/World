defmodule World.Skills.Column do
  @moduledoc """
  The skill `column` of a concreter: the columns of a floor of a house
  (`World.Skills.House`): `column` m square at each side at each end of
  the bays, from the slab under the floor to the beams over it, poured in
  their forms. None at far: the faces of the walls hide them.
  """
  @behaviour World.Skill
  alias World.Skills.House

  @names ~w(floor)

  @impl true
  def name, do: "column"

  @impl true
  def trade, do: :concreter

  @impl true
  def check(data, path), do: House.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 12 * 10

  @doc "The concrete of the columns of the floor, with 150 kg of rebar in each m³ (an estimate)."
  @impl true
  def materials(data, %{"plan" => %{"plan" => plan}}) do
    o = House.o(data, @names)
    h = House.top(plan, o.floor) - plan.beam - House.bottom(plan, o.floor)
    House.concrete(length(House.columns(plan)) * plan.column * plan.column * h, 150)
  end

  @impl true
  def make(_data, _inputs, %{level: :far}), do: {nil, %{}, %{}}

  def make(data, %{"plan" => %{"plan" => plan}}, %{name: name}) do
    o = House.o(data, @names)
    {z0, z1, c} = {House.bottom(plan, o.floor), House.top(plan, o.floor) - plan.beam, plan.column}

    meshes =
      for {x, y} <- House.columns(plan),
          do: House.box({x - c / 2, y - c / 2, z0}, {x + c / 2, y + c / 2, z1}, :concrete, :concrete)

    sources = [
      "The columns: #{round(c * 1000)} mm square, of reinforced concrete (TCVN 5574:2018 is the code of the design; the size is an estimate of a tube house)."
    ]

    {House.part(name, meshes, sources), %{}, %{}}
  end
end
