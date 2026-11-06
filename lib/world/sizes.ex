defmodule World.Sizes do
  @moduledoc """
  The sizes of an order of a known place (W13 of Vũng Tàu: a statue, a
  tower) with their sources: each size goes into the extras of the model
  (`"sizes"`) and into the receipt with its value, its unit and its
  source. A size with no source is an estimate, and says so.
  """

  @none "estimate (no source)"

  @doc "The source of a size that has none."
  def none, do: @none

  @doc """
  The list of the sizes of the options `o` (a map with atom keys): each
  `{key, unit}` with a value, with its source from `sources` (a map of the
  name of a size to a text). A unit of nil gives no unit.

      iex> World.Sizes.list(%{height: 18.0, span: nil}, [height: "m", span: "m"], %{"height" => "OSM"})
      [%{"name" => "height", "value" => 18.0, "unit" => "m", "source" => "OSM"}]
  """
  def list(o, keys, sources) do
    for {key, unit} <- keys, v = Map.fetch!(o, key), v != nil do
      name = Atom.to_string(key)
      entry = %{"name" => name, "value" => value(v), "source" => sources[name] || @none}
      if unit, do: Map.put(entry, "unit", unit), else: entry
    end
  end

  defp value(v) when is_tuple(v), do: v |> Tuple.to_list() |> Enum.map(&value/1)
  defp value(v) when is_list(v), do: Enum.map(v, &value/1)
  defp value(v), do: v

  @doc """
  A check of the sources of an order: a map of the name of a size (one of
  `names`) to a text of at most 500 characters.

      iex> World.Sizes.check(%{"height" => "OSM"}, "options.sources", ["height"])
      {:ok, %{"height" => "OSM"}}
      iex> World.Sizes.check(%{"x" => "OSM"}, "options.sources", ["height"])
      {:error, [{"options.sources.x", "must be a size (height) with a text of at most 500 characters"}]}
      iex> World.Sizes.check("OSM", "options.sources", ["height"])
      {:error, [{"options.sources", "must be a map of the name of a size to its source"}]}
  """
  def check(raw, path, names) when is_map(raw) do
    errors =
      for {k, v} <- raw, not (k in names and is_binary(v) and String.length(v) <= 500) do
        {"#{path}.#{k}", "must be a size (#{Enum.join(names, ", ")}) with a text of at most 500 characters"}
      end

    if errors == [], do: {:ok, raw}, else: {:error, errors}
  end

  def check(_, path, _), do: {:error, [{path, "must be a map of the name of a size to its source"}]}
end
