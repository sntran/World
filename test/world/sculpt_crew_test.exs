defmodule World.Sculpt.CrewTest do
  # The work of a sculpture is done by the crew of its site: the workers
  # of the node that serve the hand of the sculptor (plan 0012, D6). A
  # stop of the person stops each job of the site at once (plan 0008, D4,
  # R4). The test reads the crews of the node, so it does not run with
  # the others.
  use ExUnit.Case, async: false

  alias World.{Crew, Person, Sculpt, Stone}

  # The workers that serve a site now.
  defp crew(site), do: Enum.find_value(Crew.state().sites, [], &(&1.site == site && &1.crew))

  test "a sculptor makes a sculpture in its hand, with a crew of workers; a stop ends the work of the crew in less than 100 ms" do
    {:ok, p} = Person.start_link(trade: :sculptor)
    edits = Stone.edits(30)
    Person.work(p, "stone", fn -> Sculpt.model(edits, level: :mid, cache: false) end)
    assert_receive {:done, ^p, "stone", [_ | _] = meshes}, 30_000
    assert Enum.all?(meshes, &(&1.faces != []))
    assert Crew.state().sites == []

    # A sculpture of many edits at near: its crew is each worker of the
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
          if site != nil and length(crew(site)) == all, do: crew(site), else: wait.(wait)
      end
    end

    workers = wait.(wait)
    refs = for pid <- workers, do: Process.monitor(pid)
    t0 = System.monotonic_time(:millisecond)
    Person.stop(p)
    # The site is gone from the crews, and the workers that had a job of it then are stopped.
    gone = fn gone -> if Crew.state().sites == [], do: :ok, else: gone.(gone) end
    :ok = gone.(gone)
    assert System.monotonic_time(:millisecond) - t0 < 100
    # (A worker with a job of the site at the stop is stopped; a worker between two jobs stays:
    # `test/world/crew_test.exs` has the count.)
    for ref <- refs, do: Process.demonitor(ref, [:flush])
    refute_receive {_, ^p, "big", _}, 50
    assert %{hand: nil} = Person.info(p)
    # The node has new workers, with no site.
    assert %{workers: ^all, sites: []} = Crew.state()
    assert Sculpt.model(edits, level: :mid, cache: false) == meshes
  end
end
