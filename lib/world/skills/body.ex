defmodule World.Skills.Body do
  @moduledoc """
  The skill `body` of a sheet metal worker (plan 0002, D5): A body of steel sheet from shape data: the body of a car on lofts with the arches of its wheels, a tank.
  Its data: `shapes`, `ports`, `mass`, `sources`, `detail`, `inside`
  (`World.Skills.Vehicle`).
  """
  @behaviour World.Skill
  alias World.Skills.Vehicle

  @impl true
  def name, do: "body"

  @impl true
  def trade, do: :sheet_metal_worker

  @impl true
  def check(data, path), do: Vehicle.check_part(data, path)

  @impl true
  def estimate(data, level), do: Vehicle.estimate(data, level)

  @impl true
  def make(data, _inputs, %{name: name}), do: {Vehicle.part(data, name, :body), %{}, %{}}
end
