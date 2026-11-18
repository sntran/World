defmodule World.LabourTest do
  # The labour of the parts: here, or on a native node (in these tests, a
  # supervisor of tasks of this node is in the place of a native node).
  # (Not async: the line of the builds and the store.)
  use ExUnit.Case

  import ExUnit.CaptureLog
  alias World.{Elements, Labour}
  alias World.Elements.Store

  @moduletag timeout: 600_000

  # A group of two people: each person is a part with a recipe.
  @group %{"blueprint" => "exercise", "options" => %{"count" => 1}}

  defp parts(level) do
    {:ok, list} = Elements.list(@group, level)
    for p <- list["parts"], do: {p["key"], JSON.decode!(elem(Store.recipe(p["key"]), 1))}
  end

  test "where a part builds: here with no native node, and a person at mid or far; the rest on a native node" do
    node = [{:a_node, 4}]
    assert Labour.here?(%{"piece" => "leader", "level" => "near"}, [])
    assert Labour.here?(%{"node" => "wall", "level" => "near", "tile" => nil}, [])
    assert Labour.here?(%{"piece" => "leader", "level" => "far"}, node)
    assert Labour.here?(%{"piece" => "leader", "level" => "mid"}, node)
    refute Labour.here?(%{"piece" => "leader", "level" => "near"}, node)
    refute Labour.here?(%{"node" => "wall", "level" => "far", "tile" => nil}, node)
  end

  test "a native node builds a part by its key, puts it in the store, and gives back only the key" do
    [{key, recipe} | _] = parts("near")
    {:ok, a} = Task.Supervisor.start_link()
    {:ok, b} = Task.Supervisor.start_link()
    assert Labour.build(key, recipe, nodes: [{a, 2}, {b, 2}]) == :stored
    assert Store.has?(key)
    assert Labour.busy(a) == 0 and Labour.busy(b) == 0

    # A node that went away: the part builds on the next node; with no node left, here.
    gone = spawn(fn -> :ok end)
    Process.sleep(10)
    assert Labour.build(key, recipe, nodes: [{gone, 8}, {b, 2}]) == :stored
    assert {:ok, <<"glTF", _::binary>>} = Labour.build(key, recipe, nodes: [{gone, 8}])
    # With no native node, and a person at far: here.
    [{far, far_recipe} | _] = parts("far")
    assert {:ok, <<"glTF", _::binary>>} = Labour.build(far, far_recipe, nodes: [{a, 2}])
    assert {:ok, _} = Labour.build(far, far_recipe, nodes: [])
  end

  test "a part that raises on a node builds on the next one, and raises here when no node is left" do
    [{_key, recipe} | _] = parts("near")
    # (A recipe of a person that the group does not have: its make raises.)
    bad = String.duplicate("b", 32)
    :ok = Store.put_recipe(bad, JSON.encode!(%{recipe | "piece" => "nobody"}))
    {:ok, a} = Task.Supervisor.start_link()

    capture_log(fn ->
      assert_raise MatchError, fn -> Labour.build(bad, %{recipe | "piece" => "nobody"}, nodes: [{a, 2}]) end
    end)

    # A key with no recipe: nothing to build.
    assert Labour.make(String.duplicate("c", 32)) == :none
  end
end
