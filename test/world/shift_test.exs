defmodule World.ShiftTest do
  # A construction shift: on the edge, when to start one; on its runner,
  # its record, its end and its summary. (Not async: the shift has one
  # name on the node, and its end stops the tasks of the crews.)
  use ExUnit.Case

  alias World.{Elements, Shift}
  alias World.Elements.Store

  @moduletag :tmp_dir

  test "the edge wants a shift when parts wait and no node of a shift takes them, or each has less than 15 minutes left" do
    node = [{{World.Crew.Tasks, :a@h}, 4}]
    refute Shift.wanted?(waiting: 0, nodes: [])
    assert Shift.wanted?(waiting: 2, nodes: [])
    # A node that is not a shift (no time left): it takes the parts.
    refute Shift.wanted?(waiting: 2, nodes: node, left: fn _ -> nil end)
    assert Shift.wanted?(waiting: 2, nodes: node, left: fn _ -> 10 * 60_000 end)
    refute Shift.wanted?(waiting: 2, nodes: node, left: fn _ -> 60 * 60_000 end)
    # The time left of a node, from the node: this node is not a shift; a node that does not answer has no time.
    refute Shift.wanted?(waiting: 1, nodes: [{{World.Crew.Tasks, node()}, 4}])
    assert Shift.wanted?(waiting: 1, nodes: [{{World.Crew.Tasks, :nobody@nowhere}, 4}])
    # The queue and the nodes of this node: no part waits.
    refute Shift.wanted?()
    assert Shift.left() == nil
  end

  test "with no shift, the work of a part is only its make" do
    assert Shift.work("k", fn -> :stored end) == :stored
  end

  test "a shift keeps each part, goes home after its idle time, and writes its summary", %{tmp_dir: dir} do
    {:ok, list} = Elements.list(%{"blueprint" => "exercise", "options" => %{"count" => 1}}, "far")
    key = hd(list["parts"])["key"]
    me = self()
    summary = Path.join(dir, "summary.md")
    until = System.system_time(:millisecond) + 3_600_000

    shift =
      start_supervised!(
        {Shift, until: until, idle: 50, tick: 10, summary: summary, stop: fn status -> send(me, {:stop, status}) end}
      )

    assert Shift.left() in 3_500_000..3_600_000

    assert Shift.work(key, fn -> :stored end, ["vung_tau", "tre"]) == :stored

    assert Shift.work("f" <> String.duplicate("0", 31), fn -> {:error, [%{"message" => "no memory"}]} end, ["tre"]) ==
             {:error, [%{"message" => "no memory"}]}

    assert Shift.work("e" <> String.duplicate("0", 31), fn -> :none end) == :none
    assert_raise RuntimeError, fn -> Shift.work(key, fn -> raise "a fault" end) end

    ref = Process.monitor(shift)
    assert_receive {:stop, 0}, 2_000
    assert_receive {:DOWN, ^ref, :process, _, :normal}
    text = File.read!(summary)
    assert text =~ "4 parts in 0 minutes. The end: no work."
    assert text =~ "| vung_tau, tre | leader (far) | `#{key}` |" and text =~ "| stored |"
    # The parts of each project: a part of two projects counts for each, and a key that a node
    # makes two times counts two times, with its projects of before; a part of no project is "-".
    assert text =~ ~r/\| vung_tau \| 2 \| 1 \| \d+\.\d \|/
    assert text =~ ~r/\| tre \| 3 \| 1 \| \d+\.\d \|/
    assert text =~ ~r/\| - \| 1 \| 0 \| \d+\.\d \|/
    assert length(Regex.scan(~r/\| vung_tau, tre \| leader \(far\)/, text)) == 2

    assert text =~
             ~r/### The parts of each project\n\n\| Project \| Parts \| Stored \| Time \(s\) \|\n\|---\|---\|---\|---\|\n\| vung_tau /

    assert text =~ "error: no memory" and text =~ "no recipe" and text =~ "raised: a fault"
    assert text =~ "| ? |"
    assert Shift.left() == nil
  end

  test "at the end of its time, a shift stops the parts in work: they go back to the queue of the edge", %{tmp_dir: dir} do
    me = self()
    summary = Path.join(dir, "summary.md")

    # A part in work, in a task of the crews.
    until = System.system_time(:millisecond) + 300

    shift =
      start_supervised!(
        {Shift, until: until, tick: 10, summary: summary, stop: fn status -> send(me, {:stop, status}) end}
      )

    ref = Process.monitor(shift)

    task =
      Task.Supervisor.async_nolink(World.Crew.Tasks, fn ->
        Shift.work("a" <> String.duplicate("0", 31), fn -> Process.sleep(:infinity) end)
      end)

    assert Task.yield(task, 5_000) == {:exit, :shutdown}
    assert_receive {:stop, 0}, 2_000
    text = File.read!(summary)
    assert text =~ "0 parts" and text =~ "The end: the end of the time of the shift."
    assert text =~ "(`a#{String.duplicate("0", 31)}`, -): stopped at the end; it goes back to the queue"
    assert_receive {:DOWN, ^ref, :process, _, :normal}

    # A shift with no summary file, and no part: it ends too.
    start_supervised!(
      {Shift, until: System.system_time(:millisecond), tick: 10, stop: fn status -> send(me, {:stop, status}) end},
      id: :again
    )

    assert_receive {:stop, 0}, 2_000
    refute Store.has?("a" <> String.duplicate("0", 31))
  end

  test "with no connection to the edge for its time, a shift stops with the exit status of a new join", %{tmp_dir: dir} do
    me = self()
    summary = Path.join(dir, "summary.md")
    {:ok, here} = Agent.start_link(fn -> [:edge@h] end)

    shift =
      start_supervised!(
        {Shift,
         until: System.system_time(:millisecond) + 3_600_000,
         tick: 10,
         lost: 100,
         edge: :edge@h,
         connected: fn -> Agent.get(here, & &1) end,
         summary: summary,
         stop: fn status -> send(me, {:stop, status}) end}
      )

    # (While the edge is connected, the shift goes on.)
    refute_receive _, 200
    ref = Process.monitor(shift)
    Agent.update(here, fn _ -> [] end)
    assert_receive {:stop, 75}, 2_000
    assert_receive {:DOWN, ^ref, :process, _, :normal}
    assert File.read!(summary) =~ "The end: no connection to the edge for 0 s; a new join."
  end

  test "the shift of a runner from the environment" do
    assert World.Supervisor.shift(%{}) == []

    assert [{Shift, opts}] =
             World.Supervisor.shift(%{"WORLD_SHIFT_UNTIL" => "1700000000", "WORLD_SHIFT_SUMMARY" => "s.md"})

    assert opts == [until: 1_700_000_000_000, idle: 3_600_000, summary: "s.md", edge: nil]
    assert [{Shift, opts}] = World.Supervisor.shift(%{"WORLD_SHIFT_UNTIL" => "1", "WORLD_SHIFT_IDLE" => "5"})
    assert opts[:idle] == 300_000
    assert [{Shift, opts}] = World.Supervisor.shift(%{"WORLD_SHIFT_UNTIL" => "1", "WORLD_JOIN" => "world@127.0.0.1"})
    assert opts[:edge] == :"world@127.0.0.1"

    # The edge with shifts.
    before = Application.get_env(:world, :shifts)
    :ok = World.Supervisor.settings(%{"WORLD_SHIFTS" => "true"})
    assert Application.get_env(:world, :shifts) == true
    if before == nil, do: Application.delete_env(:world, :shifts), else: Application.put_env(:world, :shifts, before)
  end
end
