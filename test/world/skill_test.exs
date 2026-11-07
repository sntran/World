defmodule World.SkillTest do
  use ExUnit.Case, async: true

  alias World.{Build, BuildSpec, Construction, Detail, Drawing, Log, Orders, Plan, Skill, Skills}
  alias World.Orders.{Blueprint, Blueprints}

  @moduletag :tmp_dir

  # A drawing of the people: a note first (data only), a block of the
  # mason as the root, a block on its top that takes the size of the note
  # and of the root, and a note that goes to the note (so to the root).
  defp drawing do
    %{
      "name" => "tower_of_blocks",
      "kind" => "tower",
      "sources" => ["A test."],
      "extras" => %{
        "ports" => [%{"kind" => "door", "at" => [0, 0, 0], "normal" => [0, -1, 0]}],
        "collision" => [%{"name" => "all", "at" => [0, 0, 1], "size" => [1, 1, 2]}]
      },
      "nodes" => [
        %{"name" => "note", "skill" => %{"note" => %{"size" => 0.5}}},
        %{"name" => "root", "skill" => %{"block" => %{"size" => 1.0}}, "trade" => "builder", "after" => ["note"]},
        %{
          "name" => "upper",
          "skill" => %{"block" => %{"size" => 0.5}},
          "from" => ["note", "root"],
          "to" => "root",
          "at" => "top",
          "port" => "o"
        },
        %{"name" => "mark", "skill" => %{"note" => %{}}, "to" => "note"}
      ]
    }
  end

  defp order(d), do: %{"blueprint" => "drawing", "options" => %{"drawing" => d}}
  defp paths({:error, errors}), do: Enum.map(errors, & &1["path"])
  defp paths({:ok, _}), do: []

  test "a drawing made by skills: data nodes are not in the model, and each node takes the data of its nodes from" do
    item = Detail.with(:near, fn -> Drawing.build(drawing()) end)
    assert Enum.map(item.nodes, &elem(&1, 0)) == ["root", "upper"]
    assert item.kind == :tower
    {"upper", upper, connection} = List.keyfind(item.nodes, "upper", 0)
    # The note (0.5) and the root (1.0) under the upper block of 0.5.
    assert {_, {_, _, 2.0}} = World.Mesh.bounds(hd(upper.shapes))
    assert connection.to == "root"

    # The extras of the drawing (points as tuples) and of each node, in order.
    assert item.extras["noted"] == true and item.extras["blocks"] == [2.0]
    assert [%{"at" => {0, 0, 0}, "normal" => {0, -1, 0}}] = item.extras["ports"]
    assert [%{"at" => {0, 0, 1}, "size" => {1, 1, 2}}] = item.extras["collision"]
    assert Drawing.estimate(drawing(), :far) == 24

    # A node to a node with no part goes to the root.
    d = update_in(drawing(), ["nodes"], &List.replace_at(&1, 2, Map.put(Enum.at(&1, 2), "to", "note")))
    assert {_, _, %{to: "root"}} = Detail.with(:far, fn -> Drawing.build(d) end).nodes |> List.keyfind("upper", 0)
  end

  test "the plan of a drawing: a task for each node, its waits and its trade" do
    plan = Plan.of_drawing(drawing())

    assert Enum.map(plan.tasks, &{&1.id, &1.waits, &1.trade}) == [
             {"note", [], :surveyor},
             {"root", ["note"], :builder},
             {"upper", ["root", "note"], :mason},
             {"mark", ["note"], :surveyor}
           ]

    parts = Plan.of_drawing(%{"nodes" => [%{"name" => "a", "part" => "a"}]})
    assert [%{trade: :builder}] = parts.tasks
    assert parts.name == "drawing"
    box = %{"box" => %{"from" => [0, 0, 0], "to" => [1, 1, 1]}}
    one = %{"parts" => %{"a" => %{"shapes" => [box]}}, "nodes" => [%{"name" => "a", "part" => "a"}]}
    assert Drawing.estimate(one, :far) == 12
    assert "mason" in Plan.trades() and "builder" in Plan.trades()
    assert "block" in Skills.names() and "shell" in Skills.names()
  end

  test "the errors of the skill nodes of a drawing, each with its path" do
    d = "options.drawing"

    node = fn i, key, value ->
      update_in(drawing(), ["nodes"], &List.update_at(&1, i, fn n -> Map.put(n, key, value) end))
    end

    cases = [
      {node.(1, "skill", %{"lay" => %{}}), ["#{d}.nodes.1.skill"]},
      {node.(1, "skill", %{"block" => %{}, "note" => %{}}), ["#{d}.nodes.1.skill"]},
      {node.(1, "skill", "block"), ["#{d}.nodes.1.skill"]},
      {node.(1, "skill", %{"block" => %{"size" => -1}}), ["#{d}.nodes.1.skill.block.size"]},
      {node.(1, "skill", %{"block" => %{"side" => 1}}),
       ["#{d}.nodes.1.skill.block.side", "#{d}.nodes.1.skill.block.size"]},
      {node.(0, "skill", %{"note" => 5}), ["#{d}.nodes.0.skill.note"]},
      {node.(1, "part", "x"), ["#{d}.nodes.1"]},
      {node.(1, "trade", "astronaut"), ["#{d}.nodes.1.trade"]},
      {node.(1, "after", ["nobody"]), ["#{d}.nodes.1.after"]},
      {node.(2, "from", "root"), ["#{d}.nodes.2.from"]},
      {node.(0, "after", ["upper"]), ["#{d}.nodes.0"]},
      {node.(3, "to", "nobody"), ["#{d}.nodes.3.to"]}
    ]

    for {drawing, expected} <- cases do
      assert paths(Orders.check(order(drawing))) == expected, inspect({expected, Orders.check(order(drawing))})
    end

    assert {:error, [%{"message" => message}]} = Orders.check(order(node.(0, "after", ["upper"])))
    assert message =~ "must not wait for itself: "
    assert paths(Orders.check(order(drawing()))) == []
    assert Skill.keys(%{"a" => 1}, "p", ["b"], ["c"]) == [{"p.a", "is not a key"}, {"p.c", "is required"}]
  end

  test "a blueprint in data: its params, the fill of its drawing, its sizes and their sources" do
    raw = %{
      "name" => "toy_tower",
      "doc" => "A test.",
      "params" => [
        %{"name" => "size", "type" => "number", "default" => 1.0, "min" => 0.1, "max" => 5.0, "unit" => "m"},
        %{"name" => "floors", "type" => "integer", "default" => 2, "min" => 1, "max" => 4},
        %{"name" => "label", "type" => "text", "default" => "", "max" => 5},
        %{"name" => "name", "type" => "choice", "values" => ["a", "b"]},
        %{
          "name" => "rows",
          "type" => "list",
          "default" => [],
          "item" => %{"name" => "row", "type" => "object", "fields" => [%{"name" => "x", "type" => "number"}]}
        },
        %{"name" => "sources", "type" => "sources", "default" => %{}}
      ],
      "sizes" => [
        %{"name" => "size", "unit" => "m"},
        %{"name" => "floors"},
        %{"name" => "rows", "row" => ["x"]},
        %{"name" => "label"},
        %{"name" => "none"}
      ],
      "drawing" => %{
        "name" => %{"param" => "name"},
        "nodes" => [%{"name" => "root", "skill" => %{"block" => %{"size" => %{"sum" => [%{"param" => "size"}, 1]}}}}]
      }
    }

    b = Blueprint.from_data(raw)
    assert b.name == "toy_tower" and b.doc == "A test." and b.sources == []
    assert {:ok, o} = Blueprint.check_options(b.options, %{"name" => "a", "rows" => [%{"x" => 1}]}, "options")
    assert b.check.(o) == []
    assert {:error, [{"options.name", "is required"}]} = Blueprint.check_options(b.options, %{}, "options")

    assert {:error, [{"options.label", _}]} =
             Blueprint.check_options(b.options, %{"name" => "a", "label" => "123456"}, "options")

    assert {:error, [{"options.sources.x", _}]} =
             Blueprint.check_options(b.options, %{"name" => "a", "sources" => %{"x" => "y"}}, "options")

    filled = Drawing.fill(raw, Map.put(o, "sources", %{"size" => "A drawing.", "floors" => "A photo."}))
    assert filled["name"] == "a" and filled["sources"] == ["A photo.", "A drawing."]
    assert [%{"skill" => %{"block" => %{"size" => 2.0}}}] = filled["nodes"]

    assert filled["extras"]["sizes"] == [
             %{"name" => "size", "value" => 1.0, "unit" => "m", "source" => "A drawing."},
             %{"name" => "floors", "value" => 2, "source" => "A photo."},
             %{"name" => "rows", "value" => [[1.0]], "source" => "estimate (no source)"},
             %{"name" => "label", "value" => "", "source" => "estimate (no source)"}
           ]

    assert Detail.with(:far, fn -> b.build.(o) end).name == "a"

    # A drawing of its own sources and extras keeps them.
    raw = put_in(raw, ["drawing", "sources"], ["Mine."]) |> put_in(["drawing", "extras"], %{"site" => true})
    filled = Drawing.fill(raw, Map.put(o, "sources", %{"size" => "A drawing."}))
    assert filled["sources"] == ["Mine.", "A drawing."] and filled["extras"]["site"] == true

    # With no sizes and no sources, no extras; a check of the drawing gives its errors.
    raw = %{raw | "sizes" => [], "params" => [hd(raw["params"])]} |> put_in(["drawing", "name"], "Bad!")
    raw = Map.update!(raw, "drawing", &Map.delete(&1, "extras"))
    refute Map.has_key?(Drawing.fill(raw, %{"size" => 1.0}), "extras")
    assert [{"drawing.name", _}] = Blueprint.from_data(raw).check.(%{"size" => 1.0})
  end

  test "the drawing of an order for the people" do
    assert Blueprints.drawing(order(drawing())) == drawing()

    assert Blueprints.drawing(%{"blueprint" => "catalog", "options" => %{"name" => "banh_mi_cart"}}) ==
             Drawing.raw("banh_mi_cart")

    assert Blueprints.drawing(%{"blueprint" => "catalog", "options" => %{"name" => "wall_brick_sample"}}) == nil
    assert Blueprints.drawing(%{"blueprint" => "strut", "options" => %{}}) == nil
    statue = Blueprints.drawing(%{"blueprint" => "catalog", "options" => %{"name" => "tuong_chua_kito_vua"}})
    assert statue["name"] == "tuong_chua_kito_vua" and length(statue["nodes"]) == 10
    assert Enum.map(Blueprints.data(), & &1["name"]) == ["statue"]
    refute Blueprints.__mix_recompile__?()

    # An order of the catalog: its check, and its errors.
    assert Drawing.check_all!(%{"x" => %{"blueprint" => "statue", "options" => %{}}}) == ["x"]

    assert_raise ArgumentError, ~r/has errors/, fn ->
      Drawing.check_all!(%{"x" => %{"blueprint" => "statue", "options" => %{"height" => 0}}})
    end
  end

  test "the people make a drawing node by node: the bytes of a build with no world, the elements in the order of the nodes",
       %{tmp_dir: dir} do
    d = drawing()
    expected = Detail.with(:near, fn -> Drawing.build(d) end) |> Build.glb(level: :near)
    id = "blocks-#{System.unique_integer([:positive])}"
    World.watch(id)
    item = fn level -> Detail.with(level, fn -> Drawing.build(d) end) end
    {:ok, ^id} = World.build(%{id: id, item: item, drawing: d, budget: %{"workers" => 2}})
    assert {:ok, r} = World.await(id)
    assert r.glb == expected
    assert Log.check(r.log) == :ok
    assert BuildSpec.replay([r.log], dir) == :ok

    elements = for %{kind: "element", data: data} <- Log.events(r.log), do: data
    assert Enum.map(elements, & &1["task"]) == ["root", "upper"]
    assert Enum.all?(elements, &Map.has_key?(r.glbs, &1["glb"]))
    assert Construction.key({[], nil}) =~ ~r/^[0-9a-f]{16}$/

    # The budget of triangles: the estimate of the drawing, at each level.
    {:ok, small} = World.build(%{id: id <> "-small", item: item, drawing: d, budget: %{"triangles" => 10}})
    assert {:error, {:stopped, "triangles"}} = World.await(small)
    {:ok, fits} = World.build(%{id: id <> "-fits", item: item, drawing: d, level: :far, budget: %{"triangles" => 24}})
    assert {:ok, %{level: :far}} = World.await(fits)
  end

  @tag timeout: 300_000
  test "the people build the statue on Núi Nhỏ from its blueprint in data: the bytes of the catalog at far" do
    order = %{"blueprint" => "catalog", "options" => %{"name" => "tuong_chua_kito_vua"}}
    {:ok, job} = Orders.job(order, "far")
    assert job.drawing["kind"] == "statue"
    {:ok, id} = World.build(Map.put(job, :budget, %{"workers" => 8}))
    assert {:ok, r} = World.await(id, 300_000)
    assert r.glb == File.read!("priv/models/tuong_chua_kito_vua.far.glb")
    trades = for %{kind: "hired", data: %{"trade" => t}} <- Log.events(r.log), uniq: true, do: t
    assert Enum.sort(trades) == ~w(caster mason sculptor smith surveyor)
    estimates = for level <- [:near, :mid, :far], do: Drawing.estimate(job.drawing, level)
    assert estimates == Enum.sort(estimates, :desc) and Enum.uniq(estimates) == estimates
    assert Drawing.estimate(Map.update!(job.drawing, "nodes", &Enum.take(&1, 1)), :far) == 100
  end

  test "the errors of the data of the skills of a statue" do
    d = %{
      "nodes" => [
        %{"name" => "figure", "skill" => %{"figure" => %{"name" => "Bad!"}}},
        %{"name" => "be", "skill" => %{"base" => %{"reliefs" => [%{"side" => "front", "title" => 5}]}}}
      ]
    }

    assert paths(Orders.check(order(d))) == [
             "options.drawing.nodes.0.skill.figure.name",
             "options.drawing.nodes.1.skill.base.reliefs.0.title"
           ]
  end
end
