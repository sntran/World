defmodule World.Village.House do
  @moduledoc """
  A house of a village of old Việt Nam, from a request of a few words
  (`docs/plans/0019-world-serves-the-projects.md`, 7.1): a frame of
  round posts of wood, some bays in a row (gian), a porch along the
  front (hiên), and a large roof with four slopes that curve, with its
  corners lifted (đao). On the ground on a low base, or on stilts (nhà
  sàn) with a stair. The roof is thatch or tiles; the walls are planks,
  woven bamboo or earth.

  `drawing/1` gives a model in parts, each a sculpture of edits: the
  frame (`_khung`), the two long slopes of the roof with its ridge
  (`_mai`), its two end slopes (`_dau_hoi`) and the ground (`_nen`). The
  middle of the house is at x = 0 and y = 0, the front is to +y, and z
  is up from the ground.
  """

  alias World.Town.Wall

  @walls %{
    "wood" => {"#7a5234", %{"roughness" => 0.8, "surface" => %{"kind" => "wood", "scale" => 0.02}}},
    "bamboo" => {"#b89a58", %{"roughness" => 0.85, "surface" => %{"kind" => "weave", "scale" => 0.05}}},
    "earth" => {"#c9a97a", %{"roughness" => 0.95, "surface" => %{"kind" => "plaster", "scale" => 0.05}}}
  }
  @roofs %{
    "thatch" => {"#a8935c", 0.3, %{"roughness" => 0.95, "surface" => %{"kind" => "hair", "scale" => 0.03}}},
    "tiles" => {"#9b4a32", 0.14, %{"roughness" => 0.8}}
  }
  @post "#5b3a24"
  @wood %{"roughness" => 0.8, "surface" => %{"kind" => "wood", "scale" => 0.015}}
  # The height of the posts over the floor, and the base of a house on the ground (m).
  @high 2.3
  @base 0.35

  @doc "The kinds of walls."
  def walls, do: Map.keys(@walls)

  @doc "The kinds of roofs."
  def roofs, do: Map.keys(@roofs)

  @doc """
  The request with each choice made. A key that has a value keeps it; a
  value that is not possible raises an `ArgumentError`.

    * `name` (small letters, digits and `_`) and `sources` (lines of
      text).
    * `bays`: the bays in a row, 1 to 7 (3). `bay`: the width of a bay,
      1.8 to 3.6 m (2.6). `deep`: from the back wall to the front wall,
      3 to 7 m (4.2).
    * `porch`: the depth of the porch along the front, 0 to 2.4 m (1.2;
      0: no porch).
    * `stilts`: the height of the floor over the ground, 0 to 3 m (0:
      the house is on a low base of earth; 1.8: a house on stilts with a
      stair).
    * `wall`: `wood` (planks), `bamboo` (woven) or `earth`.
    * `roof`: `thatch` or `tiles`. `curve`: how much the slopes sag and
      the corners lift, 0 to 1 (0.5). `eaves`: how far the roof goes out
      over the posts, 0.4 to 1.5 m (0.9).
    * `age`: 0 to 1 (0.5): the dirt and the wear.
  """
  def request(opts \\ %{}) do
    need(is_map(opts), "the request of a house of a village is a map")
    known = ~w(name sources bays bay deep porch stilts wall roof curve eaves age)

    case Map.keys(opts) -- known do
      [] ->
        :ok

      [key | _] ->
        raise(ArgumentError, "a house of a village has no key #{inspect(key)}: its keys are #{Enum.join(known, ", ")}")
    end

    name = Map.get(opts, "name", "nha_xua")
    need(is_binary(name) and name =~ ~r/^[a-z][a-z0-9_]*$/, "the name of a house has small letters, digits and _")
    sources = Map.get(opts, "sources", [])
    need(is_list(sources) and Enum.all?(sources, &is_binary/1), "the sources of a house are lines of text")
    bays = Map.get(opts, "bays", 3)
    need(is_integer(bays) and bays in 1..7, "a house of a village has from 1 to 7 bays")
    wall = Map.get(opts, "wall", "wood")
    need(is_map_key(@walls, wall), "the wall of a house of a village is one of #{Enum.join(walls(), ", ")}")
    roof = Map.get(opts, "roof", "thatch")
    need(is_map_key(@roofs, roof), "the roof of a house of a village is one of #{Enum.join(roofs(), ", ")}")

    %{
      "name" => name,
      "sources" => sources,
      "bays" => bays,
      "bay" => number(opts, "bay", 2.6, 1.8, 3.6),
      "deep" => number(opts, "deep", 4.2, 3, 7),
      "porch" => number(opts, "porch", 1.2, 0, 2.4),
      "stilts" => number(opts, "stilts", 0.0, 0, 3),
      "wall" => wall,
      "roof" => roof,
      "curve" => number(opts, "curve", 0.5, 0, 1),
      "eaves" => number(opts, "eaves", 0.9, 0.4, 1.5),
      "age" => number(opts, "age", 0.5, 0, 1)
    }
  end

  defp number(map, key, default, lo, hi) do
    v = Map.get(map, key, default)
    need(is_number(v) and v >= lo and v <= hi, "the value of #{key} is a number from #{lo} to #{hi}")
    v * 1.0
  end

  defp need(true, _text), do: :ok
  defp need(false, text), do: raise(ArgumentError, text)

  @doc """
  The sizes of a request (m): `long` and `deep` (the frame of posts,
  with the porch), `floor` (the floor over the ground), `eaves` (the top
  of the posts), `ridge` (the top of the roof), and `roof` (`[long,
  deep]` of the roof at its eaves).
  """
  def sizes(request) do
    r = request(request)
    {long, deep} = {r["bays"] * r["bay"], r["deep"] + r["porch"]}
    floor = if r["stilts"] > 0, do: r["stilts"], else: @base
    {wide, far} = {deep + 2 * r["eaves"], long + 2 * r["eaves"]}
    # A roof of thatch is steep (the rain runs off); a roof of tiles is lower.
    rise = if(r["roof"] == "thatch", do: 0.52, else: 0.4) * wide

    %{
      "long" => r4(long),
      "deep" => r4(deep),
      "floor" => r4(floor),
      "eaves" => r4(floor + @high),
      "ridge" => r4(floor + @high + rise),
      "roof" => [r4(far), r4(wide)]
    }
  end

  @doc "The drawing of the house of a request (`request/1`): a model in parts, each a sculpture with its cells and its image."
  def drawing(request \\ %{}) do
    r = request(request)
    s = sizes(r)
    look = %{"dirt" => r4(0.2 + 0.4 * r["age"]), "wear" => r4(0.3 * r["age"])}
    levels = fn list -> Map.new(Enum.zip(~w(near mid far), list)) end

    {long, ends} = roof(r, s)

    parts = [
      {"khung", frame(r, s), [0.04, 0.07, 0.15], [30_000, 6_000, 800], [1024, 512, 128]},
      {"mai", long, [0.05, 0.08, 0.15], [7_000, 2_000, 300], [1024, 512, 128]},
      {"dau_hoi", ends, [0.05, 0.08, 0.15], [3_000, 900, 150], [512, 256, 128]},
      {"nen", ground(s), [0.08, 0.15, 0.3], [600, 300, 100], [256, 128, 64]}
    ]

    nodes =
      for {{part, edits, cells, budget, bake}, i} <- Enum.with_index(parts, 1) do
        data =
          Map.merge(look, %{
            "edits" => Enum.map(edits, &Map.put(&1, "material", "part_0#{i}")),
            "cells" => levels.(cells),
            "budget" => levels.(budget),
            "bake" => levels.(Enum.zip_with(budget, bake, &image/2))
          })

        %{"name" => "#{r["name"]}_#{part}", "skill" => %{"sculpt" => data}}
      end

    %{
      "name" => r["name"],
      "kind" => "house",
      "sources" => r["sources"],
      "materials" => Map.new(1..4, &{"part_0#{&1}", %{"color" => "#ffffff", "roughness" => 0.85, "metalness" => 0.0}}),
      "extras" => %{"village_house" => r, "sizes" => s},
      "nodes" => nodes
    }
  end

  # The side of the image of a part: the least side for its budget, and not smaller than `side`.
  defp image(budget, side),
    do: Enum.find([64, 128, 256, 512, 1024, 2048, 4096], &(&1 >= max(side, World.Sculpt.Bake.least(budget))))

  # --- The frame --------------------------------------------------------------------

  # The posts, the beams, the floor, the walls with their doors and windows, and the base or the stair.
  defp frame(r, s) do
    {long, deep, floor, eaves} = {s["long"], s["deep"], s["floor"], s["eaves"]}
    {wall_color, wall_look} = @walls[r["wall"]]
    # (The rows of posts from the back to the front: the back wall, the front wall, and the edge of the porch.)
    back = -deep / 2
    front = deep / 2 - r["porch"]
    rows = Enum.uniq([back, front, deep / 2])
    xs = for i <- 0..r["bays"], do: -long / 2 + r["bay"] * i

    posts =
      for x <- xs, y <- rows do
        Wall.edit("cylinder", [0.11, r4(eaves / 2)], [r4(x), r4(y), r4(eaves / 2)], @post, @wood)
      end

    beams =
      for(y <- rows, do: box([long + 0.3, 0.16, 0.2], [0, y, eaves - 0.1], @post, @wood)) ++
        for(x <- xs, do: box([0.16, deep + 0.3, 0.2], [x, 0, eaves - 0.28], @post, @wood))

    planks = box([long + 0.3, deep + 0.3, 0.12], [0, 0, floor - 0.06], shade(@post, 1.25), @wood)

    under =
      if r["stilts"] > 0,
        do: stair(r, s),
        else:
          [
            box([long + 0.9, deep + 0.9, floor - 0.12], [0, 0, (floor - 0.12) / 2], "#b8a078", %{
              "roughness" => 0.95,
              "surface" => %{"kind" => "stone", "scale" => 0.2}
            })
          ] ++ steps(s)

    # The back wall and the two end walls, between the floor and the beams.
    high = eaves - 0.2 - floor
    mid_z = floor + high / 2

    walls = [
      box([long, 0.08, high], [0, back, mid_z], wall_color, wall_look),
      box([long, 0.08, high], [0, front, mid_z], wall_color, wall_look),
      box([0.08, front - back, high], [-long / 2, (front + back) / 2, mid_z], wall_color, wall_look),
      box([0.08, front - back, high], [long / 2, (front + back) / 2, mid_z], wall_color, wall_look)
    ]

    # The front wall: a door in the middle bay (in each of the two middle bays of an even count), and a
    # window with upright bars in each other bay.
    doors = if rem(r["bays"], 2) == 1, do: [div(r["bays"], 2)], else: [div(r["bays"], 2) - 1, div(r["bays"], 2)]

    openings =
      for i <- 0..(r["bays"] - 1), x = -long / 2 + r["bay"] * (i + 0.5) do
        if i in doors do
          [box([1.1, 0.5, 1.9], [x, front, floor + 0.95], "#2a1c12", %{"mode" => "subtract", "roughness" => 0.9})]
        else
          [
            box([1.2, 0.3, 0.9], [x, front, floor + 1.35], "#2a1c12", %{"mode" => "subtract", "roughness" => 0.9})
            | for(
                k <- -2..2,
                do: Wall.edit("cylinder", [0.02, 0.45], [r4(x + 0.2 * k), r4(front), r4(floor + 1.35)], @post, @wood)
              )
          ]
        end
      end

    posts ++ beams ++ [planks] ++ under ++ walls ++ List.flatten(openings)
  end

  # The stair of a house on stilts, in front of the middle of the porch: a solid of steps.
  defp stair(r, s) do
    count = max(2, round(s["floor"] / 0.22))
    {rise, run} = {s["floor"] / count, 0.26}
    y0 = s["deep"] / 2 + 0.15

    outline =
      [[0, 0]] ++
        Enum.flat_map(0..(count - 1), fn k ->
          [[run * k, s["floor"] - rise * k], [run * (k + 1), s["floor"] - rise * k]]
        end) ++
        [[run * count, 0]]

    x = if rem(r["bays"], 2) == 1, do: 0.0, else: -r["bay"] / 2

    [
      Wall.outline(
        outline,
        1.0,
        [x, y0, 0],
        shade(@post, 1.1),
        Map.merge(@wood, %{"axis" => [1, 0, 0], "up" => [0, 0, 1]})
      )
    ]
  end

  # Two steps of stone in front of the base of a house on the ground.
  defp steps(s) do
    stone = %{"roughness" => 0.95, "surface" => %{"kind" => "stone", "scale" => 0.2}}

    for k <- [1, 2] do
      box(
        [1.8, 0.3, s["floor"] - 0.12 * k],
        [0, s["deep"] / 2 + 0.3 + 0.3 * k, (s["floor"] - 0.12 * k) / 2],
        "#a8946e",
        stone
      )
    end
  end

  # --- The roof ---------------------------------------------------------------------

  # A roof with four slopes that curve, as two parts: the two long slopes (a shell along the ridge, cut at
  # each end to the line of a hip) with the ridge and the four hips, and the two end slopes (a shell across
  # the house, cut to the section of the long slopes). `{long slopes, end slopes}`.
  defp roof(r, s) do
    [far, wide] = s["roof"]
    {z0, high} = {s["eaves"], s["ridge"] - s["eaves"]}
    {color, thick, look} = @roofs[r["roof"]]
    # (The height of a slope at the part `u` of the way from its eaves to the ridge: the power makes it sag.)
    power = 1 + 0.9 * r["curve"]
    rise = fn u -> high * :math.pow(u, power) end
    us = for k <- 0..12, do: k / 12
    # (The ridge is at least 0.6 m long: the ends of a short house have steeper slopes.)
    hip = min(wide / 2, (far - 0.6) / 2)
    along = %{"axis" => [1, 0, 0], "up" => [0, 0, 1]}
    across = %{"axis" => [0, 1, 0], "up" => [0, 0, 1]}

    # The line of the long slopes, seen from an end, and the line of the end slopes, seen from the front.
    side = both(for u <- us, do: [-wide / 2 * (1 - u), rise.(u)])
    front = both(for u <- us, do: [-(far / 2 - hip * u), rise.(u)])

    # The rows of a roof of tiles: thin dark lines.
    rows =
      if r["roof"] == "tiles" do
        for k <- 1..10 do
          Wall.edit("box", [r4(far), r4(far), 0.012], [0, 0, r4(z0 + high * k / 11)], shade(color, 0.8), %{
            "mode" => "paint",
            "raise" => -0.008,
            "blend" => 0.012
          })
        end
      else
        []
      end

    # The ridge, with its two ends a little higher, and the hips: each from an end of the ridge down to a
    # corner of the roof, with its end lifted and longer (the đao of a roof of tiles).
    lift = if(r["roof"] == "tiles", do: 0.5, else: 0.12) * r["curve"]
    dark = shade(color, 0.7)
    ridge_x = far / 2 - hip

    ridge =
      Wall.tube(
        for(k <- -2..2, do: [r4(ridge_x * k / 2), 0, r4(z0 + high + 0.05 + lift * 0.5 * abs(k) / 2)]),
        [0.1, 0.12, 0.12, 0.12, 0.1],
        dark,
        %{"roughness" => 0.85}
      )

    hips =
      for sx <- [-1, 1], sy <- [-1, 1] do
        line =
          for u <- [1.0, 0.75, 0.5, 0.25, 0.0, -0.12] do
            z = if u >= 0, do: rise.(u) + 0.04 + lift * (1 - u) * (1 - u), else: 0.04 + lift * 1.35
            [r4(sx * (far / 2 - hip * u)), r4(sy * wide / 2 * (1 - u)), r4(z0 + z)]
          end

        Wall.tube(line, [0.1, 0.1, 0.1, 0.09, 0.08, 0.05], dark, %{"roughness" => 0.85})
      end

    long = [
      Wall.outline(shell(side, thick), far, [0, 0, z0], color, Map.merge(look, along)),
      Wall.outline(solid(front), wide + 2.0, [0, 0, z0], color, Map.merge(look, Map.put(across, "mode", "crop")))
    ]

    ends = [
      Wall.outline(shell(front, thick), wide, [0, 0, z0], color, Map.merge(look, across)),
      Wall.outline(solid(side), far + 2.0, [0, 0, z0], color, Map.merge(look, Map.put(along, "mode", "crop")))
    ]

    {long ++ rows ++ [ridge | hips], ends ++ rows}
  end

  # A line from the left eaves up to the ridge, with its mirror down to the right eaves.
  defp both(left), do: left ++ (left |> Enum.reverse() |> tl() |> Enum.map(fn [a, z] -> [-a, z] end))

  # The outline of a shell under a line: the line, then the same line lower by the thickness, back to the start.
  defp shell(line, thick) do
    [[a0, _] | _] = line
    line ++ (line |> Enum.reverse() |> Enum.map(fn [a, z] -> [a * (1 + thick / a0), z - thick] end))
  end

  # The outline of the solid under a line, to 1 m under its eaves.
  defp solid(line) do
    {[a0, _], [a1, _]} = {hd(line), List.last(line)}
    [[a0, -1.0], [a1, -1.0]] ++ Enum.reverse(line)
  end

  # --- The ground -------------------------------------------------------------------

  defp ground(s) do
    [far, wide] = s["roof"]

    [
      box([far + 1.5, wide + 2.5, 0.2], [0, 0.5, -0.1], "#b59a6e", %{
        "roughness" => 0.98,
        "surface" => %{"kind" => "stone", "scale" => 0.4}
      })
    ]
  end

  # A box from its three sides (not their halves), with its middle at a point.
  defp box([x, y, z], at, color, more),
    do: Wall.edit("box", [r4(x / 2), r4(y / 2), r4(z / 2)], Enum.map(at, &r4/1), color, more)

  defp r4(v), do: Wall.r4(v)

  # A color, darker or lighter by a part.
  defp shade("#" <> hex, part) do
    <<r::8, g::8, b::8>> = Base.decode16!(hex, case: :mixed)

    "#" <>
      Base.encode16(<<min(255, round(r * part)), min(255, round(g * part)), min(255, round(b * part))>>, case: :lower)
  end
end
