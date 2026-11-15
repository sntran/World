defmodule World.MiniTest do
  # A very small model for a view from far (plan 0019, step 10; for Humans Must Die).
  use ExUnit.Case, async: true

  alias World.{Mini, Orders}

  defp sculpt(request), do: hd(Mini.drawing(request)["nodes"])["skill"]["sculpt"]

  test "each kind gives a drawing of one part with the flat look, of a few shapes and large cells" do
    assert length(Mini.kinds()) == 26 and "carrier" in Mini.kinds() and "ambulance" in Mini.kinds()

    for kind <- Mini.kinds() do
      d = Mini.drawing(%{"kind" => kind})
      assert {:ok, _} = World.Drawing.check(d, "d"), kind
      assert JSON.decode!(JSON.encode!(d)) == d
      assert d["name"] == kind and d["kind"] == "item" and d["extras"]["mini"]["kind"] == kind
      assert [%{"name" => name, "skill" => %{"sculpt" => s}}] = d["nodes"]
      assert name == kind <> "_than" and s["look"] == "flat" and not Map.has_key?(s, "bake")
      assert length(s["edits"]) <= 12 and Enum.all?(s["edits"], &(&1["material"] == "paint" and is_binary(&1["color"])))
      assert s["budget"] == %{"near" => 900, "mid" => 450, "far" => 220}

      assert s["cells"]["near"] < s["cells"]["mid"] and s["cells"]["mid"] < s["cells"]["far"] and
               s["cells"]["far"] <= 10
    end
  end

  test "a request with no word is a house; the scale, the color and the name of a request" do
    r = Mini.request()

    assert Mini.request(r) == r and
             r == %{"kind" => "house", "name" => "house", "sources" => [], "scale" => 1.0, "color" => nil}

    assert Mini.drawing() == Mini.drawing(%{})

    assert %{"shape" => "box", "size" => [4, 5, 1.8], "at" => [0, 0, 1.8], "color" => "#e6dcc0"} =
             hd(sculpt(%{})["edits"])

    # Each size and each place of an edit is times the scale: a box, an outline, and the points of a tube.
    small =
      sculpt(%{"kind" => "house", "scale" => 0.5, "color" => "#112233", "name" => "nha", "sources" => ["A house."]})

    assert %{"size" => [2.0, 2.5, 0.9], "at" => [+0.0, +0.0, 0.9], "color" => "#112233"} = hd(small["edits"])

    assert %{"size" => %{"outline" => [[-2.4, 1.75], [2.4, 1.75], [+0.0, 3.3]], "depth" => 5.5}} =
             Enum.at(small["edits"], 1)

    assert_in_delta small["cells"]["near"], 6 / 56, 1.0e-4
    palm = Enum.find(sculpt(%{"kind" => "tree_palm", "scale" => 2})["edits"], &(&1["shape"] == "tube"))

    assert palm["size"] == %{
             "points" => [[+0.0, +0.0, +0.0], [0.6, +0.0, 6.4], [0.8, +0.0, 12.8], [+0.0, +0.0, 18.8]],
             "radii" => [1.0, 0.84, 0.72, 0.64]
           }

    # A long ship has cells of 10 m at the most.
    assert sculpt(%{"kind" => "carrier", "scale" => 3})["cells"] == %{"near" => 10.0, "mid" => 10.0, "far" => 10.0}
  end

  test "the file flat of a small model: one mesh in some hundreds of triangles, with no image" do
    order = %{"blueprint" => "drawing", "options" => %{"drawing" => Mini.drawing(%{"kind" => "jet"})}}
    {:ok, glb} = Orders.build(order, "far", "flat")
    json = World.GLBHelper.json(glb)
    assert [%{"primitives" => [%{"attributes" => attributes, "indices" => indices}]}] = json["meshes"]
    assert Map.keys(attributes) == ~w(COLOR_0 NORMAL POSITION) and not Map.has_key?(json, "images")
    triangles = div(Enum.at(json["accessors"], indices)["count"], 3)
    assert triangles > 40 and triangles <= 220
    assert byte_size(:zlib.gzip(glb)) < 12_000
  end

  test "a word that is not possible is an error with its message" do
    wrong = [
      {[], "the request of a small model is a map"},
      {%{"size" => 3}, ~s(a small model has no key "size")},
      {%{"kind" => "dragon"}, "the kind of a small model is one of airliner, ambulance"},
      {%{"name" => "F-16"}, "the name of a small model"},
      {%{"sources" => "a page"}, "the sources of a small model are lines of text"},
      {%{"scale" => 0}, "the scale of a small model is a number from 0.1 to 10"},
      {%{"color" => "grey"}, "the color of a small model is as #a1b2c3"}
    ]

    for {request, text} <- wrong do
      error = assert_raise ArgumentError, fn -> Mini.request(request) end
      assert error.message =~ text
    end
  end
end
