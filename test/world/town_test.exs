defmodule World.TownTest do
  # A house and a street of Vũng Tàu from rules (plan 0016), and a real street from a survey (plan 0018).
  use ExUnit.Case, async: true

  alias World.Town.{House, Street, Survey}

  # (A house at the far level, when the other tests work too.)
  @moduletag timeout: 1_800_000

  defp sculpt(drawing, part), do: Enum.find(drawing["nodes"], &String.ends_with?(&1["name"], part))["skill"]["sculpt"]

  test "a request: each choice is made, the same request gives the same house, a value of the request stays" do
    r = House.request()
    assert %{"type" => "pho2_flat", "width" => 5.0, "depth" => 16.0, "road" => 13.0, "seed" => 1} = r
    assert r["family"] in House.families() and r["left"] == "shared" and r["roof"] == "terrace"
    assert House.request() == r and House.request(r) == r
    assert House.types() == ~w(cap4 pho2_flat pho2_tile pho3)

    # Each family has its door and its rail; the roof is by the type.
    assert %{"ground" => "folding_gate", "age" => 0.8} = House.request(%{"family" => "old"})
    assert %{"ground" => "roller_door", "rail" => "tubes", "awning" => false} = House.request(%{"family" => "steel"})
    assert %{"ground" => "glass_gate", "rail" => "glass", "sign" => nil} = House.request(%{"family" => "modern"})
    assert House.request(%{"type" => "cap4"})["roof"] == "steel"
    assert House.request(%{"type" => "pho2_tile"})["roof"] == "tiles"

    # The seeds give each choice of an old house, and each family.
    old = for seed <- 1..200, do: House.request(%{"family" => "old", "seed" => seed})
    assert old |> Enum.map(& &1["rail"]) |> Enum.uniq() |> Enum.sort() == ~w(bars wall)
    assert old |> Enum.map(& &1["wall"]) |> Enum.uniq() |> length() == 5

    for key <- ~w(awning vents flip),
        do: assert(old |> Enum.map(& &1[key]) |> Enum.uniq() |> Enum.sort() == [false, true])

    assert Enum.any?(old, &(&1["sign"] == nil)) and Enum.any?(old, &is_binary(&1["sign"]))

    assert for(seed <- 1..200, do: House.request(%{"seed" => seed})["family"]) |> Enum.uniq() |> Enum.sort() ==
             ~w(modern old steel)

    # A value of the request stays; a word that is not a type or a family is an error.
    assert %{"wall" => "#123456", "sign" => nil, "width" => 4.0} =
             House.request(%{"family" => "steel", "wall" => "#123456", "sign" => nil, "width" => 4.0})

    assert_raise ArgumentError, ~r/the type of a house/, fn -> House.request(%{"type" => "castle"}) end
    assert_raise ArgumentError, ~r/the family of a house/, fn -> House.request(%{"family" => "new"}) end
    assert_raise ArgumentError, ~r/is a map/, fn -> apply(House, :request, [[]]) end
    assert_raise ArgumentError, ~r/a whole number/, fn -> House.request(%{"seed" => "a"}) end
    assert_raise ArgumentError, ~r/from 3 m to 8 m/, fn -> House.request(%{"width" => 12}) end
    assert_raise ArgumentError, ~r/from 6 m to 30 m/, fn -> House.request(%{"depth" => "deep"}) end
    assert_raise ArgumentError, ~r/from 1 m to 100 m/, fn -> House.request(%{"road" => 0}) end
    # A whole number of meters is a number of meters.
    assert %{"width" => 4.0, "depth" => 12.0, "road" => 10.0} =
             House.request(%{"width" => 4, "depth" => 12, "road" => 10})
  end

  test "the sizes of the rules: the reach of a balcony by the width of the road, the storeys, the height" do
    assert Enum.map([4, 6, 10, 13, 15, 20], &House.reach/1) == [0.0, 0.5, 0.9, 1.2, 1.2, 1.4]
    assert Enum.map(House.types(), &House.storeys/1) == [1, 2, 2, 3]
    assert_in_delta House.top(%{"type" => "cap4"}), 3.9, 1.0e-9
    assert_in_delta House.top(%{"type" => "pho2_flat"}), 7.3, 1.0e-9
    assert_in_delta House.top(%{"type" => "pho3"}), 10.7, 1.0e-9
  end

  test "the drawing of each type and family is a true drawing in three parts, with the sizes of the rules" do
    for type <- House.types(), family <- House.families(), seed <- [1, 2] do
      d = House.drawing(%{"type" => type, "family" => family, "seed" => seed})
      assert {:ok, _} = World.Drawing.check(d, "d")
      assert d["kind"] == "house" and d["extras"]["house"]["type"] == type
      assert Enum.map(d["nodes"], & &1["name"]) == for(p <- ~w(mat_tien than mai), do: "#{d["name"]}_#{p}")
      roles = for n <- d["nodes"], do: n["skill"]["sculpt"]["edits"] |> Enum.map(& &1["material"]) |> Enum.uniq()
      assert roles == [["part_01"], ["part_02"], ["part_03"]]
      assert Enum.all?(d["sources"], &(byte_size(&1) <= 500))
    end

    # The most common house: 5 m wide, two storeys, a terrace.
    d = House.drawing(%{"family" => "steel", "seed" => 3, "sign" => "#1f4f9c"})
    [wall, gap | _] = sculpt(d, "mat_tien")["edits"]
    # The front wall with its parapet: 5 m wide, 8.3 m high.
    assert %{"shape" => "box", "size" => [2.5, 0.15, 4.15], "at" => [x, -0.15, 4.15]} = wall
    assert x == 0
    # The ground opening: 3.4 m by 2.85 m, between two piers of 0.8 m, from the floor at 0.3 m.
    assert %{"mode" => "subtract", "size" => [1.7, _, 1.425], "at" => [_, _, 1.725]} = gap
    # A narrow house has piers of 0.55 m.
    [_, narrow | _] = sculpt(House.drawing(%{"width" => 4.0}), "mat_tien")["edits"]
    assert %{"size" => [1.45, _, _]} = narrow
    # The slab of the balcony goes 1.2 m out on a road of 13 m; its underside is over 3.5 m.
    slab = Enum.find(sculpt(d, "mat_tien")["edits"], &match?(%{"size" => [2.5, 0.65, 0.06]}, &1))
    assert %{"at" => [_, 0.55, 3.84]} = slab
    # The thin parts are a detail at near: the rail of tubes.
    assert [%{"levels" => ["near"], "cells" => %{"near" => 0.012}, "edits" => rail}] = sculpt(d, "mat_tien")["details"]
    assert Enum.any?(rail, &(&1["shape"] == "capsule")) and Enum.all?(rail, &(&1["material"] == "part_01"))
    # The roof: the head of the stair, and a tank of 0.96 m on it.
    assert Enum.any?(sculpt(d, "mai")["edits"], &match?(%{"shape" => "cylinder", "size" => [0.48, 0.6]}, &1))
    # The older the paint, the more dirt.
    assert sculpt(House.drawing(%{"family" => "old"}), "than")["dirt"] >
             sculpt(House.drawing(%{"family" => "modern"}), "than")["dirt"]
  end

  test "the choices of a front: each rail, the awning, the blocks for the air, the sign, a road with no balcony" do
    old = %{"family" => "old", "seed" => 5}
    bars = House.drawing(Map.merge(old, %{"rail" => "bars", "awning" => true, "vents" => true, "sign" => "#e0b400"}))
    [detail] = sculpt(bars, "mat_tien")["details"]
    # Bars each 12 cm across the front, and the cloth of the awning with its stripes.
    assert Enum.any?(detail["edits"], &match?(%{"size" => [0.008, 0.008, 0.45], "repeat" => %{"count" => 41}}, &1))
    assert Enum.any?(detail["edits"], &match?(%{"surface" => %{"kind" => "fabric"}}, &1))
    assert Enum.any?(sculpt(bars, "mat_tien")["edits"], &match?(%{"color" => "#e0b400", "at" => [_, 1.22, _]}, &1))
    assert Enum.any?(sculpt(bars, "mat_tien")["edits"], &match?(%{"raise" => -0.03, "repeat" => %{"count" => 14}}, &1))

    # A rail as a low wall is in the part itself: no detail when no part is thin.
    low = House.drawing(Map.merge(old, %{"rail" => "wall", "awning" => false, "vents" => false, "sign" => nil}))
    refute Map.has_key?(sculpt(low, "mat_tien"), "details")
    refute Enum.any?(sculpt(low, "mat_tien")["edits"], &(&1["raise"] == -0.03))
    assert {:ok, _} = World.Drawing.check(low, "d")

    # A house of one storey has its sign on the wall, and no box of an air conditioner.
    one = House.drawing(%{"type" => "cap4", "family" => "old", "sign" => "#b3261e", "seed" => 2})
    assert Enum.any?(sculpt(one, "mat_tien")["edits"], &match?(%{"color" => "#b3261e", "at" => [_, 0.04, _]}, &1))
    refute Enum.any?(sculpt(one, "mat_tien")["edits"], &(&1["shape"] == "round_box"))

    # A hẻm of 4 m: no balcony and no rail (the rule of the road).
    alley = House.drawing(%{"family" => "steel", "road" => 4.0, "sign" => nil})
    refute Map.has_key?(sculpt(alley, "mat_tien"), "details")
    refute Enum.any?(sculpt(alley, "mat_tien")["edits"], &match?(%{"size" => [2.5, _, 0.06]}, &1))
    walled = House.drawing(%{"family" => "old", "rail" => "wall", "road" => 4.0, "awning" => false})
    refute Map.has_key?(sculpt(walled, "mat_tien"), "details")

    # A free side has the paint of the house; a shared side is bare.
    bare = fn d -> Enum.count(sculpt(d, "than")["edits"], &(&1["color"] == "#aaa69c")) end
    assert bare.(House.drawing(%{})) == 2 and bare.(House.drawing(%{"left" => "free"})) == 1
  end

  test "a house at a place in a row: each edit moves, and an edit with a mirror is two edits" do
    r = %{"family" => "steel", "seed" => 3}
    {here, there} = {House.drawing(r), House.drawing(r, at: 7.5, name: "nha_7")}
    assert there["name"] == "nha_7" and hd(there["nodes"])["name"] == "nha_7_mat_tien"

    for part <- ~w(mat_tien than mai), {a, b} <- Enum.zip(sculpt(here, part)["edits"], sculpt(there, part)["edits"]) do
      refute Map.has_key?(a, "mirror")

      case a do
        %{"shape" => "tube", "size" => %{"points" => points}} ->
          assert b["size"]["points"] == for([x, y, z] <- points, do: [x + 7.5, y, z])

        %{"at" => [x, y, z]} ->
          assert_in_delta hd(b["at"]), x + 7.5, 1.0e-9
          assert tl(b["at"]) == [y, z]
      end
    end

    # The two piers, one at each side of the middle of the house.
    piers =
      for %{"mode" => "paint", "size" => [0.4, 0.2, _], "at" => [x, _, _]} <- sculpt(there, "mat_tien")["edits"], do: x

    assert piers == [7.5 + 2.1, 7.5 - 2.1]
    # The four legs of the tank turn round its middle.
    legs = Enum.find(sculpt(there, "mai")["edits"], &match?(%{"repeat" => %{"center" => _}}, &1))
    assert_in_delta hd(legs["repeat"]["center"]), 7.5 + 1.2, 1.0e-9
  end

  test "the two models of the catalog are the drawings of the rules: the most common house, and a row of five houses" do
    file = fn name -> "priv/drawings/#{name}.json" |> File.read!() |> JSON.decode!() end
    house = %{"type" => "pho2_flat", "family" => "steel", "seed" => 3, "sign" => "#1f4f9c"}
    assert file.("nha_pho_2_tang_vung_tau") == House.drawing(house, name: "nha_pho_2_tang_vung_tau")
    street = Street.plan(%{"seed" => 2})
    assert file.("day_pho_vung_tau") == Street.drawing(street, name: "day_pho_vung_tau")
    # The row has each type and each family.
    assert street["lots"] |> Enum.map(& &1["type"]) |> Enum.uniq() |> Enum.sort() == House.types()
    assert street["lots"] |> Enum.map(& &1["family"]) |> Enum.uniq() |> length() == 3
  end

  test "the most common house builds at the far level with its sizes" do
    d = House.drawing(%{"family" => "steel", "seed" => 3, "sign" => nil, "left" => "free", "right" => "free"})
    model = World.Detail.with(:far, fn -> World.Drawing.build(d) end)
    assert model.kind == :house and length(model.nodes) == 3
    {{x0, y0, z0}, {x1, y1, z1}} = model |> World.Build.scene(level: :far) |> World.Scene.bounds()

    # 5 m wide (and the cap of its parapet), 16 m deep with its balcony and its step, the tank over the head of the stair.
    assert_in_delta x1 - x0, 5.06, 0.15
    assert_in_delta y0, -16.0, 0.2
    assert_in_delta y1, 1.25, 0.25
    assert_in_delta z0, 0.0, 0.1
    assert_in_delta z1, 7.3 + 2.7 + 1.8, 0.4
    tris = for {_, part, _} <- model.nodes, s <- part.shapes, reduce: 0, do: (n -> n + length(s.faces))
    assert tris <= 300 + 100 + 150

    # Each type meets the budget of each of its parts at the far level (its thin parts are whole there).
    for {type, family} <- [{"cap4", "old"}, {"pho2_tile", "steel"}, {"pho3", "old"}, {"pho2_flat", "modern"}] do
      model =
        World.Detail.with(:far, fn ->
          World.Drawing.build(House.drawing(%{"type" => type, "family" => family, "seed" => 9}))
        end)

      counts = for {_, part, _} <- model.nodes, do: part.shapes |> Enum.map(&length(&1.faces)) |> Enum.sum()
      for {count, budget} <- Enum.zip(counts, [300, 100, 150]), do: assert(count <= budget)
    end
  end

  test "the plan of a street: lots wall to wall, the same plan from the same seed, the shares of the request" do
    plan = Street.plan()
    assert %{"seed" => 1, "road" => 13.0, "lots" => lots} = plan
    assert length(lots) == 5 and Street.plan() == plan and Street.plan(%{"seed" => 2}) != plan
    # Each lot starts where the lot before it ends.
    ends = Enum.scan(lots, 0.0, &(&1["width"] + &2))
    for {lot, last} <- Enum.zip(lots, ends), do: assert_in_delta(lot["at"] + lot["width"] / 2, last, 1.0e-3)
    # The ends of the row are free; each other side is shared.
    assert hd(lots)["left"] == "free" and List.last(lots)["right"] == "free"
    assert Enum.all?(tl(lots), &(&1["left"] == "shared")) and Enum.all?(Enum.drop(lots, -1), &(&1["right"] == "shared"))
    # Each lot is the request of a house with each choice made.
    for lot <- lots, do: assert(House.request(Map.delete(lot, "at")) == Map.delete(lot, "at"))

    # Many streets: each type, each family and each width is there, and no house has the color of the house before it.
    many = for seed <- 1..60, lot <- Street.plan(%{"seed" => seed, "count" => 8})["lots"], do: lot
    assert many |> Enum.map(& &1["type"]) |> Enum.uniq() |> Enum.sort() == House.types()
    assert many |> Enum.map(& &1["family"]) |> Enum.uniq() |> Enum.sort() == Enum.sort(House.families())
    assert many |> Enum.map(& &1["width"]) |> Enum.uniq() |> Enum.sort() == [4.0, 4.5, 5.0, 5.5, 6.0]

    for seed <- 1..60,
        [a, b] <- Enum.chunk_every(Street.plan(%{"seed" => seed, "count" => 8})["lots"], 2, 1, :discard) do
      assert a["wall"] != b["wall"]
    end

    # The two-storey house with a terrace is the most common type.
    shares = Enum.frequencies_by(many, & &1["type"])
    assert shares["pho2_flat"] == shares |> Map.values() |> Enum.max()

    # The shares of a request, the length of a row, the depth and the road.
    own =
      Street.plan(%{
        "types" => [["cap4", 1]],
        "families" => [["modern", 1]],
        "widths" => [[4.0, 1]],
        "length" => 21.0,
        "depth" => 12.0,
        "road" => 6.0
      })

    assert length(own["lots"]) == 4

    assert Enum.all?(
             own["lots"],
             &match?(%{"type" => "cap4", "family" => "modern", "width" => 4.0, "depth" => 12.0, "road" => 6.0}, &1)
           )

    assert length(Street.plan(%{"length" => 2.0})["lots"]) == 1
    assert_raise ArgumentError, ~r/is a map/, fn -> apply(Street, :plan, [5]) end
    assert_raise ArgumentError, ~r/from 1 to 200 lots/, fn -> Street.plan(%{"count" => 0}) end
    assert_raise ArgumentError, ~r/from 1 to 200 lots/, fn -> Street.plan(%{"length" => "long", "count" => "many"}) end
  end

  test "the drawing of a street: each house at its place with its own parts, and the ground" do
    plan = Street.plan(%{"seed" => 4})
    d = Street.drawing(plan, name: "pho_thu")
    assert {:ok, _} = World.Drawing.check(d, "d")
    assert d["extras"]["street"] == plan and length(d["nodes"]) == 16
    # Each part has its own role: 16 images.
    roles = for n <- d["nodes"], do: n["skill"]["sculpt"]["edits"] |> Enum.map(& &1["material"]) |> Enum.uniq()
    assert roles == for(i <- 1..16, do: ["part_#{String.pad_leading("#{i}", 2, "0")}"])
    assert Map.keys(d["materials"]) |> Enum.sort() == List.flatten(roles)
    # The edits of the details have the role of their part.
    for n <- d["nodes"], detail <- n["skill"]["sculpt"]["details"] || [] do
      assert Enum.map(detail["edits"], & &1["material"]) |> Enum.uniq() ==
               n["skill"]["sculpt"]["edits"] |> Enum.map(& &1["material"]) |> Enum.uniq()
    end

    # The front wall of each house is at its lot: the row is about its middle.
    long = Enum.sum(for lot <- plan["lots"], do: lot["width"])
    walls = for n <- d["nodes"], String.ends_with?(n["name"], "_mat_tien"), do: hd(n["skill"]["sculpt"]["edits"])

    for {wall, lot} <- Enum.zip(walls, plan["lots"]) do
      assert_in_delta hd(wall["at"]), lot["at"] - long / 2, 1.0e-3
      assert_in_delta hd(wall["size"]), lot["width"] / 2, 1.0e-9
    end

    # The ground: a sidewalk of 3 m as long as the row, a lane, a pole at the wall between the first two houses.
    [walk, _, _, _, lane, pole | _] = List.last(d["nodes"])["skill"]["sculpt"]["edits"]
    assert %{"size" => [half, 1.5, 0.19], "at" => [_, 1.5, -0.19]} = walk
    assert_in_delta half, long / 2 + 0.5, 1.0e-3
    # Each part of the ground goes down to the same level (0.38 m under the sidewalk): the row stands on all of it.
    assert %{"size" => [_, _, 0.1], "at" => [_, _, -0.28]} = lane
    ground = List.last(List.last(d["nodes"])["skill"]["sculpt"]["edits"])
    assert %{"size" => [_, 8.25, 0.18], "at" => [_, -8.25, -0.2]} = ground
    assert_in_delta hd(pole["at"]), hd(plan["lots"])["width"] - long / 2, 1.0e-3
    # The front of a house in a row has an image of 1024 (a house alone: 2048).
    fronts = for n <- d["nodes"], String.ends_with?(n["name"], "_mat_tien"), do: n["skill"]["sculpt"]["bake"]
    assert Enum.uniq(fronts) == [%{"near" => 1024, "mid" => 512, "far" => 128}]
    assert sculpt(House.drawing(%{}), "mat_tien")["bake"] == %{"near" => 2048, "mid" => 512, "far" => 128}
    assert Street.drawing(plan)["name"] == "pho_4"
    # More than 5 houses are not one drawing: a drawing has 16 parts with an image.
    assert_raise ArgumentError, ~r/from 1 to 5 lots/, fn -> Street.drawing(Street.plan(%{"count" => 6})) end
  end

  test "a house with the use bar: an open front with a counter and a shelf of light, a sign, an awning" do
    assert House.uses() == ~w(home bar) and House.request()["use"] == "home"

    for family <- House.families(), seed <- 1..20 do
      r = House.request(%{"use" => "bar", "family" => family, "seed" => seed})
      assert %{"use" => "bar", "ground" => "open", "awning" => true} = r
      assert is_binary(r["sign"])
    end

    # A value of the request stays.
    assert %{"sign" => nil, "awning" => false} = House.request(%{"use" => "bar", "sign" => nil, "awning" => false})
    assert_raise ArgumentError, ~r/the use of a house/, fn -> House.request(%{"use" => "bank"}) end

    d = House.drawing(%{"use" => "bar", "family" => "steel", "seed" => 5})
    assert {:ok, _} = World.Drawing.check(d, "d")
    front = sculpt(d, "mat_tien")["edits"]
    # The counter of wood, the dark wall behind the room, and the shelf with its light.
    assert Enum.any?(front, &(&1["color"] == "#6b4a2c" and &1["surface"]["kind"] == "wood"))
    assert Enum.any?(front, &(&1["color"] == "#2a2622" and Enum.at(&1["size"], 1) == 0.09))
    assert Enum.any?(front, &(&1["glow"] == 0.6 and &1["mode"] == "paint"))
    # No door of a home is there.
    refute Enum.any?(front, &(&1["color"] in ["#b9bdc0", "#6f8078"]))
  end

  test "the survey of a real street gives the lots of a block" do
    assert Survey.names() == ["quang_trung"]
    survey = Survey.survey("quang_trung")
    assert %{"name" => "Quang Trung", "city" => "Vũng Tàu", "length_m" => 1136.3} = survey["street"]
    assert length(survey["rows"]) == 27 and map_size(survey["sources"]["photos"]) == 39
    # Each row says where its values come from, and each photo has its address and its license.
    for row <- survey["rows"], do: assert(is_map(row["marks"]) and is_list(row["sources"]) and is_binary(row["id"]))
    for {_, photo} <- survey["sources"]["photos"], do: assert(is_binary(photo["url"]) and is_binary(photo["licence"]))
    assert_raise ArgumentError, ~r/no survey/, fn -> Survey.survey("nowhere") end

    # The block of the numbers 4 to 26: 10 rows.
    rows = Survey.rows("quang_trung", "QT-T02", "QT-T11")
    assert Enum.map(rows, & &1["number"]) == ~w(4 6 8-10 12 14 16 18 20 22 24-26)
    assert_raise ArgumentError, ~r/no row/, fn -> Survey.rows("quang_trung", "QT-T02", "QT-X") end

    # A row wider than 8 m is one building on two lots of the same width.
    lots = Survey.lots(rows)
    assert length(lots) == 12

    assert [%{"number" => "8-10", "width" => 5.85} = a, %{"number" => "8-10", "same" => true} = b] =
             Enum.slice(lots, 2, 2)

    assert Map.delete(b, "same") == a and not Map.has_key?(a, "same")

    assert %{"type" => "pho2_flat", "use" => "bar", "width" => 5.8, "depth" => 20.0, "number" => "4", "name" => name} =
             hd(lots)

    assert name =~ "Vosa"
    assert %{"type" => "pho3", "family" => "steel", "wall" => "#f2f0ea", "same" => true} = List.last(lots)
    assert_in_delta Enum.sum(for lot <- lots, do: lot["width"]), 69.8, 1.0e-6
    # A row that is no house of the rules (the office at number 2).
    assert_raise ArgumentError, ~r/QT-T01 is not a house/, fn ->
      Survey.lots(Survey.rows("quang_trung", "QT-T01", "QT-T02"))
    end
  end

  test "the plan of a real street: the lots of a survey stay, and the seed makes the other choices" do
    lots = Survey.lots(Survey.rows("quang_trung", "QT-T02", "QT-T11"))

    request = %{
      "seed" => 26,
      "road" => 23.0,
      "sidewalk" => 5.5,
      "depth" => 12.0,
      "families" => [["old", 1], ["steel", 1]],
      "lots" => lots
    }

    plan = Street.plan(request)
    assert %{"sidewalk" => 5.5, "road" => 23.0} = plan
    assert Street.plan(request) == plan
    assert length(plan["lots"]) == 12

    # What the survey knows stays: the widths, the depth of each row (not of the request), the types, the use, the address.
    for {lot, known} <- Enum.zip(plan["lots"], lots) do
      assert Map.take(lot, ~w(type width depth use number name)) ==
               Map.take(known, ~w(type width depth use number name))

      assert lot["road"] == 23.0 and lot["family"] in ~w(old steel) and lot["ground"] == "open"
      refute Map.has_key?(lot, "same")
    end

    assert_in_delta List.last(plan["lots"])["at"], 69.8 - 5.85 / 2, 1.0e-3
    # One building on two lots: the same choices on the two.
    same = ~w(type family wall sign rail roof awning vents age)
    [a, b] = Enum.slice(plan["lots"], 2, 2)
    assert Map.take(a, same) == Map.take(b, same) and a["seed"] != b["seed"]
    [c, d] = Enum.take(plan["lots"], -2)
    assert Map.take(c, same) == Map.take(d, same) and c["wall"] == "#f2f0ea" and c["family"] == "steel"
    # A lot with the color of the lot before it keeps it; the first lot can have `same` (it has no lot before it).
    two = Street.plan(%{"lots" => [%{"wall" => "#101010", "same" => true}, %{"wall" => "#101010"}, %{}]})
    assert [%{"wall" => "#101010"}, %{"wall" => "#101010"}, %{"width" => _}] = two["lots"]
    assert Street.plan()["sidewalk"] == 3.0

    assert_raise ArgumentError, ~r/a list of maps/, fn -> Street.plan(%{"lots" => "many"}) end
    assert_raise ArgumentError, ~r/a list of maps/, fn -> Street.plan(%{"lots" => [1]}) end
    assert_raise ArgumentError, ~r/from 2 m to 10 m/, fn -> Street.plan(%{"sidewalk" => 30}) end
    assert_raise ArgumentError, ~r/from 2 m to 10 m/, fn -> Street.plan(%{"sidewalk" => "wide"}) end

    # A part of the row is a drawing about its own middle, with its sources.
    d = Street.drawing(plan, only: 5..8, name: "block", sources: ["A source of the block."])
    assert {:ok, _} = World.Drawing.check(d, "d")
    assert length(d["nodes"]) == 13 and List.last(d["sources"]) == "A source of the block."
    part = d["extras"]["street"]["lots"]
    assert Enum.map(part, & &1["number"]) == ~w(12 14 16 18)
    assert_in_delta hd(part)["at"], 2.9, 1.0e-9
    walls = for n <- d["nodes"], String.ends_with?(n["name"], "_mat_tien"), do: hd(n["skill"]["sculpt"]["edits"])
    assert_in_delta hd(hd(walls)["at"]), 2.9 - 4 * 5.8 / 2, 1.0e-3

    # The sidewalk of 5.5 m, and on it a parasol with a table in front of each bar (thin: in the details, at near and mid).
    ground = List.last(d["nodes"])["skill"]["sculpt"]
    assert %{"size" => [_, 2.75, _], "at" => [_, 2.75, _]} = hd(ground["edits"])
    assert [%{"levels" => ["near", "mid"], "edits" => things, "budget" => %{"near" => 6000}}] = ground["details"]
    assert length(things) == 16 and Enum.count(things, &(&1["shape"] == "cone")) == 4
    for cone <- Enum.filter(things, &(&1["shape"] == "cone")), do: assert(Enum.at(cone["at"], 1) + 1.3 < 5.5)
    # No parasol on a sidewalk of 3 m, and none in front of a home.
    narrow = Street.drawing(Street.plan(Map.put(request, "sidewalk", 3.0)), only: 1..2)
    refute Map.has_key?(List.last(narrow["nodes"])["skill"]["sculpt"], "details")
    homes = Street.drawing(Street.plan(%{"sidewalk" => 6.0, "count" => 2}))
    refute Map.has_key?(List.last(homes["nodes"])["skill"]["sculpt"], "details")
    assert_raise ArgumentError, ~r/from 1 to 5 lots/, fn -> Street.drawing(plan) end
  end
end
