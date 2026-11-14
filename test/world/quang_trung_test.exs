defmodule World.QuangTrungTest do
  # The street Quang Trung of Vũng Tàu as it is, from its survey (plan 0018).
  use ExUnit.Case, async: true

  alias World.Town.{QuangTrung, Survey}

  defp file(name), do: JSON.decode!(File.read!("priv/drawings/#{name}.json"))

  test "the plan of the block of the numbers 4 to 26: 12 lots in the order of the street, 70 m" do
    plan = QuangTrung.plan()
    assert %{"seed" => 26, "road" => 23.0, "sidewalk" => 5.5, "lots" => lots} = plan
    assert QuangTrung.plan() == plan
    assert Enum.map(lots, & &1["number"]) == ~w(4 6 8-10 8-10 12 14 16 18 20 22 24-26 24-26)
    # Each lot is a bar, a restaurant or a shop, 20 m deep; the reach of a balcony is that of a wide street.
    assert Enum.all?(
             lots,
             &(&1["use"] == "bar" and &1["ground"] == "open" and &1["depth"] == 20.0 and &1["road"] == 23.0)
           )

    last = List.last(lots)
    assert_in_delta last["at"] + last["width"] / 2, 69.8, 1.0e-3
    # The survey gives the types; the corner house has three storeys and is white.
    rows = Survey.rows("quang_trung", "QT-T02", "QT-T11")
    assert Enum.map(lots, & &1["type"]) == Enum.map(Survey.lots(rows), & &1["type"])
    assert %{"type" => "pho3", "wall" => "#f2f0ea", "family" => "steel", "right" => "free"} = last
    assert hd(lots)["left"] == "free"
    # The seed makes the family of each other lot: an old house or a house of the years of steel.
    assert lots |> Enum.map(& &1["family"]) |> Enum.uniq() |> Enum.sort() == ~w(old steel)
  end

  test "the three drawings of the block are the models of the catalog, four lots each" do
    drawings = QuangTrung.drawings()
    assert Enum.map(drawings, &elem(&1, 0)) == ~w(quang_trung_4_10 quang_trung_12_18 quang_trung_20_26)

    for {{name, drawing}, numbers} <- Enum.zip(drawings, [~w(4 6 8-10 8-10), ~w(12 14 16 18), ~w(20 22 24-26 24-26)]) do
      assert file(name) == drawing and name in World.Drawing.names()
      assert {:ok, _} = World.Drawing.check(drawing, "d")
      assert Enum.map(drawing["extras"]["street"]["lots"], & &1["number"]) == numbers
      # Four houses of three parts, and the ground with a parasol in front of each bar.
      assert length(drawing["nodes"]) == 13
      [things] = List.last(drawing["nodes"])["skill"]["sculpt"]["details"]
      assert Enum.count(things["edits"], &(&1["shape"] == "cone")) == 4
      # The sources say what is from the survey and what is a guess.
      assert Enum.any?(drawing["sources"], &(&1 =~ "OpenStreetMap")) and
               Enum.any?(drawing["sources"], &(&1 =~ "A guess"))
    end
  end

  test "the office of the port at number 2: its footprint, its storeys and its corner tower" do
    d = file("cang_vu_vung_tau")
    assert {:ok, _} = World.Drawing.check(d, "d")
    assert d["kind"] == "house" and "cang_vu_vung_tau" in World.Drawing.names()
    assert [%{"name" => "cang_vu_vung_tau_than"} = body, %{"name" => "cang_vu_vung_tau_mai"} = roof] = d["nodes"]
    [mass, hollow | rest] = body["skill"]["sculpt"]["edits"]
    # The mass is the footprint of OpenStreetMap, up to the top of the parapet: a ground storey of 4.4 m and
    # four storeys of 3.2 m, with a parapet of 1 m.
    assert %{"shape" => "extrude", "size" => %{"outline" => plan, "depth" => 18.2}, "at" => [0, 0, 9.1]} = mass
    assert length(plan) == 9 and Enum.take(plan, 2) == [[0, 0], [21.3, 0]]
    {xs, ys} = {Enum.map(plan, &hd/1), Enum.map(plan, &List.last/1)}
    # 21.3 m on Quang Trung (the front wall at y = 0), 29.2 m and 27.4 m over all.
    assert Enum.max(ys) == 0
    assert_in_delta Enum.max(xs) - Enum.min(xs), 29.2, 0.05
    assert_in_delta -Enum.min(ys), 27.4, 0.05
    assert %{"mode" => "subtract", "shape" => "extrude"} = hollow
    # The corner tower is one storey higher: 21.2 m.
    towers = for %{"shape" => "extrude", "size" => %{"depth" => 21.2}} = e <- rest, do: e
    assert [%{"at" => [0, 0, 10.6]}] = towers
    # Glass in hollows: the windows of the four upper storeys of the three fronts, and the loggias.
    glass = Enum.filter(rest, &(&1["color"] == "#4f6f86"))
    assert length(glass) > 80
    # The roof: the head of the stair, the board with four letters, and two masts in a detail of the near level.
    edits = roof["skill"]["sculpt"]["edits"]
    assert Enum.count(edits, &(&1["shape"] in ["tube", "ring"] and &1["color"] == "#5a4a32")) == 5
    assert [%{"levels" => ["near"], "edits" => masts}] = roof["skill"]["sculpt"]["details"]
    assert Enum.count(masts, &(&1["shape"] == "tube" and hd(&1["size"]["radii"]) == 0.09)) == 2
    # Each source says what it is: the footprint, the photos, and what is a guess.
    assert [osm, photos, guess] = d["sources"]
    assert osm =~ "OpenStreetMap" and photos =~ "Wikimedia Commons" and guess =~ "A guess"
  end

  test "the south wing of the Grand Hotel: a block of 39.7 m with 26 loggias between pilasters" do
    d = file("khach_san_grand_canh_nam")
    assert {:ok, _} = World.Drawing.check(d, "d")
    assert Enum.map(d["nodes"], & &1["name"]) == for(part <- ~w(than mai vuon), do: "khach_san_grand_canh_nam_#{part}")
    [body, roof, garden] = Enum.map(d["nodes"], & &1["skill"]["sculpt"])
    # The mass is the footprint of OpenStreetMap up to the cornice: 39.7 m on Quang Trung, 20.3 m deep.
    assert %{"shape" => "box", "size" => [19.85, 10.15, 5.4], "at" => [19.85, -10.15, 5.4]} = hd(body["edits"])

    # Nine bays on Quang Trung and four on Nguyễn Trãi, each with a loggia at two storeys and an opening at the ground.
    hollows = Enum.filter(body["edits"], &(&1["mode"] == "subtract"))
    assert length(hollows) == (9 + 4) * 3
    assert Enum.count(hollows, &(Enum.at(&1["size"], 1) == 1.375)) == 26
    # The rails of iron are thin: a detail of the near level, 15 tubes for each loggia.
    assert [%{"levels" => ["near"], "edits" => rails}] = body["details"]
    assert length(rails) == 26 * 15 and Enum.all?(rails, &(&1["shape"] == "tube" and &1["color"] == "#2f4a3c"))
    # The roof is a low form with four slopes (a second outline crops the first), behind the cornice of 12 m.
    assert [%{"shape" => "extrude"}, %{"shape" => "extrude", "mode" => "crop"} | _] = roof["edits"]
    assert Enum.all?(roof["edits"], &(List.last(&1["at"]) >= 11.9))
    # The garden: the bed behind its low wall, 4 m from the front, and the stone with the name.
    assert Enum.any?(garden["edits"], &(&1["shape"] == "ellipsoid"))
    assert [osm, photo, guess] = d["sources"]
    assert osm =~ "OpenStreetMap" and photo =~ "Wikimedia Commons" and guess =~ "A guess"
  end
end
