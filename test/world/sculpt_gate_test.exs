defmodule World.Sculpt.GateTest do
  # The gate of the sculptures of the node (plan 0011, D7).
  use ExUnit.Case, async: true

  alias World.Sculpt.Gate

  # A process that goes into the gate (or into its line), tells the
  # test, and stays until the test lets it go.
  defp build(gate, name) do
    test = self()
    %{in: builds, waiting: waiting} = Gate.state(gate)

    pid =
      spawn_link(fn ->
        Gate.with(
          fn ->
            send(test, {:in, name})

            receive do
              :go -> :ok
            end
          end,
          gate
        )

        send(test, {:out, name})
      end)

    # The gate has the process now: the next process comes after it.
    settled(gate, &(&1.in + &1.waiting == builds + waiting + 1))
    pid
  end

  # The state of the gate when it is as the test needs (a process goes out with a message that takes some time).
  defp settled(gate, done?, tries \\ 200) do
    state = Gate.state(gate)

    cond do
      done?.(state) ->
        state

      tries > 0 ->
        Process.sleep(5)
        settled(gate, done?, tries - 1)
    end
  end

  test "the builds go in while the gate has room, and the others wait in their order" do
    {:ok, gate} = Gate.start_link(name: nil, room: 2)
    [a, b, c, d] = for name <- ~w(a b c d)a, do: build(gate, name)
    assert_receive {:in, :a}
    assert_receive {:in, :b}
    refute_receive {:in, _}, 50
    assert Gate.state(gate) == %{in: 2, waiting: 2, room: 2}
    # One goes out: the first that waits goes in.
    send(b, :go)
    assert_receive {:out, :b}
    assert_receive {:in, :c}
    refute_receive {:in, :d}, 50
    for pid <- [a, c, d], do: send(pid, :go)
    assert_receive {:in, :d}
    for name <- ~w(a c d)a, do: assert_receive({:out, ^name})
    assert settled(gate, &(&1.in == 0)) == %{in: 0, waiting: 0, room: 2}
  end

  test "a build that stops goes out of the gate, in work or in the line; a build that raises goes out too" do
    {:ok, gate} = Gate.start_link(name: nil, room: 1)
    Process.flag(:trap_exit, true)
    a = build(gate, :a)
    assert_receive {:in, :a}
    b = build(gate, :b)
    c = build(gate, :c)
    assert Gate.state(gate).waiting == 2
    # The build in the line stops: the next one keeps its place.
    Process.exit(b, :kill)
    assert_receive {:EXIT, ^b, :killed}
    assert settled(gate, &(&1.waiting == 1)) == %{in: 1, waiting: 1, room: 1}
    # The build in work stops: the next one goes in.
    Process.exit(a, :kill)
    assert_receive {:in, :c}
    send(c, :go)
    assert_receive {:out, :c}
    assert catch_error(Gate.with(fn -> raise "no" end, gate)) == %RuntimeError{message: "no"}
    assert Gate.with(fn -> :done end, gate) == :done
    assert settled(gate, &(&1.in == 0)).waiting == 0
  end

  test "with a limit of memory, a build waits while the VM has more, but not when no build works" do
    {:ok, memory} = Agent.start_link(fn -> 300 end)
    read = fn -> {"total", Agent.get(memory, & &1) * 1_048_576} end
    {:ok, gate} = Gate.start_link(name: nil, room: 3, memory_mb: 200, memory: read)
    # No build works: the first goes in, with any memory.
    a = build(gate, :a)
    assert_receive {:in, :a}
    b = build(gate, :b)
    refute_receive {:in, :b}, 50
    # The memory has room now, but the gate looks only when a build comes or goes.
    Agent.update(memory, fn _ -> 100 end)
    c = build(gate, :c)
    assert_receive {:in, :b}
    assert_receive {:in, :c}
    for pid <- [a, b, c], do: send(pid, :go)
    for name <- ~w(a b c)a, do: assert_receive({:out, ^name})
  end

  test "the node has a gate with room for half of its schedulers; with no gate, the work is done now" do
    assert Gate.state().room == max(div(System.schedulers_online(), 2), 1)
    assert Gate.with(fn -> 1 + 1 end) == 2
    assert Gate.with(fn -> :now end, :no_gate_with_this_name) == :now
  end
end
