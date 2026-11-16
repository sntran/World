defmodule World.Skills.Course do
  @moduledoc """
  The skill `course` of a mason: one band of the courses of the infill of
  a wall of a floor of a house (`World.Skills.House`): band `band` of
  `bands` from the slab under the floor to the beam over it, between the
  columns, `wall` m thick, of bricks of TCVN 1451:1998 (220 by 105 by 60
  mm, the role `brick`), with the openings of the wall cut out. Many
  masons lay the bands of the walls at the same time; a band waits for
  the band under it. The bricks of a wall with a render (the finish is not
  `bare`) are temporary: the stream shows them, and the render hides
  them in the model. None at far: the face of the wall is the model
  there (`World.Skills.Plaster`).
  """
  @behaviour World.Skill
  alias World.Buildings.Panel
  alias World.Skills.House

  @names ~w(side floor band bands finish)

  @impl true
  def name, do: "course"

  @impl true
  def trade, do: :mason

  @impl true
  def check(data, path), do: House.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 80

  @impl true
  def make(_data, _inputs, %{level: :far}), do: {nil, %{}, %{}}

  def make(data, %{"plan" => %{"plan" => plan}}, %{name: name}) do
    o = House.o(data, @names)
    z0 = House.bottom(plan, o.floor)
    h = House.top(plan, o.floor) - plan.beam - z0
    {v0, v1} = {(o.band - 1) * h / o.bands, o.band * h / o.bands}
    {_, u, _} = House.face(plan, o.side)

    meshes =
      for {a, b} <- segments(plan, o.side) do
        at = House.at(plan, o.side, a, z0 + v0)

        Panel.sheet(at, u, {0.0, 0.0, 1.0}, b - a, v1 - v0, House.holes(plan, o.side, o.floor, a, v0, v1), :brick,
          skin: {plan.wall, :brick}
        )
      end

    sources = ["The bricks: TCVN 1451:1998, 220 by 105 by 60 mm, in a wall of #{round(plan.wall * 1000)} mm."]
    {House.part(name, meshes, sources), %{"temporary" => o.finish != "bare"}, %{}}
  end

  @doc """
  The bricks of the band: its area between the columns less its
  openings, at 62 bricks for each m² of each layer of 105 mm (a brick of
  220 by 60 mm with joints of 10 mm).
  """
  @impl true
  def materials(data, %{"plan" => %{"plan" => plan}}) do
    o = House.o(data, @names)
    h = House.top(plan, o.floor) - plan.beam - House.bottom(plan, o.floor)
    {v0, v1} = {(o.band - 1) * h / o.bands, o.band * h / o.bands}

    area =
      Enum.sum(
        for {a, b} <- segments(plan, o.side) do
          cut =
            for {u0, w0, u1, w1, _} <- House.holes(plan, o.side, o.floor, a, v0, v1),
                do: max(0.0, min(u1, b - a) - max(u0, 0.0)) * (w1 - w0)

          (b - a) * (v1 - v0) - Enum.sum(cut)
        end
      )

    %{"brick" => ceil(area * 62.1 * max(1, round(plan.wall / 0.105)))}
  end

  @doc "The lengths of a wall between its columns, along its face: `{from, to}`."
  def segments(plan, side) when side in ["front", "back"], do: [{plan.column, plan.width - plan.column}]

  def segments(plan, side) do
    c = plan.column
    {_, _, len} = House.face(plan, side)
    knots = for k <- 0..plan.bays, do: c / 2 + k * (len - c) / plan.bays
    for [a, b] <- Enum.chunk_every(knots, 2, 1, :discard), do: {a + c / 2, b - c / 2}
  end
end
