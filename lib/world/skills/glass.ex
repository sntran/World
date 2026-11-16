defmodule World.Skills.Glass do
  @moduledoc """
  The skill `glass` of a glazier (plan 0002, D5): The glass of a vehicle from shape data: the windows of a car, a screen.
  Its data: `shapes`, `ports`, `mass`, `sources`, `detail`, `inside`
  (`World.Skills.Vehicle`).
  """
  @behaviour World.Skill
  alias World.Skills.Vehicle

  @impl true
  def name, do: "glass"

  @impl true
  def trade, do: :glazier

  @impl true
  def check(data, path), do: Vehicle.check_part(data, path)

  @impl true
  def estimate(data, level), do: Vehicle.estimate(data, level)

  @impl true
  def make(data, _inputs, %{name: name}), do: {Vehicle.part(data, name, :glass), %{}, %{}}
end
