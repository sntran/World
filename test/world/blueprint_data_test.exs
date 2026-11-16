defmodule World.BlueprintDataTest do
  # A blueprint in data of a project in an order, or by its hash after
  # POST /blueprints (plan 0002, D1): World builds any blueprint whose
  # skills it has.
  use ExUnit.Case, async: true
  import Plug.Test

  alias World.{MCP, Orders}
  alias World.Orders.Blueprint

  @house "priv/blueprints/tube_house.json" |> File.read!() |> JSON.decode!()

  defp call(method, path, body), do: conn(method, path, body) |> World.Service.call(World.Service.init([]))
  defp paths({:error, errors}), do: Enum.map(errors, & &1["path"])

  defp tool(name, args) do
    message = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => name, "arguments" => args}
    }

    {200, %{"result" => r}} = MCP.answer(JSON.encode!(message), nil, "https://world.mkfifo.com")
    r["structuredContent"]
  end

  test "a blueprint in data in an order: the people build it as the blueprint of World with the same data" do
    house = Map.put(@house, "name", "nha_cua_vung_tau")
    options = %{"floors" => 1, "width" => 5.0}
    assert {:ok, full} = Orders.check(%{"blueprint" => house, "options" => options})
    assert full["blueprint"] == house and full["options"]["width"] == 5.0

    {:ok, job} = Orders.job(%{"blueprint" => house, "options" => options}, "far")
    {:ok, ours} = Orders.job(%{"blueprint" => "tube_house", "options" => options}, "far")
    assert job.drawing == ours.drawing and job.hash != ours.hash
    {:ok, id} = World.build(job)
    assert {:ok, r} = World.await(id, 60_000)
    assert r.glb == World.GLB.encode(ours.scene.(ours.item.(:far), []))
  end

  test "the store keeps a blueprint in data, and an order gives its hash" do
    assert {:ok, %{"hash" => hash, "name" => "tube_house"}} = Orders.keep_blueprint(@house)
    assert {:ok, full} = Orders.check(%{"blueprint" => %{"hash" => hash}})
    assert full["blueprint"] == @house
    assert Orders.hash(full) == Orders.hash(elem(Orders.check(%{"blueprint" => @house}), 1))

    # Through the service and the Worker path.
    assert call(:post, "/blueprints", JSON.encode!(@house)).status == 201
    bad = call(:post, "/blueprints", JSON.encode!(%{"name" => "x"}))
    assert bad.status == 422
    assert JSON.decode!(bad.resp_body)["errors"] == [%{"path" => "blueprint.drawing", "message" => "is required"}]

    for h <- ["0123456789abcdef0123456789abcdef", "nope"] do
      assert paths(Orders.check(%{"blueprint" => %{"hash" => h}})) == ["blueprint.hash"]
    end
  end

  test "the errors of a blueprint in data, each with its path" do
    bad = %{
      "name" => "Bad Name",
      "x" => 1,
      "params" => [
        %{"name" => "w", "type" => "float"},
        %{"name" => "c", "type" => "choice"},
        %{"name" => "c2", "type" => "choice", "values" => [1]},
        %{"name" => "l", "type" => "list"},
        %{"name" => "l2", "type" => "list", "item" => %{"type" => "number", "y" => 2}},
        %{"name" => "o", "type" => "object", "fields" => [%{"type" => "number"}]},
        %{"name" => "o2", "type" => "object"},
        %{"name" => "s", "type" => "skill", "skill" => "nope"},
        %{"type" => "number"},
        %{"name" => "t"},
        3
      ],
      "drawing" => %{"nodes" => []}
    }

    assert Enum.map(Blueprint.check_data(bad, "blueprint"), &elem(&1, 0)) == [
             "blueprint.x",
             "blueprint.name",
             "blueprint.params.0.type",
             "blueprint.params.1.values",
             "blueprint.params.2.values",
             "blueprint.params.3.item",
             "blueprint.params.4.item.y",
             "blueprint.params.5.fields.0.name",
             "blueprint.params.6.fields",
             "blueprint.params.7.skill",
             "blueprint.params.8.name",
             "blueprint.params.9.type",
             "blueprint.params.10"
           ]

    assert Blueprint.check_data(%{"name" => "a", "params" => 1, "drawing" => 2}, "b") == [
             {"b.params", "must be a list"},
             {"b.drawing", "must be an object"}
           ]

    assert Blueprint.check_data([1], "b") == [{"b", "must be an object"}]
    assert Orders.keep_blueprint([1]) == {:error, [%{"path" => "blueprint", "message" => "must be an object"}]}

    # The data of a skill in the drawing, with the default of each param.
    wrong = %{
      "name" => "w",
      "params" => [%{"name" => "width", "type" => "number", "default" => 99}],
      "drawing" => %{
        "nodes" => [%{"name" => "plan", "skill" => %{"house_plan" => %{"width" => %{"param" => "width"}}}}]
      }
    }

    assert paths(Orders.check(%{"blueprint" => wrong})) == ["blueprint.drawing.nodes.0.skill.house_plan.width"]
    assert paths(Orders.check(%{"blueprint" => 3})) == ["blueprint"]
  end

  test "the example of docs/skills.md is a blueprint that the people build; the document has each skill" do
    doc = File.read!("docs/skills.md")
    [json] = Regex.run(~r/```json\n(.*?)```/s, doc, capture: :all_but_first)
    example = JSON.decode!(json)
    assert Blueprint.check_data(example, "blueprint") == []
    {:ok, job} = Orders.job(%{"blueprint" => example, "options" => %{"width" => 3.5}}, "far")
    {:ok, id} = World.build(job)
    assert {:ok, r} = World.await(id, 60_000)
    assert World.Log.check(r.log) == :ok
    # The skills of World (a test can add the toy skills of test/support).
    for n <- World.Skills.names(),
        {:ok, mod} = World.Skills.fetch(n),
        String.starts_with?(inspect(mod), "World.Skills."),
        do: assert(doc =~ "`#{n}`", n)
  end

  test "the MCP tool check_blueprint: the options, the hash and the plan, or the errors" do
    r = tool("check_blueprint", %{"blueprint" => @house})
    assert r["name"] == "tube_house" and r["hash"] == Orders.hash(@house)
    assert r["plan"]["trades"]["mason"] > 0

    # A param with no default: no plan before an order gives it.
    open = put_in(@house, ["params"], [%{"name" => "name", "type" => "text"} | tl(@house["params"])])
    assert tool("check_blueprint", %{"blueprint" => open})["plan"] == nil

    assert [%{"path" => "blueprint.name"}] =
             tool("check_blueprint", %{"blueprint" => %{"name" => "A", "drawing" => %{}}})["errors"]

    assert [%{"message" => "the argument \"blueprint\" must be a JSON object"}] = tool("check_blueprint", %{})["errors"]
  end
end

defmodule World.BlueprintStoreTest do
  use ExUnit.Case, async: false

  test "the store of the blueprints fails" do
    old = Application.get_env(:world, World.Orders.Store, [])
    Application.put_env(:world, World.Orders.Store, program: "/no/such/program")
    on_exit(fn -> Application.put_env(:world, World.Orders.Store, old) end)
    house = "priv/blueprints/tube_house.json" |> File.read!() |> JSON.decode!()
    assert World.Orders.keep_blueprint(house) == {:error, :store}

    assert {:error, [%{"path" => "blueprint.hash"}]} =
             World.Orders.check(%{"blueprint" => %{"hash" => String.duplicate("a", 32)}})

    conn = Plug.Test.conn(:post, "/blueprints", JSON.encode!(house)) |> World.Service.call(World.Service.init([]))
    assert conn.status == 503
  end
end
