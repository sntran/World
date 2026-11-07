defmodule World.Skills.ScooterStand do
  @moduledoc """
  The skill `scooter_stand` of a smith: the center stand on its pivot
  (`World.Skills.Scooter`). Its data: `model`.
  """
  @behaviour World.Skill
  alias World.Skills.Scooter

  @impl true
  def name, do: "scooter_stand"

  @impl true
  def trade, do: :smith

  @impl true
  def check(data, path), do: Scooter.check(data, path)

  @impl true
  def estimate(_data, :near), do: 100
  def estimate(_data, _level), do: 25

  @impl true
  def make(data, _inputs, _context), do: Scooter.make(data, "stand")
end
