defmodule World.CensusTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.{Census, Person}

  # A census of its own for each test, so the tests do not share people.
  defp census(opts \\ []) do
    name = :"census_#{System.unique_integer([:positive])}"
    start_supervised!({Census, [name: name] ++ opts}, id: name)
    name
  end

  # A construction for the test: it sends each message it gets to the test.
  defp construction do
    test = self()
    spawn_link(fn -> forward(test) end)
  end

  defp forward(test) do
    receive do
      msg ->
        send(test, {self(), msg})
        forward(test)
    end
  end

  defp hired(c, ref) do
    assert_receive {^c, {:hired, ^ref, p}}
    p
  end

  test "a construction hires a new person of a trade; a free person goes to the next hire" do
    s = census()
    c = construction()
    p = hired(c, hire(s, :mason, c))
    assert %{trade: :mason, job: :worker} = Person.info(p)
    assert Process.get_label(p) == {:person, :worker, :mason}
    assert [%{"trade" => :mason, "by" => by}] = Census.people(s)["people"]
    assert by == Person.name(c)

    Census.release(p, c, s)
    assert hired(c, hire(s, :mason, c)) == p
    # A release by a construction that does not hold the person changes nothing.
    other = construction()
    Census.release(p, other, s)
    assert [%{"by" => ^by}] = Census.people(s)["people"]
  end

  test "the construction that holds fewer people gets the next free person" do
    s = census(limit: 2)
    [a, b] = [construction(), construction()]
    p1 = hired(a, hire(s, :mason, a))
    _p2 = hired(a, hire(s, :mason, a))
    ra = hire(s, :mason, a)
    rb = hire(s, :mason, b)
    assert length(Census.people(s)["waiting"]) == 2

    Census.release(p1, a, s)
    assert hired(b, rb) == p1
    refute_receive {^a, {:hired, ^ra, _}}
    assert [%{"by" => by}] = Census.people(s)["waiting"]
    assert by == Person.name(a)
  end

  test "at the limit, a free person of another trade leaves for a new person of the trade" do
    s = census(limit: 1)
    c = construction()
    mason = hired(c, hire(s, :mason, c))
    ref = Process.monitor(mason)
    Census.release(mason, c, s)

    steel = hired(c, hire(s, :steel, c))
    assert_receive {:DOWN, ^ref, :process, ^mason, _}
    assert [%{"trade" => :steel}] = Census.people(s)["people"]
    assert steel != mason
  end

  test "a construction that stops lets its people go, and its requests go" do
    s = census(limit: 1)
    c = construction()
    p = hired(c, hire(s, :mason, c))
    waiting = construction()
    ref = hire(s, :steel, waiting)
    hire(s, :mason, c)
    Process.unlink(c)
    Process.exit(c, :kill)

    # The person of the construction that stopped is free: it leaves, and
    # a new person of steel goes to the construction that waits.
    assert %{trade: :steel} = Person.info(hired(waiting, ref))
    refute Process.alive?(p)
    assert Census.people(s)["waiting"] == []
  end

  test "a person that stops leaves the census" do
    s = census()
    c = construction()
    p = hired(c, hire(s, :mason, c))
    ref = Process.monitor(p)
    Process.exit(p, :kill)
    assert_receive {:DOWN, ^ref, :process, ^p, :killed}
    assert Census.people(s)["people"] == []
  end

  test "a person does the work of a task and gives the result back, or the message of the error" do
    s = census()
    ref = hire(s, :mason, self())
    assert_receive {:hired, ^ref, p}
    Person.work(p, "wall", fn -> 6 * 7 end)
    assert_receive {:done, ^p, "wall", 42}, 5_000
    Person.work(p, "roof", fn -> raise "no tiles" end)
    assert_receive {:failed, ^p, "roof", "no tiles"}, 5_000
    assert Person.name(p) =~ ~r/^<\d+\.\d+\.\d+>$/

    # With a limit of the heap: the work in a process of its own.
    Person.work(p, "wall", fn -> 6 * 7 end, 100_000)
    assert_receive {:done, ^p, "wall", 42}, 5_000
    Person.work(p, "roof", fn -> raise "no tiles" end, 100_000)
    assert_receive {:failed, ^p, "roof", "no tiles"}, 5_000
    Person.work(p, "big", fn -> Enum.to_list(1..1_000_000) end, 10_000)
    assert_receive {:failed, ^p, "big", "memory"}, 5_000
    Person.work(p, "out", fn -> exit(:no_room) end, 100_000)
    assert_receive {:failed, ^p, "out", ":no_room"}, 5_000
  end

  test "the memory of the VM with no allocators of ERTS: the processes and their binaries" do
    assert {"total", total} = World.memory()
    assert {"processes", bytes} = World.memory(fn :total -> :erlang.error(:notsup) end)
    assert total > 0 and bytes > 0
  end

  test "World.census/0 is the census of the node, where a process hires and lets go" do
    ref = Person.hire(:census_test)
    assert_receive {:hired, ^ref, p}
    me = Person.name(self())
    assert %{"by" => ^me} = Enum.find(World.census()["people"], &(&1["name"] == Person.name(p)))
    Person.release(p)
    assert %{"by" => nil} = Enum.find(World.census()["people"], &(&1["name"] == Person.name(p)))
  end

  test "the node has its registries, its people, its constructions, its census and the cache of bricks; the server only with WORLD_SERVER" do
    names = for {_, _, _, _} = c <- Supervisor.which_children(World.Supervisor), do: elem(c, 0)
    assert World.Census in names and World.Sculpt.Cache in names
    assert World.Supervisor.server(%{}) == []
    assert World.Supervisor.yard(%{}) == []
    assert World.Supervisor.yard(%{"WORLD_YARD" => "true"}) == [World.Haul, World.Yard]
    [{Bandit, opts}] = World.Supervisor.server(%{"WORLD_SERVER" => "true", "PORT" => "4100"})
    assert opts[:plug] == World.Service and opts[:port] == 4100
    [{Bandit, opts}] = World.Supervisor.server(%{"WORLD_SERVER" => "true"})
    assert opts[:port] == 4000
    assert length(World.Supervisor.children(%{})) == 7
  end

  property "two constructions never hold one person" do
    check all(
            steps <-
              list_of({member_of([0, 1, 2]), member_of([:hire, :release]), member_of([:mason, :steel])}, max_length: 30),
            max_runs: 25
          ) do
      s = census(limit: 3)
      cs = [construction(), construction(), construction()]

      Enum.reduce(steps, %{}, fn {i, act, trade}, held ->
        c = Enum.at(cs, i)

        case {act, Map.get(held, c, [])} do
          {:hire, _} ->
            Census.hire(trade, c, make_ref(), s)
            held

          {:release, [p | rest]} ->
            Census.release(p, c, s)
            Map.put(held, c, rest)

          {:release, []} ->
            held
        end
        |> collect(cs)
      end)

      people = Census.people(s)["people"]
      holders = for %{"by" => by, "name" => name} <- people, by, do: {name, by}
      assert length(Enum.uniq_by(holders, &elem(&1, 0))) == length(holders)
      assert length(people) <= 3
      stop_supervised!(s)
    end
  end

  # The people that each construction got so far.
  defp collect(held, cs) do
    receive do
      {c, {:hired, _, p}} -> if(c in cs, do: Map.update(held, c, [p], &[p | &1]), else: held) |> collect(cs)
    after
      20 -> held
    end
  end

  defp hire(s, trade, c), do: tap(make_ref(), &Census.hire(trade, c, &1, s))
end
