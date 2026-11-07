defmodule World.Skills.ScooterSeat do
  @moduledoc """
  The skill `scooter_seat` of a upholsterer: the seat on its hinge
  (`World.Skills.Scooter`). Its data: `model`.
  """
  @behaviour World.Skill
  alias World.Skills.Scooter

  @impl true
  def name, do: "scooter_seat"

  @impl true
  def trade, do: :upholsterer

  @impl true
  def check(data, path), do: Scooter.check(data, path)

  @impl true
  def estimate(_data, :near), do: 300
  def estimate(_data, _level), do: 75

  @impl true
  def make(data, _inputs, _context), do: Scooter.make(data, "seat")
end
