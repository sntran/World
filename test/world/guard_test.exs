defmodule World.GuardTest do
  # No order stops the VM (the guard of the memory), and a step of a build
  # in a process of its own (World.Detail.apart/2). (Not async: the tests
  # change the limit of the memory.)
  use ExUnit.Case

  alias World.{Detail, Guard, Orders}

  @moduletag timeout: 600_000

  setup do
    before = Application.get_env(:world, :memory_mb)

    on_exit(fn ->
      if before, do: Application.put_env(:world, :memory_mb, before), else: Application.delete_env(:world, :memory_mb)
    end)
  end

  test "with no limit, the guard only runs the function" do
    Application.delete_env(:world, :memory_mb)
    assert Guard.limit() == nil
    assert Guard.run(fn -> self() end) == {:ok, self()}
  end

  test "the limit of the heap of a build counts its binaries" do
    Application.put_env(:world, :memory_mb, 1000)

    assert {:ok, {:max_heap_size, %{size: size, kill: true, include_shared_binaries: true}}} =
             Guard.run(fn -> Process.info(self(), :max_heap_size) end)

    assert size == div(Guard.limit(), :erlang.system_info(:wordsize))
  end

  test "a build that needs more memory than the limit stops with an error, and the VM and its caller go on" do
    Application.put_env(:world, :memory_mb, 1)
    assert Guard.limit() == 1_000_000
    me = self()

    assert {:error, :memory} =
             Guard.run(fn ->
               send(me, {:worker, self()})
               Process.sleep(:infinity)
             end)

    assert_received {:worker, worker}
    refute Process.alive?(worker)
    assert [%{"path" => "", "message" => "needs more memory than the factory has (1 MB): " <> _}] = Guard.errors()

    # The check of an order (a pose: its model is built) and the build of a file get the error.
    door = %{
      "blueprint" => "catalog",
      "options" => %{"name" => "door_prehung_36x80"},
      "joints" => %{"slab_door_prehung_36x80" => 10}
    }

    assert {:error, [%{"message" => "needs more memory" <> _}]} = Orders.place(door, "o")

    # The check of a model with no pose that the guard stops at far keeps the check of its data:
    # the order is good.
    tag = "#{System.unique_integer([:positive])}"

    wall = %{
      "name" => "wall",
      "kind" => "item",
      "sources" => ["A test #{tag}."],
      "nodes" => [
        %{
          "name" => "wall",
          "skill" => %{
            "sculpt" => %{
              "edits" => [%{"shape" => "box", "size" => [4, 0.15, 0.5], "at" => [0, 0, 0.5], "material" => "plaster"}],
              "sources" => ["A test wall #{tag}."],
              "cells" => %{"far" => 0.04},
              "budget" => %{"far" => 4_000}
            }
          }
        }
      ]
    }

    assert {:ok, %{"hash" => _}} = Orders.place(%{"blueprint" => "drawing", "options" => %{"drawing" => wall}}, "o")
    group = %{"blueprint" => "exercise", "options" => %{"count" => 2, "fans" => true}}
    assert {:error, [%{"message" => "needs more memory" <> _}]} = Orders.build(group, "far", "glb")
    # (A rule in code with no pose is checked by the tests of its rule: its order needs no build.)
    assert {:ok, _} = Orders.place(group, "o")
    assert Process.alive?(self())
  end

  test "the guard runs the stop of the work that a build started when it stops the build, and not after a good end" do
    me = self()
    assert Guard.on_stop(fn -> send(me, :outside) end) == :ok
    refute_received :outside

    Application.put_env(:world, :memory_mb, 100_000)

    assert {:ok, :done} =
             Guard.run(fn ->
               :ok = Guard.on_stop(fn -> send(me, :after_a_good_end) end)
               :done
             end)

    Application.put_env(:world, :memory_mb, 1)

    assert {:error, :memory} =
             Guard.run(fn ->
               Guard.on_stop(fn -> send(me, {:stop, 1}) end)
               Guard.on_stop(fn -> send(me, {:stop, 2}) end)
               Process.sleep(:infinity)
             end)

    assert_received {:stop, 1}
    assert_received {:stop, 2}

    # (Killed by its limit of the heap, before the next look.)
    assert {:error, :memory} =
             Guard.run(fn ->
               Guard.on_stop(fn -> send(me, :heap) end)
               Enum.map(1..1_000_000, & &1)
             end)

    assert_received :heap
    refute_received :after_a_good_end

    # The construction of a file that the guard stops is cancelled: it does not go on.
    group = %{"blueprint" => "exercise", "options" => %{"count" => 3, "fans" => false}}
    {:ok, full} = Orders.check(group)
    {:ok, job} = Orders.job(full, "near")
    assert {:error, [%{"message" => "needs more memory" <> _}]} = Orders.build(group, "near", "glb")

    wait = fn wait, n ->
      if Registry.lookup(World.Names, job.id) == [] or n == 0, do: n, else: Process.sleep(20) && wait.(wait, n - 1)
    end

    assert wait.(wait, 500) > 0
  end

  test "a build in the guard keeps the level of detail of its caller, gives its errors, and stops when its process stops" do
    Application.put_env(:world, :memory_mb, 100_000)
    assert Detail.with(:far, fn -> Guard.run(&Detail.level/0) end) == {:ok, :far}
    # (A build of more than one look of the guard, under the limit.)
    assert Guard.run(fn -> Process.sleep(80) && :slow end) == {:ok, :slow}
    assert_raise ArgumentError, "no", fn -> Guard.run(fn -> raise ArgumentError, "no" end) end
    # (A process that its heap limit stops: killed, as by the guard.)
    me = self()

    task =
      Task.async(fn ->
        Guard.run(fn ->
          send(me, {:worker, self()})
          Process.sleep(:infinity)
        end)
      end)

    assert_receive {:worker, worker}
    Process.exit(worker, :kill)
    assert Task.await(task) == {:error, :memory}
    # Another end of the process is its end.
    assert catch_exit(Guard.run(fn -> exit(:normal) end)) == :normal
  end

  test "in WebAssembly, the guard stops a build at the memory that the VM uses, or at a growth over the limit" do
    mb = 1_000_000
    # The memory that the VM uses.
    refute Guard.over?(100 * mb, {90 * mb, 60 * mb})
    assert Guard.over?(100 * mb, {120 * mb, 101 * mb})
    # A size over the limit, with room in it; and with no room: the next growth.
    refute Guard.over?(100 * mb, {120 * mb, 90 * mb})
    assert Guard.over?(100 * mb, {120 * mb, 115 * mb})
    # A native VM: the memory of the VM.
    assert Guard.over?(1, nil)
    refute Guard.over?(100_000 * mb, nil)
  end

  test "a step apart: its value, its level, its error, its stop, and the stop of its caller" do
    assert Detail.with(:mid, fn -> Detail.apart(&Detail.level/0) end) == :mid
    assert Detail.lean(false, fn -> Detail.apart(fn -> Process.get(:world_lean) end) end) == false
    assert Detail.apart(fn -> 1 + 1 end, sweep: 2) == 2
    assert_raise RuntimeError, "no", fn -> Detail.apart(fn -> raise "no" end) end

    # A caller that stops stops its step (they are linked).
    me = self()

    caller =
      spawn(fn ->
        Detail.apart(fn ->
          send(me, {:step, self()})
          Process.sleep(:infinity)
        end)
      end)

    assert_receive {:step, step}
    ref = Process.monitor(step)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^ref, :process, ^step, :killed}
  end
end
