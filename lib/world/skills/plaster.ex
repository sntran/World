defmodule World.Skills.Plaster do
  @moduledoc """
  The skill `plaster` of a plasterer: the render of 15 mm on the outer
  face of a wall of a floor of a house (`World.Skills.House`), over its
  bricks, its columns and its beams, with the openings cut out (the role
  `plaster`). A wall with the finish `bare` has none, but at far its
  face with the role `brick`. Under the paint of
  a wall with the finish `paint`, the render is temporary: the paint
  covers it in the model.
  """
  @behaviour World.Skill
  alias World.Buildings.Panel
  alias World.Skills.House

  @names ~w(side floor finish)

  @impl true
  def name, do: "plaster"

  @impl true
  def trade, do: :plasterer

  @impl true
  def check(data, path), do: House.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 60

  @doc "The bags of dry mortar of the render: 27 kg for each m² of 15 mm; none on a bare wall."
  @impl true
  def materials(data, %{"plan" => %{"plan" => plan}}) do
    o = House.o(data, @names)
    if o.finish == "bare", do: %{}, else: %{"mortar" => ceil(House.wall_area(plan, o.side, o.floor) * 27 / 40)}
  end

  @impl true
  def make(data, %{"plan" => %{"plan" => plan}}, %{name: name, level: level}) do
    o = House.o(data, @names)

    case {o.finish, level} do
      {"bare", :far} ->
        layer(plan, o, name, 0.015, 0.015, :brick, level)

      {"bare", _} ->
        {nil, %{}, %{}}

      _ ->
        {part, out, extras} = layer(plan, o, name, 0.015, 0.015, :plaster, level)
        {part, Map.put(out, "temporary", o.finish == "paint"), extras}
    end
  end

  @doc """
  A layer on the outer face of a wall of a floor, `out` m out of it and
  `thick` m thick, with the holes of its openings (none at far: the face
  of the wall is all of it there, from the ground to the roof, in the
  layer of floor 1).
  """
  def layer(_plan, %{floor: f}, _name, _out, _thick, _role, :far) when f > 1, do: {nil, %{}, %{}}

  def layer(plan, o, name, out, thick, role, level) do
    z0 = House.bottom(plan, o.floor)
    z1 = if level == :far, do: House.top(plan, plan.floors), else: House.top(plan, o.floor)
    {_, u, len} = House.face(plan, o.side)
    at = House.at(plan, o.side, 0.0, z0, out)
    holes = if level == :far, do: [], else: House.holes(plan, o.side, o.floor, 0.0, 0.0, z1 - z0)
    mesh = Panel.sheet(at, u, {0.0, 0.0, 1.0}, len, z1 - z0, holes, role, skin: {thick, :mortar})
    {House.part(name, [mesh], ["The render: #{round(thick * 1000)} mm of mortar (an estimate)."]), %{}, %{}}
  end
end
