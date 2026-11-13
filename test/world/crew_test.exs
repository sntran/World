defmodule World.CrewTest do
  # The crews of the sites of the node (plan 0012, D6 to D8; R5).
  use ExUnit.Case, async: true

  alias World.Crew

  defp crews(opts), do: start_supervised!({Crew, [name: nil] ++ opts}, id: make_ref())

  # The state of the crews when it is as the test needs (a worker moves at the end of its job).
  defp settled(crews, done?, tries \\ 400) do
    state = Crew.state(crews)

    cond do
      done?.(state) ->
        state

      tries > 0 ->
        Process.sleep(5)
        settled(crews, done?, tries - 1)

      true ->
        flunk("the crews did not get there: #{inspect(state)}")
    end
  end

  # A site in a process of its own: a map of `count` jobs of `ms` each. It tells the test its result.
  defp site(crews, name, count, ms) do
    test = self()

    spawn_link(fn ->
      result =
        Crew.map(
          1..count,
          fn i ->
            Process.sleep(ms)
            {i, self()}
          end,
          crews
        )

      send(test, {:mapped, name, result})
    end)
  end

  defp workers(state, site), do: Enum.find_value(state.sites, 0, &(&1.site == site && &1.workers))

  test "a map: the results in the order of the items, each job in a worker; no items; no crews; a map in a job" do
    c = crews(workers: 4)
    me = self()
    assert Crew.map([], fn _ -> flunk("no job") end, c) == []
    done = Crew.map(1..200, fn i -> {i * i, self()} end, c)
    assert Enum.map(done, &elem(&1, 0)) == Enum.map(1..200, &(&1 * &1))
    used = done |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    assert me not in used and length(used) in 1..4
    # A list of one item, and more workers than jobs.
    assert Crew.map([:a], &{&1, 1}, c) == [{:a, 1}]
    # With no crews, the jobs are done here, one after the other.
    assert Crew.map(1..3, fn i -> {i, self()} end, :no_crews_with_this_name) == for(i <- 1..3, do: {i, me})
    # A job with jobs of its own does them in its worker.
    [{inner, worker}] = Crew.map([1], fn _ -> {Crew.map(1..3, fn i -> {i, self()} end, c), self()} end, c)
    assert inner == for(i <- 1..3, do: {i, worker})
    # The crews after the maps: no site, each worker free.
    assert settled(c, &(&1.sites == [])) == %{workers: 4, nodes: [node()], sites: []}
    assert Crew.census(c) == %{"workers" => 4, "nodes" => [Atom.to_string(node())], "sites" => []}
  end

  test "a job that raises, exits or throws stops its map with the same; the crews do the next map" do
    c = crews(workers: 3)

    assert_raise ArgumentError, "no", fn ->
      Crew.map(1..50, fn i -> if(i == 7, do: raise(ArgumentError, "no"), else: i) end, c)
    end

    assert catch_exit(Crew.map(1..50, fn i -> if(i == 3, do: exit(:gone), else: i) end, c)) == :gone
    assert catch_throw(Crew.map(1..50, fn i -> if(i == 9, do: throw(:ball), else: i) end, c)) == :ball
    # (The words of the maps that stopped do not stay in the way of the next map: a
    # late result, a late failure, a job that comes back, a worker that asks.)
    old = make_ref()
    [{_, worker}] = Crew.map([1], &{&1, self()}, c)
    send(self(), {:done, old, worker, 0, :late})
    send(self(), {:failed, old, worker, :error, :late, []})
    send(self(), {:back, old, worker, 0, :moved})
    send(self(), {:ready, old, worker, false})
    # (And a worker takes no word about a map that is not its map.)
    send(worker, {:none, old})
    # (An order that a worker has already changes nothing: the second of two.)
    order = make_ref()
    send(worker, {:serve, self(), order, c})
    send(worker, {:serve, self(), order, c})
    assert Crew.map(1..100, &(&1 + 1), c) == Enum.to_list(2..101)
    # (Only a worker that asks after the end of a map can have a word here: the next map answers it.)
    {:messages, left} = Process.info(self(), :messages)
    assert Enum.all?(left, &match?({:ready, _, _, _}, &1))
    assert Crew.map(1..100, &(&1 * 2), c) == Enum.map(1..100, &(&1 * 2))
    assert settled(c, &(&1.sites == [])).workers == 3
  end

  test "a worker that stops gives its job back, and the crews have a new worker; a site that stops frees its workers" do
    c = crews(workers: 3)
    {:ok, killed} = Agent.start_link(fn -> false end)

    done =
      Crew.map(
        1..40,
        fn i ->
          # One worker stops in the middle of its job, one time.
          if i == 5 and Agent.get_and_update(killed, &{&1, true}) == false, do: Process.exit(self(), :kill)
          Process.sleep(2)
          i
        end,
        c
      )

    assert done == Enum.to_list(1..40)
    assert settled(c, &(&1.sites == [])).workers == 3

    # A site with long jobs stops: its jobs in work stop at once (their
    # workers stop, and new workers take their places).
    Process.flag(:trap_exit, true)
    a = site(c, :a, 1_000, 5_000)
    [%{crew: [_, _, _] = busy}] = settled(c, &(workers(&1, a) == 3)).sites
    refs = for w <- busy, do: Process.monitor(w)
    Process.exit(a, :kill)
    assert_receive {:EXIT, ^a, :killed}
    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, :killed}, 100)
    assert settled(c, &(&1.sites == [])).workers == 3
    assert Crew.map(1..10, & &1, c) == Enum.to_list(1..10)
  end

  test "the workers go to the sites in equal parts, at most the jobs of a site (R5)" do
    c = crews(workers: 8)
    a = site(c, :a, 600, 10)
    # One site: all the workers.
    assert workers(settled(c, &(workers(&1, a) == 8)), a) == 8
    # Two sites: half each.
    b = site(c, :b, 600, 10)
    state = settled(c, &(workers(&1, a) == 4 and workers(&1, b) == 4))
    assert [%{site: ^a, jobs: jobs, workers: 4}, %{site: ^b, jobs: 600, workers: 4}] = state.sites

    assert %{"workers" => 8, "sites" => [%{"site" => "<" <> _, "jobs" => _, "workers" => 4}, %{"workers" => 4}]} =
             Crew.census(c)

    # The end of a map that is not the map of a site now does not take the site away.
    GenServer.cast(c, {:demand, a, make_ref(), 0})
    assert workers(Crew.state(c), a) == 4
    # (The jobs of a site: of its map at its start, or the jobs that wait when a worker gave a job back.)
    assert jobs in 1..600
    # A third site with two jobs has two workers; the others have three each.
    small = site(c, :small, 2, 400)
    assert workers(settled(c, &(workers(&1, small) == 2)), small) == 2
    state = settled(c, &(workers(&1, a) == 3 and workers(&1, b) == 3))
    assert workers(state, small) == 2
    # The small site ends: its workers go back to the others.
    assert_receive {:mapped, :small, [{1, _}, {2, _}]}, 5_000
    settled(c, &(workers(&1, a) == 4 and workers(&1, b) == 4))
    # Each site has its results in order, from workers of the crews.
    assert_receive {:mapped, :a, done_a}, 20_000
    assert_receive {:mapped, :b, done_b}, 20_000

    assert Enum.map(done_a, &elem(&1, 0)) == Enum.to_list(1..600) and
             Enum.map(done_b, &elem(&1, 0)) == Enum.to_list(1..600)

    assert settled(c, &(&1.sites == [])).workers == 8
  end

  test "crews that join other crews give their workers, and their sites get workers from there; they come home when the others go" do
    home = crews(workers: 2)
    Process.flag(:trap_exit, true)
    {:ok, lead} = Crew.start_link(name: nil, workers: 3)
    assert Crew.version() == Crew.version() and byte_size(Crew.version()) == 16
    # Crews with another code do not join.
    other = crews(workers: 1, version: "another code")
    assert Crew.join(lead, other) == {:error, :code}
    assert Crew.join(:nobody@nowhere, other) == {:error, :down}
    assert Crew.leave(other) == :ok

    assert Crew.join(lead, home) == :ok
    assert Crew.state(lead).workers == 5 and Crew.state(home).workers == 0
    # A site of the crews that joined gets the five workers.
    done = Crew.map(1..300, fn i -> {i, self()} end, home)
    assert Enum.map(done, &elem(&1, 0)) == Enum.to_list(1..300)
    used = done |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    assert length(used) in 3..5
    # A worker of the crews that joined stops: a new one takes its place in the other crews.
    victim = hd(:sys.get_state(home).own)
    Process.exit(victim, :kill)
    settled(lead, &(&1.workers == 5 and not is_map_key(:sys.get_state(lead).workers, victim)))
    assert victim not in :sys.get_state(home).own and length(:sys.get_state(home).own) == 2
    assert Enum.all?(:sys.get_state(home).own, &is_map_key(:sys.get_state(lead).workers, &1))
    # (A new worker of crews that did not join is not a worker of these crews.)
    send(lead, {:new, self(), self()})
    assert Crew.state(lead).workers == 5
    # A site of the other crews gets them too.
    a = site(lead, :a, 400, 10)
    assert workers(settled(lead, &(workers(&1, a) == 5)), a) == 5

    # The crews leave: their two workers are theirs again, and the site goes on with three.
    assert Crew.leave(home) == :ok
    assert Crew.state(home).workers == 2
    assert workers(settled(lead, &(workers(&1, a) == 3)), a) == 3
    assert Crew.map(1..20, & &1, home) == Enum.to_list(1..20)
    assert_receive {:mapped, :a, done}, 20_000
    assert Enum.map(done, &elem(&1, 0)) == Enum.to_list(1..400)

    # They join again; the other crews stop in the middle of a map of a site of home: the map ends at home.
    assert Crew.join(lead, home) == :ok
    b = site(home, :b, 300, 10)
    settled(lead, &(workers(&1, b) == 5))
    GenServer.stop(lead)
    assert_receive {:mapped, :b, done}, 20_000
    assert Enum.map(done, &elem(&1, 0)) == Enum.to_list(1..300)
    assert settled(home, &(&1.sites == [])).workers == 2
  end

  test "the node has crews with two workers for each scheduler; the census has them" do
    assert Crew.state().workers == 2 * System.schedulers_online()
    assert Crew.map(1..10, &(&1 * 3)) == Enum.map(1..10, &(&1 * 3))
    assert %{"crews" => %{"workers" => _, "nodes" => [_], "sites" => sites}, "people" => _} = World.census()
    assert is_list(sites)
  end
end
