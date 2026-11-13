defmodule World.Sculpt.Finish do
  @moduledoc """
  The finish of the meshes of a sculpture
  (`docs/plans/0009-sculpture-finish.md`, D1 and D2): each point back on
  the surface of the edits, with the normal of the surface there and the
  color of the edits there.

  The collapse to a budget moves the points of a mesh by its error, and
  the normals of a mesh come from the angles between its triangles. But
  the field of the edits is exact, and a mesh in its budget has few
  points. So, for each point, with the short list of edits of its brick:

  - some steps of Newton along the gradient of the field (5 at most) put the
    point on the surface (a step is at most half a cell);
  - the gradient there is the normal of the point;
  - the fold of the edits gives its color (`World.SDF.color/3`), when an
    edit of the sculpture has a color.

  The points of some bricks go to one process, so each scheduler has
  work, and a process gets only the short lists of its bricks.
  """

  alias World.{Mesh, SDF, Sculpt, Vec}

  # The bricks of the points of one process.
  @group 16

  @doc """
  The meshes with their points on the surface, their normals and (when
  an edit has a color) their colors. `lists` is the short list of edits
  of each brick (its place to its list, `World.Sculpt.bricks/3`); a point
  in a brick that is not in `lists` takes all the `edits`.
  """
  def meshes(meshes, lists, edits, step) do
    limit = Sculpt.limit(edits, step)
    colors? = Enum.any?(edits, & &1.color)

    Enum.map(meshes, fn %Mesh{} = mesh ->
      done = points(mesh.points, lists, edits, step, limit, colors?)
      points = Enum.map(done, &elem(&1, 0))
      colors = if colors?, do: even(points, mesh.faces, Enum.map(done, &elem(&1, 2)), lists, edits, step, limit)
      Mesh.finish(%{mesh | points: points}, Enum.map(done, &elem(&1, 1)), colors)
    end)
  end

  # The color of each point, even over the faces round it: half its own
  # color, half the mean of the colors at the centers of its faces (each
  # as large as its face). Where the mesh has many points for a change of
  # the color, that is the color at the point; where the colors change
  # in less than a face (a pattern at a level of few faces), it is their
  # mean, not the color of a place that the point happens to be at.
  defp even(points, faces, colors, lists, edits, step, limit) do
    at = List.to_tuple(points)
    corners = for [a, b, c] <- faces, do: {elem(at, a), elem(at, b), elem(at, c)}
    centers = for {p, q, r} <- corners, do: Vec.scale(Vec.add(Vec.add(p, q), r), 1 / 3)
    seen = each(centers, lists, edits, step, fn p, list -> SDF.color(list, p, limit) end)

    sums =
      for {[a, b, c], {p, q, r}, {cr, cg, cb}} <- Enum.zip([faces, corners, seen]),
          area = Vec.len(Vec.cross(Vec.sub(q, p), Vec.sub(r, p))),
          v <- [a, b, c],
          reduce: %{} do
        acc ->
          add = {area * cr, area * cg, area * cb, area}

          Map.update(acc, v, add, fn {r0, g0, b0, a0} -> {r0 + area * cr, g0 + area * cg, b0 + area * cb, a0 + area} end)
      end

    for {{r, g, b} = own, i} <- Enum.with_index(colors) do
      case sums[i] do
        {sr, sg, sb, area} when area > 0.0 ->
          {round((r + sr / area) / 2), round((g + sg / area) / 2), round((b + sb / area) / 2)}

        _ ->
          own
      end
    end
  end

  @doc """
  Each point on the surface, with its normal and its color (nil with no
  `colors?`): `[{point, normal, color}]`, in the order of the points.
  """
  def points(points, lists, edits, step, limit, colors?),
    do: each(points, lists, edits, step, &point(&1, &2, step, limit, colors?))

  # The value of `f` for each point, with the short list of edits of its
  # brick, in the order of the points: the points of some bricks in one
  # process.
  defp each(points, lists, edits, step, f) do
    size = Sculpt.cells() * step

    points
    |> Enum.with_index()
    |> Enum.group_by(fn {{x, y, z}, _} -> {floor(x / size), floor(y / size), floor(z / size)} end)
    |> Enum.map(fn {at, ps} -> {Map.get(lists, at, edits), ps} end)
    |> Enum.chunk_every(@group)
    |> Task.async_stream(
      fn group -> for {list, ps} <- group, {p, i} <- ps, do: {i, f.(p, list)} end,
      max_concurrency: System.schedulers_online(),
      ordered: false,
      timeout: :infinity
    )
    |> Enum.flat_map(fn {:ok, done} -> done end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  defp point(p, list, step, limit, colors?) do
    field = &SDF.value(list, &1, limit)
    {p, gradient} = settle(p, field, step, 5)
    {p, Vec.norm(gradient), if(colors?, do: SDF.color(list, p, limit))}
  end

  # The point on the surface: steps of Newton along the gradient, each at
  # most half a cell; and the gradient at the last point.
  defp settle(p, field, step, steps) do
    v = field.(p)
    g = gradient(field, p, step * 1.0e-3)
    square = Vec.dot(g, g)

    if steps == 0 or abs(v) <= step * 1.0e-4 or square < 1.0e-12 do
      {p, g}
    else
      move = Vec.scale(g, v / square)
      far = Vec.len(move)
      move = if far > step / 2, do: Vec.scale(move, step / 2 / far), else: move
      settle(Vec.sub(p, move), field, step, steps - 1)
    end
  end

  # The gradient of the field (central differences).
  defp gradient(f, {x, y, z}, h) do
    {(f.({x + h, y, z}) - f.({x - h, y, z})) / (2 * h), (f.({x, y + h, z}) - f.({x, y - h, z})) / (2 * h),
     (f.({x, y, z + h}) - f.({x, y, z - h})) / (2 * h)}
  end
end
