defmodule World.RunTest do
  use ExUnit.Case, async: true

  alias World.{Clock, Log, Plan, Run, Stock}
  alias World.Furniture.Seats
  alias World.People.Storekeeper

  @moduletag :tmp_dir

  test "an order of the van: the people make it, its log is in order, and it replays in the specification", %{
    tmp_dir: dir
  } do
    run = Run.start()
    van = World.Vehicles.FordTransit.model()
    assert {:ok, %{from: :factory} = result} = Run.order(run, van, "van-1")
    log = Run.log(run)
    events = Log.events(log)
    assert Log.check(log) == :ok

    # One start and one end of each task of the plan, at the stations of the line.
    kinds = Enum.frequencies_by(events, & &1.kind)
    assert kinds["task_started"] == length(result.plan.tasks) and kinds["task_done"] == length(result.plan.tasks)
    assert kinds["delivered"] == 1 and kinds["model_done"] == 1
    assert byte_size(result.glb) == result.bytes and result.bytes > 1_000_000

    # The truck drives 500 m at the limit of the yard: 90 world seconds.
    assert %{data: %{"world_ms" => 90_000}} = Enum.find(events, &(&1.kind == "departed"))

    # The van takes hours of the world.
    assert List.last(events).at - hd(events).at > 3_600_000

    # The log is a behavior of specs/Order.tla, with the plan of the van.
    result = Map.put(result, :order, "van-1")
    assert World.OrderSpec.replay(events, result, run, dir) == :ok

    # A log with an unload less is not: a task takes a part that is not at the dock.
    i = Enum.find_index(events, &(&1.kind == "unloaded"))
    assert {:error, {:diverged, %{kind: kind}}} = World.OrderSpec.replay(List.delete_at(events, i), result, run, dir)
    assert kind in ~w(task_started departed)

    # The fault model allows the run too.
    assert World.OrderSpec.replay(events, result, run, dir, guard: false) == :ok

    # The same order a second time comes from the stock.
    assert Run.order(run, van, "van-2") == {:ok, %{from: :stock}}
    assert %{kind: "delivered", data: %{"from" => "stock"}} = List.last(Log.events(Run.log(run)))
    assert Run.stop(run) == :ok
  end

  test "a warehouse too small for a part refuses it, and the order stops" do
    run = Run.start(Run.yard(limit: 1_000, capacity: 2, workers: ["dung"], clock: Clock.new()))
    assert Run.order(run, Seats.seat("s")) == {:error, :full}
    assert Enum.any?(Log.events(Run.log(run)), &(&1.kind == "refused"))
    Run.stop(run)
  end

  test "a warehouse too small for the files of the model refuses them" do
    run = Run.start(Run.yard(limit: 10_000))
    assert Run.order(run, Seats.seat("s")) == {:error, :full}
    assert %{kind: "refused", data: %{"model" => "model:s"}} = List.last(Log.events(Run.log(run)))
    Run.stop(run)
  end

  test "a part in the stock does not come from the supplier again, and a missing part cannot be picked" do
    run = Run.start()
    seat = Seats.seat("s")
    [t | _] = for t <- Plan.flat(seat).tasks, t.uses, do: t
    assert Storekeeper.pick(run.storekeeper, "o", t.uses, 1) == {:error, :missing}
    assert :ok = Storekeeper.supply(run.storekeeper, "o", "supplier", t.uses, 1, :erlang.external_size(t.work))
    assert Stock.count(Storekeeper.stock(run.storekeeper), t.uses) == 1
    assert {:ok, %{from: :factory}} = Run.order(run, seat, "seat")

    supplied = for e <- Log.events(Run.log(run)), e.kind == "stored", e.data["item"] == t.uses, do: e
    assert length(supplied) == 1
    Run.stop(run)
  end

  test "the replay with the fault model finds two workers on one task", %{tmp_dir: dir} do
    run = %Run{yard: Run.yard(), workers: %{"dung" => nil, "em" => nil}}
    tasks = [%Plan.Task{id: "a", action: :order}, %Plan.Task{id: "b", action: :make, uses: "p", waits: ["a"]}]
    result = %{order: "o", plan: %Plan{tasks: tasks, parts: %{"p" => 1}}, sizes: %{"p" => 10}, bytes: 100}
    start = fn who -> %Log.Event{kind: "task_started", order: "o", who: who, data: %{"task" => "a"}} end

    assert {:error, {:violated, "OneWorkerOneTask", %{who: "em"}}} =
             World.OrderSpec.replay([start.("dung"), start.("em")], result, run, dir, guard: false)

    assert {:error, {:diverged, %{who: "em"}}} =
             World.OrderSpec.replay([start.("dung"), start.("em")], result, run, dir)
  end
end
