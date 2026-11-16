defmodule World.Skills.HousePlan do
  @moduledoc """
  The skill `house_plan` of an engineer: the plan of a house for the
  other skills of its site (`World.Skills.House`): its sizes, its floors,
  the grid of its columns, its openings, and the place of its stair. A
  node of data only; each skill of the site takes it in `from`. Its data:
  `plan`.
  """
  @behaviour World.Skill
  alias World.Skills.House

  @names ~w(width depth floors ground storey slab column beam bays wall parapet balcony roof stair_width openings)

  @impl true
  def name, do: "house_plan"

  @impl true
  def trade, do: :engineer

  @impl true
  def check(data, path), do: House.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, _inputs, _context), do: {nil, %{"plan" => House.o(data, @names)}, %{}}
end
