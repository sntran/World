defmodule World.BuildingTest do
  # A building of a town from a request of a few words (plan 0018, section 11).
  use ExUnit.Case, async: true

  alias World.Town.{Building, Wall}

  defp edits(drawing, part) do
    node = Enum.find(drawing["nodes"], &(&1["name"] == "#{drawing["name"]}_#{part}"))
    node && node["skill"]["sculpt"]["edits"]
  end

  defp checked(request) do
    drawing = Building.drawing(request)
    assert {:ok, _} = World.Drawing.check(drawing, "d")
    assert JSON.decode!(JSON.encode!(drawing)) == drawing
    drawing
  end

  test "a wall has its own axes: the way along it and the height, with the direction out of the building" do
    # The front of a plan from a size: from the corner at the left of a person in the street to the right.
    w = Wall.new([10, 0], [0, 0])
    assert %Wall{long: 10.0, t: {-1.0, +0.0}, n: {+0.0, 1.0}} = w
    assert Wall.at(w, 2, 3) == [8.0, +0.0, 3]
    assert Wall.at(w, 2, 3.5, 0.25) == [8.0, 0.25, 3.5]
    assert Wall.axis(w) == [+0.0, 1.0, 0]
    assert Wall.at(Wall.out(w, 0.5), 0, 0) == [10.0, 0.5, 0]

    # A box is about its place; the key out moves its middle out of the wall.
    assert Wall.box(w, 2, 3, {4, 1, 0.5}, "#ffffff", %{"out" => 0.25, "roughness" => 0.5}) == %{
             "shape" => "box",
             "size" => [2.0, 0.5, 0.25],
             "at" => [8.0, 0.25, 3],
             "color" => "#ffffff",
             "axis" => [+0.0, 1.0, 0],
             "up" => [0, 0, 1],
             "roughness" => 0.5
           }

    assert %{"shape" => "box", "at" => [8.0, +0.0, 3]} = Wall.box(w, 2, 3, {4, 1, 0.5}, "#ffffff")
    # A paint has a small blend; with a raise, the blend is not smaller than the raise.
    assert %{"mode" => "paint", "blend" => 0.01, "size" => [1.0, 0.5, 0.25]} = Wall.paint(w, 2, 3, {2, 1}, "#000000")
    assert %{"raise" => -0.06, "blend" => 0.06} = Wall.paint(w, 2, 3, {2, 1}, "#000000", %{"raise" => -0.06})

    # A window: its frame, its glass in a hollow, and its bars.
    assert [frame, glass, bar_1, bar_2] = Wall.window(w, 5, 2, {1.2, 1.5}, "#55707c", "#f4f1e4", 2)
    assert %{"color" => "#f4f1e4", "raise" => 0.015, "size" => [0.68, 0.83, 0.25]} = frame
    assert %{"color" => "#55707c", "raise" => -0.06, "at" => [5.0, +0.0, 2]} = glass
    assert [hd(bar_1["at"]), hd(bar_2["at"])] == [5.2, 4.8]
    assert length(Wall.window(w, 5, 2, {1.2, 1.5}, "#55707c", "#f4f1e4")) == 3
    assert length(Wall.window(w, 5, 2, {1.2, 1.5}, "#55707c", "#f4f1e4", 0)) == 2

    assert Wall.tube([[0, 0, 0], [0, 0, 1]], [0.02, 0.02], "#2f4a3c") ==
             %{
               "shape" => "tube",
               "size" => %{"points" => [[0, 0, 0], [0, 0, 1]], "radii" => [0.02, 0.02]},
               "color" => "#2f4a3c"
             }

    assert %{
             "shape" => "extrude",
             "size" => %{"outline" => [[0, 0], [1, 0], [0, 1]], "depth" => 2},
             "at" => [0, 0, 1],
             "mode" => "crop"
           } =
             Wall.outline([[0, 0], [1, 0], [0, 1]], 2, [0, 0, 1], "#ffffff", %{"mode" => "crop"})

    assert %{"shape" => "extrude"} = Wall.outline([[0, 0], [1, 0], [0, 1]], 2, [0, 0, 1], "#ffffff")
    assert %{"shape" => "ball", "size" => [1]} = Wall.edit("ball", [1], [0, 0, 0], "#ffffff")
  end

  test "a request with no word: a block of three storeys with a flat roof behind its parapet" do
    b = Building.spec()
    assert Building.spec(b) == b

    assert %{
             "name" => "toa_nha",
             "storeys" => 3,
             "ground" => 3.0,
             "band" => 1.1,
             "storey" => 3.5,
             "fronts" => [],
             "porches" => [],
             "letters" => []
           } = b

    assert b["plan"] == [[12.0, +0.0], [+0.0, +0.0], [+0.0, -10.0], [12.0, -10.0]]
    assert b["roof"] == %{"kind" => "flat", "parapet" => 1.0} and b["cornice"] == %{"high" => +0.0, "out" => 0.35}
    assert b["colors"] == Building.colors() and Building.styles() == ~w(plain windows loggias glass)

    # The floors are over the band; the eaves are under the next floor; the parapet is the top.
    assert Building.heights(b) == %{
             "ground" => 3.0,
             "floors" => [4.1, 7.6],
             "opening" => 2.75,
             "eaves" => 10.8,
             "top" => 11.8
           }

    assert %{"floors" => [], "eaves" => 4.1, "top" => 5.1} = Building.heights(%{"storeys" => 1})
    assert %{"eaves" => 3.6} = Building.heights(%{"storeys" => 1, "band" => 0})
    assert %{"top" => 12.3} = Building.heights(%{"cornice" => %{"high" => 1.5}})

    d = checked(%{})
    assert Building.drawing() == d
    assert d["kind"] == "house" and d["extras"] == %{"building" => b}
    # With no letters and no thing on the roof, the parts are the body and the ground.
    assert Enum.map(d["nodes"], & &1["name"]) == ~w(toa_nha_than toa_nha_nen) and map_size(d["materials"]) == 2
    # The body: the plan up to the top of the parapet, with the roof behind the parapet taken away.
    assert [mass, deck] = edits(d, "than")

    assert %{
             "shape" => "extrude",
             "size" => %{"outline" => outline, "depth" => 11.8},
             "at" => [0, 0, 5.9],
             "material" => "part_01"
           } = mass

    assert outline == b["plan"]

    assert %{
             "mode" => "subtract",
             "size" => %{"outline" => [[11.6, -0.4], [0.4, -0.4], [0.4, -9.6], [11.6, -9.6]], "depth" => 2.0},
             "at" => [0, 0, 11.8]
           } = deck

    # The ground goes 0.6 m round the plan.
    assert [
             %{
               "size" => %{"outline" => [[12.6, 0.6], [-0.6, 0.6], [-0.6, -10.6], [12.6, -10.6]]},
               "material" => "part_02"
             }
           ] = edits(d, "nen")

    body = hd(d["nodes"])["skill"]["sculpt"]
    assert body["budget"] == %{"near" => 14_500, "mid" => 2_550, "far" => 250} and not Map.has_key?(body, "details")
    assert body["dirt"] == 0.35 and body["wear"] == 0.15
  end

  test "a front of loggias: equal bays between pilasters, a rail at each loggia, piers at the ground storey" do
    request = %{
      "name" => "khach_san",
      "size" => [20, 12],
      "sources" => ["A hotel of the test."],
      "colors" => %{"wall" => "#ffffff"},
      "fronts" => [
        %{"style" => "loggias", "inset" => 0.4, "bays" => 4},
        %{
          "side" => 2,
          "style" => "loggias",
          "bays" => 2,
          "ground" => "windows",
          "rail" => "bars",
          "band" => true,
          "paint" => "#a6cbe3",
          "out" => 0.5
        },
        %{"side" => 3, "style" => "loggias", "bays" => 3, "ground" => "blank", "rail" => "none"},
        %{"side" => 4, "style" => "plain", "band" => true}
      ],
      "roof" => %{"kind" => "tiles"},
      "age" => 1
    }

    d = checked(request)

    assert d["sources"] == ["A hotel of the test."] and
             Enum.map(d["nodes"], & &1["name"]) == ~w(khach_san_than khach_san_mai khach_san_nen)

    body = edits(d, "than")
    hollows = Enum.filter(body, &(&1["mode"] == "subtract"))
    # A loggia at two storeys in each of the 9 bays, and an opening at the ground of the 4 bays with piers.
    assert Enum.count(hollows, &(Enum.at(&1["size"], 1) == 1.375)) == 18 and length(hollows) == 22
    # The first loggia of the front: 4.8 m from pilaster to pilaster less the pilaster, 1.5 m deep, at the left end.
    assert %{"size" => [2.025, 1.375, 1.5], "at" => [17.2, +0.0, 5.475], "color" => "#ffffff", "axis" => [+0.0, 1.0, 0]} =
             hd(hollows)

    # A part that stands out is a box of the wall, and its paint and its band are on it.
    assert Enum.any?(body, &(&1["size"] == [6.0, 5.4, 0.5] and &1["at"] == [+0.0, -6.0, 5.4]))
    assert Enum.any?(body, &(&1["color"] == "#a6cbe3" and &1["mode"] == "paint" and hd(&1["at"]) == -0.5))
    assert Enum.count(body, &(&1["color"] == "#a9694f" and &1["size"] == [6.0, 0.55, 0.25])) == 2
    # The rails are a detail of the near level: 15 tubes for a rail with crosses, bars each 12 cm for the other.
    [detail] = hd(d["nodes"])["skill"]["sculpt"]["details"]
    assert detail["levels"] == ["near"] and detail["cells"] == %{"near" => 0.012}

    # (8 rails with crosses: 2 bars, 5 posts and 8 diagonals. 4 rails with 45 upright bars.)
    assert Enum.frequencies_by(detail["edits"], &hd(&1["size"]["radii"])) == %{
             0.022 => 24,
             0.02 => 40,
             0.014 => 64,
             0.012 => 180
           }

    assert Enum.all?(
             detail["edits"],
             &(&1["shape"] == "tube" and &1["color"] == "#2f4a3c" and &1["material"] == "part_01")
           )

    assert detail["budget"] == %{"near" => 308 * 60}
    # The roof of tiles on its cornice: a prism along the long sides, cut to a slope at each end.
    assert [
             %{
               "shape" => "extrude",
               "size" => %{"outline" => [[-5.35, 0], [5.35, 0], [0, 2.2]], "depth" => 18.7},
               "at" => [10.0, -6.0, 11.95]
             },
             cut,
             flat | rows
           ] =
             edits(d, "mai")

    assert %{
             "mode" => "crop",
             "size" => %{"outline" => [[-9.35, 0], [9.35, 0], [4.0, 2.2], [-4.0, 2.2]]},
             "axis" => [+0.0, -1.0, 0]
           } = cut

    # (The flat part behind the cornice is 6 cm over its top.)
    assert %{"size" => %{"depth" => 0.12}, "at" => [0, 0, 12.0], "color" => "#9a9d98"} = flat
    assert length(rows) == 7 and Enum.all?(rows, &(&1["mode"] == "paint" and &1["color"] == "#b88c3a"))
    # The cornice is round the plan, with its lip.
    assert Enum.any?(
             body,
             &(&1["shape"] == "extrude" and
                 &1["size"]["outline"] == [[20.35, 0.35], [-0.35, 0.35], [-0.35, -12.35], [20.35, -12.35]])
           )

    assert hd(d["nodes"])["skill"]["sculpt"]["dirt"] == 0.55
  end

  test "fronts of windows and of glass, on a plan with corners" do
    plan = [[10, 0], [0, 0], [0, -8], [5, -8], [5, -4], [10, -4]]

    d =
      checked(%{
        "plan" => plan,
        "storeys" => 2,
        "fronts" => [
          %{"style" => "windows", "bays" => 3, "ledges" => true, "pilasters" => true, "bars" => 2},
          %{"side" => 2, "style" => "windows", "places" => [2, 6], "ground" => "blank"},
          %{"side" => 3, "style" => "glass"},
          %{"side" => 5, "style" => "glass", "ground" => "blank", "pitch" => 2.5, "from" => 0.5, "to" => 4.5}
        ],
        "cornice" => %{"high" => 0.6, "out" => 0.2}
      })

    body = edits(d, "than")
    assert hd(body)["size"]["outline"] == Enum.map(plan, fn [x, y] -> [x * 1.0, y * 1.0] end)
    # The cornice follows the corners of the plan: a corner that goes in stays 0.2 m from its two walls.
    cornice =
      Enum.find(
        body,
        &(&1["shape"] == "extrude" and &1["size"]["depth"] == 0.3 and hd(&1["at"]) == 0 and &1["color"] == "#f0e6c2")
      )

    assert cornice["size"]["outline"] == [
             [10.2, 0.2],
             [-0.2, 0.2],
             [-0.2, -8.2],
             [5.2, -8.2],
             [5.2, -4.2],
             [10.2, -4.2]
           ]

    glass = Enum.filter(body, &(&1["color"] == "#55707c"))
    # Three bays at two storeys, two places at the upper storey only, and two fronts of glass.
    assert length(glass) == 3 * 2 + 2 + 2
    assert Enum.count(body, &(&1["color"] == "#dfe1dc")) == 1
    assert Enum.count(body, &(&1["color"] == "#e3aa6c" and &1["size"] == [0.375, 3.65, 0.25])) == 4
    # The glass of side 3 goes to the foot of the wall; the glass of side 5 starts over the ground storey.
    assert [low, high] = Enum.filter(glass, &(&1["raise"] == -0.05))
    assert List.last(low["at"]) == 3.65 and Enum.at(low["size"], 1) == 3.35
    assert List.last(high["at"]) == 5.25 and Enum.at(high["size"], 1) == 1.75
  end

  test "a roof of tiles with gables, a porch with a terrace, and the name in letters" do
    request = %{
      "name" => "nha_chu",
      "size" => [8, 14],
      "storeys" => 2,
      "roof" => %{"kind" => "tiles", "high" => 3, "inset" => -0.4, "gables" => [1]},
      "porches" => [
        %{"wide" => 5, "deep" => 2, "terrace" => true, "board" => "#1f5fae"},
        %{"side" => 2, "columns" => 1, "steps" => 0, "door" => nil},
        %{"side" => 3, "columns" => 0, "wide" => 3}
      ],
      "letters" => [
        %{"text" => "GRAND HOTEL", "z" => 9.0},
        %{"text" => "REX", "z" => 8.0, "high" => 0.6},
        %{"side" => 2, "text" => "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "z" => 3.5, "high" => 0.3}
      ],
      "more" => %{"mai" => [%{"shape" => "box", "size" => [0.3, 0.3, 0.5], "at" => [4, -7, 12], "color" => "#b9382e"}]}
    }

    d = checked(request)
    assert Enum.map(d["nodes"], & &1["name"]) == for(part <- ~w(than mai chu nen), do: "nha_chu_#{part}")
    assert %{"eaves" => 7.3, "top" => 8.5} = Building.heights(request)
    # The ridge is along the long sides (side 2); the gable is at side 1, and its other end has a slope.
    assert [prism, cut | rest] = edits(d, "mai")

    assert %{"size" => %{"outline" => [[-4.75, 0], [4.75, 0], [0, 3.0]], "depth" => 15.5}, "axis" => [+0.0, -1.0, 0]} =
             prism

    assert %{"mode" => "crop", "size" => %{"outline" => [[-7.75, 0], [7.95, 0], [7.95, 3.0], [-3.0, 3.0]]}} = cut
    # The roof hangs over the cornice: no flat part. The wall of the gable is after the rows of the tiles (their
    # paint is not on it), and the edits of the key more are at the end.
    assert {rows, [gable, more]} = Enum.split(rest, -2)
    assert length(rows) == 10 and Enum.all?(rows, &(&1["mode"] == "paint"))
    assert %{"at" => [4.0, 0.65, 8.45], "color" => "#f1dc86", "size" => %{"depth" => 0.3}} = gable
    assert more["color"] == "#b9382e"
    # With a gable at each end, no cut.
    two = Building.drawing(put_in(request, ["roof", "gables"], [3, 1]))
    assert Enum.count(edits(two, "mai"), &(&1["mode"] == "crop")) == 0
    assert two["extras"]["building"]["roof"]["gables"] == [1, 3]

    # The letters: on the top of the cornice, in front of the cornice, and in front of the wall.
    letters = edits(d, "chu")
    assert Enum.all?(letters, &(&1["shape"] == "tube" and &1["color"] == "#b3261e" and &1["material"] == "part_03"))
    on_top = Enum.filter(letters, &(hd(&1["size"]["radii"]) == 0.06))
    assert length(on_top) == 16 and Enum.all?(on_top, &(Enum.at(hd(&1["size"]["points"]), 1) == 0.23))

    assert Enum.all?(
             Enum.filter(letters, &(hd(&1["size"]["radii"]) == 0.048)),
             &(Enum.at(hd(&1["size"]["points"]), 1) == 0.47)
           )

    assert Enum.count(letters, &(hd(&1["size"]["radii"]) == 0.024)) == 39
    # The text reads from the left to the right for a person in the street: the first letter is at the larger x.
    assert hd(hd(hd(on_top)["size"]["points"])) > hd(hd(List.last(on_top)["size"]["points"]))

    assert Enum.find(d["nodes"], &(&1["name"] == "nha_chu_chu"))["skill"]["sculpt"]["cells"] == %{
             "near" => 0.0081,
             "mid" => 0.012,
             "far" => 0.024
           }

    # The porches: a slab on columns with steps and a door; a board; a rail round a terrace.
    body = edits(d, "than")
    assert Enum.count(body, &(&1["shape"] == "cylinder")) == 3
    assert Enum.count(body, &(&1["color"] == "#b9bbb6")) == 4
    assert Enum.any?(body, &(&1["color"] == "#1f5fae"))
    [detail] = hd(d["nodes"])["skill"]["sculpt"]["details"]
    assert length(detail["edits"]) == 2 + 9 and detail["budget"] == %{"near" => 2000}
  end

  test "a line of letters with its own width: narrow letters, or the length of the line" do
    request = %{
      "size" => [20, 10],
      "letters" => [
        %{"text" => "HAI AU", "z" => 4.0, "high" => 2.1, "long" => 5.8},
        %{"side" => 3, "text" => "REX", "high" => 1.2, "wide" => 0.4},
        %{"side" => 2, "text" => "I", "high" => 0.9}
      ]
    }

    b = Building.spec(request)
    # The full request has the width of a letter that the length gives, and not the length; the width by default
    # is 2/3 of the height.
    assert [%{"wide" => 0.6105, "high" => 2.1} = hai_au, %{"wide" => 0.4}, %{"wide" => 0.6}] = b["letters"]
    refute Map.has_key?(hai_au, "long")
    assert Building.spec(b) == b
    # A length goes before a width.
    assert hd(Building.spec(put_in(request, ["letters", Access.at(0), "wide"], 1.0))["letters"])["wide"] == 0.6105

    letters = edits(checked(request), "chu")
    {hai_au, rest} = Enum.split(letters, 9)
    {rex, [i]} = Enum.split(rest, 6)
    # H, A, I, A, U: 9 strokes; the line goes from x = 12.9 to x = 7.1 on the front, with letters 0.6105 m wide.
    xs = for t <- hai_au, [x, _, _] <- t["size"]["points"], do: x
    assert_in_delta Enum.max(xs) - Enum.min(xs), 5.8, 0.001
    assert_in_delta Enum.max(xs), 12.9, 0.001
    assert [[12.9, 0.12, 4.0], [12.9, 0.12, 6.1]] = Enum.map(hd(hai_au)["size"]["points"], &round_point/1)
    assert [[x0, _, _], _] = hd(hai_au)["size"]["points"]
    assert [[x1, _, _], _] = Enum.at(hai_au, 1)["size"]["points"]
    assert_in_delta x0 - x1, 0.6105, 0.0001
    # The height of the strokes stays: 2.1 m, with a radius of 0.08 of the height.
    zs = for t <- hai_au, [_, _, z] <- t["size"]["points"], do: z
    assert {Enum.min(zs), Enum.max(zs)} == {4.0, 6.1} and hd(hd(hai_au)["size"]["radii"]) == 0.168

    # REX on the back (side 3, x from 0 to 20): the line is 0.4 (1.7 3 - 0.7) = 1.76 m long, about x = 10.
    xs = for t <- rex, [x, _, _] <- t["size"]["points"], do: x
    assert_in_delta Enum.max(xs) - Enum.min(xs), 1.76, 0.0001
    assert_in_delta (Enum.max(xs) + Enum.min(xs)) / 2, 10.0, 0.0001
    # One letter of the width by default, in the middle of its box: at the middle of side 2, 0.12 m out of it.
    assert i["size"]["points"] == [[-0.12, -5.0, 3.0], [-0.12, -5.0, 3.9]]

    for {letter, path, text} <- [
          {%{"text" => "REX", "high" => 1.2, "wide" => 0.2}, "letters.0.wide",
           "the value of wide is a number from 0.3 to 2.4"},
          {%{"text" => "REX", "high" => 1.2, "wide" => "narrow"}, "letters.0.wide", "the value of wide"},
          {%{"text" => "HOTEL", "high" => 2, "long" => 1}, "letters.0.long",
           "a line of 5 letters 1.0 m long has letters 0.1282 m wide: a letter is from 0.5 m to 4.0 m wide"},
          {%{"text" => "HOTEL", "high" => 0.3, "long" => 40}, "letters.0.long",
           "a line of 5 letters 40.0 m long has letters 5.1282 m wide: a letter is from 0.075 m to 0.6 m wide"},
          {%{"text" => "HOTEL", "long" => 0}, "letters.0.long", "the value of long is a number from 0.1 to 200"}
        ] do
      error = assert_raise ArgumentError, fn -> Building.spec(%{"letters" => [letter]}) end

      assert String.starts_with?(error.message, "#{path}: #{text}"), error.message

      assert {:error, [%{"path" => "options." <> ^path}]} =
               World.Orders.check(%{"blueprint" => "building", "options" => %{"letters" => [letter]}})
    end
  end

  defp round_point(point), do: Enum.map(point, &(Float.round(&1 * 1.0, 3) + 0.0))

  test "a porch with a curved front and its fascia, and balconies with round ends" do
    request = %{
      "size" => [20, 12],
      "storeys" => 3,
      "fronts" => [
        %{"from" => 2, "to" => 10, "bays" => 2, "balcony" => 1.2, "round" => [1.2, 1.2], "rail" => "bars"},
        %{
          "side" => 3,
          "from" => 6,
          "to" => 10.4,
          "bays" => 1,
          "balcony" => 2.2,
          "round" => [2.2, 2.2],
          "rail" => "none"
        },
        %{"side" => 2, "bays" => 2, "balcony" => 1.0, "rail" => "cross"}
      ],
      "porches" => [
        %{"at" => 15, "wide" => 8, "deep" => 5, "round" => [0, 4], "fascia" => 1.2, "columns" => 4},
        %{"side" => 3, "at" => 4, "wide" => 6, "deep" => 3, "round" => [3, 3], "terrace" => true, "columns" => 1}
      ]
    }

    b = Building.spec(request)
    assert Building.spec(b) == b

    assert [%{"balcony" => 1.2, "round" => [1.2, 1.2]}, %{"round" => [2.2, 2.2]}, %{"round" => [+0.0, +0.0]}] =
             b["fronts"]

    assert [%{"round" => [+0.0, 4.0], "fascia" => 1.2}, %{"round" => [3.0, 3.0], "fascia" => +0.0}] = b["porches"]
    # With no balcony and no round, a front and a porch are as before.
    assert %{"fronts" => [%{"balcony" => +0.0, "round" => [+0.0, +0.0]}]} = Building.spec(%{"fronts" => [%{}]})
    assert %{"porches" => [%{"round" => [+0.0, +0.0], "fascia" => +0.0}]} = Building.spec(%{"porches" => [%{}]})

    d = checked(request)
    body = edits(d, "than")
    # A balcony at each floor over the ground storey (4.1 m and 7.6 m): a slab 0.2 m thick in the color of the trim,
    # with its top at the floor.
    slabs = Enum.filter(body, &(&1["shape"] == "extrude" and &1["size"]["depth"] == 0.2))
    assert length(slabs) == 6 and Enum.all?(slabs, &(&1["color"] == "#e3aa6c"))
    assert Enum.frequencies_by(slabs, &List.last(&1["at"])) == %{4.0 => 3, 7.5 => 3}
    [round, half, square] = for k <- [0, 2, 4], do: Enum.at(slabs, k)["size"]["outline"]
    # The front of side 1 from s = 2 to 10 (x = 18 to 10), 1.2 m out, with a quarter of a circle at each end.
    assert {Enum.min_by(round, &hd/1), Enum.max_by(round, &hd/1)} == {[10.0, +0.0], [18.0, +0.0]}
    assert Enum.max(Enum.map(round, &List.last/1)) == 1.2 and length(round) == 18
    assert [16.8, 1.2] in round and [11.2, 1.2] in round

    for [x, y] <- round, x > 16.8 or x < 11.2 do
      centre = if x > 14, do: 16.8, else: 11.2
      assert_in_delta :math.sqrt((x - centre) ** 2 + y ** 2), 1.2, 0.0002
    end

    # Two round ends of 2.2 m on a front of 4.4 m: half of a disc on side 3, about x = 8.2.
    assert Enum.all?(half, fn [x, y] -> :math.sqrt((x - 8.2) ** 2 + (y + 12) ** 2) <= 2.2002 end)
    assert Enum.min(Enum.map(half, &List.last/1)) == -14.2
    # Square ends: a rectangle out of side 2.
    assert square == [[+0.0, +0.0], [-1.0, +0.0], [-1.0, -12.0], [+0.0, -12.0]]

    # The curved porch: its slab, the trim on it and the fascia of 1.2 m round its front, from 0.1 m over the top.
    [porch, trim, fascia, back, _] =
      Enum.filter(body, &(&1["shape"] == "extrude" and &1["size"]["depth"] != 0.2)) |> Enum.drop(2)

    assert %{"at" => [0, 0, 3.35], "color" => "#f0e6c2"} = porch
    # (Side 1 from s = 11 to 19, 5 m deep; a quarter of a circle of 4 m at the right corner, about s = 15, out 1.)
    assert porch["size"]["outline"] == [
             [9.0, +0.0],
             [9.0, 5.0],
             [5.0, 5.0],
             [4.2196, 4.9231],
             [3.4693, 4.6955],
             [2.7777, 4.3259],
             [2.1716, 3.8284],
             [1.6741, 3.2223],
             [1.3045, 2.5307],
             [1.0769, 1.7804],
             [1.0, 1.0],
             [1.0, +0.0]
           ]

    assert %{"at" => [0, 0, 3.52], "color" => "#e3aa6c", "size" => %{"outline" => [[9.1, +0.0] | _]}} = trim
    assert %{"at" => [0, 0, 3.0], "color" => "#e3aa6c", "size" => %{"depth" => 1.2, "outline" => outline}} = fascia
    assert [9.1, +0.0] in outline and [8.9, +0.0] in outline and [1.1, +0.0] in outline and [0.9, +0.0] in outline
    # The porch with two round corners of 3 m on side 3: half of a disc.
    assert Enum.min(Enum.map(back["size"]["outline"], &List.last/1)) == -15.0
    # The columns are at equal steps along a line 0.4 m in from the curved edge; one column is at the middle.
    assert for(e <- body, e["shape"] == "cylinder", do: Enum.take(e["at"], 2)) ==
             [[8.6, 4.6], [5.5181, 4.6], [2.6547, 3.7099], [1.4, 1.0], [4.0, -14.6]]

    # The rails in the detail: upright bars each 12 cm along the edge of the round balconies, posts with crosses
    # along the square ones, none on side 3, and the rail of the terrace round the curved porch.
    [detail] = hd(d["nodes"])["skill"]["sculpt"]["details"]

    assert Enum.frequencies_by(detail["edits"], &hd(&1["size"]["radii"])) == %{
             0.012 => 154,
             0.022 => 10,
             0.02 => 24,
             0.014 => 44,
             0.016 => 11
           }

    # (A bar goes round the edge of the balcony, 6 cm in from it, and back to the wall.)
    bar = Enum.find(detail["edits"], &(hd(&1["size"]["radii"]) == 0.022))
    assert hd(bar["size"]["points"]) == [17.94, +0.0, 4.18] and length(bar["size"]["points"]) == 18
    # The terrace on the porch: two bars along its curved edge (the two quarters meet at the middle), and 11 posts.
    assert Enum.count(detail["edits"], &(hd(&1["size"]["radii"]) == 0.022 and length(&1["size"]["points"]) == 19)) == 2

    for {request, path, text} <- [
          {%{"porches" => [%{"deep" => 3, "round" => [4, 0]}]}, "porches.0.round",
           "the round of a porch is [left, right], each from 0 to 3.0 m, the two 6.0 m at the most"},
          {%{"porches" => [%{"wide" => 4, "deep" => 3, "round" => [3, 2]}]}, "porches.0.round",
           "the round of a porch is [left, right], each from 0 to 3.0 m, the two 4.0 m at the most"},
          {%{"porches" => [%{"round" => 1}]}, "porches.0.round", "the round of a porch is [left, right]"},
          {%{"porches" => [%{"fascia" => 4}]}, "porches.0.fascia", "the value of fascia is a number from 0 to 3"},
          {%{"fronts" => [%{"balcony" => 0.3}]}, "fronts.0.balcony", "a balcony is 0.5 m deep at the least"},
          {%{"fronts" => [%{"balcony" => 5}]}, "fronts.0.balcony", "the value of balcony is a number from 0 to 4"},
          {%{"fronts" => [%{"round" => [1, 1]}]}, "fronts.0.round", "the round ends are for a front with a balcony"},
          {%{"fronts" => [%{"balcony" => 1, "round" => [2, 0]}]}, "fronts.0.round",
           "the round of the balconies of a front is [left, right], each from 0 to 1.0 m"}
        ] do
      error = assert_raise ArgumentError, fn -> Building.spec(request) end
      assert String.starts_with?(error.message, "#{path}: #{text}"), error.message
    end
  end

  test "a word that is not possible is an error with its message" do
    wrong = [
      {[], "the request of a building is a map"},
      {%{"storys" => 3}, ~s(a building has no key "storys")},
      {%{"name" => "Rex Hotel"}, "the name of a building"},
      {%{"sources" => "a photo"}, "the sources of a building are lines of text"},
      {%{"plan" => [[0, 0], [1, 1]]}, "from 3 to 64 corners"},
      {%{
         "plan" =>
           [[0, 0], [0, -8], [10, -8], [10, 0]]
           |> Enum.reverse()
           |> Enum.reverse()
           |> Enum.map(fn [x, y] -> [x, -y] end)
       }, "counterclockwise"},
      {%{"plan" => [[10, 0], [0, 0], [0, 0], [0, -8], [10, -8]]}, "at the same place"},
      {%{"size" => [2, 10]}, "the size of a building is [long, deep]"},
      {%{"storeys" => 13}, "from 1 to 12 storeys"},
      {%{"ground" => 1}, "the value of ground is a number from 2.2 to 8"},
      {%{"colors" => []}, "the colors of a building are a map"},
      {%{"colors" => %{"door" => "#ffffff"}}, ~s(a map of colors has no key "door")},
      {%{"colors" => %{"wall" => "white"}}, "the color wall is as #a1b2c3"},
      {%{"more" => %{"than" => %{}}}, "the key more is a map of lists of edits"},
      {%{"more" => %{"cua" => []}}, ~s(a map of more edits has no key "cua")},
      {%{"roof" => "tiles"}, "the roof of a building is a map"},
      {%{"roof" => %{"kind" => "dome"}}, "the roof of a building is flat or tiles"},
      {%{"roof" => %{"high" => 2}}, ~s(a flat roof has no key "high")},
      {%{"roof" => %{"kind" => "tiles", "parapet" => 1}}, ~s(a roof of tiles has no key "parapet")},
      {%{"roof" => %{"kind" => "tiles"}, "plan" => [[10, 0], [0, 0], [0, -8], [5, -8], [5, -4], [10, -4]]},
       "a plan of four square corners"},
      {%{"roof" => %{"kind" => "tiles"}, "plan" => [[10, 0], [0, 0], [2, -8], [12, -8]]},
       "a plan of four square corners"},
      {%{"roof" => %{"kind" => "tiles", "gables" => [1]}}, "a gable of this roof is at a short side: 2 or 4"},
      {%{"cornice" => 1}, "the cornice of a building is a map"},
      {%{"cornice" => %{"high" => 0.2}}, "a cornice is 0.4 m high at the least"},
      {%{"fronts" => %{}}, "the fronts of a building are a list of maps"},
      {%{"fronts" => [%{"side" => 5}]}, "the side of a front is a number from 1 to 4"},
      {%{"fronts" => [%{"stile" => "glass"}]}, ~s(a front has no key "stile")},
      {%{"fronts" => [%{"style" => "arches"}]}, "the style of a front is one of plain, windows, loggias, glass"},
      {%{"storeys" => 1, "fronts" => [%{"style" => "loggias"}]}, "2 storeys or more"},
      {%{"fronts" => [%{"from" => 13}]}, "the value of from is a number from 0 to 12"},
      {%{"fronts" => [%{"from" => 6, "to" => 7}]}, "1.5 m long at the least"},
      {%{"fronts" => [%{"bays" => 20}]}, "each 1.5 m wide at the least"},
      {%{"fronts" => [%{"ground" => "arcade"}]}, "the ground storey of a front is one of piers, windows, blank"},
      {%{"fronts" => [%{"rail" => "glass"}]}, "the rail of a front is one of cross, bars, none"},
      {%{"fronts" => [%{"window" => [1.2]}]}, "a window is [wide, high]"},
      {%{"fronts" => [%{"places" => [20]}]}, "the places of the windows of a front"},
      {%{"fronts" => [%{"paint" => "blue"}]}, "the color paint is as #a1b2c3"},
      {%{"fronts" => [%{"ledges" => 1}]}, "true or false"},
      {%{"fronts" => [%{"bars" => 9}]}, "from 0 to 8 bars"},
      {%{"porches" => [%{"columns" => -1}]}, "from 0 to 12 columns"},
      {%{"porches" => [%{"steps" => 7}]}, "from 0 to 6 steps"},
      {%{"porches" => [%{"door" => [0.2, 2]}]}, "the door of a porch is [wide, high], or nil"},
      {%{"porches" => [%{"board" => "blue"}]}, "the color board is as #a1b2c3"},
      {%{"porches" => [%{"terrace" => 1}]}, "the key terrace of a porch is true or false"},
      {%{"porches" => [%{"at" => 1}]}, "the value of at is a number from 3.0 to 9.0"},
      {%{"letters" => [%{"text" => "Rex"}]}, "from 1 to 40 letters from A to Z"},
      {%{"letters" => [%{"text" => "  "}]}, "from 1 to 40 letters from A to Z"},
      {%{"letters" => [%{"side" => 0, "text" => "REX"}]}, "the side of a line of letters is a number from 1 to 4"}
    ]

    for {request, text} <- wrong do
      error = assert_raise ArgumentError, fn -> Building.spec(request) end
      assert error.message =~ text, "#{inspect(request)}: #{error.message}"
    end

    # An error starts with the path of the value in the request, when the rule knows it.
    paths = [
      {%{"name" => 1}, "name: the name of a building"},
      {%{"storeys" => 13}, "storeys: a building has"},
      {%{"plan" => [[0, 0], [1, 1]]}, "plan: the plan of a building"},
      {%{"size" => [2, 10]}, "size: the size of a building"},
      {%{"colors" => %{"wall" => "white"}}, "colors.wall: the color wall"},
      {%{"colors" => %{"door" => "#ffffff"}}, "colors: a map of colors has no key"},
      {%{"roof" => %{"kind" => "dome"}}, "roof.kind: the roof"},
      {%{"roof" => "tiles"}, "roof: the roof of a building is a map"},
      {%{"cornice" => %{"out" => 2}}, "cornice.out: the value of out"},
      {%{"more" => %{"cua" => []}}, "more: a map of more edits"},
      {%{"fronts" => [%{}, %{"side" => 2, "bars" => 9}]}, "fronts.1.bars: a window has"},
      {%{"fronts" => [%{"stile" => "glass"}]}, "fronts.0: a front has no key"},
      {%{"porches" => [%{"board" => "blue"}]}, "porches.0.board: the color board"},
      {%{"letters" => [%{"text" => "REX", "high" => 9}]}, "letters.0.high: the value of high"}
    ]

    for {request, text} <- paths do
      error = assert_raise ArgumentError, fn -> Building.spec(request) end
      assert String.starts_with?(error.message, text), "#{inspect(request)}: #{error.message}"
    end
  end
end
