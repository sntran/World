defmodule World.StreamTest do
  # The constructions over HTTP: a job, its state, its stream and its
  # elements, and the stream of the world on a real server.
  use ExUnit.Case, async: false
  import Plug.Test

  alias World.Service

  @strut ~s({"blueprint": "strut", "options": {"length": 0.3}})

  defp call(method, path, body \\ nil, headers \\ []) do
    conn = conn(method, path, body)
    conn = Enum.reduce(headers, conn, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
    Service.call(conn, Service.init([]))
  end

  defp json(conn), do: JSON.decode!(conn.resp_body)

  # The events of a stream: the data of each message.
  defp events(body) do
    for "data: " <> data <- String.split(body, "\n"), do: JSON.decode!(data)
  end

  defp job(level, budget \\ %{}), do: ~s({"order": #{@strut}, "level": "#{level}", "budget": #{JSON.encode!(budget)}})

  test "POST /builds: a construction of the order, then its state, its stream and its elements" do
    conn = call(:post, "/builds", job("mid", %{"workers" => 2}))
    assert conn.status == 202
    %{"build" => id, "hash" => hash, "after" => after_id, "events" => events_url, "files" => files} = json(conn)
    assert id == "#{hash}-mid" and events_url == "/builds/#{id}/events?after=#{after_id}"
    assert files["glb"] =~ "/o/#{hash}.glb"

    # The stream of the construction ends with its end.
    stream = call(:get, events_url)
    assert stream.status == 200
    assert Plug.Conn.get_resp_header(stream, "content-type") == ["text/event-stream"]
    kinds = Enum.map(events(stream.resp_body), & &1["kind"])
    assert hd(kinds) == "requested" and List.last(kinds) == "done"

    # From an id: only the events after it.
    [first | _] = events(stream.resp_body)
    later = call(:get, "/builds/#{id}/events", nil, [{"last-event-id", "#{first["id"]}"}])
    refute first["id"] in Enum.map(events(later.resp_body), & &1["id"])

    # A wrong id to start after is the start.
    from_start = call(:get, "/builds/#{id}/events?after=soon")
    assert hd(events(from_start.resp_body))["kind"] == "requested"

    state = json(call(:get, "/builds/#{id}"))
    assert %{"status" => "done", "level" => "mid", "elements" => [element | _]} = state
    assert state["done"] == state["tasks"] and state["tasks"] > 0

    glb = call(:get, "/builds/#{id}/elements/#{element["glb"]}.glb")
    assert glb.status == 200
    assert <<"glTF", _::binary>> = glb.resp_body
    assert call(:get, "/builds/#{id}/elements/999.glb").status == 404
    assert call(:get, "/builds/#{id}/elements/x.glb").status == 404
    assert call(:get, "/builds/nothing/elements/0.glb").status == 404
    assert call(:get, "/builds/nothing").status == 404
  end

  test "POST /builds/ID/pause, change, resume and cancel" do
    blocks = fn size ->
      nodes = [
        %{"name" => "root", "skill" => %{"block" => %{"size" => size, "wait" => 2_000}}},
        %{"name" => "upper", "skill" => %{"block" => %{"size" => 0.5}}, "to" => "root", "at" => "top"}
      ]

      JSON.encode!(%{"order" => %{"blueprint" => "drawing", "options" => %{"drawing" => %{"nodes" => nodes}}}})
    end

    %{"build" => id} = json(call(:post, "/builds", blocks.(1.0)))
    World.watch(id)
    assert json(call(:post, "/builds/#{id}/pause")) == %{"build" => id, "asked" => "pause"}
    assert_receive {:world, %{"kind" => "paused"}}, 5_000
    assert json(call(:get, "/builds/#{id}"))["status"] == "paused"

    changed = call(:post, "/builds/#{id}/change", blocks.(2.0))
    assert changed.status == 200 and json(changed)["build"] == id

    one = %{
      "order" => %{
        "blueprint" => "drawing",
        "options" => %{
          "drawing" => %{
            "nodes" => [%{"name" => "root", "part" => "a"}],
            "parts" => %{"a" => %{"shapes" => [%{"box" => %{"from" => [0, 0, 0], "to" => [1, 1, 1]}}]}}
          }
        }
      }
    }

    assert call(:post, "/builds/#{id}/change", JSON.encode!(one)).status == 409
    assert call(:post, "/builds/#{id}/change", "{").status == 400
    assert call(:post, "/builds/#{id}/change", ~s({"order": {"blueprint": "ball"}})).status == 422
    assert call(:post, "/builds/#{id}/resume").status == 202
    # The resume is a message: the state changes with its event.
    assert_receive {:world, %{"kind" => "resumed"}}, 5_000
    assert json(call(:get, "/builds/#{id}"))["status"] == "building"
    assert {:ok, _} = World.await(id, 10_000)
    assert json(call(:get, "/builds/#{id}"))["status"] == "done"

    assert call(:post, "/builds/nothing/cancel").status == 404
    assert call(:post, "/builds/nothing/change", blocks.(2.0)).status == 404
  end

  test "POST /builds with accept: text/event-stream gives the stream of the construction at once" do
    conn = call(:post, "/builds", job("far"), [{"accept", "text/event-stream"}])
    assert conn.status == 200
    kinds = Enum.map(events(conn.resp_body), & &1["kind"])
    assert hd(kinds) == "requested" and "element" in kinds and List.last(kinds) == "done"
  end

  test "POST /builds refuses a wrong budget, a wrong order, a job with no order, and a store that fails" do
    conn =
      call(
        :post,
        "/builds",
        job("far", %{"workers" => 0, "seconds" => -1, "triangles" => 1.5, "money" => 3, "memory_mb" => 0})
      )

    assert conn.status == 422

    assert Enum.map(json(conn)["errors"], & &1["path"]) == [
             "budget.memory_mb",
             "budget.money",
             "budget.seconds",
             "budget.triangles",
             "budget.workers"
           ]

    assert call(:post, "/builds", ~s({"order": #{@strut}, "budget": 3})).status == 422
    assert [%{"path" => "level"}] = json(call(:post, "/builds", ~s({"order": #{@strut}, "level": "huge"})))["errors"]

    assert [%{"path" => "options.length"}] =
             json(call(:post, "/builds", ~s({"order": {"blueprint": "strut"}})))["errors"]

    assert [%{"path" => "order"}] = json(call(:post, "/builds", "{}"))["errors"]

    old = Application.get_env(:world, World.Orders.Store, [])
    Application.put_env(:world, World.Orders.Store, program: "/bin/false")
    on_exit(fn -> Application.put_env(:world, World.Orders.Store, old) end)
    assert call(:post, "/builds", job("far")).status == 503
    assert call(:post, "/builds/x/change", job("far")).status == 503

    # The tool build of the MCP server, with the same store.
    message = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/call"}
    params = %{"name" => "build", "arguments" => %{"order" => JSON.decode!(@strut)}}
    {200, %{"result" => r}} = World.MCP.answer(JSON.encode!(Map.put(message, "params", params)), nil, "https://x")
    assert r["isError"] == true and hd(r["content"])["text"] =~ "the store of the orders failed"
  end

  test "a budget of workers, seconds and triangles" do
    budget = %{"workers" => 2, "seconds" => 1.5, "triangles" => 100, "memory_mb" => 64}
    assert World.budget(budget) == {:ok, budget}
    assert World.budget(nil) == {:ok, %{}}
  end

  test "GET /census, /places and the ground of a place: the people of the node, the places of the yard" do
    assert %{"people" => _, "waiting" => _} = json(call(:get, "/census"))
    assert %{"places" => [%{"name" => "gate"} | _] = places, "speed_kmh" => 20} = json(call(:get, "/places"))

    assert [%{"terrain" => %{"ground" => ground, "lots" => [%{"name" => "top", "height" => _} | _]}}] =
             for(p <- places, p["terrain"], do: p)

    # The ground of the hill (plan 0006, D3): a GLB, made once.
    conn = call(:get, ground)
    assert conn.status == 200 and ["model/gltf-binary"] == Plug.Conn.get_resp_header(conn, "content-type")
    assert "glTF" <> _ = conn.resp_body
    assert call(:get, ground).resp_body == conn.resp_body
    assert call(:get, "/places/site/ground.glb").status == 404
    assert call(:get, "/places/moon/ground.glb").status == 404
  end

  describe "on a real server" do
    setup do
      Application.put_env(:world, World.Stream, ping: 50)
      on_exit(fn -> Application.delete_env(:world, World.Stream) end)
      pid = start_supervised!({Bandit, plug: Service, port: 0, ip: {127, 0, 0, 1}, startup_log: false})
      {:ok, {_, port}} = ThousandIsland.listener_info(pid)
      %{port: port}
    end

    # The next part of the response, from a socket in active mode.
    defp chunk(socket, timeout) do
      receive do
        {:tcp, ^socket, data} -> data
      after
        timeout -> flunk("no data on the stream")
      end
    end

    defp wait_for(socket, text) do
      data = chunk(socket, 30_000)
      if data =~ text, do: data, else: wait_for(socket, text)
    end

    test "GET /events: the stream of the world, a ping when nothing happens, and its end when the client goes", %{
      port: port
    } do
      last = World.Log.Server.last()
      {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: true])
      :ok = :gen_tcp.send(socket, "GET /events?after=#{last} HTTP/1.1\r\nhost: world\r\n\r\n")
      assert wait_for(socket, "text/event-stream") =~ "200"
      assert wait_for(socket, ": ping")

      # A new construction: its events come on the stream of the world.
      call(:post, "/builds", job("far"))
      assert wait_for(socket, "\"kind\":\"requested\"")

      # The client goes: the stream ends at its next ping.
      [stream] =
        for {pid, _} <- Registry.lookup(World.Events, :world), Process.get_label(pid) == {:stream, :world}, do: pid

      ref = Process.monitor(stream)
      :gen_tcp.close(socket)
      assert_receive {:DOWN, ^ref, :process, ^stream, _}, 5_000
    end
  end
end
