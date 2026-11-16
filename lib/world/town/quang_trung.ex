defmodule World.Town.QuangTrung do
  @moduledoc """
  The street Quang Trung of Vũng Tàu (the street of the Front Beach) as
  it is, from its survey (`priv/surveys/quang_trung.json`;
  `docs/plans/0018-quang-trung-street.md`).

  The first part is the block of the numbers 4 to 26, between the
  office of the port at number 2 and the corner of Nguyễn Trãi: a row of
  bars, restaurants and shops, 70 m long. The survey gives the order,
  the numbers and the names of its lots, and the corner house (three
  storeys, white). The rules of `World.Town.House` make each other
  choice from the seed: no photo shows each lot.

  The buildings that are not houses of a row (the blocks of the Grand
  Hotel) are requests of `World.Town.Building`.
  """

  alias World.Town.{Building, Street, Survey}

  # The seed of the choices that the survey does not have.
  @seed 26
  # The street between the fronts and the park: two roads of 10 m with a median (m, from photos).
  @road 23.0
  # The sidewalk of the side of the town (m, from a photo from the air).
  @sidewalk 5.5

  @sources [
    "The block of the numbers 4 to 26 of the street Quang Trung, Vũng Tàu, from its survey (priv/surveys/quang_trung.json, 2026-11-14). The order, the numbers and the uses of the lots are from addresses and from OpenStreetMap (© OpenStreetMap contributors, ODbL). The length of the block (70 m) and its depth (20 m) are from the Microsoft building footprints (ODbL).",
    "A guess, from the seed: the width of each lot (the mean, 5.8 m), its storeys, its roof, its family and its colors. No photo shows each lot. The corner house (24-26) has three storeys and is white (photos of 2014 and 2021, Wikimedia Commons). A sign has no words."
  ]

  @doc "The plan of the block of the numbers 4 to 26: 12 lots (two buildings are on two lots)."
  def plan do
    Street.plan(%{
      "seed" => @seed,
      "road" => @road,
      "sidewalk" => @sidewalk,
      "families" => [["old", 1], ["steel", 1]],
      "lots" => Survey.lots(Survey.rows("quang_trung", "QT-T02", "QT-T11"))
    })
  end

  @doc """
  The drawings of the block, from the south to the north: `{name,
  drawing}`, four lots each (a drawing has 16 parts with an image at the
  most).
  """
  def drawings do
    plan = plan()

    for {only, name} <- [{1..4, "quang_trung_4_10"}, {5..8, "quang_trung_12_18"}, {9..12, "quang_trung_20_26"}] do
      {name, Street.drawing(plan, only: only, name: name, sources: @sources)}
    end
  end

  @doc """
  The requests of the buildings of the street that are not houses of a
  row (`World.Town.Building`): `{name, request}`. The first two are the
  blocks of the Grand Hotel (2 Nguyễn Du).
  """
  def buildings, do: [{"khach_san_grand", grand()}, {"khach_san_grand_canh_nam", south_wing()}]

  @doc "The drawing of a building of `buildings/0`."
  def building(name), do: Building.drawing(Map.put(Map.new(buildings())[name], "name", name))

  # The main block of the Grand Hotel, behind its fore court. Its front (side 1) is to the court; the end with
  # the gable (side 4, at the left of a person in the court) is on Nguyễn Du.
  defp grand do
    {long, deep, terrace, wide} = {37.2, 24.0, 4.1, 5.0}
    white = %{"color" => "#f4f1e4", "roughness" => 0.6}

    # The pergola on the terrace: thin white columns with a beam, at the edge to the court.
    pergola =
      for i <- 0..8 do
        Map.merge(white, %{
          "shape" => "cylinder",
          "size" => [0.14, 1.4],
          "at" => [2.1 + 4.125 * i, wide - 0.35, terrace + 1.4]
        })
      end ++
        [
          Map.merge(white, %{
            "shape" => "box",
            "size" => [16.8, 0.15, 0.12],
            "at" => [long / 2, wide - 0.35, terrace + 2.9]
          })
        ]

    # The tower of the stair at the south end: a storey higher than the ridge.
    tower = %{
      "shape" => "box",
      "size" => [2.6, 3.0, 8.4],
      "at" => [2.6, -6.0, 8.4],
      "color" => "#e3aa6c",
      "roughness" => 0.85,
      "surface" => %{"kind" => "plaster", "scale" => 0.04}
    }

    %{
      "sources" => [
        "The main block of the Grand Hotel of Vũng Tàu (2 Nguyễn Du), behind its fore court on Quang Trung, from the rules of a building (plan 0018). The plan is its footprint in OpenStreetMap (way 118950627, © OpenStreetMap contributors, ODbL): 37.2 m to the court, 24 m deep.",
        "The front is from two photos of 2014 (trungydang, Wikimedia Commons, CC BY 3.0), a photo from the air and a photo at night (mia.vn): 3 storeys, pale yellow with orange pilasters; balconies with rails of iron at two storeys; a long terrace over the ground storey with a pergola on white columns; the name in red letters on the cornice; a roof of yellow tiles behind a terrace, with a gable to Nguyễn Du; a tower at the south end.",
        "A guess: the heights (from a bay of 4.5 m as the scale), 8 bays, the ground storey behind the terrace, the two ends and the back (no photo), the size of the tower. The terrace is straight here; the real one has a curve."
      ],
      "size" => [long, deep],
      "ground" => 3.6,
      "band" => 0.9,
      "colors" => %{"band" => "#d99a5c"},
      "fronts" => [
        %{
          "style" => "loggias",
          "inset" => 0.4,
          "bays" => 8,
          "rail" => "bars",
          "ground" => "windows",
          "window" => [2.6, 2.4],
          "sill" => 0.4,
          "bars" => 3
        },
        %{"side" => 2, "style" => "windows", "inset" => 2.0, "bays" => 4, "band" => true, "window" => [1.3, 1.7]},
        %{"side" => 3, "style" => "windows", "inset" => 1.0, "bays" => 8, "band" => true, "window" => [1.3, 1.7]},
        %{"side" => 4, "style" => "windows", "inset" => 2.0, "bays" => 4, "band" => true, "window" => [1.3, 1.7]}
      ],
      "cornice" => %{"high" => 1.1, "out" => 0.45},
      "roof" => %{"kind" => "tiles", "high" => 4.4, "inset" => 2.6, "gables" => [4]},
      "porches" => [
        %{"wide" => 35.0, "deep" => wide, "high" => terrace, "columns" => 9, "door" => [4.0, 2.6], "terrace" => true}
      ],
      "letters" => [%{"text" => "GRAND HOTEL", "z" => 12.35, "high" => 0.9}],
      "apron" => 0.6,
      "more" => %{"than" => [tower | pergola]}
    }
  end

  # The south wing of the Grand Hotel, on Quang Trung (side 1) at the corner of Nguyễn Trãi (side 2).
  defp south_wing do
    {long, deep} = {39.7, 20.3}
    leaves = %{"color" => "#6f7a4c", "roughness" => 0.95, "surface" => %{"kind" => "leaves", "scale" => 0.3}}
    stone = %{"color" => "#7d7a72", "roughness" => 0.9, "surface" => %{"kind" => "stone", "scale" => 0.15}}
    box = fn look, size, at -> Map.merge(look, %{"shape" => "box", "size" => size, "at" => at}) end

    # The garden: a bed behind a low wall of stone, 4 m from each front, and the stone with the name.
    garden = [
      box.(leaves, [long / 2 + 2.0, 2.0, 0.15], [long / 2 - 2.0, 2.0, -0.15]),
      box.(stone, [long / 2 + 2.0, 0.2, 0.45], [long / 2 - 2.0, 4.0, 0.15]),
      box.(leaves, [2.0, deep / 2, 0.15], [-2.0, -deep / 2, -0.15]),
      box.(stone, [0.2, deep / 2 + 2.0, 0.45], [-4.0, -deep / 2 + 2.0, 0.15]),
      %{
        "shape" => "ellipsoid",
        "size" => [1.3, 0.45, 0.75],
        "at" => [4.0, 2.4, 0.6],
        "color" => "#c9a56a",
        "roughness" => 0.9,
        "surface" => %{"kind" => "stone", "scale" => 0.2}
      }
    ]

    %{
      "sources" => [
        "The south wing of the Grand Hotel of Vũng Tàu (2 Nguyễn Du), on Quang Trung at the corner of Nguyễn Trãi, from the rules of a building (plan 0018). The plan is its footprint in OpenStreetMap (way 118946705, © OpenStreetMap contributors, ODbL): 39.7 m on Quang Trung, 20.3 m deep.",
        "The front is from a photo of 2015 (trungydang, Wikimedia Commons, CC BY 3.0): 3 storeys; a low ground storey between piers; a brown band; two storeys of loggias between orange pilasters, with rails of iron; pale yellow walls; a cornice; a stone with the name in a bed behind a low wall. The roof of yellow tiles with four slopes, about 3 m high, is from a photo from the air (mia.vn).",
        "A guess: the heights (from a bay of 4.3 m as the scale), 9 bays on Quang Trung, the front on Nguyễn Trãi (4 bays as those of Quang Trung), the north end and the back (no photo), the pattern of the rails."
      ],
      "size" => [long, deep],
      "fronts" => [
        %{"style" => "loggias", "inset" => 0.4, "bays" => 9},
        %{"side" => 2, "style" => "loggias", "inset" => 0.4, "bays" => 4},
        %{"side" => 3, "style" => "windows", "inset" => 1.8, "bays" => 8, "band" => true, "window" => [1.2, 1.2]},
        %{"side" => 4, "style" => "windows", "inset" => 1.0, "bays" => 3, "band" => true, "window" => [1.2, 1.2]}
      ],
      "roof" => %{"kind" => "tiles", "high" => 3.0},
      "more" => %{"nen" => garden}
    }
  end
end
