defmodule World.Places do
  @moduledoc """
  The places of the yard of the node (plan 0002, D6; `priv/places.json`):
  the gate of the suppliers, the warehouse, the factories and the site,
  each at a point in meters on one flat plane, with the stock of the
  warehouse and the trucks of the yard.

  - A **supplier** (the gate) brings the materials from outside, and
    rents a truck with its driver until the yard has trucks of its own.
  - The **warehouse** keeps the stock (`World.Stock`).
  - A **factory** makes the things of its kinds: a construction of a
    model of such a kind is at the factory, and its materials come there
    by truck.
  - The **site**: a house, a statue or a tower is built where it stands.

  The warehouse and each factory have a building: an order of a house
  that the people build (D7). The trucks are an order of a van.
  """

  @external_resource path = Path.join([__DIR__, "..", "..", "priv", "places.json"])
  @data path |> File.read!() |> JSON.decode!()

  @doc "The data of the yard: the places, the stock, the trucks."
  def data, do: @data

  @doc "The places, in their order."
  def all, do: @data["places"]

  @doc "A place by its name: `{:ok, place}` or `:error`."
  def fetch(name) do
    case Enum.find(all(), &(&1["name"] == name)) do
      nil -> :error
      p -> {:ok, p}
    end
  end

  @doc "The place where a model of a kind (`\"vehicle\"`, `\"house\"`) is built, or nil."
  def for_kind(kind), do: Enum.find_value(all(), &(kind in Map.get(&1, "kinds", []) && &1["name"]))

  @doc "The distance in meters between two places, on a straight line of the yard."
  def distance(a, b) do
    {:ok, %{"at" => [x0, y0]}} = fetch(a)
    {:ok, %{"at" => [x1, y1]}} = fetch(b)
    :math.sqrt((x1 - x0) ** 2 + (y1 - y0) ** 2)
  end

  @doc """
  The world time of a drive between two places, in milliseconds: the
  distance at the speed limit of the yard (`speed_kmh`).
  """
  def drive(a, b), do: round(distance(a, b) / (@data["speed_kmh"] / 3.6) * 1000)

  @doc "The places with a building, in their order: the warehouse and the factories."
  def buildings, do: for(p <- all(), Map.has_key?(p, "building"), do: p)

  @doc "The trucks of the yard: `count`, `load_kg` and the `order` of each."
  def trucks, do: @data["trucks"]
end
