defmodule World.BenchTest do
  # The measure of the builds (plan 0007, D1 and R1).
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  alias World.Bench

  @moduletag :tmp_dir

  test "the orders: each model of the catalog (with the drawings), each blueprint in data; the orders of some names" do
    all = Bench.orders()
    assert length(all) == length(World.Catalog.models()) + length(World.Orders.Blueprints.data())
    assert length(all) == length(Enum.uniq_by(all, &elem(&1, 0)))
    assert Enum.all?(World.Drawing.names(), fn d -> Enum.any?(all, &(elem(&1, 0) == d)) end)
    assert {:ok, ^all} = Bench.select([])
    # In the order of all the orders.
    assert {:ok, [{"alpaca", "catalog", _}, {"tuong_chua_kito_vua", "catalog", _}, {"scooter", "blueprint", _}]} =
             Bench.select(["tuong_chua_kito_vua", "scooter", "alpaca"])

    assert {:error, ["nothing"]} = Bench.select(["alpaca", "nothing"])
  end

  test "a build that the people make, measured; a build that fails, stops, takes too long, or has a wrong order" do
    {:ok, [alpaca]} = Bench.select(["alpaca"])
    me = self()
    [built] = Bench.run([alpaca], level: "far", each: &send(me, {:each, &1}))
    assert_received {:each, ^built}
    assert %{"name" => "alpaca", "kind" => "catalog", "result" => "built"} = built
    assert built["ms"] >= 0 and built["peak_mb"] > 0 and built["busy"] >= 0 and built["cores"] >= 0
    assert built["tasks"] >= 1 and is_integer(built["elements"]) and built["triangles"] > 0 and built["bytes"] > 0
    # The scale of the world clock comes back after the measure.
    assert Application.get_env(:world, :scale) == 86_400_000

    # A heap of 1 MB for each person that makes a node: the work stops,
    # and the build fails.
    {:ok, [scooter]} = Bench.select(["scooter"])

    assert [%{"result" => "failed", "error" => "memory"}] =
             Bench.run([scooter], level: "far", budget: %{"memory_mb" => 1})

    # A deadline before the end: the build stops.
    assert [%{"result" => "stopped"}] = Bench.run([alpaca], level: "near", budget: %{"seconds" => 0.001})
    # No time to wait: the measure stops the build and goes on.
    {:ok, [statue]} = Bench.select(["tuong_chua_kito_vua"])
    assert [%{"result" => "timeout", "ms" => _}] = Bench.run([statue], timeout: 1)
    wrong = {"nothing", "catalog", %{"blueprint" => "catalog", "options" => %{"name" => "nothing"}}}
    assert [%{"result" => "order", "error" => _} = order] = Bench.run([wrong])

    lines = Bench.table([built, order])
    assert hd(lines) =~ ~r/^name +kind +result +ms +peak MB +busy +cores +tasks +triangles$/
    assert Enum.at(lines, 1) =~ ~r/^alpaca +catalog +built +\d+/
    assert Enum.at(lines, 2) =~ ~r/^nothing +catalog +order$/
    assert List.last(lines) == "1 of 2 built, #{built["ms"]} ms"
  end

  test "the triangles of a GLB: the indices of each primitive, or its points" do
    json =
      JSON.encode!(%{
        "accessors" => [%{"count" => 36}, %{"count" => 9}],
        "meshes" => [
          %{
            "primitives" => [
              %{"indices" => 0, "attributes" => %{"POSITION" => 1}},
              %{"attributes" => %{"POSITION" => 1}}
            ]
          }
        ]
      })

    glb = <<"glTF", 2::little-32, 0::little-32, byte_size(json)::little-32, "JSON", json::binary>>
    assert Bench.triangles(glb) == 12 + 3
  end

  test "mix world.bench: the table, the JSON, a wrong name", %{tmp_dir: dir} do
    out = Path.join(dir, "bench.json")
    io = capture_io(fn -> Mix.Tasks.World.Bench.run(["alpaca", "--level", "far", "--workers", "2", "--out", out]) end)
    assert io =~ "alpaca: built in " and io =~ "1 of 1 built, "
    assert [%{"name" => "alpaca", "result" => "built"}] = JSON.decode!(File.read!(out))
    assert_raise Mix.Error, ~r/Not a model or a blueprint: nothing/, fn -> Mix.Tasks.World.Bench.run(["nothing"]) end
  end
end
