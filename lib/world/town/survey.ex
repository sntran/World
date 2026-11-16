defmodule World.Town.Survey do
  @moduledoc """
  The survey of a real street (`priv/surveys/NAME.json`;
  `docs/plans/0018-quang-trung-street.md`): one row for each lot, in
  the order of the street, with what is known of the lot and where each
  value comes from.

  A survey has `note`, `street` (its name, its city, its length),
  `sources` (the photos, the data and the pages that it reads) and
  `rows`. A row has an `id`, its `side` of the street, the `number` and
  the `name` of the lot, `width_m` and `depth_m`, `storeys`, `use`,
  `type`, `marks` (where each value comes from; `GUESS` is a guess) and
  descriptions from the photos. A row that the rules of
  `World.Town.House` can make has `house`: the keys of the request of
  that house that the survey knows.

  `lots/1` gives the lots of rows for the plan of a street
  (`World.Town.Street.plan/1`).
  """

  @dir Path.expand("../../../priv/surveys", __DIR__)
  @files Path.wildcard(Path.join(@dir, "*.json"))
  for f <- @files, do: @external_resource(f)
  @surveys Map.new(@files, fn f -> {Path.basename(f, ".json"), f |> File.read!() |> JSON.decode!()} end)

  # A house of the rules is not wider than this: a wider row is one building on two lots or more.
  @wide 8.0

  @doc "The names of the surveys."
  def names, do: @surveys |> Map.keys() |> Enum.sort()

  @doc "The survey of a name (raises for a name with no survey)."
  def survey(name), do: Map.get(@surveys, name) || raise(ArgumentError, "no survey #{inspect(name)}")

  @doc """
  The rows of a survey from one row to another (their ids), in their
  order: a block of a street.
  """
  def rows(name, first, last) do
    rows = survey(name)["rows"]
    index = fn id -> Enum.find_index(rows, &(&1["id"] == id)) || raise(ArgumentError, "no row #{inspect(id)}") end
    Enum.slice(rows, index.(first)..index.(last)//1)
  end

  @doc """
  The lots of rows for the plan of a street: for each row with `house`,
  its keys with the width, the depth, the number and the name of the
  row. A row wider than 8 m is one building on lots of the same width:
  each lot after the first has `same` (it takes the choices of the lot
  before it). A row with no `house` is not a lot of houses: it raises.
  """
  def lots(rows) do
    Enum.flat_map(rows, fn row ->
      house = row["house"] || raise(ArgumentError, "the row #{row["id"]} is not a house of the rules")
      count = ceil(row["width_m"] / @wide)

      lot =
        Map.merge(house, %{
          "width" => Float.round(row["width_m"] / count, 3),
          "depth" => row["depth_m"] * 1.0,
          "number" => row["number"],
          "name" => row["name"]
        })

      [lot | List.duplicate(Map.put(lot, "same", true), count - 1)]
    end)
  end
end
