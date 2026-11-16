defmodule World.Skills.BicycleFrame do
  @moduledoc """
  The skill `bicycle_frame` of a welder (plan 0002, D5): The frame of a bicycle with a diamond frame from its geometry sheet: the tubes, the shell, the seat post, the saddle and a bottle cage, with the ports `steer`, `rear_axle`, `bb`, `stand` and `rack`. Its data: the
  numbers of the geometry sheet (`World.Skills.Bicycle`).
  """
  @behaviour World.Skill
  alias World.Skills.Bicycle
  alias World.Vehicles.Bicycle, as: Sheet

  @impl true
  def name, do: "bicycle_frame"

  @impl true
  def trade, do: :welder

  @impl true
  def check(data, path), do: Bicycle.check(data, path)

  @impl true
  def estimate(_data, :near), do: 600
  def estimate(_data, _level), do: 150

  @impl true
  def make(data, _inputs, %{name: name}) do
    s = Bicycle.sheet(data)
    %{front: {_, fy, _}, r: r} = Sheet.points(s)
    # The model moves to the center of its length (the extras place).
    {Sheet.frame(s, name), %{}, %{"place" => [0.0, -(fy + r) / 2, 0.0]}}
  end
end
