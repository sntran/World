defmodule World.Skills.VanSeats do
  @moduledoc """
  The skill `van_seats` of an upholsterer: the front seats and the rows
  of benches of a van on their mounts (`World.Vehicles.Van.Trim`), only
  at near. No data.
  """
  @behaviour World.Skill
  alias World.Skills.Van
  alias World.Vehicles.Van.Trim

  @impl true
  def name, do: "van_seats"

  @impl true
  def trade, do: :upholsterer

  @impl true
  def check(data, path), do: World.Skill.keys(data, path, [])

  @impl true
  def estimate(_data, :near), do: 6000
  def estimate(_data, _level), do: 0

  @impl true
  def make(_data, inputs, %{level: :near, name: name}) do
    van = Van.van(inputs).van
    {Van.station(name, van, inside: true) |> Trim.group(van, "seats"), %{}, %{}}
  end

  def make(_data, _inputs, _context), do: {nil, %{}, %{}}
end
