defmodule World.StandardsTest do
  use ExUnit.Case, async: true

  alias World.Materials.{Fasteners, Stock}
  alias World.Standards

  doctest Standards

  test "each table has its source, its unit, its fields and its sizes" do
    for {file, t} <- Standards.tables() do
      table = Standards.table(file, t)
      assert is_binary(table["source"]) and table["unit"] in ["mm", "in", "kg/m3", "cm", "cm2"]
      assert [_ | _] = table["fields"]
      assert map_size(table["sizes"]) > 2, "#{file}/#{t}"
    end

    # A table of one number for each name (the height of a nut), and the
    # names of a table in order.
    assert Standards.tuples({"fasteners", "nut"})["M8"] == 6.8
    assert hd(Standards.names({"stock", "pipe"})) == "1"

    refute Standards.__mix_recompile__?()
    assert_raise ArgumentError, "no table stock/nope", fn -> Standards.table("stock", "nope") end
    assert_raise ArgumentError, "no M7 in fasteners/hex_head", fn -> Standards.size({"fasteners", "hex_head"}, "M7") end
  end

  test "the head of an M8 bolt is 13 mm across the flats; a 2x4 is 38 by 89 mm" do
    assert Fasteners.table(:hex_head, "M8") == {0.013, 0.0053}
    {t, w} = Stock.table(:lumber, "2x4")
    assert {Float.round(t * 1000, 1), Float.round(w * 1000, 1)} == {38.1, 88.9}
    # A steel pipe of NPS 1, schedule 40: 33.4 mm outside, a wall of 3.38 mm.
    pipe = Standards.part({:pipe, "1", :sch40, 1.0})
    assert Float.round(pipe.params["od"] * 1000, 1) == 33.4 and Float.round(pipe.params["wall"] * 1000, 2) == 3.38
    assert Stock.pipe("2", :sch80, 0.5).params["wall"] > Stock.pipe("2", :sch40, 0.5).params["wall"]
    assert "4" in Stock.names(:pipe)
  end

  test "a part by its standard name" do
    assert Standards.part({:bolt, "M8x40"}).params == %{"thread" => "M8", "length" => 0.04}
    assert Standards.part({:cap_screw, "M6x20"}).kind == :cap_screw
    assert Standards.part({:nut, "M8"}).kind == :nut
    assert Standards.part({:washer, "M8"}).kind == :washer
    assert Standards.part({:bearing, "6204"}).kind == :bearing
    assert Standards.part({:lumber, "2x4", 2.4}).kind == :lumber
    assert Standards.part({:masonry, "brick_vn"}).kind == :brick
    assert_raise ArgumentError, fn -> Standards.part({:bolt, "M7x40"}) end
  end

  test "a wrong name of a standard stops the compile" do
    require Standards
    assert Standards.name!({"fasteners", "hex_head"}, "M8") == "M8"
    assert Standards.known?({"stock", "pipe"}, "1-1/2")
    refute Standards.known?({"nope", "nope"}, "M8")

    assert_raise CompileError, ~r/no M7 in the standard fasteners\/hex_head/, fn ->
      Code.eval_string(~s|require World.Standards; World.Standards.name!({"fasteners", "hex_head"}, "M7")|)
    end

    # A name that is not a literal is checked at run time (by size/2).
    name = Enum.random(["M8"])
    assert Standards.name!({"fasteners", "hex_head"}, name) == "M8"
  end
end
