defmodule World.FlatTest do
  # The flat look of a model: one mesh, a color at each point, no image (plan 0019, 4.2).
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Flat, Frame, Orders, Scene}

  defp triangle(material, z, more \\ %{}) do
    struct(
      %Scene.Primitive{
        material: material,
        positions: [{0.0, 0.0, z}, {1.0, 0.0, z}, {0.0, 1.0, z}],
        normals: [],
        indices: [0, 1, 2]
      },
      more
    )
  end

  test "a scene becomes one node with one mesh: each face with its own points, its normal and its color" do
    scene = %Scene{
      name: "thing",
      extras: %{"size" => [1, 1, 1], "joints" => ["lid"]},
      materials: %{steel: %{"color" => [10, 20, 30]}},
      nodes: [
        # The color of the scene for a role, the color of the palette, and gray for a role with no color.
        %Scene.Node{
          name: "a",
          primitives: [triangle(:steel, 0.0), triangle(:glass, 1.0), triangle(:no_such_role, 2.0)]
        },
        # The colors of the points of a mesh, with or with no alpha; two copies of a node that is 10 m along x.
        %Scene.Node{
          name: "b",
          parent: 0,
          frame: Frame.move({10.0, 0.0, 0.0}),
          instances: [%Frame{}, Frame.move({0.0, 5.0, 0.0})],
          primitives: [
            triangle(:steel, 0.0, %{colors: [{1, 2, 3}, {4, 5, 6}, {7, 8, 9}]}),
            triangle(:steel, 1.0, %{colors: [{9, 8, 7, 0.5}, {1, 1, 1, 1.0}, {1, 1, 1, 1.0}]})
          ]
        },
        # A face with no area has a normal that points up. A collision box and a node with no mesh are not in it.
        %Scene.Node{
          name: "c",
          primitives: [
            %Scene.Primitive{
              material: :steel,
              positions: [{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {2.0, 0.0, 0.0}],
              normals: [],
              indices: [0, 1, 2]
            }
          ]
        },
        %Scene.Node{name: "hit", primitives: [triangle(:steel, 9.0)], extras: %{"collision" => "box"}},
        %Scene.Node{name: "empty"}
      ]
    }

    flat = Flat.scene(scene)

    assert %Scene{name: "thing", extras: %{"size" => [1, 1, 1]}, nodes: [%Scene.Node{name: "thing", primitives: [p]}]} =
             flat

    assert flat.materials == %{paint: %{"color" => [255, 255, 255], "roughness" => 0.9, "metalness" => 0.0}}
    assert Flat.faces(flat) == 8 and p.indices == Enum.to_list(0..23) and length(p.positions) == 24
    colors = p.colors |> Enum.chunk_every(3) |> Enum.map(&hd/1)
    [glass] = World.GLB.palette()["glass"]["color"] |> List.to_tuple() |> List.wrap()
    assert colors == [{10, 20, 30}, glass, {200, 200, 200}, {1, 2, 3}, {1, 2, 3}, {9, 8, 7}, {9, 8, 7}, {10, 20, 30}]
    assert Enum.all?(Enum.chunk_every(p.colors, 3), fn [a, b, c] -> a == b and b == c end)
    assert Enum.take(p.normals, 3) == List.duplicate({0.0, 0.0, 1.0}, 3) and List.last(p.normals) == {0.0, 0.0, 1.0}
    # The points are in the axes of the model: the second copy of the node is 5 m along y.
    assert Enum.slice(p.positions, 9, 3) == [{10.0, 0.0, 0.0}, {11.0, 0.0, 0.0}, {10.0, 1.0, 0.0}]
    assert Enum.slice(p.positions, 12, 3) == [{10.0, 5.0, 0.0}, {11.0, 5.0, 0.0}, {10.0, 6.0, 0.0}]
    assert <<"glTF", _::binary>> = World.GLB.encode(flat)
  end

  test "the points of a skin are at the places of its bones; a budget gives fewer faces with the colors of the mesh before" do
    person = Build.scene(Detail.with(:far, fn -> World.People.Human.person("p", age: 9) end), level: :far)
    flat = Flat.scene(person)
    assert Flat.faces(flat) == Scene.triangles(person)
    {{_, _, z0}, {_, _, z1}} = Scene.bounds(flat)
    {{_, _, w0}, {_, _, w1}} = Scene.bounds(person)
    assert_in_delta z0, w0, 1.0e-6
    assert_in_delta z1, w1, 1.0e-6

    small = Flat.scene(person, budget: 300)
    assert Flat.faces(small) <= 300 and Flat.faces(small) > 100
    [p] = hd(small.nodes).primitives
    [q] = hd(flat.nodes).primitives
    assert MapSet.subset?(MapSet.new(p.colors), MapSet.new(q.colors))
    {{_, _, s0}, {_, _, s1}} = Scene.bounds(small)
    assert_in_delta s1 - s0, z1 - z0, 0.1
    # A budget that the mesh has already changes nothing.
    assert Flat.faces(Flat.scene(person, budget: 1_000_000)) == Flat.faces(flat)
  end

  test "the file flat of an order: a drawing from edits has the colors of its edits, a model of a rule the colors of its roles" do
    assert "flat" in Orders.files()

    drawing = %{
      "name" => "block",
      "nodes" => [
        %{
          "name" => "block_a",
          "skill" => %{
            "sculpt" => %{
              "edits" => [
                %{"shape" => "box", "size" => [0.3, 0.2, 0.1], "color" => "#f1dc86"},
                %{"shape" => "ball", "size" => [0.15], "at" => [0, 0, 0.2], "color" => "#9b4a32"}
              ],
              "cells" => %{"near" => 0.02, "mid" => 0.03, "far" => 0.05},
              "budget" => %{"near" => 2000, "mid" => 800, "far" => 300},
              "bake" => %{"near" => 512, "mid" => 256, "far" => 128}
            }
          }
        }
      ]
    }

    order = %{"blueprint" => "drawing", "options" => %{"drawing" => drawing}}
    {:ok, glb} = Orders.build(order, "far", "flat")
    json = World.GLBHelper.json(glb)
    assert [%{"primitives" => [%{"attributes" => attributes}]}] = json["meshes"]
    assert Map.keys(attributes) == ~w(COLOR_0 NORMAL POSITION) and not Map.has_key?(json, "images")
    assert length(json["nodes"]) == 1 and length(json["materials"]) == 1
    # The two colors of the edits are the colors of the points.
    colors = World.GLBHelper.floats(glb, attributes["COLOR_0"]) |> Enum.uniq()
    assert length(colors) >= 2 and length(colors) < 40

    {:ok, track} = Orders.build(%{"blueprint" => "l_track", "options" => %{"length" => 0.2}}, "far", "flat")

    {:ok, less} =
      Orders.build(%{"blueprint" => "l_track", "options" => %{"length" => 0.2}}, "far", "flat", triangles: 40)

    assert byte_size(less) < byte_size(track)
    assert {:error, [%{"path" => "triangles"}]} = Orders.build(order, "far", "flat", triangles: 5)
  end

  test "the light look: a primitive for each role with its material, no color at the points; a budget keeps each role" do
    scene = %Scene{
      name: "thing",
      # (A material with an image and no color has the color of the palette for its role.)
      materials: %{steel: %{"color" => [10, 20, 30], "roughness" => 0.4, "image" => "x"}, skin: %{"image" => "y"}},
      nodes: [
        %Scene.Node{name: "a", primitives: [triangle(:steel, 0.0), triangle(:glass, 1.0), triangle(:skin, 2.0)]},
        %Scene.Node{name: "b", primitives: [triangle(:steel, 3.0)]}
      ]
    }

    light = Flat.scene(scene, roles: true)
    assert [%Scene.Node{name: "thing", primitives: [glass, skin, steel]}] = light.nodes
    assert [glass.material, skin.material, steel.material] == [:glass, :skin, :steel]
    assert glass.colors == nil and length(steel.positions) == 6 and Flat.faces(light) == 4
    [r, g, b] = World.GLB.palette()["skin"]["color"]

    assert light.materials == %{
             steel: %{"color" => [10, 20, 30], "roughness" => 0.4},
             skin: %{"color" => [r, g, b]}
           }

    # The flat look of the same scene has the color of the palette for the skin too.
    [p] = hd(Flat.scene(scene).nodes).primitives
    assert Enum.at(p.colors, 6) == {r, g, b}

    person = Build.scene(Detail.with(:far, fn -> World.People.Human.person("p", age: 9) end), level: :far)
    roles = fn s -> s.nodes |> hd() |> Map.fetch!(:primitives) |> Enum.map(& &1.material) end
    all = Flat.scene(person, roles: true)
    small = Flat.scene(person, roles: true, budget: 600)
    assert Flat.faces(all) == Scene.triangles(person) and Flat.faces(small) <= 600
    assert roles.(small) == roles.(all) and :skin in roles.(all) and length(roles.(all)) >= 4
    assert <<"glTF", _::binary>> = World.GLB.encode(small)
  end

  test "a wrap: one closed skin round a model of many thin parts, in a small budget, with the roles of the model" do
    order = %{"blueprint" => "scooter"}
    {:ok, job} = Orders.job(order, "far")
    scooter = job.scene.(job.item.(:far), [])
    assert Scene.triangles(scooter) > 3_000

    wrapped = Flat.scene(scooter, roles: true, wrap: true, budget: 500)
    assert Flat.faces(wrapped) <= 500 and Flat.faces(wrapped) > 300
    prims = hd(wrapped.nodes).primitives
    assert :paint in Enum.map(prims, & &1.material) and length(prims) >= 4
    # The skin is as long and as high as the model (2 cells of the cast at the most), and it is closed: each
    # edge is in two faces. A part that is thinner than a cell (the ends of the bars, the mirrors) is not in it.
    {{x0, y0, _}, {x1, y1, z1}} = Scene.bounds(scooter)
    {{u0, v0, w0}, {u1, v1, w1}} = Scene.bounds(wrapped)
    for {a, b} <- [{y0, v0}, {y1, v1}, {z1, w1}], do: assert_in_delta(a, b, 0.09)
    assert u0 >= x0 and u1 <= x1 and u1 - u0 > 0.35 and w0 >= 0.0 and w0 < 0.09
    key = fn {x, y, z} -> {round(x * 1.0e5), round(y * 1.0e5), round(z * 1.0e5)} end

    edges =
      for p <- prims, [a, b, c] <- Enum.chunk_every(p.positions, 3), {u, v} <- [{a, b}, {b, c}, {c, a}] do
        Enum.sort([key.(u), key.(v)])
      end

    assert edges |> Enum.frequencies() |> Map.values() |> Enum.uniq() == [2]

    # The files of an order: light with a budget and a wrap, flat with a wrap; a wrap that is not true or false.
    assert "light" in Orders.files()
    {:ok, light} = Orders.build(order, "far", "light", triangles: 500, wrap: true)
    json = World.GLBHelper.json(light)
    assert [%{"primitives" => primitives}] = json["meshes"]
    assert length(primitives) >= 4 and Enum.all?(primitives, &(Map.keys(&1["attributes"]) == ~w(NORMAL POSITION)))
    assert length(json["nodes"]) == 1 and not Map.has_key?(json, "images") and not Map.has_key?(json, "skins")
    {:ok, flat} = Orders.build(order, "far", "flat", triangles: 500, wrap: true)
    assert [%{"primitives" => [%{"attributes" => %{"COLOR_0" => _}}]}] = World.GLBHelper.json(flat)["meshes"]

    assert {:error, [%{"path" => "wrap", "message" => "must be true or false"}]} =
             Orders.build(order, "far", "light", wrap: 1)
  end
end
