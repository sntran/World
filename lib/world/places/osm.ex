defmodule World.Places.OSM do
  @moduledoc """
  Places from OpenStreetMap (`docs/world.md`, step P8): a tile of the
  data of OpenStreetMap (`priv/osm/NAME.json`, © OpenStreetMap
  contributors, ODbL 1.0) gives a street of World:

  - each building: its footprint, up to its height (`height`, or
    `building:levels` at 3.5 m a level, or 2 levels when the data has
    neither), with a flat roof and its parapet, and at the near level a
    band at each floor;
  - each road: a strip of asphalt of its width (`width`, or the width of
    its kind), cut at the box of the tile, and at the near level a curb on
    each side;
  - each tree: a plant of the nursery (`World.Plants`), of its species
    when the data has it (`genus`, `species`), else a frangipani.

  The points go from latitude and longitude to meters on a plane at the
  center of the box of the tile: x to the east, y to the north (the
  lengths of a degree of the WGS 84 ellipsoid at that latitude). A street
  is an assembly of the kind `:street`: it is built on its site.
  """
  alias World.{Assembly, Detail, Frame, Part, Shape}

  @dir Path.expand("../../../priv/osm", __DIR__)
  @files Path.wildcard(Path.join(@dir, "*.json"))
  for f <- @files, do: @external_resource(f)
  @tiles Map.new(@files, fn f -> {Path.basename(f, ".json"), f |> File.read!() |> JSON.decode!()} end)

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  # The height of a level of a building in Việt Nam: 3.3 to 3.6 m for a
  # tube house (an estimate), and the levels of a building with no data.
  @level 3.5
  @levels 2
  # The width of a road of each kind, when the data has none (m): an
  # estimate from the streets of the center of Vũng Tàu.
  @widths %{
    "primary" => 14.0,
    "secondary" => 12.0,
    "tertiary" => 10.0,
    "residential" => 7.0,
    "service" => 4.0,
    "footway" => 2.0
  }
  @parapet 0.9

  @doc "The names of the tiles."
  def tiles, do: @tiles |> Map.keys() |> Enum.sort()

  @doc "The data of a tile (raises for a name with no tile)."
  def tile(name), do: Map.get(@tiles, name) || raise(ArgumentError, "no tile #{inspect(name)}")

  @doc """
  The point `{x, y}` (m) of `[lat, lon]` on the plane of a tile whose
  center is at `{lat0, lon0}`: the lengths of a degree of latitude and of
  longitude of WGS 84 at `lat0`.

      iex> {x, y} = World.Places.OSM.point([10.0009, 107.0], {10.0, 107.0})
      iex> {Float.round(x, 6), Float.round(y, 1)}
      {0.0, 99.5}
  """
  def point([lat, lon], {lat0, lon0}) do
    phi = lat0 * :math.pi() / 180
    m_lat = 111_132.92 - 559.82 * :math.cos(2 * phi) + 1.175 * :math.cos(4 * phi)
    m_lon = 111_412.84 * :math.cos(phi) - 93.5 * :math.cos(3 * phi)
    {(lon - lon0) * m_lon, (lat - lat0) * m_lat}
  end

  @doc "The center of the box of a tile: `{lat, lon}`."
  def center(%{"bbox" => [s, w, n, e]}), do: {(s + n) / 2, (w + e) / 2}

  @doc "The height of a building from its tags (m)."
  def height(tags) do
    cond do
      h = number(tags["height"]) -> h
      l = number(tags["building:levels"]) -> l * @level
      true -> @levels * @level
    end
  end

  @doc "The width of a road from its tags (m)."
  def width(tags), do: number(tags["width"]) || Map.get(@widths, tags["highway"], 5.0)

  defp number(nil), do: nil

  defp number(s) do
    case Float.parse(String.trim(s)) do
      {v, ""} -> v
      _ -> nil
    end
  end

  @doc """
  The street of a tile: its buildings, its roads and its trees. The
  option `name` of the assembly.
  """
  def street(name, opts \\ []) do
    t = tile(name)
    c = center(t)

    buildings = for b <- t["buildings"], loop = loop(b["points"], c), length(loop) >= 3, do: building(loop, b["tags"])
    box = box(t, c)
    roads = for r <- t["roads"], line = Enum.map(r["points"], &point(&1, c)), do: road(line, r["tags"], box)

    ground = Part.new("ground_" <> name, :ground, [ground(t, c)], [@o], sources: [t["note"]])

    asm =
      Assembly.new(Keyword.get(opts, :name, "street_" <> name), ground,
        root: "ground_" <> name,
        kind: :street,
        sources: [t["note"]],
        extras: %{
          "tile" => name,
          "bbox" => t["bbox"],
          "license" => "ODbL-1.0",
          "attribution" => "© OpenStreetMap contributors"
        }
      )
      |> Assembly.add("buildings", Part.new("buildings_" <> name, :building, List.flatten(buildings), [@o]),
        at: "o",
        port: "o"
      )
      |> Assembly.add("roads", Part.new("roads_" <> name, :road, List.flatten(roads), [@o]), at: "o", port: "o")

    t["trees"]
    |> Enum.with_index(1)
    |> Enum.reduce(asm, fn {tree, i}, asm ->
      {x, y} = point(tree["at"], c)

      Assembly.add(asm, "tree_#{i}", plant(tree["tags"]),
        at: Part.port("tree_#{i}", {x, y, 0.0}, {0, 0, 1}, {0, 1, 0}),
        port: "o"
      )
    end)
  end

  # The points of a closed way on the plane, with no last point (the
  # first one again), counterclockwise.
  defp loop(points, c) do
    pts = points |> Enum.map(&point(&1, c)) |> Enum.dedup()
    pts = if hd(pts) == List.last(pts), do: Enum.drop(pts, -1), else: pts
    if area(pts) < 0, do: Enum.reverse(pts), else: pts
  end

  defp area(pts) do
    pts
    |> Enum.zip(tl(pts) ++ [hd(pts)])
    |> Enum.map(fn {{x0, y0}, {x1, y1}} -> x0 * y1 - x1 * y0 end)
    |> Enum.sum()
    |> Kernel./(2)
  end

  # A building: the walls up to the roof, a parapet round the roof, and
  # at the near level a band at each floor.
  defp building(loop, tags) do
    h = height(tags)
    walls = Shape.prism(loop, h, :plaster)
    parapet = Shape.prism(loop, @parapet, :plaster, frame: Frame.move({0.0, 0.0, h}))

    bands =
      if Detail.level() == :near do
        for k <- 1..max(round(h / @level) - 1, 0)//1 do
          Shape.prism(grow(loop, 0.08), 0.2, :concrete, frame: Frame.move({0.0, 0.0, k * @level - 0.1}))
        end
      else
        []
      end

    if Detail.level() == :far, do: [walls], else: [walls, parapet | bands]
  end

  # A loop moved out from its center (a band that stands out of a wall).
  defp grow(loop, d) do
    n = length(loop)
    {cx, cy} = {Enum.sum(Enum.map(loop, &elem(&1, 0))) / n, Enum.sum(Enum.map(loop, &elem(&1, 1))) / n}

    for {x, y} <- loop do
      {dx, dy} = {x - cx, y - cy}
      l = :math.sqrt(dx * dx + dy * dy)
      if l < 1.0e-9, do: {x, y}, else: {x + d * dx / l, y + d * dy / l}
    end
  end

  # A road: a strip of asphalt on each segment of its line, and at the
  # near level a curb at each side of a road for cars.
  defp road(line, tags, box) do
    w = width(tags)
    car = tags["highway"] in ~w(primary secondary tertiary residential)

    for [p, q] <- Enum.chunk_every(line, 2, 1, :discard), {a, b} <- List.wrap(clip(p, q, box)), a != b do
      strip = strip(a, b, w, 0.0, 0.02, :asphalt)

      curbs =
        if car and Detail.level() == :near,
          do:
            for(
              s <- [-1, 1],
              do: strip(offset(a, b, s * w / 2), offset_end(a, b, s * w / 2), 0.15, 0.0, 0.15, :concrete)
            ),
          else: []

      [strip | curbs]
    end
  end

  # A box along the segment from `a` to `b`, `w` wide, from `z0` to `z1`.
  defp strip({x0, y0}, {x1, y1}, w, _lift, h, material) do
    {dx, dy} = {x1 - x0, y1 - y0}
    l = :math.sqrt(dx * dx + dy * dy)
    {nx, ny} = {-dy / l * w / 2, dx / l * w / 2}
    loop = [{x0 - nx, y0 - ny}, {x1 - nx, y1 - ny}, {x1 + nx, y1 + ny}, {x0 + nx, y0 + ny}]
    Shape.prism(loop, h, material)
  end

  defp offset({x0, y0}, {x1, y1}, d) do
    {dx, dy} = {x1 - x0, y1 - y0}
    l = :math.sqrt(dx * dx + dy * dy)
    {x0 - dy / l * d, y0 + dx / l * d}
  end

  defp offset_end(a, b, d), do: offset(b, a, -d)

  # The box of the tile on its plane: `{x0, y0, x1, y1}`.
  defp box(%{"bbox" => [s, w, n, e]}, c) do
    {x0, y0} = point([s, w], c)
    {x1, y1} = point([n, e], c)
    {x0, y0, x1, y1}
  end

  # The part of a segment in a box (the method of Liang and Barsky), or
  # nil when it is all out of the box.
  defp clip({ax, ay} = a, {bx, by}, {x0, y0, x1, y1}) do
    {dx, dy} = {bx - ax, by - ay}
    edges = [{-dx, ax - x0}, {dx, x1 - ax}, {-dy, ay - y0}, {dy, y1 - ay}]

    result =
      Enum.reduce_while(edges, {0.0, 1.0}, fn {p, q}, {t0, t1} ->
        cond do
          p == 0 and q < 0 -> {:halt, nil}
          p == 0 -> {:cont, {t0, t1}}
          p < 0 -> {:cont, {max(t0, q / p), t1}}
          true -> {:cont, {t0, min(t1, q / p)}}
        end
      end)

    case result do
      {t0, t1} when t0 < t1 -> {at(a, dx, dy, t0), at(a, dx, dy, t1)}
      _ -> nil
    end
  end

  defp at({x, y}, dx, dy, t), do: {x + dx * t, y + dy * t}

  # The ground of the tile: its box, flat, under the roads.
  defp ground(t, c) do
    {x0, y0, x1, y1} = box(t, c)
    Shape.box({x0, y0, -0.1}, {x1, y1, 0.0}, :ground)
  end

  # A tree of the data: of its genus, or a frangipani when the data does
  # not say. A tree at the near level of the street is built at mid, and
  # at mid at far: a street has many trees.
  defp plant(tags) do
    genus = String.downcase(tags["genus"] || tags["species"] || "")

    fun =
      cond do
        genus =~ "cocos" -> &World.Plants.coconut/0
        genus =~ "musa" -> &World.Plants.banana/0
        genus =~ "bambus" -> &World.Plants.bamboo/0
        true -> &World.Plants.frangipani/0
      end

    level = %{near: :mid, mid: :far, far: :far}[Detail.level()]
    Detail.with(level, fun)
  end
end
