defmodule World.Simplify do
  @moduledoc """
  Fewer triangles for a mesh, with its shape (`docs/plans/0008-model-from-edits.md`,
  D8): edge collapse by quadric error metrics (M. Garland, P. Heckbert,
  "Surface Simplification Using Quadric Error Metrics", SIGGRAPH 1997).

  Each point has the quadric of the planes of its faces: the sum of the
  squared distances to them. The cost of an edge is the least of its
  quadric at its two ends and at its middle; the edge of the least cost
  goes first: its two points become one point at that place, and the
  faces between them go. A collapse does not happen when it turns a face
  over, when the two points have more than two neighbors in common (so
  each edge stays in two faces), or when two faces would be on the same
  three points. A point at the border of two
  materials moves only along the border (an edge of the border collapses,
  and the planes of the border keep its line), and a point where three
  materials meet stays: so each face keeps its material, and the faces
  of each material still meet the faces of the next one. The collapses
  stop at the budget of faces.
  """

  alias World.Vec

  # The weight of the plane of a border of two materials.
  @border 10.0

  @doc """
  The mesh of `points` and triangles `faces` (each `{[a, b, c],
  material}`) with at most `budget` faces, or as few as it can:
  `{points, faces}` (the points that the faces use, in a new order).
  """
  def collapse(points, faces, budget) when length(faces) <= budget, do: {points, faces}

  def collapse(points, faces, budget) do
    %{points: points, faces: faces} = collapse(points, faces, budget, [])
    {points, faces}
  end

  # The cost of the square of the length of an edge (m²), next to the error of its collapse.
  @length 1.0e-7

  @doc """
  `collapse/3` with options: `fixed` (the indices of the points that
  stay where they are: the points that a mesh shares with the next
  one), `quadrics` (the quadric of each point, from a collapse
  before: the planes of the first surface, in place of the planes of
  these faces), and `pins` (a weight for each point, or nil: the cost
  of a move of the point from its first place, the weight times the
  square of the distance; so a point with a large pin stays near its
  place, as a point where the colors of a mesh change). Gives
  `%{points, faces, ids, quadrics}`: `ids` are the indices in `points`
  of the points that stay, and `quadrics` their quadrics, for a collapse
  after.

  With the option `limit`, no collapse costs more than it (the collapse
  can stop with more faces than the budget). With the option `free`, the
  collapse goes on past the budget while a collapse costs no more than
  it (a flat part needs few faces).

  With the option `costs: true`, it gives only the cost of each collapse
  in its turn and the faces after it (`[{cost, faces}]`): the collapse
  to a smaller budget does the same collapses first, so a caller with
  many meshes can give each mesh the part of one budget where the costs
  are the least.
  """
  def collapse(points, faces, budget, opts) do
    pts = points |> Enum.with_index() |> Map.new(fn {p, i} -> {i, Vec.float(p)} end)
    fs = faces |> Enum.with_index() |> Map.new(fn {{[a, b, c], m}, i} -> {i, {a, b, c, m}} end)

    vfaces =
      Enum.reduce(fs, %{}, fn {f, {a, b, c, _}}, acc ->
        Enum.reduce([a, b, c], acc, &Map.update(&2, &1, [f], fn l -> [f | l] end))
      end)

    kinds = Map.new(vfaces, fn {v, list} -> {v, list |> Enum.map(&elem(fs[&1], 3)) |> Enum.uniq() |> length()} end)
    stay = MapSet.new(Keyword.get(opts, :fixed, []))
    locked = for({v, n} <- kinds, n > 1, into: MapSet.new(), do: v) |> MapSet.union(stay)
    fixed = for({v, n} <- kinds, n > 2, into: MapSet.new(), do: v) |> MapSet.union(stay)

    # The faces of each edge, once.
    edges =
      for {f, {a, b, c, _}} <- fs, {x, y} <- [{a, b}, {b, c}, {c, a}], reduce: %{} do
        acc -> Map.update(acc, {min(x, y), max(x, y)}, [f], &[f | &1])
      end

    q =
      case opts[:quadrics] do
        nil -> pts |> quadrics(fs, edges) |> pinned(pts, opts[:pins])
        list -> list |> Enum.with_index() |> Map.new(fn {q, i} -> {i, q} end)
      end

    s = %{pts: pts, fs: fs, vf: vfaces, q: q, locked: locked, fixed: fixed, ver: %{}, count: map_size(fs)}
    heap = edges |> Map.keys() |> Enum.flat_map(&List.wrap(entry(s, &1))) |> :gb_sets.from_list()

    # (With `limit`: no collapse that costs more. With `free`: past the
    # budget, each collapse that costs no more.)
    s = Map.merge(s, %{limit: opts[:limit], free: opts[:free]})

    if opts[:costs] do
      # The cost of each collapse in its turn, and the faces that it left.
      run(Map.put(s, :costs, []), heap, budget).costs |> Enum.reverse()
    else
      s = run(s, heap, budget)
      pack(s)
    end
  end

  defp run(%{count: n, free: nil} = s, _heap, budget) when n <= budget, do: s

  defp run(s, heap, budget) do
    if :gb_sets.is_empty(heap) do
      s
    else
      {{cost, a, b, va, vb}, heap} = :gb_sets.take_smallest(heap)

      cond do
        s.limit != nil and cost > s.limit -> s
        s.count <= budget and cost > s.free -> s
        true -> step(s, heap, budget, {cost, a, b, va, vb})
      end
    end
  end

  defp step(s, heap, budget, {cost, a, b, va, vb}) do
    if Map.get(s.ver, a, 0) == va and Map.get(s.ver, b, 0) == vb and Map.has_key?(s.pts, a) and Map.has_key?(s.pts, b) do
      # The place again, as the entry found it (the two points have not
      # changed since): the heap keeps no place, so it is smaller.
      {_, ^a, ^b, place} = best(s, {min(a, b), max(a, b)})

      case merge(s, a, b, place) do
        {:ok, s} -> run(cost(s, cost), Enum.reduce(around(s, a), heap, &push(&2, s, a, &1)), budget)
        :no -> run(s, heap, budget)
      end
    else
      run(s, heap, budget)
    end
  end

  # With the option `costs`: the cost of a collapse that was done, and the faces after it.
  defp cost(%{costs: costs, count: count} = s, cost), do: %{s | costs: [{cost, count} | costs]}
  defp cost(s, _cost), do: s

  # The quadric of each point: the planes of its faces (each plane made
  # once), and the planes of the borders of the materials: for each edge
  # whose two faces have two materials, the plane through the edge at a
  # right angle to each face, with a large weight. So a point on a border
  # moves along it, and the border keeps its line.
  defp quadrics(pts, fs, edges) do
    q =
      Enum.reduce(fs, %{}, fn {_, {a, b, c, _} = face}, q ->
        p = plane(pts, face)
        Enum.reduce([a, b, c], q, fn v, q -> Map.update(q, v, p, &add(&1, p)) end)
      end)

    for {{x, y}, list} <- edges,
        list |> Enum.map(&elem(fs[&1], 3)) |> Enum.uniq() |> length() > 1,
        f <- list,
        reduce: q do
      q ->
        {a, b, c, _} = fs[f]
        side = Vec.cross(Vec.sub(pts[y], pts[x]), normal([pts[a], pts[b], pts[c]]))
        plane = plane_of(side, pts[x], @border)
        q |> Map.update!(x, &add(&1, plane)) |> Map.update!(y, &add(&1, plane))
    end
  end

  # The quadrics with the pins of the points: the quadric of a pin is
  # its weight times the square of the distance to the point.
  defp pinned(q, _pts, nil), do: q

  defp pinned(q, pts, pins) do
    for {w, i} <- Enum.with_index(pins), w > 0.0, is_map_key(q, i), reduce: q do
      q ->
        {x, y, z} = pts[i]
        pin = {w, 0.0, 0.0, -w * x, w, 0.0, -w * y, w, -w * z, w * (x * x + y * y + z * z)}
        Map.update!(q, i, &add(&1, pin))
    end
  end

  # An edge into the heap, with its cost and its place. A point where
  # three materials meet stays; a point on a border moves only along it.
  defp push(heap, s, a, b) do
    case entry(s, {min(a, b), max(a, b)}) do
      nil -> heap
      e -> :gb_sets.add(e, heap)
    end
  end

  defp entry(s, edge) do
    case best(s, edge) do
      nil -> nil
      {cost, a, b, _place} -> {cost, a, b, Map.get(s.ver, a, 0), Map.get(s.ver, b, 0)}
    end
  end

  # The cost of an edge, the point that stays, the point that goes and the
  # place: or nil.
  defp best(s, {a, b}) do
    {la, lb} = {MapSet.member?(s.locked, a), MapSet.member?(s.locked, b)}
    {fa, fb} = {MapSet.member?(s.fixed, a), MapSet.member?(s.fixed, b)}
    both = [s.pts[a], s.pts[b], Vec.scale(Vec.add(s.pts[a], s.pts[b]), 0.5)]

    # The places, and the point that stays (the first): the point that
    # does not move keeps its index too.
    {places, a, b} =
      cond do
        fa and fb -> {[], a, b}
        la and lb and not on_border?(s, a, b) -> {[], a, b}
        fa -> {[s.pts[a]], a, b}
        fb -> {[s.pts[b]], b, a}
        la and lb -> {both, a, b}
        la -> {[s.pts[a]], a, b}
        lb -> {[s.pts[b]], b, a}
        true -> {both, a, b}
      end

    case places do
      [] ->
        nil

      _ ->
        qe = add(s.q[a], s.q[b])
        {cost, place} = places |> Enum.map(&{error(qe, &1), &1}) |> Enum.min_by(&elem(&1, 0))
        # A very small cost for the length of the edge: on a flat part
        # each collapse costs nothing, and the short edges go first. (With
        # no such cost the order is by the numbers of the points: one
        # point takes all the points round it, its faces are long and
        # thin, and the work grows with the square of the faces.)
        {cost + @length * Vec.dot(Vec.sub(s.pts[a], s.pts[b]), Vec.sub(s.pts[a], s.pts[b])), a, b, place}
    end
  end

  # An edge on a border of two materials: its two faces have two materials.
  defp on_border?(s, a, b) do
    for(f <- s.vf[a], f in s.vf[b], uniq: true, do: elem(s.fs[f], 3)) |> length() > 1
  end

  # The points that share a face with a point.
  defp around(s, v), do: for(f <- s.vf[v], {a, b, c, _} = s.fs[f], u <- [a, b, c], u != v, uniq: true, do: u)

  # The points a and b become one point (a) at the place: the faces of both
  # go there, and the faces between them go.
  defp merge(s, a, b, place) do
    common = MapSet.intersection(MapSet.new(around(s, a)), MapSet.new(around(s, b)))
    shared = for f <- s.vf[a], f in s.vf[b], do: f
    moved = Enum.uniq(s.vf[a] ++ s.vf[b]) -- shared

    if MapSet.size(common) != 2 or length(shared) != 2 or twins?(s, moved, a, b) or
         Enum.any?(moved, &flips?(s, &1, a, b, place)) do
      :no
    else
      fs =
        Enum.reduce(moved, Map.drop(s.fs, shared), fn f, fs ->
          {x, y, z, m} = fs[f]
          Map.put(fs, f, {sub(x, b, a), sub(y, b, a), sub(z, b, a), m})
        end)

      vf = s.vf |> Map.delete(b) |> Map.put(a, moved)
      vf = Enum.reduce(shared, vf, fn f, vf -> drop(vf, s.fs[f], f, [a, b]) end)
      q = s.q |> Map.put(a, add(s.q[a], s.q[b])) |> Map.delete(b)
      ver = s.ver |> Map.update(a, 1, &(&1 + 1)) |> Map.update(b, 1, &(&1 + 1))
      # The point a is at the place of b when b stays: it stays too.
      locked = if MapSet.member?(s.locked, b), do: MapSet.put(s.locked, a), else: s.locked
      fixed = if MapSet.member?(s.fixed, b), do: MapSet.put(s.fixed, a), else: s.fixed
      pts = s.pts |> Map.put(a, place) |> Map.delete(b)

      {:ok,
       %{s | pts: pts, fs: fs, vf: vf, q: q, ver: ver, locked: locked, fixed: fixed, count: s.count - length(shared)}}
    end
  end

  defp sub(x, b, a), do: if(x == b, do: a, else: x)

  # Two faces on the same three points after the collapse (a tetrahedron
  # would become a flat shell of two faces).
  defp twins?(s, moved, a, b) do
    sets = for f <- moved, {x, y, z, _} = s.fs[f], do: Enum.sort([sub(x, b, a), sub(y, b, a), sub(z, b, a)])
    length(Enum.uniq(sets)) < length(sets)
  end

  # A face that goes: out of the lists of its other points.
  defp drop(vf, {x, y, z, _}, f, skip) do
    Enum.reduce([x, y, z] -- skip, vf, fn v, vf -> Map.update!(vf, v, &List.delete(&1, f)) end)
  end

  # A face of a or b turns over (or to no area) when its point goes to the place.
  defp flips?(s, f, a, b, place) do
    {x, y, z, _} = s.fs[f]
    old = Enum.map([x, y, z], &s.pts[&1])
    new = Enum.map([x, y, z], &if(&1 == a or &1 == b, do: place, else: s.pts[&1]))
    {n0, n1} = {normal(old), normal(new)}
    Vec.len(n1) < 1.0e-12 or Vec.dot(n0, n1) <= 0.2 * Vec.len(n0) * Vec.len(n1)
  end

  defp normal([p, q, r]), do: Vec.cross(Vec.sub(q, p), Vec.sub(r, p))

  # The quadric of the plane of a face: (n . x + d)^2, as its ten numbers.
  defp plane(pts, {a, b, c, _}), do: plane_of(normal([pts[a], pts[b], pts[c]]), pts[a], 1.0)

  # The quadric of the plane through a point with a normal, with a weight.
  defp plane_of(n, p, w) do
    len = Vec.len(n)

    if len < 1.0e-15 do
      zero()
    else
      {x, y, z} = Vec.scale(n, 1 / len)
      d = -Vec.dot({x, y, z}, p)
      {w * x * x, w * x * y, w * x * z, w * x * d, w * y * y, w * y * z, w * y * d, w * z * z, w * z * d, w * d * d}
    end
  end

  defp zero, do: {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}

  defp error({xx, xy, xz, xd, yy, yz, yd, zz, zd, dd}, {x, y, z}) do
    xx * x * x + 2 * xy * x * y + 2 * xz * x * z + 2 * xd * x + yy * y * y + 2 * yz * y * z + 2 * yd * y + zz * z * z +
      2 * zd * z + dd
  end

  # The points that the faces use, in a new order, and the faces on them.
  defp pack(s) do
    used = s.fs |> Map.values() |> Enum.flat_map(fn {a, b, c, _} -> [a, b, c] end) |> Enum.uniq() |> Enum.sort()
    ids = used |> Enum.with_index() |> Map.new()
    faces = s.fs |> Enum.sort() |> Enum.map(fn {_, {a, b, c, m}} -> {[ids[a], ids[b], ids[c]], m} end)
    %{points: Enum.map(used, &s.pts[&1]), faces: faces, ids: used, quadrics: Enum.map(used, &s.q[&1])}
  end

  @doc "The sum of two quadrics (`collapse/4`)."
  def add({a1, a2, a3, a4, a5, a6, a7, a8, a9, a10}, {b1, b2, b3, b4, b5, b6, b7, b8, b9, b10}),
    do: {a1 + b1, a2 + b2, a3 + b3, a4 + b4, a5 + b5, a6 + b6, a7 + b7, a8 + b8, a9 + b9, a10 + b10}
end
