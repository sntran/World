defmodule World.Sculpt.FinishTest do
  # The finish of a sculpture: each point on the surface, the normals of
  # the surface, the colors of the edits (plan 0009, D1 to D3; R1 to R3).
  use ExUnit.Case, async: true

  alias World.{Frame, Mesh, SDF, Sculpt, Vec}
  alias World.Sculpt.{Finish, Surface}

  defp raw(edits, step, budget) do
    %{bricks: bricks} = Sculpt.bricks(edits, step, each: &Surface.piece(&1, step))
    {Surface.meshes(Enum.map(bricks, & &1.piece), budget: budget, small: 2 * step), Map.new(bricks, &{&1.at, &1.edits})}
  end

  test "after the collapse, each point is on the surface again: less than 1% of a cell (R1)" do
    edits = World.Stone.edits(30)
    step = 0.05
    limit = Sculpt.limit(edits, step)
    {raw, lists} = raw(edits, step, 600)

    off = fn meshes ->
      meshes |> Enum.flat_map(& &1.points) |> Enum.map(&abs(SDF.value(edits, &1, limit))) |> Enum.max()
    end

    done = Finish.meshes(raw, lists, edits, step)
    assert off.(raw) > 0.1 * step
    assert off.(done) < 0.01 * step
    assert Enum.map(done, & &1.faces) == Enum.map(raw, & &1.faces)
    # A point in a brick with no list takes all the edits: the same points.
    assert Finish.meshes(raw, %{}, edits, step) |> Enum.map(& &1.points) == Enum.map(done, & &1.points)
    # The model has the finish, and no colors with no color in its edits.
    model = Sculpt.model(edits, step: step, budget: 600, cache: false)
    assert off.(model) < 0.01 * step and Enum.all?(model, &(&1.normals != nil and &1.colors == nil))
  end

  test "the normal of each corner of a ball is the normal of the true surface; a box keeps its hard edges (R3)" do
    [ball] = Sculpt.model([SDF.edit(:ball, {0.5})], step: 0.05, budget: 400, cache: false)

    for {p, n} <- Mesh.triangles(ball) do
      assert_in_delta Vec.len(p), 0.5, 1.0e-5
      # Less than 1 degree from the radius.
      assert Vec.dot(n, Vec.norm(p)) > :math.cos(:math.pi() / 180)
    end

    # The same mesh with no normals of its own: the rule of the angle, some degrees off.
    plain = Mesh.triangles(%{ball | normals: nil})
    assert Enum.any?(plain, fn {p, n} -> Vec.dot(n, Vec.norm(p)) < :math.cos(2 * :math.pi() / 180) end)

    [box] = Sculpt.model([SDF.edit(:box, {0.4, 0.3, 0.2})], step: 0.05, budget: 200, cache: false)

    for [{a, n}, {b, _}, {c, _}] <- Enum.chunk_every(Mesh.triangles(box), 3) do
      face = Vec.norm(Vec.cross(Vec.sub(b, a), Vec.sub(c, a)))
      # Each corner has the normal of its flat face: one axis.
      assert Vec.dot(n, face) > 0.9999 and Enum.max(Enum.map(Tuple.to_list(n), &abs/1)) > 0.9999
    end
  end

  test "the color of each point is the color of the edits there, even over its faces, with a soft border for a paint with a blend (R2)" do
    red = {200, 30, 30}
    blue = {20, 40, 220}

    edits = [
      SDF.edit(:ball, {0.5}, color: red),
      SDF.edit(:box, {1.0, 1.0, 0.5}, frame: Frame.move({0.0, 0.0, 0.5}), mode: :paint, blend: 0.2, color: blue)
    ]

    # A paint with a color and no material keeps the material under it: one mesh.
    [mesh] = Sculpt.model(edits, step: 0.05, budget: 1_500, cache: false)
    assert length(mesh.colors) == length(mesh.points) and mesh.material == :paint
    assert {_, nil} = SDF.field(edits, {0.0, 0.0, 0.5})
    assert {_, :wood} = SDF.field([SDF.edit(:ball, {0.5}, material: :wood) | tl(edits)], {0.0, 0.0, 0.5})

    # Away from the border, the color of the edits at the point; across
    # the border, near it (the mean with the colors at the centers of the
    # faces round the point).
    for {{_, _, z} = p, {r, g, b} = c} <- Enum.zip(mesh.points, mesh.colors) do
      {r0, g0, b0} = SDF.color(edits, p)
      assert abs(r - r0) <= 20 and abs(g - g0) <= 20 and abs(b - b0) <= 20

      cond do
        z < -0.2 -> assert c == red
        z > 0.2 -> assert c == blue
        true -> assert r in 20..200 and b in 30..220
      end
    end

    # Many colors between the two across the border: no step of the grid.
    between = for {{_, _, z}, c} <- Enum.zip(mesh.points, mesh.colors), abs(z) < 0.09, uniq: true, do: c
    assert length(between) > 10
    # The corners of the mesh carry the colors.
    assert [{_, _, {_, _, _}} | _] = Mesh.triangles(mesh)
  end

  test "a pattern of colors smaller than the faces gives its mean, not the color of the place of each point" do
    # A ball with thin dark bands: 2 cm of each 4 cm, and faces of about 15 cm.
    bands =
      for k <- -12..12 do
        SDF.edit(:box, {1.0, 1.0, 0.01}, frame: Frame.move({0.0, 0.0, k * 0.04}), mode: :paint, color: {0, 0, 0})
      end

    edits = [SDF.edit(:ball, {0.5}, color: {200, 200, 200}) | bands]
    [mesh] = Sculpt.model(edits, step: 0.05, budget: 300, cache: false)
    spread = fn values -> Enum.sum(for v <- values, do: abs(v - 100)) / length(values) end
    even = spread.(for {r, _, _} <- mesh.colors, do: r)
    own = spread.(for p <- mesh.points, do: elem(SDF.color(edits, p), 0))
    # At a point, the color is one of the two; over the faces round it, nearer to their mean.
    assert own > 80 and even < 0.75 * own

    # A point with no face keeps the color of its place.
    lone = %{mesh | points: mesh.points ++ [{0.0, 0.0, 0.5}]}
    [done] = Finish.meshes([lone], %{}, edits, 0.05)
    assert List.last(done.colors) == SDF.color(edits, List.last(done.points))
  end

  test "the color of an edit that adds across its blend, of an edit that takes away, and white with no color" do
    gold = {168, 136, 64}
    green = {40, 160, 60}

    edits = [
      SDF.edit(:ball, {0.5}, color: gold),
      SDF.edit(:ball, {0.3}, frame: Frame.move({0.6, 0.0, 0.0}), blend: 0.1),
      SDF.edit(:cylinder, {0.1, 1.0}, mode: :subtract, color: green),
      SDF.edit(:ball, {0.05}, frame: Frame.move({0.0, 2.0, 0.0}), mode: :subtract)
    ]

    assert SDF.color(edits, {-0.5, 0.0, 0.0}) == gold
    assert SDF.color(edits, {0.9, 0.0, 0.0}) == {255, 255, 255}
    # In the smooth joint of the two balls: between gold and white.
    {r, g, b} = SDF.color(edits, {0.42, 0.0, 0.27})
    assert r in 169..254 and g in 137..254 and b in 65..254
    # The wall of the hole has the color of the edit that cuts it.
    assert SDF.color(edits, {0.1, 0.0, 0.0}) == green
    assert SDF.color([], {0.0, 0.0, 0.0}) == {255, 255, 255}
  end

  test "a mesh that moves turns its normals; a primitive of corners with colors has the color of each point" do
    [ball] = Sculpt.model([SDF.edit(:ball, {0.5}, color: {10, 20, 30})], step: 0.1, budget: 100, cache: false)
    turn = Frame.new({1.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0})
    moved = Mesh.transform(ball, turn)
    assert hd(moved.normals) == Frame.dir(turn, hd(ball.normals)) and moved.colors == ball.colors
    plain = World.Shape.box({0, 0, 0}, {1, 1, 1}, :paint)
    assert Mesh.transform(plain, turn).normals == nil

    part =
      World.Part.new(
        "both",
        :part,
        [ball, %{plain | points: Enum.map(plain.points, &Vec.add(&1, {5.0, 0.0, 0.0}))}],
        []
      )

    [prim] = hd(World.Build.scene(part).nodes).primitives
    assert length(prim.colors) == length(prim.positions)
    assert {10, 20, 30} in prim.colors and {255, 255, 255} in prim.colors
    assert <<"glTF", _::binary>> = World.Build.glb(part)
  end
end
