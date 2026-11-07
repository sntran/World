defmodule World.Skills.House do
  @moduledoc """
  The data that the skills of a house share (`World.Skills.HousePlan`,
  `Footing`, `Column`, `Slab`, `Course`, `Plaster`, `Paint`, `Opening`,
  `Iron`, `Flight`, `Roof`; the blueprint `priv/blueprints/tube_house.json`):
  the options of their data, and the geometry of the plan.

  A house of the people is built as on a real site in Việt Nam: a frame
  of reinforced concrete (footings, then floor by floor the columns, the
  beams and the slab), an infill of bricks laid in bands of courses by
  many masons at one time, a stair, a roof, the openings, the iron, and
  at the end the plaster and the paint.

  The axes: x across the width (from `-width / 2` to `width / 2`), y along
  the depth (the front at `depth / 2`), z up from the floor of the ground
  floor. Floor 1 is from 0 to `ground`, and floor `f` over it from
  `ground + (f - 2) * storey` to `ground + (f - 1) * storey`. A column is
  `column` m square, at each side at each end of the `bays` along the
  depth; a beam is `beam` m deep under each slab of `slab` m.
  """
  alias World.Orders.Blueprint
  alias World.{Mesh, Part, Shape}
  import Blueprint, only: [option: 3]

  @sides ~w(front back left right)

  @doc "The port of each part of a house: the origin, z up, y to the front."
  def port, do: Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @doc "The options of the data of the skills of a house, by their names."
  def options do
    m = fn name, default, min, max -> option(name, :number, default: default, min: min, max: max, unit: "m") end

    [
      m.("width", 4.0, 2.5, 12.0),
      m.("depth", 16.0, 4.0, 40.0),
      option("floors", :integer, default: 3, min: 1, max: 8),
      m.("ground", 3.6, 2.4, 6.0),
      m.("storey", 3.3, 2.4, 5.0),
      m.("slab", 0.12, 0.08, 0.25),
      m.("column", 0.22, 0.15, 0.6),
      m.("beam", 0.3, 0.2, 0.8),
      option("bays", :integer, default: 4, min: 1, max: 12),
      m.("wall", 0.11, 0.08, 0.4),
      m.("parapet", 1.0, 0.0, 2.0),
      m.("balcony", 0.8, 0.0, 2.0),
      option("roof", :choice, default: "terrace", values: ~w(terrace metal)),
      m.("stair_width", 0.9, 0.6, 1.5),
      option("openings", :list,
        default: [],
        max: 64,
        item:
          option("opening", :object,
            fields: [
              option("side", :choice, values: @sides),
              option("floor", :integer, min: 1, max: 8),
              option("kind", :choice, default: "window", values: ~w(window door shutter)),
              m.("x", 0.0, -20.0, 20.0),
              m.("width", 1.2, 0.3, 12.0),
              m.("height", 1.4, 0.3, 5.0),
              m.("sill", 0.9, 0.0, 4.0)
            ]
          )
      ),
      option("floor", :integer, default: 1, min: 1, max: 8),
      option("side", :choice, default: "front", values: @sides),
      option("band", :integer, default: 1, min: 1, max: 8),
      option("bands", :integer, default: 3, min: 1, max: 8),
      option("finish", :choice, default: "plaster", values: ~w(plaster paint bare))
    ]
  end

  @doc "The errors of the data of a skill of a house: only the options `names`."
  def check(data, path, names) do
    case Blueprint.check_options(Enum.filter(options(), &(&1.name in names)), data, path) do
      {:ok, _} -> []
      {:error, errors} -> errors
    end
  end

  @doc "The data of a skill of a house with the defaults of the options `names`, as a map of atoms."
  def o(data, names) do
    {:ok, full} = Blueprint.check_options(Enum.filter(options(), &(&1.name in names)), data, "")
    Map.new(full, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  @doc "The bottom of floor `f` (the top of the slab under it)."
  def bottom(_plan, 1), do: 0.0
  def bottom(plan, f), do: plan.ground + (f - 2) * plan.storey

  @doc "The top of floor `f` (the top of the slab over it)."
  def top(plan, f), do: plan.ground + (f - 1) * plan.storey

  @doc "The places of the columns: `{x, y}` of the center of each."
  def columns(plan) do
    {hw, hd, c} = {plan.width / 2, plan.depth / 2, plan.column}
    for x <- [-(hw - c / 2), hw - c / 2], k <- 0..plan.bays, do: {x, -hd + c / 2 + k * (plan.depth - c) / plan.bays}
  end

  @doc """
  The frame of the outer face of a wall: `{at, u, len}`. The wall goes
  along `u` from `at` for `len` m, its outside to `u × z`. Seen from
  outside, `u` goes from the left to the right.
  """
  def face(plan, side) do
    {hw, hd} = {plan.width / 2, plan.depth / 2}

    case side do
      "front" -> {{hw, hd, 0.0}, {-1.0, 0.0, 0.0}, plan.width}
      "back" -> {{-hw, -hd, 0.0}, {1.0, 0.0, 0.0}, plan.width}
      "left" -> {{-hw, hd, 0.0}, {0.0, -1.0, 0.0}, plan.depth}
      "right" -> {{hw, -hd, 0.0}, {0.0, 1.0, 0.0}, plan.depth}
    end
  end

  @doc """
  The holes of the openings of a wall of a floor in a band from `z0` to
  `z1` (over the bottom of the floor), in the coordinates of a sheet of
  the band that starts `from` m along the wall: `{u0, v0, u1, v1, depth}`.
  """
  def holes(plan, side, floor, from, z0, z1) do
    {_, _, len} = face(plan, side)

    for %{"side" => ^side, "floor" => ^floor} = w <- plan.openings,
        a = len / 2 + w["x"] - w["width"] / 2 - from,
        b = max(w["sill"], z0) - z0,
        c = a + w["width"],
        d = min(w["sill"] + w["height"], z1) - z0,
        d > b,
        do: {a, b, c, d, 0.0}
  end

  @doc "The openings of a wall of a floor."
  def openings(plan, side, floor), do: for(%{"side" => ^side, "floor" => ^floor} = w <- plan.openings, do: w)

  @doc "A box of a material role, with its matter (`World.Mass`)."
  def box(a, b, role, matter), do: Shape.box(a, b, role) |> Mesh.matter(matter)

  @doc "A part of a house: its name, its meshes, the port `o` and its sources."
  def part(name, meshes, sources), do: Part.new(name, :building, meshes, [port()], sources: sources)

  @doc "The point at `a` along the face of a wall, `z` up, and `n` m out of it."
  def at(plan, side, a, z, n \\ 0.0) do
    {{x, y, _}, {ux, uy, _}, _} = face(plan, side)
    {ox, oy} = {uy, -ux}
    {x + ux * a + ox * n, y + uy * a + oy * n, z}
  end
end
