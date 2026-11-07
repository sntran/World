defmodule World.Skills.Lamp do
  @moduledoc """
  The skill `lamp` of a electrician (plan 0002, D5): The lamps of a vehicle from shape data: at each level (detail `always`, unless the data gives another).
  Its data: `shapes`, `ports`, `mass`, `sources`, `detail`, `inside`
  (`World.Skills.Vehicle`).
  """
  @behaviour World.Skill
  alias World.Skills.Vehicle

  @impl true
  def name, do: "lamp"

  @impl true
  def trade, do: :electrician

  @impl true
  def check(data, path), do: Vehicle.check_part(data, path)

  @impl true
  def estimate(data, level), do: Vehicle.estimate(data, level)

  @impl true
  def make(data, _inputs, %{name: name}),
    do: {Vehicle.part(Map.put_new(data, "detail", "always"), name, :light), %{}, %{}}
end
