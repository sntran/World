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

  # The chart of each face of the baked meshes: its points, its normals,
  # the corners of its chart in texels, and its texels `{column, row}`.
  defp charts(meshes, side) do
    for m <- meshes, {[a, b, c], uv} <- Enum.zip(m.faces, m.uvs) do
      [{x0, y0}, {x1, _}, _] = corners = for {u, v} <- uv, do: {round(u * side), round(v * side)}
      n = abs(x1 - x0) + 4
      # The first chart of a square has its first corner at (1, 1); the second one at (n - 1, n - 1).
      {lower?, {ox, oy}} = if x1 > x0, do: {true, {x0 - 1, y0 - 1}}, else: {false, {x0 - n + 1, y0 - n + 1}}
      texels = for j <- 0..(n - 1), i <- 0..(n - 1), i + j <= n - 2 == lower?, do: {ox + i, oy + j}
      at = fn k -> {Enum.at(m.points, k), Enum.at(m.normals, k)} end
      %{corners: corners, texels: texels, points: Enum.map([a, b, c], at), n: n}
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
  # the tangents of the corners, as an app makes them (the rule of the
  # tangents of `World.GLB`).
  defp shown(chart, at, {r, g, b}) do
    [{p0, n0}, {p1, n1}, {p2, n2}] = chart.points
    [{u0, v0}, {u1, v1}, {u2, v2}] = chart.corners
    {e1, e2} = {Vec.sub(p1, p0), Vec.sub(p2, p0)}
    {du1, dv1, du2, dv2} = {u1 - u0, v1 - v0, u2 - u0, v2 - v0}
    det = du1 * dv2 - du2 * dv1
    t = Vec.scale(Vec.sub(Vec.scale(e1, dv2), Vec.scale(e2, dv1)), 1 / det)
    bt = Vec.scale(Vec.sub(Vec.scale(e2, du1), Vec.scale(e1, du2)), 1 / det)

    frames =
      for n <- [n0, n1, n2] do
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

  test "a chart for each triangle: no texel in two charts, and the values go past the edges of a chart (R3)" do
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
    assert length(all) == length(Enum.uniq(all))
    assert Enum.all?(all, fn {x, y} -> x in 0..127 and y in 0..127 end)

    # Each texel of a chart (with its border past the edges) has the color of the ball; each other texel is gray.
    owned = MapSet.new(all)

    for y <- 0..127, x <- 0..127 do
      assert texel(maps.color, x, y) == if(MapSet.member?(owned, {x, y}), do: gold, else: {128, 128, 128})
    end

    # The legs of a chart follow the area of its triangle: the image is full to a large part.
    assert length(all) > 0.6 * 128 * 128
    # An image with no place for the charts.
    assert Bake.maps(meshes, edits, 0.1, 32) == :small
    assert Bake.least(faces) > 32 and Bake.least(faces) <= 128
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

  test "a triangle with no area, a triangle far from each edit, one triangle alone; a frame with no volume" do
    edits = [SDF.edit(:ball, {0.1}, color: {10, 20, 30})]
    up = {0.0, 0.0, 1.0}

    mesh =
      Mesh.new(
        [{5.0, 0.0, 0.0}, {5.1, 0.0, 0.0}, {5.0, 0.1, 0.0}, {5.2, 0.0, 0.0}],
        # Triangles far from the ball, and a triangle with its points on a line.
        [[0, 1, 2], [0, 1, 3], [1, 3, 2], [0, 2, 1], [1, 0, 2]],
        :paint
      )
      # The normal of a point along the first side of a triangle: its tangent is another direction.
      |> Mesh.finish([up, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, up], nil)

    {[baked], maps} = Bake.maps([mesh], edits, 0.01, 64)
    assert length(baked.uvs) == 5
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
    g = gltf(@data)
    assert length(g["images"]) == 2 and length(g["materials"]) == 2
    # The two materials share the two images.
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
    assert length(g["images"]) == 2

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
    assert length(g["images"]) == 2

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
  end
end
