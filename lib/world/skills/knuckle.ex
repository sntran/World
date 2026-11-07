defmodule World.Skills.Knuckle do
  @moduledoc """
  The skill `knuckle` of a mechanic (plan 0002, D5): the knuckle of a
  corner of a vehicle with four wheels, with its brake disc
  (`World.Vehicles.Corners.knuckle/4`). Its data: `at` (the center of the
  hub, `[x, y, z]`: x more than 0 at the right side) and `disc` (the
  diameter of the brake disc, or none). In the drawing it goes on the
  port `corner_NAME` of the body with its port `steer` (a hinge of the
  role `steer` at the front), and the wheel on its port `axle`.
  """
  @behaviour World.Skill
  import World.Orders.Blueprint, only: [option: 3]
  alias World.Skills.Vehicle
  alias World.Vehicles.Corners

  @impl true
  def name, do: "knuckle"

  @impl true
  def trade, do: :mechanic

  defp options,
    do: [
      option("at", :list, max: 3, item: option("v", :number, min: -50.0, max: 50.0, unit: "m")),
      option("disc", :number, default: nil, min: 0.1, max: 0.6, unit: "m")
    ]

  @impl true
  def check(data, path) do
    case Vehicle.check(data, path, options()) do
      [] -> if length(data["at"]) == 3, do: [], else: [{path <> ".at", "must be a point [x, y, z]"}]
      errors -> errors
    end
  end

  @impl true
  def estimate(_data, _level), do: 80

  @impl true
  def make(data, _inputs, %{name: name}) do
    %{"at" => [x, y, z], "disc" => disc} = Vehicle.o(data, options())
    side = if x >= 0, do: 1.0, else: -1.0
    {Corners.knuckle(name, {x / 1, y / 1, z / 1}, side, disc), %{}, %{}}
  end
end
