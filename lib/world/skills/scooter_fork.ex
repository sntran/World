defmodule World.Skills.ScooterFork do
  @moduledoc """
  The skill `scooter_fork` of a mechanic: the fork, the front fender, the bars with their grips, levers and mirrors, and the front wheel on its axle bolt
  (`World.Skills.Scooter`). Its data: `model`.
  """
  @behaviour World.Skill
  alias World.Skills.Scooter

  @impl true
  def name, do: "scooter_fork"

  @impl true
  def trade, do: :mechanic

  @impl true
  def check(data, path), do: Scooter.check(data, path)

  @impl true
  def estimate(_data, :near), do: 3000
  def estimate(_data, _level), do: 750

  @impl true
  def make(data, _inputs, _context), do: Scooter.make(data, "fork")
end
