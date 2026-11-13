defmodule World.Sculpt.Surface do
  @moduledoc """
  The surface of the bricks of a sculpture
  (`docs/plans/0008-model-from-edits.md`, D7): dual contouring in each
  brick, and one mesh from the pieces of the bricks.

  A quad goes across each edge of the grid that the surface cuts, from
  the points of the four cells round the edge. Each edge belongs to one
  brick: the brick of the point where it starts (each axis of the point
  from 0 to 7 in the brick). The cells round an edge at a face of a brick
  are in its border, and the next brick has the same field there (to the
  bit: `World.SDF.prune/3`), so the points of those cells are the same in
  each brick, and the pieces join with no gap.

  A cell has one point for each part of the surface in it: the inside
  corners of the cell that share an edge or a face of the cell are one
  part (not through the center of the cell). The rule of a face takes its
  four corners only, so the two cells of the face agree, and each edge of
  the mesh is in two faces (or, at a face of a cell whose inside
  corners are on its diagonal, in four: two sheets of the surface touch
  there; the mesh stays closed). The point of a part is at the least squared
  distance to the planes of the cuts of its edges (each plane through the
  cut, with the normal of the field there), with a little pull to the
  mean of the cuts, and stays in its cell: so a sharp edge of hard edits
  stays sharp.

  The material of a quad is the material of the field at the cut of its
  edge. The mesh has a `World.Mesh` for each material.
  """

  import Bitwise
  alias World.{Mesh, SDF, Sculpt, Vec}

  @edges [{0, 1}, {2, 3}, {4, 5}, {6, 7}, {0, 2}, {1, 3}, {4, 6}, {5, 7}, {0, 4}, {1, 5}, {2, 6}, {3, 7}]
  # The pull to the mean of the cuts, for each cut: small, so it moves a
  # point only along the ways that the planes do not hold (along a sharp
  # edge, in a flat face), not off a corner.
  @pull 1.0e-3
  # The bricks of a region of the collapse, on each axis.
  @region 4
  # The least faces of a region, on the mean, for a collapse by regions.
  @least 500
  # The weight of the pin of a point for the collapse, for a change of
  # the color from black to white at the point.
  @pin 9.0

  # A key of a point: its cell (18 bits for each axis, from -2^17) and its
  # part (3 bits), in one small integer.
  @bits 18
  @half 1 <<< (@bits - 1)
  @mask (1 <<< @bits) - 1

  @doc """
  The piece of the surface of a brick (`World.Sculpt.bricks/3`), as
  binaries that go from one process to another with no copy:
  `%{at: brick, points: binary, quads: binary, materials: list}` (and
  `colors`, three bytes for each point, when an edit has a color). Each
  point is its key (`key/2`, 64 bits) and its place (three floats of 64
  bits); each quad is the indices of its four points in the piece (in
  turn round its edge, the outside to the right hand; 32 bits each) and
  the index of its material in `materials` (8 bits). `decode/1` gives
  the quads and the points as terms.
  """
  def piece(%{at: {bi, bj, bk}, edits: edits, limit: limit} = brick, step) do
    n = Sculpt.cells()
    base = {bi * n, bj * n, bk * n}
    v = fn {i, j, k} -> Sculpt.at(brick, {i, j, k}) end

    crossed =
      for i <- 0..(n - 1),
          j <- 0..(n - 1),
          k <- 0..(n - 1),
          axis <- 0..2,
          start = {i, j, k},
          v0 = v.(start),
          v1 = v.(Vec.add(start, unit(axis))),
          v0 < 0 != v1 < 0,
          do: {start, axis, v0, v1}

    # The cells of the quads, and each edge of those cells that the
    # surface cuts: its cut and the normal there, found once.
    cells = for {start, axis, _, _} <- crossed, c <- around(axis, start), uniq: true, do: c
    cuts = cuts(cells, base, step, field(brick, edits, limit, step), v)

    quads =
      for {start, axis, v0, v1} <- crossed do
        inside = if v0 < 0, do: start, else: Vec.add(start, unit(axis))
        keys = for c <- around(axis, start), do: {Vec.add(base, c), part(c, inside, v)}
        {_cut, _normal, material} = cuts[{start, axis}]
        {if(v1 > v0, do: keys, else: Enum.reverse(keys)), material}
      end

    keys = quads |> Enum.flat_map(&elem(&1, 0)) |> Enum.uniq()
    index = keys |> Enum.with_index() |> Map.new()
    materials = quads |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    mindex = materials |> Enum.with_index() |> Map.new()

    places = for k <- keys, do: point(k, base, step, cuts, v)

    points =
      for {{cell, part}, {x, y, z}} <- Enum.zip(keys, places), into: <<>> do
        <<key(cell, part)::64, x::float-64, y::float-64, z::float-64>>
      end

    quads =
      for {ks, m} <- quads, into: <<>> do
        [a, b, c, d] = Enum.map(ks, &index[&1])
        <<a::32, b::32, c::32, d::32, mindex[m]::8>>
      end

    piece = %{at: {bi, bj, bk}, points: points, quads: quads, materials: materials}

    # With an edit that has a color, the color of each point too: the
    # collapse keeps the points where the colors change (`meshes/2`).
    if Enum.any?(edits, & &1.color) do
      color = color(brick, edits, limit, step)
      Map.put(piece, :colors, for(p <- places, {r, g, b} = color.(p), into: <<>>, do: <<round(r), round(g), round(b)>>))
    else
      piece
    end
  end

  @doc "The key of a point: its cell `{i, j, k}` and its part (0 to 7), in one integer."
  def key({i, j, k}, part) do
    for c <- [i, j, k],
        c + @half < 0 or c + @half > @mask,
        do: raise(ArgumentError, "a cell is too far from the origin")

    (i + @half) <<< (2 * @bits + 3) ||| (j + @half) <<< (@bits + 3) ||| (k + @half) <<< 3 ||| part
  end

  # The cell of a key.
  defp cell(key) do
    {(key >>> (2 * @bits + 3) &&& @mask) - @half, (key >>> (@bits + 3) &&& @mask) - @half,
     (key >>> 3 &&& @mask) - @half}
  end

  @doc """
  The quads and the points of a piece as terms: `%{quads: [{keys,
  material}], points: %{key => {x, y, z}}, colors: %{key => {r, g, b}}}`
  (no colors for a piece with none).
  """
  def decode(%{points: points, quads: quads, materials: materials} = piece) do
    keys = for <<k::64, _::binary-size(24) <- points>>, do: k
    t = List.to_tuple(keys)
    m = List.to_tuple(materials)

    %{
      colors: Map.new(Enum.zip(keys, for(<<r::8, g::8, b::8 <- Map.get(piece, :colors, <<>>)>>, do: {r, g, b}))),
      points: Map.new(for(<<k::64, x::float-64, y::float-64, z::float-64 <- points>>, do: {k, {x, y, z}})),
      quads:
        for(<<a::32, b::32, c::32, d::32, i::8 <- quads>>,
          do: {[elem(t, a), elem(t, b), elem(t, c), elem(t, d)], elem(m, i)}
        )
    }
  end

  @doc """
  The meshes of the pieces of a sculpture: one `World.Mesh` for each
  material, with its quads in two triangles. With the option `small`
  (m), no piece of the surface less than `small` across (a part thinner
  than the cells leaves such pieces); with the option `budget` (faces),
  fewer faces for all the materials together, with their shape
  (`World.Simplify.collapse/4`): first each region of 4 × 4 × 4 bricks
  in a process of its own; then, with the option `step` (the cells, m),
  each region of a second set, moved by half a region, in a process of
  its own (the borders of the first regions are in the middle of these);
  then the band of faces at the borders that are left.
  """
  def meshes(pieces, opts \\ []) do
    budget = opts[:budget]
    groups = Enum.group_by(pieces, &region(&1.at))
    faces = fn ps -> ps |> Enum.map(&div(byte_size(&1.quads), 17)) |> Enum.sum() |> Kernel.*(2) end
    total = faces.(pieces)
    # The pins of the colors count less when the budget keeps few of the
    # faces: a budget that takes most of the faces away cannot keep a
    # pattern of colors, and must keep the shape.
    pin = if budget, do: @pin * min(budget / max(total, 1), 1.0) ** 2, else: 0.0

    {pts, tris} =
      if budget && total > budget && map_size(groups) > 1 && total / map_size(groups) >= @least do
        groups
        |> Enum.sort()
        |> Task.async_stream(
          fn {r, ps} ->
            {r,
             region_collapse(
               r,
               ps,
               max(round(1.1 * budget * faces.(ps) / total), div(faces.(ps), 4)),
               pin,
               free(opts[:step])
             )}
          end,
          # (Two tasks for each scheduler: a task waits at times, for memory or for the collector.)
          max_concurrency: 2 * System.schedulers_online(),
          # (In any order: a region with much work does not keep the others back.)
          ordered: false,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, part} -> part end)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(&elem(&1, 1))
        |> join()
        |> between(budget, opts[:step])
        |> last_pass(budget)
      else
        {_keys, pts, tris, pins} = triangles(pieces, pin)

        if budget && length(tris) > budget do
          %{points: pts, faces: tris} = World.Simplify.collapse(pts, tris, budget, pins: pins)
          {pts, tris}
        else
          {pts, tris}
        end
      end

    tris = if opts[:small], do: drop_small(List.to_tuple(pts), tris, opts[:small]), else: tris
    all = List.to_tuple(pts)

    tris
    |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    |> Enum.sort_by(fn {material, _} -> inspect(material) end)
    |> Enum.map(fn {material, faces} ->
      used = faces |> Enum.concat() |> Enum.uniq()
      local = used |> Enum.with_index() |> Map.new()
      Mesh.new(Enum.map(used, &elem(all, &1)), Enum.map(faces, fn f -> Enum.map(f, &local[&1]) end), material || :paint)
    end)
  end

  # The triangles of some pieces, on their points (one point for each key):
  # `{keys, points, triangles, pins}`.
  defp triangles(pieces, pin) do
    decoded = Enum.map(pieces, &decode/1)
    points = Enum.reduce(decoded, %{}, &Map.merge(&2, &1.points))
    colors = Enum.reduce(decoded, %{}, &Map.merge(&2, &1.colors))
    quads = Enum.flat_map(decoded, & &1.quads)
    keys = quads |> Enum.flat_map(&elem(&1, 0)) |> Enum.uniq()
    ids = keys |> Enum.with_index() |> Map.new()
    tris = for {q, m} <- quads, [a, b, c, d] = Enum.map(q, &ids[&1]), f <- [[a, b, c], [a, c, d]], do: {f, m}
    {keys, Enum.map(keys, &points[&1]), tris, pins(keys, colors, tris, pin)}
  end

  # The pin of each point for the collapse (`World.Simplify.collapse/4`):
  # the square of the most change of the color from the point to a point
  # next to it (each color from 0 to 1), times the weight `pin`. A point
  # where the colors change stays near its place, so the collapse keeps
  # the border of two colors, and takes the points where the color is even.
  defp pins(_keys, colors, _tris, pin) when colors == %{} or pin == 0.0, do: nil

  defp pins(keys, colors, tris, pin) do
    c = keys |> Enum.map(&Map.get(colors, &1, {255, 255, 255})) |> List.to_tuple()

    change =
      for {[a, b, d], _} <- tris, {u, v} <- [{a, b}, {b, d}, {d, a}], reduce: %{} do
        acc ->
          {{r0, g0, b0}, {r1, g1, b1}} = {elem(c, u), elem(c, v)}
          square = ((r0 - r1) ** 2 + (g0 - g1) ** 2 + (b0 - b1) ** 2) / (255 * 255)
          acc |> Map.update(u, square, &max(&1, square)) |> Map.update(v, square, &max(&1, square))
      end

    for i <- 0..(tuple_size(c) - 1)//1, do: pin * Map.get(change, i, 0.0)
  end

  # Fewer faces, in three rounds. The first round: each region of bricks
  # (4 on each axis) in a process of its own, with its own pieces, to 1.1
  # times its share of the budget or to a quarter of its faces (the more
  # of the two: the points at its borders, which the next regions share,
  # stay where they are, and must not take its budget). The second round
  # (`between/3`): the points that the regions held, in many processes.
  # The last pass: the band of faces near the points that are held
  # still, to the budget, with the quadrics of the rounds before. With
  # fewer than 500 faces for each region, one pass. A region gives back
  # only its fewer faces, and the last pass has only the band, so no
  # process has the whole mesh in a collapse.
  defp region_collapse(r, pieces, budget, pin, free) do
    {keys, pts, tris, pins} = triangles(pieces, pin)
    {lo, hi} = cells(r)
    fixed = for {k, i} <- Enum.with_index(keys), border?(cell(k), lo, hi), do: i
    # (Past its budget, a region does each collapse that costs almost
    # nothing: a flat part needs few faces. And it does no collapse that
    # moves the surface by more than half a cell, also when it has more
    # faces than its budget then: a region with few points that can
    # move must not break a small part. The rounds after this one choose
    # over all the regions.)
    r =
      World.Simplify.collapse(
        pts,
        tris,
        budget,
        [fixed: fixed, pins: pins] ++ if(free, do: [free: free, limit: 625 * free], else: [])
      )

    global = List.to_tuple(keys)
    held = MapSet.new(fixed)
    ids = Enum.map(r.ids, &elem(global, &1))
    {r.points, r.faces, ids, r.quadrics, for({i, k} <- Enum.zip(r.ids, ids), i in held, do: k)}
  end

  # A cell at a border of its region, or out of it: the next region can
  # have its point too.
  defp border?({i, j, k}, {li, lj, lk}, {hi, hj, hk}),
    do: i <= li or j <= lj or k <= lk or i >= hi or j >= hj or k >= hk

  # The regions together: a shared point (the same key) is one point,
  # with the sum of its quadrics in each region. Also the indices of the
  # points that the regions held (the points at their borders).
  defp join(parts) do
    {index, points, quadrics} =
      for {pts, _, ids, qs, _} <- parts, {p, g, q} <- Enum.zip([pts, ids, qs]), reduce: {%{}, [], %{}} do
        {index, points, quadrics} ->
          if Map.has_key?(index, g),
            do: {index, points, Map.update!(quadrics, g, &World.Simplify.add(&1, q))},
            else: {Map.put(index, g, map_size(index)), [p | points], Map.put(quadrics, g, q)}
      end

    faces =
      for {_, fs, ids, _, _} <- parts,
          ids = List.to_tuple(ids),
          {f, m} <- fs,
          do: {Enum.map(f, &index[elem(ids, &1)]), m}

    order = index |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&quadrics[elem(&1, 0)])
    held = for {_, _, _, _, keys} <- parts, k <- keys, into: MapSet.new(), do: index[k]
    {Enum.reverse(points), faces, order, held}
  end

  # The second round: the points at the borders of the regions of the
  # first round (the points that those regions held: most of the points
  # that are left), in many processes. A process gets the points and the
  # faces of its group only (a message is a copy).
  #
  # - First the collapses that cost almost nothing (each moves the
  #   surface by less than a fiftieth of a cell), in groups of the held
  #   points: a flat part keeps no point of a border. The groups are the
  #   held points in each region moved by half a region, then (for the
  #   points at the borders of those groups) by a quarter.
  # - Then, when the budget is not met: each region (moved by half a
  #   region, by the centers of its faces) gives the cost of each of its
  #   collapses in their turn; the collapses with the least costs over
  #   all the regions are done, to the budget; and each region does its
  #   own. So the budget goes to the regions by the cost of their
  #   collapses, not by their faces, and a region with a small part (a
  #   chimney on a roof) keeps the faces of that part. No collapse there
  #   moves the surface by more than half a cell: the last pass has the
  #   whole mesh, and finds the collapses that a region cannot do.
  defp between(mesh, _budget, nil), do: mesh

  defp between(mesh, budget, step) do
    free = mesh |> borders(step, 0.5) |> borders(step, 0.25)
    total = length(elem(free, 1))

    if total <= budget do
      free
    else
      limit = [limit: 625 * free(step)]

      # The costs of the collapses of each region, each cost not less than the costs before it.
      {_, costs} =
        regions(free, step, 0.5, fn faces, _ ->
          {max(round(budget * faces / total / 2), 1), [costs: true] ++ limit}
        end)

      # The faces of each region after the collapses with the least costs
      # over all the regions, to the budget.
      {targets, _} =
        for({g, {faces, list}} <- costs, {cost, left} <- running(list), do: {cost, g, -left, faces})
        |> Enum.sort()
        |> Enum.reduce_while({%{}, total}, fn {_, g, left, faces}, {targets, count} ->
          if count <= budget,
            do: {:halt, {targets, count}},
            else: {:cont, {Map.put(targets, g, -left), count - (Map.get(targets, g, faces) + left)}}
        end)

      {mesh, _} = regions(free, step, 0.5, fn faces, g -> {Map.get(targets, g, faces), limit} end)
      mesh
    end
  end

  # The cost of a collapse that moves the surface by a fiftieth of a
  # cell: a collapse with less is free (nil with no cells). A flat part
  # has such collapses; a round part keeps its faces for its budget.
  defp free(nil), do: nil
  defp free(step), do: 4.0e-4 * step * step

  # The costs of some collapses in their turn, each not less than the costs before it.
  defp running(costs) do
    costs |> Enum.map_reduce(0.0, fn {cost, left}, most -> {{max(cost, most), left}, max(cost, most)} end) |> elem(0)
  end

  # The size of a region (m), for cells of `step`.
  defp size(step), do: Sculpt.cells() * @region * step

  # The free collapses of the held points of a mesh (the points at the
  # borders of the first regions), each group in a process of its own.
  # After the first round a flat part has faces as large as a region, so
  # a group cannot be the faces of a place: it is the held points of a
  # place (a region moved by the part `shift` of a region), with the
  # faces round them. The other points of those faces stay: the points
  # in the middle of the first regions (two groups can have such a point,
  # and each gives the planes of the points that went to it), and the
  # held points next to a held point of a different group (a group with
  # a different `shift` moves them).
  defp borders({pts, tris, quadrics, held}, step, shift) do
    {all, qs} = {List.to_tuple(pts), List.to_tuple(quadrics)}

    group = fn v ->
      {x, y, z} = elem(all, v)
      {floor(x / size(step) + shift), floor(y / size(step) + shift), floor(z / size(step) + shift)}
    end

    of = Map.new(held, &{&1, group.(&1)})

    # A held point next to a held point of a different group stays.
    stay =
      for {f, _} <- tris,
          [a, b] <- pairs(f),
          is_map_key(of, a) and is_map_key(of, b) and of[a] != of[b],
          v <- [a, b],
          into: MapSet.new(),
          do: v

    of = Map.drop(of, MapSet.to_list(stay))
    # The faces of each group (the faces of its points that can move), and the other faces.
    {groups, rest} =
      Enum.reduce(tris, {%{}, []}, fn {f, _} = face, {groups, rest} ->
        case Enum.find(f, &is_map_key(of, &1)) do
          nil -> {groups, [face | rest]}
          v -> {Map.update(groups, of[v], [face], &[face | &1]), rest}
        end
      end)

    done =
      groups
      |> Enum.sort()
      |> Enum.map(fn {g, faces} ->
        faces = Enum.reverse(faces)
        used = faces |> Enum.flat_map(&elem(&1, 0)) |> Enum.uniq()
        local = used |> Enum.with_index() |> Map.new()

        {{g, used}, Enum.map(used, &elem(all, &1)), Enum.map(faces, fn {f, m} -> {Enum.map(f, &local[&1]), m} end),
         [
           limit: free(step),
           fixed: for(v <- used, not is_map_key(of, v), do: local[v]),
           quadrics: Enum.map(used, &elem(qs, &1))
         ]}
      end)
      |> Task.async_stream(
        fn {key, points, faces, opts} -> {key, World.Simplify.collapse(points, faces, 1, opts)} end,
        # (Two tasks for each scheduler: a task waits at times, for memory or for the collector.)
        max_concurrency: 2 * System.schedulers_online(),
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, part} -> part end)
      |> Enum.sort_by(&elem(&1, 0))

    # A point of a group that stays in the mesh has its new place and its
    # new quadric. A point that the group held has its place, and the
    # planes that it got in each group.
    {moved, more, faces} =
      Enum.reduce(done, {%{}, %{}, []}, fn {{_, used}, r}, {moved, more, faces} ->
        used = List.to_tuple(used)
        global = Enum.map(r.ids, &elem(used, &1))
        g = List.to_tuple(global)

        {moved, more} =
          for {v, p, q} <- Enum.zip([global, r.points, r.quadrics]), reduce: {moved, more} do
            {moved, more} ->
              if is_map_key(of, v),
                do: {Map.put(moved, v, {p, q}), more},
                else: {moved, Map.update(more, v, less(q, elem(qs, v)), &World.Simplify.add(&1, less(q, elem(qs, v))))}
          end

        {moved, more, [Enum.map(r.faces, fn {f, m} -> {Enum.map(f, &elem(g, &1)), m} end) | faces]}
      end)

    {pts, quadrics} =
      Enum.zip(pts, quadrics)
      |> Enum.with_index()
      |> Enum.map(fn {{p, q}, i} ->
        case moved do
          %{^i => new} -> new
          _ -> {p, if(is_map_key(more, i), do: World.Simplify.add(q, more[i]), else: q)}
        end
      end)
      |> Enum.unzip()

    faces = Enum.reverse(rest) ++ (faces |> Enum.reverse() |> Enum.concat())
    left = for {f, _} <- faces, v <- f, MapSet.member?(held, v), into: MapSet.new(), do: v
    {pts, faces, quadrics, left}
  end

  defp pairs([a, b, c]), do: [[a, b], [b, c], [c, a]]

  # A quadric less a quadric: the planes that a point got.
  defp less(a, b), do: List.to_tuple(Enum.zip_with(Tuple.to_list(a), Tuple.to_list(b), &(&1 - &2)))

  # A collapse of each region of a mesh in a process of its own: the
  # regions are moved by the part `shift` of a region, and a face is in
  # the region of its center. A point of the faces of two regions stays.
  # `plan` gives, for the faces of a region and the region, the budget
  # and the options of its collapse (`World.Simplify.collapse/4`). Gives
  # the mesh after the collapses, and (for the option `costs`) the faces
  # and the costs of each region.
  defp regions({pts, tris, quadrics, held}, step, shift, plan) do
    size = size(step)
    {all, qs} = {List.to_tuple(pts), List.to_tuple(quadrics)}

    region = fn [a, b, c] ->
      {x, y, z} = Vec.add(Vec.add(elem(all, a), elem(all, b)), elem(all, c))
      {floor(x / 3 / size + shift), floor(y / 3 / size + shift), floor(z / 3 / size + shift)}
    end

    groups = Enum.group_by(tris, fn {f, _} -> region.(f) end)

    # The region of each point, or `:many` for a point of two regions.
    of =
      for {g, faces} <- groups, {f, _} <- faces, v <- f, reduce: %{} do
        acc ->
          Map.update(acc, v, g, fn
            ^g -> g
            _ -> :many
          end)
      end

    done =
      groups
      |> Enum.sort()
      |> Enum.map(fn {g, faces} ->
        used = faces |> Enum.flat_map(&elem(&1, 0)) |> Enum.uniq()
        local = used |> Enum.with_index() |> Map.new()
        {budget, opts} = plan.(length(faces), g)

        {{g, used, length(faces)}, Enum.map(used, &elem(all, &1)),
         Enum.map(faces, fn {f, m} -> {Enum.map(f, &local[&1]), m} end), budget,
         opts ++ [fixed: for(v <- used, of[v] == :many, do: local[v]), quadrics: Enum.map(used, &elem(qs, &1))]}
      end)
      |> Task.async_stream(
        fn {key, points, faces, budget, opts} -> {key, World.Simplify.collapse(points, faces, budget, opts)} end,
        # (Two tasks for each scheduler: a task waits at times, for memory or for the collector.)
        max_concurrency: 2 * System.schedulers_online(),
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, part} -> part end)
      |> Enum.sort_by(&elem(&1, 0))

    case done do
      [{_, costs} | _] when is_list(costs) ->
        {nil, for({{g, _, faces}, costs} <- done, do: {g, {faces, costs}})}

      _ ->
        # The points of a region that stay keep their index; a point that
        # moved has its new place and its new quadric. (A point of two
        # regions did not move; it keeps its quadric of before.)
        {moved, faces} =
          Enum.reduce(done, {%{}, []}, fn {{_, used, _}, r}, {moved, faces} ->
            used = List.to_tuple(used)
            global = Enum.map(r.ids, &elem(used, &1))
            g = List.to_tuple(global)

            {for({v, p, q} <- Enum.zip([global, r.points, r.quadrics]), of[v] != :many, into: moved, do: {v, {p, q}}),
             [Enum.map(r.faces, fn {f, m} -> {Enum.map(f, &elem(g, &1)), m} end) | faces]}
          end)

        {pts, quadrics} =
          Enum.zip(pts, quadrics)
          |> Enum.with_index()
          |> Enum.map(fn {old, i} -> Map.get(moved, i, old) end)
          |> Enum.unzip()

        faces = faces |> Enum.reverse() |> Enum.concat()
        # The points for the band of the last pass: the held points that are left, and the points of two regions.
        left = for {f, _} <- faces, v <- f, MapSet.member?(held, v) or of[v] == :many, into: MapSet.new(), do: v
        {{pts, faces, quadrics, left}, nil}
    end
  end

  # The last pass: only the faces near the borders of the regions (two
  # rings of faces round the points that the rounds before held), with the points that they
  # share with the other faces where they are; the other faces are done.
  # When the band cannot reach the budget, the whole mesh.
  defp last_pass({pts, tris, _quadrics, _held}, budget) when length(tris) <= budget, do: {pts, tris}

  defp last_pass({pts, tris, quadrics, held}, budget) do
    ring = fn set -> for {f, _} <- tris, Enum.any?(f, &MapSet.member?(set, &1)), v <- f, into: MapSet.new(), do: v end
    near = ring.(held)
    {band, rest} = Enum.split_with(tris, fn {f, _} -> Enum.any?(f, &MapSet.member?(near, &1)) end)
    target = length(band) - (length(tris) - budget)
    outside = for {f, _} <- rest, v <- f, into: MapSet.new(), do: v

    with true <- target > 0,
         {used, r} = band_collapse(pts, quadrics, band, outside, target),
         true <- length(r.faces) <= target do
      join_band(pts, rest, used, r)
    else
      _ ->
        %{points: pts, faces: tris} = World.Simplify.collapse(pts, tris, budget, quadrics: quadrics)
        {pts, tris}
    end
  end

  # The band on its own points: the points that the other faces use stay.
  defp band_collapse(pts, quadrics, band, outside, target) do
    used = band |> Enum.flat_map(&elem(&1, 0)) |> Enum.uniq()
    local = used |> Enum.with_index() |> Map.new()
    {all, qs} = {List.to_tuple(pts), List.to_tuple(quadrics)}
    fixed = for v <- used, MapSet.member?(outside, v), do: local[v]
    faces = Enum.map(band, fn {f, m} -> {Enum.map(f, &local[&1]), m} end)

    {used,
     World.Simplify.collapse(Enum.map(used, &elem(all, &1)), faces, target,
       fixed: fixed,
       quadrics: Enum.map(used, &elem(qs, &1))
     )}
  end

  # The faces of the band after its collapse, with the other faces: the
  # points of the band that stay keep their index, and its moved points
  # take their new places.
  defp join_band(pts, rest, used, r) do
    used = List.to_tuple(used)
    global = Enum.map(r.ids, &elem(used, &1))
    moved = Map.new(Enum.zip(global, r.points))
    pts = pts |> Enum.with_index() |> Enum.map(fn {p, i} -> Map.get(moved, i, p) end)
    g = List.to_tuple(global)
    {pts, rest ++ Enum.map(r.faces, fn {f, m} -> {Enum.map(f, &elem(g, &1)), m} end)}
  end

  # The region of a brick, and the first and the last cells of a region.
  defp region({i, j, k}),
    do: {Integer.floor_div(i, @region), Integer.floor_div(j, @region), Integer.floor_div(k, @region)}

  defp cells({i, j, k}) do
    n = Sculpt.cells() * @region
    {{i * n, j * n, k * n}, {(i + 1) * n - 1, (j + 1) * n - 1, (k + 1) * n - 1}}
  end

  # The field of the edits of a brick at a point, as two functions: its
  # value (the hot loop, `World.SDF.fast/1`) and its material. With the
  # short list of the eighth of the brick that the point is in (the same
  # values).
  defp field(%{eighths: eighths, at: at}, _edits, limit, step) do
    corner = Sculpt.corner(at, step)
    fast = eighths |> Tuple.to_list() |> Enum.map(&SDF.fast/1) |> List.to_tuple()
    part = fn p -> Sculpt.eighth(Vec.scale(Vec.sub(p, corner), 1 / step)) end

    {fn p -> SDF.value(elem(fast, part.(p)), p, limit) end,
     fn p -> elem(SDF.field(elem(eighths, part.(p)), p, limit), 1) end}
  end

  defp field(_brick, edits, limit, _step) do
    fast = SDF.fast(edits)
    {&SDF.value(fast, &1, limit), &elem(SDF.field(edits, &1, limit), 1)}
  end

  # The color of the edits of a brick at a point, in the same way.
  defp color(%{eighths: eighths, at: at}, _edits, limit, step) do
    corner = Sculpt.corner(at, step)

    fn p -> SDF.color(elem(eighths, Sculpt.eighth(Vec.scale(Vec.sub(p, corner), 1 / step))), p, limit) end
  end

  defp color(_brick, edits, limit, _step), do: &SDF.color(edits, &1, limit)

  # The faces of each piece of the surface (faces joined by their points)
  # whose box is at least `small` m across: a smaller piece is the noise of
  # a part thinner than the cells.
  defp drop_small(pts, tris, small) do
    near =
      Enum.reduce(tris, %{}, fn {[a, b, c], _}, acc -> acc |> link(a, [b, c]) |> link(b, [a, c]) |> link(c, [a, b]) end)

    {keep, _} =
      Enum.reduce(Map.keys(near), {MapSet.new(), MapSet.new()}, fn v, {keep, seen} ->
        if MapSet.member?(seen, v) do
          {keep, seen}
        else
          piece = flood(near, [v], MapSet.new([v]))
          {{x0, y0, z0}, {x1, y1, z1}} = piece |> Enum.map(&elem(pts, &1)) |> Vec.bounds()
          big = Vec.len({x1 - x0, y1 - y0, z1 - z0}) >= small
          {if(big, do: MapSet.union(keep, piece), else: keep), MapSet.union(seen, piece)}
        end
      end)

    Enum.filter(tris, fn {[a, _, _], _} -> MapSet.member?(keep, a) end)
  end

  defp link(acc, v, us), do: Map.update(acc, v, us, &(us ++ &1))

  defp flood(_near, [], seen), do: seen

  defp flood(near, [v | rest], seen) do
    next = for u <- near[v], not MapSet.member?(seen, u), uniq: true, do: u
    flood(near, next ++ rest, Enum.reduce(next, seen, &MapSet.put(&2, &1)))
  end

  # The part of the surface of a cell that the inside corner `inside` is
  # in: its least corner.
  defp part(cell, inside, v) do
    solid = for c <- 0..7, v.(Vec.add(cell, corner(c))) < 0, do: c
    corner = index(Vec.sub(inside, cell))
    Enum.min(component(solid, [corner], [corner]))
  end

  # The inside corners joined to some corners: by an edge or a face of the
  # cell (one bit or two bits apart), not by its center.
  defp component(_solid, [], seen), do: seen

  defp component(solid, [c | rest], seen) do
    next = for d <- solid, d not in seen, popcount(bxor(c, d)) in [1, 2], do: d
    component(solid, rest ++ next, seen ++ next)
  end

  defp popcount(x), do: band(x, 1) + band(bsr(x, 1), 1) + band(bsr(x, 2), 1)

  # The point of a part of a cell: dual contouring of the cuts of its
  # edges, kept in the cell.
  defp point({global, part}, base, step, cuts, v) do
    cell = Vec.sub(global, base)
    solid = for c <- 0..7, v.(Vec.add(cell, corner(c))) < 0, do: c
    mine = component(solid, [part], [part])

    {points, normals} =
      for {c0, c1} <- @edges,
          p0 = Vec.add(cell, corner(c0)),
          v0 = v.(p0),
          v1 = v.(Vec.add(cell, corner(c1))),
          v0 < 0 != v1 < 0,
          if(v0 < 0, do: c0, else: c1) in mine do
        {cut, normal, _} = cuts[{p0, axis(c0, c1)}]
        {cut, normal}
      end
      |> Enum.unzip()

    lo = place(base, cell, step)
    clamp(qef(points, normals, Vec.mean(points)), lo, Vec.add(lo, {step, step, step}))
  end

  # Each edge of the cells that the surface cuts (`{start, axis}`): its
  # cut, the normal of the field there, and the material there.
  defp cuts(cells, base, step, field, v) do
    for cell <- cells,
        {c0, c1} <- @edges,
        p0 = Vec.add(cell, corner(c0)),
        p1 = Vec.add(cell, corner(c1)),
        v0 = v.(p0),
        v1 = v.(p1),
        v0 < 0 != v1 < 0,
        uniq: true do
      {p0, p1, v0, v1}
    end
    |> Map.new(fn {p0, p1, v0, v1} ->
      {cut, value, material} = cut(place(base, p0, step), place(base, p1, step), v0, v1, field, step)
      {{p0, axis(p0, p1)}, {cut, gradient(field, cut, value, step), material}}
    end)
  end

  defp axis({x, _, _}, {x1, _, _}) when x != x1, do: 0
  defp axis({_, y, _}, {_, y1, _}) when y != y1, do: 1
  defp axis({_, _, _}, {_, _, _}), do: 2
  defp axis(c0, c1) when is_integer(c0), do: axis(corner(c0), corner(c1))

  # The cut of an edge of the grid: where the field of the edits is 0 on
  # it, from the values at its ends (regula falsi, the Illinois way, in 8
  # steps or fewer, to a thousandth of a cell: the finish pass puts the
  # points of the mesh on the surface): near a sharp edge the field is not a line along an edge of
  # the grid, so a line between the two values is not the cut.
  defp cut(p0, p1, v0, v1, field, step), do: falsi(p0, p1, field, {0.0, v0}, {1.0, v1}, 8, nil, step * 1.0e-3)

  # The cut, the value of the field there (near 0) and its material: the
  # last point of the search.
  defp falsi(p0, p1, {value, material} = field, {a, fa}, {b, fb}, n, side, tol) do
    t = a - fa * (b - a) / (fb - fa)
    p = Vec.lerp(p0, p1, t)
    ft = value.(p)

    cond do
      abs(ft) <= tol or n == 1 -> {p, ft, material.(p)}
      ft < 0 == fa < 0 -> falsi(p0, p1, field, {t, ft}, {b, if(side == :a, do: fb / 2, else: fb)}, n - 1, :a, tol)
      true -> falsi(p0, p1, field, {a, if(side == :b, do: fa / 2, else: fa)}, {t, ft}, n - 1, :b, tol)
    end
  end

  # The least squares of the planes of the cuts, with a pull to the mean:
  # (sum n n^T + w I) x = sum n (n . p) + w m.
  defp qef(cuts, normals, mean) do
    w = @pull * length(cuts)

    {a, b} =
      Enum.zip(cuts, normals)
      |> Enum.reduce({{w, 0.0, 0.0, w, 0.0, w}, Vec.scale(mean, w)}, fn {p, {x, y, z} = n},
                                                                        {{xx, xy, xz, yy, yz, zz}, b} ->
        d = Vec.dot(n, p)
        {{xx + x * x, xy + x * y, xz + x * z, yy + y * y, yz + y * z, zz + z * z}, Vec.add(b, Vec.scale(n, d))}
      end)

    solve(a, b)
  end

  # The solution of a symmetric 3 × 3 system (with the pull, it has one).
  defp solve({a, b, c, d, e, f}, {p, q, r}) do
    det = a * (d * f - e * e) - b * (b * f - c * e) + c * (b * e - c * d)

    {(p * (d * f - e * e) - b * (q * f - e * r) + c * (q * e - d * r)) / det,
     (a * (q * f - e * r) - p * (b * f - c * e) + c * (b * r - q * c)) / det,
     (a * (d * r - q * e) - b * (b * r - q * c) + p * (b * e - c * d)) / det}
  end

  defp clamp({x, y, z}, {a, b, c}, {d, e, f}), do: {min(max(x, a), d), min(max(y, b), e), min(max(z, c), f)}

  # The normal of the field at a cut, from the value of the field there
  # and at three points next to it (the finish pass gives the normals of
  # the mesh: this one places the point of a cell).
  defp gradient({f, _material}, {x, y, z}, value, step) do
    h = step * 1.0e-3
    Vec.norm({f.({x + h, y, z}) - value, f.({x, y + h, z}) - value, f.({x, y, z + h}) - value})
  end

  defp place(base, p, step), do: Vec.scale(Vec.add(base, p), step) |> Vec.float()
  defp corner(c), do: {band(c, 1), band(bsr(c, 1), 1), bsr(c, 2)}
  defp index({x, y, z}), do: x + 2 * y + 4 * z

  defp unit(0), do: {1, 0, 0}
  defp unit(1), do: {0, 1, 0}
  defp unit(2), do: {0, 0, 1}

  # The four cells round the edge from the point {a, b, c} along an axis,
  # in turn about the axis (the right hand).
  defp around(0, {a, b, c}), do: [{a, b - 1, c - 1}, {a, b, c - 1}, {a, b, c}, {a, b - 1, c}]
  defp around(1, {a, b, c}), do: [{a - 1, b, c - 1}, {a - 1, b, c}, {a, b, c}, {a, b, c - 1}]
  defp around(2, {a, b, c}), do: [{a - 1, b - 1, c}, {a, b - 1, c}, {a, b, c}, {a - 1, b, c}]
end
