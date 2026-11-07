defmodule World.Skills.Fork do
  @moduledoc """
  The skill `fork` of a mechanic (plan 0002, D5): A telescopic fork with its fender, or the bars of a cockpit with their grips, levers and mirrors, from shape data; the wheel goes on its port `axle`.
  Its data: `shapes`, `ports`, `mass`, `sources`, `detail`, `inside`
  (`World.Skills.Vehicle`).
  """
  @behaviour World.Skill
  alias World.Skills.Vehicle

  @impl true
  def name, do: "fork"

  @impl true
  def trade, do: :mechanic

  @impl true
  def check(data, path), do: Vehicle.check_part(data, path)

  @impl true
  def estimate(data, level), do: Vehicle.estimate(data, level)

  @impl true
  def make(data, _inputs, %{name: name}), do: {Vehicle.part(data, name, :fork), %{}, %{}}
end
