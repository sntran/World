defmodule World.PersonTest do
  # A person does each task in a hand, and stops it at once at a stop
  # (plan 0007, D5 and R5). A test sets the scale of the world clock, so
  # the tests do not run with the others.
  use ExUnit.Case, async: false

  alias World.Person

  setup do
    old = Application.get_env(:world, :scale)
    on_exit(fn -> Application.put_env(:world, :scale, old) end)
    :ok
  end

  defp person do
    {:ok, p} = Person.start_link(trade: :builder)
    p
  end

  test "the result of a hand: done, failed, or over its memory" do
    p = person()
    Person.work(p, "a", fn -> 42 end)
    assert_receive {:done, ^p, "a", 42}
    Person.work(p, "b", fn -> raise "no brick" end)
    assert_receive {:failed, ^p, "b", "no brick"}
    Person.work(p, "c", fn -> exit(:tired) end)
    assert_receive {:failed, ^p, "c", ":tired"}
    Person.work(p, "d", fn -> Enum.to_list(1..1_000_000) end, 1_000)
    assert_receive {:failed, ^p, "d", "memory"}, 5_000
    assert %{hand: nil, trade: :builder} = Person.info(p)
  end

  test "a stop: the hand of a task that does not end stops at once, and no result goes" do
    p = person()
    Person.work(p, "wall", fn -> Process.sleep(:infinity) end)
    assert %{hand: {hand, _, _, "wall"}} = Person.info(p)
    t0 = System.monotonic_time(:millisecond)
    Person.stop(p)
    assert %{hand: nil} = Person.info(p)
    assert System.monotonic_time(:millisecond) - t0 < 100 and not Process.alive?(hand)
    refute_receive {_, ^p, "wall", _}, 50
    # A stop with no task does nothing; a stop of a person that is gone too.
    Person.stop(p)
    assert %{hand: nil} = Person.info(p)
    assert Person.stop(spawn(fn -> :ok end)) == :ok
  end

  test "a cancel: each person of the construction with a task is free in less than 100 ms" do
    # One day in a second of the wall: each task of the wall is 3 hours.
    Application.put_env(:world, :scale, 86_400)
    item = fn level -> World.Detail.with(level, fn -> World.Buildings.masonry_wall("row", "brick_vn", 1.0, 1.5) end) end
    id = "stop-#{System.unique_integer([:positive])}"
    World.watch(id)
    {:ok, ^id} = World.build(%{id: id, item: item, budget: %{"workers" => 4}})
    assert_receive {:world, %{"kind" => "task_started", "who" => who}}, 10_000
    p = who |> String.to_charlist() |> :erlang.list_to_pid()
    assert %{hand: {_, _, _, _}} = Person.info(p)
    t0 = System.monotonic_time(:millisecond)
    :ok = World.cancel(id)
    assert {:error, {:stopped, "cancelled"}} = World.await(id, 5_000)
    assert %{hand: nil} = Person.info(p)
    assert System.monotonic_time(:millisecond) - t0 < 100
  end
end
