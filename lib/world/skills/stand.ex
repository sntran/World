defmodule World.Skills.Stand do
  @moduledoc """
  The skill `stand` of a smith (plan 0002, D5): a part of steel bars from
  shape data (`World.Skills.Vehicle`): a stand, a rack, a guard. Its data:
  `shapes`, `ports`, `mass`, `sources`, `detail`, `inside`. A part that
  goes on a port of another part has its shapes from its own port: a
  rack from the rear axle, a stand from its pivot.
  """
  @behaviour World.Skill
  alias World.Skills.Vehicle

  @impl true
  def name, do: "stand"

  @impl true
  def trade, do: :smith

  @impl true
  def check(data, path), do: Vehicle.check_part(data, path)

  @impl true
  def estimate(data, level), do: Vehicle.estimate(data, level)

  @impl true
  def make(data, _inputs, %{name: name}), do: {Vehicle.part(data, name, :stand), %{}, %{}}
end
