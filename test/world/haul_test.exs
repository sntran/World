defmodule World.HaulTest do
  # The haul of the yard: the trucks bring the takeoff of a task to its
  # place (plan 0002, D6 and D8), and its log replays in specs/Haul.tla.
  use ExUnit.Case, async: true

  alias Accord.TLA.Checker
  alias World.{BuildSpec, Haul, HaulSpec, Log, Orders, Stock}

  @moduletag :tmp_dir
  @model Path.expand("../../specs/MCHaul.tla", __DIR__)

  defp start(name, opts \\ []), do: start_supervised!({Haul, [name: name] ++ opts}, id: name)
  defp kinds(log), do: for(e <- Log.events(log), do: e.kind)

  test "with no truck of the yard, a supplier brings the bricks of a band from the gate in rented trucks", %{
    tmp_dir: dir
  } do
    h = start(:haul_rent)
    Haul.ask(h, :band, "b|wall_1", "site", %{"brick" => 1000})
    assert_receive {:hauled, :band}, 5000
    log = Haul.log(h)
    assert Log.check(log) == :ok
    assert Enum.frequencies(kinds(log)) == %{"haul_asked" => 1, "loaded" => 2, "unloaded" => 2, "hauled" => 1}
    [asked | _] = Log.events(log)
    assert asked.data["from"] == "gate" and length(asked.data["loads"]) == 2
    # The stock of the warehouse does not change: the warehouse is not open.
    assert Stock.count(Haul.stock(h), "brick") == 200_000
    assert HaulSpec.replay(log, [], dir) == :ok
  end

  test "the trucks of the yard bring the takeoff from the open warehouse, one load at a time for each truck", %{
    tmp_dir: dir
  } do
    h = start(:haul_own)
    :ok = Haul.join(h, "truck_1", "vehicles")
    :ok = Haul.open(h)
    Haul.ask(h, :slab, "b|slab_1", "site", %{"cement" => 40, "rebar" => 60})
    Haul.ask(h, :none, "b|col_1", "site", %{})
    assert_receive {:hauled, :none}, 5000
    assert_receive {:hauled, :slab}, 5000
    log = Haul.log(h)
    assert Stock.count(Haul.stock(h), "cement") == 20_000 - 40

    # 2,000 kg of cement and 624 kg of rebar: two loads, on the one truck one after the other.
    moves = for %{kind: k, data: d} <- Log.events(log), k in ~w(loaded unloaded), do: {k, d["truck"], d["load"]}

    assert moves == [
             {"loaded", "truck_1", "L1"},
             {"unloaded", "truck_1", "L1"},
             {"loaded", "truck_1", "L2"},
             {"unloaded", "truck_1", "L2"}
           ]

    assert HaulSpec.replay(log, [], dir) == :ok
  end

  test "a stock that is short: a supplier brings the takeoff from the gate" do
    stock = Stock.new(%{"brick" => %{"count" => 10, "unit" => "brick", "kg" => 1.6}})
    h = start(:haul_short, stock: stock)
    :ok = Haul.open(h)
    Haul.ask(h, :band, "b|wall_2", "site", %{"brick" => 20})
    assert_receive {:hauled, :band}, 5000
    assert [%{data: %{"from" => "gate"}} | _] = Log.events(Haul.log(h))
    assert Stock.count(Haul.stock(h), "brick") == 10
  end

  test "a log with a load that does not come diverges in the replay", %{tmp_dir: dir} do
    h = start(:haul_lost)
    Haul.ask(h, :band, "b|wall_1", "site", %{"brick" => 1000})
    assert_receive {:hauled, :band}, 5000
    log = Haul.log(h)
    # The first unloaded is lost: the haul tells the task before its loads are there.
    lost = %{log | events: List.delete(log.events, Enum.find(Enum.reverse(log.events), &(&1.kind == "unloaded")))}
    assert {:error, {:diverged, %{kind: "hauled"}}} = HaulSpec.replay(lost, [], dir)

    # One truck takes the two loads: in the fault model, a truck over its load.
    [first | _] = for %{kind: "loaded", data: d} <- Log.events(log), do: d["truck"]
    two = %{log | events: Enum.map(log.events, &if(&1.kind == "loaded", do: put_in(&1.data["truck"], first), else: &1))}

    assert {:error, {:violated, "InLoad", %{kind: "loaded"}}} =
             HaulSpec.replay(two, [], Path.join(dir, "two"), guard: false)

    # A log of a haul that nobody asked: nothing to replay.
    assert HaulSpec.replay(Log.new(log.clock), [], Path.join(dir, "none")) == :ok
  end

  test "a construction of an item that is not a drawing has no takeoff" do
    h = start(:haul_item)
    part = World.Part.new("box", :part, [World.Shape.box({0, 0, 0}, {1, 1, 1}, :steel)], [])
    {:ok, id} = World.build(%{id: "haul-item", item: fn _ -> part end, haul: h, place: "site"})
    assert {:ok, r} = World.await(id, 30_000)
    refute Enum.any?(Log.events(r.log), &(&1.kind == "parts_asked"))
  end

  test "the people build a house at the site: each task with a takeoff starts after its materials are there", %{
    tmp_dir: dir
  } do
    h = start(:haul_house)
    {:ok, job} = Orders.job(%{"blueprint" => "tube_house", "options" => %{"floors" => 1}}, "mid")
    {:ok, id} = World.build(Map.merge(job, %{haul: h, place: "site", budget: %{"workers" => 8}}))
    # A word of the haul for no task of the construction changes nothing.
    send(GenServer.whereis({:via, Registry, {World.Names, id}}), {:hauled, make_ref()})
    assert {:ok, r} = World.await(id, 60_000)
    # The same model as a build with no haul.
    assert r.glb == World.GLB.encode(job.scene.(job.item.(:mid), []))
    assert Log.check(r.log) == :ok

    asked = for %{kind: "parts_asked", data: d} <- Log.events(r.log), do: d["task"]
    here = for %{kind: "parts_here", data: d} <- Log.events(r.log), do: d["task"]
    assert ~w(slab_0 col_1 wall_left_1_1 roof) -- asked == [] and "plan" not in asked
    assert Enum.sort(asked) == Enum.sort(here)
    assert BuildSpec.replay([r.log], dir) == :ok
    assert HaulSpec.replay(Haul.log(h), [r.log], Path.join(dir, "haul")) == :ok
  end

  test "the model of the haul: each invariant holds and each task starts; the checker finds each fault" do
    assert {:ok, %{distinct_states: states}} = Checker.check(@model)
    assert states > 50

    assert {:error, %{kind: :invariant, property: "InLoad"}, _} =
             Checker.check(@model, config: Path.rootname(@model) <> "Two.cfg")

    assert {:error, %{kind: :invariant, property: "PartsFirst"}, _} =
             Checker.check(@model, config: Path.rootname(@model) <> "Early.cfg")
  end
end
