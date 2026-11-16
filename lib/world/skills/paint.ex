defmodule World.Skills.Paint do
  @moduledoc """
  The skill `paint` of a painter: the paint on the render of a wall of a
  floor of a house (`World.Skills.House`, the role `paint`: an app gives
  its color), 3 mm on the plaster: in the model, the paint is the
  render with its color (the plaster under it is temporary). Only a wall with the finish `paint`.
  """
  @behaviour World.Skill
  alias World.Skills.{House, Plaster}

  @names ~w(side floor finish)

  @impl true
  def name, do: "paint"

  @impl true
  def trade, do: :painter

  @impl true
  def check(data, path), do: House.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 60

  @doc "The cans of paint: two coats of 0.12 L for each m²; none on a wall with no paint."
  @impl true
  def materials(data, %{"plan" => %{"plan" => plan}}) do
    o = House.o(data, @names)
    if o.finish == "paint", do: %{"paint" => ceil(House.wall_area(plan, o.side, o.floor) * 0.24 / 18)}, else: %{}
  end

  @impl true
  def make(data, %{"plan" => %{"plan" => plan}}, %{name: name, level: level}) do
    o = House.o(data, @names)
    if o.finish == "paint", do: Plaster.layer(plan, o, name, 0.018, 0.018, :paint, level), else: {nil, %{}, %{}}
  end
end
