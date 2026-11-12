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
  over, or when the two points have more than two neighbors in common
  (so each edge stays in two faces). A point at the border of two
  materials stays where it is, so the faces of each material still meet
  the faces of the next one. The collapses stop at the budget of faces.
  """

  alias World.Vec

  @doc """
  The mesh of `points` and triangles `faces` (each `{[a, b, c],
  material}`) with at most `budget` faces, or as few as it can:
  `{points, faces}` (the points that the faces use, in a new order).
  """
  def collapse(points, faces, budget) when length(faces) <= budget, do: {points, faces}

  def collapse(points, faces, budget) do
    pts = points |> Enum.with_index() |> Map.new(fn {p, i} -> {i, Vec.float(p)} end)
    fs = faces |> Enum.with_index() |> Map.new(fn {{[a, b, c], m}, i} -> {i, {a, b, c, m}} end)

    vfaces =
      Enum.reduce(fs, %{}, fn {f, {a, b, c, _}}, acc ->
        Enum.reduce([a, b, c], acc, &Map.update(&2, &1, [f], fn l -> [f | l] end))
      end)

    q = Map.new(pts, fn {v, _} -> {v, Enum.reduce(vfaces[v] || [], zero(), &add(&2, plane(pts, fs[&1])))} end)

    locked =
      for {v, list} <- vfaces,
          list |> Enum.map(&elem(fs[&1], 3)) |> Enum.uniq() |> length() > 1,
          into: MapSet.new(),
          do: v

    s = %{pts: pts, fs: fs, vf: vfaces, q: q, locked: locked, ver: %{}, count: map_size(fs)}
    heap = Enum.reduce(edges(s), :gb_sets.new(), fn {a, b}, h -> push(h, s, a, b) end)
    s = run(s, heap, budget)
    pack(s)
  end

  defp run(%{count: n} = s, _heap, budget) when n <= budget, do: s

  defp run(s, heap, budget) do
    if :gb_sets.is_empty(heap) do
      s
    else
      {{_cost, a, b, va, vb, place}, heap} = :gb_sets.take_smallest(heap)

      if Map.get(s.ver, a, 0) == va and Map.get(s.ver, b, 0) == vb and Map.has_key?(s.pts, a) and Map.has_key?(s.pts, b) do
        case merge(s, a, b, place) do
          {:ok, s} -> run(s, Enum.reduce(around(s, a), heap, &push(&2, s, a, &1)), budget)
          :no -> run(s, heap, budget)
        end
      else
        run(s, heap, budget)
      end
    end
  end

  # The edges of the faces, each once.
  defp edges(s) do
    for {_, {a, b, c, _}} <- s.fs, {x, y} <- [{a, b}, {b, c}, {c, a}], uniq: true, do: {min(x, y), max(x, y)}
  end

  # An edge into the heap, with its cost and its place; none between two
  # points that stay.
  defp push(heap, s, a, b) do
    {a, b} = {min(a, b), max(a, b)}
    {la, lb} = {MapSet.member?(s.locked, a), MapSet.member?(s.locked, b)}

    places =
      cond do
        la and lb -> []
        la -> [s.pts[a]]
        lb -> [s.pts[b]]
        true -> [s.pts[a], s.pts[b], Vec.scale(Vec.add(s.pts[a], s.pts[b]), 0.5)]
      end

    case places do
      [] ->
        heap

      _ ->
        qe = add(s.q[a], s.q[b])
        {cost, place} = places |> Enum.map(&{error(qe, &1), &1}) |> Enum.min_by(&elem(&1, 0))
        :gb_sets.add({cost, a, b, Map.get(s.ver, a, 0), Map.get(s.ver, b, 0), place}, heap)
    end
  end

  # The points that share a face with a point.
  defp around(s, v), do: for(f <- s.vf[v], {a, b, c, _} = s.fs[f], u <- [a, b, c], u != v, uniq: true, do: u)

  # The points a and b become one point (a) at the place: the faces of both
  # go there, and the faces between them go.
  defp merge(s, a, b, place) do
    common = MapSet.intersection(MapSet.new(around(s, a)), MapSet.new(around(s, b)))
    shared = for f <- s.vf[a], f in s.vf[b], do: f
    moved = Enum.uniq(s.vf[a] ++ s.vf[b]) -- shared

    if MapSet.size(common) != 2 or length(shared) != 2 or Enum.any?(moved, &flips?(s, &1, a, b, place)) do
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
      pts = s.pts |> Map.put(a, place) |> Map.delete(b)
      {:ok, %{s | pts: pts, fs: fs, vf: vf, q: q, ver: ver, locked: locked, count: s.count - length(shared)}}
    end
  end

  defp sub(x, b, a), do: if(x == b, do: a, else: x)

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
  defp plane(pts, {a, b, c, _}) do
    n = normal([pts[a], pts[b], pts[c]])
    len = Vec.len(n)

    if len < 1.0e-15 do
      zero()
    else
      {x, y, z} = Vec.scale(n, 1 / len)
      d = -Vec.dot({x, y, z}, pts[a])
      {x * x, x * y, x * z, x * d, y * y, y * z, y * d, z * z, z * d, d * d}
    end
  end

  defp zero, do: {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}

  defp add({a1, a2, a3, a4, a5, a6, a7, a8, a9, a10}, {b1, b2, b3, b4, b5, b6, b7, b8, b9, b10}),
    do: {a1 + b1, a2 + b2, a3 + b3, a4 + b4, a5 + b5, a6 + b6, a7 + b7, a8 + b8, a9 + b9, a10 + b10}

  defp error({xx, xy, xz, xd, yy, yz, yd, zz, zd, dd}, {x, y, z}) do
    xx * x * x + 2 * xy * x * y + 2 * xz * x * z + 2 * xd * x + yy * y * y + 2 * yz * y * z + 2 * yd * y + zz * z * z +
      2 * zd * z + dd
  end

  # The points that the faces use, in a new order, and the faces on them.
  defp pack(s) do
    used = s.fs |> Map.values() |> Enum.flat_map(fn {a, b, c, _} -> [a, b, c] end) |> Enum.uniq() |> Enum.sort()
    ids = used |> Enum.with_index() |> Map.new()
    faces = s.fs |> Enum.sort() |> Enum.map(fn {_, {a, b, c, m}} -> {[ids[a], ids[b], ids[c]], m} end)
    {Enum.map(used, &s.pts[&1]), faces}
  end
end
