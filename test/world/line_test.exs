defmodule World.LineTest do
  # The line of the builds of a request, in two classes (plan 0019, 4.3).
  use ExUnit.Case, async: true

  alias World.Line

  defp line(slots) do
    name = :"line_#{System.unique_integer([:positive])}"
    start_supervised!({Line, slots: slots, name: name}, id: name)
    name
  end

  # A build that holds its place in the line until the test lets it go.
  defp hold(line, class, tag) do
    test = self()

    spawn(fn ->
      Line.run(
        class,
        fn ->
          send(test, {:in, tag})
          receive(do: (:go -> :ok))
        end,
        line
      )

      send(test, {:out, tag})
    end)
  end

  defp wait(line, fun), do: if(fun.(Line.state(line)), do: :ok, else: wait(line, fun))

  test "a build runs in the process of the call and gives its result; a build that raises leaves the line" do
    line = line(1)
    assert Line.run(:now, fn -> self() end, line) == self()
    assert_raise RuntimeError, fn -> Line.run(:batch, fn -> raise "no" end, line) end
    assert Line.run(fn -> 7 end) == 7
    assert Line.state(line) == %{slots: 1, working: 0, now: 0, batch: 0}
    # The line of the node has one place by default.
    assert %{slots: slots, batch: 0} = Line.state()
    assert slots >= 1
  end

  test "one build at a time: a build that a person waits for goes before the builds of a batch" do
    line = line(1)
    first = hold(line, :batch, :first)
    assert_receive {:in, :first}
    batch_1 = hold(line, :batch, :batch_1)
    batch_2 = hold(line, :batch, :batch_2)
    wait(line, &(&1.batch == 2))
    now = hold(line, :now, :now)
    wait(line, &(&1.now == 1))
    assert Line.state(line) == %{slots: 1, working: 1, now: 1, batch: 2}

    send(first, :go)
    assert_receive {:in, :now}
    refute_received {:in, :batch_1}
    send(now, :go)
    # In a class, the first to come is the first to go.
    assert_receive {:in, :batch_1}
    send(batch_1, :go)
    assert_receive {:in, :batch_2}
    send(batch_2, :go)
    assert_receive {:out, :batch_2}
    wait(line, &(&1.working == 0))
  end

  test "two places: two builds at one time" do
    line = line(2)
    a = hold(line, :now, :a)
    b = hold(line, :now, :b)
    assert_receive {:in, :a}
    assert_receive {:in, :b}
    c = hold(line, :now, :c)
    wait(line, &(&1.now == 1))
    refute_received {:in, :c}
    send(a, :go)
    assert_receive {:in, :c}
    for pid <- [b, c], do: send(pid, :go)
    wait(line, &(&1.working == 0))
  end

  test "a build that stops with no word leaves its place, in work or in the line" do
    line = line(1)
    working = hold(line, :now, :working)
    assert_receive {:in, :working}
    waiting = hold(line, :now, :waiting)
    wait(line, &(&1.now == 1))
    Process.exit(waiting, :kill)
    wait(line, &(&1.now == 0))
    next = hold(line, :batch, :next)
    wait(line, &(&1.batch == 1))
    Process.exit(working, :kill)
    assert_receive {:in, :next}
    send(next, :go)
    assert_receive {:out, :next}
  end
end
