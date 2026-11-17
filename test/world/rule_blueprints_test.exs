defmodule World.RuleBlueprintsTest do
  # The rules that draw a thing from a request of a few words are blueprints: an order and the edits of an
  # order work for them as for each other model (plan 0019, 7.0).
  use ExUnit.Case, async: true

  alias World.Orders
  alias World.Orders.{Blueprints, Edits}
  alias World.Town.Street

  @rules [
    {"street_house", World.Town.House, :request, %{"type" => "pho3", "family" => "modern", "seed" => 7}},
    {"building", World.Town.Building, :spec, %{"size" => [12, 8], "storeys" => 2}},
    {"village_house", World.Village.House, :request, %{"stilts" => 1.8, "roof" => "tiles"}},
    {"village_thing", World.Village.Yard, :request, %{"kind" => "fence", "length" => 6}},
    {"appliance", World.Home.Appliance, :request, %{"kind" => "range", "size" => [0.76, 0.66, 0.92]}},
    {"mini", World.Mini, :request, %{"kind" => "jet"}}
  ]

  test "an order of a rule: its options are the words of the request, and the full order has the full request" do
    for {name, module, full, request} <- @rules do
      assert name in Blueprints.names()
      {:ok, blueprint} = Blueprints.fetch(name)
      # (A building takes its size too: its full request has the outline of its plan.)
      keys = Map.keys(apply(module, full, [%{}])) ++ if(name == "building", do: ["size"], else: [])
      assert Enum.map(blueprint.options, & &1.name) == Enum.sort(keys)

      assert {:ok, order} = Orders.check(%{"blueprint" => name, "options" => request})
      assert order["options"] == apply(module, full, [request])
      # The full order is an order: its check gives it again, and its drawing is the drawing of the rule.
      assert Orders.check(order) == {:ok, order}
      assert Blueprints.drawing(order) == module.drawing(request)
      # An order with no option is the thing of the rule with each default.
      assert {:ok, %{"options" => options}} = Orders.check(%{"blueprint" => name})
      assert options == apply(module, full, [%{}])

      assert {:error, [%{"path" => "options.no_such_word"}]} =
               Orders.check(%{"blueprint" => name, "options" => %{"no_such_word" => 1}})
    end

    # A word that the rule refuses: the reason of the rule, at the path of the options, or at the path of the
    # value when the rule gives it.
    for {name, options, path, text} <- [
          {"street_house", %{"type" => "castle"}, "options", "the type of a house"},
          {"building", %{"storeys" => 0}, "options.storeys", "a building has from 1 to 12 storeys"},
          {"building", %{"fronts" => [%{}, %{"bays" => 0}]}, "options.fronts.1.bays", "a bay of a front"},
          {"building", %{"roof" => %{"kind" => "flat", "parapet" => 9}}, "options.roof.parapet", "the value of"},
          {"building", %{"apron" => 20}, "options.apron", "the value of apron"},
          {"building", %{"fronts" => [%{"from" => 6, "to" => 7}]}, "options.fronts.0", "a front is 1.5 m long"},
          {"village_house", %{"bays" => 0}, "options", "from 1 to 7 bays"},
          {"village_thing", %{"kind" => "pagoda"}, "options", "the kind of a thing of a village"},
          {"appliance", %{"kind" => "toaster"}, "options", "the kind of an appliance"},
          {"mini", %{"kind" => "dragon"}, "options", "the kind of a small model"}
        ] do
      assert {:error, [%{"path" => ^path, "message" => message}]} =
               Orders.check(%{"blueprint" => name, "options" => options})

      assert message =~ text, message
    end
  end

  test "a thing of a rule is placed, built and edited as each other model" do
    {:ok, placed} = Orders.place(%{"blueprint" => "appliance", "options" => %{"kind" => "fridge"}}, "o")
    assert placed["order"]["options"]["size"] == [0.91, 0.84, 1.78] and placed["order"]["options"]["doors"] == "french"
    assert Map.has_key?(placed["files"], "drawing.json")
    # The size of the fridge of the project, and one door: two edits of the order.
    edits = [%{"set" => "options.size.2", "to" => 1.7}, %{"set" => "options.doors", "to" => "single"}]
    {:ok, edited} = Edits.place(placed["hash"], edits, "o")
    assert %{"size" => [0.91, 0.84, 1.7], "doors" => "single", "kind" => "fridge"} = edited["order"]["options"]

    assert {:error, [%{"path" => "options", "message" => "the doors of a fridge" <> _}]} =
             Edits.place(placed["hash"], [%{"set" => "options.doors", "to" => "four"}], "o")

    # Each small model is an order that the check accepts (a jet does not go through a door: it is the mark of
    # a large thing, held by its site). Its flat file is some hundreds of triangles.
    for kind <- World.Mini.kinds() do
      assert {:ok, _} = Orders.place(%{"blueprint" => "mini", "options" => %{"kind" => kind}}, "o"), kind
    end

    {:ok, glb} = Orders.build(%{"blueprint" => "mini", "options" => %{"kind" => "turbine"}}, "far", "flat")
    assert [%{"primitives" => [%{"attributes" => %{"COLOR_0" => _}}]}] = World.GLBHelper.json(glb)["meshes"]
  end

  test "a street: the full order has the plan of its lots, and the model is the houses of some of its lots" do
    assert {:ok, order} = Orders.check(%{"blueprint" => "street", "options" => %{"seed" => 4}})
    plan = Street.plan(%{"seed" => 4})
    assert order["options"] == Map.put(plan, "only", [1, 5])
    assert Blueprints.drawing(order) == Street.drawing(plan, only: 1..5)

    # A long row: the first five lots by default; the plan of the plan is the same plan (a lot keeps its seed).
    assert {:ok, long} = Orders.check(%{"blueprint" => "street", "options" => %{"count" => 12}})
    assert length(long["options"]["lots"]) == 12 and long["options"]["only"] == [1, 5]
    assert Orders.check(long) == {:ok, long}
    assert Street.plan(Street.plan(%{"count" => 12})) == Street.plan(%{"count" => 12})

    # A part of a row, and the lots of a real street (plan 0018).
    street = %{"count" => 12, "sidewalk" => 5.5, "lots" => [%{"use" => "bar", "number" => "4"}, %{"same" => true}, %{}]}
    assert {:ok, part} = Orders.check(%{"blueprint" => "street", "options" => Map.put(street, "only", [2, 3])})
    assert [%{"use" => "bar", "number" => "4"}, %{"use" => "bar"}, %{"use" => "home"}] = part["options"]["lots"]
    assert Blueprints.drawing(part) == Street.drawing(Street.plan(street), only: 2..3)
    assert length(Blueprints.drawing(part)["nodes"]) == 7

    for only <- [[3, 2], [0, 1], "all", [7, 9], [1, 3.5]] do
      assert {:error, [%{"path" => "options.only", "message" => "must be [first, last]" <> _}]} =
               Orders.check(%{"blueprint" => "street", "options" => Map.put(street, "only", only)})
    end

    assert {:error, [%{"path" => "options.only"}]} =
             Orders.check(%{"blueprint" => "street", "options" => %{"count" => 12, "only" => [1, 6]}})

    assert {:error, [%{"path" => "options", "message" => _}]} =
             Orders.check(%{"blueprint" => "street", "options" => %{"count" => 0}})

    # One house of a street as a placed order; an edit gives the lot a use.
    {:ok, placed} = Orders.place(%{"blueprint" => "street", "options" => %{"count" => 3, "only" => [2, 2]}}, "o")
    {:ok, edited} = Edits.place(placed["hash"], [%{"set" => "options.lots.1.use", "to" => "bar"}], "o")
    assert Enum.at(edited["order"]["options"]["lots"], 1)["use"] == "bar"
    assert Enum.at(edited["order"]["options"]["lots"], 0) == Enum.at(placed["order"]["options"]["lots"], 0)
  end
end
