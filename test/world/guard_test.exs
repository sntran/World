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

  test "a build that needs more memory than the limit stops with an error, and the VM and its caller go on" do
    Application.put_env(:world, :memory_mb, 1)
    assert Guard.limit() == 1_000_000
    me = self()
    assert {:error, :memory} = Guard.run(fn -> send(me, {:worker, self()}) && Process.sleep(:infinity) end)
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
    group = %{"blueprint" => "exercise", "options" => %{"count" => 2, "fans" => true}}
    assert {:error, [%{"message" => "needs more memory" <> _}]} = Orders.build(group, "far", "glb")
    # (A rule in code with no pose is checked by the tests of its rule: its order needs no build.)
    assert {:ok, _} = Orders.place(group, "o")
    assert Process.alive?(self())
  end

  test "a build in the guard keeps the level of detail of its caller, gives its errors, and stops when its process stops" do
    Application.put_env(:world, :memory_mb, 100_000)
    assert Detail.with(:far, fn -> Guard.run(&Detail.level/0) end) == {:ok, :far}
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
