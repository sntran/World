defmodule World.WorkTest do
  # The people of a site at work (plan 0006, D10; R8): the animations of
  # the work of each trade, the props of a site, and a person with them.
  use ExUnit.Case, async: true

  alias World.Orders
  alias World.People.{Pose, Props}

  test "the work of the trades: a loop of two poses for each, and the props of a site" do
    assert Pose.work() == ~w(carry set_panel pour trowel hammer climb guide)
    for w <- Pose.work(), do: assert({2.0, 10, [{0.0, %{}}, {1.0, %{}}]} = Pose.routine(w))
    # The work of a site is not a routine of exercise.
    assert Enum.all?(Pose.work(), &(&1 not in Pose.routines()))

    for name <- ~w(hard_hat bucket trowel hammer) do
      part = Props.prop(name)
      assert part.shapes != [] and part.sources != []
      assert Map.has_key?(part.ports, Props.on(name)), name
    end

    assert Props.on("hard_hat") == "crown" and Props.on("hammer") == "grip"
  end

  test "a person of a site: the walk and the work of each trade as animations, a hard hat and a trowel" do
    order = %{
      "blueprint" => "person",
      "options" => %{"animations" => ["walk" | Pose.work()], "hat" => "hard_hat", "right_hand" => "trowel"}
    }

    assert {:ok, glb} = Orders.build(order, "far", "glb")
    <<"glTF", _::binary-8, n::little-32, "JSON", json::binary-size(n), _::binary>> = glb
    gltf = JSON.decode!(json)
    # Each clip of the order (and the blink of the eyes of each person).
    assert ["walk" | Pose.work()] -- Enum.map(gltf["animations"], & &1["name"]) == []
    assert gltf["skins"] != []
    # The hard hat (orange) and the trowel (a blade of steel on a handle of wood).
    assert ~w(orange steel wood) -- Enum.map(gltf["materials"], & &1["name"]) == []
  end
end
