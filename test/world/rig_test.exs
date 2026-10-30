defmodule World.RigTest do
  use ExUnit.Case, async: true

  alias World.{Detail, Rig, Subdivision, Vec}

  # A cube of side 1 around the origin: 8 points, 6 faces of 4 sides
  # (each face to the outside).
  @cube_points for x <- [-0.5, 0.5], y <- [-0.5, 0.5], z <- [-0.5, 0.5], do: {x, y, z}
  @cube_faces [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]

  defp bones do
    [
      %{name: "low", head: {0, 0, -0.5}, tail: {0, 0, 0}, radius: {{0.3, 0.3}, {0.3, 0.3}}},
      %{name: "high", parent: "low", head: {0, 0, 0}, tail: {0, 0, 0.5}, radius: {{0.3, 0.3}, {0.2, 0.2}}}
    ]
  end

  test "a smooth step of a closed mesh: each face is faces of 4 sides, the weights stay a sum of 1" do
    points = Enum.map(@cube_points, fn {_, _, z} = p -> {p, if(z < 0, do: %{0 => 1.0}, else: %{1 => 1.0})} end)
    {after_one, faces} = Subdivision.smooth(points, @cube_faces, 1)
    assert length(after_one) == 8 + 12 + 6 and length(faces) == 24
    assert Enum.all?(faces, &(length(&1) == 4))

    for {p, ws} <- after_one do
      # The corners go in, the centers of the faces stay on the faces.
      assert Vec.len(p) <= :math.sqrt(0.75) + 1.0e-9
      assert_in_delta ws |> Map.values() |> Enum.sum(), 1.0, 1.0e-9
    end

    {corner, _} = hd(after_one)
    assert_in_delta elem(corner, 0), -5 / 18, 1.0e-9
    assert Subdivision.smooth(points, @cube_faces, 0) == {points, @cube_faces}
    {twice, _} = Subdivision.smooth(points, @cube_faces, 2)
    assert length(twice) == 98
  end

  test "a smooth step keeps the border, and a point on no face" do
    points = for p <- [{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}, {5, 5, 5}], do: {Vec.float(p), %{0 => 1.0}}
    {after_one, faces} = Subdivision.smooth(points, [[0, 1, 2, 3]], 1)
    places = Enum.map(after_one, &elem(&1, 0))
    assert Enum.take(places, 5) == Enum.map(points, &elem(&1, 0))
    # The middles of the 4 edges, then the center.
    assert {0.5, 0.0, 0.0} in places and {0.5, 0.5, 0.0} == List.last(places)
    assert length(faces) == 4
  end

  test "a rig with a base mesh: the points follow their bones, a sphere on the mesh" do
    weights = %{"low" => for(i <- 0..3, do: {i, 1.0}), "high" => for(i <- 4..6, do: {i, 0.5})}

    f =
      Rig.figure("box",
        bones: bones(),
        mesh: %{points: @cube_points, faces: @cube_faces, weights: weights, smooth: 0, material: :paint},
        spheres: [
          {{:on, {0.1, 0, 0.05}, {0, 1, 0}}, 0.03, "high", :eye},
          {{:on, {0.05, 0.1, 0}, {0, 0, 1}}, 0.03, "high", :eye}
        ]
      )

    [mesh] = for n <- f.nodes, n.primitives != [], do: n
    [skin, eyes] = mesh.primitives
    assert skin.material == :paint and length(skin.positions) == 8
    # A point with weights on one bone, a point with half weights on one
    # bone, a point with no weight (on the root).
    assert Enum.at(skin.joints, 0) == {0, 0, 0, 0} and Enum.at(skin.weights, 0) == {1.0, 0.0, 0.0, 0.0}
    assert Enum.at(skin.joints, 4) == {1, 0, 0, 0} and Enum.at(skin.weights, 4) == {1.0, 0.0, 0.0, 0.0}
    assert Enum.at(skin.weights, 7) == {1.0, 0.0, 0.0, 0.0}
    # Each normal goes out from the middle.
    for {p, n} <- Enum.zip(skin.positions, skin.normals), do: assert(Vec.dot(p, n) > 0)

    # The center of the first eye is a third of its radius in the face
    # y = 0.5; of the second, in the face z = 0.5.
    {ys, zs} = eyes.positions |> Enum.split(div(length(eyes.positions), 2))
    assert Vec.len(Vec.sub(Vec.mean(ys), {0.1, 0.49, 0.05})) < 1.0e-9
    assert Vec.len(Vec.sub(Vec.mean(zs), {0.05, 0.1, 0.49})) < 1.0e-9

    # A ray that meets no face: the center is at the start of the ray.
    far =
      Rig.figure("box",
        bones: bones(),
        mesh: %{points: @cube_points, faces: @cube_faces, weights: %{}},
        spheres: [{{:on, {0, 0, 2}, {0, 0, 1}}, 0.03, "low", :eye}]
      )

    [[_, eye]] = for n <- far.nodes, n.primitives != [], do: n.primitives
    assert Vec.len(Vec.sub(Vec.mean(eye.positions), {0.0, 0.0, 1.99})) < 1.0e-9
    [skin] = for n <- far.nodes, n.primitives != [], do: hd(n.primitives)
    assert skin.material == :fur

    # Far from the camera: fewer smooth steps.
    near = Rig.figure("box", bones: bones(), mesh: %{points: @cube_points, faces: @cube_faces, weights: %{}, smooth: 1})

    mid =
      Detail.with(:mid, fn ->
        Rig.figure("box", bones: bones(), mesh: %{points: @cube_points, faces: @cube_faces, weights: %{}, smooth: 1})
      end)

    count = fn f -> f.nodes |> Enum.flat_map(& &1.primitives) |> Enum.map(&length(&1.positions)) |> Enum.sum() end
    assert count.(near) == 26 and count.(mid) == 8
  end

  test "a base mesh with the colors of its points, and a part on a bone" do
    colors = for {_, _, z} <- @cube_points, do: if(z < 0, do: {0, 0, 0}, else: {255, 255, 255})

    horn =
      {[{{0.0, 0.0, 0.5}, {0.0, 0.0, 1.0}}, {{0.1, 0.0, 0.5}, {0.0, 0.0, 1.0}}, {{0.0, 0.1, 0.6}, {0.0, 0.0, 1.0}}],
       [[0, 1, 2]]}

    f =
      Rig.figure("box",
        bones: bones(),
        mesh: %{
          points: @cube_points,
          faces: @cube_faces,
          weights: %{"low" => for(i <- 0..7, do: {i, 1.0})},
          smooth: 1,
          colors: colors
        },
        parts: [{:horn, "high", elem(horn, 0), elem(horn, 1)}]
      )

    [mesh] = for n <- f.nodes, n.primitives != [], do: n
    [skin, part] = mesh.primitives
    # The new points of the smooth step are means of the colors.
    assert length(skin.colors) == 26 and Enum.any?(skin.colors, fn {r, _, _} -> r > 0 and r < 255 end)
    assert Enum.all?(skin.joints, &(&1 == {0, 0, 0, 0}))
    assert part.material == :horn and part.colors == nil and Enum.uniq(part.joints) == [{1, 0, 0, 0}]

    glb = World.GLB.encode(World.Build.scene(f))
    [prim | _] = World.GLBHelper.json(glb)["meshes"] |> hd() |> Map.fetch!("primitives")
    assert Map.has_key?(prim["attributes"], "COLOR_0")
  end

  test "a fringe: the faces with no fade are under, the faces with some fade are under and over, lifted" do
    fade = for {_, _, z} <- @cube_points, do: if(z < 0, do: 0.0, else: 1.0)

    f =
      Rig.figure("box",
        bones: bones(),
        mesh: %{
          points: @cube_points,
          faces: @cube_faces,
          weights: %{"low" => for(i <- 0..7, do: {i, 1.0})},
          colors: List.duplicate({200, 100, 50}, 8),
          fade: fade,
          fringe: {:fur, :bare, :fringe},
          faded: [:fringe],
          lift: %{fringe: 0.01}
        }
      )

    [mesh] = for n <- f.nodes, n.primitives != [], do: n
    by = Map.new(mesh.primitives, &{&1.material, &1})
    # The bottom is bare; the four sides are bare under a fringe; the top
    # is fur.
    assert Map.keys(by) |> Enum.sort() == [:bare, :fringe, :fur]
    assert length(by.fur.positions) == 4 and length(by.bare.positions) == 8 and length(by.fringe.positions) == 8

    # The fringe has the fade as the alpha of its colors, 1 cm out.
    assert Enum.sort(Enum.uniq(by.fringe.colors)) == [{200, 100, 50, 0.0}, {200, 100, 50, 1.0}]
    assert Enum.uniq(by.bare.colors) == [{200, 100, 50}]
    out = fn p -> p.positions |> Enum.map(&Vec.len/1) |> Enum.max() end
    assert_in_delta out.(by.fringe), out.(by.bare) + 0.01, 1.0e-6

    json = World.GLBHelper.json(World.GLB.encode(World.Build.scene(f)))

    types =
      for p <- hd(json["meshes"])["primitives"], do: Enum.at(json["accessors"], p["attributes"]["COLOR_0"])["type"]

    assert Enum.sort(types) == ["VEC3", "VEC3", "VEC4"]
  end

  test "a base mesh with UVs and fur: a seam splits a point, a smooth step makes the UVs of each face" do
    # Each face of the cube has its own square of UV: each edge is a seam.
    uvs =
      for {f, k} <- Enum.with_index(@cube_faces),
          do: Enum.map(Enum.zip(f, [{0, 0}, {1, 0}, {1, 1}, {0, 1}]), fn {_, {u, v}} -> {(u + 2 * k) / 12, v / 2} end)

    fur = for {_, _, z} <- @cube_points, do: if(z < 0, do: 0.0, else: 0.02)
    roles = [:eye | List.duplicate(:fur, 5)]
    dirs = List.duplicate({1.0, 0.0, 0.0}, length(@cube_points))

    mesh = %{
      points: @cube_points,
      faces: @cube_faces,
      weights: %{},
      smooth: 1,
      roles: roles,
      fur: fur,
      fur_dirs: dirs,
      uvs: uvs
    }

    f = Rig.figure("box", bones: bones(), mesh: Map.put(mesh, :colored, [:fur]))

    [node] = for n <- f.nodes, n.primitives != [], do: n
    [eye, skin] = node.primitives
    # A face after one step is 3 × 3 points of its own: 9 for the eye and
    # 45 for the 5 faces of fur (26 points with no seams).
    assert length(eye.positions) == 9 and length(skin.positions) == 45
    assert length(skin.uvs) == 45 and eye.fur == nil and length(skin.fur) == 45

    # The center of a face has the mean UV of its corners; a point on a
    # seam has one normal on its two sides; the fur is a mean too.
    assert {1 / 24, 0.25} in eye.uvs

    by_place = Enum.group_by(Enum.zip(eye.positions ++ skin.positions, eye.normals ++ skin.normals), &elem(&1, 0))
    for {_, list} <- by_place, do: assert(length(Enum.uniq_by(list, &elem(&1, 1))) == 1)
    assert Enum.min(skin.fur) == 0.0 and Enum.max(skin.fur) == 0.02 and 0.01 in skin.fur

    # The direction of the fur along the skin: x on the faces along x, the
    # normal on the faces across x.
    for {d, n} <- Enum.zip(skin.fur_dirs, skin.normals) do
      assert abs(World.Vec.len(d) - 1) < 1.0e-9
      assert abs(World.Vec.dot(d, n)) < 1.0e-6 or d == n
    end

    attrs = World.GLBHelper.json(World.GLB.encode(World.Build.scene(f)))["meshes"] |> hd() |> Map.fetch!("primitives")

    assert [%{"attributes" => %{"TEXCOORD_0" => _} = eye_attrs}, %{"attributes" => %{"_FUR" => _, "_FUR_DIR" => _}}] =
             attrs

    refute Map.has_key?(eye_attrs, "_FUR")

    # Fur on a role with no colors: `furred`.
    g = Rig.figure("box", bones: bones(), mesh: mesh |> Map.put(:colored, [:fur]) |> Map.put(:furred, [:eye, :fur]))
    [eye, _] = hd(for n <- g.nodes, n.primitives != [], do: n).primitives
    assert length(eye.fur) == 9 and length(eye.fur_dirs) == 9
  end

  test "a rig with a smooth skin: one surface, a thin tube, a sphere on the skin" do
    bones =
      bones() ++
        [
          %{
            name: "ear",
            parent: "high",
            head: {0.15, 0, 0.4},
            tail: {0.15, 0, 0.6},
            radius: {{0.02, 0.02}, {0.01, 0.01}},
            skin: :tube
          }
        ]

    f =
      Rig.figure("blob",
        bones: bones,
        blend: 0.05,
        step: 0.05,
        spheres: [{{:on, {0, 0, 0.2}, {0, 1, 0}}, 0.02, "high", :eye}]
      )

    [mesh] = for n <- f.nodes, n.primitives != [], do: n
    [fur, eye] = mesh.primitives
    assert fur.material == :fur and length(fur.positions) > 100
    for w <- fur.weights, do: assert_in_delta(Enum.sum(Tuple.to_list(w)), 1.0, 1.0e-9)
    # Both bones move the skin, the ear has its own tube.
    assert fur.joints |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort() == [0, 1, 2]
    # The skin of "high" at z = 0.2 is about 0.26 from its bone.
    front = eye.positions |> Enum.map(&elem(&1, 1)) |> Enum.max()
    assert front > 0.2 and front < 0.32
  end
end
