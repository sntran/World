defmodule Xuong.ServiceTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias Xuong.Service

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

  test "POST /build: each file, and the errors" do
    glb = call(:post, "/build?level=far", @strut)
    assert glb.status == 200
    assert <<"glTF", _::binary>> = glb.resp_body
    assert Plug.Conn.get_resp_header(glb, "content-type") == ["model/gltf-binary"]

    receipt = call(:post, "/build?level=far&file=receipt", @strut)
    assert json(receipt)["level"] == "far"
    assert json(call(:post, "/build?level=far&file=parts", @strut))["parts"] != []

    assert [%{"path" => "file"}] = json(call(:post, "/build?file=zip", @strut))["errors"]
    assert [%{"path" => "level"}] = json(call(:post, "/build?level=huge", @strut))["errors"]
  end

  test "a page that is not there" do
    assert call(:get, "/nope").status == 404
  end

  test "the application starts the server only with XUONG_SERVER" do
    assert Xuong.Application.children(%{}) == []
    [{Bandit, opts}] = Xuong.Application.children(%{"XUONG_SERVER" => "true", "PORT" => "4100"})
    assert opts[:plug] == Service and opts[:port] == 4100
    [{Bandit, opts}] = Xuong.Application.children(%{"XUONG_SERVER" => "true"})
    assert opts[:port] == 4000
  end
end
