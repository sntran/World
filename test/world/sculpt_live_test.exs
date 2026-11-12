defmodule World.Sculpt.LiveTest do
  # A live sculpture takes a change of one edit at a time, and sends the
  # new pieces of its surface to each watcher (plan 0008, D11, R8). It
  # uses the cache of the node, so the tests are not async.
  use ExUnit.Case, async: false

  alias World.{Frame, SDF, Sculpt, Stone}
  alias World.Sculpt.{Cache, Live}

  @step 0.04

  setup do
    Cache.clear()
    name = {:test, System.unique_integer([:positive])}
    on_exit(fn -> Live.stop(name) end)
    {:ok, name: name}
  end

  # The events of a live sculpture to its version `v`.
  defp events(name, v, acc \\ []) do
    receive do
      {:sculpture, ^name, {:done, ^v}} -> Enum.reverse(acc)
      {:sculpture, ^name, {:failed, ^v, reason}} -> {:failed, reason}
      {:sculpture, ^name, event} -> events(name, v, [event | acc])
    after
      60_000 -> flunk("no event of version #{v}")
    end
  end

  defp moved(edit, dz),
    do:
      SDF.edit(edit.shape, edit.size,
        frame: Frame.compose(Frame.move({0.0, 0.0, dz}), edit.frame),
        mode: edit.mode,
        blend: edit.blend
      )

  test "a live sculpture sends its pieces, and after a change only the pieces of the bricks that the change reaches", %{
    name: name
  } do
    edits = Stone.edits(60)
    Live.watch(name)
    {:ok, _} = Live.start(name, edits, step: @step)
    first = events(name, 0)
    %{bricks: bricks} = Sculpt.bricks(edits, @step)
    assert length(first) == length(bricks) and Enum.all?(first, &match?({:piece, _, _}, &1))
    assert Live.meshes(name) == Sculpt.model(edits, step: @step)

    {:ok, 1} = Live.edit(name, 10, moved(Enum.at(edits, 10), 0.05))
    change = events(name, 1)
    assert change != [] and length(change) < length(bricks) / 3
    edits = List.replace_at(edits, 10, moved(Enum.at(edits, 10), 0.05))
    assert Live.meshes(name) == Sculpt.model(edits, step: @step, cache: false)
    assert %{version: 1, busy: false, edits: ^edits} = Live.info(name)
  end

  test "an edit at the end, an edit taken away, a wrong index", %{name: name} do
    edits = Stone.edits(20)
    Live.watch(name)
    {:ok, _} = Live.start(name, edits, step: @step)
    first = events(name, 0)
    ball = SDF.edit(:ball, {0.3}, frame: Frame.move({1.2, 0.0, 0.0}))
    {:ok, 1} = Live.edit(name, 20, ball)
    added = events(name, 1)
    assert added != [] and Enum.all?(added, &match?({:piece, _, _}, &1))
    # Without the ball, its bricks go, and the bricks of the stone near it
    # have their old pieces again.
    {:ok, 2} = Live.edit(name, 20, nil)
    taken = events(name, 2)
    at = fn events -> MapSet.new(events, &elem(&1, 1)) end
    gone = for {:gone, a} <- taken, into: MapSet.new(), do: a
    assert gone == MapSet.difference(at.(added), at.(first)) and gone != MapSet.new()
    assert at.(taken) == at.(added)
    assert Live.meshes(name, budget: 500) == Sculpt.model(edits, step: @step, budget: 500)
    assert Live.edit(name, 21, ball) == {:error, :index}
    assert Live.edit(name, 20, nil) == {:error, :index}
    assert Live.edit(name, -1, ball) == {:error, :index}
  end

  test "a new edit while the last one is in work stops that work and its crew: the newest edit wins", %{name: name} do
    edits = Stone.edits(40)
    Live.watch(name)
    {:ok, _} = Live.start(name, edits, step: 0.02)
    events(name, 0)

    # A big new ball: many new bricks. Then, at once, a change of it.
    big = SDF.edit(:ball, {0.6}, frame: Frame.move({1.0, 0.0, 0.0}))
    {:ok, 1} = Live.edit(name, 40, big)
    {:ok, 2} = Live.edit(name, 40, moved(big, 0.1))
    events(name, 2)
    refute_received {:sculpture, ^name, {:done, 1}}
    assert Live.meshes(name) == Sculpt.model(edits ++ [moved(big, 0.1)], step: 0.02)
    assert Enum.filter(Process.list(), &match?({:sculpture_work, ^name, _}, :proc_lib.get_label(&1))) == []
  end

  @tag :capture_log
  test "a work that fails sends its reason; a sculpture that is not there", %{name: name} do
    Live.watch(name)
    {:ok, _} = Live.start(name, [%{SDF.edit(:ball, {0.3}) | size: nil}], step: @step)
    assert {:failed, _} = events(name, 0)
    assert %{busy: false} = Live.info(name)
    # A message that is not for it (a piece of an old work) changes nothing.
    [{pid, _}] = Registry.lookup(World.Names, {:sculpture, name})
    send(pid, {:piece, 7, {0, 0, 0}, "key", %{}})
    assert %{version: 0, bricks: 0} = Live.info(name)
    assert Live.stop(name) == :ok
    assert Live.info(name) == {:error, :none}
    assert Live.meshes(name) == {:error, :none}
    assert Live.stop(name) == {:error, :none}
    assert Live.edit({:never, name}, 0, nil) == {:error, :none}
  end

  test "a sculpture at the level near by default; a sculpture that stops in a call" do
    name = {:near, System.unique_integer([:positive])}
    Live.watch(name)
    {:ok, _} = Live.start(name, [SDF.edit(:ball, {0.05})])
    assert [_ | _] = events(name, 0)
    assert Live.meshes(name) == Sculpt.model([SDF.edit(:ball, {0.05})], level: :near)
    Live.stop(name)

    # A process with the name of a sculpture that stops at the first message.
    me = self()

    spawn(fn ->
      {:ok, _} = Registry.register(World.Names, {:sculpture, :gone}, :erlang.alias([:priority]))
      send(me, :ready)
      receive do: (_ -> exit(:normal))
    end)

    assert_receive :ready
    assert Live.info(:gone) == {:error, :none}
  end
end
