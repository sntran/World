defmodule World.Skills.ScooterBody do
  @moduledoc """
  The skill `scooter_body` of a molder: the body of plastic panels, with its lights
  (`World.Skills.Scooter`). Its data: `model`.
  """
  @behaviour World.Skill
  alias World.Skills.Scooter

  @impl true
  def name, do: "scooter_body"

  @impl true
  def trade, do: :molder

  @impl true
  def check(data, path), do: Scooter.check(data, path)

  @impl true
  def estimate(_data, :near), do: 4000
  def estimate(_data, _level), do: 1000

  @impl true
  def make(data, _inputs, _context), do: Scooter.make(data, "body")
end
