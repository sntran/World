defmodule World.Skills.Van do
  @moduledoc """
  The data that the skills of a van share (`World.Skills.VanOrder`,
  `VanBody`, `VanInside`, `VanClosure`, `VanTrim`, `VanGlass`,
  `VanSeats`, `VanChassis`, `VanUpfit`; the blueprint
  `priv/blueprints/van.json`): the options of the order of a van, and
  the mark of a station.

  A van of the people is built as on the line of its maker
  (`World.Vehicles.Van`): an engineer gives the order to the line; the
  body shop presses the body; at the same time the fitters make the hood
  and each door, the trimmers the plastic, the lamps, the grille, the
  small parts and the cab, a glazier the windows, an upholsterer the
  seats, the mechanics the engine bay, the drive and each corner, and an
  electrician the items on the roof. Each group goes on the body at its
  place.

  Each group is a small assembly on a mark: a part with no mesh, with
  the ports of the body (its `origin` and its corners) at the origin of
  the van. The group goes on the body at `origin`, so each of its parts
  is where the line puts it.
  """
  alias World.{Assembly, Part}
  alias World.Orders.{Blueprint, Blueprints}
  alias World.Vehicles.Van, as: Line
  alias World.Vehicles.Van.{BodyShop, Kit}

  # The values of the options, as the atoms of `World.Vehicles.Van`.
  @atoms Map.new(~w(dc_charger second_alternator fan solar)a, &{Atom.to_string(&1), &1})

  @doc "The options of the order of a van: those of the blueprint `van`."
  def options do
    {:ok, bp} = Blueprints.fetch("van")
    bp.options
  end

  @doc """
  The errors of the order of a van: each key is an option of the
  blueprint `van`; with the `model`, also the checks of the model (its
  sizes, its doors, its windows, its rows, the items on its roof).
  """
  def check(%{"model" => %{} = model} = data, path) do
    case model_errors(model, path <> ".model") do
      [] ->
        case check(Map.delete(data, "model"), path) do
          [] -> order_check(Map.put(full(Map.delete(data, "model")), "model", model), path)
          errors -> errors
        end

      errors ->
        errors
    end
  end

  def check(data, path) when is_map(data) do
    known = for o <- options(), Map.has_key?(data, o.name), do: o

    case Blueprint.check_options(known, data, path) do
      {:ok, o} when is_map_key(data, "model") -> order_check(full(o), path)
      {:ok, _} -> []
      {:error, errors} -> errors
    end
  end

  def check(_data, path), do: [{path, "must be an object"}]

  defp order_check(full, path) do
    {:ok, bp} = Blueprints.fetch("van")
    for {p, message} <- bp.check.(full), do: {String.replace_prefix(p, "options", path), message}
  end

  # The order with the default of each option; the data of a model stays as it is.
  defp full(%{"model" => %{} = model} = data), do: Map.put(full(Map.delete(data, "model")), "model", model)

  defp full(data) do
    {:ok, o} = Blueprint.check_options(options(), data, "")
    o
  end

  @model ~w(make roof length width height wheelbase front track tire floor sources)
  @make ~w(traces hull front openings seats sources)

  # The data of a model of a van of a project, in the format of
  # priv/data/vans.json, with the data of its make in `make`: its keys,
  # and the hull and the sizes that it makes.
  defp model_errors(m, path) do
    missing =
      for(k <- @model, not Map.has_key?(m, k), do: {"#{path}.#{k}", "is required"}) ++
        if(is_map(m["make"]),
          do: for(k <- @make, not Map.has_key?(m["make"], k), do: {"#{path}.make.#{k}", "is required"}),
          else: [{"#{path}.make", "must be the data of a make: traces, hull, front, openings, seats, sources"}]
        ) ++
        if(is_map(m["make"]) and Map.has_key?(m["make"], "contents"),
          do: World.Skills.Vehicle.check_contents(m["make"]["contents"], "#{path}.make.contents"),
          else: []
        )

    if missing == [] do
      try do
        _ = Line.hull(m)
        _ = Line.sizes(m)
        []
      rescue
        e -> [{path, "does not make the hull of a van: #{Exception.message(e)}"}]
      end
    else
      missing
    end
  end

  @doc "The errors of the data of a skill of a station: only the key `group`, one of `groups`."
  def group_check(data, path, groups) do
    case Blueprint.check_options([Blueprint.option("group", :choice, values: groups)], data, path) do
      {:ok, _} -> []
      {:error, errors} -> errors
    end
  end

  @doc """
  The order on the line of the data of an order (`World.Vehicles.Van.line/2`),
  with the items of the engine bay and of the roof as atoms.
  """
  def line(data) do
    o = full(data)
    engine_bay = Enum.map(o["engine_bay"], &Map.fetch!(@atoms, &1))
    roof = for %{"kind" => k, "at" => d} <- o["roof"], do: {Map.fetch!(@atoms, k), d}

    van =
      Line.line(o["model"], size: o["size"], doors: o["doors"], windows: o["windows"], rows: o["rows"])

    %{van: van, engine_bay: engine_bay, roof: roof}
  end

  @doc """
  The assembly of a group of a station: its root is the mark of the body
  (`mark/2`); with `inside: true`, the mark of the inside of the body
  too (the seats go on it).
  """
  def station(name, van, opts \\ []) do
    a = Assembly.new(name, mark("mark", BodyShop.ports(van)), root: "mark")

    if Keyword.get(opts, :inside, false),
      do:
        Assembly.add(a, "inside", mark("inside", [Kit.origin() | BodyShop.mounts(van)]), at: "origin", port: "origin"),
      else: a
  end

  @doc "A mark: a part with no mesh and its ports, at the origin of the van."
  def mark(name, ports), do: Part.new(name, :mark, [], ports, detail: :always)

  @doc "The data of the node `order` in the inputs of a skill of a van."
  def van(inputs), do: inputs["order"]["line"]
end
