defmodule World.ElementsTest do
  # The parts list of an order (W24 to W28): World gives the parts, and a
  # project puts them together. No join, and no whole model in memory.
  # (Not async: the tests change the limits of the parts.)
  use ExUnit.Case

  alias World.{Elements, Frame, Orders}
  alias World.Elements.Store

  @moduletag timeout: 1_800_000

  setup_all do
    # The parts of the tests before (the store keeps a part: its key is its data).
    dir =
      Keyword.get(
        Application.get_env(:world, World.Orders.Store, []),
        :dir,
        System.get_env("WORLD_ORDER_DIR", "tmp/orders")
      )

    File.rm_rf!(Path.join(dir, "parts"))
    :ok
  end

  setup do
    before =
      for k <- [:tile_faces, :tile_least, :part_wait, :memory_mb], into: %{}, do: {k, Application.get_env(:world, k)}

    # Small steps and parts, so that a small wall is cut.
    Application.put_env(:world, :tile_faces, 3_000)
    Application.put_env(:world, :tile_least, 400)

    on_exit(fn ->
      for {k, v} <- before, do: if(v, do: Application.put_env(:world, k, v), else: Application.delete_env(:world, k))
    end)
  end

  # A wall from edits (8 m long, with a soft bump at each end) and a lid on
  # a hinge at its top: a sculpture and a part of shapes.
  # (`tag` makes the data of the wall, and so its keys, its own: the store keeps the parts of each test.)
  defp drawing(bump \\ 0.3, tag \\ "") do
    %{
      "name" => "wall",
      "kind" => "item",
      "sources" => ["A test."],
      "parts" => %{
        "lid" => %{
          "shapes" => [%{"box" => %{"from" => [-0.5, -0.1, 0], "to" => [0.5, 0.1, 0.05]}, "material" => "wood"}],
          "ports" => %{"hinge" => %{"at" => [0, 0, 0], "axis" => [1, 0, 0]}}
        }
      },
      "nodes" => [
        %{
          "name" => "wall",
          "skill" => %{
            "sculpt" => %{
              "edits" => [
                %{"shape" => "box", "size" => [4, 0.15, 0.5], "at" => [0, 0, 0.5], "material" => "plaster"},
                %{"shape" => "ball", "size" => [0.3], "at" => [-3.5, 0, 1], "blend" => 0.1},
                %{"shape" => "ball", "size" => [bump], "at" => [3.5, 0, 1], "blend" => 0.1}
              ],
              "ports" => %{"top" => %{"at" => [0, 0, 1], "axis" => [1, 0, 0]}},
              "sources" => ["A test wall #{tag}."],
              "cells" => %{"far" => 0.04},
              "budget" => %{"far" => 4_000}
            }
          }
        },
        %{
          "name" => "lid",
          "part" => "lid",
          "to" => "wall",
          "at" => "top",
          "port" => "hinge",
          "joint" => %{"kind" => "hinge", "role" => "lid", "limits" => [0, 90]}
        }
      ]
    }
  end

  defp order(d), do: %{"blueprint" => "drawing", "options" => %{"drawing" => d}}

  test "the parts list of a drawing: a sculpture in tiles with recipes, a part of shapes in the store, the joints and the places" do
    d = drawing(0.3, "list")
    assert {:ok, list} = Elements.list(order(d), "far")
    {:ok, full} = Orders.check(order(d))
    assert list["order"] == Orders.hash(full) and list["level"] == "far"
    assert list["joints"] == ["lid"]
    {tiles, [lid]} = Enum.split_with(list["parts"], &(&1["node"] == "wall"))

    # The wall is cut into tiles: each a part with its key, its URL and its recipe, and no GLB yet.
    assert length(tiles) >= 2
    assert Enum.map(tiles, & &1["part"]) == for(i <- 0..(length(tiles) - 1), do: "wall_#{i}")

    for t <- tiles do
      assert t["key"] =~ ~r/^[0-9a-f]{32}$/ and t["url"] == "/p/#{t["key"]}.glb"
      assert t["roles"] |> Enum.sort() == ["paint", "plaster"]
      assert t["tile"]["share"] > 0 and t["matrix"] == Frame.matrix(World.GLB.gl_frame(Frame.identity()))
      assert {:ok, _} = Store.recipe(t["key"])
      refute Store.has?(t["key"])
    end

    # The shares of the faces of the tiles: about all of the faces.
    assert_in_delta Enum.sum(for t <- tiles, do: t["tile"]["share"]), 1.0, 0.3

    # The lid is made for the list: its GLB is in the store, and it is on its hinge, at the top of the wall.
    assert lid["part"] == "lid" and lid["joint"] == "lid" and lid["kind"] == "part" and lid["roles"] == ["wood"]
    assert Store.has?(lid["key"])
    # (Its place in the axes of glTF: y up, so the top of the wall at 1 m is y = 1.)
    assert_in_delta Enum.at(lid["matrix"], 13), 1.0, 1.0e-9

    # Each tile builds from its recipe at its first request, and then comes from the store.
    for t <- tiles do
      assert {:ok, <<"glTF", _::binary>> = glb} = Elements.part(t["key"])
      assert Store.has?(t["key"]) and Elements.part(t["key"]) == {:ok, glb}
    end

    # The same order again: the same keys (W25).
    assert {:ok, ^list} = Elements.list(order(d), "far")
    assert Elements.part(String.duplicate("e", 32)) == :none
  end

  test "an edit of an order changes only the keys of the parts whose data changed (W27)" do
    {:ok, before} = Elements.list(order(drawing(0.3, "edit")), "far")
    # A larger bump at the end x = 3.5: the tiles at the other end, and the lid, keep their keys.
    {:ok, after_edit} = Elements.list(order(drawing(0.35, "edit")), "far")
    keys = fn l -> MapSet.new(l["parts"], & &1["key"]) end
    same = MapSet.intersection(keys.(before), keys.(after_edit))
    lid = Enum.find(before["parts"], &(&1["part"] == "lid"))
    assert MapSet.member?(same, lid["key"])
    assert MapSet.size(same) >= 2 and MapSet.size(same) < length(before["parts"])
  end

  test "a sculpture with few faces is one part, built from its recipe" do
    small = put_in(drawing(0.3, "small"), ["nodes", Access.at(0), "skill", "sculpt", "cells"], %{"far" => 0.2})
    {:ok, list} = Elements.list(order(small), "far")
    assert [%{"part" => "wall"} = wall, %{"part" => "lid"}] = list["parts"]
    refute Map.has_key?(wall, "tile")
    assert {:ok, <<"glTF", _::binary>>} = Elements.part(wall["key"])
  end

  test "a part that takes long builds on after the request, and the next request gets it" do
    {:ok, list} = Elements.list(order(drawing(0.3, "fetch")), "far")
    [t | _] = list["parts"]
    refute Store.has?(t["key"])
    # Two requests that do not wait: one build, which goes on.
    assert Elements.fetch(t["key"], 0) == :building
    assert Elements.fetch(t["key"], 0) == :building
    assert {:ok, <<"glTF", _::binary>>} = Elements.fetch(t["key"], 600_000)
    assert {:ok, _} = Elements.fetch(t["key"], 0)
    assert Elements.fetch(String.duplicate("d", 32), 0) == :none
  end

  test "a part that needs more memory than the VM has gives an error, and the VM goes on" do
    d = drawing(0.3, "memory")
    {:ok, list} = Elements.list(order(d), "far")
    [t | _] = list["parts"]
    Application.put_env(:world, :memory_mb, 1)
    assert {:error, [%{"message" => "needs more memory than the factory has (1 MB)" <> _}]} = Elements.part(t["key"])
    assert {:error, [_]} = Elements.list(order(d), "far")
    assert {:error, [_]} = Orders.build(order(d), "far", "elements")
    Application.delete_env(:world, :memory_mb)
    assert {:ok, _} = Elements.part(t["key"])
  end

  test "a group of people: each person is a part, with its props, made one by one" do
    group = %{"blueprint" => "exercise", "options" => %{"count" => 2, "fans" => true}}
    {:ok, list} = Elements.list(group, "far")

    assert Enum.map(list["parts"], &{&1["node"], &1["kind"]}) == [
             {"leader", "figure"},
             {"person_1", "figure"},
             {"person_2", "figure"}
           ]

    assert list["parts"] |> Enum.map(& &1["key"]) |> Enum.uniq() |> length() == 3
    for p <- list["parts"], do: assert(Store.has?(p["key"]) and "skin" in p["roles"])
    # Each person is at its place in the group: the place of its figure in the whole model.
    {:ok, full} = Orders.check(group)
    {:ok, blueprint} = World.Orders.Blueprints.fetch("exercise")
    whole = World.Detail.with(:far, fn -> blueprint.build.(full["options"]) end)

    for {{:figure, path, frame, _, nil}, part} <- Enum.zip(World.Build.places(whole, :far), list["parts"]) do
      assert part["node"] == path
      for {a, b} <- Enum.zip(part["matrix"], Frame.matrix(World.GLB.gl_frame(frame))), do: assert_in_delta(a, b, 1.0e-9)
    end

    # A rule with no pieces: its model is made, and each part of it is a part of the list.
    {:ok, strut} = Elements.list(%{"blueprint" => "strut", "options" => %{"length" => 0.3}}, "far")
    assert [%{"kind" => "part", "joint" => nil}] = strut["parts"]
    # The same group with an edit of one person only would keep the keys of the others: a key is the content.
    assert {:ok, ^list} = Elements.list(group, "far")
  end

  test "the key of a part from its content, the keys of the nodes of a drawing, and the version of a rule" do
    part = World.Part.new("p", :part, [World.Shape.box({0, 0, 0}, {1, 1, 1}, :wood)], [])
    key = Elements.made_key(part, :far)
    assert key =~ ~r/^[0-9a-f]{32}$/
    # The level where a part shows is not its content; its level, its maps and the colors are.
    assert Elements.made_key(%{part | detail: :always}, :far) == key
    refute Elements.made_key(part, :mid) == key
    refute Elements.made_key(part, :far, %{"wood" => %{"image" => "x"}}) == key
    refute Elements.made_key(part, :far, %{}, %{"wood" => "#ff0000"}) == key

    keys = Elements.node_keys(drawing(), :far)
    # A node waits for its parent: a change of the wall changes the key of the lid.
    assert Elements.node_keys(drawing(0.35), :far)["lid"] != keys["lid"]
    assert Elements.node_keys(drawing(), :mid)["wall"] != keys["wall"]
    assert Elements.node_keys(drawing(), :far) == keys

    version = Elements.version(World.Skills.Sculpt)
    assert version =~ ~r/^[0-9a-f]{12}$/ and Elements.version(World.Skills.Sculpt) == version
    refute Elements.version(World.Orders.Blueprints) == version
  end

  test "the GLB of a part has the maps of its node and the colors of the order" do
    part = World.Part.new("p", :part, [World.Shape.box({0, 0, 0}, {1, 1, 1}, :wood)], [])
    plain = Elements.glb(part, :far)
    red = Elements.glb(part, :far, %{}, %{"wood" => "#ff0000"})
    refute plain == red
    assert red =~ "[255,0,0]" or red =~ "1.0,0.0,0.0"
    assert Elements.glb(part, :far, %{"wood" => %{"roughness" => 0.123}}) =~ "0.123"
  end

  test "an order with a sculpture larger than a step of a part is not built for its check" do
    # (A wall that floats: its check fails when the order builds it.)
    high =
      put_in(drawing(0.3, "high"), ["nodes", Access.at(0), "skill", "sculpt", "edits", Access.at(0), "at"], [0, 0, 5])

    Application.put_env(:world, :tile_faces, 1_000_000)
    assert {:error, [%{"path" => "model"} | _]} = Orders.place(order(high), "o")
    Application.put_env(:world, :tile_faces, 3_000)
    assert {:ok, _} = Orders.place(order(high), "o")
  end

  test "the URLs of the parts: GET /p/KEY.glb, from the store or built (202 while it builds), and the elements of a construction" do
    get = fn path -> Plug.Test.conn(:get, path) |> World.Service.call(World.Service.init([])) end
    {:ok, list} = Elements.list(order(drawing(0.3, "urls")), "far")
    [t | _] = list["parts"]
    lid = List.last(list["parts"])

    # A part in the store: its GLB, with a key that does not change.
    conn = get.("/p/#{lid["key"]}.glb")
    assert conn.status == 200
    assert <<"glTF", _::binary>> = conn.resp_body
    assert Plug.Conn.get_resp_header(conn, "etag") == [~s("#{lid["key"]}")]
    assert [cache] = Plug.Conn.get_resp_header(conn, "cache-control")
    assert cache =~ "immutable"

    # A part that builds: 202 with retry-after, then the part.
    Application.put_env(:world, :part_wait, 0)
    conn = get.("/p/#{t["key"]}.glb")
    assert conn.status == 202 and Plug.Conn.get_resp_header(conn, "retry-after") == ["15"]
    assert {:ok, _} = Elements.fetch(t["key"], 600_000)
    assert get.("/p/#{t["key"]}.glb").status == 200

    # A part that needs more memory than the VM has: 422.
    [_, other | _] = list["parts"]
    Application.put_env(:world, :part_wait, 600_000)
    Application.put_env(:world, :memory_mb, 1)
    assert get.("/p/#{other["key"]}.glb").status == 422
    Application.delete_env(:world, :memory_mb)

    for path <- ["/p/#{String.duplicate("c", 32)}.glb", "/p/xyz.glb", "/p/#{lid["key"]}.png"],
        do: assert(get.(path).status == 404)

    # The GLB of an element of a construction comes from the store of the parts after the construction (W28).
    assert get.("/builds/gone/elements/#{lid["key"]}.glb").status == 200
    assert get.("/builds/gone/elements/abc.glb").status == 404
  end

  test "a parts list that takes long builds on after the request: 202, then the list" do
    post = fn path, body -> Plug.Test.conn(:post, path, body) |> World.Service.call(World.Service.init([])) end
    get = fn path -> Plug.Test.conn(:get, path) |> World.Service.call(World.Service.init([])) end
    order = order(drawing(0.3, "list-202"))
    {:ok, placed} = Orders.place(order, "o")
    Application.put_env(:world, :part_wait, 0)

    # The build of the Worker (POST /build): 202 while the list builds, then the list from the files of the node.
    conn = post.("/build?level=far&file=elements&hash=#{placed["hash"]}", nil)
    assert conn.status == 202 and Plug.Conn.get_resp_header(conn, "retry-after") == ["15"]
    Application.put_env(:world, :part_wait, 600_000)
    conn = post.("/build?level=far&file=elements&hash=#{placed["hash"]}", nil)
    assert conn.status == 200 and JSON.decode!(conn.resp_body)["order"] == placed["hash"]
    assert post.("/build?level=far&file=elements&hash=#{placed["hash"]}", nil).status == 200

    # The file of the server on a computer (GET /o/): the same.
    Application.put_env(:world, :part_wait, 0)
    conn = get.("/o/#{placed["hash"]}.mid.elements.json")
    assert conn.status == 202
    Application.put_env(:world, :part_wait, 600_000)
    conn = get.("/o/#{placed["hash"]}.mid.elements.json")
    assert conn.status == 200 and JSON.decode!(conn.resp_body)["level"] == "mid"
    assert get.("/o/#{placed["hash"]}.mid.elements.json").status == 200
  end
end
