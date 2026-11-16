defmodule World.Skills.VanInside do
  @moduledoc """
  The skill `van_inside` of a trimmer: the floors, the wells of the
  wheels and the pillar inside the body of a van
  (`World.Vehicles.Van.BodyShop.inside/1`), only at near. No data.
  """
  @behaviour World.Skill
  alias World.Skills.Van
  alias World.Vehicles.Van.BodyShop

  @impl true
  def name, do: "van_inside"

  @impl true
  def trade, do: :trimmer

  @impl true
  def check(data, path), do: World.Skill.keys(data, path, [])

  @impl true
  def estimate(_data, :near), do: 600
  def estimate(_data, _level), do: 0

  @impl true
  def make(_data, inputs, %{level: :near}), do: {BodyShop.inside(Van.van(inputs).van), %{}, %{}}
  def make(_data, _inputs, _context), do: {nil, %{}, %{}}
end
