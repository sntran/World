defmodule World.DrawingTest do
  use ExUnit.Case, async: true

  alias World.{Build, Drawing, GLBHelper, Orders, Scene}

  defp order(drawing), do: %{"blueprint" => "drawing", "options" => %{"drawing" => drawing}}
  defp paths({:error, errors}), do: Enum.map(errors, & &1["path"])
  defp paths({:ok, _}), do: []

  # A box with a lid on a hinge and a drawer on a slide, with each shape.
  defp box do
    %{
      "name" => "box",
      "materials" => %{"wood" => %{"color" => "#AA5500", "roughness" => 0.4, "metalness" => 0}},
      "sources" => ["A test."],
      "parts" => %{
        "base" => %{
          "shapes" => [
            %{"box" => %{"from" => [0, 0, 0], "to" => [0.4, 0.3, 0.2]}, "material" => "wood"},
            %{
              "cylinder" => %{"radius" => 0.02, "length" => 0.1},
              "at" => [0.2, 0.15, 0.2],
              "axis" => [0, 0, 1],
              "up" => [0, 1, 0]
            },
            %{"sphere" => %{"radius" => 0.02}, "at" => [0.2, 0.15, 0.3]},
            %{"prism" => %{"loop" => [[0, 0], [0.1, 0], [0, 0.1]], "length" => 0.01}, "axis" => [1, 0, 0]},
            %{"lathe" => %{"profile" => [[0, 0], [0.03, 0], [0.02, 0.05], [0, 0.05]]}, "at" => [0.3, 0.1, 0.2]},
            %{"tube" => %{"line" => [[0, 0, 0.2], [0.4, 0, 0.2]], "radius" => 0.005}, "material" => "steel"}
          ],
          "ports" => %{
            "hinge" => %{"at" => [0, 0.3, 0.2], "axis" => [1, 0, 0]},
            "slot" => %{"at" => [0.2, 0, 0.1], "axis" => [0, -1, 0]}
          }
        },
        "lid" => %{
          "shapes" => [%{"box" => %{"from" => [0, -0.3, 0], "to" => [0.4, 0, 0.01]}}],
          "ports" => %{"hinge" => %{"at" => [0, 0, 0], "axis" => [1, 0, 0]}}
        },
        "drawer" => %{"shapes" => [%{"box" => %{"from" => [-0.1, 0, -0.05], "to" => [0.1, 0.25, 0.05]}}]}
      },
      "nodes" => [
        %{"name" => "base", "part" => "base"},
        %{
          "name" => "lid",
          "part" => "lid",
          "to" => "base",
          "at" => "hinge",
          "port" => "hinge",
          "joint" => %{"kind" => "hinge", "role" => "lid", "limits" => [0, 100]}
        },
        %{
          "name" => "drawer",
          "part" => "drawer",
          "to" => "base",
          "at" => "slot",
          "port" => %{"at" => [0, 0, 0], "axis" => [0, -1, 0], "up" => [0, -1, 0]},
          "joint" => %{"kind" => "slide", "role" => "drawer", "limits" => [0, 0.2]},
          "turn" => 0,
          "offset" => 0
        }
      ],
      "clips" => [
        %{
          "name" => "open",
          "length" => 2,
          "keys" => [
            %{"t" => 0, "joints" => %{"lid" => 0, "drawer" => 0}},
            %{"t" => 1, "joints" => %{"lid" => 200}},
            %{"t" => 2, "joints" => %{"lid" => 0, "drawer" => 0.1}}
          ]
        },
        %{
          "name" => "late",
          "length" => 1,
          "keys" => [%{"t" => 0, "joints" => %{"lid" => 0}}, %{"t" => 1, "joints" => %{"lid" => 10, "drawer" => 0.1}}]
        }
      ]
    }
  end

  test "a drawing: its parts, its joints, its materials and its clips" do
    assert {:ok, _} = Orders.check(order(box()))
    a = Drawing.build(box())
    assert a.kind == :item and a.name == "box" and a.sources == ["A test."]
    assert a.materials.wood["color"] == [170, 85, 0] and a.materials.wood["roughness"] == 0.4

    scene = Build.scene(a)
    assert scene.extras["joints"] == ["lid", "drawer"]
    [open, late] = scene.animations
    lid = Enum.find_index(scene.nodes, &(&1.name == "lid"))
    drawer = Enum.find_index(scene.nodes, &(&1.name == "drawer"))
    [rotation] = for c <- open.channels, c.node == lid, do: c
    [move] = for c <- open.channels, c.node == drawer, do: c
    assert rotation.path == :rotation and rotation.times == [0.0, 1.0, 2.0]
    # The lid stops at its limit; the drawer has no key at 1 s: it is in a
    # line between its keys.
    assert rotation.values |> Enum.at(1) == scene_at(a, %{"lid" => 100}, lid)
    assert move.path == :translation
    assert_in_delta elem(Enum.at(move.values, 1), 1), elem(Enum.at(move.values, 0), 1) - 0.05, 1.0e-9
    # Before its first key, a joint has the value of that key.
    [early] = for c <- late.channels, c.node == drawer, do: c
    assert Enum.uniq(early.values) |> length() == 1
    {:ok, glb} = Orders.build(order(box()), "near", "glb")
    assert [%{"name" => "open"}, %{"name" => "late"}] = GLBHelper.json(glb)["animations"]
    # A drawing with no name, no kind and no clip.
    plain = %{
      "parts" => %{"p" => %{"shapes" => [%{"sphere" => %{"radius" => 0.1}}]}},
      "nodes" => [%{"name" => "p", "part" => "p"}]
    }

    assert %{name: "drawing", kind: :item, clips: []} = Drawing.build(plain)
  end

  defp scene_at(a, pose, node), do: Enum.at(Build.scene(a, pose: pose).nodes, node).frame

  test "the cart of bánh mì: a seller and a dog of other blueprints, and the clips" do
    cart = Drawing.file("banh_mi_cart")
    scene = Build.scene(cart, level: :far)
    assert ~w(wheel_l wheel_r door) -- scene.extras["joints"] == []
    assert "seller/elbow_r" in scene.extras["joints"] and "seller/arm_r" in scene.extras["limbs"]
    assert Enum.map(scene.animations, & &1.name) == ["wag", "open", "roll"]
    assert "tai_chi_fan" not in Enum.map(Build.parts(cart), & &1["name"])
    assert "non_la" in Enum.map(Build.parts(cart), & &1["name"])
    {{_, _, ground}, _} = Scene.bounds(scene)
    assert_in_delta ground, 0.0, 0.01
    assert_raise File.Error, fn -> Drawing.file("nothing") end
  end

  test "a drawing in the catalog with errors does not build" do
    dir = Path.join([:code.priv_dir(:world), "drawings"])
    path = Path.join(dir, "broken_test.json")
    File.write!(path, ~s({"nodes": []}))

    try do
      assert_raise ArgumentError, ~r/the drawing broken_test has errors/, fn -> Drawing.file("broken_test") end
    after
      File.rm!(path)
    end
  end

  test "the errors of a drawing, each with its path" do
    d = "options.drawing"
    put = fn keys, value -> put_in(box(), Enum.map(keys, &Access.key(&1)), value) end
    base = fn key, value -> Map.put(box(), key, value) end

    node = fn i, key, value ->
      update_in(box(), ["nodes"], &List.update_at(&1, i, fn n -> Map.put(n, key, value) end))
    end

    shape = fn s -> put.(["parts", "drawer", "shapes"], [s]) end
    clip = fn key, value -> update_in(box(), ["clips"], fn [c | rest] -> [Map.put(c, key, value) | rest] end) end
    keys = fn keys -> clip.("keys", keys) end

    cases = [
      {[], [d]},
      {base.("color", 1), ["#{d}.color"]},
      {base.("name", "Box!"), ["#{d}.name"]},
      {base.("kind", "boat"), ["#{d}.kind"]},
      {base.("sources", "a"), ["#{d}.sources"]},
      {base.("sources", [String.duplicate("a", 501)]), ["#{d}.sources.0"]},
      {base.("materials", []), ["#{d}.materials"]},
      {base.("materials", %{"gold" => %{}}), ["#{d}.materials.gold"]},
      {base.("materials", %{"wood" => 1}), ["#{d}.materials.wood"]},
      {base.("materials", %{"wood" => %{"color" => "red", "roughness" => 2, "shine" => 1}}),
       ["#{d}.materials.wood.shine", "#{d}.materials.wood.color", "#{d}.materials.wood.roughness"]},
      {base.("parts", []), ["#{d}.parts"]},
      {put.(["parts", "Lid"], %{"shapes" => [%{"sphere" => %{"radius" => 1}}]}), ["#{d}.parts.Lid"]},
      {put.(["parts", "drawer"], 1), ["#{d}.parts.drawer"]},
      {put.(["parts", "drawer"], %{"shapes" => [], "paint" => 1}),
       ["#{d}.parts.drawer.paint", "#{d}.parts.drawer.shapes"]},
      {put.(["parts", "drawer"], %{}), ["#{d}.parts.drawer.shapes"]},
      {shape.(1), ["#{d}.parts.drawer.shapes.0"]},
      {shape.(%{"box" => %{}, "sphere" => %{}}), ["#{d}.parts.drawer.shapes.0"]},
      {shape.(%{
         "sphere" => %{"radius" => 1},
         "size" => 1,
         "material" => "gold",
         "at" => [1],
         "axis" => [0, 0, 0],
         "up" => [0, 0, 99]
       }), ~w(size material at axis up) |> Enum.map(&"#{d}.parts.drawer.shapes.0.#{&1}")},
      {shape.(%{"box" => %{"from" => [0, 0, 0]}}), ["#{d}.parts.drawer.shapes.0.box.to"]},
      {shape.(%{"box" => 1}), ["#{d}.parts.drawer.shapes.0.box"]},
      {shape.(%{"sphere" => %{"radius" => -1}}), ["#{d}.parts.drawer.shapes.0.sphere.radius"]},
      {shape.(%{"cylinder" => %{"radius" => 1}}), ["#{d}.parts.drawer.shapes.0.cylinder.length"]},
      {shape.(%{"prism" => %{"loop" => [[0, 0], [1, 0]], "length" => 1}}), ["#{d}.parts.drawer.shapes.0.prism.loop"]},
      {shape.(%{"lathe" => %{"profile" => [[-1, 0], [1, 1]]}}), ["#{d}.parts.drawer.shapes.0.lathe.profile.0"]},
      {shape.(%{"tube" => %{"line" => [[0, 0, 0], [1, 0, 0]], "radius" => 0}}),
       ["#{d}.parts.drawer.shapes.0.tube.radius"]},
      {put.(["parts", "drawer", "ports"], 1), ["#{d}.parts.drawer.ports"]},
      {put.(["parts", "drawer", "ports"], %{"A" => %{"at" => [0, 0, 0]}, "b" => %{"axis" => [0, 0, 1]}}),
       ["#{d}.parts.drawer.ports.A", "#{d}.parts.drawer.ports.b.at"]},
      {put.(["parts", "drawer", "shapes"], List.duplicate(%{"sphere" => %{"radius" => 1}}, 64))
       |> put_in(["parts", "lid", "shapes"], List.duplicate(%{"sphere" => %{"radius" => 1}}, 64))
       |> put_in(["parts", "x"], %{"shapes" => List.duplicate(%{"sphere" => %{"radius" => 1}}, 64)})
       |> put_in(["parts", "y"], %{"shapes" => List.duplicate(%{"sphere" => %{"radius" => 1}}, 64)}), ["#{d}.parts"]},
      {base.("nodes", []), ["#{d}.nodes"]},
      {base.("nodes", [1]), ["#{d}.nodes.0"]},
      {base.("nodes", [%{"part" => "base"}]), ["#{d}.nodes.0.name"]},
      {node.(1, "name", "base"), ["#{d}.nodes.1.name"]},
      {node.(1, "part", "roof"), ["#{d}.nodes.1.part"]},
      # A node on a node with an error has no error of its own.
      {node.(1, "part", "roof") |> update_in(["nodes"], &List.update_at(&1, 2, fn n -> Map.put(n, "to", "lid") end)),
       ["#{d}.nodes.1.part"]},
      {node.(1, "item", %{"blueprint" => "catalog"}), ["#{d}.nodes.1"]},
      {node.(0, "to", "lid"), ["#{d}.nodes.0.to"]},
      {node.(1, "to", "drawer"), ["#{d}.nodes.1.to"]},
      {node.(1, "at", "nowhere"), ["#{d}.nodes.1.at"]},
      {node.(1, "at", 3), ["#{d}.nodes.1.at"]},
      {node.(1, "port", %{"axis" => [0, 0, 1]}), ["#{d}.nodes.1.port.at"]},
      {node.(1, "joint", %{"kind" => "ball", "role" => "lid", "limits" => [2, 1]}),
       ["#{d}.nodes.1.joint.kind", "#{d}.nodes.1.joint.limits"]},
      {node.(1, "joint", %{"kind" => "hinge", "role" => "fly"}), ["#{d}.nodes.1.joint.role"]},
      {node.(1, "turn", 400), ["#{d}.nodes.1.turn"]},
      {node.(1, "wings", 2), ["#{d}.nodes.1.wings"]},
      {base.("clips", 1), ["#{d}.clips"]},
      {clip.("name", "Open"), ["#{d}.clips.0.name"]},
      {clip.("speed", 1), ["#{d}.clips.0.speed"]},
      {clip.("length", 0), ["#{d}.clips.0.length", "#{d}.clips.0.keys.1.t", "#{d}.clips.0.keys.2.t"]},
      {keys.([%{"t" => 0, "joints" => %{}}]), ["#{d}.clips.0.keys"]},
      {keys.([%{"t" => 0, "joints" => 1}, %{"t" => 1, "joints" => %{"base" => 1, "lid" => "a"}}]),
       ["#{d}.clips.0.keys.0.joints", "#{d}.clips.0.keys.1.joints.base", "#{d}.clips.0.keys.1.joints.lid"]},
      {keys.([%{"t" => 1, "joints" => %{}}, %{"t" => 1, "joints" => %{}}]), ["#{d}.clips.0.keys"]}
    ]

    for {drawing, expected} <- cases do
      assert paths(Orders.check(order(drawing))) == expected
    end
  end

  test "the items of other blueprints in a drawing, and their errors" do
    d = "options.drawing"
    person = %{"blueprint" => "person", "options" => %{"hair" => "none", "clothes" => []}}

    cup = %{
      "parts" => %{"cup" => %{"shapes" => [%{"cylinder" => %{"radius" => 0.04, "length" => 0.1}}]}},
      "nodes" => [%{"name" => "cup", "part" => "cup"}]
    }

    stall =
      fn item, more ->
        %{
          "parts" => %{"floor" => %{"shapes" => [%{"box" => %{"from" => [-1, -1, -0.01], "to" => [1, 1, 0]}}]}},
          "nodes" => [
            %{"name" => "floor", "part" => "floor"},
            Map.merge(%{"name" => "p", "item" => item, "to" => "floor"}, more)
          ]
        }
      end

    # A cup in the hand of a person: a node on a port of a bone.
    drawn = %{"blueprint" => "drawing", "options" => %{"drawing" => cup}}
    holder = stall.(person, %{"port" => "ground"})
    holder = update_in(holder, ["nodes"], &(&1 ++ [%{"name" => "cup", "item" => drawn, "to" => "p", "at" => "grip_r"}]))
    assert {:ok, _} = Orders.check(order(holder))
    scene = Build.scene(Drawing.build(holder), level: :far)
    hand = Enum.find_index(scene.nodes, &(&1.name == "hand_r"))
    assert Enum.at(scene.nodes, hand).primitives != []

    assert paths(Orders.check(order(stall.(person, %{"port" => "wing"})))) == ["#{d}.nodes.1.port"]
    assert paths(Orders.check(order(stall.(%{"blueprint" => "kite"}, %{})))) == ["#{d}.nodes.1.item.blueprint"]
    assert paths(Orders.check(order(stall.(Map.put(person, "joints", %{}), %{})))) == ["#{d}.nodes.1.item.joints"]

    # Three drawings one in the other are the most.
    deep =
      Enum.reduce(1..3, cup, fn _, inner ->
        stall.(%{"blueprint" => "drawing", "options" => %{"drawing" => inner}}, %{})
      end)

    assert ["#{d}.nodes.1.item.options.drawing.nodes.1.item.options.drawing.nodes.1.item.options.drawing"] ==
             paths(Orders.check(order(deep)))
  end

  test "the example of docs/format.md builds" do
    [_, json] = Regex.run(~r/## A drawing.*?```json\n(.*?)```/s, File.read!("docs/format.md"))
    assert {:ok, <<"glTF", _::binary>>} = Orders.build(JSON.decode!(json), "far", "glb")
  end
end
