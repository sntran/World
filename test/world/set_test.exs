defmodule World.Orders.SetTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias World.Orders.Set

  @house %{"blueprint" => "lot_house", "options" => %{"floors" => 2}}
  @strut %{"blueprint" => "strut", "options" => %{"length" => 0.3}}

  test "a set from one order: the variants by seed, the values of vary, the same set gives the same orders" do
    set = %{
      "order" => @house,
      "count" => 6,
      "seed" => 7,
      "vary" => %{"depth" => [12.0, 16.0, 20.0], "roof" => ["flat", "clay"]}
    }

    assert {:ok, orders} = Set.check(set)
    assert length(orders) == 6
    assert Enum.map(orders, & &1["options"]["seed"]) == Enum.to_list(7000..7005)
    assert Enum.all?(orders, &(&1["options"]["floors"] == 2 and &1["options"]["depth"] in [12.0, 16.0, 20.0]))
    assert orders |> Enum.map(& &1["options"]["roof"]) |> Enum.uniq() |> length() > 1
    assert Set.check(set) == {:ok, orders}

    # A seed in the base stays; a blueprint with no seed gets none.
    {:ok, fixed} = Set.check(%{"order" => put_in(@house, ["options", "seed"], 3), "count" => 2})
    assert Enum.map(fixed, & &1["options"]["seed"]) == [3, 3]
    {:ok, [strut]} = Set.check(%{"order" => @strut})
    refute Map.has_key?(strut["options"], "seed")
    assert {:error, [%{"path" => "variants.0.blueprint"}]} = Set.check(%{"order" => %{"blueprint" => "none"}})
  end

  test "a set from a list of orders, and the errors of a set" do
    assert {:ok, [_, _]} = Set.check(%{"orders" => [@house, @strut]})

    for {set, path} <- [
          {%{"orders" => []}, "orders"},
          {%{"orders" => List.duplicate(@strut, Set.max() + 1)}, "orders"},
          {%{"orders" => [@strut, %{"blueprint" => "strut"}]}, "orders.1.options.length"},
          {%{"order" => @house, "count" => 0}, "count"},
          {%{"order" => @house, "seed" => "x"}, "seed"},
          {%{"order" => @house, "vary" => %{"depth" => []}}, "vary"},
          {%{"order" => @house, "vary" => %{"width" => [9.0]}}, "variants.0.options.width"},
          {%{"nothing" => 1}, ""},
          {%{"orders" => ["x"]}, "orders.0"},
          {%{"order" => %{"options" => %{}}}, "variants.0.blueprint"}
        ] do
      assert {:error, [%{"path" => ^path} | _]} = Set.check(set)
    end
  end

  test "a set is placed: each variant with its hash, its files and its lot; the set has a hash" do
    set = %{"order" => @house, "count" => 3, "seed" => 1, "vary" => %{"width" => [3.5, 4.0, 5.0]}}
    assert {:ok, %{"set" => hash, "variants" => variants}} = Set.place(set, "https://world.example")
    assert hash =~ ~r/^[0-9a-f]{32}$/
    assert length(variants) == 3

    for v <- variants do
      assert v["files"]["far.glb"] == "https://world.example/o/#{v["hash"]}.far.glb"
      assert v["lot"] == %{"width" => v["order"]["options"]["width"], "depth" => 16.0}
    end

    assert {:ok, %{"set" => ^hash}} = Set.place(set, "https://world.example")
    {:ok, %{"variants" => [strut]}} = Set.place(%{"orders" => [@strut]}, "https://world.example")
    refute Map.has_key?(strut, "lot")
  end

  test "a variant with a model that is not true is refused, with its path" do
    door = %{
      "blueprint" => "catalog",
      "options" => %{"name" => "door_prehung_36x80"},
      "joints" => %{"slab_door_prehung_36x80" => 200}
    }

    assert {:error, [%{"path" => "variants.1.model"}]} = Set.place(%{"orders" => [@strut, door]}, "https://x")
    assert {:error, [%{"path" => "count"}]} = Set.place(%{"order" => @strut, "count" => 99}, "https://x")
  end

  test "POST /sets" do
    body = JSON.encode!(%{"orders" => [@strut]})
    conn = conn(:post, "/sets", body) |> World.Service.call(World.Service.init([]))
    assert conn.status == 200
    assert %{"set" => _, "variants" => [%{"hash" => _}]} = JSON.decode!(conn.resp_body)

    bad = conn(:post, "/sets", ~s({"orders": []})) |> World.Service.call(World.Service.init([]))
    assert bad.status == 422
  end
end

defmodule World.Orders.SetStoreTest do
  use ExUnit.Case, async: false
  import Plug.Test

  test "the store of the orders fails: 503" do
    old = Application.get_env(:world, World.Orders.Store, [])
    Application.put_env(:world, World.Orders.Store, program: "/no/such/program")
    on_exit(fn -> Application.put_env(:world, World.Orders.Store, old) end)

    set = %{"orders" => [%{"blueprint" => "strut", "options" => %{"length" => 0.3}}]}
    assert World.Orders.Set.place(set, "https://x") == {:error, :store}
    conn = conn(:post, "/sets", JSON.encode!(set)) |> World.Service.call(World.Service.init([]))
    assert conn.status == 503
  end
end
