defmodule World.Standards do
  @moduledoc """
  The standards of the world (`docs/world.md`, step P3): the sizes of the
  standard parts, in `priv/standards/*.json`, read when the module
  compiles (a literal of the module: no read of a file at run time; a new
  file compiles the module again).

  - `fasteners.json`: metric bolts, nuts, washers and screws (ISO 4014,
    4017, 4032, 7089, 4762, 7380), wood screws (ASME B18.6.1), inch
    threads (ASME B18.2.1, B18.2.2, B18.3).
  - `stock.json`: US softwood lumber (PS 20), deep groove ball bearings
    (ISO 15), steel pipe (ASME B36.10M).
  - `masonry.json`: bricks and concrete blocks (TCVN 1451, ASTM C216,
    ASTM C90), each with its source.

  Each table has its source, its unit, the names of its fields and its
  sizes. `size/2` gives the sizes of a name; `name!/2` checks a literal
  name when the code compiles (a wrong name stops the compile); `part/1`
  makes a part from its standard name (`{:bolt, "M8x40"}`).
  """

  @dir Path.expand("../../priv/standards", __DIR__)
  @files Path.wildcard(Path.join(@dir, "*.json"))
  for file <- @files, do: @external_resource(file)

  # The tables: `{file, table}` to `%{source, unit, fields, sizes}`.
  @tables (for file <- @files,
               {table, %{"sizes" => _} = t} <- JSON.decode!(File.read!(file)),
               into: %{} do
             {{Path.basename(file, ".json"), table}, t}
           end)

  # A new file of the standards compiles the module again.
  def __mix_recompile__?, do: Enum.sort(Path.wildcard(Path.join(@dir, "*.json"))) != Enum.sort(@files)

  @doc """
  The tables of the standards: a list of `{file, table}`.

      iex> {"fasteners", "hex_head"} in World.Standards.tables()
      true
  """
  def tables, do: @tables |> Map.keys() |> Enum.sort()

  @doc """
  A table: `%{"source", "unit", "fields", "sizes"}`.

      iex> World.Standards.table("stock", "pipe")["unit"]
      "in"
  """
  def table(file, table), do: Map.get(@tables, {file, table}) || raise(ArgumentError, "no table #{file}/#{table}")

  @doc """
  The sizes of a name in a table, as the file has them (a list, a number
  or a map), in the unit of the table.

      iex> World.Standards.size({"fasteners", "hex_head"}, "M8")
      [13.0, 5.3]
      iex> World.Standards.size({"stock", "lumber"}, "2x4")
      [1.5, 3.5]
  """
  def size({file, t}, name),
    do: Map.get(table(file, t)["sizes"], name) || raise(ArgumentError, "no #{name} in #{file}/#{t}")

  @doc """
  The sizes of a table as tuples (a list of numbers is a tuple; a number
  stays a number), by name: the tables of the code of the parts.

      iex> World.Standards.tuples({"stock", "bearing"})["6204"]
      {20, 47, 14}
  """
  def tuples({file, t}) do
    Map.new(table(file, t)["sizes"], fn
      {name, [_ | _] = l} -> {name, List.to_tuple(l)}
      {name, x} -> {name, x}
    end)
  end

  @doc "The names of a table, in order."
  def names({file, t}), do: table(file, t)["sizes"] |> Map.keys() |> Enum.sort()

  @doc "If a table has a name."
  def known?({file, t}, name), do: Map.has_key?(Map.get(@tables, {file, t}, %{"sizes" => %{}})["sizes"], name)

  @doc """
  The name of a size of a table, checked when the code compiles if it is
  a literal: a wrong name stops the compile.
  """
  defmacro name!(table, name) do
    with {file, t} when is_binary(file) and is_binary(t) <- table, true <- is_binary(name) do
      unless known?({file, t}, name) do
        raise CompileError,
          file: __CALLER__.file,
          line: __CALLER__.line,
          description: "no #{name} in the standard #{file}/#{t}"
      end
    end

    name
  end

  @doc """
  A part by its standard name: `{:bolt, "M8x40"}` (a hexagon head bolt,
  M8, 40 mm long), `{:cap_screw, "M6x20"}`, `{:nut, "M8"}`, `{:washer,
  "M8"}`, `{:bearing, "6204"}`, `{:lumber, "2x4", length}`, `{:pipe, "1",
  :sch40, length}` (meters), `{:masonry, "brick_vn"}`.
  """
  def part({:bolt, name}), do: with({t, l} <- threaded(name), do: World.Materials.Fasteners.bolt(t, l))
  def part({:cap_screw, name}), do: with({t, l} <- threaded(name), do: World.Materials.Fasteners.cap_screw(t, l))
  def part({:nut, thread}), do: World.Materials.Fasteners.nut(thread)
  def part({:washer, thread}), do: World.Materials.Fasteners.washer(thread)
  def part({:bearing, code}), do: World.Materials.Stock.bearing(code)
  def part({:lumber, nominal, length}), do: World.Materials.Stock.lumber(nominal, length)
  def part({:pipe, nps, schedule, length}), do: World.Materials.Stock.pipe(nps, schedule, length)
  def part({:masonry, name}), do: World.Materials.Construction.masonry(name)

  # "M8x40": the thread and the length (m).
  defp threaded(name) do
    [thread, length] = String.split(name, "x")
    size({"fasteners", "hex_head"}, thread)
    {thread, String.to_integer(length) / 1000}
  end
end
