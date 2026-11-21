defmodule World.Drawing.Catalog do
  @moduledoc """
  The drawings of the catalog (`priv/drawings/NAME.json`), read when the
  module compiles (a new file compiles the module again). Their check
  needs the catalog (a drawing holds other models), so a test checks each
  one (`check_all!/1`).

  They are not in `World.Drawing`: the version of a rule
  (`World.Elements.version/1`) has the data files of each module that the
  rule calls, and a rule that makes a drawing from an order does not read
  the catalog. So a new drawing of the catalog does not change the key of
  each part of each drawing.
  """
  alias World.Drawing
  alias World.Orders.Blueprints

  @root Path.expand("../../../priv/drawings", __DIR__)
  @files Path.wildcard(Path.join(@root, "*.json"))
  for f <- @files, do: @external_resource(f)
  @drawings Map.new(@files, fn f -> {Path.basename(f, ".json"), f |> File.read!() |> JSON.decode!()} end)
  @hash :erlang.md5(Enum.join(@files))

  @doc false
  def __mix_recompile__?, do: :erlang.md5(Enum.join(Path.wildcard(Path.join(@root, "*.json")))) != @hash

  @doc """
  The assembly of a model of the catalog in `priv/drawings/NAME.json`: a
  drawing, or an order of a blueprint (a blueprint in data with its
  options: the statue on Núi Nhỏ). A name with no file raises.
  """
  def file(name) do
    case raw(name) || raise(ArgumentError, "no drawing #{inspect(name)}") do
      %{"blueprint" => _} = order ->
        {:ok, full} = World.Orders.check(order)
        {:ok, blueprint} = Blueprints.fetch(full["blueprint"])
        blueprint.build.(full["options"])

      raw ->
        {:ok, raw} = Drawing.check(raw, name)
        Drawing.build(raw)
    end
  end

  @doc "The data of the file `priv/drawings/NAME.json`, or nil."
  def raw(name), do: Map.get(@drawings, name)

  @doc "The names of the drawings of the catalog, in order."
  def names, do: @drawings |> Map.keys() |> Enum.sort()

  @doc """
  The names of the drawings (of `drawings`, by default the drawings of the
  catalog), after a check of each one (an order of a blueprint with
  `World.Orders.check/1`): a drawing with errors raises an
  `ArgumentError` with its errors.
  """
  def check_all!(drawings \\ @drawings) do
    for {name, raw} <- Enum.sort(drawings) do
      result = if raw["blueprint"], do: World.Orders.check(raw), else: Drawing.check(raw, name)

      case result do
        {:ok, _} -> name
        {:error, errors} -> raise ArgumentError, "the drawing #{name} has errors: #{inspect(errors)}"
      end
    end
  end
end
