defmodule World.VillageHouseTest do
  # A house of a village of old Việt Nam from a request of a few words (plan 0019, 7.1).
  use ExUnit.Case, async: true

  alias World.Village.House

  defp part(drawing, name),
    do: Enum.find(drawing["nodes"], &(&1["name"] == "#{drawing["name"]}_#{name}"))["skill"]["sculpt"]

  defp checked(request) do
    drawing = House.drawing(request)
    assert {:ok, _} = World.Drawing.check(drawing, "d")
    assert JSON.decode!(JSON.encode!(drawing)) == drawing
    drawing
  end

  test "a request with no word: three bays on a low base, planks, a roof of thatch" do
    r = House.request()
    assert House.request(r) == r

    assert r == %{
             "name" => "nha_xua",
             "sources" => [],
             "bays" => 3,
             "bay" => 2.6,
             "deep" => 4.2,
             "porch" => 1.2,
             "stilts" => 0.0,
             "wall" => "wood",
             "roof" => "thatch",
             "curve" => 0.5,
             "eaves" => 0.9,
             "age" => 0.5
           }

    assert House.walls() == ~w(bamboo earth wood) and House.roofs() == ~w(thatch tiles)
    # The frame is 7.8 m by 5.4 m with the porch; the roof goes 0.9 m out, and a roof of thatch is steep.
    assert House.sizes(r) == %{
             "long" => 7.8,
             "deep" => 5.4,
             "floor" => 0.35,
             "eaves" => 2.65,
             "ridge" => 6.394,
             "roof" => [9.6, 7.2]
           }

    d = checked(%{})
    assert House.drawing() == d
    assert Enum.map(d["nodes"], & &1["name"]) == for(p <- ~w(khung mai dau_hoi nen), do: "nha_xua_#{p}")
    assert d["kind"] == "house" and d["extras"] == %{"village_house" => r, "sizes" => House.sizes(r)}
    frame = part(d, "khung")["edits"]

    # Four posts in each of three rows (the back wall, the front wall, the edge of the porch), and five bars in each of two windows.
    posts = Enum.filter(frame, &(&1["shape"] == "cylinder" and &1["size"] == [0.11, 1.325]))

    assert length(posts) == 12 and
             posts |> Enum.map(&Enum.at(&1["at"], 1)) |> Enum.uniq() |> Enum.sort() == [-2.7, 1.5, 2.7]

    assert Enum.count(frame, &(&1["shape"] == "cylinder" and &1["size"] == [0.02, 0.45])) == 10
    # One door in the middle bay and a window in each other bay; a base with two steps, and no stair.
    hollows = Enum.filter(frame, &(&1["mode"] == "subtract"))
    assert Enum.map(hollows, &hd(&1["at"])) == [-2.6, 0.0, 2.6] and Enum.at(hollows, 1)["size"] == [0.55, 0.25, 0.95]
    refute Enum.any?(frame, &(&1["shape"] == "extrude"))
    assert Enum.count(frame, &(&1["color"] == "#a8946e")) == 2
    assert part(d, "khung")["dirt"] == 0.4 and Enum.all?(frame, &(&1["material"] == "part_01"))
  end

  test "the roof: two long slopes with the ridge and four hips, and two end slopes; the rows of a roof of tiles" do
    d = checked(%{"name" => "nha_ngoi", "bays" => 5, "roof" => "tiles", "curve" => 1})
    assert %{"ridge" => ridge, "eaves" => 2.65, "roof" => [14.8, 7.2]} = House.sizes(d["extras"]["village_house"])
    assert_in_delta ridge, 2.65 + 0.4 * 7.2, 1.0e-3
    long = part(d, "mai")["edits"]

    assert [
             %{
               "shape" => "extrude",
               "axis" => [1, 0, 0],
               "levels" => ["near", "mid"],
               "size" => %{"depth" => 14.8, "outline" => shell}
             },
             %{"shape" => "extrude", "levels" => ["far"], "size" => %{"outline" => thick}},
             %{"mode" => "crop", "axis" => [0, 1, 0]} | rest
           ] = long

    # At the far level the shell is 0.4 m thick (the last point of its outline is under the first one).
    assert List.last(shell) == [-3.46, -0.14] and List.last(thick) == [-3.2, -0.4]

    # The slope goes from its eaves up to the ridge under a line that sags: the middle of the slope is low.
    assert hd(shell) == [-3.6, 0.0] and Enum.at(shell, 12) == [0.0, 2.88]
    assert [-1.8, sag] = Enum.at(shell, 6)
    assert sag < 0.3 * 2.88
    assert Enum.count(rest, &(&1["mode"] == "paint")) == 10
    tubes = Enum.filter(rest, &(&1["shape"] == "tube"))
    assert length(tubes) == 5
    # The end of each hip of a roof of tiles is lifted and longer than the corner (the đao).
    [last_x, last_y, last_z] = tubes |> List.last() |> get_in(["size", "points"]) |> List.last()
    assert last_x > 7.4 and last_y > 3.6 and last_z > 2.65 + 0.5

    ends = part(d, "dau_hoi")["edits"]

    assert [
             %{"shape" => "extrude", "axis" => [0, 1, 0], "size" => %{"depth" => 7.2}},
             %{"levels" => ["far"]},
             %{"mode" => "crop", "axis" => [1, 0, 0]} | rows
           ] = ends

    assert length(rows) == 10

    # A roof of thatch has no rows, and its corners lift only a little. A house of one bay has a short ridge.
    small = checked(%{"bays" => 1, "bay" => 1.8, "deep" => 3, "porch" => 0, "curve" => 0})
    assert [_, _, _ | tubes] = part(small, "mai")["edits"]
    assert length(tubes) == 5 and Enum.all?(tubes, &(&1["shape"] == "tube"))
    [ridge_tube | _] = tubes
    assert ridge_tube["size"]["points"] |> Enum.map(&hd/1) |> Enum.max() == 0.3
    assert length(part(small, "dau_hoi")["edits"]) == 3
    # With no porch, the posts are in two rows.
    posts = Enum.filter(part(small, "khung")["edits"], &(&1["shape"] == "cylinder" and hd(&1["size"]) == 0.11))
    assert length(posts) == 4
  end

  test "a house on stilts has a stair in front of its door; an even count of bays has two doors" do
    d =
      checked(%{
        "name" => "nha_san",
        "bays" => 4,
        "stilts" => 1.8,
        "wall" => "bamboo",
        "sources" => ["A house on stilts of the test."]
      })

    assert d["sources"] == ["A house on stilts of the test."]
    assert %{"floor" => 1.8, "eaves" => 4.1} = House.sizes(d["extras"]["village_house"])
    frame = part(d, "khung")["edits"]
    assert [stair] = Enum.filter(frame, &(&1["shape"] == "extrude"))
    # Eight steps from the floor down to the ground, in front of the left door of the two.
    assert stair["at"] == [-1.3, 2.85, 0] and length(stair["size"]["outline"]) == 18
    assert List.last(stair["size"]["outline"]) == [2.08, 0.0]
    hollows = Enum.filter(frame, &(&1["mode"] == "subtract"))
    assert Enum.map(hollows, &Enum.at(&1["size"], 2)) == [0.45, 0.95, 0.95, 0.45]
    assert Enum.any?(frame, &(&1["color"] == "#b89a58" and &1["surface"]["kind"] == "weave"))
    refute Enum.any?(frame, &(&1["color"] == "#a8946e"))
    assert Enum.any?(part(checked(%{"wall" => "earth"}), "khung")["edits"], &(&1["color"] == "#c9a97a"))
  end

  test "a word that is not possible is an error with its message" do
    wrong = [
      {[], "the request of a house of a village is a map"},
      {%{"floors" => 2}, ~s(a house of a village has no key "floors")},
      {%{"name" => "Nhà"}, "the name of a house"},
      {%{"sources" => "a photo"}, "the sources of a house are lines of text"},
      {%{"bays" => 8}, "from 1 to 7 bays"},
      {%{"wall" => "brick"}, "the wall of a house of a village is one of bamboo, earth, wood"},
      {%{"roof" => "steel"}, "the roof of a house of a village is one of thatch, tiles"},
      {%{"stilts" => 4}, "the value of stilts is a number from 0 to 3"}
    ]

    for {request, text} <- wrong do
      error = assert_raise ArgumentError, fn -> House.request(request) end
      assert error.message =~ text
    end
  end
end
