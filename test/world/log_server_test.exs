defmodule World.Log.ServerTest do
  # The log of the node and its store. The store of the log is in the
  # environment of the application, so these tests do not run at one
  # time with the others.
  use ExUnit.Case, async: false

  alias World.Log.{Server, Store}
  alias World.{Clock, Log}

  @moduletag :tmp_dir
  @script Path.expand("../../scripts/log-store.mjs", __DIR__)

  defp with_store(file) do
    Application.put_env(:world, Store, program: @script, file: file)
    on_exit(fn -> Application.delete_env(:world, Store) end)
  end

  defp server(opts) do
    name = :"log_#{System.unique_integer([:positive])}"
    start_supervised!({Server, [name: name] ++ opts}, id: name)
    name
  end

  # An event of the construction `order`, of a kind.
  defp event(order, kind, n \\ 0) do
    {:ok, log} = Log.add(Log.new(Clock.new(start: 0)), kind, wall: n, order: order, who: "<0.1.0>")
    hd(log.events)
  end

  test "each event gets the next id, goes to the watchers of its construction and of the world, and stays in the memory" do
    s = server(store: false)
    order = "b#{System.unique_integer([:positive])}"
    World.watch(order)
    World.watch(:world)
    assert Server.last(s) == 0 and Server.history(0, s) == []

    Server.publish(event(order, "requested"), s)
    Server.publish(event(order, "plan_made", 1), s)
    assert_receive {:world, %{"id" => 1, "kind" => "requested", "order" => ^order}}
    assert_receive {:world, %{"id" => 1, "kind" => "requested"}}
    assert_receive {:world, %{"id" => 2, "kind" => "plan_made"}}
    assert Server.last(s) == 2
    assert [%{"id" => 1}, %{"id" => 2}] = Server.history(0, s)
    assert [%{"id" => 2}] = Server.history(1, s)
    assert Server.history(2, s) == []
  end

  test "the memory keeps the last 2,000 events; with no store, the older events are not there" do
    s = server(store: false)
    for n <- 1..2_001, do: Server.publish(event("many", "requested", n), s)
    history = Server.history(0, s)
    assert length(history) == 2_000 and hd(history)["id"] == 2
  end

  test "a publish takes the same work with 10 events in the log or 10,000 (plan 0007, R7)" do
    s = server(store: false)
    pid = Process.whereis(s)

    # The publishes are casts: a call first, so the work before is done.
    work = fn n ->
      Server.last(s)
      {:reductions, r0} = Process.info(pid, :reductions)
      for i <- 1..n, do: Server.publish(event("work", "requested", i), s)
      Server.last(s)
      {:reductions, r1} = Process.info(pid, :reductions)
      (r1 - r0) / n
    end

    for _ <- 1..10, do: Server.publish(event("work", "requested"), s)
    small = work.(200)
    for _ <- 1..10_000, do: Server.publish(event("work", "requested"), s)
    large = work.(200)
    assert large < small * 1.5
  end

  test "the store keeps each event in batches; a new log goes on from the last id, and reads the older events from the store",
       %{tmp_dir: dir} do
    with_store(Path.join(dir, "log.jsonl"))
    assert Store.on?()
    s = server([])

    # The log starts after 50 ids, and puts its start into the store.
    assert [%{"id" => 50, "kind" => "started"}] = Server.history(0, s)

    # 60 events: a batch of 50 at once, and 10 after the time of a batch.
    for n <- 1..60, do: Server.publish(event("kept", "requested", n), s)
    assert Server.last(s) == 110
    Process.sleep(400)
    assert {:ok, 110} = Store.last()

    stop_supervised!(s)
    again = server([])
    assert Server.last(again) == 160
    # The memory of the new log has its start only: the events come from the store.
    assert length(Server.history(0, again)) == 62
    assert [%{"id" => 110}, %{"id" => 160, "kind" => "started"}] = Server.history(109, again)

    # An event in the buffer goes into the store before a read of the store.
    Server.publish(event("kept", "done", 61), again)
    assert length(Server.history(0, again)) == 63
  end

  test "a store that fails gives no older events, and the log goes on" do
    Application.put_env(:world, Store, program: "/bin/false")
    on_exit(fn -> Application.delete_env(:world, Store) end)
    assert Store.last() == :error and Store.read(0, 10) == :error and Store.append(["{}"]) == :error
    assert Store.append([]) == :ok

    s = server([])
    assert Server.last(s) == 0
    Server.publish(event("lost", "requested"), s)
    assert [%{"id" => 1}] = Server.history(0, s)

    # The memory does not keep the first event, and the store cannot give it.
    for n <- 1..2_000, do: Server.publish(event("lost", "requested", n), s)
    assert length(Server.history(0, s)) == 2_000
  end

  test "with no program, the node has no store" do
    refute Store.on?()
  end
end
