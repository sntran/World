defmodule World.Town.House do
  @moduledoc """
  A house of a street of Vũng Tàu from a request, as a drawing of edits
  in parts (`docs/plans/0016-a-house-and-a-street.md`).

  A request is a map of a few words: the `type` of the house, its
  `family` (the years of its build, and so its doors, its rails and its
  colors), the `width` and the `depth` of what is built, the width of
  its `road`, and a `seed`. `request/1` gives the request with each
  choice made: the same request gives the same house. `drawing/1` gives
  the drawing: the rules cut the front into storeys, the storeys into
  piers and openings, and each rule gives edits (`World.Skills.Sculpt`).
  A choice is from the seed, the name of the rule and its place, never
  from the order of the work.

  The types:

  | Type | What it is |
  |---|---|
  | `cap4` | A house of one storey (nhà cấp 4) with a roof of corrugated steel behind a low front wall. |
  | `pho2_flat` | A town house of two storeys with a flat terrace, a parapet, the head of the stair and a water tank: the most common house. |
  | `pho2_tile` | Two storeys under a roof of red tiles (mái Thái). |
  | `pho3` | Three storeys with a flat terrace. |

  The families:

  | Family | Years | The ground floor | The rail | The look |
  |---|---|---|---|---|
  | `old` | 1985 to 2000 | A folding gate of iron | Bars of iron, or a low wall | Cream or yellow paint, wood shutters, blocks for the air, stains |
  | `steel` | 2000 to 2015 | A roll-up door, piers of granite | Tubes of stainless steel | Pastel paint, glass in aluminum, a sign |
  | `modern` | 2015 to now | Glass doors behind a white gate | Glass | White and gray, wood slats |

  The sizes are from the rules of building and from drawings with sizes
  (the plan, section 3): a floor 0.3 m over the sidewalk, a ground
  storey of 3.6 m, each upper storey 3.4 m, a parapet of 1 m, a ground
  opening 2.85 m high between two piers, and a balcony that goes out by
  the width of the road (TCVN 9411:2012, the standard of row houses:
  0.9 m for a road of 7 to 12 m, 1.2 m for 12 to 15 m, 1.4 m over that,
  none under 5 m).

  The axes: x across the front, the front wall at y = 0, the street to
  +y, z up from the sidewalk.
  """

  @types ~w(cap4 pho2_flat pho2_tile pho3)
  @families ~w(old steel modern)

  # The floor over the sidewalk, the ground storey, an upper storey, the parapet (m).
  @floor 0.3
  @ground 3.6
  @upper 3.4
  @parapet 1.0
  # The height of the ground opening, and the thickness of the front part.
  @opening 2.85
  @front 0.3

  @walls %{
    "old" => [{"#e6dab4", 4}, {"#ead38a", 3}, {"#e9e5d8", 2}, {"#c3d6c0", 1}, {"#e6c2bc", 1}],
    "steel" => [{"#ece8dc", 3}, {"#bcd4e2", 2}, {"#ead9a0", 2}, {"#c8dcc4", 1}, {"#e8c6c0", 1}],
    "modern" => [{"#f2f0ea", 5}, {"#d9d8d4", 2}]
  }
  @signs ["#1f4f9c", "#b3261e", "#e0b400", "#1d7a46", "#e2e2de"]

  @doc "The types of a house."
  def types, do: @types

  @doc "The families of a house."
  def families, do: @families

  @doc """
  The request with each choice made: a map with the keys `type`,
  `family`, `width`, `depth`, `road`, `seed`, `left` and `right` (each
  `shared` with a neighbor, or `free`), and the choices of the rules:
  `wall` (a color), `ground` (`folding_gate`, `roller_door` or
  `glass_gate`), `rail` (`bars`, `wall`, `tubes` or `glass`), `sign`
  (a color, or nil), `awning` (true or false), `vents` (true or false),
  `roof` (`terrace`, `tiles` or `steel`), `age` (0 to 1) and `flip`
  (true: the door of the balcony is at the other side). A key of the
  request that has a value keeps it.
  """
  def request(opts \\ %{}) do
    unless is_map(opts), do: raise(ArgumentError, "the request of a house is a map")
    seed = Map.get(opts, "seed", 1)
    type = Map.get(opts, "type", "pho2_flat")
    family = Map.get(opts, "family") || pick(seed, :family, [{"old", 4}, {"steel", 4}, {"modern", 2}])
    unless type in @types, do: raise(ArgumentError, "the type of a house is one of #{Enum.join(@types, ", ")}")

    unless family in @families,
      do: raise(ArgumentError, "the family of a house is one of #{Enum.join(@families, ", ")}")

    choices = %{
      "type" => type,
      "family" => family,
      "seed" => seed,
      "width" => 5.0,
      "depth" => 16.0,
      "road" => 13.0,
      "left" => "shared",
      "right" => "shared",
      "wall" => pick(seed, :wall, @walls[family]),
      "ground" => %{"old" => "folding_gate", "steel" => "roller_door", "modern" => "glass_gate"}[family],
      "rail" =>
        case family do
          "old" -> pick(seed, :rail, [{"bars", 3}, {"wall", 2}])
          "steel" -> "tubes"
          "modern" -> "glass"
        end,
      "sign" =>
        if(family != "modern" and unit(seed, :sign) < 0.5, do: pick(seed, :sign_color, for(c <- @signs, do: {c, 1}))),
      "awning" => family == "old" and unit(seed, :awning) < 0.5,
      "vents" => family == "old" and unit(seed, :vents) < 0.6,
      "roof" => %{"cap4" => "steel", "pho2_tile" => "tiles"}[type] || "terrace",
      "age" => %{"old" => 0.8, "steel" => 0.5, "modern" => 0.15}[family],
      "flip" => unit(seed, :flip) < 0.5
    }

    r = Map.merge(choices, Map.take(opts, Map.keys(choices)))
    number = fn key, lo, hi -> is_number(r[key]) and r[key] >= lo and r[key] <= hi end
    unless is_integer(seed), do: raise(ArgumentError, "the seed of a house is a whole number")
    unless number.("width", 3, 8), do: raise(ArgumentError, "the width of a house is from 3 m to 8 m")
    unless number.("depth", 6, 30), do: raise(ArgumentError, "the depth of a house is from 6 m to 30 m")
    unless number.("road", 1, 100), do: raise(ArgumentError, "the width of a road is from 1 m to 100 m")
    %{r | "width" => r["width"] * 1.0, "depth" => r["depth"] * 1.0, "road" => r["road"] * 1.0}
  end

  @doc "How far a balcony goes out over the sidewalk, by the width of the road (TCVN 9411:2012, table 2)."
  def reach(road) when road < 5, do: 0.0
  def reach(road) when road < 7, do: 0.5
  def reach(road) when road < 12, do: 0.9
  def reach(road) when road <= 15, do: 1.2
  def reach(_road), do: 1.4

  @doc "The storeys of a type."
  def storeys("cap4"), do: 1
  def storeys("pho3"), do: 3
  def storeys(_type), do: 2

  @doc "The height of the top of the roof slab of a request, over the sidewalk."
  def top(%{"type" => type}), do: @floor + @ground + (storeys(type) - 1) * @upper

  @doc """
  The drawing of the house of a request (`request/1`): a model in parts,
  each part a sculpture with its cells and its image. The option `at`
  moves the house along x (a house in a row), `name` names it, and
  `image` is the side of the image of its front at near (2048 by
  default; a house in a row has 1024).
  """
  def drawing(request, opts \\ []) do
    r = request(request)
    {x, name} = {Keyword.get(opts, :at, 0.0), Keyword.get(opts, :name, "nha_#{r["type"]}_#{r["family"]}_#{r["seed"]}")}
    look = %{"dirt" => r4(0.15 + 0.6 * r["age"]), "wear" => r4(0.3 * r["age"])}
    image = Keyword.get(opts, :image, 2048)

    parts = [
      {"mat_tien", front(r), details(r), [0.025, 0.05, 0.05], [14_000, 2_500, 300], [image, 512, 128]},
      {"than", body(r), [], [0.08, 0.12, 0.25], [2_000, 500, 100], [512, 256, 128]},
      # (The parapet and the legs of the tank are thin: the same cells at each level.)
      {"mai", roof(r), [], [0.04, 0.04, 0.04], [5_000, 1_000, 150], [1024, 256, 128]}
    ]

    nodes =
      for {{part, edits, details, cells, budget, bake}, i} <- Enum.with_index(parts, 1) do
        role = "part_0#{i}"
        levels = fn list -> Map.new(Enum.zip(~w(near mid far), list)) end

        data =
          Map.merge(look, %{
            "edits" => Enum.flat_map(edits, &place(&1, x, role)),
            "cells" => levels.(cells),
            "budget" => levels.(budget),
            "bake" => levels.(bake)
          })

        data =
          if details == [],
            do: data,
            else:
              Map.put(data, "details", [
                %{
                  "edits" => Enum.flat_map(details, &place(&1, x, role)),
                  "cells" => %{"near" => 0.012},
                  "budget" => %{"near" => 6_000},
                  "levels" => ["near"]
                }
              ])

        %{"name" => "#{name}_#{part}", "skill" => %{"sculpt" => data}}
      end

    %{
      "name" => name,
      "kind" => "house",
      "sources" => sources(r),
      "materials" => Map.new(1..3, &{"part_0#{&1}", %{"color" => "#ffffff", "roughness" => 0.85, "metalness" => 0.0}}),
      "extras" => %{"house" => r, "lot" => %{"width" => r["width"], "depth" => r["depth"]}},
      "nodes" => nodes
    }
  end

  defp sources(r) do
    [
      "A house of a street of Vũng Tàu from rules (plan 0016): the type #{r["type"]}, the family #{r["family"]}, #{r["width"]} m wide, the seed #{r["seed"]}. It is no real house: its form is the common form of its type.",
      "The sizes: TCVN 9411:2012, the standard of row houses (the reach of a balcony by the width of the road, its underside 3.5 m over the sidewalk, a ground storey of 3.6 m, a floor over the sidewalk), and sample drawings of town houses of 4 m and 5 m with sizes (the levels 0.45, 3.6 and 7.1 m; a ground opening of 3.4 m by 2.85 m).",
      "The look is from photos of the streets Trưng Nhị, Ba Cu, Bà Triệu and Trần Phú of Vũng Tàu (Wikimedia Commons, and adverts of houses): folding gates and awnings on the old houses, granite piers and stainless rails from 2000, white fronts with glass from 2015. The colors and the shares of the choices are a guess. A sign has no words."
    ]
  end

  # --- The front: storeys, piers and openings ----------------------------------

  defp front(r) do
    {w, top} = {r["width"], top(r)}
    hw = w / 2
    flat? = r["roof"] == "terrace"
    # (The front wall goes up to the top of the parapet of a terrace, and to a low wall in front of a roof of steel.)
    high = top + %{"terrace" => @parapet, "steel" => 0.6, "tiles" => 0.0}[r["roof"]]
    paint = %{"roughness" => 0.85, "surface" => %{"kind" => "plaster", "scale" => 0.03}}

    [
      e("box", [hw, @front / 2, high / 2], [0, -@front / 2, high / 2], r["wall"], paint)
      | ground(r, hw) ++
          Enum.flat_map(1..(storeys(r["type"]) - 1)//1, &storey(r, hw, &1)) ++
          if(flat?,
            do: [e("box", [hw + 0.03, @front / 2 + 0.04, 0.04], [0, -@front / 2, high], shade(r["wall"], 0.9), paint)],
            else: []
          ) ++
          things(r, hw, high) ++ stains(r, hw, high)
    ]
  end

  # The ground storey: the opening between two piers with its door, the
  # step, the piers with their stone, the sign and the awning.
  defp ground(r, hw) do
    pier = if hw >= 2.5, do: 0.8, else: 0.55
    {half, mid} = {hw - pier, @floor + @opening / 2}
    stone = %{"old" => {"#d6cdb4", 0.6}, "steel" => {"#6a3a34", 0.25}, "modern" => {"#8d8f92", 0.3}}[r["family"]]
    {color, rough} = stone

    [
      e("box", [half, @front, @opening / 2], [0, -@front / 2, mid], "#33302c", %{
        "mode" => "subtract",
        "roughness" => 0.9
      }),
      # The floor behind the opening, and two steps to the sidewalk.
      e("box", [hw, @front / 2, @floor / 2], [0, -@front / 2, @floor / 2], "#a8a49a", concrete()),
      e("box", [half + 0.1, 0.3, @floor / 2], [0, 0.3, @floor / 2], "#a8a49a", concrete()),
      e("box", [half + 0.1, 0.15, @floor / 4], [0, 0.75, @floor / 4], "#a8a49a", concrete()),
      # The stone or the tiles of the piers, as high as the opening.
      e("box", [pier / 2, 0.2, @opening / 2], [hw - pier / 2, 0, mid], color, %{
        "mode" => "paint",
        "mirror" => "x",
        "blend" => 0.008,
        "raise" => 0.008,
        "roughness" => rough,
        "surface" => %{"kind" => "stone", "scale" => 0.04}
      })
      | door(r["ground"], half, mid) ++ sign(r, hw)
    ]
  end

  # A folding gate of iron: a sheet with a bar each 9 cm, and rust.
  defp door("folding_gate", half, mid) do
    iron = %{"roughness" => 0.6, "metal" => 0.7, "surface" => %{"kind" => "brushed", "scale" => 0.004}}

    [
      e("box", [half, 0.03, @opening / 2], [0, -0.1, mid], "#6f8078", iron),
      e("box", [0.012, 0.06, @opening / 2], [-half + 0.045, -0.1, mid], "#55635c", %{
        "mode" => "paint",
        "blend" => 0.008,
        "raise" => 0.008,
        "repeat" => %{"count" => floor(2 * half / 0.09), "move" => [0.09, 0, 0]}
      })
    ]
  end

  # A roll-up door: slats of steel, 10 cm each.
  defp door("roller_door", half, mid) do
    [
      e("box", [half, 0.03, @opening / 2], [0, -0.1, mid], "#b9bdc0", %{"roughness" => 0.4, "metal" => 0.8}),
      e("box", [half, 0.06, 0.006], [0, -0.1, @floor + 0.1], "#8f9498", %{
        "mode" => "paint",
        "blend" => 0.006,
        "raise" => -0.006,
        "repeat" => %{"count" => floor(@opening / 0.1) - 1, "move" => [0, 0, 0.1]}
      }),
      e("box", [0.3, 0.05, 0.03], [0, -0.06, @floor + 0.35], "#3b3d40", %{"roughness" => 0.5, "metal" => 0.8})
    ]
  end

  # Four doors of glass in frames of aluminum, and a white gate of cut steel that is open at one side.
  defp door("glass_gate", half, mid) do
    frame = %{"roughness" => 0.4, "metal" => 0.8}

    [
      e("box", [half, 0.02, @opening / 2], [0, -0.2, mid], "#22303a", %{"roughness" => 0.06, "metal" => 0.0}),
      e(
        "box",
        [0.03, 0.04, @opening / 2],
        [-half + 0.03, -0.2, mid],
        "#5a5d60",
        Map.put(frame, "repeat", %{"count" => 5, "move" => [(2 * half - 0.06) / 4, 0, 0]})
      ),
      e("box", [half, 0.04, 0.03], [0, -0.2, @floor + @opening - 0.5], "#5a5d60", frame),
      e("box", [half / 2, 0.025, @opening / 2 - 0.25], [-half / 2, -0.03, mid - 0.25], "#f2f2ee", %{"roughness" => 0.5}),
      # (The pattern of the gate: holes as dark squares.)
      e("box", [0.05, 0.05, 0.05], [-half + 0.2, -0.03, @floor + 0.3], "#3a3d40", %{
        "mode" => "paint",
        "blend" => 0.01,
        "raise" => -0.01,
        "repeat" => %{"count" => max(floor(half / 0.2) - 1, 1), "move" => [0.2, 0, 0]}
      })
    ]
  end

  # A sign at the front of the first balcony (it hides the rail, as on a
  # street of shops), or on the wall over the opening of a house of one
  # storey: a board with two light marks (no words).
  defp sign(%{"sign" => nil}, _hw), do: []

  defp sign(%{"sign" => color} = r, hw) do
    {y, z} =
      if storeys(r["type"]) > 1,
        do: {reach(r["road"]) + 0.02, @floor + @ground + 0.4},
        else: {0.04, @floor + @opening + 0.5}

    [
      e("box", [hw - 0.05, 0.04, 0.5], [0, y, z], color, %{"roughness" => 0.4}),
      e("box", [hw - 0.4, 0.06, 0.16], [0, y + 0.02, z + 0.1], "#f4f1e6", %{
        "mode" => "paint",
        "blend" => 0.01,
        "opacity" => 0.9
      }),
      e("box", [hw / 2, 0.06, 0.05], [0, y + 0.02, z - 0.25], "#f4f1e6", %{
        "mode" => "paint",
        "blend" => 0.01,
        "opacity" => 0.7
      })
    ]
  end

  # An upper storey: the balcony, its door and its window, the shade over them.
  defp storey(r, hw, n) do
    z = @floor + @ground + (n - 1) * @upper
    out = reach(r["road"])
    side = if r["flip"], do: -1, else: 1
    {door, window} = {side * -hw * 0.42, side * hw * 0.45}
    glass? = r["family"] != "old"

    leaf =
      if glass?,
        do: {"#24323c", %{"roughness" => 0.08}},
        else: {"#7a5a38", %{"roughness" => 0.6, "surface" => %{"kind" => "wood", "scale" => 0.01}}}

    {tone, finish} = leaf
    frame = if glass?, do: "#5c6064", else: "#5e4428"

    slab =
      if out > 0.0,
        do: [
          e("box", [hw, out / 2 + 0.05, 0.06], [0, out / 2 - 0.05, z - 0.06], shade(r["wall"], 0.95), %{
            "roughness" => 0.85,
            "surface" => %{"kind" => "plaster", "scale" => 0.03}
          })
        ],
        else: []

    slab ++
      opening(door, z + 1.15, 0.6, 1.15, tone, finish, frame) ++
      opening(window, z + 1.6, 0.6, 0.7, tone, finish, frame) ++
      [
        # The shade over the door and the window.
        e("box", [hw - 0.05, 0.3, 0.04], [0, 0.25, z + 2.55], shade(r["wall"], 0.95), %{"roughness" => 0.85})
      ] ++ vents(r, hw, z) ++ wall_rail(r, hw, z, out)
  end

  # An opening of an upper storey: a hollow in the wall, a leaf, a frame round it and a bar at its middle.
  defp opening(x, z, half, high, tone, finish, frame) do
    [
      e("box", [half, 0.06, high], [x, 0, z], frame, %{"mode" => "subtract", "roughness" => 0.5}),
      e("box", [half - 0.05, 0.02, high - 0.05], [x, -0.07, z], tone, finish),
      e("box", [0.025, 0.03, high], [x, -0.05, z], frame, %{"roughness" => 0.5})
    ]
  end

  # Blocks for the air over the shade of an old house: dark squares in a row.
  defp vents(%{"vents" => true}, hw, z) do
    [
      e("box", [0.1, 0.1, 0.1], [-hw + 0.5, 0, z + 2.95], "#4a443a", %{
        "mode" => "paint",
        "blend" => 0.01,
        "raise" => -0.03,
        "repeat" => %{"count" => floor((2 * hw - 0.7) / 0.3), "move" => [0.3, 0, 0]}
      })
    ]
  end

  defp vents(_r, _hw, _z), do: []

  # The rail of a balcony as a low wall with a cap (the other rails are thin: in the details).
  defp wall_rail(%{"rail" => "wall"} = r, hw, z, out) when out > 0.0 do
    paint = %{"roughness" => 0.85, "surface" => %{"kind" => "plaster", "scale" => 0.03}}

    [
      e("box", [hw, 0.05, 0.45], [0, out - 0.05, z + 0.45], r["wall"], paint),
      e("box", [0.05, out / 2, 0.45], [hw - 0.05, out / 2, z + 0.45], r["wall"], Map.put(paint, "mirror", "x")),
      e("box", [hw + 0.02, 0.08, 0.03], [0, out - 0.05, z + 0.93], shade(r["wall"], 0.9), paint)
    ]
  end

  defp wall_rail(_r, _hw, _z, _out), do: []

  # The things on a front: the box of an air conditioner with its pipe, a
  # meter box on a pier, and the pipe of the rain water at one side.
  defp things(r, hw, high) do
    side = if r["flip"], do: -1, else: 1
    z = min(top(r) - 0.6, high - 1.2)

    cooler =
      if storeys(r["type"]) > 1 do
        [
          e("round_box", [0.34, 0.145, 0.215, 0.02], [side * (hw - 0.6), 0.16, z], "#e4e2da", %{"roughness" => 0.5}),
          e("cylinder", [0.15, 0.03], [side * (hw - 0.68), 0.3, z], "#6a6c6e", %{
            "mode" => "paint",
            "axis" => [0, 1, 0],
            "blend" => 0.01,
            "raise" => -0.005
          })
        ]
      else
        []
      end

    cooler ++
      [
        e("box", [0.125, 0.06, 0.175], [-side * (hw - 0.3), 0.06, 2.0], "#8e9294", %{"roughness" => 0.6, "metal" => 0.4}),
        tube([[side * (hw - 0.1), 0.07, high - 0.1], [side * (hw - 0.1), 0.07, 0.1]], [0.045, 0.045], "#9aa7ac", %{
          "roughness" => 0.5
        })
      ]
  end

  # The marks of the rain: dark lines down from the cap of the wall and from the slab of each balcony.
  defp stains(r, hw, high) do
    count = round(8 * r["age"])
    tops = [high | for(n <- 1..(storeys(r["type"]) - 1)//1, do: @floor + @ground + (n - 1) * @upper - 0.12)]

    for {z, k} <- Enum.with_index(tops), i <- 1..count//1 do
      x = (2 * unit(r["seed"], {:stain, k, i}) - 1) * (hw - 0.15)
      long = 0.3 + 0.9 * unit(r["seed"], {:long, k, i})

      e("box", [0.02 + 0.04 * unit(r["seed"], {:wide, k, i}), 0.6, long / 2], [x, 0.3, z - long / 2], "#5d5a50", %{
        "mode" => "paint",
        "blend" => 0.03,
        "opacity" => 0.35
      })
    end
  end

  # --- The thin parts of the front, at near ----------------------------------------

  defp details(r) do
    hw = r["width"] / 2
    out = reach(r["road"])

    rails =
      for n <- 1..(storeys(r["type"]) - 1)//1,
          out > 0.0,
          edit <- rail(r["rail"], hw, @floor + @ground + (n - 1) * @upper, out),
          do: edit

    rails ++ cloth(r, hw)
  end

  # Bars of iron each 12 cm with two flat rails.
  defp rail("bars", hw, z, out) do
    iron = %{"roughness" => 0.6, "metal" => 0.8, "surface" => %{"kind" => "rust", "scale" => 0.1}}

    [
      e(
        "box",
        [0.008, 0.008, 0.45],
        [-hw + 0.06, out - 0.05, z + 0.45],
        "#2e3432",
        Map.put(iron, "repeat", %{"count" => floor((2 * hw - 0.12) / 0.12) + 1, "move" => [0.12, 0, 0]})
      ),
      e("box", [hw - 0.04, 0.02, 0.012], [0, out - 0.05, z + 0.9], "#2e3432", iron),
      e("box", [hw - 0.04, 0.012, 0.012], [0, out - 0.05, z + 0.08], "#2e3432", iron),
      e("box", [0.012, out / 2, 0.012], [hw - 0.05, out / 2, z + 0.9], "#2e3432", Map.put(iron, "mirror", "x"))
    ]
  end

  # Tubes of stainless steel: posts, a top rail and two more.
  defp rail("tubes", hw, z, out) do
    steel = %{"roughness" => 0.25, "metal" => 1.0}

    line = fn h, r ->
      e("capsule", [hw - 0.06, r], [0, out - 0.05, z + h], "#c9ccce", Map.put(steel, "axis", [1, 0, 0]))
    end

    [
      e(
        "cylinder",
        [0.022, 0.46],
        [-hw + 0.06, out - 0.05, z + 0.46],
        "#c9ccce",
        Map.put(steel, "repeat", %{"count" => 4, "move" => [(2 * hw - 0.12) / 3, 0, 0]})
      ),
      line.(0.92, 0.025),
      line.(0.62, 0.014),
      line.(0.32, 0.014),
      e(
        "capsule",
        [out / 2 - 0.05, 0.02],
        [hw - 0.06, out / 2, z + 0.92],
        "#c9ccce",
        Map.merge(steel, %{"axis" => [0, 1, 0], "mirror" => "x"})
      )
    ]
  end

  # A sheet of glass between posts of steel.
  defp rail("glass", hw, z, out) do
    [
      e("box", [hw - 0.06, 0.008, 0.42], [0, out - 0.05, z + 0.5], "#9fc0cc", %{"roughness" => 0.05}),
      e("box", [0.02, 0.02, 0.48], [-hw + 0.05, out - 0.05, z + 0.48], "#c9ccce", %{
        "roughness" => 0.25,
        "metal" => 1.0,
        "repeat" => %{"count" => 3, "move" => [hw - 0.05, 0, 0]}
      })
    ]
  end

  defp rail("wall", _hw, _z, _out), do: []

  # The awning: a cloth on a slope with stripes, 1.6 m out.
  defp cloth(%{"awning" => true} = r, hw) do
    {normal, along} = {[0, 0.2588, 0.9659], [0, 0.9659, -0.2588]}
    at = [0, 0.85, @floor + @opening + 0.05]
    color = pick(r["seed"], :cloth, [{"#2f6fb5", 2}, {"#2f8a57", 1}, {"#b33a2e", 1}])

    [
      e("box", [hw - 0.1, 0.85, 0.012], at, "#f0eee6", %{
        "axis" => normal,
        "up" => along,
        "roughness" => 0.9,
        "surface" => %{"kind" => "fabric", "scale" => 0.004}
      }),
      e("box", [0.1, 0.9, 0.05], [-hw + 0.3, 0.85, @floor + @opening + 0.05], color, %{
        "mode" => "paint",
        "axis" => normal,
        "up" => along,
        "blend" => 0.004,
        "repeat" => %{"count" => floor((2 * hw - 0.4) / 0.4) + 1, "move" => [0.4, 0, 0]}
      })
    ]
  end

  defp cloth(_r, _hw), do: []

  # --- The body and the roof ----------------------------------------------------

  # The body behind the front: the side walls (bare when a neighbor is
  # there), the back wall with its door and a window for each storey.
  defp body(r) do
    {hw, d, top} = {r["width"] / 2, r["depth"], top(r)}
    back = -d
    plaster = %{"roughness" => 0.9, "surface" => %{"kind" => "plaster", "scale" => 0.05}}

    sides =
      for {key, x} <- [{"left", -hw}, {"right", hw}], r[key] == "shared" do
        e("box", [0.02, (d - @front) / 2, top / 2], [x, (back - @front) / 2, top / 2], "#aaa69c", %{
          "mode" => "paint",
          "blend" => 0.01,
          "roughness" => 0.95,
          "surface" => %{"kind" => "concrete", "scale" => 0.06}
        })
      end

    windows =
      for n <- 0..(storeys(r["type"]) - 1) do
        z = if n == 0, do: @floor + 1.6, else: @floor + @ground + (n - 1) * @upper + 1.6

        e("box", [0.5, 0.05, 0.6], [hw * 0.4, back, z], "#24323c", %{
          "mode" => "paint",
          "blend" => 0.01,
          "raise" => -0.02,
          "roughness" => 0.1
        })
      end

    [
      e("box", [hw, (d - @front) / 2, top / 2], [0, (back - @front) / 2, top / 2], shade(r["wall"], 0.97), plaster),
      e("box", [0.45, 0.05, 1.05], [-hw * 0.45, back, @floor + 1.05], "#6a6f72", %{
        "mode" => "paint",
        "blend" => 0.01,
        "raise" => -0.02,
        "roughness" => 0.5,
        "metal" => 0.5
      })
      | sides ++ windows
    ]
  end

  defp roof(%{"roof" => "terrace"} = r) do
    {hw, d, top} = {r["width"] / 2, r["depth"], top(r)}
    mid = -(d + @front) / 2
    wall = %{"roughness" => 0.9, "surface" => %{"kind" => "plaster", "scale" => 0.05}}
    # The head of the stair (tum): 2.7 m high, with its door to the terrace.
    {tx, ty, th} = {hw - 1.3, -d * 0.55, 2.7}
    steel = %{"roughness" => 0.25, "metal" => 1.0}

    [
      e("box", [hw, (d - @front) / 2, 0.06], [0, mid, top + 0.0], "#9c9a92", concrete()),
      # The parapet at the two sides and at the back.
      e(
        "box",
        [0.06, (d - @front) / 2, @parapet / 2],
        [hw - 0.06, mid, top + @parapet / 2],
        shade(r["wall"], 0.97),
        Map.put(wall, "mirror", "x")
      ),
      e("box", [hw, 0.06, @parapet / 2], [0, -d + 0.06, top + @parapet / 2], shade(r["wall"], 0.97), wall),
      e("box", [1.2, 1.5, th / 2], [tx, ty, top + th / 2], shade(r["wall"], 0.97), wall),
      e("box", [1.3, 1.6, 0.05], [tx, ty, top + th], "#9c9a92", concrete()),
      e("box", [0.05, 0.4, 1.0], [tx - 1.2, ty, top + 1.0], "#6a6f72", %{
        "mode" => "paint",
        "blend" => 0.01,
        "raise" => -0.02,
        "roughness" => 0.5,
        "metal" => 0.5
      }),
      # The water tank of 1,000 liters on its stand (0.96 m across, 1.7 m with its legs).
      e("cylinder", [0.48, 0.6], [tx, ty, top + th + 1.05], "#cfd2d4", steel),
      e("cone", [0.48, 0.15, 0.08], [tx, ty, top + th + 1.73], "#cfd2d4", steel),
      e(
        "box",
        [0.03, 0.03, 0.2],
        [tx + 0.3, ty + 0.3, top + th + 0.25],
        "#b8bbbd",
        Map.merge(steel, %{"repeat" => %{"count" => 4, "angle" => 90, "center" => [tx, ty, 0]}})
      ),
      # (The three bands of the tank.)
      e("cylinder", [0.485, 0.01], [tx, ty, top + th + 0.75], "#a9acae", %{
        "mode" => "paint",
        "blend" => 0.01,
        "raise" => 0.004,
        "repeat" => %{"count" => 3, "move" => [0, 0, 0.3]}
      })
    ]
  end

  # A roof of red tiles on two slopes, with ribs each 25 cm.
  defp roof(%{"roof" => "tiles"} = r) do
    {hw, d, top} = {r["width"] / 2, r["depth"], top(r)}
    high = 0.55 * (hw + 0.4)

    [
      e(
        "extrude",
        %{"outline" => [[-hw - 0.4, 0], [hw + 0.4, 0], [0, r4(high)]], "depth" => r4(d + 0.6)},
        [0, -d / 2 + 0.15, top],
        "#a8482f",
        %{
          "axis" => [0, 1, 0],
          "up" => [0, 0, 1],
          "roughness" => 0.8
        }
      ),
      e("box", [hw + 0.5, 0.02, high], [0, -d + 0.1, top + high / 2], "#8a3a26", %{
        "mode" => "paint",
        "blend" => 0.012,
        "raise" => 0.012,
        "repeat" => %{"count" => floor(d / 0.25), "move" => [0, 0.25, 0]}
      }),
      tube([[0, -d - 0.1, top + high], [0, 0.4, top + high]], [0.09, 0.09], "#93402a", %{"roughness" => 0.8})
    ]
  end

  # A roof of corrugated steel with one slope to the back, behind the low front wall.
  defp roof(%{"roof" => "steel"} = r) do
    {hw, d, top} = {r["width"] / 2, r["depth"], top(r)}
    {normal, along} = {[0, 0.0872, 0.9962], [0, 0.9962, -0.0872]}
    at = [0, -d / 2 - 0.1, top + 0.1]

    [
      e("box", [hw, d / 2, 0.03], at, "#8b98a0", %{
        "axis" => normal,
        "up" => along,
        "roughness" => 0.5,
        "metal" => 0.7,
        "surface" => %{"kind" => "rust", "scale" => 0.4}
      }),
      e("box", [0.03, d / 2, 0.06], [-hw + 0.1, -d / 2 - 0.1, top + 0.1], "#75828a", %{
        "mode" => "paint",
        "axis" => normal,
        "up" => along,
        "blend" => 0.012,
        "raise" => 0.012,
        "repeat" => %{"count" => floor((2 * hw - 0.2) / 0.2) + 1, "move" => [0.2, 0, 0]}
      })
    ]
  end

  # --- The words of an edit ------------------------------------------------------

  defp e(shape, size, at, color, more) do
    edit = Map.merge(%{"shape" => shape, "size" => rounded(size), "at" => rounded(at), "color" => color}, more)

    case edit do
      %{"raise" => h} -> Map.put(edit, "blend", max(Map.get(edit, "blend", 0), abs(h)))
      _ -> edit
    end
  end

  defp tube(points, radii, color, more),
    do:
      Map.merge(
        %{"shape" => "tube", "size" => %{"points" => Enum.map(points, &rounded/1), "radii" => radii}, "color" => color},
        more
      )

  defp concrete, do: %{"roughness" => 0.9, "surface" => %{"kind" => "concrete", "scale" => 0.05}}

  # An edit of a house at its place in a row, with the role of its part.
  # An edit with a mirror is two edits: one at each side of the middle
  # of the house (the mirror of a sculpture is across its own middle).
  defp place(%{"mirror" => "x", "at" => [ax, ay, az]} = edit, x, role) do
    edit = Map.delete(edit, "mirror")
    place(edit, x, role) ++ place(%{edit | "at" => [-ax, ay, az]}, x, role)
  end

  defp place(%{"shape" => "tube", "size" => %{"points" => points} = size} = edit, x, role) do
    moved = for [px, py, pz] <- points, do: [r4(px + x), py, pz]
    [Map.merge(edit, %{"size" => %{size | "points" => moved}, "material" => role})]
  end

  defp place(%{"at" => [ax, ay, az]} = edit, x, role) do
    edit = Map.merge(edit, %{"at" => [r4(ax + x), ay, az], "material" => role})

    case edit do
      %{"repeat" => %{"center" => [cx, cy, cz]} = repeat} ->
        [%{edit | "repeat" => %{repeat | "center" => [r4(cx + x), cy, cz]}}]

      _ ->
        [edit]
    end
  end

  defp rounded(list) when is_list(list), do: Enum.map(list, &rounded/1)
  defp rounded(%{} = map), do: map
  defp rounded(v), do: r4(v)

  defp r4(v) when is_integer(v), do: v
  defp r4(v), do: Float.round(v * 1.0, 4)

  # A color, darker by a part.
  defp shade("#" <> hex, part) do
    <<r::8, g::8, b::8>> = Base.decode16!(hex, case: :mixed)
    "#" <> Base.encode16(<<round(r * part), round(g * part), round(b * part)>>, case: :lower)
  end

  # A number from 0 to 1 for a seed and a key, and a choice by weights.
  defp unit(seed, key), do: :erlang.phash2({seed, key}, 1_000_000) / 1_000_000

  defp pick(seed, key, options) do
    total = options |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    at = unit(seed, key) * total

    Enum.reduce_while(options, 0, fn {value, weight}, sum ->
      if at < sum + weight, do: {:halt, value}, else: {:cont, sum + weight}
    end)
  end
end
