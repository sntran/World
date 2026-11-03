defmodule World.BoatsTest do
  use ExUnit.Case, async: true

  alias World.Boats.Ghe
  alias World.Materials.Stock

  doctest Ghe
  doctest Stock, only: [vn: 2, vn_section: 2]

  @vn World.Standards.table("stock", "vn_lumber")["sizes"]

  test "a size of TCVN 1075 rounds up, and a size over the standard is refused" do
    assert Stock.vn(:thickness, 0.05) == 0.05
    assert Stock.vn(:thickness, 0.051) == 0.06
    assert_raise ArgumentError, "no thickness of TCVN 1075 is 330.0 mm or more", fn -> Stock.vn(:thickness, 0.33) end
  end

  test "the ghe of BV-92479-TS: its length and breadth at the waterline, and its members to QCVN 91 and TCVN 1075" do
    g = Ghe.ghe()
    assert g.kind == :boat and World.Places.family_of(g) == :boats

    # Lmax 20.7 m: L at the waterline is under the first band of the
    # rules (21 m), so the sizes are those of the first band.
    assert_in_delta g.extras["length"], 18.65, 0.01
    assert_in_delta g.extras["breadth"], 6.67, 0.01

    s = g.extras["scantlings"]
    # The keel of the rules is 220 by 308 mm; Bảng 1 of TCVN 1075 has no
    # 220 by 320, so it is 250 by 320.
    assert {s["keel_w"], s["keel_h"], s["stem"], s["keelson"]} == {250, 320, 250, 280}
    assert s["frame"] == [120, 160, 180]
    assert s["plank"] == 50 and s["deck"] == 60

    # The frame spacing is L + 20 cm or less.
    assert s["spacing"] <= (g.extras["length"] + 20) * 10

    # Each section is a pair of Bảng 1 of TCVN 1075 (a square member is
    # a thickness with its width of the same size).
    pairs = @vn["pairs"]

    for {k, v} <- s,
        k not in ~w(spacing floor_h keel_h frame plank ceiling deck),
        is_list(v) or k in ~w(stem keelson) do
      [a, b] =
        v
        |> List.wrap()
        |> then(fn
          [x] -> [x, x]
          l -> Enum.sort(l)
        end)

      assert b in pairs[Integer.to_string(a)], "#{k}: #{a} by #{b} mm"
    end

    assert s["keel_h"] in pairs[Integer.to_string(s["keel_w"])]
  end

  test "a longer boat takes a later band, and the wood group changes the size" do
    big = Ghe.scantlings(28.0, 7.2, 3.8, "II")
    assert {big.keel, big.stem, big.beam} == {24.5, 25.5, 16}
    assert Ghe.scantlings(28.0, 7.2, 3.8, "I").keel < big.keel
  end

  test "the ghe is a true model, and its mass is on its middle line" do
    g = Ghe.ghe()
    assert World.Check.model(g) == :ok

    %{mass: mass, center: {x, y, _}, unknown: unknown} = World.Mass.of(g)
    assert abs(x) < 0.01
    assert y > 0.35 * 20.7 and y < 0.55 * 20.7
    assert mass > 20_000 and unknown == []
  end

  test "a ghe of other sizes" do
    g = Ghe.ghe(24.8, 7.27, 2.46)
    assert g.extras["length"] > 21
    assert World.Check.model(g) == :ok
  end
end
