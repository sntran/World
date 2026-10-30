defmodule World.GLBTest do
  use ExUnit.Case, async: true

  alias World.Frame

  alias World.GLB

  alias World.GLBHelper

  alias World.Mesh

  alias World.Scene

  alias World.Shape

  defp box_node(name, parent \\ nil) do
    m = Shape.box({0, 0, 0}, {1, 1, 1}, :paint)

    %Scene.Node{
      name: name,
      parent: parent,
      frame: Frame.move({0, 1, 0}),
      primitives: [Scene.primitive(:paint, Mesh.triangles(m))]
    }
  end

  test "a scene of two nodes" do
    scene = %Scene{
      name: "two",
      extras: %{"kind" => "item"},
      nodes: [box_node("a"), %{box_node("b", 0) | extras: %{"role" => "door"}}]
    }

    json = GLBHelper.json(GLB.encode(scene))

    assert [%{"nodes" => [0], "name" => "two", "extras" => %{"kind" => "item"}}] = json["scenes"]
    assert [%{"children" => [1], "mesh" => 0}, %{"mesh" => 1, "extras" => %{"role" => "door"}}] = json["nodes"]
    # (x, y, z) is (-x, z, y) in glTF: a move along y is a move along +Z.
    assert hd(json["nodes"])["translation"] == [-0.0, 0.0, 1.0]
    assert [%{"name" => "paint"}] = json["materials"]
    assert Scene.triangles(scene) == 24
    assert GLB.encode(scene) == GLB.encode(scene)
  end

  test "a node with no mesh, a skin, an animation, and a texture" do
    corners = Mesh.triangles(Shape.box({0, 0, 0}, {1, 1, 1}, :skin))
    p = Scene.primitive(:skin, corners)
    n = length(p.positions)

    p = %{
      p
      | uvs: List.duplicate({0.5, 0.5}, n),
        joints: List.duplicate({0, 1, 0, 0}, n),
        weights: List.duplicate({0.5, 0.5, 0.0, 0.0}, n)
    }

    scene = %Scene{
      name: "skin",
      nodes: [
        %Scene.Node{name: "root"},
        %Scene.Node{name: "bone", parent: 0, frame: Frame.move({0, 0, 1})},
        %Scene.Node{name: "body", skin: 0, primitives: [p]}
      ],
      skins: [%{joints: [0, 1], inverse_bind: [Frame.identity(), Frame.move({0, 0, -1})], skeleton: 0, name: "rig"}],
      animations: [
        %{
          name: "wave",
          channels: [
            %{node: 1, path: :rotation, times: [0, 1], values: [Frame.identity(), Frame.turn({1, 0, 0}, 30)]},
            %{node: 1, path: :translation, times: [0, 1], values: [{0, 0, 1}, {0, 0, 1.1}]}
          ]
        }
      ],
      materials: %{
        skin: %{
          "color" => [200, 150, 120],
          "roughness" => 0.6,
          "metalness" => 0.0,
          "image" => {"image/png", <<137, 80, 78, 71>>}
        }
      }
    }

    json = GLBHelper.json(GLB.encode(scene))
    assert [%{"joints" => [0, 1], "skeleton" => 0, "name" => "rig"}] = json["skins"]
    assert [%{"channels" => [_, _], "samplers" => [_, _]}] = json["animations"]
    assert [%{"mimeType" => "image/png"}] = json["images"]
    assert [%{"pbrMetallicRoughness" => %{"baseColorTexture" => %{"index" => 0}}}] = json["materials"]
    assert %{"JOINTS_0" => _, "WEIGHTS_0" => _, "TEXCOORD_0" => _} = hd(hd(json["meshes"])["primitives"])["attributes"]
    refute Map.has_key?(Enum.at(json["nodes"], 0), "mesh")
    refute Map.has_key?(json, "extensionsUsed")

    # A texture that repeats: 3 times in one unit of UV.
    tiled = put_in(scene.materials.skin["image_scale"], 3.0)
    json = GLBHelper.json(GLB.encode(tiled))
    assert json["extensionsUsed"] == ["KHR_texture_transform"]

    assert [%{"pbrMetallicRoughness" => %{"baseColorTexture" => %{"extensions" => %{"KHR_texture_transform" => t}}}}] =
             json["materials"]

    assert t == %{"scale" => [3.0, 3.0]}
  end

  test "an animation of the weights of the morph targets" do
    p = Scene.primitive(:paint, Mesh.triangles(Shape.box({0, 0, 0}, {1, 1, 1}, :paint)))
    p = %{p | targets: [{"open", Enum.map(p.positions, fn _ -> {0.0, 0.0, 0.1} end)}]}

    scene = %Scene{
      nodes: [%Scene.Node{name: "face", primitives: [p]}],
      animations: [
        %{name: "talk", channels: [%{node: 0, path: :weights, times: [0, 0.5, 1], values: [[0.0], [1.0], [0.0]]}]}
      ]
    }

    json = GLBHelper.json(GLB.encode(scene))

    [%{"channels" => [%{"target" => %{"path" => "weights", "node" => 0}}], "samplers" => [%{"output" => out}]}] =
      json["animations"]

    assert Enum.at(json["accessors"], out)["count"] == 3
    # All the points move up (z of World is y of glTF).
    [%{"primitives" => [%{"targets" => [%{"POSITION" => t}]}]}] = json["meshes"]

    [x, y, z] = Enum.at(json["accessors"], t)["max"]
    assert x == 0.0 and z == 0.0
    assert_in_delta y, 0.1, 1.0e-6
  end

  test "a material with no role in the palette is grey, and a scene with no mesh" do
    json = GLBHelper.json(GLB.encode(%Scene{nodes: [%Scene.Node{}]}))
    refute Map.has_key?(json, "buffers")

    m = Shape.box({0, 0, 0}, {1, 1, 1}, :unknown_role)

    json =
      GLBHelper.json(
        GLB.encode(%Scene{nodes: [%Scene.Node{primitives: [Scene.primitive(m.material, Mesh.triangles(m))]}]})
      )

    assert [%{"name" => "unknown_role"}] = json["materials"]

    json =
      GLBHelper.json(
        GLB.encode(%Scene{
          materials: %{unknown_role: %{color: [0, 0, 0], roughness: 1, metalness: 0}},
          nodes: [%Scene.Node{primitives: [Scene.primitive(m.material, Mesh.triangles(m))]}]
        })
      )

    assert [%{"pbrMetallicRoughness" => %{"baseColorFactor" => [0.0, 0.0, 0.0, 1.0]}}] = json["materials"]
  end

  test "large primitives use 32-bit indices" do
    corners = for i <- 0..70_000, do: {{i / 1, 0.0, 0.0}, {0.0, 0.0, 1.0}}
    p = Scene.primitive(:paint, Enum.take(corners, 3 * div(length(corners), 3)))
    json = GLBHelper.json(GLB.encode(%Scene{nodes: [%Scene.Node{primitives: [p]}]}))
    ind = Enum.at(json["accessors"], hd(hd(json["meshes"])["primitives"])["indices"])
    assert ind["componentType"] == 5125
  end

  test "write! writes the file, and the palette has the roles" do
    path = Path.join(System.tmp_dir!(), "world_glb_test/one.glb")
    GLB.write!(path, %Scene{nodes: [box_node("a")]})
    assert File.read!(path) |> binary_part(0, 4) == "glTF"
    assert Map.has_key?(GLB.palette(), "tire")
  end

  test "gl_frame keeps a turn a turn" do
    f = GLB.gl_frame(Frame.turn({0.3, 0.4, 0.5}, 33))
    assert_in_delta World.Vec.dot(World.Vec.cross(f.x, f.y), f.z), 1.0, 1.0e-9
  end
end
