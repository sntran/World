defmodule World.ChangeTest do
  # A pause, a resume, a cancel and a change of a construction
  # (docs/plans/0001-people-build-on-demand.md, step 3).
  use ExUnit.Case, async: true

  alias World.{Build, BuildSpec, Detail, Drawing, Log, Orders}

  @moduletag :tmp_dir

  # A block of the mason that takes some time, a note, and a block on it.
  defp drawing(size) do
    %{
      "name" => "slow_blocks",
      "nodes" => [
        %{"name" => "note", "skill" => %{"note" => %{"size" => 0.5}}},
        %{"name" => "root", "skill" => %{"block" => %{"size" => size, "wait" => 300}}},
        %{
          "name" => "upper",
          "skill" => %{"block" => %{"size" => 0.5}},
          "from" => ["root"],
          "to" => "root",
          "at" => "top"
        },
        %{"name" => "mark", "skill" => %{"note" => %{}}, "from" => ["note"]}
      ]
    }
  end

  # The blocks with a slow block on the top, to pause after the upper block.
  defp tall(size) do
    slow = %{
      "name" => "top",
      "skill" => %{"block" => %{"size" => 0.2, "wait" => 1000}},
      "from" => ["upper"],
      "to" => "upper",
      "at" => "top"
    }

    update_in(drawing(size), ["nodes"], &(&1 ++ [slow]))
  end

  defp job(d, id), do: %{id: id, item: fn level -> Detail.with(level, fn -> Drawing.build(d) end) end, drawing: d}
  defp glb(d), do: Detail.with(:near, fn -> Drawing.build(d) end) |> Build.glb(level: :near)
  defp id, do: "change-#{System.unique_integer([:positive])}"
  defp started(log, task), do: Enum.count(Log.events(log), &(&1.kind == "task_started" and &1.data["task"] == task))

  test "a change in a pause keeps the nodes whose data is the same, and the people make the others again",
       %{tmp_dir: dir} do
    id = id()
    World.watch(id)
    {:ok, ^id} = World.build(Map.put(job(drawing(1.0), id), :budget, %{"workers" => 1}))
    assert_receive {:world, %{"kind" => "task_started", "data" => %{"task" => "root"}}}, 5_000
    assert World.pause(id) == :ok
    assert_receive {:world, %{"kind" => "paused", "data" => %{"in_hand" => 1}}}

    # The root is in hand: its result goes to nobody, and it is made again.
    assert World.change(id, job(drawing(2.0), "other")) == :ok
    assert_receive {:world, %{"kind" => "changed", "data" => %{"redo" => ["root"], "keep" => ["note", "mark"]}}}
    assert_receive {:world, %{"kind" => "task_dropped", "data" => %{"task" => "root"}}}, 5_000
    assert World.resume(id) == :ok

    assert {:ok, r} = World.await(id, 10_000)
    assert r.glb == glb(drawing(2.0))
    assert started(r.log, "note") == 1 and started(r.log, "root") == 2
    assert Log.check(r.log) == :ok
    assert BuildSpec.replay([r.log], dir) == :ok
  end

  test "a change takes down each built element that it drops, the last built first; a change of the lot drops each",
       %{tmp_dir: dir} do
    id = id()
    World.watch(id)
    {:ok, ^id} = World.build(Map.put(job(tall(1.0), id), :budget, %{"workers" => 1}))
    assert_receive {:world, %{"kind" => "element", "data" => %{"task" => "upper"}}}, 5_000
    assert World.pause(id) == :ok
    assert_receive {:world, %{"kind" => "paused"}}

    # The root changes, so the upper block on it: both come down, the upper first.
    assert World.change(id, job(tall(2.0), "other")) == :ok
    assert_receive {:world, %{"kind" => "changed", "data" => %{"remove" => [up, root]}}}
    assert up == %{"id" => "remove/upper", "action" => "remove", "waits" => [], "trade" => "mason"}
    assert root["id"] == "remove/root" and root["waits"] == ["remove/upper"]
    assert World.resume(id) == :ok
    assert {:ok, r} = World.await(id, 10_000)
    assert r.glb == glb(tall(2.0))
    kinds = for e <- Log.events(r.log), e.kind in ~w(element_removed element), do: {e.kind, e.data["task"]}
    gone = Enum.filter(kinds, &(elem(&1, 0) == "element_removed"))
    assert gone == [{"element_removed", "upper"}, {"element_removed", "root"}]
    # The root comes back after it came down.
    assert for({k, "root"} <- kinds, do: k) == ~w(element element_removed element)
    # To take down a part takes a third of its days.
    started = for e <- Log.events(r.log), e.kind == "task_started", into: %{}, do: {e.data["task"], e.data["days"]}
    assert_in_delta started["remove/root"], 0.125 / 3, 1.0e-9
    assert Log.check(r.log) == :ok
    assert BuildSpec.replay([r.log], dir) == :ok

    # A change of the lot: each built node comes down, and is made again.
    id = id()
    World.watch(id)
    {:ok, ^id} = World.build(Map.put(job(tall(1.0), id), :budget, %{"workers" => 1}))
    assert_receive {:world, %{"kind" => "element", "order" => ^id, "data" => %{"task" => "root"}}}, 5_000
    assert World.pause(id) == :ok
    assert_receive {:world, %{"kind" => "paused", "order" => ^id}}, 5_000
    assert World.change(id, Map.merge(job(tall(1.0), "other"), %{lot: "cape", geo: %{"at" => [1, 2, 3]}})) == :ok

    assert_receive {:world,
                    %{
                      "kind" => "changed",
                      "order" => ^id,
                      "data" => %{"lot" => "cape", "keep" => [], "remove" => [%{"id" => "remove/" <> _} | _]}
                    }}

    assert World.resume(id) == :ok
    assert {:ok, r} = World.await(id, 10_000)
    assert started(r.log, "note") == 2
    assert Log.check(r.log) == :ok
  end

  test "a pause gives no task until the resume; a pause and a resume twice change nothing", %{tmp_dir: dir} do
    id = id()
    World.watch(id)
    {:ok, ^id} = World.build(job(drawing(1.0), id))
    assert_receive {:world, %{"kind" => "task_started", "data" => %{"task" => "root"}}}, 5_000
    assert World.pause(id) == :ok and World.pause(id) == :ok
    assert_receive {:world, %{"kind" => "task_done", "data" => %{"task" => "root"}}}, 5_000
    refute_receive {:world, %{"kind" => "task_started", "data" => %{"task" => "upper"}}}, 300
    assert World.resume(id) == :ok and World.resume(id) == :ok
    assert {:ok, r} = World.await(id, 10_000)
    assert r.glb == glb(drawing(1.0))
    assert Enum.count(Log.events(r.log), &(&1.kind == "paused")) == 1
    assert BuildSpec.replay([r.log], dir) == :ok
  end

  test "a cancel stops a construction, and the errors of a change" do
    id = id()
    World.watch(id)
    {:ok, ^id} = World.build(job(drawing(1.0), id))
    assert_receive {:world, %{"kind" => "task_started", "data" => %{"task" => "root"}}}, 5_000
    assert World.change(id, job(drawing(2.0), "x")) == {:error, :not_paused}
    World.pause(id)
    assert World.change(id, %{job(drawing(2.0), "x") | drawing: nil}) == {:error, :not_a_drawing}
    other = update_in(drawing(2.0), ["nodes"], &Enum.take(&1, 3))
    assert World.change(id, job(other, "x")) == {:error, :other_nodes}
    assert World.cancel(id) == :ok
    assert {:error, {:stopped, "cancelled"}} = World.await(id, 5_000)
    # The registry takes the name out when the process has stopped.
    assert Enum.find(1..200, fn _ -> Registry.lookup(World.Names, id) == [] or (Process.sleep(10) && false) end)

    for f <- [&World.pause/1, &World.resume/1, &World.cancel/1], do: assert(f.(id) == {:error, :none})
    assert World.change(id, job(drawing(2.0), "x")) == {:error, :none}
  end

  @tag timeout: 300_000
  test "the statue at far: a pause after its base, a change of its height, a resume: the base stays", %{tmp_dir: dir} do
    order = fn height -> %{"blueprint" => "statue", "options" => %{"height" => height}} end
    {:ok, job} = Orders.job(order.(32.0), "far")
    World.watch(job.id)
    {:ok, id} = World.build(Map.put(job, :budget, %{"workers" => 1}))
    assert_receive {:world, %{"kind" => "task_done", "data" => %{"task" => "be"}}}, 60_000
    World.pause(id)
    assert_receive {:world, %{"kind" => "paused"}}
    {:ok, taller} = Orders.job(order.(30.0), "far")
    assert World.change(id, taller) == :ok
    assert_receive {:world, %{"kind" => "changed", "data" => %{"keep" => ["be"]}}}
    World.resume(id)

    assert {:ok, r} = World.await(id, 300_000)
    expected = World.GLB.encode(taller.scene.(taller.item.(:far), []))
    assert r.glb == expected
    assert started(r.log, "be") == 1
    assert BuildSpec.replay([r.log], dir) == :ok
  end
end
