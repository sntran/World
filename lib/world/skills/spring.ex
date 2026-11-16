defmodule World.Skills.Spring do
  @moduledoc """
  The skill `spring` of a smith (plan 0002, D5): a coil spring from its
  spec sheet (`World.Materials.Stock.spring/6`): `diameter`, `wire`,
  `length`, `turns`, `material`, and `inside` (a spring that a body
  hides). Its ports: `end_a` and `end_b`.
  """
  @behaviour World.Skill
  import World.Orders.Blueprint, only: [option: 3]
  alias World.Materials.Stock
  alias World.Skills.Vehicle

  @impl true
  def name, do: "spring"

  @impl true
  def trade, do: :smith

  defp options,
    do: [
      option("diameter", :number, min: 0.005, max: 0.5, unit: "m"),
      option("wire", :number, min: 0.0005, max: 0.05, unit: "m"),
      option("length", :number, min: 0.01, max: 1.0, unit: "m"),
      option("turns", :integer, min: 2, max: 40),
      option("material", :choice, default: "steel", values: ~w(steel paint black chrome)),
      option("inside", :boolean, default: false)
    ]

  @impl true
  def check(data, path), do: Vehicle.check(data, path, options())

  @impl true
  def estimate(_data, _level), do: 600

  @impl true
  def make(data, _inputs, %{name: name}) do
    o = Vehicle.o(data, options())
    material = String.to_existing_atom(o["material"])
    part = Stock.spring(o["diameter"], o["wire"], o["length"], o["turns"], material, name: name)
    {%{part | inside: o["inside"]}, %{}, %{}}
  end
end
