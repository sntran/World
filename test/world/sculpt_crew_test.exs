defmodule World.Sculpt.CrewTest do
  # The tree of a sculpture is the crew of the hand of a sculptor: a stop
  # of the person stops each process of the tree at once (plan 0008, D4,
  # R4). The test counts the processes of the node, so it does not run
  # with the others.
  use ExUnit.Case, async: false

  alias World.{Person, Sculpt, Stone}

  defp crew, do: Enum.filter(Process.list(), &match?({:sculpt, _, _}, :proc_lib.get_label(&1)))

  test "a sculptor makes a sculpture in its hand, with a crew of processes; a stop ends the crew in less than 100 ms" do
    {:ok, p} = Person.start_link(trade: :sculptor)
    edits = Stone.edits(30)
    Person.work(p, "stone", fn -> Sculpt.model(edits, level: :mid, cache: false) end)
    assert_receive {:done, ^p, "stone", [_ | _] = meshes}, 30_000
    assert Enum.all?(meshes, &(&1.faces != []))
    assert crew() == []

    # A sculpture of many edits at near: its crew grows, then the stop.
    Person.work(p, "big", fn -> Sculpt.model(Stone.edits(300), level: :near, cache: false) end)

    wait = fn wait ->
      if length(crew()) < 8,
        do:
          (
            Process.sleep(5)
            wait.(wait)
          ),
        else: :ok
    end

    :ok = wait.(wait)
    t0 = System.monotonic_time(:millisecond)
    Person.stop(p)

    gone = fn gone ->
      if crew() != [],
        do:
          (
            Process.sleep(1)
            gone.(gone)
          ),
        else: System.monotonic_time(:millisecond)
    end

    assert gone.(gone) - t0 < 100
    refute_receive {_, ^p, "big", _}, 50
    assert %{hand: nil} = Person.info(p)
  end
end
