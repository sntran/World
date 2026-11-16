defmodule World.Skills.VanChassis do
  @moduledoc """
  The skill `van_chassis` of a mechanic: one group of the chassis of a
  van (`World.Vehicles.Van.Chassis`): the engine bay with the items of
  the order in it, the drive under the body, or the corner of one wheel
  on its knuckle. Its data: `group`, one of
  `World.Vehicles.Van.Chassis.groups/0`.
  """
  @behaviour World.Skill
  alias World.Skills.Van
  alias World.Vehicles.Van.Chassis

  @groups ~w(engine_bay drive front_right front_left rear_right rear_left)

  @impl true
  def name, do: "van_chassis"

  @impl true
  def trade, do: :mechanic

  @impl true
  def check(data, path), do: Van.group_check(data, path, @groups)

  @impl true
  def estimate(_data, :near), do: 2500
  def estimate(_data, _level), do: 400

  @impl true
  def make(data, inputs, %{name: name}) do
    %{van: van, engine_bay: items} = Van.van(inputs)
    {Van.station(name, van) |> Chassis.group(van, data["group"], items), %{}, %{}}
  end
end
