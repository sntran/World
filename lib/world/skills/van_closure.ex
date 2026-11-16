defmodule World.Skills.VanClosure do
  @moduledoc """
  The skill `van_closure` of a fitter: the hood or one door of a van on
  its hinges or its rail (`World.Vehicles.Van.Closures`), from the
  openings factory. Its data: `group`, one of
  `World.Vehicles.Van.Closures.groups/0`.
  """
  @behaviour World.Skill
  alias World.Skills.Van
  alias World.Vehicles.Van.Closures

  @groups ~w(hood front_door_right front_door_left sliding_door rear_door_right rear_door_left)

  @impl true
  def name, do: "van_closure"

  @impl true
  def trade, do: :fitter

  @impl true
  def check(data, path), do: Van.group_check(data, path, @groups)

  @impl true
  def estimate(_data, :near), do: 1500
  def estimate(_data, _level), do: 300

  @impl true
  def make(data, inputs, %{name: name}) do
    van = Van.van(inputs).van
    {Van.station(name, van) |> Closures.group(van, data["group"]), %{}, %{}}
  end
end
