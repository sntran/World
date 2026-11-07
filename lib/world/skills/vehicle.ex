defmodule World.Skills.Vehicle do
  @moduledoc """
  The data that the skills of the vehicle trades share (plan 0002, D5;
  `docs/skills.md`): a skill takes the numbers of a spec sheet where its
  trade has one (a wheel from its tire code, a bicycle frame from its
  geometry), and shape data for the free shapes from the photos (the
  shapes of `docs/format.md`, "A drawing"). No skill names a model: the
  blueprint of a vehicle gives the numbers and the shapes of its model.

  A part from shape data (`part/3`) has its `shapes`, its `ports` (a name
  to `at`, `axis`, `up`), its `mass` (kg, from a data sheet), its
  `sources`, its `detail` (`always`, `near` or `low`) and `inside` (a
  part that a body hides). The joints are in the drawing.
  """
  alias World.{Drawing, Part}
  alias World.Orders.Blueprint

  @keys ~w(shapes ports mass sources detail inside)

  @doc "The errors of the data of a skill with `options` (`World.Orders.Blueprint.option/3`)."
  def check(data, path, options) do
    case Blueprint.check_options(options, data, path) do
      {:ok, _} -> []
      {:error, errors} -> errors
    end
  end

  @doc "The data of a skill with the default of each of its `options`."
  def o(data, options) do
    {:ok, full} = Blueprint.check_options(options, data, "")
    full
  end

  @doc "The errors of the data of a part from shape data."
  def check_part(data, path) when is_map(data) do
    World.Skill.keys(data, path, @keys, ~w(shapes)) ++
      if(Map.has_key?(data, "shapes"), do: Drawing.check_shapes(data["shapes"], path <> ".shapes"), else: []) ++
      optional(data, "ports", path, &Drawing.check_ports/2) ++
      optional(data, "mass", path, &mass/2) ++
      optional(data, "sources", path, &sources/2) ++
      optional(data, "detail", path, &choice(&1, &2, ~w(always near low))) ++
      optional(data, "inside", path, &choice(&1, &2, [true, false]))
  end

  def check_part(_data, path), do: [{path, "must be an object"}]

  defp optional(data, key, path, check),
    do: if(Map.has_key?(data, key), do: check.(data[key], "#{path}.#{key}"), else: [])

  defp mass(v, path),
    do: if(is_number(v) and v > 0 and v <= 100_000, do: [], else: [{path, "must be a mass in kg, more than 0"}])

  defp sources(v, path) do
    if is_list(v) and length(v) <= 16 and Enum.all?(v, &(is_binary(&1) and byte_size(&1) <= 500)),
      do: [],
      else: [{path, "must be a list of at most 16 texts of at most 500 bytes"}]
  end

  defp choice(v, path, values),
    do: if(v in values, do: [], else: [{path, "must be one of: #{Enum.join(values, ", ")}"}])

  @doc "The part of the node `name` of the kind `kind` from shape data (`check_part/2`)."
  def part(data, name, kind) do
    opts =
      [sources: Map.get(data, "sources", []), inside: Map.get(data, "inside", false)] ++
        if(d = data["detail"], do: [detail: String.to_existing_atom(d)], else: []) ++
        if(m = data["mass"], do: [params: %{"mass" => m / 1}], else: [])

    Part.new(name, kind, Enum.map(data["shapes"], &Drawing.mesh/1), Drawing.ports(Map.get(data, "ports", %{})), opts)
  end

  @doc "The triangles of a part from shape data at a level: an estimate, before the make."
  def estimate(data, level) do
    if check_part(data, "") == [],
      do: World.Detail.with(level, fn -> World.Construction.estimate(part(data, "estimate", :part), level) end),
      else: 0
  end
end
