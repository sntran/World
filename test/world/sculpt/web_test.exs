defmodule World.Sculpt.WebTest do
  # A live sculpture over MCP and HTTP (plan 0008, step 6). The live
  # sculptures of the node are one supervisor, so the tests are not async.
  use ExUnit.Case, async: false
  import Plug.Test

  alias World.{MCP, Service}
  alias World.Sculpt.Live

  @origin "https://world.mkfifo.com"

  defp tool(name, args) do
    message = %{
      "jsonrpc" => "2.0",
      "id" => 7,
      "method" => "tools/call",
      "params" => %{"name" => name, "arguments" => args}
    }

    {200, %{"result" => result}} = MCP.answer(JSON.encode!(message), nil, @origin)
    result
  end

  defp get(path), do: conn(:get, path) |> Service.call(Service.init([]))

  # The events of a stream of server-sent events.
  defp events(conn), do: for("data: " <> e <- String.split(conn.resp_body, "\n"), do: JSON.decode!(e))

  defp errors(result), do: Enum.map(result["structuredContent"]["errors"], & &1["path"])

  setup do
    World.Sculpt.Cache.clear()

    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(World.Sculptures),
          do: DynamicSupervisor.terminate_child(World.Sculptures, pid)
    end)

    :ok
  end

  @stone [
    %{"shape" => "ellipsoid", "size" => [0.4, 0.3, 0.25], "material" => "stone_wash"},
    %{"shape" => "ball", "size" => [0.1], "at" => [0.35, 0, 0], "blend" => 0.03}
  ]

  test "open a live sculpture, follow its pieces, change one edit, and close it" do
    r = tool("open_sculpture", %{"edits" => @stone, "level" => "mid"})
    assert %{"sculpture" => id, "version" => 0, "events" => events_url, "glb" => glb_url} = r["structuredContent"]
    assert events_url == "#{@origin}/sculptures/#{id}/events" and glb_url == "#{@origin}/sculptures/#{id}.glb"
    # The same edits open the same sculpture.
    assert tool("open_sculpture", %{"edits" => @stone, "level" => "mid"})["structuredContent"]["sculpture"] == id

    first = events(get("/sculptures/#{id}/events?until=0"))
    assert List.last(first)["kind"] in ~w(done state)
    pieces = for %{"kind" => "piece"} = p <- first, do: p
    assert pieces != []

    assert [%{"material" => "stone_wash", "points" => [[_, _, _] | _], "faces" => [[_, _, _] | _]} | _] =
             hd(pieces)["meshes"]

    # The GLB now, then a change: the new pieces and done.
    glb = get("/sculptures/#{id}.glb")
    assert glb.status == 200 and match?(<<"glTF", _::binary>>, glb.resp_body)
    edit = %{"shape" => "ball", "size" => [0.12], "at" => [-0.35, 0, 0], "blend" => 0.03, "material" => "gray"}

    assert %{"sculpture" => ^id, "version" => 1} =
             tool("edit_sculpture", %{"sculpture" => id, "index" => 2, "edit" => edit})["structuredContent"]

    change = events(get("/sculptures/#{id}/events?until=1"))
    assert %{"kind" => "done", "version" => 1} = List.last(change)
    assert Enum.any?(change, &(&1["kind"] == "piece" and Enum.any?(&1["meshes"], fn m -> m["material"] == "gray" end)))

    # A stream after the end of the version: the pieces now, and the state.
    again = events(get("/sculptures/#{id}/events?until=1"))
    assert %{"kind" => "state", "version" => 1, "busy" => false} = List.last(again)

    assert %{"closed" => true} = tool("close_sculpture", %{"sculpture" => id})["structuredContent"]
    assert get("/sculptures/#{id}.glb").status == 404
    assert get("/sculptures/#{id}/events").status == 404
    assert get("/sculptures/#{id}.obj").status == 404
  end

  test "a stream ends with closed when the sculpture stops; an edit taken away" do
    %{"sculpture" => id} =
      tool("open_sculpture", %{"edits" => @stone, "level" => "far", "name" => "rock"})["structuredContent"]

    assert id == "rock"
    events(get("/sculptures/rock/events?until=0"))

    assert %{"version" => 1} =
             tool("edit_sculpture", %{"sculpture" => "rock", "index" => 1, "edit" => nil})["structuredContent"]

    me = self()

    spawn(fn ->
      Process.sleep(200)
      send(me, :stop)
      Live.stop("rock")
    end)

    # A stream with no end of its own: it ends when the sculpture stops.
    e = events(get("/sculptures/rock/events"))
    assert_received :stop
    assert List.last(e) == %{"kind" => "closed"} and Enum.any?(e, &(&1 == %{"kind" => "done", "version" => 1}))
  end

  test "the errors of the tools, each with its path" do
    assert errors(tool("open_sculpture", %{})) == ["edits"]

    assert errors(
             tool("open_sculpture", %{
               "edits" => [%{"shape" => "egg", "size" => [1]}],
               "level" => "high",
               "name" => "A B"
             })
           ) ==
             ["edits.0.shape", "level", "name"]

    %{"sculpture" => id} = tool("open_sculpture", %{"edits" => @stone, "level" => "far"})["structuredContent"]

    assert errors(
             tool("edit_sculpture", %{"sculpture" => id, "index" => 0, "edit" => %{"shape" => "ball", "size" => [1, 2]}})
           ) == ["edit.size"]

    assert errors(tool("edit_sculpture", %{"sculpture" => id, "index" => 9, "edit" => nil})) == ["index"]
    assert errors(tool("edit_sculpture", %{"sculpture" => "nobody", "index" => 0, "edit" => nil})) == ["sculpture"]
    assert errors(tool("edit_sculpture", %{"sculpture" => id})) == [""]
    assert errors(tool("close_sculpture", %{"sculpture" => "nobody"})) == ["sculpture"]
    assert tool("edit_sculpture", %{"sculpture" => id, "index" => 0, "edit" => nil})["isError"] == nil
  end

  test "the node has at most its count of live sculptures; a ping keeps a stream open; the JSON of a failed work" do
    Application.put_env(:world, World.Sculpt.Web, most: 1)
    on_exit(fn -> Application.delete_env(:world, World.Sculpt.Web) end)
    %{"sculpture" => id} = tool("open_sculpture", %{"edits" => @stone, "level" => "far"})["structuredContent"]
    assert errors(tool("open_sculpture", %{"edits" => @stone, "level" => "mid"})) == [""]

    Application.put_env(:world, World.Stream, ping: 20)
    on_exit(fn -> Application.delete_env(:world, World.Stream) end)

    spawn(fn ->
      Process.sleep(100)
      Live.stop(id)
    end)

    conn = get("/sculptures/#{id}/events")
    assert conn.resp_body =~ ": ping\n\n"
    assert World.Sculpt.Web.json({:failed, 3, :boom}) == %{"kind" => "failed", "version" => 3, "reason" => ":boom"}
    assert World.Sculpt.Web.json({:gone, {1, -2, 3}}) == %{"kind" => "gone", "at" => [1, -2, 3]}
  end

  describe "on a real server" do
    setup do
      pid = start_supervised!({Bandit, plug: Service, port: 0, ip: {127, 0, 0, 1}, startup_log: false})
      {:ok, {_, port}} = ThousandIsland.listener_info(pid)
      %{port: port}
    end

    # A client of the stream of a sculpture that reads its first part, then goes.
    defp go_after_first(port, id) do
      {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: true])
      :ok = :gen_tcp.send(socket, "GET /sculptures/#{id}/events HTTP/1.1\r\nhost: world\r\n\r\n")

      wait = fn wait ->
        receive do: ({:tcp, ^socket, data} -> if(data =~ "state", do: :ok, else: wait.(wait))),
                after: (30_000 -> flunk("no stream"))
      end

      :ok = wait.(wait)
      [stream] = for {pid, _} <- Registry.lookup(World.Events, {:sculpture, id}), pid != self(), do: pid
      ref = Process.monitor(stream)
      :gen_tcp.close(socket)
      ref
    end

    test "a stream ends when its client goes: at the next ping, or at the next event", %{port: port} do
      %{"sculpture" => id} =
        tool("open_sculpture", %{"edits" => @stone, "level" => "mid", "name" => "gone"})["structuredContent"]

      events(get("/sculptures/gone/events?until=0"))

      Application.put_env(:world, World.Stream, ping: 50)
      ref = go_after_first(port, id)
      assert_receive {:DOWN, ^ref, :process, _, _}, 5_000

      Application.put_env(:world, World.Stream, ping: 60_000)
      on_exit(fn -> Application.delete_env(:world, World.Stream) end)
      ref = go_after_first(port, id)
      Process.sleep(100)
      big = %{"shape" => "ball", "size" => [0.5], "at" => [1.0, 0, 0]}
      tool("edit_sculpture", %{"sculpture" => id, "index" => 2, "edit" => big})
      assert_receive {:DOWN, ^ref, :process, _, _}, 30_000
    end
  end
end
