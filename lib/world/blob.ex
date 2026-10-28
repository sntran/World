defmodule World.Blob do
  @moduledoc """
  A smooth skin around bones: one surface for a body of an animal, with
  no seams at the joints.

  Each bone has a round body: a cone with round ends, with its half
  sizes `{x, z}` at the head and at the tail, and a `group` (its own
  name by default). The bodies of a group join with no blend (a back of
  three bones has no bumps at its joints); the surface is where the
  smooth union of the groups is zero (a field of distances: below zero
  is inside). The smooth union makes a thigh grow out of the hips as a
  muscle does, with the width `blend`. The mesh comes from the field on
  a grid of `step` meters (surface nets: one point in each cell that the
  surface goes through, and a quad across each edge of the grid that it
  cuts). Each point follows the bones near it, more the nearer one.
  """
  alias World.{Frame, Vec}

  @doc """
  The points and the triangles of the skin of `bones` (each with its
  `frame` at rest, `head`, `tail`, `radius` and its index `index` in the
  skin). Gives `{points, triangles}`: each point is `{position, normal,
  {joints, weights}}`.
  """
  def mesh(bones, step, blend) do
    bodies = Enum.map(bones, &body(&1, blend))
    {lo, hi} = bounds(bodies, step)

    {nx, ny, nz} =
      Vec.sub(hi, lo) |> then(fn {x, y, z} -> {ceil(x / step) + 1, ceil(y / step) + 1, ceil(z / step) + 1} end)

    at = fn i, j, k -> Vec.add(lo, {i * step, j * step, k * step}) end
    field = &field(bodies, &1, blend)

    values = List.to_tuple(for i <- 0..(nx - 1), j <- 0..(ny - 1), k <- 0..(nz - 1), do: field.(at.(i, j, k)))
    value = fn i, j, k -> elem(values, (i * ny + j) * nz + k) end

    # One point in each cell that the surface goes through: the mean of
    # the points where it cuts the edges of the cell.
    cells =
      for i <- 0..(nx - 2), j <- 0..(ny - 2), k <- 0..(nz - 2), reduce: %{} do
        acc ->
          corners = for c <- 0..7, do: corner(c, i, j, k)
          vs = Enum.map(corners, fn {a, b, c} -> value.(a, b, c) end)

          if Enum.any?(vs, &(&1 < 0)) and Enum.any?(vs, &(&1 >= 0)) do
            cuts =
              for {c0, c1} <- edges(), v0 = Enum.at(vs, c0), v1 = Enum.at(vs, c1), v0 < 0 != v1 < 0 do
                {a0, b0, d0} = Enum.at(corners, c0)
                {a1, b1, d1} = Enum.at(corners, c1)
                Vec.lerp(at.(a0, b0, d0), at.(a1, b1, d1), v0 / (v0 - v1))
              end

            Map.put(acc, {i, j, k}, {map_size(acc), Vec.mean(cuts)})
          else
            acc
          end
      end

    # A quad across each edge of the grid that the surface cuts, from
    # the points of the four cells around the edge.
    quads =
      for {{i, j, k}, _} <- cells,
          axis <- 0..2,
          {{a0, b0, c0}, {a1, b1, c1}} = edge(axis, i, j, k),
          v0 = value.(a0, b0, c0),
          v1 = value.(a1, b1, c1),
          v0 < 0 != v1 < 0,
          around = around(axis, i, j, k),
          Enum.all?(around, &Map.has_key?(cells, &1)),
          do: Enum.map(around, &elem(cells[&1], 0))

    points = cells |> Map.values() |> Enum.sort() |> Enum.map(&elem(&1, 1))
    h = step / 2

    verts =
      for p <- points do
        grad =
          for {dx, dy, dz} <- [{1, 0, 0}, {0, 1, 0}, {0, 0, 1}],
              do: field.(Vec.add(p, {dx * h, dy * h, dz * h})) - field.(Vec.sub(p, {dx * h, dy * h, dz * h}))

        {p, Vec.norm(List.to_tuple(grad)), weights(bodies, p, blend)}
      end

    # Each triangle faces the outside: the side of the normals of its
    # points (the field grows to the outside).
    v = List.to_tuple(verts)
    at = fn i -> elem(elem(v, i), 0) end
    out = fn i -> elem(elem(v, i), 1) end

    tris =
      for [a, b, c, d] <- quads, [p, q, r] <- [[a, b, c], [a, c, d]] do
        n = Vec.cross(Vec.sub(at.(q), at.(p)), Vec.sub(at.(r), at.(p)))
        if Vec.dot(n, Vec.add(Vec.add(out.(p), out.(q)), out.(r))) >= 0, do: [p, q, r], else: [p, r, q]
      end

    {verts, tris}
  end

  @doc """
  The point of the surface on a ray from a point inside (`from`) in the
  direction `dir`: to put an eye or a button on the skin.
  """
  def surface(bones, from, dir, blend) do
    bodies = Enum.map(bones, &body(&1, blend))
    dir = Vec.norm(dir)
    at = fn d -> Vec.add(from, Vec.scale(dir, d)) end
    far = Enum.find(Enum.map(1..100, &(&1 * 0.005)), 0.5, &(field(bodies, at.(&1), blend) >= 0))

    Enum.reduce(1..20, {max(far - 0.005, 0.0), far}, fn _, {lo, hi} ->
      mid = (lo + hi) / 2
      if field(bodies, at.(mid), blend) < 0, do: {mid, hi}, else: {lo, mid}
    end)
    |> then(fn {lo, hi} -> at.((lo + hi) / 2) end)
  end

  # The body of a bone: its frame, its length, its sizes, and its box.
  defp body(b, blend) do
    {{xh, zh}, {xt, zt}} = b.radius
    reach = Enum.max([xh, zh, xt, zt]) + blend

    box =
      [b.head, b.tail]
      |> Enum.reduce({{1.0e9, 1.0e9, 1.0e9}, {-1.0e9, -1.0e9, -1.0e9}}, fn {x, y, z}, {{a, c, e}, {d, f, g}} ->
        {{min(a, x - reach), min(c, y - reach), min(e, z - reach)},
         {max(d, x + reach), max(f, y + reach), max(g, z + reach)}}
      end)

    %{
      to: Frame.invert(b.frame),
      len: Vec.len(Vec.sub(b.tail, b.head)),
      radius: b.radius,
      box: box,
      index: b.index,
      group: Map.get(b, :group, b.name)
    }
  end

  defp bounds(bodies, step) do
    {los, his} = bodies |> Enum.map(& &1.box) |> Enum.unzip()
    {lo, hi} = {Vec.bounds(los) |> elem(0), Vec.bounds(his) |> elem(1)}
    {Vec.sub(lo, {step, step, step}), Vec.add(hi, {step, step, step})}
  end

  # The distance (about) from a point to the body of a bone: below zero
  # inside.
  defp distance(%{to: to, len: len, radius: {{xh, zh}, {xt, zt}}}, p) do
    {x, y, z} = Frame.point(to, p)
    t = (y / len) |> max(0.0) |> min(1.0)
    {rx, rz} = {xh + (xt - xh) * t, zh + (zt - zh) * t}
    cap = if y < 0, do: min(xh, zh), else: min(xt, zt)
    dy = y - t * len
    q = :math.sqrt(x * x / (rx * rx) + z * z / (rz * rz) + dy * dy / (cap * cap))
    (q - 1) * min(rx, rz)
  end

  defp inside?(%{box: {{a, b, c}, {d, e, f}}}, {x, y, z}),
    do: x >= a and x <= d and y >= b and y <= e and z >= c and z <= f

  # The field at a point: the minimum in each group, and the smooth
  # minimum of the groups.
  defp field(bodies, p, blend) do
    bodies
    |> Enum.reduce(%{}, fn body, groups ->
      if inside?(body, p),
        do: Map.update(groups, body.group, distance(body, p), &min(&1, distance(body, p))),
        else: groups
    end)
    |> Map.values()
    |> Enum.reduce(1.0, &smin(&2, &1, blend))
  end

  # The smooth minimum of two distances (a polynomial of width k).
  defp smin(a, b, k) do
    h = max(k - abs(a - b), 0.0) / k
    min(a, b) - h * h * k * 0.25
  end

  # The bones that a point follows: the nearest, and the others less as
  # they are farther (at most four).
  defp weights(bodies, p, blend) do
    near = for body <- bodies, inside?(body, p), do: {body.index, distance(body, p)}
    {_, best} = Enum.min_by(near, &elem(&1, 1))

    ws =
      near
      |> Enum.map(fn {i, d} -> {i, max(0.0, 1 - (d - best) / (1.5 * blend)) ** 2} end)
      |> Enum.filter(&(elem(&1, 1) > 0))
      |> Enum.sort_by(&(-elem(&1, 1)))
      |> Enum.take(4)

    sum = ws |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    ws = Enum.map(ws, fn {i, w} -> {i, w / sum} end) ++ List.duplicate({0, 0.0}, 4 - length(ws))
    {List.to_tuple(Enum.map(ws, &elem(&1, 0))), List.to_tuple(Enum.map(ws, &elem(&1, 1)))}
  end

  # The 8 corners of a cell, and its 12 edges (pairs of corners).
  defp corner(c, i, j, k),
    do: {i + Bitwise.band(c, 1), j + Bitwise.band(Bitwise.bsr(c, 1), 1), k + Bitwise.band(Bitwise.bsr(c, 2), 1)}

  defp edges, do: for(a <- 0..7, b <- 0..7, a < b, Bitwise.bxor(a, b) in [1, 2, 4], do: {a, b})

  # The edge of the grid along an axis from the far corner of a cell (i,
  # j, k), and the four cells around it.
  defp edge(0, i, j, k), do: {{i, j + 1, k + 1}, {i + 1, j + 1, k + 1}}
  defp edge(1, i, j, k), do: {{i + 1, j, k + 1}, {i + 1, j + 1, k + 1}}
  defp edge(2, i, j, k), do: {{i + 1, j + 1, k}, {i + 1, j + 1, k + 1}}

  defp around(0, i, j, k), do: [{i, j, k}, {i, j + 1, k}, {i, j + 1, k + 1}, {i, j, k + 1}]
  defp around(1, i, j, k), do: [{i, j, k}, {i, j, k + 1}, {i + 1, j, k + 1}, {i + 1, j, k}]
  defp around(2, i, j, k), do: [{i, j, k}, {i + 1, j, k}, {i + 1, j + 1, k}, {i, j + 1, k}]
end
