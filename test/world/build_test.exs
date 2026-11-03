defmodule World.BuildTest do
  use ExUnit.Case, async: true

  alias World.{Assembly, Build, GLBHelper, Mirror, Part, Scene, Shape}

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  defp brick(name \\ "brick"), do: Part.new(name, :brick, [Shape.box({0, 0, 0}, {0.2, 0.1, 0.06}, :clay)], [@o])

  # A mesh of 254 triangles: big enough to share at two copies.
  defp wheel(name \\ "wheel"),
    do: Part.new(name, :wheel, [Shape.cylinder(0.1, 0.05, :rubber, sides: 64)], [@o])

  defp base, do: Part.new("base", :part, [Shape.box({0, 0, -0.01}, {4.0, 0.1, 0.0}, :steel)], [@o])

  # A row of n bricks (or of other parts) on a base.
  defp row(n, part \\ brick()) do
    Enum.reduce(1..n, Assembly.new("row", base(), root: "base"), fn i, a ->
      Assembly.add(a, "b#{i}", part, at: Part.port("p#{i}", {0.2 * i, 0, 0}, {0, 0, 1}, {0, 1, 0}), port: "o")
    end)
  end

  defp points(%Scene{} = s) do
    frames = Scene.world_frames(s)

    s.nodes
    |> Enum.with_index()
    |> Enum.flat_map(fn {n, i} ->
      for f <- if(n.instances, do: Enum.map(n.instances, &World.Frame.compose(frames[i], &1)), else: [frames[i]]),
          p <- n.primitives,
          pt <- p.positions,
          do: round6(World.Frame.point(f, pt))
    end)
    |> MapSet.new()
  end

  test "a big mesh in the model twice is in the scene once: each copy is a node with its frame" do
    s = Build.scene(row(2, wheel()))
    [root | copies] = s.nodes
    assert length(copies) == 2 and Enum.all?(copies, &(&1.parent == 0 and &1.mesh == 0))
    assert hd(copies).primitives == List.last(copies).primitives
    assert Enum.map(copies, & &1.name) == ~w(b1 b2)
    # The base is in the mesh of the root, at its place.
    assert [%{material: :steel}] = root.primitives
    tris = div(length(hd(hd(copies).primitives).indices), 3)
    assert tris >= 100 and Scene.triangles(s) == 12 + 2 * tris
    assert_in_delta s.extras["size"] |> hd(), 4.0, 1.0e-9

    # A small mesh (a brick) in a few copies stays in the mesh of its node.
    assert [%{primitives: [_, _]}] = Build.scene(row(15)).nodes
  end

  test "16 copies in one node are one node with an instance for each; with instances: false, in the mesh of the node" do
    s = Build.scene(row(16))
    assert [_, %Scene.Node{instances: frames, name: "brick", extras: %{"count" => 16}}] = s.nodes
    assert length(frames) == 16 and Scene.triangles(s) == 17 * 12
    flat = Build.scene(row(16), instances: false)
    assert [%{instances: nil}] = flat.nodes
    assert points(s) == points(flat)
    assert Scene.bounds(s) == Scene.bounds(flat)
  end

  test "a mirror shares the mesh of its source, with a scale of -1 on x, and has the same points" do
    right = wheel("shoe")
    left = Mirror.part(right, "shoe_left")

    pair =
      Assembly.new("pair", base(), root: "base")
      |> Assembly.add("r", right, at: Part.port("r", {0.5, 0, 0}, {0, 0, 1}, {0, 1, 0}), port: "o")
      |> Assembly.add("l", left, at: Part.port("l", {-0.5, 0, 0}, {0, 0, 1}, {0, 1, 0}), port: "o")

    s = Build.scene(pair)
    [_, r, l] = s.nodes
    assert r.mesh == l.mesh and r.scale == 1.0 and l.scale == {-1.0, 1.0, 1.0}

    # The points of the mirror, from its own meshes, are the points of the
    # node with the scale.
    own = for m <- left.shapes, pt <- m.points, into: MapSet.new(), do: round6(World.Vec.add(pt, {-0.5, 0.0, 0.0}))
    assert MapSet.subset?(own, points(%{s | nodes: [hd(s.nodes), l]}))

    # Many mirrors in one node: the frames are mirrors and the node has the scale.
    lefts =
      Enum.reduce(1..16, Assembly.new("lefts", base(), root: "base"), fn i, a ->
        at = Part.port("p#{i}", {0.2 * i, 0, 0}, {0, 0, 1}, {1, 1, 0})
        a |> Assembly.add("l#{i}", left, at: at, port: "o") |> Assembly.add("r#{i}", right, at: at, port: "o")
      end)

    many = Build.scene(lefts)
    assert [{-1.0, 1.0, 1.0}, 1.0] == many.nodes |> Enum.filter(& &1.instances) |> Enum.map(& &1.scale)
    assert points(many) == points(Build.scene(lefts, instances: false))
  end

  test "a split scene: each part a node with its task, and the copies share a mesh" do
    s = Build.scene(row(16), split: true)
    [_ | parts] = s.nodes
    assert length(parts) == 17 and Enum.all?(parts, &(&1.instances == nil and &1.extras["task"]))
    assert parts |> Enum.map(& &1.mesh) |> Enum.uniq() == [0, 1]
  end

  test "the GLB of a model with copies: one mesh, the scale of a mirror and the instances" do
    json = GLBHelper.json(Build.glb(row(16)))
    assert length(json["meshes"]) == 2 and json["extensionsUsed"] == ["EXT_mesh_gpu_instancing"]
    [_, node] = json["nodes"]
    %{"TRANSLATION" => t, "ROTATION" => r} = node["extensions"]["EXT_mesh_gpu_instancing"]["attributes"]
    assert Enum.at(json["accessors"], t)["count"] == 16 and Enum.at(json["accessors"], r)["type"] == "VEC4"

    shoe = wheel("shoe")

    pair =
      Assembly.new("pair", base(), root: "base")
      |> Assembly.add("r", shoe, at: Part.port("r", {0.5, 0, 0}, {0, 0, 1}, {0, 1, 0}), port: "o")
      |> Assembly.add("l", Mirror.part(shoe), at: Part.port("l", {-0.5, 0, 0}, {0, 0, 1}, {0, 1, 0}), port: "o")

    json = GLBHelper.json(Build.glb(pair))
    assert [_, %{"mesh" => m}, %{"mesh" => m, "scale" => [-1.0, 1.0, 1.0]}] = json["nodes"]
    refute Map.has_key?(json, "extensionsUsed")
  end

  defp round6({x, y, z}), do: {Float.round(x / 1, 5) + 0.0, Float.round(y / 1, 5) + 0.0, Float.round(z / 1, 5) + 0.0}
end
