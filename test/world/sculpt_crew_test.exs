defmodule World.Sculpt.CrewTest do
  # The work of a sculpture is done by the crew of its site: the tasks
  # of the streams of the hand of the sculptor (`World.Crew`, plan 0012,
  # D6). They are linked to the hand, so a stop of the person stops each
  # of them at once (plan 0008, D4, R4). The test reads the tasks of the
  # node, so it does not run with the others.
  use ExUnit.Case, async: false

  alias World.{Crew, Person, Sculpt, Stone}

  # The tasks of a site now: the tasks of the node that the site called.
  defp crew(site) do
    for task <- Task.Supervisor.children(World.Crew.Tasks),
        {:dictionary, dictionary} <- [Process.info(task, :dictionary)],
        match?([^site | _], dictionary[:"$callers"]),
        do: task
  end

  test "a sculptor makes a sculpture in its hand, with a crew of tasks; a stop ends the crew in less than 100 ms" do
    {:ok, p} = Person.start_link(trade: :sculptor)
    edits = Stone.edits(30)
    Person.work(p, "stone", fn -> Sculpt.model(edits, level: :mid, cache: false) end)
    assert_receive {:done, ^p, "stone", [_ | _] = meshes}, 30_000
    assert Enum.all?(meshes, &(&1.faces != []))
    assert Crew.state().sites == 0 and Task.Supervisor.children(World.Crew.Tasks) == []

    # A sculpture of many edits at near: its crew has each worker of the
    # node, then the stop. (Small cells, so the work is much longer than
    # the wait for its crew on a machine with other work.)
    Person.work(p, "big", fn -> Sculpt.model(Stone.edits(600), step: 0.01, cache: false) end)
    all = Crew.state().workers

    wait = fn wait ->
      receive do
        {:done, ^p, "big", _} -> flunk("the work was done before its crew had each worker")
      after
        2 ->
          # (The hand of the person: the process of its work.)
          site = with {hand, _, _, _} <- Person.info(p).hand, do: hand
          tasks = if site, do: crew(site), else: []
          if length(tasks) == all, do: tasks, else: wait.(wait)
      end
    end

    tasks = wait.(wait)
    refs = for pid <- tasks, do: Process.monitor(pid)
    t0 = System.monotonic_time(:millisecond)
    Person.stop(p)
    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, _}, 1_000)
    assert System.monotonic_time(:millisecond) - t0 < 100
    refute_receive {_, ^p, "big", _}, 50
    assert %{hand: nil} = Person.info(p)
    # The node has no site and no task, and the next sculpture is the same.
    gone = fn gone ->
      if Crew.state().sites == 0 and Task.Supervisor.children(World.Crew.Tasks) == [], do: :ok, else: gone.(gone)
    end

    assert gone.(gone) == :ok
    assert Sculpt.model(edits, level: :mid, cache: false) == meshes
  end
end
