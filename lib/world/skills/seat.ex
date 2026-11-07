defmodule World.Skills.Seat do
  @moduledoc """
  The skill `seat` of a upholsterer (plan 0002, D5): A seat from shape data: a saddle, the seat of a scooter or of a motorcycle.
  Its data: `shapes`, `ports`, `mass`, `sources`, `detail`, `inside`
  (`World.Skills.Vehicle`).
  """
  @behaviour World.Skill
  alias World.Skills.Vehicle

  @impl true
  def name, do: "seat"

  @impl true
  def trade, do: :upholsterer

  @impl true
  def check(data, path), do: Vehicle.check_part(data, path)

  @impl true
  def estimate(data, level), do: Vehicle.estimate(data, level)

  @impl true
  def make(data, _inputs, %{name: name}), do: {Vehicle.part(data, name, :seat), %{}, %{}}
end
