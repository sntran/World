defmodule World.Skills.VanUpfit do
  @moduledoc """
  The skill `van_upfit` of an electrician: the items of DIY on the roof
  of a van (`World.Vehicles.Van.Upfit`), from the order. None when the
  order has no item on the roof. No data.
  """
  @behaviour World.Skill
  alias World.Skills.Van
  alias World.Vehicles.Van.Upfit

  @impl true
  def name, do: "van_upfit"

  @impl true
  def trade, do: :electrician

  @impl true
  def check(data, path), do: World.Skill.keys(data, path, [])

  @impl true
  def estimate(_data, _level), do: 400

  @impl true
  def make(_data, inputs, %{name: name}) do
    case Van.van(inputs) do
      %{roof: []} -> {nil, %{}, %{}}
      %{van: van, roof: roof} -> {Van.station(name, van) |> Upfit.fit(van, roof), %{}, %{}}
    end
  end
end
