defmodule World.Orders.EditsTest do
  # The edits of an order: a project asks for a model, looks at it, and sends small changes.
  use ExUnit.Case, async: true

  alias World.Orders
  alias World.Orders.Edits

  @order %{
    "blueprint" => "x",
    "options" => %{"height" => 2, "nodes" => [%{"name" => "roof", "sizes" => [1, 2]}, %{"name" => "wall"}]},
    "colors" => %{}
  }

  test "a set, a remove and an insert on an order: a key of an object, an item of a list by its index or its name" do
    edits = [
      %{"set" => "options.height", "to" => 3},
      %{"set" => "colors.paint", "to" => "#102030"},
      %{"set" => "options.nodes.0.sizes.1", "to" => 5},
      # The index of the count of the items adds an item at the end.
      %{"set" => "options.nodes.roof.sizes.2", "to" => 9},
      %{"insert" => "options.nodes.wall", "value" => %{"name" => "door"}},
      %{"insert" => "options.nodes.3", "value" => %{"name" => "last"}},
      %{"remove" => "options.nodes.roof.name"},
      %{"remove" => "options.nodes.wall"},
      %{"set" => "options.nodes.2", "to" => %{"name" => "end"}}
    ]

    assert {:ok, order} = Edits.change(@order, edits)
    assert order["colors"] == %{"paint" => "#102030"} and order["options"]["height"] == 3
    assert order["options"]["nodes"] == [%{"sizes" => [1, 5, 9]}, %{"name" => "door"}, %{"name" => "end"}]
    assert order["blueprint"] == "x"
  end

  test "an edit that is not possible gives its index and the reason; the edits before it are not kept" do
    wrong = [
      {%{"set" => "options.height"}, ~s(must be {"set": PATH, "to": VALUE})},
      {%{"set" => "options.height", "to" => 1, "more" => 1}, "must be"},
      {%{"remove" => ["options"]}, "must be"},
      {"remove options", "must be"},
      {%{"remove" => "options.width"}, "options.width: there is no width to remove"},
      {%{"insert" => "options.height", "value" => 1}, "options.height: an insert is for an item of a list"},
      {%{"set" => "options.sizes.height", "to" => 1}, "there is no sizes (the keys there: height, nodes)"},
      {%{"set" => "options.nodes.5", "to" => 1}, "the list has no item 5 (it has 2 items)"},
      {%{"remove" => "options.nodes.2"}, "the list has no item 2"},
      {%{"set" => "options.nodes.floor.name", "to" => 1}, "the list has no item floor"},
      {%{"set" => "options.nodes.2.name", "to" => 1}, "the list has no item 2"},
      {%{"set" => "options.height.deep", "to" => 1}, "the value before deep is not an object or a list"}
    ]

    for {edit, text} <- wrong do
      assert {:error, [%{"path" => "edits.1", "message" => message}]} =
               Edits.change(@order, [%{"set" => "options.height", "to" => 3}, edit])

      assert message =~ text
    end

    for edits <- [[], nil, %{"set" => "a", "to" => 1}] do
      assert {:error, [%{"path" => "edits", "message" => "must be a list of one edit or more"}]} =
               Edits.change(@order, edits)
    end
  end

  test "a palm with its specifications, then edits after a look at it: a new order with its parent and its history" do
    request = %{
      "blueprint" => "plant",
      "options" => %{"height" => 9, "numbers" => %{"fronds" => 14, "lean" => 20, "trunk" => 0.28}}
    }

    {:ok, first} = Orders.place(request, "https://world.mkfifo.com")
    assert Edits.history(first["hash"]) == [%{"hash" => first["hash"]}]

    edits = [
      %{"set" => "options.numbers.fronds", "to" => 32},
      %{"set" => "options.numbers.lean", "to" => 7},
      %{"remove" => "options.numbers.trunk"},
      %{"set" => "colors.leaf", "to" => "#5c9440"}
    ]

    assert {:ok, second} = Edits.place(first["hash"], edits, "https://world.mkfifo.com")
    assert second["parent"] == first["hash"] and second["hash"] != first["hash"]
    assert second["history"] == [%{"hash" => first["hash"]}, %{"hash" => second["hash"], "edits" => edits}]
    assert second["files"]["far.glb"] == "https://world.mkfifo.com/o/#{second["hash"]}.far.glb"
    assert %{"fronds" => 32.0, "lean" => 7.0, "trunk" => nil} = second["order"]["options"]["numbers"]
    assert second["order"]["colors"] == %{"leaf" => "#5c9440"} and second["order"]["options"]["height"] == 9
    # The new order is an order as each other one: the same order from a full request has the same hash.
    {:ok, same} = Orders.place(Map.take(second["order"], ~w(blueprint options colors)), "o")
    assert same["hash"] == second["hash"]

    # The palm of the new order has 32 fronds (a frond at near: its rachis and 36 leaflets).
    fronds = fn placed ->
      {:ok, job} = Orders.job(placed["order"], "near")
      [_, {_, crown, _} | _] = job.item.(:near).nodes
      div(length(crown.shapes), 37)
    end

    assert fronds.(first) == 14 and fronds.(second) == 32

    # An edit of the new order: the history has the three orders.
    {:ok, third} = Edits.place(second["hash"], [%{"set" => "options.height", "to" => 12}], "o")
    assert Enum.map(third["history"], & &1["hash"]) == [first["hash"], second["hash"], third["hash"]]
    assert Edits.history(third["hash"]) == third["history"]

    # An edit that the rules of the order refuse: the errors of the check, with their paths.
    assert {:error, [%{"path" => "options.numbers.fronds", "message" => "must be from " <> _}]} =
             Edits.place(second["hash"], [%{"set" => "options.numbers.fronds", "to" => 500}], "o")

    assert {:error, [%{"path" => "options.numbers.culms", "message" => "a coconut has no number culms: base, " <> _}]} =
             Edits.place(second["hash"], [%{"set" => "options.numbers.culms", "to" => 5}], "o")

    assert {:error, [%{"path" => "edits.0"}]} = Edits.place(second["hash"], [%{"remove" => "options.sizes"}], "o")

    # A hash that the store does not have, and a text that is not a hash.
    for hash <- ["00000000000000000000000000000123", "the palm"] do
      assert {:error, [%{"path" => "order", "message" => "the store has no order of this hash" <> _}]} =
               Edits.place(hash, edits, "o")
    end
  end

  test "edits of a model with no rule of its own: a drawing of edits gets a new size, new shapes and a paint" do
    drawing = World.Village.Yard.drawing(%{"kind" => "jar", "name" => "chum"})
    {:ok, first} = Orders.place(%{"blueprint" => "drawing", "options" => %{"drawing" => drawing}}, "o")
    at = "options.drawing.nodes.chum_than.skill.sculpt.edits"

    ear = fn x ->
      %{"shape" => "cylinder", "size" => [0.07, 0.02], "at" => [x, 0, 0.6], "axis" => [0, 1, 0], "color" => "#4a2e20"}
    end

    band = %{
      "shape" => "cylinder",
      "size" => [0.5, 0.04],
      "at" => [0, 0, 0.42],
      "color" => "#c9b48a",
      "mode" => "paint"
    }

    edits = [
      %{"set" => "#{at}.0.size", "to" => [0.36, 0.36, 0.5]},
      %{"insert" => "#{at}.1", "value" => ear.(0.37)},
      %{"insert" => "#{at}.1", "value" => ear.(-0.37)},
      %{"set" => "#{at}.7", "to" => band}
    ]

    assert {:ok, second} = Edits.place(first["hash"], edits, "o")
    [node] = second["order"]["options"]["drawing"]["nodes"]
    shapes = node["skill"]["sculpt"]["edits"]
    assert length(shapes) == 8 and hd(shapes)["size"] == [0.36, 0.36, 0.5] and List.last(shapes) == band
    assert Enum.map(Enum.slice(shapes, 1, 2), & &1["at"]) == [[-0.37, 0, 0.6], [0.37, 0, 0.6]]

    # The new jar is higher at its sides: its file builds. (The far level, with a small image.)
    {:ok, glb} = Orders.build(second["order"], "far", "glb")
    assert <<"glTF", _::binary>> = glb

    # A size that is not a size of the shape: the error of the check has the path of the value.
    assert {:error, [%{"path" => "options.drawing.nodes.0.skill.sculpt.edits.0.size"}]} =
             Edits.place(first["hash"], [%{"set" => "#{at}.0.size", "to" => [0.36, 0.36]}], "o")
  end
end
