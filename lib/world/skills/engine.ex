defmodule World.Skills.Engine do
  @moduledoc """
  The skill `engine` of a mechanic (plan 0002, D5): An engine from shape data, with its mass from its data sheet (`mass`) and its ports: the pivot and the axle of a swing arm unit, the port of its shock.
  Its data: `shapes`, `ports`, `mass`, `sources`, `detail`, `inside`
  (`World.Skills.Vehicle`).
  """
  @behaviour World.Skill
  alias World.Skills.Vehicle

  @impl true
  def name, do: "engine"

  @impl true
  def trade, do: :mechanic

  @impl true
  def check(data, path), do: Vehicle.check_part(data, path)

  @impl true
  def estimate(data, level), do: Vehicle.estimate(data, level)

  @impl true
  def make(data, _inputs, %{name: name}), do: {Vehicle.part(data, name, :engine), %{}, %{}}
end
