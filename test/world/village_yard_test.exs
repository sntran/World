defmodule World.VillageYardTest do
  # The things of the yard of a village of old Việt Nam (plan 0019, 7.1; for Tre).
  use ExUnit.Case, async: true

  alias World.Village.Yard

  defp edits(request), do: hd(Yard.drawing(request)["nodes"])["skill"]["sculpt"]["edits"]

  test "each kind gives a drawing of one part from edits, and an order of it is true" do
    assert Yard.kinds() == ~w(bridge fence gate haystack jar well)

    for kind <- Yard.kinds() do
      d = Yard.drawing(%{"kind" => kind})
      assert {:ok, _} = World.Drawing.check(d, "d"), kind
      assert JSON.decode!(JSON.encode!(d)) == d
      assert d["name"] == kind and d["kind"] == "building" and d["extras"]["village_thing"]["kind"] == kind
      assert [%{"name" => name, "skill" => %{"sculpt" => sculpt}}] = d["nodes"]
      assert name == kind <> "_than" and Enum.all?(sculpt["edits"], &(&1["material"] == "part_01"))
      %{"near" => near, "mid" => mid, "far" => far} = sculpt["cells"]
      assert near < mid and mid < far and far <= 0.2
      # The bed of a canal holds the poles of a bridge; each other thing stands.
      assert Map.has_key?(d["extras"], "site") == (kind == "bridge")

      assert {:ok, _} = World.Orders.place(%{"blueprint" => "drawing", "options" => %{"drawing" => d}}, "http://x"),
             kind
    end
  end

  test "a request with no word is a well; the length of a fence and of a bridge, the color and the name" do
    r = Yard.request()
    assert Yard.request(r) == r
    assert r == %{"kind" => "well", "name" => "well", "sources" => [], "length" => 2.8, "color" => "#a5673f"}
    assert Yard.drawing() == Yard.drawing(%{})

    # A well: a platform, a wall of the color of the request, a curb, a hole and the water.
    assert [
             _,
             %{"color" => "#112233", "size" => [0.9, 0.35]},
             %{"mode" => "paint"},
             %{"mode" => "subtract"},
             %{"mode" => "paint"}
           ] =
             edits(%{"color" => "#112233", "name" => "gieng", "sources" => ["A well."]})

    # A fence of 6 m: 7 posts, 2 rails of 6 m along x, a slat each 11 cm at the near level, and one panel at
    # each other level.
    fence = edits(%{"kind" => "fence", "length" => 6})
    assert Enum.count(fence, &(&1["size"] == [0.035, 0.65])) == 7
    assert [%{"axis" => [1, 0, 0]}, _] = Enum.filter(fence, &(&1["size"] == [0.022, 3.0]))
    assert Enum.count(fence, &(&1["levels"] == ["near"])) == 56

    assert [%{"levels" => ["mid"], "size" => [3.0, 0.02, 0.5]}, %{"levels" => ["far"]}] =
             Enum.filter(fence, &(&1["shape"] == "box"))

    # A bridge of 9 m: its trestles are a third of its length from its middle. A jar has no length of a request.
    bridge = edits(%{"kind" => "bridge", "length" => 9})
    tubes = for %{"shape" => "tube", "size" => %{"points" => [[x, _, _], _]}} <- bridge, do: x
    assert tubes == [-3.0, -3.0, 3.0, 3.0]
    assert Yard.request(%{"kind" => "jar", "length" => 5})["length"] == 0.85
    assert Enum.count(edits(%{"kind" => "jar"}), &(&1["mode"] == "subtract")) == 3
    assert length(edits(%{"kind" => "gate"})) == 10 and length(edits(%{"kind" => "haystack"})) == 4
  end

  test "a word that is not possible is an error with its message" do
    wrong = [
      {[], "the request of a thing of a village is a map"},
      {%{"size" => 3}, ~s(a thing of a village has no key "size")},
      {%{"kind" => "pagoda"}, "the kind of a thing of a village is one of bridge, fence"},
      {%{"name" => "Giếng"}, "the name of a thing of a village"},
      {%{"sources" => "a page"}, "the sources of a thing of a village are lines of text"},
      {%{"kind" => "fence", "length" => 30}, "the length of a fence or of a bridge is from 1 m to 20 m"},
      {%{"kind" => "bridge", "length" => "long"}, "the length of a fence or of a bridge"},
      {%{"color" => "brown"}, "the color of a thing of a village is as #a1b2c3"}
    ]

    for {request, text} <- wrong do
      error = assert_raise ArgumentError, fn -> Yard.request(request) end
      assert error.message =~ text
    end
  end
end
