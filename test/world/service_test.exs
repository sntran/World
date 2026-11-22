defmodule World.ServiceTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias World.Service

  defp call(method, path, body \\ nil) do
    conn(method, path, body) |> Service.call(Service.init([]))
  end

  defp json(conn), do: JSON.decode!(conn.resp_body)

  @strut ~s({"blueprint": "strut", "options": {"length": 0.3}})

  test "GET /blueprints" do
    conn = call(:get, "/blueprints")
    assert conn.status == 200
    assert "house" in Enum.map(json(conn), & &1["name"])
  end

  test "POST /check" do
    conn = call(:post, "/check", @strut)
    assert conn.status == 200
    assert %{"hash" => _, "order" => %{"options" => %{"kind" => "slotted", "length" => 0.3}}} = json(conn)

    conn = call(:post, "/check", ~s({"blueprint": "strut"}))
    assert conn.status == 422
    assert [%{"path" => "options.length"}] = json(conn)["errors"]

    assert call(:post, "/check", "nope").status == 400
    assert call(:post, "/check", String.duplicate(" ", 1_100_000)).status == 413
  end

  test "POST /earth/heights: the heights of the real Earth at the points of a project" do
    conn = call(:post, "/earth/heights", ~s({"points": [[27.99, 86.93], [11.35, 142.2]]}))
    assert conn.status == 200
    assert %{"heights" => [high, deep], "unit" => "m", "source" => "ETOPO1" <> _} = json(conn)
    assert high > 5000 and deep < -8000

    conn = call(:post, "/earth/heights", ~s({"points": [[100, 0]]}))
    assert conn.status == 422
    assert [%{"path" => "points.0"}] = json(conn)["errors"]
    assert [%{"path" => "points"}] = json(call(:post, "/earth/heights", "[1]"))["errors"]
  end

  test "POST /build: each file, and the errors" do
    glb = call(:post, "/build?level=far", @strut)
    assert glb.status == 200
    assert <<"glTF", _::binary>> = glb.resp_body
    assert Plug.Conn.get_resp_header(glb, "content-type") == ["model/gltf-binary"]
    # The hash of the full order, as /check gives it.
    hash = json(call(:post, "/check", @strut))["hash"]
    assert Plug.Conn.get_resp_header(glb, "x-world-order") == [hash]

    receipt = call(:post, "/build?level=far&file=receipt", @strut)
    assert json(receipt)["level"] == "far"
    assert json(call(:post, "/build?level=far&file=parts", @strut))["parts"] != []

    log = call(:post, "/build?level=far&file=log", @strut)
    assert Plug.Conn.get_resp_header(log, "content-type") == ["application/json"]
    assert {:ok, _} = World.Log.from_json(log.resp_body)

    replay = call(:post, "/build?level=far&file=replay", @strut)
    assert Plug.Conn.get_resp_header(replay, "content-type") == ["model/gltf-binary"]
    assert <<"glTF", _::binary>> = replay.resp_body

    assert [
             %{
               "path" => "file",
               "message" => "must be one of: glb, log, replay, parts, receipt, solids, flat, light, drawing, elements"
             }
           ] =
             json(call(:post, "/build?file=zip", @strut))["errors"]

    assert [%{"path" => "level"}] = json(call(:post, "/build?level=huge", @strut))["errors"]
  end

  test "an order of Phượt (a traveler) gives its files and its log, and the times agree" do
    order = ~s({"blueprint": "traveler", "options": {"vehicle": "motorbike"}})
    assert <<"glTF", _::binary>> = call(:post, "/build?level=far", order).resp_body

    log = call(:post, "/build?level=far&file=log", order)
    assert ["build;dur=" <> ms] = Plug.Conn.get_resp_header(log, "server-timing")
    {:ok, l} = World.Log.from_json(log.resp_body)
    assert World.Log.check(l) == :ok
    events = World.Log.events(l)
    first = hd(events)
    done = Enum.find(events, &(&1.kind == "done"))

    # The run is in the time of the build in the service, and the events
    # of the order are in the time of the run.
    assert %{kind: "run_done", data: %{"ms" => run, "memory_peak" => peak, "memory_end" => memory}} = List.last(events)
    assert run <= String.to_integer(ms)
    # (Each time is a whole count of ms: the two can be 1 ms apart.)
    assert done.wall - first.wall <= run + 1
    assert peak >= memory and memory > 0
    assert List.last(events).data["memory"] == "total"
  end

  test "two builds at one time: the second waits for the first, and each gives its file" do
    builds =
      for length <- [0.3, 0.4],
          do:
            Task.async(fn ->
              call(:post, "/build?level=far", ~s({"blueprint": "strut", "options": {"length": #{length}}}))
            end)

    # (Since #76 the checks of the orders of the other tests go through the same line of the builds.)
    assert [%{status: 200}, %{status: 200}] = Task.await_many(builds, 600_000)
  end

  test "POST /orders keeps the full order and gives the URLs of its files, from x-world-origin" do
    conn =
      conn(:post, "/orders", @strut)
      |> Plug.Conn.put_req_header("x-world-origin", "https://world.mkfifo.com")
      |> Service.call(Service.init([]))

    assert conn.status == 200
    %{"hash" => hash, "files" => files, "replay" => replay} = json(conn)
    assert files["mid.glb"] == "https://world.mkfifo.com/o/#{hash}.mid.glb"
    assert replay == "https://world.mkfifo.com/replay.html?order=#{hash}"

    # With no x-world-origin, the URLs start with this server.
    assert json(call(:post, "/orders", @strut))["files"]["glb"] == "http://www.example.com:80/o/#{hash}.glb"

    assert call(:post, "/orders", ~s({"blueprint": "strut"})).status == 422
    assert call(:post, "/orders", "nope").status == 400
  end

  test "POST /orders/HASH/edits: small changes to an order of the store give a new order with its history" do
    %{"hash" => hash} = json(call(:post, "/orders", @strut))

    conn =
      conn(:post, "/orders/#{hash}/edits", ~s({"edits": [{"set": "options.length", "to": 0.45}]}))
      |> Plug.Conn.put_req_header("x-world-origin", "https://world.mkfifo.com")
      |> Service.call(Service.init([]))

    assert conn.status == 200
    %{"hash" => new, "parent" => ^hash, "history" => history, "files" => files, "order" => order} = json(conn)
    assert new != hash and order["options"]["length"] == 0.45
    assert history == [%{"hash" => hash}, %{"hash" => new, "edits" => [%{"set" => "options.length", "to" => 0.45}]}]
    assert files["glb"] == "https://world.mkfifo.com/o/#{new}.glb"
    assert call(:get, "/o/#{new}.far.glb").status == 200
    # (A strut comes from the code of a rule: it is the one node of its drawing. A model of the catalog with
    # a drawing gives that drawing.)
    assert %{"nodes" => [%{"name" => "model", "item" => %{"blueprint" => "strut"}}]} =
             json(call(:get, "/o/#{new}.drawing.json"))

    drawing = call(:get, "/m/catalog.drawing.json?name=cay_bang")
    assert drawing.status == 200 and header(drawing, "content-type") == "application/json"
    assert %{"name" => "cay_bang", "nodes" => [_ | _]} = json(drawing)

    # A length that the rule refuses, an edit that is not possible, a body with no edits, an order that is not there.
    wrong = call(:post, "/orders/#{hash}/edits", ~s({"edits": [{"set": "options.length", "to": -1}]}))
    assert wrong.status == 422
    assert [%{"path" => "options.length"}] = json(wrong)["errors"]
    wrong = call(:post, "/orders/#{hash}/edits", ~s({"edits": [{"remove": "options.width"}]}))
    assert wrong.status == 422
    assert [%{"path" => "edits.0"}] = json(wrong)["errors"]
    assert [%{"path" => "edits"}] = json(call(:post, "/orders/#{hash}/edits", "[1]"))["errors"]
    assert [%{"path" => "edits"}] = json(call(:post, "/orders/#{hash}/edits", "{}"))["errors"]
    assert call(:post, "/orders/#{hash}/edits", "nope").status == 400
    gone = call(:post, "/orders/#{String.duplicate("0", 32)}/edits", ~s({"edits": [{"remove": "options.length"}]}))
    assert gone.status == 404
    assert [%{"path" => "order"}] = json(gone)["errors"]
  end

  test "POST /build of a hash: 404 for an order that is not in the store, or for a wrong hash" do
    assert json(call(:post, "/build?hash=ffffffffffffffffffffffffffffffff", ""))["errors"] ==
             [%{"path" => "", "message" => "no such order: send it to POST /orders"}]

    assert call(:post, "/build?hash=../../x", "").status == 404
  end

  test "/mcp: one JSON-RPC message for each POST, 202 for a notification, 405 for the other methods" do
    ping = ~s({"jsonrpc":"2.0","id":1,"method":"ping"})
    conn = call(:post, "/mcp", ping)
    assert conn.status == 200
    assert json(conn) == %{"jsonrpc" => "2.0", "id" => 1, "result" => %{}}
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["application/json"]

    old =
      conn(:post, "/mcp", ping)
      |> Plug.Conn.put_req_header("mcp-protocol-version", "1999-01-01")
      |> Service.call(Service.init([]))

    assert old.status == 400

    notified = call(:post, "/mcp", ~s({"jsonrpc":"2.0","method":"notifications/initialized"}))
    assert {notified.status, notified.resp_body} == {202, ""}

    assert call(:post, "/mcp", String.duplicate(" ", 1_100_000)).status == 413

    for method <- [:get, :delete] do
      conn = call(method, "/mcp")
      assert conn.status == 405
      assert Plug.Conn.get_resp_header(conn, "allow") == ["POST"]
    end
  end

  defp header(conn, name), do: conn |> Plug.Conn.get_resp_header(name) |> List.first()

  test "GET /m/: a file of an order in the URL, from the store of the node after its first build" do
    conn = call(:get, "/m/strut.glb?length=0.31")
    assert conn.status == 200 and header(conn, "content-type") == "model/gltf-binary"
    assert <<"glTF", _::binary>> = conn.resp_body
    {:ok, full} = World.Orders.check(%{"blueprint" => "strut", "options" => %{"length" => 0.31}})
    hash = World.Orders.hash(full)
    assert header(conn, "x-world-order") == hash and header(conn, "x-world-version") == World.Files.version()

    assert header(conn, "cache-control") =~ "stale-while-revalidate" and
             header(conn, "access-control-allow-origin") == "*"

    etag = header(conn, "etag")
    assert {:ok, %{body: body, etag: ^etag}} = World.Files.get(hash, "near", "glb")
    assert body == conn.resp_body

    # The second request reads the store; the same ETag gives 304; a client that takes gzip gets gzip.
    again = call(:get, "/m/strut.glb?length=0.31")
    assert again.resp_body == body and header(again, "x-world-stale") == nil

    same =
      conn(:get, "/m/strut.glb?length=0.31")
      |> Plug.Conn.put_req_header("if-none-match", etag)
      |> Service.call(Service.init([]))

    assert same.status == 304 and same.resp_body == ""

    small =
      conn(:get, "/m/strut.glb?length=0.31")
      |> Plug.Conn.put_req_header("accept-encoding", "gzip, br")
      |> Service.call(Service.init([]))

    assert header(small, "content-encoding") == "gzip" and :zlib.gunzip(small.resp_body) == body

    # The other files and levels of the order; a build of a batch, by the query or by the header.
    parts = call(:get, "/m/strut.parts.json?length=0.31&class=batch")
    assert parts.status == 200 and header(parts, "content-type") == "application/json" and is_map(json(parts))

    far =
      conn(:get, "/m/strut.far.glb?length=0.31")
      |> Plug.Conn.put_req_header("x-world-class", "batch")
      |> Service.call(Service.init([]))

    assert far.status == 200 and header(far, "x-world-order") == hash
    assert %{"parts" => _} = json(call(:get, "/m/strut.solids.json?length=0.31"))
  end

  test "GET /m/: the colors, the joints, the targets and the fields of an option in the URL, and the errors" do
    assert call(:get, "/m/strut.far.glb?length=0.33&color.steel=%23ff0000").status == 200
    # (A field of an option that is an object: the origin of a person.)
    person = call(:get, "/m/person.far.glb?age=9&origin.asian=1&origin.african=0")
    assert person.status == 200
    assert <<"glTF", _::binary>> = person.resp_body

    assert [%{"path" => "options.length"}] = json(call(:get, "/m/strut.glb"))["errors"]
    assert [%{"path" => "joints.lid"}] = json(call(:get, "/m/strut.far.glb?length=0.3&joint.lid=10"))["errors"]
    assert call(:get, "/m/strut.far.glb?length=0.3&joint.lid=open").status == 422

    assert [%{"path" => "targets.arm_l"}] =
             json(call(:get, "/m/strut.far.glb?length=0.3&target.arm_l=0.1,0.2,0.3"))["errors"]

    # The flat look of a level, with a budget of triangles: a file of its own in the store.
    flat = call(:get, "/m/strut.far.flat.glb?length=0.36")
    assert flat.status == 200 and header(flat, "content-type") == "model/gltf-binary"
    less = call(:get, "/m/strut.far.flat.glb?length=0.36&triangles=40")
    assert less.status == 200 and byte_size(less.resp_body) < byte_size(flat.resp_body)
    assert header(less, "x-world-order") == header(flat, "x-world-order")
    assert [%{"path" => "triangles"}] = json(call(:get, "/m/strut.far.flat.glb?length=0.36&triangles=many"))["errors"]

    # The light look (a primitive for each role), and a wrap: each a file of its own in the store, of one order.
    light = call(:get, "/m/strut.far.light.glb?length=0.36")
    assert light.status == 200 and header(light, "content-type") == "model/gltf-binary"
    assert header(light, "x-world-order") == header(flat, "x-world-order")
    wrap = call(:get, "/m/strut.far.light.glb?length=0.36&triangles=60&wrap=1")
    assert wrap.status == 200 and wrap.resp_body != light.resp_body
    assert header(wrap, "x-world-order") == header(flat, "x-world-order")
    hash = header(flat, "x-world-order")
    assert {:ok, _} = World.Files.get(hash, "far", "light.60.wrap")
    assert {:ok, _} = World.Files.get(hash, "far", "light")
    assert {:ok, _} = World.Files.get(hash, "far", "flat.40")
    assert call(:get, "/m/strut.txt?length=0.3").status == 404
    assert call(:get, "/m/.glb").status == 404
  end

  test "GET /o/: a file of an order of POST /orders; a stale file goes out at once and the node builds it again" do
    placed = json(call(:post, "/orders", ~s({"blueprint": "strut", "options": {"length": 0.34}})))
    hash = placed["hash"]
    conn = call(:get, "/o/#{hash}.far.glb")
    assert conn.status == 200 and header(conn, "x-world-order") == hash
    assert call(:get, "/o/#{hash}.txt").status == 404
    assert call(:get, "/o/short.glb").status == 404
    assert call(:get, "/o/#{String.duplicate("0", 32)}.glb").status == 404

    # A file of an older version of World: the same bytes at once, with a mark, then a new build one time.
    meta = Path.join(World.Files.dir(), "#{hash}.far.glb.meta")
    File.write!(meta, JSON.encode!(%{"etag" => header(conn, "etag"), "version" => "000000000000"}))
    stale = call(:get, "/o/#{hash}.far.glb")
    assert stale.status == 200 and stale.resp_body == conn.resp_body
    assert header(stale, "x-world-stale") == "true" and header(stale, "x-world-version") == "000000000000"
    call(:get, "/o/#{hash}.far.glb")

    wait = fn wait, n ->
      case World.Files.get(hash, "far", "glb") do
        {:ok, entry} when n == 0 -> entry
        {:ok, %{version: "000000000000"}} -> Process.sleep(50) && wait.(wait, n - 1)
        {:ok, entry} -> entry
      end
    end

    assert World.Files.fresh?(wait.(wait, 400))
    assert header(call(:get, "/o/#{hash}.far.glb"), "x-world-stale") == nil
  end

  @tag :tmp_dir
  test "the files of the site, when the node has a site; OPTIONS gives the headers of CORS", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "index.html"), "<p>World</p>")
    File.mkdir_p!(Path.join(dir, "kit"))
    File.write!(Path.join(dir, "kit/kit.json"), "{}")
    Application.put_env(:world, :site, dir)
    on_exit(fn -> Application.delete_env(:world, :site) end)

    home = call(:get, "/")
    assert home.status == 200 and home.resp_body == "<p>World</p>" and header(home, "content-type") == "text/html"
    kit = call(:get, "/kit/kit.json")

    assert kit.status == 200 and header(kit, "content-type") == "application/json" and
             header(kit, "cache-control") =~ "max-age"

    assert call(:get, "/kit/none.json").status == 404
    assert call(:get, "/kit/..%2Findex.html").status == 404
    assert call(:post, "/kit/kit.json").status == 404

    options = call(:options, "/orders")
    assert options.status == 204 and header(options, "access-control-allow-methods") == "GET, POST, OPTIONS"
    assert header(options, "access-control-max-age") == "86400"
  end

  test "a page that is not there" do
    assert call(:get, "/nope").status == 404
  end
end
