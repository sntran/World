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
      # (The recipe has the estimate of the memory of the build of the tile: World.Labour.fits?/1.)
      assert {:ok, json} = Store.recipe(t["key"])
      recipe = JSON.decode!(json)
      assert is_float(recipe["memory"]) and recipe["memory"] >= 15
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

  test "a group of people: each person is a part, with its props, made alone at its first request" do
    group = %{"blueprint" => "exercise", "options" => %{"count" => 2, "fans" => true}}
    {:ok, list} = Elements.list(group, "far")

    assert Enum.map(list["parts"], &{&1["node"], &1["kind"]}) == [
             {"leader", "piece"},
             {"person_1", "piece"},
             {"person_2", "piece"}
           ]

    keys = Enum.map(list["parts"], & &1["key"])
    assert length(Enum.uniq(keys)) == 3
    # The list makes no person: each has a recipe.
    for k <- keys, do: assert({:ok, _} = Store.recipe(k))
    for p <- list["parts"], do: assert(p["matrix"] == Frame.matrix(World.GLB.gl_frame(Frame.identity())))

    # Each person, made alone, is at its place in the group: the place of its figure in the whole model.
    {:ok, full} = Orders.check(group)
    {:ok, blueprint} = World.Orders.Blueprints.fetch("exercise")
    whole = World.Detail.with(:far, fn -> blueprint.build.(full["options"]) end)

    for {{:figure, path, frame, _, nil}, part} <- Enum.zip(World.Build.places(whole, :far), list["parts"]) do
      assert part["node"] == path

      {:ok, <<"glTF", _::32, _::32, size::little-32, "JSON", json::binary-size(size), _::binary>>} =
        Elements.part(part["key"])

      {x, y, z} = World.GLB.gl_frame(frame).at

      assert Enum.any?(JSON.decode!(json)["nodes"], fn n ->
               match?([_, _, _], n["translation"]) and
                 Enum.zip(n["translation"], [x, y, z]) |> Enum.all?(fn {a, b} -> abs(a - b) < 1.0e-6 end)
             end)
    end

    # A rule with no pieces: its model is made, and each part of it is a part of the list.
    {:ok, strut} = Elements.list(%{"blueprint" => "strut", "options" => %{"length" => 0.3}}, "far")
    assert [%{"kind" => "part", "joint" => nil}] = strut["parts"]
    assert {:ok, ^list} = Elements.list(group, "far")

    # A group in a node of a drawing: each person is a part of the node, at its place in the model.
    group_node = %{
      "name" => "group",
      "item" => %{"blueprint" => "exercise", "options" => %{"count" => 1}},
      "to" => "wall",
      "at" => "top"
    }

    yard = update_in(drawing(0.3, "yard"), ["nodes"], &(&1 ++ [group_node]))
    {:ok, drawn} = Elements.list(order(yard), "far")
    people = Enum.filter(drawn["parts"], &(&1["node"] == "group"))
    assert Enum.map(people, &{&1["kind"], &1["part"]}) == [{"figure", "leader"}, {"figure", "person_1"}]
    # (The leader stands at the top of the wall: 1 m up, the y of glTF.)
    assert_in_delta Enum.at(hd(people)["matrix"], 13), 1.0, 1.0e-6
    for p <- people, do: assert(p["roles"] != [] and Store.has?(p["key"]))
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

    # A module with no file of the source (made in memory) has only the versions of Elixir and OTP.
    [{loose, _}] = Code.compile_string("defmodule World.ElementsTestLoose do def x, do: World.Frame.identity() end")
    assert Elements.version(loose) =~ ~r/^[0-9a-f]{12}$/

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

  test "a build that stops before its end: the part or the list of another build, else an error (no loop)" do
    post = fn path, body -> Plug.Test.conn(:post, path, body) |> World.Service.call(World.Service.init([])) end
    get = fn path -> Plug.Test.conn(:get, path) |> World.Service.call(World.Service.init([])) end

    # A build of the key that runs now: it gets the wait of a request, does `last`, and stops with no answer.
    stops = fn key, last ->
      me = self()

      spawn(fn ->
        {:ok, _} = Registry.register(World.Names, {:build, key}, nil)
        send(me, :registered)
        receive do: ({:wait, _, _} -> last.())
      end)

      assert_receive :registered
    end

    tag = "stops-#{System.os_time()}"
    {:ok, list} = Elements.list(order(drawing(0.3, tag)), "far")
    [t, u | _] = list["parts"]
    glb = Elements.glb(World.Part.new("p", :part, [World.Shape.box({0, 0, 0}, {1, 1, 1}, :wood)], []), :far)
    stops.({:part, t["key"]}, fn -> Store.put(t["key"], glb) end)
    # (The part of another build is in the store: the GLB does not come to this node.)
    assert Elements.fetch(t["key"]) == :stored
    # GET /p/ of a part that another node puts in the store: the Worker in front of the VM (x-world-origin)
    # reads it from R2 (204); a server with no Worker sends it from its store.
    {:ok, more} = Elements.list(order(drawing(0.3, tag <> "-more")), "far")
    [v, w | _] = more["parts"]
    stops.({:part, v["key"]}, fn -> Store.put(v["key"], glb) end)
    assert get.("/p/#{v["key"]}.glb").status == 200
    stops.({:part, w["key"]}, fn -> Store.put(w["key"], glb) end)
    front = Plug.Test.conn(:get, "/p/#{w["key"]}.glb") |> Plug.Conn.put_req_header("x-world-origin", "https://w")
    assert World.Service.call(front, World.Service.init([])).status == 204
    stops.({:part, u["key"]}, fn -> :ok end)
    assert {:error, [%{"message" => "the build stopped before its end" <> _}]} = Elements.fetch(u["key"])

    # The parts list of POST /build: from the files after another build, else 422.
    [one, two, three, four] =
      for i <- 1..4 do
        {:ok, placed} = Orders.place(order(drawing(0.3, "#{tag}-#{i}")), "o")
        placed["hash"]
      end

    stops.({:file, one, "far"}, fn -> World.Files.put(one, "far", "elements", ~s({"parts":[]})) end)
    conn = post.("/build?level=far&file=elements&hash=#{one}", nil)
    assert conn.status == 200 and conn.resp_body == ~s({"parts":[]})
    stops.({:file, two, "far"}, fn -> :ok end)
    conn = post.("/build?level=far&file=elements&hash=#{two}", nil)
    assert conn.status == 422 and conn.resp_body =~ "the build stopped"

    # GET /o/: 500 when the build stops, and 422 with the errors of the build.
    stops.({:file, three, "near", "elements"}, fn -> :ok end)
    conn = get.("/o/#{three}.elements.json")
    assert conn.status == 500 and conn.resp_body =~ "the build stopped"
    Application.put_env(:world, :memory_mb, 1)
    conn = get.("/o/#{four}.far.elements.json")
    assert conn.status == 422 and conn.resp_body =~ "needs more memory"
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

  test "with construction shifts: a part of a project waits for a shift, and the answer tells the Worker to start one; a public part gets 422" do
    get = fn path, headers ->
      headers
      |> Enum.reduce(Plug.Test.conn(:get, path), fn {k, v}, conn -> Plug.Conn.put_req_header(conn, k, v) end)
      |> World.Service.call(World.Service.init([]))
    end

    {:ok, list} = Elements.list(%{"blueprint" => "exercise", "options" => %{"count" => 5}}, "near")
    key = hd(list["parts"])["key"]
    memory = Application.get_env(:world, :memory_mb)
    Application.put_env(:world, :shifts, true)
    Application.put_env(:world, :part_wait, 50)

    try do
      # (Before any part waits: the first request of a project marks its answer.)
      Application.put_env(:world, :part_wait, 0)
      first = get.("/p/#{key}.glb", [{"x-world-project", "vung_tau"}])
      assert first.status == 202 and Plug.Conn.get_resp_header(first, "x-world-shift") == ["wanted"]
      for {pid, _} <- Registry.lookup(World.Names, {:build, {:part, key}}), do: Process.exit(pid, :kill)
      Process.sleep(20)
      Application.put_env(:world, :part_wait, 50)
      public = get.("/p/#{key}.glb", [])
      assert public.status == 422 and public.resp_body =~ "does not fit the memory and the CPU time of the edge"

      assert public.resp_body =~ "ask for the whole file of the order" and
               public.resp_body =~ "a repository of the account sntran"

      # (No node of a shift here: the part waits in the queue.)
      project = get.("/p/#{key}.glb", [{"x-world-project", "vung_tau"}])
      assert project.status == 202
      assert Plug.Conn.get_resp_header(project, "x-world-shift") == ["wanted"]
      # (The build goes on after the answer of 202: the part comes into the queue soon after.)
      assert Enum.find(1..400, fn _ -> World.Labour.waiting() == 1 or (Process.sleep(25) && false) end)

      # A part of a sculpture under the limit of faces fits the edge: it builds at once, for a project and for a public caller.
      # (The wait of a request is longer than its build.)
      Application.put_env(:world, :part_wait, 60_000)
      {:ok, wall} = Elements.list(order(drawing(0.3, "shift")), "far")
      sculpted = Enum.find(wall["parts"], &(&1["tile"] != nil or &1["node"] == "wall"))["key"]
      assert <<"glTF", _::binary>> = get.("/p/#{sculpted}.glb", [{"x-world-project", "vung_tau"}]).resp_body
      assert get.("/p/#{sculpted}.glb", []).status == 200

      # A part that fits by its estimate, and that the guard of the memory stops at the edge: a
      # project waits for a shift; a public caller gets the error of the guard.
      {:ok, other} = Elements.list(order(drawing(0.25, "guard")), "far")
      guarded = Enum.find(other["parts"], &(&1["tile"] != nil or &1["node"] == "wall"))["key"]
      {:ok, third} = Elements.list(order(drawing(0.26, "guard")), "far")
      # (The last tile has the bump of 0.26 m: a part of its own.)
      first = third["parts"] |> Enum.filter(&(&1["node"] == "wall")) |> List.last() |> Map.fetch!("key")
      assert first != guarded
      Application.put_env(:world, :memory_mb, 1)
      public = get.("/p/#{guarded}.glb", [])
      assert public.status == 422 and public.resp_body =~ "needs more memory than the factory has"
      # (The process of that build waits 1 s for late requests: a new request starts a new build.)
      for {pid, _} <- Registry.lookup(World.Names, {:build, {:part, guarded}}), do: Process.exit(pid, :kill)
      Process.sleep(20)
      Application.put_env(:world, :part_wait, 50)
      # (That build wrote its mark, and it did not end: the part waits for a shift at once.)
      assert World.Elements.Store.marked?(guarded)
      project = get.("/p/#{guarded}.glb", [{"x-world-project", "vung_tau"}])
      assert project.status == 202

      assert Enum.find(1..400, fn _ ->
               Process.sleep(25)
               World.Labour.waiting() == 2
             end)

      # The first request of another part is of a project: the build starts here, and when the
      # guard stops it, the part goes to the queue.
      refute World.Elements.Store.marked?(first)
      assert get.("/p/#{first}.glb", [{"x-world-project", "vung_tau"}]).status == 202

      assert Enum.find(1..400, fn _ ->
               Process.sleep(25)
               World.Labour.waiting() == 3
             end)

      for k <- [guarded, first],
          {pid, _} <- Registry.lookup(World.Names, {:build, {:part, k}}),
          do: Process.exit(pid, :kill)
    after
      if memory, do: Application.put_env(:world, :memory_mb, memory), else: Application.delete_env(:world, :memory_mb)
      Application.delete_env(:world, :shifts)
      Application.delete_env(:world, :part_wait)
      # (The part waits no more.)
      for {pid, _} <- Registry.lookup(World.Names, {:build, {:part, key}}), do: Process.exit(pid, :kill)
    end
  end

  test "the check of an order and of its edits waits in the line of the builds, as a build" do
    me = self()
    post = fn path, body -> Plug.Test.conn(:post, path, body) |> World.Service.call(World.Service.init([])) end

    # (A build holds the one place of the line; a request waits behind it, and goes when it ends.)
    behind = fn request ->
      holder =
        spawn(fn ->
          World.Line.run(fn ->
            send(me, :in)
            receive(do: (:go -> :ok))
          end)
        end)

      assert_receive :in
      task = Task.async(request)
      # (The request is in the line, behind the build, for 10 s at most.)
      assert Enum.any?(1..1000, fn _ -> World.Line.state().now == 1 or (Process.sleep(10) && false) end)
      refute Task.yield(task, 300)
      send(holder, :go)
      Task.await(task, 60_000)
    end

    placed = behind.(fn -> post.("/orders", ~s({"blueprint": "strut", "options": {"length": 0.3}})) end)
    assert placed.status == 200
    hash = JSON.decode!(placed.resp_body)["hash"]

    edited = behind.(fn -> post.("/orders/#{hash}/edits", ~s({"edits": [{"set": "options.length", "to": 0.4}]})) end)
    assert edited.status == 200
    assert JSON.decode!(edited.resp_body)["hash"] != hash
  end
end
