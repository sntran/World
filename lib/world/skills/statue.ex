defmodule World.Skills.Statue do
  @moduledoc """
  The data that the skills of a statue share (`World.Skills.Figure`,
  `Robe`, the cast in pours of `CastSurvey`, `Formwork`, `CastOutside`,
  `Pour`, `CastField`, `ShellSlab` and `Shell`, `Grille`, `Halo`, `Set`,
  `Base`, `Stair`, `Rail`, `Site`; the blueprint
  `priv/blueprints/statue.json`): the options of
  the data of their nodes, with their defaults, ranges and units, the
  materials and the port of a part.

  A statue (W13 of Vũng Tàu) is a figure of the person blueprint
  (`World.People.Human`) at any size and in any pose, in a long robe,
  cast as one solid of concrete or stone (`World.Cast`), with a halo, on
  a round plinth and on a base with panels of figures in relief. With
  `hollow`, the near level has walls, a spiral stair and openings. The
  origin is on the ground at the center of the base; the figure looks to
  +y.
  """
  alias World.Orders.Blueprint
  alias World.People.{Data, Pose}
  alias World.Part
  require Data
  import Blueprint, only: [option: 3]

  # The materials of a statue: the role of its look and of its mass.
  @materials %{concrete: {:stone_wash, :concrete}, stone: {:stone, :stone}}

  @doc "The materials of a statue."
  def materials, do: Map.keys(@materials)

  @doc "The role of the look and the role of the mass of a material of a statue."
  def material(name), do: Map.fetch!(@materials, name)

  @doc "The port of each part of a statue: the origin, z up, y to the front."
  def port, do: Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @doc "The options of the data of the skills of a statue, by their names."
  def options do
    hair = Data.assets() |> Map.fetch!("hair") |> Map.keys() |> Enum.sort()
    m = fn name, default, min, max -> option(name, :number, default: default, min: min, max: max, unit: "m") end

    [
      option("name", :data, default: "tuong", check: &name/2),
      m.("height", 32.0, 1.0, 100.0),
      m.("span", nil, 0.5, 100.0),
      m.("hand", nil, 0.1, 10.0),
      option("pose", :choice, default: "arms_out", values: ["arms_out" | Pose.names()]),
      option("lift", :number, default: 8.0, min: -45.0, max: 60.0, unit: "deg"),
      option("gender", :number, default: 1.0, min: 0.0, max: 1.0),
      option("age", :number, default: 35.0, min: 25.0, max: 90.0, unit: "years"),
      option("hair", :choice, default: Data.name!("hair", "long01"), values: ["none" | hair]),
      option("robe", :boolean, default: true),
      option("halo", :boolean, default: true),
      option("rays", :integer, default: 9, min: 0, max: 17),
      option("material", :choice, default: "concrete", values: Enum.map(materials(), &Atom.to_string/1)),
      option("hollow", :boolean, default: false),
      m.("wall", 0.3, 0.1, 2.0),
      option("steps", :integer, default: 133, min: 10, max: 1000),
      m.("well", 1.0, 0.3, 4.0),
      option("windows", :list,
        default: [],
        max: 12,
        item:
          option("window", :object,
            fields: [m.("z", :required, 0.0, 100.0), m.("width", 1.2, 0.2, 5.0), m.("height", 1.2, 0.2, 5.0)]
          )
      ),
      m.("plinth_radius", 4.5, 0.0, 50.0),
      m.("plinth_height", 1.2, 0.0, 20.0),
      m.("base_width", 12.0, 1.0, 100.0),
      m.("base_depth", 12.0, 1.0, 100.0),
      m.("base_height", 4.0, 0.0, 50.0),
      m.("corner", 1.5, 0.1, 10.0),
      option("reliefs", :list,
        default: [],
        max: 4,
        item:
          option("relief", :object,
            fields: [
              option("side", :choice, values: ~w(front back left right)),
              option("figures", :integer, default: 3, min: 1, max: 20),
              option("title", :data, default: "", check: &text/2)
            ]
          )
      ),
      m.("rail", 1.0, 0.0, 3.0),
      m.("feet", 5.2, 0.0, 70.0),
      option("band", :integer, default: 1, min: 1, max: 64),
      option("bands", :integer, default: 1, min: 1, max: 64)
    ]
  end

  defp name(v, path) do
    if is_binary(v) and v =~ ~r/^[a-z0-9_]{1,40}$/,
      do: {:ok, v},
      else: {:error, [{path, "must be a name: a to z, 0 to 9 and _, at most 40"}]}
  end

  defp text(v, _path) when is_binary(v) and byte_size(v) <= 200, do: {:ok, v}
  defp text(_, path), do: {:error, [{path, "must be a text of at most 200 bytes"}]}

  @doc "The errors of the data of a skill of a statue: only the options `names`."
  def check(data, path, names) do
    case Blueprint.check_options(Enum.filter(options(), &(&1.name in names)), data, path) do
      {:ok, _} -> []
      {:error, errors} -> errors
    end
  end

  @doc """
  The data of a skill of a statue with the defaults of the options
  `names`, as a map of atoms (the material an atom, each window `{z,
  width, height}`, the hair `none` nil).
  """
  def o(data, names) do
    {:ok, full} = Blueprint.check_options(Enum.filter(options(), &(&1.name in names)), data, "")

    Map.new(full, fn
      {"material", m} -> {:material, String.to_existing_atom(m)}
      {"windows", ws} -> {:windows, for(w <- ws, do: {w["z"], w["width"], w["height"]})}
      {"hair", "none"} -> {:hair, nil}
      {k, v} -> {String.to_existing_atom(k), v}
    end)
  end
end
