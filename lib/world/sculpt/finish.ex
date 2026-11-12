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

      %{mesh | points: Enum.map(done, &elem(&1, 0))}
      |> Mesh.finish(Enum.map(done, &elem(&1, 1)), if(colors?, do: Enum.map(done, &elem(&1, 2))))
    end)
  end

  @doc """
  Each point on the surface, with its normal and its color (nil with no
  `colors?`): `[{point, normal, color}]`, in the order of the points.
  """
  def points(points, lists, edits, step, limit, colors?) do
    size = Sculpt.cells() * step

    points
    |> Enum.with_index()
    |> Enum.group_by(fn {{x, y, z}, _} -> {floor(x / size), floor(y / size), floor(z / size)} end)
    |> Enum.map(fn {at, ps} -> {Map.get(lists, at, edits), ps} end)
    |> Enum.chunk_every(@group)
    |> Task.async_stream(
      fn group -> for {list, ps} <- group, {p, i} <- ps, do: {i, point(p, list, step, limit, colors?)} end,
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
