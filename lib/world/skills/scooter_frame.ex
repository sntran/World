defmodule World.Skills.ScooterFrame do
  @moduledoc """
  The skill `scooter_frame` of a welder: the frame of steel tube under the body, with the head of the steering: the root, with the ports of the other parts
  (`World.Skills.Scooter`). Its data: `model`.
  """
  @behaviour World.Skill
  alias World.Skills.Scooter

  @impl true
  def name, do: "scooter_frame"

  @impl true
  def trade, do: :welder

  @impl true
  def check(data, path), do: Scooter.check(data, path)

  @impl true
  def estimate(_data, :near), do: 60
  def estimate(_data, _level), do: 15

  @impl true
  def make(data, _inputs, _context), do: Scooter.make(data, "frame")
end
