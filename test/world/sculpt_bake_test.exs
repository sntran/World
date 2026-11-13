defmodule World.Sculpt.BakeTest do
  # The maps of a sculpture: a color map and a normal map from the field
  # of its edits, a chart for each triangle (plan 0010, D1 to D4; R1 to R5).
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Drawing, Frame, Mesh, Orders, SDF, Sculpt, Vec}
  alias World.Sculpt.Bake

  # The texel of a map at a column and a row.
  defp texel(rows, x, y) do
    <<_::binary-size(^x * 3), r, g, b, _::binary>> = Enum.at(rows, y)
    {r, g, b}
  end

  # The chart of each face of the baked meshes: its points with their
  # normals, the corners of its chart in texels, the tangent and the
  # bitangent of each corner as an app makes them, and its texels
  # `{column, row}`: the texels with their centers in the triangle.
  defp charts(meshes, side) do
    for m <- meshes, tangents = tangents(m), {[a, b, c], uv} <- Enum.zip(m.faces, m.uvs) do
      corners = for {u, v} <- uv, do: {u * side, v * side}
      at = fn k -> {Enum.at(m.points, k), Enum.at(m.normals, k)} end
      points = Enum.map([a, b, c], at)

      chart = %{
        corners: corners,
        points: points,
        frames: for({point, uv} <- Enum.zip(points, uv), do: tangents[{point, uv}])
      }

      {xs, ys} = Enum.unzip(corners)

      [{x0, y0}, {x1, y1}, {x2, y2}] = corners
      # (A chart with its corners on a line has no texel.)
      flat? = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0) == 0

      texels =
        for j <- floor(Enum.min(ys))..ceil(Enum.max(ys)),
            i <- floor(Enum.min(xs))..ceil(Enum.max(xs)),
            not flat?,
            {la, lb, lc} = weights(chart, {i, j}),
            min(la, min(lb, lc)) >= 0,
            do: {i, j}

      Map.put(chart, :texels, texels)
    end
  end

  # The tangent and the bitangent of each point of a mesh (a point with
  # its normal and its UV), as an app makes them (the rule of
  # `World.GLB`): the sum of the directions of +u and of +v on the
  # surface, of each triangle with that point.
  defp tangents(m) do
    points = List.to_tuple(Enum.zip(m.points, m.normals))

    for {face, [{u0, v0}, {u1, v1}, {u2, v2}] = uv} <- Enum.zip(m.faces, m.uvs), reduce: %{} do
      acc ->
        [{{p0, _}, _}, {{p1, _}, _}, {{p2, _}, _}] = keys = Enum.zip(Enum.map(face, &elem(points, &1)), uv)
        {e1, e2} = {Vec.sub(p1, p0), Vec.sub(p2, p0)}
        {du1, dv1, du2, dv2} = {u1 - u0, v1 - v0, u2 - u0, v2 - v0}
        det = du1 * dv2 - du2 * dv1

        if abs(det) < 1.0e-12 do
          acc
        else
          t = Vec.scale(Vec.sub(Vec.scale(e1, dv2), Vec.scale(e2, dv1)), 1 / det)
          bt = Vec.scale(Vec.sub(Vec.scale(e2, du1), Vec.scale(e1, du2)), 1 / det)
          Enum.reduce(keys, acc, &Map.update(&2, &1, {t, bt}, fn {t0, b0} -> {Vec.add(t0, t), Vec.add(b0, bt)} end))
        end
    end
  end

  # The weights of the three corners of a chart at the center of a texel.
  defp weights(%{corners: [{x0, y0}, {x1, y1}, {x2, y2}]}, {x, y}) do
    {px, py} = {x + 0.5, y + 0.5}
    det = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
    l1 = ((px - x0) * (y2 - y0) - (x2 - x0) * (py - y0)) / det
    l2 = ((x1 - x0) * (py - y0) - (px - x0) * (y1 - y0)) / det
    {1 - l1 - l2, l1, l2}
  end

  defp mix([a, b, c], {la, lb, lc}), do: Vec.add(Vec.add(Vec.scale(a, la), Vec.scale(b, lb)), Vec.scale(c, lc))

  # The normal of a texel in the axes of the sculpture: from the map and
  # the tangents of the corners, as an app makes them.
  defp shown(chart, at, {r, g, b}) do
    frames =
      for {{_, n}, {t, bt}} <- Enum.zip(chart.points, chart.frames) do
        tangent = Vec.norm(Vec.sub(t, Vec.scale(n, Vec.dot(n, t))))
        sign = if Vec.dot(Vec.cross(n, tangent), bt) > 0, do: -1.0, else: 1.0
        {tangent, Vec.scale(Vec.cross(n, tangent), sign), n}
      end

    w = weights(chart, at)
    [tm, bm, nm] = for k <- 0..2, do: Vec.norm(mix(Enum.map(frames, &elem(&1, k)), w))
    {x, y, z} = {r / 127.5 - 1, g / 127.5 - 1, b / 127.5 - 1}
    Vec.norm(Vec.add(Vec.add(Vec.scale(tm, x), Vec.scale(bm, y)), Vec.scale(nm, z)))
  end

  defp angle(a, b), do: :math.acos(min(max(Vec.dot(a, b), -1.0), 1.0)) * 180 / :math.pi()

  test "the charts: a triangle has its own texels, the border of a chart has the values of the texels next to it, the image is full to a large part (R3)" do
    gold = {200, 160, 60}
    edits = [SDF.edit(:ball, {0.5}, color: gold)]
    meshes = Sculpt.model(edits, step: 0.1, budget: 201, cache: false)
    faces = meshes |> Enum.map(&length(&1.faces)) |> Enum.sum()
    {baked, maps} = Bake.maps(meshes, edits, 0.1, 128)
    assert maps.side == 128 and length(maps.color) == 128 and byte_size(hd(maps.normal)) == 3 * 128

    # A baked mesh has the UVs of the corners of its faces, no colors of its points, and each corner the normal of its point.
    assert [%Mesh{colors: nil, angle: 180.0, uvs: [[{_, _}, {_, _}, {_, _}] | _]}] = baked
    charts = charts(baked, 128)
    assert length(charts) == faces
    all = Enum.flat_map(charts, & &1.texels)
    # A texel is in one triangle (but for a texel with its center on an edge of two triangles).
    assert length(all) - length(Enum.uniq(all)) < 0.01 * length(all)
    assert Enum.all?(all, fn {x, y} -> x in 0..127 and y in 0..127 end)

    # Each texel of a triangle has the color of the ball, and each texel
    # as far as two texels from it too (the border of its chart: an app
    # reads the maps a little past the edge of a triangle). A texel far
    # from each triangle is gray.
    owned = MapSet.new(all)

    near? = fn x, y, far ->
      Enum.any?(-far..far, fn dy -> Enum.any?(-far..far, &MapSet.member?(owned, {x + &1, y + dy})) end)
    end

    for y <- 0..127, x <- 0..127 do
      cond do
        near?.(x, y, 2) -> assert texel(maps.color, x, y) == gold
        not near?.(x, y, 4) -> assert texel(maps.color, x, y) == {128, 128, 128}
        true -> :border
      end
    end

    # The triangles next to each other on the ball are next to each other in the image: two
    # triangles with a common edge have that edge at one place of the image, for most of the edges.
    edges =
      for %{corners: [a, b, c], points: [{p, _}, {q, _}, {r, _}]} <- charts,
          {e, at} <- [{{p, q}, {a, b}}, {{q, r}, {b, c}}, {{r, p}, {c, a}}],
          do: {Enum.sort(Tuple.to_list(e)), Enum.sort(Tuple.to_list(at))}

    joined = edges |> Enum.group_by(&elem(&1, 0), &elem(&1, 1)) |> Map.values() |> Enum.count(&match?([same, same], &1))
    assert joined > 0.5 * length(edges) / 2

    # A texel has one size on the surface, for each triangle and each direction: the sides of a
    # triangle in the image are its sides on the surface times one scale, to 15 % (a patch is
    # seen flat from the direction of its first triangle, at most 30 degrees from each of its faces).
    scales =
      for %{corners: [a, b, c], points: [{p, _}, {q, _}, {r, _}]} <- charts,
          {{x0, y0}, {x1, y1}, from, to} <- [{a, b, p, q}, {b, c, q, r}, {c, a, r, p}] do
        :math.sqrt((x1 - x0) ** 2 + (y1 - y0) ** 2) / Vec.len(Vec.sub(to, from))
      end

    assert Enum.min(scales) > 0.85 * Enum.max(scales)

    # The image is full to a large part.
    assert length(all) > 0.33 * 128 * 128
    # An image with no place for the charts.
    assert Bake.maps(meshes, edits, 0.1, 16) == :small
    assert Bake.least(faces) > 16 and Bake.least(faces) <= 128
  end

  test "the color of a texel is the color of the edits at its place; a sharp border stays sharp (R1)" do
    red = {200, 30, 30}
    blue = {20, 40, 220}
    green = {30, 180, 60}

    edits = [
      SDF.edit(:ball, {0.5}, color: red),
      # A sharp border at z = 0.1, and a soft spot at the side.
      SDF.edit(:box, {1.0, 1.0, 0.5}, frame: Frame.move({0.0, 0.0, 0.6}), mode: :paint, color: blue),
      SDF.edit(:ball, {0.2}, frame: Frame.move({0.5, 0.0, -0.2}), mode: :paint, blend: 0.1, color: green)
    ]

    meshes = Sculpt.model(edits, step: 0.1, budget: 200, cache: false)
    {baked, maps} = Bake.maps(meshes, edits, 0.1, 256)

    for chart <- charts(baked, 256), at <- chart.texels do
      place = mix(Enum.map(chart.points, &elem(&1, 0)), weights(chart, at))
      {r, g, b} = texel(maps.color, elem(at, 0), elem(at, 1))
      {r0, g0, b0} = SDF.color(edits, place)
      assert abs(r - r0) <= 1 and abs(g - g0) <= 1 and abs(b - b0) <= 1
    end

    # Away from the soft spot, a texel is red or blue: no mix at the sharp border.
    far =
      for c <- charts(baked, 256),
          Enum.all?(c.points, fn {{x, _, _}, _} -> x < 0 end),
          {x, y} <- c.texels,
          uniq: true,
          do: texel(maps.color, x, y)

    assert Enum.sort(far) == Enum.sort([red, blue])
  end

  test "the normal map and the tangents give the normal of the true surface; a small relief is in the map (R2)" do
    ball = [SDF.edit(:ball, {0.5})]
    meshes = Sculpt.model(ball, step: 0.1, budget: 200, cache: false)
    {baked, maps} = Bake.maps(meshes, ball, 0.1, 256)
    # With no color, only the normal map.
    assert maps.color == nil

    worst =
      for chart <- charts(baked, 256), at <- chart.texels, reduce: 0.0 do
        worst ->
          place = mix(Enum.map(chart.points, &elem(&1, 0)), weights(chart, at))
          max(worst, angle(shown(chart, at, texel(maps.normal, elem(at, 0), elem(at, 1))), Vec.norm(place)))
      end

    assert worst < 2.0

    # A bump of 2 cm on the ball (a fifth of a cell): not in the mesh of 200 faces, but in the map.
    bump = ball ++ [SDF.edit(:ball, {0.05}, frame: Frame.move({0.0, 0.0, 0.47}), blend: 0.01)]
    {baked, maps} = Bake.maps(meshes, bump, 0.1, 256)

    turned =
      for chart <- charts(baked, 256), at <- chart.texels do
        place = mix(Enum.map(chart.points, &elem(&1, 0)), weights(chart, at))
        angle(shown(chart, at, texel(maps.normal, elem(at, 0), elem(at, 1))), Vec.norm(place))
      end

    assert Enum.max(turned) > 20.0
    # Only near the bump: most of the texels have the normal of the ball.
    assert Enum.count(turned, &(&1 > 2.0)) < 0.05 * length(turned)
  end

  test "a corner at a hard edge has the normal of its face; a corner of a smooth surface keeps the normal of its point" do
    box = [SDF.edit(:box, {0.3, 0.2, 0.1}, color: {200, 60, 60})]
    [mesh] = Sculpt.model(box, step: 0.05, budget: 300, cache: false)
    {[baked], maps} = Bake.maps([mesh], box, 0.05, 128)
    # The points at the edges of the box are there again, one for each face that is far from the normal of the point.
    assert length(baked.points) > length(mesh.points)
    assert Enum.take(baked.points, length(mesh.points)) == mesh.points
    assert length(baked.normals) == length(baked.points) and baked.colors == nil
    {pt, nt} = {List.to_tuple(baked.points), List.to_tuple(baked.normals)}

    for [a, b, c] = face <- baked.faces do
      flat = Vec.norm(Vec.cross(Vec.sub(elem(pt, b), elem(pt, a)), Vec.sub(elem(pt, c), elem(pt, a))))
      for v <- face, do: assert(angle(elem(nt, v), flat) < 35.1)
    end

    # The normals of the map are the normals of the faces of the box, but
    # for the texels at an edge (a texel there has a part of two faces).
    along =
      for chart <- charts([baked], 128),
          {x, y} = at <- chart.texels,
          {la, lb, lc} = weights(chart, at),
          min(la, min(lb, lc)) > 0.05 do
        n = shown(chart, at, texel(maps.normal, x, y))
        Enum.max(Enum.map(Tuple.to_list(n), &abs/1))
      end

    assert Enum.count(along, &(&1 > 0.999)) > 0.85 * length(along)

    # A mesh of more than 4,000 triangles: its patches are made in groups
    # of triangles, each group in its own process, and each triangle has
    # its chart.
    fine = Sculpt.model(ball = [SDF.edit(:ball, {0.5}, color: {200, 60, 60})], step: 0.03, budget: 4_400, cache: false)
    many = fine |> Enum.map(&length(&1.faces)) |> Enum.sum()
    assert many > 4_000
    {many_baked, many_maps} = Bake.maps(fine, ball, 0.03, 512)
    many_charts = charts(many_baked, 512)
    assert length(many_charts) == many
    assert Enum.count(many_charts, &(&1.texels != [])) > 0.99 * many

    for chart <- Enum.take_every(many_charts, 50),
        {x, y} <- chart.texels,
        do: assert(texel(many_maps.color, x, y) == {200, 60, 60})

    # A ball has no hard edge: no new point.
    ball = [SDF.edit(:ball, {0.5})]
    [round] = Sculpt.model(ball, step: 0.1, budget: 200, cache: false)
    {[same], _} = Bake.maps([round], ball, 0.1, 128)
    assert same.points == round.points and same.faces == round.faces
  end

  test "a long chart reads the field in its triangle: no color of another part past its end, and the true normals" do
    red = {200, 40, 40}
    # A red cylinder with a blue ball past its end.
    edits = [
      SDF.edit(:cylinder, {0.05, 0.2}, color: red),
      SDF.edit(:ball, {0.08}, frame: Frame.move({0.0, 0.0, 0.3}), color: {40, 40, 200})
    ]

    # Two long thin triangles on the side of the cylinder, from end to end: a texel
    # of a small chart is 32 mm from the next one, and 1.5 texels past the end is at the ball.
    turn = fn deg -> {0.05 * :math.cos(deg * :math.pi() / 180), 0.05 * :math.sin(deg * :math.pi() / 180)} end
    side = fn deg, z -> (fn {x, y} -> {x, y, z} end).(turn.(deg)) end
    points = [side.(0, -0.19), side.(0, 0.19), side.(10, -0.19), side.(10, 0.19)]
    normals = for {x, y, _} <- points, do: Vec.norm({x, y, 0.0})
    mesh = Mesh.new(points, [[0, 2, 1], [1, 2, 3]], :paint) |> Mesh.finish(normals, nil)
    {[baked], maps} = Bake.maps([mesh], edits, 0.005, 16)
    assert baked.points == points
    charts = charts([baked], 16)
    assert length(charts) == 2

    for chart <- charts, {x, y} = at <- chart.texels do
      # Each texel of the two charts, in the triangle or past its edge, is red.
      assert texel(maps.color, x, y) == red
      # Its normal is the normal of the cylinder at its place in the triangle.
      {la, lb, lc} = weights(chart, at)
      w = Enum.map([la, lb, lc], &max(&1, 0.0))
      inside = List.to_tuple(Enum.map(w, &(&1 / Enum.sum(w))))
      {px, py, _} = mix(Enum.map(chart.points, &elem(&1, 0)), inside)
      {r, g, b} = texel(maps.normal, x, y)
      # (The frame of the texel at that place: the weights with none less than 0.)
      n = shown(%{chart | corners: chart.corners}, at, {r, g, b})
      if min(la, min(lb, lc)) >= 0, do: assert(angle(n, Vec.norm({px, py, 0.0})) < 2.0)
      assert b >= 250
    end

    # With cells as large as the texels, the texels read the field at their own places: the blue of the ball is there.
    {_, wide} = Bake.maps([mesh], edits, 0.5, 16)
    colors = for row <- wide.color, <<r, g, b <- row>>, uniq: true, do: {r, g, b}
    assert red in colors
  end

  test "a triangle with no area, a triangle far from each edit, one triangle alone; a frame with no volume" do
    edits = [SDF.edit(:ball, {0.1}, color: {10, 20, 30})]
    up = {0.0, 0.0, 1.0}

    mesh =
      Mesh.new(
        [
          {5.0, 0.0, 0.0},
          {5.1, 0.0, 0.0},
          {5.0, 0.1, 0.0},
          {5.2, 0.0, 0.0},
          {5.0625, 1.0e-10, 0.0},
          {5.125, 0.0, 0.0},
          # A small triangle (1 mm: less than a texel), and a long one alone.
          {6.0, 0.0, 0.0},
          {6.001, 0.0, 0.0},
          {6.0, 0.001, 0.0},
          {7.0, 0.0, 0.0},
          {7.4, 0.0, 0.0},
          {7.1, 0.05, 0.0}
        ],
        # Triangles far from the ball, two triangles with their points on
        # a line (one with its first point between the two others), and
        # a sliver: its points almost on a line (the product of the
        # squares of its sides less the square of their product is 0 in
        # floats).
        [[0, 1, 2], [0, 1, 3], [1, 0, 3], [1, 3, 2], [0, 2, 1], [1, 0, 2], [0, 5, 4], [6, 7, 8], [9, 10, 11]],
        :paint
      )
      # The normal of a point of the sliver along the direction of +u of
      # its chart: its tangent is another direction. (A triangle with an
      # area has the normal of its face at such a corner.)
      |> Mesh.finish([up, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, up, {0.0, 1.0, 0.0}, up, up, up, up, up, up, up], nil)

    {[baked], maps} = Bake.maps([mesh], edits, 0.01, 64)
    assert length(baked.uvs) == 9
    # Far from each edit the field has no gradient: the normal of the face, and no color of an edit.
    colors = for row <- maps.color, <<r, g, b <- row>>, uniq: true, do: {r, g, b}
    assert Enum.sort(colors) == [{128, 128, 128}, {255, 255, 255}]
    for row <- maps.normal, <<r, g, b <- row>>, do: assert(r in 127..128 and g in 127..128 and b == 255)

    assert Bake.in_frame({0.0, 1.0, 0.0}, {1.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, up) == {0.0, 0.0, 1.0}
    assert Bake.in_frame({0.0, 1.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, up) == {0.0, 1.0, 0.0}
  end

  defp drawing(data),
    do: %{"name" => "ball", "kind" => "item", "nodes" => [%{"name" => "ball", "skill" => %{"sculpt" => data}}]}

  defp paths(data) do
    case Orders.check(%{"blueprint" => "drawing", "options" => %{"drawing" => drawing(data)}}) do
      {:error, errors} -> Enum.map(errors, & &1["path"])
      {:ok, _} -> []
    end
  end

  defp gltf(data) do
    <<"glTF", 2::little-32, _::little-32, size::little-32, "JSON", json::binary-size(size), _::binary>> =
      Detail.with(:far, fn -> Build.glb(Drawing.build(drawing(data))) end)

    JSON.decode!(json)
  end

  @data %{
    "edits" => [
      %{"shape" => "ball", "size" => [0.3], "material" => "paint", "color" => "#c08020"},
      %{"shape" => "ball", "size" => [0.1], "at" => [0, 0.3, 0], "material" => "gray"}
    ],
    "cells" => %{"far" => 0.05},
    "budget" => %{"far" => 300},
    "bake" => %{"far" => 128}
  }

  test "the GLB of a baked sculpture: the two maps on each material, a sampler with no smaller copies, tangents (R5)" do
    assert paths(@data) == []
    # With no occlusion: the color and the normals.
    g = gltf(Map.put(@data, "occlusion", false))
    assert length(g["images"]) == 2 and length(g["materials"]) == 2
    assert Enum.all?(g["materials"], &(not is_map_key(&1, "occlusionTexture")))

    # The occlusion is in the red of a third image: the finish, with the roughness and the metal (plan 0012, D1).
    g = gltf(@data)
    assert length(g["images"]) == 3 and length(g["materials"]) == 2

    for m <- g["materials"] do
      assert %{"index" => finish} = m["pbrMetallicRoughness"]["metallicRoughnessTexture"]
      assert m["occlusionTexture"] == %{"index" => finish}
      assert %{"roughnessFactor" => 1.0, "metallicFactor" => 1.0} = m["pbrMetallicRoughness"]
    end

    # The two materials share the images.
    for m <- g["materials"] do
      assert %{"index" => color} = m["pbrMetallicRoughness"]["baseColorTexture"]
      assert %{"index" => normal} = m["normalTexture"]
      assert Enum.map([color, normal], &Enum.at(g["textures"], &1)["sampler"]) == [1, 1]
    end

    assert [_, %{"minFilter" => 9729, "magFilter" => 9729, "wrapS" => 33071, "wrapT" => 33071}] = g["samplers"]

    for p <- hd(g["meshes"])["primitives"] do
      assert Map.has_key?(p["attributes"], "TEXCOORD_0") and Map.has_key?(p["attributes"], "TANGENT")
      refute Map.has_key?(p["attributes"], "COLOR_0")
    end

    # With no color of an edit: only the normal map. With bones: a skinned mesh with the maps.
    plain = put_in(@data, ["edits"], [%{"shape" => "ball", "size" => [0.3]}])
    assert [%{"normalTexture" => _} = m] = gltf(plain)["materials"]
    refute Map.has_key?(m["pbrMetallicRoughness"], "baseColorTexture")

    bones = [
      %{"name" => "a", "head" => [0, -0.3, 0], "tail" => [0, 0, 0]},
      %{"name" => "b", "parent" => "a", "head" => [0, 0, 0], "tail" => [0, 0.4, 0]}
    ]

    g = gltf(Map.put(@data, "bones", bones))
    assert [%{"joints" => [_, _]}] = g["skins"]
    assert length(g["images"]) == 3

    for p <- hd(g["meshes"])["primitives"] do
      assert ~w(JOINTS_0 NORMAL POSITION TANGENT TEXCOORD_0 WEIGHTS_0) -- Map.keys(p["attributes"]) == []
    end

    # With no bake at the level: the colors of the points, as before.
    g = gltf(Map.put(@data, "bake", %{"near" => 1024}) |> Map.put("budget", %{"far" => 300, "near" => 5_000}))
    assert g["images"] == nil and Map.has_key?(hd(hd(g["meshes"])["primitives"])["attributes"], "COLOR_0")
  end

  test "with maps, a relief smaller than the cells is in the maps only; with no maps, it is in the mesh" do
    data = %{
      "edits" => [
        %{"shape" => "ball", "size" => [0.3], "color" => "#c08020"},
        %{"shape" => "ball", "size" => [0.1], "at" => [0, 0, 0.3], "mode" => "paint", "blend" => 0.02, "raise" => 0.02}
      ],
      "cells" => %{"far" => 0.05},
      "budget" => %{"far" => 2_000}
    }

    top = fn data ->
      {"ball", part, _} = hd(Detail.with(:far, fn -> Drawing.build(drawing(data)) end).nodes)
      part.shapes |> Enum.flat_map(& &1.points) |> Enum.map(&elem(&1, 2)) |> Enum.max()
    end

    assert_in_delta top.(data), 0.32, 0.002
    assert_in_delta top.(Map.put(data, "bake", %{"far" => 256})), 0.3, 0.005
    # A relief of half a cell or more stays in the mesh with maps too.
    high = put_in(data, ["cells", "far"], 0.03) |> Map.put("bake", %{"far" => 256})
    assert_in_delta top.(high), 0.32, 0.002
  end

  test "a sculpture with details: each detail has its own cells and its levels; the maps of all are one image (plan 0010, D5)" do
    data = %{
      "edits" => [%{"shape" => "ball", "size" => [0.3], "color" => "#c82020"}],
      "cells" => %{"mid" => 0.05, "far" => 0.05},
      "budget" => %{"mid" => 400, "far" => 400},
      "details" => [
        %{
          # A small blue horn, with cells of a tenth of the cells of the ball.
          "edits" => [%{"shape" => "cone", "size" => [0.02, 0.0, 0.04], "at" => [0, 0, 0.33], "color" => "#2020c8"}],
          "cells" => %{"mid" => 0.005},
          "budget" => %{"mid" => 200},
          "levels" => ["mid"]
        }
      ]
    }

    assert paths(data) == []
    shapes = fn data, level -> elem(hd(Detail.with(level, fn -> Drawing.build(drawing(data)) end).nodes), 1).shapes end
    [ball, horn] = shapes.(data, :mid)
    {{_, _, _}, {_, _, top}} = Vec.bounds(horn.points)
    # The horn is 8 cm high and 4 cm wide: less than one cell of the ball, and it has its shape.
    assert_in_delta top, 0.37, 0.003
    assert length(horn.faces) in 50..200 and length(ball.faces) <= 400
    assert {32, 32, 200} in horn.colors and {200, 32, 32} in ball.colors
    # At far the sculpture has no detail.
    assert [_ball] = shapes.(data, :far)

    # With maps: one image for the ball and the horn, each with the colors of its own edits.
    baked = Map.put(data, "bake", %{"mid" => 256})
    assert paths(baked) == []
    [ball, horn] = shapes.(baked, :mid)
    assert ball.uvs != nil and horn.uvs != nil and horn.colors == nil
    g = gltf_at(baked, :mid)
    assert length(g["images"]) == 3

    # The maps of the parts, each with its own edits and cells.
    edits = fn list -> World.Skills.Sculpt.edits(list) end
    {main, detail} = {edits.(data["edits"]), edits.(hd(data["details"])["edits"])}

    parts = [
      {Sculpt.model(main, step: 0.05, budget: 400), main, 0.05},
      {Sculpt.model(detail, step: 0.005, budget: 200), detail, 0.005}
    ]

    {[b, h], maps} = Bake.maps(parts, 256)
    [red] = for c <- charts([b], 256) |> Enum.take(1), {x, y} <- Enum.take(c.texels, 1), do: texel(maps.color, x, y)
    blues = for c <- charts([h], 256), {x, y} <- c.texels, uniq: true, do: texel(maps.color, x, y)
    # (A triangle with no area has a gray chart.)
    assert {red, blues -- [{128, 128, 128}]} == {{200, 32, 32}, [{32, 32, 200}]}

    # With bones, the points of a detail follow the bones too.
    bones = [%{"name" => "a", "head" => [0, 0, -0.3], "tail" => [0, 0, 0.4]}]
    g = gltf_at(Map.put(baked, "bones", bones), :mid)
    assert Enum.all?(hd(g["meshes"])["primitives"], &Map.has_key?(&1["attributes"], "JOINTS_0"))

    # The errors of the details, each with its path.
    at = "options.drawing.nodes.0.skill.sculpt"
    bad = fn value -> paths(Map.put(data, "details", value)) end
    detail = hd(data["details"])
    assert bad.(7) == ["#{at}.details"]
    assert bad.([7]) == ["#{at}.details.0"]
    assert bad.([%{"cells" => %{"mid" => 0.005}}]) == ["#{at}.details.0.edits"]
    assert bad.([Map.put(detail, "levels", ["high"])]) == ["#{at}.details.0.levels"]
    assert bad.([Map.put(detail, "levels", [])]) == ["#{at}.details.0.levels"]
    assert bad.([Map.put(detail, "bake", %{})]) == ["#{at}.details.0.bake"]
    assert bad.([Map.put(detail, "budget", %{"mid" => 1})]) == ["#{at}.details.0.budget.mid"]
    assert bad.([Map.put(detail, "cells", %{"mid" => 9})]) == ["#{at}.details.0.cells.mid"]
    assert bad.([put_in(detail, ["edits", Access.at(0), "shape"], "horn")]) == ["#{at}.details.0.edits.0.shape"]
    # A baked level needs the budget of each detail at that level, and a place for all the triangles.
    assert paths(Map.put(baked, "details", [Map.delete(detail, "budget")])) == ["#{at}.bake.mid"]
    assert paths(Map.put(baked, "details", [Map.delete(detail, "budget") |> Map.put("levels", ["far"])])) == []
    assert paths(Map.put(baked, "bake", %{"mid" => 64})) == ["#{at}.bake.mid"]
  end

  defp gltf_at(data, level) do
    <<"glTF", 2::little-32, _::little-32, size::little-32, "JSON", json::binary-size(size), _::binary>> =
      Detail.with(level, fn -> Build.glb(Drawing.build(drawing(data)), level: level) end)

    JSON.decode!(json)
  end

  test "the finish of the edits at a point: a roughness, a metal and a glow, with the weights of the colors (plan 0010, D10)" do
    ball = SDF.edit(:ball, {0.5}, material: :gold)
    # A half of metal with a soft border, a wet spot, and a spot that glows.
    metal =
      SDF.edit(:box, {1.0, 1.0, 0.5},
        frame: Frame.move({0.0, 0.0, 0.6}),
        mode: :paint,
        blend: 0.1,
        metal: 1.0,
        roughness: 0.2
      )

    wet = SDF.edit(:ball, {0.1}, frame: Frame.move({0.5, 0.0, -0.2}), mode: :paint, roughness: 0.05)
    lamp = SDF.edit(:ball, {0.1}, frame: Frame.move({-0.5, 0.0, -0.2}), mode: :paint, glow: 0.8, color: {255, 200, 100})
    edits = [ball, metal, wet, lamp]
    assert SDF.finished?(edits) and not SDF.finished?([ball])
    # With no finish of its own, an edit that adds has the finish of its material, or rough and no metal.
    assert SDF.finish(edits, {0.0, 0.0, -0.5}) == {0.6, 0.0, 0.0}
    assert SDF.finish(edits, {0.0, 0.0, -0.5}, %{gold: {0.3, 1.0}}) == {0.3, 1.0, 0.0}
    assert SDF.finish(edits, {0.0, 0.0, 0.5}) == {0.2, 1.0, 0.0}
    # A paint gives the parts that it has: the roughness only, or the glow only.
    assert SDF.finish(edits, {0.5, 0.0, -0.2}) == {0.05, 0.0, 0.0}
    assert SDF.finish(edits, {-0.5, 0.0, -0.2}) == {0.6, 0.0, 0.8}
    # Across the soft border of the metal: between the two.
    {rough, metal_part, _} = SDF.finish(edits, Vec.scale(Vec.norm({1.0, 0.0, 0.22}), 0.5))
    assert rough > 0.2 and rough < 0.6 and metal_part > 0.0 and metal_part < 1.0
    # An edit that adds with its own finish, and a cut with a finish on the surface that it cuts.
    knob = SDF.edit(:ball, {0.1}, frame: Frame.move({0.0, 0.5, 0.0}), roughness: 0.9, metal: 0.5, glow: 0.1)
    hole = SDF.edit(:ball, {0.1}, frame: Frame.move({0.0, -0.5, 0.0}), mode: :subtract, metal: 1.0)
    assert SDF.finish([ball, knob, hole], {0.0, 0.6, 0.0}) == {0.9, 0.5, 0.1}
    assert SDF.finish([ball, knob, hole], {0.0, -0.4, 0.0}) == {0.6, 1.0, 0.0}

    # One fold gives the value, the color and the finish: the same as the
    # two folds, to the bit, for each mode of an edit.
    crop = SDF.edit(:box, {0.45, 1.0, 1.0}, mode: :crop, blend: 0.05, roughness: 0.1, color: {9, 9, 9})
    all = edits ++ [knob, hole, crop]
    :rand.seed(:exsss, {4, 4, 4})

    for _ <- 1..300 do
      p = {:rand.uniform() * 1.4 - 0.7, :rand.uniform() * 1.4 - 0.7, :rand.uniform() * 1.4 - 0.7}
      {value, color} = SDF.sample(all, p, 0.3)
      assert SDF.sample(all, p, 0.3, %{gold: {0.3, 1.0}}) == {value, color, SDF.finish(all, p, %{gold: {0.3, 1.0}})}
    end

    # The maps: the roughness in the green and the metal in the blue of the finish, the color times the glow.
    meshes = Sculpt.model(edits, step: 0.1, budget: 200, cache: false)
    {baked, maps} = Bake.maps(meshes, edits, 0.1, 128)
    assert length(maps.finish) == 128 and length(maps.glow) == 128

    for chart <- charts(baked, 128), {x, y} = at <- chart.texels do
      place = mix(Enum.map(chart.points, &elem(&1, 0)), weights(chart, at))
      {rough, metal, glow} = SDF.finish(edits, place)
      assert texel(maps.finish, x, y) == {255, round(rough * 255), round(metal * 255)}
      {r, g, b} = SDF.color(edits, place)
      assert texel(maps.glow, x, y) == {round(r * glow), round(g * glow), round(b * glow)}
    end

    # No chart: rough, no metal, no glow. With no finish of an edit, no such images.
    assert texel(maps.finish, 127, 127) == {255, 153, 0} and texel(maps.glow, 127, 127) == {0, 0, 0}

    assert {_, %{finish: nil, glow: nil}} =
             Bake.maps(Sculpt.model([ball], step: 0.1, budget: 200, cache: false), [ball], 0.1, 128)

    # A finish and no glow: the image of the finish only.
    assert {_, %{finish: [_ | _], glow: nil}} = Bake.maps(meshes, [ball, metal], 0.1, 128)
  end

  test "the GLB of a sculpture with finishes: the image of the metal and the roughness, and the image of the glow (R10)" do
    data =
      put_in(@data, ["edits"], [
        %{"shape" => "ball", "size" => [0.3], "material" => "paint", "color" => "#c08020"},
        %{
          "shape" => "box",
          "size" => [0.4, 0.4, 0.2],
          "at" => [0, 0, 0.25],
          "mode" => "paint",
          "blend" => 0.05,
          "finish" => "shiny_metal"
        },
        %{
          "shape" => "ball",
          "size" => [0.08],
          "at" => [0.3, 0, 0],
          "mode" => "paint",
          "glow" => 0.9,
          "roughness" => 0.3
        }
      ])

    assert paths(data) == []
    g = gltf(data)
    assert length(g["images"]) == 4
    [m] = g["materials"]

    assert %{"metallicRoughnessTexture" => %{"index" => _}, "roughnessFactor" => 1.0, "metallicFactor" => 1.0} =
             m["pbrMetallicRoughness"]

    assert %{"emissiveTexture" => %{"index" => glow}, "emissiveFactor" => [1.0, 1.0, 1.0]} = m
    assert Enum.at(g["textures"], glow)["sampler"] == 1

    # The finish of an edit from its name, or from its own numbers; the errors with their paths.
    [_, metal, lamp] = World.Skills.Sculpt.edits(data["edits"])
    assert {metal.roughness, metal.metal, metal.glow} == {0.15, 1.0, nil}
    assert {lamp.roughness, lamp.metal, lamp.glow} == {0.3, nil, 0.9}
    at = "options.drawing.nodes.0.skill.sculpt.edits.1"
    bad = fn key, value -> paths(put_in(data, ["edits", Access.at(1), key], value)) end
    assert bad.("finish", "wax") == ["#{at}.finish"]
    assert bad.("roughness", 2) == ["#{at}.roughness"]
    assert bad.("metal", -1) == ["#{at}.metal"]
    assert bad.("glow", "bright") == ["#{at}.glow"]
  end

  # The texels of the baked meshes with their places: `{place, {column, row}}`.
  defp places(meshes, side) do
    for c <- charts(meshes, side), at <- c.texels, do: {mix(Enum.map(c.points, &elem(&1, 0)), weights(c, at)), at}
  end

  test "the look from the shape: a crease is less open, dirt is in the creases, wear is at the sharp edges (plan 0012, R1)" do
    # A slab with a post on it, of one gray.
    gray = {128, 128, 128}
    slab = SDF.edit(:box, {0.5, 0.5, 0.05}, color: gray)
    post = SDF.edit(:box, {0.1, 0.1, 0.2}, frame: Frame.move({0.0, 0.0, 0.25}), color: gray)
    edits = [slab, post]
    meshes = Sculpt.model(edits, step: 0.02, budget: 1_500, cache: false)
    mean = fn list -> Enum.sum(list) / length(list) end

    # With no look, the maps are as before: no finish for edits with none.
    {_, plain} = Bake.maps([{meshes, edits, 0.02}], 256, %{})
    assert plain.finish == nil

    {baked, maps} = Bake.maps([{meshes, edits, 0.02}], 256, %{}, %{occlusion: true})
    assert maps.color == plain.color and maps.normal == plain.normal
    at = places(baked, 256)
    red = fn {i, j} -> elem(texel(maps.finish, i, j), 0) end
    # The top of the slab, far from the post and from its edges: open.
    open = for {{x, y, z}, t} <- at, z > 0.045, x < -0.3, x > -0.45, abs(y) < 0.3, do: red.(t)
    # The top of the slab at the foot of the post: a crease.
    foot = for {{x, y, z}, t} <- at, z > 0.045, z < 0.055, x < -0.1, x > -0.125, abs(y) < 0.08, do: red.(t)
    # A side of the post near its top: less open than the slab (the slab is under it), more than the foot.
    side = for {{x, y, z}, t} <- at, x < -0.095, x > -0.105, z > 0.3, z < 0.4, abs(y) < 0.06, do: red.(t)
    assert length(open) > 100 and length(foot) > 10 and length(side) > 10
    assert mean.(open) > 240
    assert mean.(foot) < 0.6 * mean.(open)
    assert mean.(side) > mean.(foot) + 40
    # The green and the blue are the finish of the material by default: rough, no metal.
    assert {_, 153, 0} = texel(maps.finish, elem(hd(at), 1) |> elem(0), elem(hd(at), 1) |> elem(1))

    # Dirt: the foot of the post is darker and more rough; the open top is as it was.
    {dirty, soil} = Bake.maps([{meshes, edits, 0.02}], 256, %{}, %{dirt: 1.0})
    at = places(dirty, 256)
    tone = fn maps, {i, j} -> elem(texel(maps.color, i, j), 0) end
    rough = fn maps, {i, j} -> elem(texel(maps.finish, i, j), 1) end

    {open, foot} =
      {for({{x, y, z}, t} <- at, z > 0.045, x < -0.3, x > -0.45, abs(y) < 0.3, do: t),
       for({{x, y, z}, t} <- at, z > 0.045, z < 0.055, x < -0.1, x > -0.125, abs(y) < 0.08, do: t)}

    assert mean.(Enum.map(foot, &tone.(soil, &1))) < 0.75 * mean.(Enum.map(open, &tone.(soil, &1)))
    assert mean.(Enum.map(foot, &rough.(soil, &1))) > mean.(Enum.map(open, &rough.(soil, &1))) + 20
    assert_in_delta mean.(Enum.map(open, &tone.(soil, &1))), 128, 3
    # (With no occlusion, the red is 255 at each place.)
    assert Enum.all?(open ++ foot, fn {i, j} -> elem(texel(soil.finish, i, j), 0) == 255 end)

    # Wear: the top of the post near its edges is lighter and less rough than its middle.
    {worn, used} = Bake.maps([{meshes, edits, 0.02}], 256, %{}, %{wear: 1.0})
    at = places(worn, 256)
    top = for {{x, y, z}, t} <- at, z > 0.445, do: {max(abs(x), abs(y)), t}
    edge = for {far, t} <- top, far > 0.085, do: t
    middle = for {far, t} <- top, far < 0.04, do: t
    assert length(edge) > 10 and length(middle) > 10
    assert mean.(Enum.map(edge, &tone.(used, &1))) > mean.(Enum.map(middle, &tone.(used, &1))) + 10
    assert mean.(Enum.map(edge, &rough.(used, &1))) < mean.(Enum.map(middle, &rough.(used, &1))) - 10
  end

  test "a part of a baked mesh and a mesh with no maps of one material: each point has a UV" do
    edits = [SDF.edit(:ball, {0.3}, color: {200, 100, 50})]
    {[baked], _} = Bake.maps(Sculpt.model(edits, step: 0.1, cache: false), edits, 0.1, 128)
    box = World.Shape.box({1, 1, 1}, {2, 2, 2}, :paint)
    [prim] = hd(Build.scene(World.Part.new("both", :part, [baked, box], [])).nodes).primitives
    assert length(prim.uvs) == length(prim.positions) and {0.0, 0.0} in prim.uvs and prim.colors == nil
  end

  test "the errors of the data `bake`, each with its path" do
    at = "options.drawing.nodes.0.skill.sculpt"
    bad = fn value -> paths(Map.put(@data, "bake", value)) end
    assert bad.(256) == ["#{at}.bake"]
    assert bad.(%{"far" => 100}) == ["#{at}.bake.far"]
    assert bad.(%{"far" => 128, "high" => 64}) == ["#{at}.bake.high"]
    # A level with a bake needs a budget, and an image with a place for its triangles.
    assert bad.(%{"mid" => 256}) == ["#{at}.bake.mid"]
    assert bad.(%{"far" => 64}) == ["#{at}.bake.far"]
    assert paths(Map.delete(@data, "budget")) == ["#{at}.bake.far"]
    # The look from the shape: true or false, and two numbers from 0 to 1.
    assert paths(Map.merge(@data, %{"occlusion" => false, "dirt" => 0.5, "wear" => 1})) == []
    assert paths(Map.put(@data, "occlusion", "no")) == ["#{at}.occlusion"]
    assert paths(Map.put(@data, "dirt", 2)) == ["#{at}.dirt"]
    assert paths(Map.put(@data, "wear", -0.1)) == ["#{at}.wear"]
  end
end
