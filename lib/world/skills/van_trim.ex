defmodule World.Skills.VanTrim do
  @moduledoc """
  The skill `van_trim` of a trimmer: one group of the trim of a van
  (`World.Vehicles.Van.Trim`): the black plastic, the lamps, the grille,
  and at near the small parts and the cab. Its data: `group`.
  """
  @behaviour World.Skill
  alias World.Skills.Van
  alias World.Vehicles.Van.Trim

  @groups ~w(plastic lamps grille details cab)

  @impl true
  def name, do: "van_trim"

  @impl true
  def trade, do: :trimmer

  @impl true
  def check(data, path), do: Van.group_check(data, path, @groups)

  @impl true
  def estimate(_data, :near), do: 2000
  def estimate(_data, _level), do: 300

  @impl true
  def make(%{"group" => group}, _inputs, %{level: level}) when group in ~w(details cab) and level != :near,
    do: {nil, %{}, %{}}

  def make(data, inputs, %{name: name}) do
    van = Van.van(inputs).van
    {Van.station(name, van) |> Trim.group(van, data["group"]), %{}, %{}}
  end
end
