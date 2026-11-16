defmodule World.Skills.VanGlass do
  @moduledoc """
  The skill `van_glass` of a glazier: the windshield and the windows of
  the body of a van, from the openings factory
  (`World.Vehicles.Van.Trim`). No data.
  """
  @behaviour World.Skill
  alias World.Skills.Van
  alias World.Vehicles.Van.Trim

  @impl true
  def name, do: "van_glass"

  @impl true
  def trade, do: :glazier

  @impl true
  def check(data, path), do: World.Skill.keys(data, path, [])

  @impl true
  def estimate(_data, :near), do: 400
  def estimate(_data, _level), do: 100

  @impl true
  def make(_data, inputs, %{name: name}) do
    van = Van.van(inputs).van
    {Van.station(name, van) |> Trim.group(van, "windows"), %{}, %{}}
  end
end
