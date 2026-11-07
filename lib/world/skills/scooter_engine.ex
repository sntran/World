defmodule World.Skills.ScooterEngine do
  @moduledoc """
  The skill `scooter_engine` of a mechanic: the engine and the swing arm, with the muffler, the rear shock and the rear wheel
  (`World.Skills.Scooter`). Its data: `model`.
  """
  @behaviour World.Skill
  alias World.Skills.Scooter

  @impl true
  def name, do: "scooter_engine"

  @impl true
  def trade, do: :mechanic

  @impl true
  def check(data, path), do: Scooter.check(data, path)

  @impl true
  def estimate(_data, :near), do: 3000
  def estimate(_data, _level), do: 750

  @impl true
  def make(data, _inputs, _context), do: Scooter.make(data, "engine")
end
