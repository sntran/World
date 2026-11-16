defmodule World.Skills.Towers do
  @moduledoc """
  The data that the skills of a tower share (`World.Skills.TowerBody`,
  `Lantern`, `Tower`, `SpiralStair`, `TowerSite`; the blueprint
  `priv/blueprints/tower.json`): the options of the data of their nodes.

  A tower (W13 of Vũng Tàu) is a lighthouse, a water tower or a bell
  tower of masonry on a round platform, from the ground up: the platform
  (`platform_width`, `platform_height`); the round body, `body` m across
  at its foot and `top` m at the cornice, with a `ledge` round its foot
  and `bands` (rings at their heights; the ledge, the bands and the flare
  are over the platform, the other heights over the ground); the
  `pilasters` of `pilaster_width` m, out to `across` m, flared at their
  foot out to `foot` m over the lowest `flare` m; the cornice, a cove
  from `cornice` m to the floor of the gallery at `gallery` m; the
  gallery (`gallery_width` m) with its rail (`rail` m); the drum (`drum`
  m across), the lantern (`lantern_from`, `lantern_to`, `lantern_width`,
  with its `panes` of glass in frames and a lens), the dome to `height`
  m, a ball, and a lightning rod to `rod` m; a door at the foot
  (`door_width`, `door_height`, `door_angle`), and with `hollow` at near
  the wall of `wall` m and a spiral stair of `steps` steps. The origin is
  on the ground at the center of the platform.
  """
  alias World.Orders.Blueprint
  alias World.Part
  import Blueprint, only: [option: 3]

  @doc "The port of each part of a tower: the origin, z up, y to the front."
  def port, do: Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @doc "The options of the data of the skills of a tower, by their names."
  def options do
    m = fn name, default, min, max -> option(name, :number, default: default, min: min, max: max, unit: "m") end

    [
      option("name", :data, default: "thap", check: &name/2),
      m.("height", 18.0, 3.0, 80.0),
      m.("platform_width", 7.8, 0.0, 40.0),
      m.("platform_height", 0.3, 0.0, 3.0),
      m.("body", 3.2, 0.5, 20.0),
      m.("top", 3.2, 0.5, 20.0),
      m.("ledge", 0.8, 0.0, 5.0),
      option("bands", :list, default: [4.1, 7.5], max: 8, item: option("band", :number, min: 0.0, max: 80.0)),
      option("pilasters", :integer, default: 4, min: 0, max: 16),
      m.("pilaster_width", 0.7, 0.1, 3.0),
      m.("across", 5.1, 0.5, 30.0),
      m.("foot", 6.4, 0.5, 40.0),
      m.("flare", 3.1, 0.0, 30.0),
      m.("cornice", 10.2, 1.0, 80.0),
      m.("gallery", 12.7, 1.0, 80.0),
      m.("gallery_width", 5.6, 0.5, 30.0),
      m.("rail", 1.0, 0.5, 2.0),
      m.("drum", 2.5, 0.5, 20.0),
      m.("lantern_from", 15.4, 1.0, 80.0),
      m.("lantern_to", 17.3, 1.0, 80.0),
      m.("lantern_width", 2.2, 0.3, 10.0),
      option("panes", :integer, default: 10, min: 6, max: 24),
      m.("rod", 21.0, 1.0, 100.0),
      m.("door_width", 0.9, 0.5, 3.0),
      m.("door_height", 2.1, 1.5, 5.0),
      option("door_angle", :number, default: 270.0, min: 0.0, max: 360.0, unit: "deg"),
      option("hollow", :boolean, default: false),
      m.("wall", 0.5, 0.1, 3.0),
      option("steps", :integer, default: 55, min: 5, max: 500),
      option("light", :data, default: nil, check: &light/2)
    ]
  end

  defp name(v, path) do
    if is_binary(v) and v =~ ~r/^[a-z0-9_]{1,40}$/,
      do: {:ok, v},
      else: {:error, [{path, "must be a name: a to z, 0 to 9 and _, at most 40"}]}
  end

  @doc "A check of a light: a color, a count of flashes, a period (s) and a range (nm)."
  def light(%{"color" => c, "flashes" => f, "period" => p, "range" => r} = raw, _path)
      when is_binary(c) and byte_size(c) <= 20 and is_integer(f) and f >= 0 and f <= 9 and is_number(p) and p > 0 and
             p <= 60 and is_number(r) and r > 0 and r <= 50,
      do: {:ok, Map.take(raw, ["color", "flashes", "period", "range"])}

  def light(_, path), do: {:error, [{path, "must be {color, flashes: 0 to 9, period: s, range: nm}"}]}

  @doc "The errors of the data of a skill of a tower: only the options `names`."
  def check(data, path, names) do
    case Blueprint.check_options(Enum.filter(options(), &(&1.name in names)), data, path) do
      {:ok, _} -> []
      {:error, errors} -> errors
    end
  end

  @doc """
  The data of a skill of a tower with the defaults of the options
  `names`, as a map of atoms, with `platform` (`{width, height}`),
  `lantern` (`{from, to, width}`) and `door` (`{width, height}`).
  """
  def o(data, names) do
    {:ok, full} = Blueprint.check_options(Enum.filter(options(), &(&1.name in names)), data, "")
    o = Map.new(full, fn {k, v} -> {String.to_existing_atom(k), v} end)

    o
    |> join(:platform, [:platform_width, :platform_height])
    |> join(:lantern, [:lantern_from, :lantern_to, :lantern_width])
    |> join(:door, [:door_width, :door_height])
  end

  defp join(o, key, keys) do
    if Enum.all?(keys, &Map.has_key?(o, &1)), do: Map.put(o, key, List.to_tuple(Enum.map(keys, &o[&1]))), else: o
  end
end
