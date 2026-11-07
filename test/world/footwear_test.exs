defmodule World.FootwearTest do
  use ExUnit.Case, async: true

  alias World.{Footwear, Part}
  alias World.Footwear.{Last, Sole, Upper}
  alias World.People.Human

  doctest Last

  setup_all do
    {:ok, last: Last.new()}
  end

  test "the footprint of a foot: its rows from the heel to the toes, on its side; a woman of the defaults has a shorter foot" do
    %{length: l, rows: rows} = Human.footprint([], "r")
    assert l > 0.2 and l < 0.3
    ys = Enum.map(rows, &elem(&1, 0))
    assert ys == Enum.sort(ys)
    assert Enum.all?(rows, fn {_, x0, x1, top} -> x0 <= x1 and x0 > 0 and top > 0 end)

    %{rows: left} = Human.footprint()
    assert Enum.all?(left, fn {_, _, x1, _} -> x1 < 0 end)
    assert Human.footprint(gender: 0.0).length < l
  end

  test "the last: the foot and 2 Paris points; a row at a part of the foot; the gap of the toes inside the foot", %{
    last: last
  } do
    assert_in_delta last.length - last.foot, 2 * Last.paris(), 1.0e-9
    {y, x0, x1, top} = Last.at(last, 0.5)
    assert_in_delta y, Last.y(last, 0.5), 0.003
    assert x0 < 0 and x1 > 0 and top > 0
    assert Enum.all?(Last.back(last, 0.12), fn {ry, _, _, _} -> ry <= Last.y(last, 0.12) end)

    {gx, gy} = Last.toe_gap(last)
    {_, a, b, _} = Last.at(last, 0.88)
    assert gx > a and gx < (a + b) / 2 and gy > Last.y(last, 0.8)
    assert Footwear.eu_size(last.foot) == Last.eu_size(last.foot)
  end

  test "a stack of soles: each layer on the one under it, a rim, and a tip turned up", %{last: last} do
    layers = [
      [name: "a", heel: 0.004, role: :gray, matter: :rubber_sole],
      [name: "b", heel: 0.02, ball: 0.01, role: :dark, matter: :eva, rim: 0.005, source: "a test"]
    ]

    %{parts: [a, b], top: top} = Sole.stack(last, layers)
    assert_in_delta top.(0.0), 0.024, 1.0e-9
    assert_in_delta top.(last.length), 0.014, 1.0e-9
    assert length(b.shapes) == 2 and length(a.shapes) == 1
    assert b.params["ball"] == 0.01 and a.params["ball"] == 0.004
    assert_in_delta Sole.thickness(Enum.at(layers, 1), last, 0.65 * last.length), 0.01, 1.0e-9

    %{top: up} = Sole.stack(last, layers, rise: 0.008)
    assert_in_delta up.(last.length) - top.(last.length), 0.008, 1.0e-9
    assert up.(0.5 * last.length) == top.(0.5 * last.length)
    assert length(Sole.stations(last, 0.006)) > 10
  end

  test "the paths of the straps on the foot", %{last: last} do
    top = fn _ -> 0.02 end

    # Over the foot: its top over the foot; with a closure, its outside
    # end straight down; with `high`, its top at most there.
    plain = Upper.over(last, 0.7, top)
    {_, _, _, foot} = Last.at(last, 0.7)
    assert_in_delta plain |> Enum.map(&elem(&1, 2)) |> Enum.max(), foot + 0.004, 1.0e-6
    [{x1, _, _}, {x2, _, z2}] = Enum.take(Upper.over(last, 0.38, top, closure: true, high: 0.06), -2)
    assert x1 == x2 and and_in(z2, 0.032)
    assert Upper.over(last, 0.38, top, high: 0.06) |> Enum.map(&elem(&1, 2)) |> Enum.max() <= 0.064 + 1.0e-9

    # Round the heel: from one point to the other, behind the foot.
    heel = Upper.heel(last, top, {{0.05, 0.08, 0.05}, {-0.05, 0.08, 0.05}}, 0.04)
    assert hd(heel) == {0.05, 0.08, 0.05} and List.last(heel) == {-0.05, 0.08, 0.05}
    assert Enum.any?(heel, fn {_, y, _} -> y == 0.0 end)

    # The thong: a post at the gap of the toes, a strap to each side.
    %{post: [{px, py, _}, _], straps: [inside, outside]} = Upper.thong(last, top)
    assert {px, py} == Last.toe_gap(last)
    {{ix, _, _}, {ox, _, _}} = {List.last(inside), List.last(outside)}
    assert ix < px and ox > px

    # Two straps that cross, and a band with its ends down the sides.
    [a, b] = Upper.cross(last, top, 0.01)
    assert elem(hd(a), 0) < 0 and elem(hd(b), 0) > 0
    band = Upper.band(last, 0.68, top, {0.008, 0.006})
    assert elem(hd(band), 2) == 0.014 and elem(List.last(band), 2) == 0.014
  end

  test "nails and plugs", %{last: last} do
    band = Upper.band(last, 0.68, fn _ -> 0.02 end, {0.008, 0.006})
    assert length(Upper.nails(band, {0.05, 0.002}, 3)) == 12

    [plug] = Upper.plugs([{0.0, 0.1, 0.005}], 0.01, {:black, :rubber})
    {{_, _, low}, {_, _, high}} = World.Mesh.bounds(plug)
    assert_in_delta low, 0.001, 1.0e-9
    assert_in_delta high, 0.005, 1.0e-9
  end

  test "each model of the shoe shop is a true pair, with a mass for each part (the mark between the shoes has none: 0)" do
    for {name, fun} <- Footwear.models() do
      s = fun.()
      assert World.Plan.trade(s) == :shoemaker, name
      assert World.Check.model(s) == :ok, name
      %{mass: mass, unknown: unknown} = World.Mass.of(s)
      assert unknown == [] and s.extras["pair"]
      assert mass > 0.1 and mass < 0.8, "#{name}: #{mass} kg"
      assert_in_delta s.extras["last"] - s.extras["foot"], 2 * Last.paris(), 1.0e-3
    end
  end

  test "a pair: the left shoe is the mirror of the right one, beside it" do
    shoe = Footwear.thong()
    pair = Footwear.pair(shoe)
    assert Enum.map(pair.nodes, &elem(&1, 0)) == ["pair_dep_tong_vn", "right", "left"]
    xs = fn node -> pair |> World.Assembly.node_frame(node) |> Map.fetch!(:at) |> elem(0) end
    assert xs.("right") > 0 and xs.("left") < 0
    assert_in_delta World.Mass.of(pair).mass, 2 * World.Mass.of(shoe).mass, 1.0e-9
  end

  test "the sport sandal: its closures, the heel strap from the ankle strap, and the ankle strap at the ankle" do
    s = Footwear.sandal()
    names = Enum.map(s.nodes, &elem(&1, 0))

    assert ~w(ring_toe_sandal patch_toe_sandal fold_toe_sandal ring_ankle_sandal patch_ankle_sandal fold_ankle_sandal glide_sandal) --
             names == []

    {_, _, heel} = List.keyfind(s.nodes, "strap_heel_sandal", 0)
    assert heel.to == "strap_ankle_sandal"
    {_, ankle, _} = List.keyfind(s.nodes, "strap_ankle_sandal", 0)
    {{_, y0, _}, {_, _, z1}} = Part.bounds(ankle)
    assert y0 < 0.5 * s.extras["foot"] and z1 <= 0.085 + 0.004 + 0.003

    l = Footwear.sandal(leather: true)
    {_, strap, _} = List.keyfind(l.nodes, "strap_toe_sandal", 0)
    assert hd(strap.shapes).matter == :leather
    names = Enum.map(l.nodes, &elem(&1, 0))
    assert "buckle_toe_sandal" in names and "buckle_ankle_sandal" in names
    refute "ring_ankle_sandal" in names or "glide_sandal" in names
  end

  test "a board with round ends and two teeth under it: the geta" do
    g = Footwear.geta()
    {_, teeth, _} = List.keyfind(g.nodes, "teeth_geta", 0)
    assert teeth.params["count"] == 2 and length(teeth.shapes) == 2
    {_, board, _} = List.keyfind(g.nodes, "board_geta", 0)
    {{_, _, z0}, _} = Part.bounds(board)
    assert_in_delta z0, 0.045, 1.0e-9
    assert hd(board.shapes).matter == :paulownia
    {_, hanao, _} = List.keyfind(g.nodes, "hanao_geta", 0)
    assert Enum.all?(hanao.shapes, &(&1.matter == :cotton))
  end

  test "the dép tổ ong: a lattice not over its limit; the slide: one band into the sole", %{last: last} do
    top = fn _ -> 0.02 end
    high = Upper.lattice(last, {0.45, 0.86}, top, 4, 0.055)
    assert length(high) > 8
    assert high |> List.flatten() |> Enum.map(&elem(&1, 2)) |> Enum.max() <= 0.059 + 1.0e-9
    assert Upper.lattice(last, {0.45, 0.86}, top, 2) |> List.flatten() |> Enum.map(&elem(&1, 2)) |> Enum.max() > 0.059

    h = Footwear.honeycomb()
    {_, vamp, _} = List.keyfind(h.nodes, "vamp_dep_to_ong", 0)
    assert length(vamp.shapes) > 8 and hd(vamp.shapes).matter == :eva

    s = Footwear.slide()
    {_, band, _} = List.keyfind(s.nodes, "band_dep_quai_ngang", 0)
    {{_, _, z0}, _} = Part.bounds(band)
    assert z0 < 0.02
  end

  test "the clogs: the high heel is higher, the strap is nailed, the sole is vông wood" do
    flat = Footwear.clog()
    high = Footwear.clog(heel: :high)
    assert flat.kind == :clog

    height = fn c, n ->
      {_, sole, _} = List.keyfind(c.nodes, n, 0)
      {_, {_, _, top}} = Part.bounds(sole)
      top
    end

    assert height.(high, "sole_guoc_cao_vn") > height.(flat, "sole_guoc_moc_vn") + 0.04

    {_, sole, _} = List.keyfind(flat.nodes, "sole_guoc_moc_vn", 0)
    assert hd(sole.shapes).matter == :vong
    {_, band, _} = List.keyfind(flat.nodes, "band_guoc_moc_vn", 0)
    assert Enum.count(band.shapes, &(&1.matter == :steel)) == 12
  end

  defp and_in(z, expected), do: abs(z - expected) < 1.0e-9
end
