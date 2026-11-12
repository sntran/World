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
  the field in it (`World.SDF.cell/4`, in its ball grown by the border
  of the bricks), and a child with no surface in it stops. Each child
  with a surface is a process of its own (fork and join), so the work
  goes to each scheduler of the node as the tree grows. The processes of
  the tree are linked to the process that starts the tree (the hand of a
  sculptor, D4), so a stop of that process stops each one of them, and
  each has the label `{:sculpt, at, span}`.

  The field has a limit (`limit/2`, `World.SDF.field/3`): far from the
  surface each value is the limit, so an edit there changes nothing, and
  the short list of a brick holds only the edits near it. After a change
  of one edit, only the bricks near the old or the new edit have a new
  short list (D6).

  A brick gives its field at 11 × 11 × 11 points: the 9 points of its 8
  cells on each axis and a border of one cell on each side, so the cells
  at its faces know the field of the next bricks. The field is a binary
  of floats of 32 bits (x first, then y, then z), which goes from one
  process to another with no copy.
  """

  alias World.{Detail, SDF, Vec}
  alias World.Sculpt.{Cache, Surface}

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
  brick, the meshes of the pieces (`World.Sculpt.Surface`), with no
  piece of the surface less than two cells across, and their finish
  (each point on the surface, with its normal and its color,
  `World.Sculpt.Finish`). The
  options: `level` (the level of detail of `World.Detail` by default),
  `step` (the size of the cells, the size of the level by default),
  `budget` (the most faces, `World.Simplify`), `parallel`, and `cache`
  (true by default: the pieces of the bricks of the node, and the meshes
  of the same edits, cells and budget, `World.Sculpt.Cache`).
  """
  def model(edits, opts \\ []) do
    step = opts[:step] || step(opts[:level] || Detail.level())
    opts = opts |> Keyword.put(:each, &Surface.piece(&1, step)) |> Keyword.put_new(:cache, true)
    # The meshes of the same edits, cells and budget come from the cache.
    key = if opts[:cache], do: Cache.key({:model, opts[:budget]}, step, edits)

    with nil <- key && Cache.get(key) do
      %{bricks: bricks} = bricks(edits, step, opts)

      meshes =
        bricks
        |> Enum.map(& &1.piece)
        |> Surface.meshes(budget: opts[:budget], small: 2 * step)
        |> World.Sculpt.Finish.meshes(Map.new(bricks, &{&1.at, &1.edits}), edits, step)

      if key, do: Cache.put(key, meshes)
      meshes
    end
  end

  @doc """
  The cells (m) for the meshes of a sculpture in a budget of faces: the
  largest cells that give about 1.5 times the budget before the collapse
  (the surface of the sculpture is about half the surface of its box, and
  a cell of the surface gives about three faces), but at most half the
  thinnest edit that adds or takes away (so each part is two cells
  across), and at least an eighth of the cells of the budget. The box is
  the box of the shapes that add (with no blend). Nil with no edit that
  adds.
  """
  def fit(edits, budget) do
    case for(%{mode: :add, box: box} <- edits, do: box) do
      [] ->
        nil

      boxes ->
        {{x0, y0, z0}, {x1, y1, z1}} = Vec.bounds(Enum.flat_map(boxes, &Tuple.to_list/1))
        {a, b, c} = {x1 - x0, y1 - y0, z1 - z0}
        cells = :math.sqrt(2 * (a * b + b * c + c * a) / budget)
        thin = for %{mode: mode} = e <- edits, mode != :paint, do: thickness(e.shape, e.size)
        max(min(cells, Enum.min(thin) / 2), cells / 8)
    end
  end

  # The least thickness of a shape: twice its least size.
  defp thickness(:tube, {_, radii}), do: 2 * Enum.min(radii)
  defp thickness(:capsule, {_h, r}), do: 2 * r
  defp thickness(:ring, {_big, r}), do: 2 * r
  defp thickness(:cylinder, {r, h}), do: 2 * min(r, h)
  defp thickness(:cone, {r1, r2, h}), do: 2 * min(max(r1, r2), h)
  defp thickness(shape, {x, y, z, _}) when shape in [:round_box, :superellipsoid], do: 2 * Enum.min([x, y, z])
  defp thickness(_shape, size), do: 2 * (size |> Tuple.to_list() |> Enum.min())

  @doc """
  The bricks of a sculpture with cells of `step` m: `%{bricks: bricks,
  evaluations: n, step: step}`. Each brick is `%{at: {i, j, k}, edits:
  edits, limit: limit, field: binary}` (the edits that can change the
  field in it, the limit of the field, `limit/2`, and its field). `evaluations` counts each evaluation of the distance of an
  edit at a point. The options: `parallel` (true by default): false makes
  each cell in the process that calls (the same bricks); `each`: a
  function of a brick, whose value goes into the brick as `piece`, in the
  process of the brick; `cache` (false by default), with `each`: the
  piece of a brick comes from the cache of the node when the cache has
  its key (`World.Sculpt.Cache`), and its field is not made (`field:
  nil`); each brick has its `key`. With `cache: :keys`, a brick from the
  cache has the piece `:cached` (the piece stays in the cache). `cached`
  counts the bricks from the cache. `sink`: a function of each brick that
  is made (not from the cache), called in the process of the brick as
  soon as it is made (the stream of a live sculpture,
  `World.Sculpt.Live`).
  """
  def bricks(edits, step, opts \\ []) do
    case SDF.bounds(edits) do
      nil ->
        %{bricks: [], evaluations: 0, cached: 0, step: step}

      {lo, hi} ->
        size = @cells * step
        {a, b, c} = from = index(lo, size)
        {d, e, f} = index(hi, size)
        span = cube(max(max(d - a, e - b), f - c) + 1, 1)

        how = %{
          step: step,
          limit: limit(edits, step),
          parallel: Keyword.get(opts, :parallel, true),
          each: opts[:each],
          cache: opts[:each] && opts[:cache],
          sink: opts[:sink]
        }

        {bricks, n} = cell(edits, {from, span}, how)
        cached = Enum.count(bricks, &is_nil(&1.field))
        %{bricks: Enum.sort_by(bricks, & &1.at), evaluations: n, cached: cached, step: step}
    end
  end

  @doc """
  The limit of the field of a sculpture with cells of `step` m
  (`World.SDF.field/3`): two cells and two of its largest blends, and at
  least four cells. So the cuts of the edges of the grid, and the steps
  of their search, are in the field with no limit, unless three blends
  meet there; and the field at the center of an eighth of a brick can
  be more than its half diagonal (3.5 cells) from 0, so the tree can
  tell that it has no surface.
  """
  def limit(edits, step), do: max(2 * step + 2 * Enum.reduce(edits, 0.0, &max(&1.blend, &2)), 4 * step)

  # The brick of a point, and the least power of 4 that holds n bricks.
  defp index({x, y, z}, size), do: {floor(x / size), floor(y / size), floor(z / size)}
  defp cube(n, span) when span >= n, do: span
  defp cube(n, span), do: cube(n, span * 4)

  # A brick: its field at each point, with the edits that can change it;
  # or its piece from the cache.
  defp cell(edits, {at, 1}, %{step: step, limit: limit, each: each} = how) do
    key = if how.cache, do: Cache.key(at, step, {limit, edits})

    {brick, n} =
      case key && hit(key, how.cache) do
        nil ->
          {field, n, eighths} = field(edits, at, step, limit)
          brick = %{at: at, edits: edits, limit: limit, field: field}
          brick = if each, do: Map.put(brick, :piece, each.(Map.put(brick, :eighths, eighths))), else: brick
          if key, do: Cache.put(key, brick.piece)
          if how.sink, do: how.sink.(Map.put(brick, :key, key))
          {brick, n}

        piece ->
          {%{at: at, edits: edits, limit: limit, field: nil, piece: piece}, 0}
      end

    brick = if key, do: Map.put(brick, :key, key), else: brick
    {[brick], n}
  end

  # A cell of the tree: its 64 children, each with its edits, and the
  # children with a surface, each in a process of its own.
  defp cell(edits, {at, span}, how) do
    child = div(span, 4)
    {ax, ay, az} = at

    {work, n} =
      for x <- 0..3, y <- 0..3, z <- 0..3, reduce: {[], 0} do
        {work, n} ->
          c = {{ax + x * child, ay + y * child, az + z * child}, child}
          {kept, used} = classify(edits, c, how)
          {if(kept, do: [{c, kept} | work], else: work), n + used}
      end

    results =
      if how.parallel do
        # At most two processes for each scheduler at one time in each
        # cell: the work goes to each scheduler, and the heaps of the
        # bricks that wait for a scheduler do not fill the memory.
        work
        |> Task.async_stream(fn {c, kept} -> crew(kept, c, how) end,
          max_concurrency: 2 * System.schedulers_online(),
          ordered: false,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, result} -> result end)
      else
        Enum.map(work, fn {c, kept} -> cell(kept, c, how) end)
      end

    Enum.reduce(results, {[], n}, fn {bricks, m}, {all, n} -> {bricks ++ all, n + m} end)
  end

  # A brick of the cache: its piece, or (with `cache: :keys`) only the
  # sign that the cache has it.
  defp hit(key, :keys), do: if(Cache.member?(key), do: :cached)
  defp hit(key, _), do: Cache.get(key)

  # A cell in a process of the crew: linked to the process that made it
  # (to the hand of the sculptor at the root), so a stop of the hand stops
  # the whole tree (D4).
  defp crew(edits, {at, span} = c, how) do
    Process.set_label({:sculpt, at, span})
    cell(edits, c, how)
  end

  # The edits of a cell (in its ball, grown by the border of a brick), or
  # nil when the cell has no surface: the range of the field in its ball
  # does not hold 0, or its field at its center (at the center of each of
  # its eight parts, for a brick) is more than its half diagonal from 0;
  # and the evaluations that it took.
  defp classify(edits, {at, span}, %{step: step, limit: limit}) do
    side = span * @cells * step
    center = Vec.add(corner(at, step), {side / 2, side / 2, side / 2})
    half = side * :math.sqrt(3) / 2
    {kept, {lo, hi}} = SDF.cell(edits, center, half + border(step), limit)
    used = length(edits) + length(kept)

    cond do
      lo > 0 or hi < 0 ->
        {nil, used}

      span == 1 and not Enum.any?(parts(center, side), &(abs(SDF.value(kept, &1, limit)) <= half / 2)) ->
        {nil, used + 8 * length(kept)}

      span == 1 ->
        {kept, used + 8 * length(kept)}

      abs(SDF.value(kept, center, limit)) > half ->
        {nil, used + length(kept)}

      true ->
        {kept, used + length(kept)}
    end
  end

  # The centers of the eight parts of a cube.
  defp parts({x, y, z}, side) do
    q = side / 4
    for a <- [-q, q], b <- [-q, q], c <- [-q, q], do: {x + a, y + b, z + c}
  end

  @doc """
  The brick `at` with cells of `step` m, its short list of edits and the
  limit of its field: its field, and the short lists of its eighths
  (`eighths`, for `World.Sculpt.Surface.piece/2`).
  """
  def brick(at, edits, step, limit) do
    {field, _, eighths} = field(edits, at, step, limit)
    %{at: at, edits: edits, limit: limit, field: field, eighths: eighths}
  end

  @doc """
  The piece of a brick of `bricks/3` with `cache: :keys`: from the
  cache, or made again when the cache has let it go since.
  """
  def piece(%{piece: :cached} = b, step),
    do: Cache.get(b.key) || Surface.piece(brick(b.at, b.edits, step, b.limit), step)

  def piece(b, _step), do: b.piece

  @doc """
  The eighth of a brick (0 to 7) that the point `{i, j, k}` of the brick
  is in (in cells from its corner, from -1 to 9), or nil between two
  eighths.
  """
  def eighth({i, j, k}) do
    case {side(i), side(j), side(k)} do
      {a, b, c} when is_integer(a) and is_integer(b) and is_integer(c) -> a + 2 * b + 4 * c
      _ -> nil
    end
  end

  # The field of a brick at each of its points, with its border: each
  # eighth of the points (from -1 to 4, and from 5 to 9, on each axis)
  # with the edits of its own ball, so a point takes fewer edits; the
  # values are the same (`World.SDF.prune/4`). Also the evaluations that
  # it takes, and the lists of the eighths.
  defp field(edits, at, step, limit) do
    {ox, oy, oz} = corner(at, step)

    lists =
      List.to_tuple(
        for c <- 0..1, b <- 0..1, a <- 0..1 do
          {{cx, rx}, {cy, ry}, {cz, rz}} = {part(a), part(b), part(c)}
          center = {ox + cx * step, oy + cy * step, oz + cz * step}
          SDF.prune(edits, center, step * :math.sqrt(rx * rx + ry * ry + rz * rz), limit)
        end
      )

    field =
      for k <- -1..(@points - 2), j <- -1..(@points - 2), i <- -1..(@points - 2), into: <<>> do
        list = elem(lists, eighth({i, j, k}))
        <<SDF.value(list, {ox + i * step, oy + j * step, oz + k * step}, limit)::float-32-little>>
      end

    counts = for c <- 0..1, b <- 0..1, a <- 0..1, do: (6 - a) * (6 - b) * (6 - c)
    n = 8 * length(edits) + Enum.sum(Enum.zip_with(Tuple.to_list(lists), counts, &(length(&1) * &2)))
    {field, n, lists}
  end

  # The center and the half size of an eighth of the points on an axis
  # (in cells), and the eighth of a point.
  defp part(0), do: {1.5, 2.5}
  defp part(1), do: {7.0, 2.0}
  defp side(i) when i <= 4, do: 0
  defp side(i) when i >= 5, do: 1
  defp side(_), do: nil

  # The border of a cell: the points of its bricks go one cell past its
  # sides, so its ball is the ball of its box grown by one cell on each
  # axis.
  defp border(step), do: step * :math.sqrt(3)

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
