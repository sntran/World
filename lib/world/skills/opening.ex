defmodule World.Skills.Opening do
  @moduledoc """
  The skill `opening` of a joiner: the doors and the windows of a wall of
  a floor of a house (`World.Skills.House`), in the middle of the wall: a
  window is a frame of aluminum (50 mm) with its glass (6 mm); a door a
  frame and a leaf of wood (40 mm); a `shutter` (the cửa cuốn of a shop) a
  rolling shutter of steel, closed, with its box over it. None at far.
  """
  @behaviour World.Skill
  alias World.Skills.House

  @names ~w(side floor)

  @impl true
  def name, do: "opening"

  @impl true
  def trade, do: :joiner

  @impl true
  def check(data, path), do: House.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 120

  @impl true
  def make(_data, _inputs, %{level: :far}), do: {nil, %{}, %{}}

  def make(data, %{"plan" => %{"plan" => plan}}, %{name: name}) do
    o = House.o(data, @names)

    case House.openings(plan, o.side, o.floor) do
      [] -> {nil, %{}, %{}}
      list -> {House.part(name, Enum.flat_map(list, &pieces(plan, o, &1)), sources()), %{}, %{}}
    end
  end

  defp sources, do: ["The openings: frames of aluminum of 50 mm and glass of 6 mm, doors of wood of 40 mm (estimates)."]

  # A box between two points on the face of the wall, from `n0` to `n1` out of it.
  defp slab(plan, side, {a0, z0}, {a1, z1}, {n0, n1}, role, matter) do
    p = House.at(plan, side, a0, z0, n0)
    q = House.at(plan, side, a1, z1, n1)
    {{x0, y0, _}, {x1, y1, _}} = World.Vec.bounds([p, q])
    House.box({x0, y0, min(z0, z1)}, {x1, y1, max(z0, z1)}, role, matter)
  end

  defp pieces(plan, o, w) do
    {_, _, len} = House.face(plan, o.side)
    z = House.bottom(plan, o.floor) + w["sill"]
    {a0, a1, z0, z1} = {len / 2 + w["x"] - w["width"] / 2, len / 2 + w["x"] + w["width"] / 2, z, z + w["height"]}
    mid = -plan.wall / 2
    t = 0.05

    case w["kind"] do
      "shutter" ->
        [
          slab(plan, o.side, {a0, z0}, {a1, z1}, {mid - 0.01, mid + 0.01}, :metal_shutter, :steel),
          slab(plan, o.side, {a0, z1}, {a1, z1 + 0.3}, {0.0, 0.3}, :metal_shutter, :steel)
        ]

      kind ->
        {role, matter, infill, leaf} =
          if kind == "door", do: {:wood, :wood, :wood, 0.04}, else: {:aluminum, :aluminum, :glass, 0.006}

        frame = [
          slab(plan, o.side, {a0, z0}, {a1, z0 + t}, {mid - 0.03, mid + 0.03}, role, matter),
          slab(plan, o.side, {a0, z1 - t}, {a1, z1}, {mid - 0.03, mid + 0.03}, role, matter),
          slab(plan, o.side, {a0, z0 + t}, {a0 + t, z1 - t}, {mid - 0.03, mid + 0.03}, role, matter),
          slab(plan, o.side, {a1 - t, z0 + t}, {a1, z1 - t}, {mid - 0.03, mid + 0.03}, role, matter)
        ]

        frame ++
          [slab(plan, o.side, {a0 + t, z0 + t}, {a1 - t, z1 - t}, {mid - leaf / 2, mid + leaf / 2}, infill, infill)]
    end
  end
end
