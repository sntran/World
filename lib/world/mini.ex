defmodule World.Mini do
  @moduledoc """
  A very small model for a view from far, from a kind
  (`docs/plans/0019-world-serves-the-projects.md`, step 10; for Humans
  Must Die): a building, an aircraft, a ship, a vehicle, a wind turbine
  or a tree as a few thick solid shapes, with flat faces and a color at
  each point, in some hundreds of triangles. A thing that is a few
  pixels on the screen needs a clear outline, not details: each part is
  thicker than in real life.

  `drawing/1` gives a model of one part from edits with the look `flat`
  (`World.Skills.Sculpt`). The sizes are those of the real thing (m).
  The middle of the thing is at x = 0 and y = 0, it stands on z = 0 (a
  ship floats: z = 0 is the water), and its front is to +y.
  """

  alias World.Town.Wall

  # Each kind: the longest size of the real thing (m), for the cells of its sculpture.
  @kinds %{
    "house" => 12,
    "block" => 45,
    "tower" => 170,
    "office" => 45,
    "factory" => 70,
    "data_center" => 70,
    "barn" => 18,
    "stilt_house" => 10,
    "lighthouse" => 36,
    "jet" => 17,
    "airliner" => 42,
    "helicopter" => 14,
    "carrier" => 335,
    "destroyer" => 160,
    "container_ship" => 300,
    "tanker" => 250,
    "patrol_boat" => 48,
    "police_car" => 5,
    "ambulance" => 6,
    "fire_truck" => 9,
    "tank" => 10,
    "missile_battery" => 12,
    "turbine" => 140,
    "tree_broad" => 13,
    "tree_pine" => 16,
    "tree_palm" => 11
  }

  @doc "The kinds of a small model."
  def kinds, do: @kinds |> Map.keys() |> Enum.sort()

  @doc """
  The request with each choice made: `kind` (one of `kinds/0`), `name`
  (small letters, digits and `_`), `sources`, `scale` (0.1 to 10: each
  size of the real thing times it), and `color` (the main color of the
  thing; each kind has its own). A value that is not possible raises an
  `ArgumentError`.
  """
  def request(opts \\ %{}) do
    need(is_map(opts), "the request of a small model is a map")

    case Map.keys(opts) -- ~w(kind name sources scale color) do
      [] ->
        :ok

      [key | _] ->
        raise(ArgumentError, "a small model has no key #{inspect(key)}: its keys are kind, name, sources, scale, color")
    end

    kind = Map.get(opts, "kind", "house")
    need(is_map_key(@kinds, kind), "the kind of a small model is one of #{Enum.join(kinds(), ", ")}")
    name = Map.get(opts, "name", kind)
    need(is_binary(name) and name =~ ~r/^[a-z][a-z0-9_]*$/, "the name of a small model has small letters, digits and _")
    sources = Map.get(opts, "sources", [])
    need(is_list(sources) and Enum.all?(sources, &is_binary/1), "the sources of a small model are lines of text")
    scale = Map.get(opts, "scale", 1.0)
    need(is_number(scale) and scale >= 0.1 and scale <= 10, "the scale of a small model is a number from 0.1 to 10")
    color = Map.get(opts, "color")

    need(
      is_nil(color) or (is_binary(color) and color =~ ~r/^#[0-9a-f]{6}$/),
      "the color of a small model is as #a1b2c3 (small letters)"
    )

    %{"kind" => kind, "name" => name, "sources" => sources, "scale" => scale * 1.0, "color" => color}
  end

  defp need(true, _text), do: :ok
  defp need(false, text), do: raise(ArgumentError, text)

  @doc """
  The drawing of the small model of a request (`request/1`): one part
  from edits with the look `flat`, with large cells (the longest size
  of the thing is 56 cells at the near level, 40 at mid and 28 at far).
  """
  def drawing(request \\ %{}) do
    r = request(request)
    long = @kinds[r["kind"]] * r["scale"]
    levels = fn list -> Map.new(Enum.zip(~w(near mid far), list)) end

    data = %{
      "look" => "flat",
      "edits" => for(e <- kind(r["kind"], r["color"]), do: e |> scaled(r["scale"]) |> Map.put("material", "paint")),
      "cells" => levels.(for(n <- [56, 40, 28], do: r4(min(long / n, 10.0)))),
      "budget" => levels.([900, 450, 220])
    }

    %{
      "name" => r["name"],
      "kind" => "item",
      "sources" => r["sources"],
      "materials" => %{"paint" => %{"color" => "#ffffff", "roughness" => 0.8, "metalness" => 0.0}},
      "extras" => %{"mini" => r},
      "nodes" => [%{"name" => "#{r["name"]}_than", "skill" => %{"sculpt" => data}}]
    }
  end

  # An edit at a scale: its sizes and its place times the scale.
  defp scaled(e, k) when k == 1.0, do: e

  defp scaled(%{"size" => size, "at" => at} = e, k) do
    size =
      case size do
        %{"outline" => points, "depth" => depth} ->
          %{"outline" => for([a, b] <- points, do: [r4(a * k), r4(b * k)]), "depth" => r4(depth * k)}

        list ->
          Enum.map(list, &r4(&1 * k))
      end

    %{e | "size" => size, "at" => Enum.map(at, &r4(&1 * k))}
  end

  # (A tube has no place of its own: its points are its place.)
  defp scaled(%{"size" => %{"points" => points, "radii" => radii}} = e, k) do
    %{
      e
      | "size" => %{"points" => for(p <- points, do: Enum.map(p, &r4(&1 * k))), "radii" => Enum.map(radii, &r4(&1 * k))}
    }
  end

  # --- The words of a small model -------------------------------------------------------

  defp e(shape, size, at, color, more \\ %{}),
    do: Wall.edit(shape, Enum.map(size, &r4/1), Enum.map(at, &r4/1), color, more)

  defp box(half, at, color), do: e("box", half, at, color)
  defp ball(r, at, color), do: e("ball", [r], at, color)
  defp egg(half, at, color, more \\ %{}), do: e("ellipsoid", half, at, color, more)
  # (A cylinder and a cone along z, or along the axis of `more`.)
  defp rod(r, half, at, color, more \\ %{}), do: e("cylinder", [r, half], at, color, more)
  defp cone(r1, r2, half, at, color, more \\ %{}), do: e("cone", [r1, r2, half], at, color, more)
  @along_x %{"axis" => [1, 0, 0], "up" => [0, 0, 1]}
  @along_y %{"axis" => [0, 1, 0], "up" => [0, 0, 1]}

  # A plan: an outline in x and y, `depth` high, with its middle at the height `z`.
  defp plan(points, depth, z, color), do: Wall.outline(points, depth, [0, 0, z], color)
  # A side view: an outline in y and z, `depth` wide along x, with its middle at `x`.
  defp side(points, depth, x, color), do: Wall.outline(points, depth, [x, 0, 0], color, @along_x)
  # A roof with two slopes: its ridge along y, `long`, from `z0` at its eaves (half of `wide` from the ridge) to `z1`.
  defp gable(wide, long, z0, z1, color, y \\ 0),
    do: Wall.outline([[-wide / 2, z0], [wide / 2, z0], [0, z1]], long, [0, y, 0], color, @along_y)

  # Four wheels of a vehicle: the half of its track, the places of its two axles along y, and the radius.
  defp wheels(half, [front, back], r) do
    for x <- [-half, half], y <- [front, back], do: rod(r, r * 0.45, [x, y, r], "#1e2022", @along_x)
  end

  # The hull of a ship: its plan with a point at the bow (+y), from the water up to `deck`, and a part under the water.
  defp hull(long, wide, deck, color, bottom \\ "#7a2a22") do
    {l, w} = {long / 2, wide / 2}
    outline = [[-w, -l], [w, -l], [w, l * 0.55], [0, l], [-w, l * 0.55]]
    [plan(outline, deck, deck / 2, color), plan(outline, deck * 0.25, -deck * 0.12, bottom)]
  end

  # --- The kinds ------------------------------------------------------------------------

  defp kind("house", color) do
    [
      box([4, 5, 1.8], [0, 0, 1.8], color || "#e6dcc0"),
      gable(9.6, 11, 3.5, 6.6, "#9b4a32"),
      box([0.5, 0.5, 1.0], [2.2, -2.5, 6.0], "#8a8478")
    ]
  end

  defp kind("block", color) do
    c = color || "#d8d2c4"

    [
      box([20, 6, 15], [0, 0, 15], c),
      box([20.4, 6.4, 1.5], [0, 0, 1.5], shade(c, 0.7)),
      box([18.5, 5, 0.8], [0, 0, 30.6], "#8d8a80")
    ] ++
      for(k <- 1..4, do: box([20.3, 6.3, 0.5], [0, 0, 6.0 * k + 2.0], shade(c, 0.82)))
  end

  defp kind("tower", color) do
    c = color || "#7f9bb0"

    [
      box([15, 15, 40], [0, 0, 40], c),
      box([12, 12, 30], [0, 0, 110], shade(c, 1.08)),
      box([8, 8, 12], [0, 0, 152], shade(c, 0.9)),
      cone(2.5, 0.6, 10, [0, 0, 174], "#c9ccd0")
    ]
  end

  defp kind("office", color) do
    c = color || "#5f8fa8"

    [
      box([15, 10, 20], [0, 0, 20], c),
      box([15.6, 10.6, 1.2], [0, 0, 1.2], "#c9ccd0"),
      box([15.6, 10.6, 0.9], [0, 0, 40.2], "#c9ccd0")
    ] ++ for(k <- 1..3, do: box([15.4, 10.4, 0.6], [0, 0, 10.0 * k], "#dfe3e6"))
  end

  defp kind("factory", color) do
    c = color || "#b9b4a4"
    # (A roof of four slopes in a row, and a chimney.)
    roof = for i <- 0..3, do: e("wedge", [30, 3.75, 2], [0, -11.25 + 7.5 * i, 12], "#6f7a82")

    [
      box([30, 15, 5], [0, 0, 5], c),
      rod(2.2, 14, [22, -9, 14], "#a8574a"),
      box([8, 6, 3], [-18, 18, 3], shade(c, 0.9)) | roof
    ]
  end

  defp kind("data_center", color) do
    c = color || "#c9ccd0"
    units = for i <- -2..2, j <- [-1, 1], do: box([4, 4, 1.6], [12.0 * i, 9.0 * j, 11.6], "#6f7a82")
    [box([32, 20, 5], [0, 0, 5], c), box([32.5, 20.5, 0.8], [0, 0, 3], "#2f5f9e") | units]
  end

  defp kind("barn", color) do
    [
      box([6, 8, 3], [0, 0, 3], color || "#9c3b2e"),
      gable(13.6, 17, 6, 9.5, "#4a4038"),
      box([2, 0.3, 2.2], [0, 8, 2.2], "#e6dcc0")
    ]
  end

  defp kind("stilt_house", color) do
    posts = for x <- [-2.6, 2.6], y <- [-1.8, 1.8], do: rod(0.35, 1.2, [x, y, 1.2], "#5b3a24")
    posts ++ [box([3.2, 2.4, 1.3], [0, 0, 3.7], color || "#b89a58"), gable(8.4, 7.2, 4.8, 7.6, "#a8935c")]
  end

  defp kind("lighthouse", color) do
    c = color || "#eceeed"

    [
      cone(4.0, 2.6, 13, [0, 0, 13], c),
      rod(3.6, 2.2, [0, 0, 10], "#b3261e"),
      rod(3.0, 2.0, [0, 0, 20], "#b3261e"),
      rod(3.6, 0.5, [0, 0, 26.5], "#3a3d40"),
      rod(2.0, 1.8, [0, 0, 28.8], "#f2d24a"),
      cone(2.6, 0.3, 1.6, [0, 0, 32.2], "#b3261e")
    ]
  end

  defp kind("jet", color) do
    c = color || "#8d979b"

    [
      egg([1.1, 8, 1.1], [0, 0, 1.9], c),
      # (The wings and the tail planes as one plan each; the fin as a side view.)
      plan([[-5.6, -4.5], [5.6, -4.5], [0, 2.5]], 0.7, 1.8, c),
      plan([[-2.8, -8.2], [2.8, -8.2], [0, -5.2]], 0.6, 1.9, c),
      side([[-8.0, 1.8], [-5.0, 1.8], [-7.8, 4.6]], 0.6, 0, shade(c, 0.9)),
      egg([0.6, 1.6, 0.6], [0, 3.2, 2.5], "#27323a")
    ]
  end

  defp kind("airliner", color) do
    c = color || "#eceeed"

    [
      egg([2.1, 20, 2.1], [0, 0, 4.2], c),
      plan([[-18, -6], [-17, -8], [0, -1], [17, -8], [18, -6], [0, 6]], 1.0, 3.6, shade(c, 0.92)),
      plan([[-7, -19.5], [7, -19.5], [0, -14.5]], 0.9, 4.6, shade(c, 0.92)),
      side([[-19.5, 4.5], [-13.5, 4.5], [-19.0, 11.5]], 0.9, 0, "#2f5f9e"),
      rod(1.2, 2.4, [-6.5, 0.5, 2.2], "#8d979b", @along_y),
      rod(1.2, 2.4, [6.5, 0.5, 2.2], "#8d979b", @along_y)
    ]
  end

  defp kind("helicopter", color) do
    c = color || "#c94a2e"

    [
      egg([1.4, 3.2, 1.5], [0, 1, 2.4], c),
      box([0.4, 3.4, 0.4], [0, -4.6, 2.9], c),
      side([[-8.4, 2.6], [-7.2, 2.6], [-8.4, 4.6]], 0.5, 0, shade(c, 0.85)),
      egg([0.9, 1.1, 0.8], [0, 3.2, 2.5], "#27323a"),
      rod(0.3, 0.5, [0, 1, 4.2], "#3a3d40"),
      # (The rotor: two blades that cross.)
      box([6.5, 0.45, 0.2], [0, 1, 4.8], "#3a3d40"),
      box([0.45, 6.5, 0.2], [0, 1, 4.8], "#3a3d40"),
      box([0.25, 2.6, 0.2], [-1.3, 1, 0.2], "#3a3d40"),
      box([0.25, 2.6, 0.2], [1.3, 1, 0.2], "#3a3d40")
    ]
  end

  defp kind("carrier", color) do
    c = color || "#7f878c"

    hull(320, 40, 20, c) ++
      [
        # The flight deck is wider than the hull; the island is at the right side.
        plan([[-36, -160], [30, -160], [38, -40], [38, 90], [20, 165], [-20, 165], [-36, 60]], 4.5, 22, shade(c, 0.78)),
        box([7, 22, 12], [28, -20, 36], c),
        box([4, 8, 6], [28, -22, 54], shade(c, 0.9)),
        rod(1.6, 9, [28, -14, 66], "#3a3d40"),
        box([1.2, 150, 0.4], [-8, 0, 24.5], "#eceeed")
      ]
  end

  defp kind("destroyer", color) do
    c = color || "#8d979b"

    hull(155, 19, 9, c) ++
      [
        box([7, 26, 6], [0, -4, 15], c),
        box([5, 10, 5], [0, 4, 26], shade(c, 0.9)),
        rod(1.2, 9, [0, 2, 39], "#3a3d40"),
        rod(3.0, 4.5, [0, -22, 22], shade(c, 0.8)),
        box([3.5, 5, 2.5], [0, 48, 11.5], shade(c, 0.85)),
        rod(0.9, 6, [0, 57, 12.5], "#3a3d40", @along_y)
      ]
  end

  defp kind("container_ship", color) do
    c = color || "#2a4a6a"
    colors = ["#b3261e", "#2f5f9e", "#d9a03a", "#3f7a52", "#c9ccd0", "#b3261e"]
    stacks = for {box_color, i} <- Enum.with_index(colors), do: box([18, 16, 9], [0, -70 + 36 * i, 27], box_color)

    hull(300, 44, 18, c) ++
      stacks ++ [box([18, 9, 16], [0, -128, 34], "#eceeed"), rod(3.0, 5, [0, -134, 55], "#3a3d40")]
  end

  defp kind("tanker", color) do
    c = color || "#1e2022"

    hull(250, 44, 16, c) ++
      [
        box([20.5, 100, 1.2], [0, 12, 17], "#8a3a2c"),
        box([16, 10, 13], [0, -108, 29], "#eceeed"),
        rod(3.2, 5, [0, -112, 47], "#d9a03a"),
        rod(1.4, 95, [0, 10, 20], "#c9ccd0", @along_y),
        box([6, 4, 3], [0, 20, 21], "#c9ccd0")
      ]
  end

  defp kind("patrol_boat", color) do
    c = color || "#eceeed"

    hull(46, 8.5, 4.5, c, "#2a4a6a") ++
      [
        box([4.4, 23.2, 0.7], [0, 0, 3.2], "#d9541e"),
        box([2.8, 7, 2.6], [0, 0, 7.1], c),
        box([2.2, 3.6, 1.6], [0, 2, 11.3], shade(c, 0.9)),
        rod(0.5, 3.5, [0, -2, 15], "#3a3d40")
      ]
  end

  defp kind("police_car", color) do
    c = color || "#eceeed"

    wheels(0.85, [1.45, -1.4], 0.36) ++
      [
        box([0.95, 2.3, 0.4], [0, 0, 0.75], c),
        box([0.86, 1.15, 0.33], [0, -0.2, 1.42], "#27323a"),
        box([0.97, 0.75, 0.41], [0, -0.1, 0.75], "#1f3f8a"),
        box([0.55, 0.14, 0.09], [0, -0.2, 1.84], "#b3261e")
      ]
  end

  defp kind("ambulance", color) do
    c = color || "#eceeed"

    wheels(0.95, [1.9, -1.6], 0.42) ++
      [
        box([1.05, 0.95, 0.75], [0, 1.9, 1.25], c),
        box([1.08, 1.85, 1.05], [0, -0.95, 1.55], c),
        box([0.9, 0.5, 0.3], [0, 2.2, 1.65], "#27323a"),
        box([1.1, 1.85, 0.14], [0, -0.95, 1.2], "#b3261e"),
        box([0.5, 0.14, 0.1], [0, 1.6, 2.1], "#2f5f9e")
      ]
  end

  defp kind("fire_truck", color) do
    c = color || "#b3261e"

    wheels(1.15, [2.6, -2.4], 0.55) ++
      [
        box([1.25, 1.3, 1.0], [0, 3.0, 1.75], c),
        box([1.25, 2.9, 0.85], [0, -1.3, 1.6], c),
        box([1.05, 0.6, 0.38], [0, 3.6, 2.2], "#27323a"),
        # (The ladder on its top, a little up at the front.)
        box([0.4, 3.6, 0.16], [0, -0.6, 2.75], "#c9ccd0"),
        box([1.27, 2.9, 0.12], [0, -1.3, 1.2], "#eceeed"),
        box([0.6, 0.16, 0.1], [0, 2.6, 2.85], "#2f5f9e")
      ]
  end

  defp kind("tank", color) do
    c = color || "#5d6b3c"

    [
      box([0.45, 3.4, 0.5], [-1.4, 0, 0.5], "#2c2e30"),
      box([0.45, 3.4, 0.5], [1.4, 0, 0.5], "#2c2e30"),
      box([1.7, 3.3, 0.45], [0, 0, 1.25], c),
      egg([1.35, 1.7, 0.6], [0, -0.3, 2.1], shade(c, 0.9)),
      rod(0.14, 2.6, [0, 3.6, 2.15], shade(c, 0.75), @along_y)
    ]
  end

  defp kind("missile_battery", color) do
    c = color || "#5d6b3c"

    wheels(1.15, [3.6, -3.4], 0.6) ++
      [
        box([1.25, 5.2, 0.45], [0, 0, 1.45], c),
        box([1.2, 1.1, 0.8], [0, 4.1, 2.7], shade(c, 0.9)),
        # (The launcher at a slope, a dome of radar, and a mast.)
        e("box", [1.0, 2.6, 0.7], [0, -1.6, 3.4], shade(c, 1.1), %{"axis" => [0, -0.45, 0.89], "up" => [0, 0.89, 0.45]}),
        ball(0.75, [0, 1.6, 2.75], "#dfe3e6"),
        rod(0.12, 1.6, [0.9, 2.6, 3.5], "#3a3d40")
      ]
  end

  defp kind("turbine", color) do
    c = color || "#eceeed"
    # (Three blades round the hub, in the plane of x and z: the rotor looks to +y.)
    blades =
      for degrees <- [90, 210, 330] do
        a = degrees * :math.pi() / 180
        {dx, dz} = {:math.cos(a), :math.sin(a)}
        e("box", [2.0, 1.1, 22], [dx * 23, 5.5, 90 + dz * 23], c, %{"axis" => [r4(dx), 0, r4(dz)], "up" => [0, 1, 0]})
      end

    [
      cone(3.4, 2.2, 45, [0, 0, 45], c),
      box([2.6, 5.5, 2.6], [0, 1.5, 90], shade(c, 0.9)),
      ball(2.8, [0, 5.5, 90], shade(c, 0.85)) | blades
    ]
  end

  defp kind("tree_broad", color) do
    c = color || "#4f8a3c"

    [
      rod(0.55, 2.6, [0, 0, 2.6], "#6b4a2e"),
      egg([4.2, 4.0, 3.6], [0, 0, 8.0], c),
      egg([2.8, 2.8, 2.6], [1.6, 0.8, 10.4], shade(c, 1.12)),
      egg([2.6, 2.6, 2.2], [-2.0, -0.8, 6.6], shade(c, 0.88))
    ]
  end

  defp kind("tree_pine", color) do
    c = color || "#2f6b3f"

    [
      rod(0.5, 1.8, [0, 0, 1.8], "#5b3a24"),
      cone(3.6, 1.2, 2.8, [0, 0, 5.6], c),
      cone(2.8, 0.8, 2.6, [0, 0, 9.4], shade(c, 1.08)),
      cone(1.9, 0.1, 2.6, [0, 0, 13.2], shade(c, 1.16))
    ]
  end

  defp kind("tree_palm", color) do
    c = color || "#4a8a3a"
    # (Eight fronds round the top of the trunk, each a flat shape that goes out and down.)
    fronds =
      for i <- 0..7 do
        a = i * :math.pi() / 4
        {dx, dy} = {:math.cos(a), :math.sin(a)}

        egg([0.75, 0.3, 2.3], [dx * 1.9, dy * 1.9, 9.1], c, %{
          "axis" => [r4(dx * 0.92), r4(dy * 0.92), -0.39],
          "up" => [0, 0, 1]
        })
      end

    [
      Wall.tube([[0, 0, 0], [0.3, 0, 3.2], [0.4, 0, 6.4], [0, 0, 9.4]], [0.5, 0.42, 0.36, 0.32], "#8a6a48"),
      ball(0.8, [0, 0, 9.5], "#6b4a2e") | fronds
    ]
  end

  defp r4(v), do: Wall.r4(v)

  # A color, darker or lighter by a part.
  defp shade("#" <> hex, part) do
    <<r::8, g::8, b::8>> = Base.decode16!(hex, case: :mixed)

    "#" <>
      Base.encode16(<<min(255, round(r * part)), min(255, round(g * part)), min(255, round(b * part))>>, case: :lower)
  end
end
