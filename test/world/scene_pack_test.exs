defmodule World.ScenePackTest do
  # A packed primitive: its points and its normals as binaries (plan 0007,
  # D6), the same scene and the same bytes.
  use ExUnit.Case, async: true

  alias World.{Scene, Surface}
  alias World.Scene.Primitive

  defp primitive do
    corners = [
      {{0.0, 0.0, 0.0}, {0.0, 0.0, 1.0}},
      {{1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}},
      {{0.0, -2.0, 0.5}, {0.0, 0.0, 1.0}}
    ]

    Scene.primitive(:wood, corners)
  end

  test "a primitive packed and unpacked is the same primitive; its points; a primitive with more data stays as it is" do
    p = primitive()
    packed = Scene.pack(p)
    assert packed.positions == [] and packed.packed.count == 3 and byte_size(packed.packed.positions) == 72
    assert Scene.unpack(packed) == p and Scene.unpack(p) == p
    assert Scene.positions(packed) == p.positions and Scene.positions(p) == p.positions
    with_uvs = %{p | uvs: [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]}
    assert Scene.pack(with_uvs) == with_uvs
  end

  test "a scene of a packed primitive: the same box, the same GLB, and its surface" do
    node = %Scene.Node{name: "a", primitives: [primitive()]}
    scene = %Scene{nodes: [node], materials: %{}}
    packed = %{scene | nodes: [%{node | primitives: [Scene.pack(primitive())]}]}
    assert Scene.bounds(packed) == Scene.bounds(scene)
    assert World.GLB.encode(packed) == World.GLB.encode(scene)
    corners = [[0, 0], [1, 0], [1, 1], [0, 1]]
    assert Surface.apply(packed, corners) == Surface.apply(scene, corners)
    assert %Primitive{packed: nil} = hd(hd(Surface.apply(packed, corners).nodes).primitives)
  end
end
