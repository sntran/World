defmodule World.Sculpt do
  @moduledoc """
  The bricks of a sculpture (`docs/plans/0008-model-from-edits.md`, D3
  and D5): the cells of the grid near its surface, found by a tree of
  processes.

  The grid has cells of `step` m. A brick is 8 × 8 × 8 cells, and the
  bricks are on one grid for each `step` (the brick `{i, j, k}` starts
  at `{i, j, k}` times 8 cells), so a brick of a sculpture stays at its
  place when the edits change. The root is a cube of 4^n bricks round
  the bounds of the sculpture (`World.SDF.bounds/1`). Each cell of the
  tree splits in 4 × 4 × 4: each child takes the edits that can change
  the field in it (`World.SDF.prune/3`, in its ball grown by the border
  of the bricks), and a child whose field at its center is more than its
  half diagonal from 0 has no surface in it, so it stops. Each child
  with a surface is a process of its own (fork and join), so the work
  goes to each scheduler of the node as the tree grows.

  A brick gives its field at 11 × 11 × 11 points: the 9 points of its 8
  cells on each axis and a border of one cell on each side, so the cells
  at its faces know the field of the next bricks. The field is a binary
  of floats of 32 bits (x first, then y, then z), which goes from one
  process to another with no copy.
  """

  alias World.{Detail, SDF, Vec}
  alias World.Sculpt.Surface

  @cells 8
  @points @cells + 3
  # The cells of each level of detail, in m (D8).
  @steps %{near: 0.02, mid: 0.08, far: 0.32}

  @doc "The cells of a brick on each axis."
  def cells, do: @cells

  @doc "The points of the field of a brick on each axis (with its border)."
  def points, do: @points

  @doc "The size of the cells (m) of a level of detail: `:near`, `:mid` or `:far`."
  def step(level), do: Map.fetch!(@steps, level)

  @doc """
  The meshes of a sculpture (a `World.Mesh` for each material): its
  bricks, the piece of the surface of each brick in the process of the
  brick, and the meshes of the pieces (`World.Sculpt.Surface`). The
  options: `level` (the level of detail of `World.Detail` by default),
  `step` (the size of the cells, the size of the level by default),
  `budget` (the most faces, `World.Simplify`) and `parallel`.
  """
  def model(edits, opts \\ []) do
    step = opts[:step] || step(opts[:level] || Detail.level())
    %{bricks: bricks} = bricks(edits, step, Keyword.put(opts, :each, &Surface.piece(&1, step)))
    Surface.meshes(Enum.map(bricks, & &1.piece), budget: opts[:budget])
  end

  @doc """
  The bricks of a sculpture with cells of `step` m: `%{bricks: bricks,
  evaluations: n, step: step}`. Each brick is `%{at: {i, j, k}, edits:
  edits, field: binary}` (the edits that can change the field in it, and
  its field). `evaluations` counts each evaluation of the distance of an
  edit at a point. The options: `parallel` (true by default): false makes
  each cell in the process that calls (the same bricks); `each`: a
  function of a brick, whose value goes into the brick as `piece`, in the
  process of the brick.
  """
  def bricks(edits, step, opts \\ []) do
    case SDF.bounds(edits) do
      nil ->
        %{bricks: [], evaluations: 0, step: step}

      {lo, hi} ->
        size = @cells * step
        {a, b, c} = from = index(lo, size)
        {d, e, f} = index(hi, size)
        span = cube(max(max(d - a, e - b), f - c) + 1, 1)
        {bricks, n} = cell(edits, {from, span}, step, {Keyword.get(opts, :parallel, true), opts[:each]})
        %{bricks: Enum.sort_by(bricks, & &1.at), evaluations: n, step: step}
    end
  end

  # The brick of a point, and the least power of 4 that holds n bricks.
  defp index({x, y, z}, size), do: {floor(x / size), floor(y / size), floor(z / size)}
  defp cube(n, span) when span >= n, do: span
  defp cube(n, span), do: cube(n, span * 4)

  # A brick: its field at each point, with the edits that can change it.
  defp cell(edits, {at, 1}, step, {_parallel, each}) do
    origin = corner(at, step)
    {ox, oy, oz} = origin

    field =
      for k <- -1..(@points - 2), j <- -1..(@points - 2), i <- -1..(@points - 2), into: <<>> do
        <<SDF.value(edits, {ox + i * step, oy + j * step, oz + k * step})::float-32-little>>
      end

    brick = %{at: at, edits: edits, field: field}
    brick = if each, do: Map.put(brick, :piece, each.(brick)), else: brick
    {[brick], length(edits) * @points ** 3}
  end

  # A cell of the tree: its 64 children, each with its edits, and the
  # children with a surface, each in a process of its own.
  defp cell(edits, {at, span}, step, {parallel, _} = how) do
    child = div(span, 4)
    {ax, ay, az} = at

    {work, n} =
      for x <- 0..3, y <- 0..3, z <- 0..3, reduce: {[], 0} do
        {work, n} ->
          c = {{ax + x * child, ay + y * child, az + z * child}, child}
          {kept, used} = classify(edits, c, step)
          {if(kept, do: [{c, kept} | work], else: work), n + used}
      end

    results =
      if parallel do
        work
        |> Enum.map(fn {c, kept} -> Task.async(fn -> cell(kept, c, step, how) end) end)
        |> Task.await_many(:infinity)
      else
        Enum.map(work, fn {c, kept} -> cell(kept, c, step, how) end)
      end

    Enum.reduce(results, {[], n}, fn {bricks, m}, {all, n} -> {bricks ++ all, n + m} end)
  end

  # The edits of a cell (in its ball, grown by the border of a brick), or
  # nil when the cell has no surface; and the evaluations that it took.
  defp classify(edits, {at, span}, step) do
    side = span * @cells * step
    center = Vec.add(corner(at, step), {side / 2, side / 2, side / 2})
    half = side * :math.sqrt(3) / 2
    kept = SDF.prune(edits, center, half + border(step))
    v = SDF.value(kept, center)
    {if(abs(v) > half, do: nil, else: kept), length(edits) + length(kept)}
  end

  # The border of a brick: one cell on each side, to its far corner.
  defp border(step), do: 2 * step * :math.sqrt(3)

  @doc "The corner of the brick `{i, j, k}` (its first cell) with cells of `step` m."
  def corner({i, j, k}, step), do: {i * @cells * step, j * @cells * step, k * @cells * step}

  @doc """
  The value of the field of a brick at its point `{i, j, k}` (from -1 to
  9 on each axis: the points of its cells and its border).
  """
  def at(%{field: field}, {i, j, k}) do
    <<v::float-32-little>> = binary_part(field, 4 * (i + 1 + @points * (j + 1 + @points * (k + 1))), 4)
    v
  end
end
