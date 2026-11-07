defmodule World.Skills.Swingarm do
  @moduledoc """
  The skill `swingarm` of a welder (plan 0002, D5): A swing arm of tubes from shape data, with its ports `pivot`, `axle` and `shock`.
  Its data: `shapes`, `ports`, `mass`, `sources`, `detail`, `inside`
  (`World.Skills.Vehicle`).
  """
  @behaviour World.Skill
  alias World.Skills.Vehicle

  @impl true
  def name, do: "swingarm"

  @impl true
  def trade, do: :welder

  @impl true
  def check(data, path), do: Vehicle.check_part(data, path)

  @impl true
  def estimate(data, level), do: Vehicle.estimate(data, level)

  @impl true
  def make(data, _inputs, %{name: name}), do: {Vehicle.part(data, name, :swingarm), %{}, %{}}
end
