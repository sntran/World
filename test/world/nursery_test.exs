defmodule World.NurseryTest do
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Plants, Scene}

  test "each plant of the nursery: its height, its levels, its checks, the nursery makes it" do
    for {name, fun} <- Plants.models() do
      near = Detail.with(:near, fun)
      assert World.Check.model(near) == :ok, name
      assert World.Plan.trade(near) == :gardener
      tris = for l <- [:near, :mid, :far], do: Scene.triangles(Build.scene(Detail.with(l, fun), level: l))
      assert tris == Enum.sort(tris, :desc), "#{name}: #{inspect(tris)}"
      [_, _, h] = Build.scene(near, level: :near).extras["size"]
      assert h > 0.8 * near.extras["height"] and h < 1.6 * near.extras["height"], "#{name}: #{h}"
    end
  end

  test "the blueprint plant: an order of a species with its height, and the light file in the triangles of a project" do
    alias World.Orders
    assert "plant" in Orders.Blueprints.names()

    for species <- Plants.species() do
      {:ok, job} = Orders.job(%{"blueprint" => "plant", "options" => %{"species" => species}}, "far")
      item = job.item.(:far)
      assert item.kind == :plant and item.extras["species"] == species
      assert item.extras["height"] == Plants.number(species, "height")
    end

    order = %{"blueprint" => "plant", "options" => %{"height" => 9, "seed" => 4}}

    assert {:ok, %{"order" => %{"options" => %{"species" => "coconut", "month" => 6}}}} =
             Orders.place(order, "http://x")

    {:ok, job} = Orders.job(order, "far")
    assert job.item.(:far).extras["height"] == 9
    # A coconut palm at far in the 204 triangles of Vũng Tàu, with its two roles.
    {:ok, light} = Orders.build(order, "far", "light", triangles: 204)
    assert [%{"primitives" => [_, _] = primitives}] = World.GLBHelper.json(light)["meshes"]
    counts = for p <- primitives, do: div(Enum.at(World.GLBHelper.json(light)["accessors"], p["indices"])["count"], 3)
    assert Enum.sum(counts) <= 204 and Enum.sum(counts) > 120

    assert {:error, [%{"path" => "options.species"}]} =
             Orders.check(%{"blueprint" => "plant", "options" => %{"species" => "oak"}})
  end

  test "the areca palm: a thin straight trunk with a green crown shaft, a small crown, a bunch of orange fruits" do
    palm = Detail.with(:near, &Plants.areca/0)
    assert palm.name == "areca_palm" and palm.extras == %{"species" => "areca", "height" => 12.0}
    assert Enum.map(palm.nodes, &elem(&1, 0)) == ~w(trunk_areca crown_areca nuts_areca)
    [{_, trunk, _}, _, {_, nuts, _}] = palm.nodes
    # The trunk and the crown shaft: the shaft has the role of a leaf. The fruits have their own role.
    assert Enum.map(trunk.shapes, & &1.material) == [:bark, :leaf]
    assert length(nuts.shapes) == 24 and Enum.all?(nuts.shapes, &(&1.material == :fruit))
    assert World.GLB.palette()["fruit"]["color"] == [216, 112, 42]
    {{x0, _, _}, {x1, _, z1}} = Scene.bounds(Build.scene(palm, level: :near))
    assert z1 > 12 and z1 < 14 and x1 - x0 < 3.5

    # The coconut palm has no crown shaft, and its nuts are green.
    coconut = Detail.with(:near, &Plants.coconut/0)
    [{_, trunk, _}, _, {_, nuts, _}] = coconut.nodes
    assert Enum.map(trunk.shapes, & &1.material) == [:bark]
    assert length(nuts.shapes) == 12 and Enum.all?(nuts.shapes, &(&1.material == :leaf))
  end

  test "the numbers of a plant come from the request: a project gives and corrects the trunk, the fronds, the lean" do
    alias World.Orders
    numbers = Plants.numbers()
    # Each number of a species but its height, with its least and its most (a quarter and four times).
    assert numbers["fronds"] == {9 / 4, 120, true} and numbers["trunk"] == {0.02, 1.32, false}
    refute Map.has_key?(numbers, "height") or Map.has_key?(numbers, "flowering")
    assert Plants.numbers("coconut") == ~w(base frond fronds leaflet lean nut nuts trunk)
    assert "crownshaft" in Plants.numbers("areca") and "culms" in Plants.numbers("bamboo")

    # In `with_numbers/2` a number of the request comes before the number of the species; a count is whole.
    assert Plants.with_numbers(%{"fronds" => 11.6, "lean" => 3}, fn ->
             {Plants.number("coconut", "fronds"), Plants.number("coconut", "lean"), Plants.number("coconut", "trunk")}
           end) == {12, 3.0, 0.33}

    assert Plants.number("coconut", "fronds") == 30
    # (A call in a call: the numbers of the outer call come back.)
    assert Plants.with_numbers(%{"fronds" => 8}, fn ->
             Plants.with_numbers(%{"fronds" => 9}, fn -> :ok end)
             Plants.number("coconut", "fronds")
           end) == 8

    fronds = fn options ->
      {:ok, job} = Orders.job(%{"blueprint" => "plant", "options" => options}, "near")
      [_, {_, crown, _} | _] = job.item.(:near).nodes
      # (A frond at near: its rachis and 36 leaflets.)
      div(length(crown.shapes), 37)
    end

    assert fronds.(%{}) == 30 and fronds.(%{"numbers" => %{"fronds" => 12}}) == 12

    {:ok, job} =
      Orders.job(
        %{"blueprint" => "plant", "options" => %{"species" => "areca", "numbers" => %{"crownshaft" => 1.0}}},
        "far"
      )

    assert [{_, trunk, _} | _] = job.item.(:far).nodes
    {{_, _, z0}, {_, _, z1}} = World.Part.bounds(%{trunk | shapes: [List.last(trunk.shapes)]})
    assert_in_delta z1 - z0, 1.0, 0.01

    # A number that the species does not have, and a number out of its limits.
    assert {:error, [%{"path" => "options.numbers.culms", "message" => "a coconut has no number culms" <> _}]} =
             Orders.check(%{"blueprint" => "plant", "options" => %{"numbers" => %{"culms" => 20}}})

    assert {:error, [%{"path" => "options.numbers.fronds"}]} =
             Orders.check(%{"blueprint" => "plant", "options" => %{"numbers" => %{"fronds" => 0}}})
  end

  test "the far level of a palm has less than 500 faces; a taller palm is taller" do
    far = Build.scene(Detail.with(:far, &Plants.coconut/0), level: :far)
    assert Scene.triangles(far) < 500
    [_, _, h] = Build.scene(Detail.with(:far, fn -> Plants.coconut(height: 22) end), level: :far).extras["size"]
    assert h > 22
  end

  test "the frangipani has no leaves in the dry season, and flowers from May to August" do
    names = fn month -> Enum.map(Plants.frangipani(month: month).nodes, &elem(&1, 0)) end
    refute "leaves_frangipani" in names.(2)
    assert "flowers_frangipani" in names.(6)
    refute "flowers_frangipani" in names.(10)
    assert "leaves_frangipani" in names.(10)
  end

  test "the species and their numbers come with their sources" do
    assert Plants.species() == ~w(areca bamboo banana coconut frangipani)
    assert Plants.number("coconut", "fronds") == 30
    assert Plants.bamboo(culms: 5).extras["culms"] == 5
    assert Plants.coconut(nuts: false).nodes |> Enum.map(&elem(&1, 0)) |> Enum.member?("nuts_coconut") == false
    assert Plants.banana(bunch: false).nodes |> length() == 2
  end
end
