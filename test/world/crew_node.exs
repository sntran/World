# One of the two Erlang nodes of `test/world/crew_nodes_test.exs` (plan
# 0012, R6): a VM of its own, with the name and the node to join from
# the environment (`World.Supervisor.crews/1`). It says its results in
# lines `RESULT key value`.
#
#   mix run --no-compile test/world/crew_node.exs lead|guest
alias World.Crew

[role] = System.argv()
say = fn key, value -> IO.puts("RESULT #{key} #{value}") end

wait = fn wait, done?, tries ->
  cond do
    done?.() -> :ok
    tries == 0 -> raise "the two nodes did not get there: #{inspect(Crew.state())}"
    true -> Process.sleep(20) && wait.(wait, done?, tries - 1)
  end
end

# The hash of the file of a model from edits at near, made here (with an empty cache of bricks).
build = fn ->
  World.Sculpt.Cache.clear()
  {:ok, model} = World.Catalog.fetch("dog_edits")
  glb = World.Build.glb(World.Detail.with(:near, model), level: :near)
  Base.encode16(:crypto.hash(:sha256, glb), case: :lower)
end

# The tasks of the other node now (the jobs that it does for this node).
theirs = fn other -> Task.Supervisor.children({World.Crew.Tasks, other}) end

case role do
  "guest" ->
    # This node shares its workers with the other node.
    wait.(wait, fn -> length(Crew.state().nodes) == 2 end, 3_000)
    say.("joined", true)
    Process.sleep(:infinity)

  "lead" ->
    wait.(wait, fn -> length(Crew.state().nodes) == 2 end, 3_000)
    [other] = Crew.state().nodes -- [node()]
    say.("workers", Crew.state().workers)
    # Small jobs: the tasks of each node do some. (The function of a
    # job is of a module that the two nodes have: a function of this
    # file is not on the other node.)
    done = Crew.map(List.duplicate(&Node.self/0, 20_000), &:timer.tc/1)
    counts = Enum.frequencies_by(done, &elem(&1, 1))
    say.("jobs_here", Map.get(counts, node(), 0))
    say.("jobs_there", Map.get(counts, other, 0))

    # A model: a process counts the looks at the other node where it has tasks of this build.
    me = self()

    watch =
      spawn_link(fn ->
        look = fn look, seen ->
          receive do
            :stop -> send(me, {:seen, seen})
          after
            5 -> look.(look, seen + if(theirs.(other) == [], do: 0, else: 1))
          end
        end

        look.(look, 0)
      end)

    say.("first", build.())
    send(watch, :stop)

    receive do
      {:seen, seen} -> say.("looks_with_their_tasks", seen)
    end

    # The model again: the other node stops while it has tasks of this build.
    spawn_link(fn ->
      wait.(wait, fn -> theirs.(other) != [] end, 3_000)
      Process.sleep(300)
      :erpc.cast(other, System, :halt, [0])
      send(me, :halted)
    end)

    say.("second", build.())

    receive do
      :halted -> say.("halted_in_the_build", true)
    after
      0 -> say.("halted_in_the_build", false)
    end

    wait.(wait, fn -> Crew.state().nodes == [node()] end, 500)
    # The node works alone again.
    say.("third", build.())
end
