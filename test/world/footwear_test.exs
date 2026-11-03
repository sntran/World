defmodule World.FootwearTest do
  use ExUnit.Case, async: true

  alias World.{Footwear, Part}
  alias World.People.Human

  doctest Footwear

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

  test "a sandal of webbing: a true model, its sole the length of the last, each part with a mass" do
    s = Footwear.sandal()
    assert s.kind == :sandal and World.Places.family_of(s) == :footwear
    assert World.Check.model(s) == :ok

    %{mass: mass, unknown: []} = World.Mass.of(s)
    assert mass > 0.1 and mass < 0.4

    # The last is the foot and 2 Paris points (13.3 mm).
    %{"foot" => foot, "last" => last, "eu_size" => size} = s.extras
    assert_in_delta last - foot, 2 * 2 / 300, 1.0e-3
    assert size == Footwear.eu_size(foot)

    {_, outsole, _} = List.keyfind(s.nodes, "outsole_sandal", 0)
    {{_, y0, _}, {_, y1, _}} = Part.bounds(outsole)
    assert_in_delta y1 - y0, last, 1.0e-3

    names = Enum.map(s.nodes, &elem(&1, 0))
    assert ~w(ring_sandal patch_sandal fold_sandal glide_sandal) -- names == []
  end

  test "a sandal of leather: straps of leather, closed with a pin buckle" do
    s = Footwear.sandal(leather: true)
    assert World.Check.model(s) == :ok
    {_, strap, _} = List.keyfind(s.nodes, "strap_toe_sandal", 0)
    assert hd(strap.shapes).matter == :leather and strap.params["thickness"] == 0.003
    names = Enum.map(s.nodes, &elem(&1, 0))
    assert "buckle_sandal" in names and "ring_sandal" not in names
  end
end
