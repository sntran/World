defmodule World.Skills.Frame do
  @moduledoc """
  The skill `frame` of a welder (plan 0002, D5): The frame of a motor vehicle of steel tubes from shape data, with its head tube and its ports (`steer`, `pivot`, `stand`, `body`, `seat`).
  Its data: `shapes`, `ports`, `mass`, `sources`, `detail`, `inside`
  (`World.Skills.Vehicle`).
  """
  @behaviour World.Skill
  alias World.Skills.Vehicle

  @impl true
  def name, do: "frame"

  @impl true
  def trade, do: :welder

  @impl true
  def check(data, path), do: Vehicle.check_part(data, path)

  @impl true
  def estimate(data, level), do: Vehicle.estimate(data, level)

  @impl true
  def make(data, _inputs, %{name: name}), do: {Vehicle.part(data, name, :frame), %{}, %{}}
end
