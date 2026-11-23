defmodule World.Sculpt.Shade do
  @moduledoc """
  The look of a level of a sculpture with a budget and no maps (plan
  0020, D5 and D6): for each point of its meshes, how open the point is
  (the occlusion), its dirt and its wear, and the finish of the edits
  there. A level with maps has the same things in its texels
  (`World.Sculpt.Bake`); here they are in the points, so a far model with
  no image still has dark creases, worn edges, metal and light.

  - How open a point is comes from the field along the normal of the
    point: how much of the way is taken at two near distances (a crease)
    and at two far ones (a part over the place, as the body of a car over
    its wheel), with the distances and the parts of the bake. As the color
    of a point (`World.Sculpt.Finish`), it is even over the faces round
    the point: half its own value, half the mean of the values at the
    centers of its faces (each as large as its face). A mesh of few faces
    has its points at its corners and in its creases; a face shows the
    values of its corners from one to the next, so a large open face is
    not dark from a crease at one corner.
  - `dirt` makes a point in a crease darker and more rough; `wear` makes
    a point at a sharp edge lighter and less rough.
  - The finish is the fold of the edits (`World.SDF.finish/3`): the
    roughness, the metal and the glow, with the finish of the role of the
    palette for an edit with none.

  The occlusion goes into the alpha of the color of each point (`:alpha`,
  the default: the color stays true, and an app that reads only the color
  draws the model opaque), into the color (`:color`: the color times how
  open the point is), or nowhere (`occlusion: false`).
  """

  alias World.{Mesh, SDF, Vec}

  # The distances of the values along the normal, in cells, and the part
  # of each in how open a place is (as in `World.Sculpt.Bake`).
  @near {1.5, 4.0}
  @far {10.0, 25.0}
  @parts {0.3, 0.3, 0.25, 0.15}
  # The distance of the value under the surface for the wear of an edge, in cells.
  @under 2.0
  # The points of one process.
  @group 256

  @doc """
  The meshes of a level with the color and the finish of each point
  (`World.Mesh.shaded/3`). `look` has `occlusion` (true or false),
  `into` (`:alpha` or `:color`), `dirt` and `wear`; `defaults` is the
  finish of each role (a role to `{roughness, metal}`). With no
  occlusion, no dirt, no wear and no edit with a finish, the meshes stay
  as they are.
  """
  def meshes(meshes, edits, step, defaults, look) do
    if look.occlusion or look.dirt > 0.0 or look.wear > 0.0 or SDF.finished?(edits),
      do: Enum.map(meshes, &mesh(&1, edits, step, defaults, look)),
      else: meshes
  end

  defp mesh(%Mesh{points: points, normals: normals, faces: faces} = mesh, edits, step, defaults, look) do
    at = List.to_tuple(points)

    # The center, the normal and the area of each face with an area.
    centers =
      for [a, b, c] = face <- faces,
          {p, q, r} = {elem(at, a), elem(at, b), elem(at, c)},
          cross = Vec.cross(Vec.sub(q, p), Vec.sub(r, p)),
          area = Vec.len(cross) / 2,
          area > 0.0,
          do: {face, Vec.scale(Vec.add(Vec.add(p, q), r), 1 / 3), cross, area}

    samples =
      for({p, n} <- Enum.zip(points, normals), do: {p, n, true}) ++ for({_, c, n, _} <- centers, do: {c, n, false})

    seen =
      samples
      |> Enum.chunk_every(@group)
      |> Task.async_stream(&group(&1, edits, step, defaults, look), ordered: true, timeout: :infinity)
      |> Enum.flat_map(fn {:ok, list} -> list end)

    {own, around} = Enum.split(seen, length(points))
    shades = even(Enum.map(own, &elem(&1, 0)), Enum.zip(centers, around), length(points))
    colors = mesh.colors || List.duplicate({255, 255, 255}, length(points))

    shaded =
      for {color, shade, {_, finish}} <- Enum.zip([colors, shades, own]), do: shaded(color, finish, shade, look)

    Mesh.shaded(mesh, Enum.map(shaded, &elem(&1, 0)), Enum.map(shaded, &elem(&1, 1)))
  end

  # The values of each point, even over its faces: half its own, half the
  # mean of the values at the centers of its faces by their areas.
  defp even(own, faces, count) do
    sums =
      for {{[a, b, c], _, _, area}, {{o, k, e}, _}} <- faces, i <- [a, b, c], reduce: %{} do
        acc ->
          Map.update(acc, i, {o * area, k * area, e * area, area}, fn {so, sk, se, sa} ->
            {so + o * area, sk + k * area, se + e * area, sa + area}
          end)
      end

    for {{o, k, e}, i} <- Enum.zip(own, 0..(count - 1)//1) do
      case sums do
        %{^i => {so, sk, se, sa}} -> {(o + so / sa) / 2, (k + sk / sa) / 2, (e + se / sa) / 2}
        _ -> {o, k, e}
      end
    end
  end

  # How open each point of a group is, how deep in a crease, how near a
  # sharp edge, and its finish: with the edits that can change the field
  # at the farthest distance from the box of the group.
  defp group(pairs, edits, step, defaults, look) do
    {lo, hi} = Vec.bounds(Enum.map(pairs, &elem(&1, 0)))
    {center, half} = {Vec.lerp(lo, hi, 0.5), Vec.len(Vec.sub(hi, lo)) / 2}
    {{n1, n2}, {f1, f2}} = {@near, @far}
    # (The values are right as far as the farthest distance: a limit past it.)
    limit = (f2 + 2) * step
    near = SDF.fast(SDF.prune(edits, center, half + (n2 + 0.5) * step, limit))
    far = SDF.fast(SDF.prune(edits, center, half + (f2 + 0.5) * step, limit))
    here = SDF.prune(edits, center, half + step, limit)
    {a, b, c, d} = @parts

    # How much of the way along the normal is taken: 0 with nothing there,
    # 1 with a surface at the place.
    taken = fn list, p, n, cells, at ->
      dist = cells * step
      min(max((dist + at - SDF.value(list, Vec.add(p, Vec.scale(n, dist)), limit)) / dist, 0.0), 1.0)
    end

    for {p, n, finish?} <- pairs do
      n = Vec.norm(n)
      {at, wide} = {SDF.value(near, p, limit), SDF.value(far, p, limit)}
      {o1, o2} = {taken.(near, p, n, n1, at), taken.(near, p, n, n2, at)}
      # (The square: a part that is far takes a small part of the sky.)
      {o3, o4} = {taken.(far, p, n, f1, wide) ** 2, taken.(far, p, n, f2, wide) ** 2}
      edge = if look.wear > 0.0, do: thin(near, p, n, at, step, limit), else: 0.0
      # (The finish of a point; a face gives only how open its center is.)
      {{1.0 - (a * o1 + b * o2 + c * o3 + d * o4), (o1 + o2) / 2, edge}, finish? && SDF.finish(here, p, defaults)}
    end
  end

  # How thin the solid is under a point: 0 under a flat face, more near a sharp edge.
  defp thin(near, p, n, at, step, limit) do
    dist = @under * step
    min(max((dist - at + SDF.value(near, Vec.sub(p, Vec.scale(n, dist)), limit)) / dist, 0.0), 1.0)
  end

  # The color and the finish of a point with its dirt, its wear and its
  # occlusion (as the bake shades a texel).
  defp shaded({r, g, b}, {rough, metal, glow}, {open, crease, edge}, %{dirt: dirt, wear: wear} = look) do
    dark = 1.0 - 0.6 * dirt * crease
    light = 0.35 * wear * edge
    tone = fn v -> min(v * dark + (255 - v * dark) * light, 255.0) end
    rough = min(max(rough + 0.3 * dirt * crease - 0.25 * wear * edge, 0.05), 1.0)
    {r, g, b} = {tone.(r), tone.(g), tone.(b)}

    color =
      case {look.occlusion, look.into} do
        {false, _} -> {round(r), round(g), round(b)}
        {true, :color} -> {round(r * open), round(g * open), round(b * open)}
        {true, :alpha} -> {round(r), round(g), round(b), Float.round(open, 3)}
      end

    {color, {byte(rough), byte(metal), byte(glow)}}
  end

  defp byte(v), do: round(min(max(v, 0.0), 1.0) * 255)
end
