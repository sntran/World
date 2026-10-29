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
