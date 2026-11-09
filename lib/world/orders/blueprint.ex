defmodule World.Orders.Blueprint do
  @moduledoc """
  A blueprint: a family of models with options (`docs/factory.md`). An
  order gives the options; the blueprint checks them, gives the default
  of each option that the order does not give, and builds the model.

  - `name`: the name of the blueprint in an order (`"person"`).
  - `doc`: what the blueprint builds.
  - `options`: a list of `World.Orders.Blueprint.Option`.
  - `build`: a function of the options (a map with a string key for each
    option) to a `World.Assembly` or a `World.Part`.
  - `check`: a function of the options to a list of errors, for the
    checks across options (a window must be in its wall). Each error is
    `{path, message}`.
  - `sources`: where the data of the blueprint comes from.
  """
  defstruct name: nil, doc: "", options: [], build: nil, check: nil, sources: []

  defmodule Option do
    @moduledoc """
    An option of a blueprint.

    - `type`: `:number`, `:integer`, `:choice`, `:boolean`, `:color`,
      `:list`, `:object`, or `:data` (any data of JSON that the function
      `check` checks: of the value and its path, to `{:ok, value}` or
      `{:error, errors}`).
    - `default`: the value when the order does not give one; `:required`
      when the order must give it.
    - `unit`: for a number (`"m"`, `"years"`).
    - `min`, `max`: the range of a number or an integer, and the most
      items of a list (`max`).
    - `values`: the values of a choice.
    - `item`: the option of each item of a list (its name is not used).
    - `presets`: the names of the presets of a list: the order can give
      the name in place of the list (the windows `"crew"` of a van), and
      the build makes the list of the preset.
    - `fields`: the options of an object.
    """
    defstruct name: nil,
              type: :number,
              default: :required,
              unit: nil,
              min: nil,
              max: nil,
              values: nil,
              item: nil,
              fields: nil,
              presets: nil,
              check: nil,
              doc: ""
  end

  @doc "An option: the name, the type, and the keys of `World.Orders.Blueprint.Option`."
  def option(name, type, opts \\ []), do: struct!(Option, [name: name, type: type] ++ opts)

  @doc """
  A blueprint in data (`priv/blueprints/NAME.json`, `docs/format.md`): its
  `name`, `doc`, `sources`, `params` (the options) and `drawing`, a
  drawing whose values can be `{"param": NAME}` (`World.Drawing.fill/2`).
  A param has the keys of an option (`type`, `default`, `min`, `max`,
  `unit`, `values`, `item`, `fields`, `doc`); with no `default`, an order
  must give it. Two types are for data only: `text` (at most `max` bytes,
  200 by default), `sources` (the source of each name of the `sizes` of
  the blueprint: `World.Sizes`) and `skill` (a value that the skill
  `skill` checks, as the key of the name of the param in its data).
  """
  def from_data(raw) do
    sized = for s <- Map.get(raw, "sizes", []), do: s["name"]

    %__MODULE__{
      name: raw["name"],
      doc: Map.get(raw, "doc", ""),
      options: for(p <- Map.get(raw, "params", []), do: param(p, sized)),
      build: fn o -> World.Drawing.build(World.Drawing.fill(raw, o)) end,
      check: fn o ->
        case World.Drawing.check(World.Drawing.fill(raw, o), "drawing") do
          {:ok, _} -> []
          {:error, errors} -> errors
        end
      end,
      sources: Map.get(raw, "sources", [])
    }
  end

  @types ~w(number integer choice boolean color list object text sources skill materials)
  @param_keys ~w(name type default unit min max values item fields doc skill)

  @doc """
  The errors of a blueprint in data from a project (plan 0002, D1), each
  `{path, message}` with the path from `path`: its keys, its `name`, each
  param (its keys, its type, the `values` of a choice, the `item` of a
  list, the `fields` of an object, the `skill` of a param of the type
  skill), and its drawing with the default of each param: the errors of
  the data of each skill (`World.Drawing.check/2`). `[]` when the
  blueprint is good.
  """
  def check_data(raw, path) when is_map(raw) do
    keys = World.Skill.keys(raw, path, ~w(name doc sources params sizes drawing), ~w(name drawing))

    name =
      if Map.has_key?(raw, "name") and not name?(raw["name"]),
        do: [{path <> ".name", "must be a name: a to z, 0 to 9 and _, 1 to 40"}],
        else: []

    params =
      case Map.get(raw, "params", []) do
        list when is_list(list) ->
          list |> Enum.with_index() |> Enum.flat_map(fn {p, i} -> param_errors(p, "#{path}.params.#{i}") end)

        _ ->
          [{path <> ".params", "must be a list"}]
      end

    drawing =
      if Map.has_key?(raw, "drawing") and not is_map(raw["drawing"]),
        do: [{path <> ".drawing", "must be an object"}],
        else: []

    case keys ++ name ++ params ++ drawing do
      [] -> drawing_errors(raw, path)
      errors -> errors
    end
  end

  def check_data(_raw, path), do: [{path, "must be an object"}]

  defp name?(name), do: is_binary(name) and name =~ ~r/^[a-z0-9_]{1,40}$/

  defp param_errors(p, path) when is_map(p) do
    keys =
      World.Skill.keys(p, path, @param_keys, ~w(type) ++ if(String.ends_with?(path, ".item"), do: [], else: ~w(name)))

    type =
      case p["type"] do
        t when t in @types -> type_errors(t, p, path)
        nil -> []
        _ -> [{path <> ".type", "must be one of: #{Enum.join(@types, ", ")}"}]
      end

    keys ++ type
  end

  defp param_errors(_p, path), do: [{path, "must be an object"}]

  defp type_errors("choice", %{"values" => [_ | _] = values}, path),
    do: if(Enum.all?(values, &is_binary/1), do: [], else: [{path <> ".values", "must be a list of texts"}])

  defp type_errors("choice", _p, path), do: [{path <> ".values", "must be a list of texts"}]
  defp type_errors("list", %{"item" => item}, path), do: param_errors(item, path <> ".item")
  defp type_errors("list", _p, path), do: [{path <> ".item", "is required"}]

  defp type_errors("object", %{"fields" => fields}, path) when is_list(fields),
    do: fields |> Enum.with_index() |> Enum.flat_map(fn {f, i} -> param_errors(f, "#{path}.fields.#{i}") end)

  defp type_errors("object", _p, path), do: [{path <> ".fields", "must be a list"}]

  defp type_errors("skill", p, path),
    do:
      if(World.Skills.fetch(p["skill"]) == :error,
        do: [{path <> ".skill", "must be a skill: #{Enum.join(World.Skills.names(), ", ")}"}],
        else: []
      )

  defp type_errors(_type, _p, _path), do: []

  # The drawing with the default of each param: the errors of the data of
  # its nodes. A param with no default: the order gives it, and checks it.
  defp drawing_errors(raw, path) do
    b = from_data(raw)

    with {:ok, o} <- check_options(b.options, %{}, path <> ".params"),
         {:error, errors} <- World.Drawing.check(World.Drawing.fill(raw, o), path <> ".drawing") do
      errors
    else
      _ -> []
    end
  end

  defp param(p, sized) do
    opts = [
      default: Map.get(p, "default", :required),
      unit: p["unit"],
      min: p["min"],
      max: p["max"],
      values: p["values"],
      doc: Map.get(p, "doc", "")
    ]

    case p["type"] do
      "list" -> option(p["name"], :list, opts ++ [item: param(p["item"], sized)])
      "object" -> option(p["name"], :object, opts ++ [fields: for(f <- p["fields"], do: param(f, sized))])
      "text" -> option(p["name"], :data, opts ++ [check: &text(&1, &2, p["max"] || 200)])
      "sources" -> option(p["name"], :data, opts ++ [check: &World.Sizes.check(&1, &2, sized)])
      "skill" -> option(p["name"], :data, opts ++ [check: &by_skill(&1, &2, p)])
      "materials" -> option(p["name"], :data, opts ++ [check: &World.Drawing.check_materials/2])
      type -> option(p["name"], String.to_existing_atom(type), opts)
    end
  end

  # A value that a skill checks as one key of its data (`skill`): the light
  # of a tower is checked by the skill tower_site.
  defp by_skill(raw, path, %{"name" => name, "skill" => skill}) do
    {:ok, mod} = World.Skills.fetch(skill)

    case mod.check(%{name => raw}, String.replace_suffix(path, "." <> name, "")) do
      [] -> {:ok, raw}
      errors -> {:error, errors}
    end
  end

  defp text(raw, _path, max) when is_binary(raw) and byte_size(raw) <= max, do: {:ok, raw}
  defp text(_, path, max), do: {:error, [{path, "must be a text of at most #{max} bytes"}]}

  @doc """
  Check the options of an order (a map with string keys) against the
  options of a blueprint. Gives `{:ok, options}` with a value for each
  option, or `{:error, errors}`: each error is `{path, message}`, with
  the path from `prefix` (`"options.age"`).
  """
  def check_options(options, given, prefix) when is_map(given) do
    known = MapSet.new(options, & &1.name)

    unknown =
      for key <- Enum.sort(Map.keys(given)),
          not MapSet.member?(known, key),
          do: {"#{prefix}.#{key}", "is not an option"}

    {values, errors} =
      Enum.reduce(options, {%{}, unknown}, fn o, {values, errors} ->
        path = "#{prefix}.#{o.name}"

        case {Map.fetch(given, o.name), o.default} do
          {:error, :required} -> {values, errors ++ [{path, "is required"}]}
          {:error, default} -> {Map.put(values, o.name, default), errors}
          # The full order gives null for an option with no value by default.
          {{:ok, nil}, nil} -> {Map.put(values, o.name, nil), errors}
          {{:ok, raw}, _} -> put(values, errors, o.name, value(o, raw, path))
        end
      end)

    if errors == [], do: {:ok, values}, else: {:error, errors}
  end

  def check_options(_options, _given, prefix), do: {:error, [{prefix, "must be an object"}]}

  defp put(values, errors, name, {:ok, v}), do: {Map.put(values, name, v), errors}
  defp put(values, errors, _name, {:error, more}), do: {values, errors ++ more}

  @doc """
  The value of an option from an order. A number, an integer and a yes
  or no can also come as a string (from the query of a URL), and a list
  as a string of items with commas.
  """
  def value(%Option{type: :number} = o, raw, path) do
    case number(raw) do
      {:ok, x} -> range(o, x / 1, path)
      :error -> {:error, [{path, "must be a number"}]}
    end
  end

  def value(%Option{type: :integer} = o, raw, path) do
    case number(raw) do
      {:ok, x} when x == trunc(x) -> range(o, trunc(x), path)
      _ -> {:error, [{path, "must be an integer"}]}
    end
  end

  def value(%Option{type: :choice, values: values}, raw, path) do
    if raw in values, do: {:ok, raw}, else: {:error, [{path, "must be one of: #{Enum.join(values, ", ")}"}]}
  end

  def value(%Option{type: :boolean}, raw, path) do
    case raw do
      b when is_boolean(b) -> {:ok, b}
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:error, [{path, "must be true or false"}]}
    end
  end

  def value(%Option{type: :color}, raw, path) do
    if is_binary(raw) and Regex.match?(~r/^#[0-9a-fA-F]{6}$/, raw),
      do: {:ok, String.downcase(raw)},
      else: {:error, [{path, "must be a color #rrggbb"}]}
  end

  def value(%Option{type: :list, presets: [_ | _] = presets} = o, raw, path) when is_binary(raw) do
    if raw in presets, do: {:ok, raw}, else: value(%{o | presets: nil}, raw, path)
  end

  def value(%Option{type: :list} = o, raw, path) when is_binary(raw),
    do: value(o, if(raw == "", do: [], else: String.split(raw, ",")), path)

  def value(%Option{type: :list, item: item, max: max}, raw, path) when is_list(raw) do
    if max && length(raw) > max do
      {:error, [{path, "must have at most #{max} items"}]}
    else
      results = for {x, i} <- Enum.with_index(raw), do: value(item, x, "#{path}.#{i}")
      errors = for {:error, e} <- results, do: e

      if errors == [],
        do: {:ok, for({:ok, v} <- results, do: v)},
        else: {:error, List.flatten(errors)}
    end
  end

  def value(%Option{type: :list}, _raw, path), do: {:error, [{path, "must be a list"}]}
  def value(%Option{type: :object, fields: fields}, raw, path), do: check_options(fields, raw, path)
  def value(%Option{type: :data, check: check}, raw, path), do: check.(raw, path)

  defp number(x) when is_number(x), do: {:ok, x}

  defp number(s) when is_binary(s) do
    case Float.parse(s) do
      {x, ""} -> {:ok, x}
      _ -> :error
    end
  end

  defp number(_), do: :error

  defp range(%Option{min: min, max: max, unit: unit}, x, path) do
    if (min == nil or x >= min) and (max == nil or x <= max),
      do: {:ok, x},
      else: {:error, [{path, "must be from #{min} to #{max}#{if unit, do: " " <> unit}"}]}
  end

  @doc "A blueprint as JSON data (the page `/blueprints` of the factory)."
  def describe(%__MODULE__{} = b) do
    %{"name" => b.name, "doc" => b.doc, "options" => Enum.map(b.options, &describe_option/1), "sources" => b.sources}
  end

  defp describe_option(%Option{} = o) do
    %{
      "name" => o.name,
      "type" => Atom.to_string(o.type),
      "default" => if(o.default == :required, do: nil, else: o.default),
      "required" => o.default == :required,
      "unit" => o.unit,
      "min" => o.min,
      "max" => o.max,
      "values" => o.values,
      "presets" => o.presets,
      "item" => if(o.item, do: describe_option(o.item)),
      "fields" => if(o.fields, do: Enum.map(o.fields, &describe_option/1)),
      "doc" => o.doc
    }
    |> Map.reject(fn {_, v} -> v == nil end)
  end
end
