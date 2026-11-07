defmodule World.PlacesTest do
  # The places of the yard, the stock and the takeoff of a task (plan 0002, D6).
  use ExUnit.Case, async: true

  alias World.{Detail, Drawing, Mass, Orders, Places, Stock}

  test "the places of the yard: their kinds, the place of a kind of model, the drives, the buildings" do
    assert Enum.map(Places.all(), & &1["name"]) == ~w(gate warehouse vehicles workshop site)
    assert Places.for_kind("vehicle") == "vehicles" and Places.for_kind("house") == "site"
    assert Places.for_kind("furniture") == "workshop" and Places.for_kind("animal") == nil
    assert {:ok, %{"kind" => "warehouse"}} = Places.fetch("warehouse")
    assert Places.fetch("moon") == :error
    assert Places.distance("warehouse", "vehicles") == 160.0
    # 160 m at 20 km/h: 28.8 s of the world.
    assert Places.drive("warehouse", "vehicles") == 28_800
    assert Places.trucks()["count"] == 2

    # Each building is a house that the people can build.
    for p <- Places.buildings() do
      assert {:ok, _} = Orders.check(p["building"]), p["name"]
    end

    assert Enum.map(Places.buildings(), & &1["name"]) == ~w(warehouse vehicles workshop)
  end

  test "the stock: a take, a take that is short, a delivery, the mass and the loads of a truck" do
    s = Stock.new()
    assert Stock.count(s, "brick") == 200_000 and Stock.count(s, "gold") == 0
    assert {:ok, s1} = Stock.take(s, %{"brick" => 1000, "cement" => 10})
    assert Stock.count(s1, "brick") == 199_000
    assert Stock.take(s1, %{"brick" => 200_000, "gold" => 2}) == {:short, %{"brick" => 1000, "gold" => 2}}
    assert Stock.count(Stock.put(s1, %{"brick" => 1000, "gold" => 2}), "gold") == 2
    assert Stock.mass(s, %{"brick" => 1000, "cement" => 10}) == 2100.0

    # 1,000 bricks of 1.6 kg for a truck of 1,500 kg: 937 and 63.
    assert Stock.loads(s, %{"brick" => 1000}, 1500.0) == [%{"brick" => 937}, %{"brick" => 63}]
    assert Stock.loads(s, %{"brick" => 10, "cement" => 1}, 1500.0) == [%{"brick" => 10, "cement" => 1}]
    # A bag heavier than a load is a load of its own.
    assert Stock.loads(s, %{"cement" => 2}, 10.0) == [%{"cement" => 1}, %{"cement" => 1}]
    assert Stock.loads(s, %{}, 10.0) == []
  end

  # The made node of a tube house at near, and its takeoff.
  defp made(d, name, made) do
    inputs = Drawing.inputs(d, name, made)
    {Detail.with(:near, fn -> Drawing.make(d, name, inputs) end), Drawing.materials(d, name, inputs)}
  end

  defp volume(part), do: Enum.sum(for m <- part.shapes, do: elem(Mass.mesh(m), 0))

  test "the takeoff of each task of a tube house agrees with the element that the people make" do
    {:ok, job} = Orders.job(%{"blueprint" => "tube_house", "options" => %{}}, "near")
    d = job.drawing
    {plan, none} = made(d, "plan", %{})
    assert none == %{}
    m = %{"plan" => plan}
    {_, _, _} = plan

    for name <- ~w(slab_0 col_1 slab_1 slab_3) do
      {{part, _, _}, t} = made(d, name, m)
      # 7 bags of cement for 1 m3 of concrete.
      assert_in_delta t["cement"] / 7, volume(part), 1 / 7 + 0.02 * volume(part), name
      assert t["rebar"] > 0
    end

    # A band of bricks: 62 bricks for each m2 of its face.
    {{part, _, _}, t} = made(d, "wall_left_1_1", m)
    assert_in_delta t["brick"] / 62.1, volume(part) / 0.11, 1.0

    {_, t} = made(d, "wall_front_1_1", m)
    {_, full} = made(d, "wall_left_1_2", m)
    # The front has the shutter: fewer bricks than a side wall of the same floor.
    assert t["brick"] < full["brick"]

    assert %{"mortar" => _} = elem(made(d, "plaster_back_1", m), 1)
    assert elem(made(d, "plaster_left_1", m), 1) == %{}
    assert %{"paint" => _} = elem(made(d, "paint_front_1", m), 1)
    assert elem(made(d, "paint_back_1", m), 1) == %{}
    assert %{"steel" => _} = elem(made(d, "iron_1", m), 1)
    assert elem(made(d, "iron_3", m), 1) == %{}
    assert %{"brick" => _} = elem(made(d, "roof", m), 1)
    assert elem(made(d, "opening_front_1", m), 1) == %{}
  end

  test "the takeoff of a metal roof with no parapet, and of a node that is not a skill" do
    plan = %{
      "plan" =>
        elem(
          Detail.with(:near, fn -> World.Skills.HousePlan.make(%{"roof" => "metal", "parapet" => 0.0}, %{}, %{}) end),
          1
        )["plan"]
    }

    assert %{"roof_sheet" => n} = World.Skills.Roof.materials(%{}, %{"plan" => plan})
    assert n == ceil(4.4 * 16.0 * 1.1 / 6.42)
    d = %{"nodes" => [%{"name" => "b", "part" => "x"}]}
    assert Drawing.materials(d, "b", %{}) == %{}
  end
end
