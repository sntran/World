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
  - The **site**: a house or a tower is built where it stands.
  - A place can have a **terrain** (plan 0006, D4): the true ground of a
    place of the Vũng Tàu game (`World.Terrain`), with its lots at their
    points of the game. The hill of Núi Nhỏ (`nui_nho`) has the lot of
    the statue on its top and the lot of the cape of Nghinh Phong.

  The warehouse and each factory have a building: an order of a house
  that the people build (D7). The trucks are an order of a van.
  """

  alias World.{Part, Terrain}

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

  @doc """
  The lots of a place with a terrain, in their order: each with the
  height of its ground (m, over the sea) and its point on the yard
  (`"yard"`; the point of the place is the game point `origin` of its
  terrain). A place with no terrain has no lots.
  """
  def lots(%{"terrain" => t, "at" => [px, py]}) do
    [ox, oz] = t["origin"]

    for %{"at" => [x, z]} = l <- t["lots"] do
      Map.merge(l, %{"height" => Terrain.height(t["name"], {x, z}), "yard" => [px + x - ox, py + oz - z]})
    end
  end

  def lots(_place), do: []

  @doc "A lot of a place by its name (`lots/1`), or nil."
  def lot(place, name), do: Enum.find(lots(place), &(&1["name"] == name))

  @doc """
  The ground of a place with a terrain: a part with the mesh of its
  terrain in the box of the place, flat on each lot (`World.Terrain.mesh/7`),
  in the frame of World from the game point `origin` at the height of the
  sea (x east, y north, z up). So a model on a lot stands at the point
  of the lot and the height of its ground.
  """
  def ground(%{"terrain" => t} = place) do
    [ox, oz] = t["origin"]
    [x0, z0, x1, z1] = t["box"]
    pads = for %{"at" => [x, z]} = l <- lots(place), do: {x, z, l["radius"], l["height"]}
    mesh = Terrain.mesh(t["name"], {x0, z0, x1, z1}, t["step"], {ox, oz, 0.0}, :grass, pads)
    Part.new(place["name"] <> "_ground", :ground, [mesh], [])
  end

  @doc """
  The place of a model on a lot of a place with a terrain, in the frame
  of the game (plan 0006, D5; `World.Terrain.geo/3`).
  """
  def geo(place, lot) do
    %{"at" => [x, z], "height" => h, "turn" => turn} = lot(place, lot)
    Terrain.geo({x, z}, h, turn)
  end

  @doc """
  The places for the map of the world page: a place with a terrain has
  its lots (`lots/1`) and the path of its ground (`ground/1`, a GLB).
  """
  def view do
    for p <- all() do
      if p["terrain"],
        do:
          Map.update!(p, "terrain", &Map.merge(&1, %{"lots" => lots(p), "ground" => "/places/#{p["name"]}/ground.glb"})),
        else: p
    end
  end

  @doc "The trucks of the yard: `count`, `load_kg` and the `order` of each."
  def trucks, do: @data["trucks"]
end
