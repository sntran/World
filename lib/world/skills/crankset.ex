defmodule World.Skills.Crankset do
  @moduledoc """
  The skill `crankset` of a mechanic (plan 0002, D5): The crankset of a bicycle: the chainring of `teeth`, two arms of `arm`, and the pedals on their hinges; its port `axle` goes on the port `bb` of the frame. Its data: the
  numbers of the geometry sheet (`World.Skills.Bicycle`).
  """
  @behaviour World.Skill
  alias World.Skills.Bicycle
  alias World.Vehicles.Bicycle, as: Sheet

  @impl true
  def name, do: "crankset"

  @impl true
  def trade, do: :mechanic

  @impl true
  def check(data, path), do: Bicycle.check(data, path)

  @impl true
  def estimate(_data, :near), do: 500
  def estimate(_data, _level), do: 125

  @impl true
  def make(data, _inputs, %{name: name}), do: {Sheet.crankset(Bicycle.sheet(data), name), %{}, %{}}
end
