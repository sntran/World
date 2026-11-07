defmodule World.Skills.Panel do
  @moduledoc """
  The skill `panel` of a molder (plan 0002, D5): A panel of plastic from shape data: the body of a scooter, a fender, a cowl (a skin of ABS: `skin` and `matter` of its shapes).
  Its data: `shapes`, `ports`, `mass`, `sources`, `detail`, `inside`
  (`World.Skills.Vehicle`).
  """
  @behaviour World.Skill
  alias World.Skills.Vehicle

  @impl true
  def name, do: "panel"

  @impl true
  def trade, do: :molder

  @impl true
  def check(data, path), do: Vehicle.check_part(data, path)

  @impl true
  def estimate(data, level), do: Vehicle.estimate(data, level)

  @impl true
  def make(data, _inputs, %{name: name}), do: {Vehicle.part(data, name, :body), %{}, %{}}
end
