defmodule World.OrdersAtlasTest do
  # (Not async: some tests change the wait of a build and the store, in the application environment.)
  use ExUnit.Case, async: false
  import Plug.Test

  alias World.{GLBHelper, Orders}
  alias World.Orders.{Set, Store}

  # A ball and a box with a bake at mid and far, in a color of its own.
  defp ball(color) do
    data = %{
      "edits" => [
        %{"shape" => "ball", "size" => [0.3], "color" => color},
        %{"shape" => "box", "size" => [0.2, 0.2, 0.2], "at" => [0, 0.3, 0], "color" => "#405060"}
      ],
      "cells" => %{"far" => 0.05, "mid" => 0.05},
      "budget" => %{"far" => 300, "mid" => 300},
      "bake" => %{"far" => 128, "mid" => 128}
    }

    drawing = %{"name" => "ball", "kind" => "item", "nodes" => [%{"name" => "ball", "skill" => %{"sculpt" => data}}]}
    %{"blueprint" => "drawing", "options" => %{"drawing" => drawing}}
  end

  defp call(conn), do: World.Service.call(conn, World.Service.init([]))

  # A hash that no other test has: the store of the tests keeps its files, and other tests ask for hashes
  # that it must not have.
  defp fresh, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  setup do
    wait = Application.get_env(:world, :part_wait)
    store = Application.get_env(:world, World.Orders.Store, [])

    on_exit(fn ->
      if wait, do: Application.put_env(:world, :part_wait, wait), else: Application.delete_env(:world, :part_wait)
      Application.put_env(:world, World.Orders.Store, store)
    end)
  end

  test "the keys atlas and images of an order: in the full order only when they change the files" do
    order = ball("#c08020")
    {:ok, plain} = Orders.check(order)
    refute Map.has_key?(plain, "atlas") or Map.has_key?(plain, "images")
    assert Orders.check(Map.merge(order, %{"atlas" => false, "images" => "png"})) == {:ok, plain}

    assert {:ok, %{"atlas" => true, "images" => "ktx2"} = full} =
             Orders.check(Map.merge(order, %{"atlas" => true, "images" => "ktx2"}))

    assert Orders.hash(full) != Orders.hash(plain)
    assert {:error, [%{"path" => "atlas"}]} = Orders.check(Map.put(order, "atlas", "yes"))
    assert {:error, [%{"path" => "images"}]} = Orders.check(Map.put(order, "images", "webp"))
  end

  test "the GLB of an order with an atlas, and with KTX2: the people build it, then its images are packed (R14, R16)" do
    json = fn order ->
      {:ok, glb} = Orders.build(order, "far", "glb")
      GLBHelper.json(glb)
    end

    plain = json.(ball("#c08020"))
    atlas = json.(Map.put(ball("#c08020"), "atlas", true))
    assert length(atlas["materials"]) <= length(plain["materials"]) and length(atlas["images"]) == 3
    assert Enum.any?(atlas["materials"], &String.starts_with?(&1["name"], "atlas"))

    assert length(for(m <- atlas["meshes"], p <- m["primitives"], do: p)) <=
             length(for(m <- plain["meshes"], p <- m["primitives"], do: p))

    packed = json.(Map.put(ball("#c08020"), "images", "ktx2"))

    assert packed["extensionsRequired"] == ["KHR_texture_basisu"] and
             length(packed["images"]) == length(plain["images"])

    both = json.(Map.merge(ball("#c08020"), %{"atlas" => true, "images" => "ktx2"}))
    assert Enum.all?(both["images"], &(&1["mimeType"] == "image/ktx2"))

    assert {:ok, %World.Scene{}} = Orders.scene(ball("#c08020"), "far")
    assert {:error, [%{"path" => "level"}]} = Orders.scene(ball("#c08020"), "high")
  end

  test "a set with an atlas: the store keeps it, and each variant has the URLs of its files with the atlas (D12)" do
    orders = [ball("#c08020"), ball("#2080c0")]
    {:ok, placed} = Set.place(%{"orders" => orders, "atlas" => true}, "https://w")
    hash = placed["set"]
    assert placed["atlas"] == true and placed["images"] == "png"

    for {v, i} <- Enum.with_index(placed["variants"]) do
      assert v["atlas"] == %{
               "glb" => "https://w/s/#{hash}/#{i}.glb",
               "mid.glb" => "https://w/s/#{hash}/#{i}.mid.glb",
               "far.glb" => "https://w/s/#{hash}/#{i}.far.glb"
             }

      assert v["files"]["far.glb"] == "https://w/o/#{v["hash"]}.far.glb"
    end

    {:ok, json} = Store.get_key(Store.set(hash))

    assert JSON.decode!(json) == %{
             "set" => Enum.map(placed["variants"], & &1["hash"]),
             "atlas" => true,
             "images" => "png"
           }

    # With no atlas: another hash, and no URLs of an atlas. With KTX2 and no atlas: each order has the key.
    {:ok, plain} = Set.place(%{"orders" => orders}, "https://w")
    assert plain["set"] != hash and not Map.has_key?(plain, "atlas")
    {:ok, ktx2} = Set.place(%{"orders" => orders, "images" => "ktx2"}, "https://w")
    assert Enum.all?(ktx2["variants"], &(&1["order"]["images"] == "ktx2")) and ktx2["set"] != plain["set"]

    assert {:error, [%{"path" => "atlas"}]} = Set.place(%{"orders" => orders, "atlas" => 1}, "https://w")
    assert {:error, [%{"path" => "images"}]} = Set.place(%{"orders" => orders, "images" => "gif"}, "https://w")
  end

  test "the files of a set with an atlas at a level: a GLB for each variant with no image, and the images one time" do
    {:ok, placed} = Set.place(%{"orders" => [ball("#c08020"), ball("#2080c0")], "atlas" => true}, "https://w")
    hash = placed["set"]
    {:ok, files} = Set.files(hash, "far")
    names = for {name, _} <- files, do: name

    assert names -- ["#{hash}/0.far.glb", "#{hash}/1.far.glb"] ==
             for(m <- ~w(finish color normal), do: "#{hash}.far.#{m}.png")

    for i <- [0, 1] do
      json = GLBHelper.json(List.keyfind(files, "#{hash}/#{i}.far.glb", 0) |> elem(1))

      assert Enum.sort(for(img <- json["images"], do: img["uri"])) ==
               for(m <- ~w(color finish normal), do: "../#{hash}.far.#{m}.png")
    end

    for name <- names, do: assert(Set.name(name) == {:ok, hash, "far"})
    assert Set.name("#{hash}/3.glb") == {:ok, hash, "near"} and Set.name("#{hash}.mid.glow.ktx2") == {:ok, hash, "mid"}
    assert Set.name("#{hash}.far.color.gif") == :error and Set.name("#{hash}/0.high.glb") == :error

    # No such set; a set with a variant that the store does not have; a variant whose order is not good.
    assert Set.files(fresh(), "far") == :none
    lost = fresh()

    :ok =
      Store.put_key(
        Store.set(lost),
        Orders.encode(%{"set" => [fresh()], "atlas" => true, "images" => "png"})
      )

    assert Set.files(lost, "far") == :none
    {bad, order} = {fresh(), fresh()}
    :ok = Store.put(order, ~s({"blueprint": "none"}))

    :ok =
      Store.put_key(
        Store.set(bad),
        Orders.encode(%{"set" => [order], "atlas" => true, "images" => "png"})
      )

    assert {:error, [%{"path" => "blueprint"}]} = Set.files(bad, "far")

    # With KTX2.
    {:ok, ktx2} = Set.place(%{"orders" => [ball("#c08020")], "atlas" => true, "images" => "ktx2"}, "https://w")
    {:ok, files} = Set.files(ktx2["set"], "far")
    assert Enum.count(files, fn {name, _} -> String.ends_with?(name, ".ktx2") end) == 3
    assert GLBHelper.json(elem(hd(files), 1))["extensionsRequired"] == ["KHR_texture_basisu"]
  end

  test "people as a set with one atlas (plan 0021, R7): each GLB keeps its skin and its clips, and the atlas" do
    person = fn options -> %{"blueprint" => "person", "options" => Map.put(options, "animations", ["walk", "idle"])} end
    orders = [person.(%{"gender" => 1.0, "age" => 30}), person.(%{"gender" => 0.0, "age" => 62})]
    {:ok, placed} = Set.place(%{"orders" => orders, "atlas" => true}, "https://w")
    hash = placed["set"]
    {:ok, files} = Set.files(hash, "far")
    glbs = for {name, bin} <- files, String.ends_with?(name, ".glb"), do: bin
    # (The maps of the atlas, each one time for the set.)
    pngs = for {name, _} <- files, String.ends_with?(name, ".png"), do: name
    assert length(glbs) == 2 and "#{hash}.far.color.png" in pngs
    assert Enum.all?(pngs, &(&1 =~ ~r/^#{hash}\.far\.(color|normal|finish|glow)\.png$/))

    for bin <- glbs do
      json = GLBHelper.json(bin)
      assert [_] = json["skins"]
      assert ["walk", "idle"] -- Enum.map(json["animations"], & &1["name"]) == []
      {urls, own} = Enum.split_with(json["images"], & &1["uri"])
      assert urls != [] and Enum.all?(urls, &(String.replace_prefix(&1["uri"], "../", "") in pngs))
      # (The picture of the skin is a JPEG: the atlas takes the PNG pictures, so it stays in the GLB of each person.)
      assert Enum.map(own, & &1["mimeType"]) == ["image/jpeg"]
    end
  end

  test "POST /set for the Worker, and GET /s/ of the server on a computer" do
    {:ok, placed} = Set.place(%{"orders" => [ball("#c08020"), ball("#2080c0")], "atlas" => true}, "https://w")
    hash = placed["set"]

    # The Worker: all of the files of the level in one answer, with their names and sizes.
    conn = call(conn(:post, "/set?name=#{hash}/1.far.glb", ""))
    assert conn.status == 200
    [index] = Plug.Conn.get_resp_header(conn, "x-world-files")

    sizes =
      for pair <- String.split(index, ","), [name, size] = String.split(pair, " "), do: {name, String.to_integer(size)}

    assert length(sizes) == 5 and Enum.sum(for {_, s} <- sizes, do: s) == byte_size(conn.resp_body)
    assert call(conn(:post, "/set?name=nothing", "")).status == 404

    # The server on a computer: each file, then from the files of the node.
    glb = call(conn(:get, "/s/#{hash}/0.far.glb"))
    assert glb.status == 200 and Plug.Conn.get_resp_header(glb, "content-type") == ["model/gltf-binary"]
    png = call(conn(:get, "/s/#{hash}.far.color.png"))
    assert png.status == 200 and Plug.Conn.get_resp_header(png, "content-type") == ["image/png"]
    assert call(conn(:get, "/s/#{hash}/0.far.glb")).resp_body == glb.resp_body
    assert call(conn(:get, "/s/#{hash}.far.glow.png")).status == 404
    assert call(conn(:get, "/s/#{fresh()}/0.far.glb")).status == 404
    assert call(conn(:get, "/s/nothing.glb")).status == 404

    # A variant whose order is not good: 422.
    {bad, order} = {fresh(), fresh()}
    :ok = Store.put(order, ~s({"blueprint": "none"}))

    :ok =
      Store.put_key(
        Store.set(bad),
        Orders.encode(%{"set" => [order], "atlas" => true, "images" => "png"})
      )

    assert call(conn(:post, "/set?name=#{bad}/0.far.glb", "")).status == 422
    assert call(conn(:get, "/s/#{bad}/0.far.glb")).status == 422
  end

  test "the files of a set build one time for all of their requests: 202 while they build, 500 when the build stops" do
    {:ok, placed} = Set.place(%{"orders" => [ball("#c08020")], "atlas" => true}, "https://w")
    hash = placed["set"]

    # (A build of the files of the level that waits: each request joins it.)
    {:new, builder} = World.Elements.start({:set, hash, "mid"}, fn -> receive(do: (:never -> :ok)) end)
    Application.put_env(:world, :part_wait, 0)
    conn = call(conn(:get, "/s/#{hash}/0.mid.glb"))
    assert conn.status == 202 and Plug.Conn.get_resp_header(conn, "retry-after") == ["15"]
    assert call(conn(:post, "/set?name=#{hash}.mid.color.png", "")).status == 202

    Application.put_env(:world, :part_wait, 600_000)
    request = Task.async(fn -> call(conn(:get, "/s/#{hash}/0.mid.glb")) end)
    # (When the request waits for the build, the build stops.)
    assert Enum.find(1..2000, fn _ ->
             Process.info(builder, :monitored_by) |> elem(1) != [] or (Process.sleep(5) && false)
           end)

    Process.exit(builder, :kill)
    assert Task.await(request).status == 500

    # A new request builds the files again.
    assert call(conn(:get, "/s/#{hash}/0.mid.glb")).status == 200
  end

  test "the files of a set that need more memory than the factory has: 422, and the VM goes on" do
    {:ok, placed} = Set.place(%{"orders" => [ball("#c08020")], "atlas" => true}, "https://w")
    memory = Application.get_env(:world, :memory_mb)
    Application.put_env(:world, :memory_mb, 1)

    on_exit(fn ->
      if memory, do: Application.put_env(:world, :memory_mb, memory), else: Application.delete_env(:world, :memory_mb)
    end)

    assert {:error, [%{"message" => "needs more memory than the factory has (1 MB)" <> _}]} =
             Set.files(placed["set"], "far")

    Application.delete_env(:world, :memory_mb)
    assert {:ok, [_, _, _, _]} = Set.files(placed["set"], "far")
  end

  test "the store fails: 503" do
    {:ok, placed} = Set.place(%{"orders" => [ball("#c08020")], "atlas" => true}, "https://w")
    Application.put_env(:world, World.Orders.Store, program: "/no/such/program")
    assert Set.place(%{"orders" => [ball("#2080c0")], "atlas" => true}, "https://w") == {:error, :store}
    assert Set.files(placed["set"], "far") == {:error, :store}
    assert call(conn(:post, "/set?name=#{placed["set"]}/0.far.glb", "")).status == 503
    assert call(conn(:get, "/s/#{placed["set"]}/0.near.glb")).status == 404
    assert call(conn(:get, "/s/#{placed["set"]}/0.glb")).status == 503
  end
end
