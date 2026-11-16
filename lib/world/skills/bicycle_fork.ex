defmodule World.Skills.BicycleFork do
  @moduledoc """
  The skill `bicycle_fork` of a welder (plan 0002, D5): The fork of a bicycle from its geometry sheet, with the stem, a drop bar and the fender: the ports `steer` and `axle` (the front wheel goes on it). Its data: the
  numbers of the geometry sheet (`World.Skills.Bicycle`).
  """
  @behaviour World.Skill
  alias World.Skills.Bicycle
  alias World.Vehicles.Bicycle, as: Sheet

  @impl true
  def name, do: "bicycle_fork"

  @impl true
  def trade, do: :welder

  @impl true
  def check(data, path), do: Bicycle.check(data, path)

  @impl true
  def estimate(_data, :near), do: 400
  def estimate(_data, _level), do: 100

  @impl true
  def make(data, _inputs, %{name: name}), do: {Sheet.fork(Bicycle.sheet(data), name), %{}, %{}}
end
