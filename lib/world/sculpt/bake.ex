defmodule World.Sculpt.Bake do
  @moduledoc """
  The maps of a sculpture (`docs/plans/0010-sculpture-maps.md`, D1 to
  D4): a color map and a normal map for its meshes, made from the field
  of its edits at each texel. So the detail of the model is the detail
  of the edits at the size of a texel, not at the size of a cell or of a
  triangle.

  **The charts.** A chart is a patch of triangles of the mesh: a first
  triangle, and the triangles round it that are joined to it by edges
  (with less than 35 degrees between two faces at an edge) and that
  face less than 25 degrees from the first one. The patch is seen flat
  from the direction of its first triangle: a texel is as large on the
  surface along each direction, to a tenth, for each triangle of the
  image (the scale of the image), a long thin one too. So a chart is
  one piece of the surface with nothing cut at an edge inside it. A
  patch has 64 triangles at the most. A chart has the rectangle of its
  patch (turned to the least area) with a border of two texels. The
  rectangles go into the image in rows, the highest first, and the
  scale is the largest one that fits.

  **A texel** is a place on the plane of its triangle. Its color is the
  color of the edits there (`World.SDF.sample/3`). Its normal is the
  gradient of the field there: the change of the value to the next
  texels of the chart gives the part in the plane, and one value off the
  plane gives the rest. The edits of a triangle are the edits that reach
  its ball (`World.SDF.prune/4`), so a texel takes two values of a short
  list. A texel of the border (past an edge of its triangle) has the
  values at the nearest place of the edge. An app with antialiasing
  reads the maps as far as a pixel past the edge of a triangle: with
  the border of two texels it reads the same surface there, when a
  pixel is not more than two texels. (That is why a texel has one size
  on the surface for each triangle: a pixel past the edge of a thin
  triangle is then no more texels than past the edge of a large one.)

  **The normal map** has the normal in the tangent space of glTF: at a
  texel, the tangent, the bitangent and the normal are the means of
  those of the three corners of the triangle, as an app makes them. The
  tangent of a corner is the direction of +u in the chart, at a right
  angle to the normal of the corner, with the rule of `World.GLB` for
  its sign.
  """

  alias World.{Mesh, SDF, Sculpt, Vec}
  alias World.Sculpt.Texture

  # The border of a rectangle round its triangles, in texels.
  @border 2
  # The most triangles of a patch, and the cosine of the most angle from
  # the face of its first triangle to the face of another one (25 degrees).
  @patch 256
  # The most triangles of a group: the patches of a group are made in one process.
  @group 4_000
  @tilt 0.866
  # The texels round the triangles of a chart that have values.
  @reach 3
  # The cosine of the most angle from the normal of a point to a face that keeps that normal (35 degrees).
  @hard 0.819
  # The corners of a tetrahedron: four values there give the gradient of a field at its center.
  @tetrahedron [{1.0, -1.0, -1.0}, {-1.0, -1.0, 1.0}, {-1.0, 1.0, -1.0}, {1.0, 1.0, 1.0}]
  # The texel of a place with no chart: a mean gray, and the normal of the face.
  @gray <<128, 128, 128>>
  @flat <<128, 128, 255>>
  # The finish of a place with no chart: open, rough, no metal.
  @plain <<255, 153, 0>>

  @doc """
  The least side of an image (texels) for `faces` triangles: a triangle
  alone needs a rectangle of 4 by 4 texels (its border), and the rows
  lose some.
  """
  def least(faces), do: ceil(:math.sqrt(faces * 18 * 1.1)) + 6

  @doc """
  The maps of the meshes of some sculptures in one image (a sculpture
  and its details, each with its own edits and cells): `parts` is a list
  of `{meshes, edits, step}`. The meshes come back in one list, in the
  order of the parts.

  When an edit has a finish of its own (`World.SDF.finish/3`), the maps
  have `finish` too: the rows of an image with the roughness in its
  green and the metal in its blue, as glTF reads them; and `glow`, the
  color of each texel times its glow, when an edit glows. `defaults` is
  the finish of the material of an edit with none of its own (a role to
  `{roughness, metal}`).

  `look` is the look of the surface from its shape
  (`docs/plans/0012-a-world-of-sites.md`, D1 and D2):

  - `occlusion: true`: the red of `finish` is how open each place is
    (255 on an open face, less in a crease, where less light of the sky
    comes), as glTF reads the occlusion. The maps have `finish` then,
    also when no edit has a finish.
  - `dirt` (0 to 1): the creases are darker and more rough.
  - `wear` (0 to 1): the sharp edges are lighter and less rough.

  How open a place is comes from the field along the normal of the
  place: with nothing there, the field at a distance is that distance.
  The bake reads it at a grid of texels (each fourth texel for the near
  distances, each sixteenth for the far ones), and the texels between
  take it from the texels of the grid round them.

  With no `look`, the surface has no look from its shape.
  """
  def maps(parts, side, defaults \\ %{}), do: maps(parts, side, defaults, %{})

  @doc """
  The maps of the meshes of a sculpture (`World.Sculpt.model/2`: each
  with the normals of its points), in an image of `side` texels on each
  side: `{meshes, maps}`. Each mesh has the UVs of the corners of its
  faces (`World.Mesh.map/2`) and no colors of its points; `maps` is
  `%{side: side, color: rows, normal: rows}`, the rows from the top,
  each a binary of three bytes for each texel (`color` is nil when no
  edit has a color). `:small` when the image has no place for the charts
  (`least/1`).
  """
  def maps(meshes, edits, step, side) when is_number(step), do: maps([{meshes, edits, step}], side, %{}, %{})

  def maps(parts, side, defaults, look) when is_map(look) do
    look = Map.merge(%{occlusion: false, dirt: 0.0, wear: 0.0}, look)
    shade? = look.occlusion or look.dirt > 0.0 or look.wear > 0.0
    # (An edit with a surface: the relief, the color and the finish of each texel change.)
    grain? = Enum.any?(parts, fn {_, edits, _} -> Enum.any?(edits, & &1.surface) end)
    look = Map.merge(look, %{shade: shade?, grain: grain?})

    colors? =
      grain? or look.dirt > 0.0 or look.wear > 0.0 or
        Enum.any?(parts, fn {_, edits, _} -> Enum.any?(edits, & &1.color) end)

    finish? = shade? or grain? or Enum.any?(parts, fn {_, edits, _} -> SDF.finished?(edits) end)
    glow? = Enum.any?(parts, fn {_, edits, _} -> Enum.any?(edits, &((&1.glow || 0.0) > 0.0)) end)
    # The finish of the materials, when a texel needs it (nil with no finish of an edit).
    defaults = if finish?, do: defaults
    meshes = parts |> Enum.flat_map(&elem(&1, 0)) |> Enum.map(&split/1)
    # The edits of all the parts in one list: the list of a triangle is
    # places in it. Each part has its first place, its limit and its cells.
    {fields, edits, _} =
      Enum.reduce(parts, {[], [], 0}, fn {ms, edits, step}, {fields, all, first} ->
        field = %{first: first, edits: edits, limit: Sculpt.limit(edits, step), step: step}
        {fields ++ List.duplicate(field, length(ms)), all ++ edits, first + length(edits)}
      end)

    fields = List.to_tuple(fields)

    triangles =
      for {%Mesh{} = m, mi} <- Enum.with_index(meshes),
          points = List.to_tuple(m.points),
          normals = List.to_tuple(m.normals),
          {[a, b, c], fi} <- Enum.with_index(m.faces) do
        {p0, p1, p2} = {elem(points, a), elem(points, b), elem(points, c)}
        area = Vec.len(Vec.cross(Vec.sub(p1, p0), Vec.sub(p2, p0))) / 2

        %{
          id: {mi, fi},
          points: {p0, p1, p2},
          normals: {elem(normals, a), elem(normals, b), elem(normals, c)},
          area: area,
          limit: elem(fields, mi).limit,
          step: elem(fields, mi).step
        }
      end

    case pack(triangles, side) do
      :small ->
        :small

      {squares, scale} ->
        lists =
          triangles
          |> Enum.group_by(fn %{id: {mi, _}} -> mi end)
          |> Enum.map(fn {mi, group} -> lists(group, 1 / scale, elem(fields, mi)) end)
          |> Enum.reduce(%{}, &Map.merge/2)

        all = List.to_tuple(edits)

        # A message is a copy: a process gets the edits of its squares one
        # time, and the short list of each triangle as places in them.
        # The rectangles of a process have about the same count of
        # texels as those of each other process (a rectangle can be 2
        # texels or 20,000).
        most = max(div(Enum.sum(for s <- squares, do: s.w * s.h), 16 * System.schedulers_online()), 1)

        done =
          squares
          |> Enum.chunk_while(
            {[], 0},
            fn s, {group, texels} ->
              if texels + s.w * s.h >= most,
                do: {:cont, Enum.reverse([s | group]), {[], 0}},
                else: {:cont, {[s | group], texels + s.w * s.h}}
            end,
            fn
              {[], _} -> {:cont, nil}
              {group, _} -> {:cont, Enum.reverse(group), nil}
            end
          )
          |> Enum.map(fn group ->
            used = for(s <- group, {t, _} <- s.tris, i <- Map.fetch!(lists, t.id), uniq: true, do: i)
            place = used |> Enum.with_index() |> Map.new()

            listed = fn {t, at} ->
              {Map.put(t, :list, Enum.map(Map.fetch!(lists, t.id), &Map.fetch!(place, &1))), at}
            end

            # (For the occlusion, a process has all the edits of the parts of its rectangles.)
            whole =
              if shade?,
                do: for(s <- group, {%{id: {mi, _}}, _} <- s.tris, uniq: true, into: %{}, do: {mi, elem(fields, mi)})

            {Enum.map(used, &elem(all, &1)), Enum.map(group, &%{&1 | tris: Enum.map(&1.tris, listed)}), whole}
          end)
          |> Task.async_stream(
            fn {some, group, whole} ->
              some = List.to_tuple(some)
              edits = fn {t, at} -> {%{t | list: Enum.map(t.list, &elem(some, &1))}, at} end

              for s <- group do
                # The field of the part of the rectangle (of its first triangle).
                field = whole && whole[s.tris |> hd() |> elem(0) |> Map.fetch!(:id) |> elem(0)]
                look = Map.put(look, :field, field)
                {s.at, {s.w, s.h}, texels(%{s | tris: Enum.map(s.tris, edits)}, defaults, side, look)}
              end
            end,
            # (Two tasks for each scheduler: a task waits at times, for memory or for the collector.)
            max_concurrency: 2 * System.schedulers_online(),
            ordered: false,
            timeout: :infinity
          )
          |> Enum.flat_map(fn {:ok, group} -> group end)

        # The UVs of the corners of each triangle (v down from the top of the image).
        uvs =
          for %{at: {x, y}} = s <- squares, {t, corners} <- s.tris, into: %{} do
            {t.id, for({i, j} <- Tuple.to_list(corners), do: {(x + i) / side, (y + j) / side})}
          end

        meshes =
          for {m, mi} <- Enum.with_index(meshes) do
            # Each corner takes the normal of its point: the normal map has the hard edges.
            Mesh.map(
              %{m | colors: nil, angle: 180.0},
              for({_, fi} <- Enum.with_index(m.faces), do: Map.fetch!(uvs, {mi, fi}))
            )
          end

        [color, normal, finish, glow] =
          [{colors?, 0, @gray}, {true, 1, @flat}, {finish?, 2, @plain}, {glow?, 3, <<0, 0, 0>>}]
          |> Task.async_stream(fn {wanted?, which, blank} -> if wanted?, do: image(done, side, which, blank) end,
            timeout: :infinity
          )
          |> Enum.map(fn {:ok, rows} -> rows end)

        {meshes, %{side: side, color: color, normal: normal, finish: finish, glow: glow}}
    end
  end

  # A corner at a hard edge gets a point of its own, with the normal of
  # its face: a corner whose face is more than `@hard` from the normal of
  # its point. The frame of a triangle then turns little from corner to
  # corner, so the normals of its texels are small turns from it. (With
  # one normal for all the faces round a point of a hard edge, the frame
  # turns much along a thin triangle, and the light shows streaks.)
  defp split(%Mesh{points: points, normals: normals, faces: faces} = m) do
    {pt, nt} = {List.to_tuple(points), List.to_tuple(normals)}

    {faces, more, _} =
      Enum.reduce(faces, {[], [], tuple_size(pt)}, fn [a, b, c] = face, {faces, more, next} ->
        cross = Vec.cross(Vec.sub(elem(pt, b), elem(pt, a)), Vec.sub(elem(pt, c), elem(pt, a)))

        {e1, e2} = {Vec.sub(elem(pt, b), elem(pt, a)), Vec.sub(elem(pt, c), elem(pt, a))}

        # A triangle with almost no area keeps the normals of its points:
        # the normal of its face is not sure (its points are on a line).
        if Vec.len(cross) < 1.0e-4 * (Vec.dot(e1, e1) + Vec.dot(e2, e2)) do
          {[face | faces], more, next}
        else
          flat = Vec.norm(cross)

          {face, more, next} =
            Enum.reduce(face, {[], more, next}, fn v, {vs, more, next} ->
              if Vec.dot(elem(nt, v), flat) >= @hard,
                do: {[v | vs], more, next},
                else: {[next | vs], [{elem(pt, v), flat} | more], next + 1}
            end)

          {[Enum.reverse(face) | faces], more, next}
        end
      end)

    more = Enum.reverse(more)

    %{
      m
      | points: points ++ Enum.map(more, &elem(&1, 0)),
        normals: normals ++ Enum.map(more, &elem(&1, 1)),
        faces: Enum.reverse(faces),
        colors: nil
    }
  end

  # --- The charts -------------------------------------------------------------

  # The rectangles of the charts in the image, and the scale of the
  # image (texels for each meter): `{[%{at: {x, y}, w: w, h: h, tris:
  # [{triangle, the texels of its corners in the rectangle}]}], scale}`,
  # at the largest scale that fits (a search by halves), or `:small`.
  defp pack(triangles, side) do
    # The patches of each group of triangles in a process of its own
    # (and with a heap of its own: the caller can hold a large model).
    strips =
      triangles
      |> groups()
      |> Task.async_stream(&patches/1, max_concurrency: System.schedulers_online(), ordered: false, timeout: :infinity)
      |> Enum.flat_map(fn {:ok, patches} -> patches end)

    if place(strips, 0.0, side) == :small do
      :small
    else
      mean = Enum.sum(Enum.map(triangles, &:math.sqrt(2 * &1.area))) / max(length(triangles), 1)
      # At this scale a triangle of the mean size is two times as wide as the image.
      high = 2 * side / max(mean, 1.0e-9)

      {scale, _} =
        Enum.reduce(1..16, {0.0, high}, fn _, {lo, hi} ->
          mid = (lo + hi) / 2
          if place(strips, mid, side) == :small, do: {lo, mid}, else: {mid, hi}
        end)

      {place(strips, scale, side), scale}
    end
  end

  # The triangles in groups by their places, of `@group` triangles at
  # the most: a group is cut in two halves across the longest side of
  # its box, at its middle triangle, again and again. A patch is of one
  # group.
  defp groups(triangles) when length(triangles) <= @group, do: [triangles]

  defp groups(triangles) do
    centers = for %{points: {p0, p1, p2}} = t <- triangles, do: {Vec.add(Vec.add(p0, p1), p2), t}
    {{x0, y0, z0}, {x1, y1, z1}} = Vec.bounds(Enum.map(centers, &elem(&1, 0)))
    {_, axis} = Enum.max([{x1 - x0, 0}, {y1 - y0, 1}, {z1 - z0, 2}])

    {low, high} =
      centers
      |> Enum.sort_by(fn {c, t} -> {elem(c, axis), t.id} end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.split(div(length(triangles), 2))

    groups(low) ++ groups(high)
  end

  # The patches of the triangles, each seen flat: `[%{tris: [{triangle,
  # the places of its corners on the plane of the patch (meters)}], w:
  # the width of the patch, h: its height}]`. The largest free triangle
  # starts a patch. The patch then takes, ring by ring, each free
  # triangle of its mesh across an edge of one of its triangles, that is
  # less than 35 degrees from that triangle and less than 25 degrees
  # from the first one, and that does not lie on a triangle of the
  # patch (a surface that goes round and over itself).
  defp patches(triangles) do
    by_id = Map.new(triangles, &{&1.id, &1})

    across =
      for t <- triangles, {k, key, _} <- edges(t), reduce: %{} do
        acc -> Map.update(acc, key, [{t.id, k}], &[{t.id, k} | &1])
      end

    {patches, _} =
      triangles
      |> Enum.sort_by(&{-&1.area, &1.id})
      |> Enum.reduce({[], MapSet.new()}, fn t, {patches, used} ->
        cond do
          t.id in used ->
            {patches, used}

          Vec.len(flat(t)) < 1.0e-18 ->
            # A triangle with no area has no direction: alone, on its longest edge.
            [{k, _, length} | _] = edges(t)
            {foot, height} = apex(t.points, k)
            alone = [{t, unturned({{foot, height}, {0.0, 0.0}, {length, 0.0}}, k)}]
            {[level(alone) | patches], MapSet.put(used, t.id)}

          true ->
            axis = Vec.norm(flat(t))
            x = Vec.norm(Vec.cross(axis, if(abs(elem(axis, 0)) < 0.9, do: {1.0, 0.0, 0.0}, else: {0.0, 1.0, 0.0})))
            y = Vec.cross(axis, x)

            seen = fn %{points: {p0, p1, p2}} ->
              for(p <- [p0, p1, p2], do: {Vec.dot(p, x), Vec.dot(p, y)}) |> List.to_tuple()
            end

            used = MapSet.put(used, t.id)
            {tris, used} = grow([t], {[{t, seen.(t)}], 1}, used, {across, by_id, axis, seen})
            {[level(tris) | patches], used}
        end
      end)

    Enum.reverse(patches)
  end

  # The patch with the triangles round the triangles of `ring` (the
  # triangles that it took last), ring by ring. Gives the patch and the
  # triangles that are not free.
  defp grow([], {tris, _count}, used, _mesh), do: {Enum.reverse(tris), used}

  defp grow(ring, patch, used, {across, by_id, axis, seen} = mesh) do
    {next, patch, used} =
      for t <- ring, {k, key, _} <- edges(t), {id, ko} <- Map.fetch!(across, key), reduce: {[], patch, used} do
        {next, {tris, count} = patch, used} ->
          o = by_id[id]

          # The two go round their edge in opposite directions, as the faces of a closed mesh do.
          with true <- count < @patch and id not in used and smooth?(t, o),
               true <- Vec.dot(flat(o), axis) >= @tilt * Vec.len(flat(o)),
               true <-
                 elem(t.points, rem(k + 1, 3)) == elem(o.points, rem(ko + 2, 3)) and
                   elem(t.points, rem(k + 2, 3)) == elem(o.points, rem(ko + 1, 3)),
               at = seen.(o),
               false <- Enum.any?(tris, fn {_, other} -> overlap?(at, other) end) do
            {[o | next], {[{o, at} | tris], count + 1}, MapSet.put(used, id)}
          else
            _ -> {next, patch, used}
          end
      end

    grow(Enum.reverse(next), patch, used, mesh)
  end

  # The edges of a triangle, the longest first: `{k, key, length}`, the
  # edge `k` is the edge with no corner `k`.
  defp edges(%{id: {mesh, _}, points: points}) do
    for k <- 0..2 do
      {p, q} = {elem(points, rem(k + 1, 3)), elem(points, rem(k + 2, 3))}
      {k, {mesh, min(p, q), max(p, q)}, Vec.len(Vec.sub(q, p))}
    end
    |> Enum.sort_by(fn {k, _, length} -> {-length, k} end)
  end

  defp smooth?(a, b) do
    {na, nb} = {flat(a), flat(b)}
    {la, lb} = {Vec.len(na), Vec.len(nb)}
    la > 1.0e-18 and lb > 1.0e-18 and Vec.dot(na, nb) >= @hard * la * lb
  end

  defp flat(%{points: {p0, p1, p2}}), do: Vec.cross(Vec.sub(p1, p0), Vec.sub(p2, p0))

  # The corner `k` of a triangle over its edge `k`: the place of its
  # foot along the edge (from the corner after `k`), and its height.
  defp apex(points, k) do
    {p, a, b} = {elem(points, k), elem(points, rem(k + 1, 3)), elem(points, rem(k + 2, 3))}
    length = Vec.len(Vec.sub(b, a))
    along = if length > 1.0e-18, do: Vec.scale(Vec.sub(b, a), 1 / length), else: {1.0, 0.0, 0.0}
    foot = Vec.dot(Vec.sub(p, a), along)
    {foot, Vec.len(Vec.sub(Vec.sub(p, a), Vec.scale(along, foot)))}
  end

  # Three places `{of the corner k, of the corner after it, of the next one}` in the order of the corners.
  defp unturned(places, 0), do: places
  defp unturned({a, b, c}, 1), do: {c, a, b}
  defp unturned({a, b, c}, 2), do: {b, c, a}

  # Two flat triangles lie on each other: a corner of one is in the
  # other, or two of their edges cross. (Two triangles with a common
  # corner or a common edge, each on its side, do not.)
  defp overlap?({{ax, ay}, {bx, by}, {cx, cy}} = one, {{dx, dy}, {ex, ey}, {fx, fy}} = other) do
    # First their boxes: most triangles of a patch are far from each other.
    if max(ax, max(bx, cx)) < min(dx, min(ex, fx)) or max(dx, max(ex, fx)) < min(ax, min(bx, cx)) or
         max(ay, max(by, cy)) < min(dy, min(ey, fy)) or max(dy, max(ey, fy)) < min(ay, min(by, cy)) do
      false
    else
      {a, b} = {Tuple.to_list(one), Tuple.to_list(other)}
      sides = fn [p, q, r] -> [{p, q}, {q, r}, {r, p}] end

      Enum.any?(a, &within?(&1, b)) or Enum.any?(b, &within?(&1, a)) or
        Enum.any?(sides.(a), fn e -> Enum.any?(sides.(b), &cross?(e, &1)) end)
    end
  end

  defp turn2({ax, ay}, {bx, by}, {cx, cy}), do: (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)

  # A place is in a flat triangle, not on its border.
  defp within?(p, [a, b, c]) do
    size = abs(turn2(a, b, c))
    least = 1.0e-9 * size
    turns = [turn2(a, b, p), turn2(b, c, p), turn2(c, a, p)]
    size > 0.0 and (Enum.all?(turns, &(&1 > least)) or Enum.all?(turns, &(&1 < -least)))
  end

  # Two segments cross at a place that is not an end of one of them.
  defp cross?({a, b}, {c, d}) do
    turns = [turn2(a, b, c), turn2(a, b, d), turn2(c, d, a), turn2(c, d, b)]
    least = 1.0e-9 * Enum.sum(Enum.map(turns, &abs/1))

    [s1, s2, s3, s4] =
      for t <- turns do
        cond do
          t > least -> 1
          t < -least -> -1
          true -> 0
        end
      end

    s1 * s2 < 0 and s3 * s4 < 0
  end

  # The turns of a rectangle that are tried for a patch: each 2 degrees of a quarter turn.
  @turns for k <- 0..44, a = k * :math.pi() / 90, do: {:math.cos(a), :math.sin(a)}

  # The turn that gives the rectangle of a patch the least area (its
  # cosine and its sine), and that rectangle: its corner, its width and
  # its height.
  defp fit(tris) do
    places = for {_, at} <- tris, p <- Tuple.to_list(at), uniq: true, do: p

    @turns
    |> Enum.map(fn turn ->
      {xs, ys} = places |> Enum.map(&turned(turn, &1)) |> Enum.unzip()
      {{x0, x1}, {y0, y1}} = {Enum.min_max(xs), Enum.min_max(ys)}
      {turn, {x0, y0, x1 - x0, y1 - y0}}
    end)
    |> Enum.min_by(fn {_, {_, _, w, h}} -> w * h end)
  end

  defp turned({cos, sin}, {x, y}), do: {x * cos + y * sin, y * cos - x * sin}

  # A patch turned so that its rectangle has the least area, with the
  # corner of its rectangle at the origin.
  defp level(tris) do
    {turn, {x0, y0, w, h}} = fit(tris)
    move = fn p -> (fn {x, y} -> {x - x0, y - y0} end).(turned(turn, p)) end
    %{tris: for({t, {a, b, c}} <- tris, do: {t, {move.(a), move.(b), move.(c)}}), w: w, h: h}
  end

  # The rectangles at a scale (texels for each meter), in rows.
  defp place(strips, scale, side) do
    sized =
      strips
      |> Enum.map(fn %{tris: tris, w: w, h: h} ->
        texel = fn {x, y} -> {@border + x * scale, @border + y * scale} end

        %{
          w: ceil(w * scale) + 2 * @border,
          h: ceil(h * scale) + 2 * @border,
          tris: for({t, {a, b, c}} <- tris, do: {t, {texel.(a), texel.(b), texel.(c)}})
        }
      end)
      |> Enum.sort_by(fn %{w: w, h: h, tris: [{t, _} | _]} -> {-h, -w, t.id} end)

    {squares, _, y, height} =
      Enum.reduce(sized, {[], 0, 0, 0}, fn %{w: w, h: h} = s, {squares, x, y, height} ->
        # A new row when the rectangle does not fit in this one.
        {x, y, height} = if x + w > side, do: {0, y + height, h}, else: {x, y, max(height, h)}
        {[Map.put(s, :at, {x, y}) | squares], x + w, y, height}
      end)

    if y + height > side or Enum.any?(sized, &(&1.w > side)), do: :small, else: Enum.reverse(squares)
  end

  # --- The edits of each triangle ---------------------------------------------

  # The short list of each triangle: the edits that reach its ball (their
  # places in the list of the edits). First
  # the edits of each cube of a grid of the triangles (a cube of 8 times
  # the mean size of a triangle), then the edits of each triangle from
  # the list of its cube.
  defp lists(triangles, texel, %{edits: edits, limit: limit, first: first}) do
    balls = for t <- triangles, do: {t.id, ball(t, texel)}
    mean = Enum.sum(for {_, {_, r}} <- balls, do: r) / max(length(balls), 1)
    size = max(8 * mean, 1.0e-6)
    # The place of each edit in the list, by its id: a list of a triangle
    # is places, not edits (the lists come back in messages).
    place = edits |> Enum.with_index(first) |> Map.new(fn {e, i} -> {e.id, i} end)

    balls
    |> Enum.group_by(fn {_, {{x, y, z}, _}} -> {floor(x / size), floor(y / size), floor(z / size)} end)
    |> Task.async_stream(
      fn {{i, j, k}, group} ->
        most = Enum.max(for {_, {_, r}} <- group, do: r)
        center = {(i + 0.5) * size, (j + 0.5) * size, (k + 0.5) * size}
        near = SDF.prune(edits, center, size * :math.sqrt(3) / 2 + most, limit)
        for {id, {c, r}} <- group, do: {id, for(e <- SDF.prune(near, c, r, limit), do: Map.fetch!(place, e.id))}
      end,
      max_concurrency: System.schedulers_online(),
      ordered: false,
      timeout: :infinity
    )
    |> Enum.flat_map(fn {:ok, group} -> group end)
    |> Map.new()
  end

  # The ball of the places where the texels of a triangle read the field:
  # its center, and the most distance to a corner of the triangle, and
  # two texels and a part more (a texel in the triangle reads the field
  # as far as a texel from its place).
  defp ball(%{points: {p0, p1, p2}}, texel) do
    c = Vec.scale(Vec.add(Vec.add(p0, p1), p2), 1 / 3)
    far = Enum.max(for p <- [p0, p1, p2], do: Vec.len(Vec.sub(p, c)))
    {c, (far + 2.5 * texel) * 1.05 + 1.0e-9}
  end

  # --- The texels of a square -------------------------------------------------

  # The rows of a rectangle: `{colors, normals, finishes, glows}`, each a
  # list of `h` binaries from the top.
  defp texels(%{w: w, h: h, tris: tris}, defaults, side, look) do
    # (An app makes no tangent from a triangle with almost no area of
    # UVs: `World.GLB`. The UVs are the texels over the side of the image.)
    least = 1.0e-12 * side * side
    charts = tris |> Enum.map(fn {t, corners} -> chart(t, corners, least) end) |> framed() |> List.to_tuple()

    # The chart, the place, the value and the color of the field at each
    # texel of a triangle, and the weights of the corners of the
    # triangle at that place.
    # (The finish only when an edit has one: `defaults` then. One fold of
    # the edits gives it with the color.)
    values =
      for {{i, j}, {k, weights}} <- owners(charts, w, h), c = elem(charts, k), p = mix(c.points, weights), into: %{} do
        {f, color, finish} =
          cond do
            look.grain -> grain(SDF.seen(c.list, p, c.limit, defaults), c, p)
            defaults -> SDF.sample(c.list, p, c.limit, defaults)
            true -> Tuple.insert_at(SDF.sample(c.list, p, c.limit), 2, nil)
          end

        {{i, j}, {c, p, f, color, {weights, finish}}}
      end

    shade = if look.shade and map_size(values) > 0, do: shade(values, look)

    done =
      for {{i, j} = at, {c, p, f, color, {weights, finish}}} <- values, into: %{} do
        {{r, g, b}, finish} = if shade, do: shaded(color, finish, shade.(i, j), look), else: {color, finish}
        {finish, glow} = if finish, do: finish({r, g, b}, finish), else: {<<>>, <<>>}
        {at, {<<r, g, b>>, normal(c, i, j, {p, f, weights}, values), finish, glow}}
      end

    # (With the relief of a surface, the normals of two texels next to
    # each other are not of one smooth surface: the border has the
    # normal of the texel next to it.)
    plain? = look.grain and Enum.any?(tris, fn {t, _} -> Enum.any?(t.list, & &1.surface) end)
    done = spread(done, w, h, plain?)

    rows =
      for j <- 0..(h - 1) do
        for i <- 0..(w - 1), reduce: {<<>>, <<>>, <<>>, <<>>} do
          {colors, normals, finishes, glows} ->
            case done[{i, j}] do
              {color, normal, finish, glow} ->
                {<<colors::binary, color::binary>>, <<normals::binary, normal::binary>>,
                 <<finishes::binary, finish::binary>>, <<glows::binary, glow::binary>>}

              nil ->
                {<<colors::binary, @gray::binary>>, <<normals::binary, @flat::binary>>,
                 <<finishes::binary, @plain::binary>>, <<glows::binary, 0, 0, 0>>}
            end
        end
      end

    {Enum.map(rows, &elem(&1, 0)), Enum.map(rows, &elem(&1, 1)), Enum.map(rows, &elem(&1, 2)),
     Enum.map(rows, &elem(&1, 3))}
  end

  # The texels next to a texel: the four at its sides first.
  @next [{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, 1}, {1, -1}, {-1, -1}]

  # The texels of a rectangle with the border of its triangles: ring by
  # ring to `@reach` texels, a texel with no values takes the values of
  # a texel next to it. An app reads the maps a little past the edge of
  # a triangle (the mean of four texels; a pixel past the edge with
  # antialiasing): it reads the same surface there.
  #
  # The normal of a texel of the first ring goes on with the change of
  # the two texels before it (the texel next to it, and the one behind
  # that): on a round surface the normals go on across the edge of a
  # patch as they are on the next patch, with no step in the light. A
  # texel of the border does not read the field: past an edge can be
  # another part of the sculpture.
  defp spread(inside, w, h, plain?) do
    {done, _} =
      Enum.reduce(1..@reach, {inside, Enum.sort(Map.keys(inside))}, fn ring, {done, from} ->
        {done, next} =
          for {i, j} <- from,
              {di, dj} <- @next,
              {k, l} = {i + di, j + dj},
              k >= 0 and k < w and l >= 0 and l < h,
              reduce: {done, []} do
            {done, next} ->
              if is_map_key(done, {k, l}) do
                {done, next}
              else
                near = Map.fetch!(done, {i, j})
                value = if ring == 1 and not plain?, do: on(near, inside[{i - di, j - dj}]), else: near
                {Map.put(done, {k, l}, value), [{k, l} | next]}
              end
          end

        {done, Enum.sort(next)}
      end)

    done
  end

  # The values one texel after `near`: its color and its finish, and its
  # normal with the change from `far` to `near`, when that change is
  # small (the two are of one smooth surface). The same with no `far`.
  defp on(near, nil), do: near

  defp on({color, <<x1, y1, z1>> = normal, finish, glow}, {_, <<x2, y2, z2>>, _, _}) do
    if max(abs(x1 - x2), max(abs(y1 - y2), abs(z1 - z2))) <= 12,
      do: {color, <<byte8(2 * x1 - x2), byte8(2 * y1 - y2), byte8(2 * z1 - z2)>>, finish, glow},
      else: {color, normal, finish, glow}
  end

  defp byte8(v), do: min(max(v, 0), 255)

  # The bytes of the finish of a texel (the roughness in the green, the
  # metal in the blue), and of its glow (its color times its glow).
  defp finish({r, g, b}, {rough, metal, glow}), do: finish({r, g, b}, {rough, metal, glow, 1.0})

  # (With how open the place is, in the red: the occlusion of glTF.)
  defp finish({r, g, b}, {rough, metal, glow, open}) do
    {<<round(open * 255), round(rough * 255), round(metal * 255)>>,
     <<round(r * glow), round(g * glow), round(b * glow)>>}
  end

  # --- The surface of an edit --------------------------------------------------

  # The value, the color and the finish of a texel with the surface of
  # its edit (`World.Sculpt.Texture`): the relief moves the surface out
  # (so the normals of the texels have it), and the color and the finish
  # change. A mark of the surface that is smaller than 1.5 texels does not
  # show (the image cannot have it); it shows in full from 3.5 texels.
  defp grain({f, color, finish, %{surface: {kind, scale}} = e}, %{u: u, face: face}, p) do
    fade = min(max((scale / Vec.len(u) - 1.5) / 2, 0.0), 1.0)

    if fade == 0.0 do
      {f, color, finish}
    else
      q = along(e, Vec.scale(World.Frame.point(e.back, p), 1 / scale))
      {height, tone, more, less, to} = Texture.at(kind, q, along(e, World.Frame.dir(e.back, face)))
      {r, g, b} = color
      {rough, metal, glow} = finish
      tone = 1.0 + (tone - 1.0) * fade
      {r, g, b} = {r * tone, g * tone, b * tone}

      {r, g, b} =
        case to do
          {{tr, tg, tb}, part} -> {r + (tr - r) * part * fade, g + (tg - g) * part * fade, b + (tb - b) * part * fade}
          nil -> {r, g, b}
        end

      {f - height * scale * fade, {byte8(round(r)), byte8(round(g)), byte8(round(b))},
       {min(max(rough + more * fade, 0.05), 1.0), metal * (1.0 + (less - 1.0) * fade), glow}}
    end
  end

  defp grain({f, color, finish, _edit}, _chart, _p), do: {f, color, finish}

  # A place in the axes of the surface of an edit: its z is the long
  # axis of a box (the grain of a plank goes along the plank); for each
  # other shape, the z of the edit.
  defp along(%{shape: shape, size: size}, {x, y, z}) when shape in [:box, :round_box] do
    {a, b, c} = {elem(size, 0), elem(size, 1), elem(size, 2)}

    cond do
      c >= a and c >= b -> {x, y, z}
      a >= b -> {y, z, x}
      true -> {z, x, y}
    end
  end

  defp along(_edit, q), do: q

  # --- How open a place is ----------------------------------------------------

  # The distances of the values along the normal, in cells: two near
  # ones (a crease of the surface) and two far ones (a part over the
  # place, as the body of a car over its wheel).
  @near {1.5, 4.0}
  @far {10.0, 25.0}
  # The grid of the texels that read the field, for the near distances and for the far ones.
  @fine 4
  @wide 16
  # The part of each distance in how open a place is.
  @parts {0.3, 0.3, 0.25, 0.15}
  # The distance of the value under the surface for the wear of an edge, in cells.
  @under 2.0

  # A function from a texel to `{open, crease, edge}`: how open the
  # place is (1 on an open face), how deep it is in a crease (0 to 1),
  # and how near it is to a sharp edge (0 to 1).
  defp shade(values, %{field: %{edits: edits, step: step}} = look) do
    {lo, hi} = Vec.bounds(for {_, {_, p, _, _, _}} <- values, do: p)
    {center, half} = {Vec.lerp(lo, hi, 0.5), Vec.len(Vec.sub(hi, lo)) / 2}
    {{n1, n2}, {f1, f2}} = {@near, @far}
    # (The values are right as far as the farthest distance: a limit past it.)
    limit = (f2 + 2) * step
    near = SDF.fast(SDF.prune(edits, center, half + (n2 + 0.5) * step, limit))
    far = SDF.fast(SDF.prune(edits, center, half + (f2 + 0.5) * step, limit))

    # How much of the way along the normal is taken: 0 with nothing
    # there, 1 with a surface at the place.
    taken = fn list, p, n, cells ->
      d = cells * step
      min(max((d - SDF.value(list, Vec.add(p, Vec.scale(n, d)), limit)) / d, 0.0), 1.0)
    end

    # How thin the solid is under the place: 0 under a flat face (the
    # field at a depth is that depth), more near a sharp edge.
    thin = fn p, n ->
      d = @under * step
      min(max((d + SDF.value(near, Vec.sub(p, Vec.scale(n, d)), limit)) / d, 0.0), 1.0)
    end

    fine = fn {c, p, _, _, {weights, _}} ->
      n = Vec.norm(mix(c.normals, weights))
      edge = if look.wear > 0.0, do: thin.(p, n), else: 0.0
      [taken.(near, p, n, n1), taken.(near, p, n, n2), edge]
    end

    wide = fn {c, p, _, _, {weights, _}} ->
      n = Vec.norm(mix(c.normals, weights))
      # (The square: a part that is far takes a small part of the sky.)
      [taken.(far, p, n, f1) ** 2, taken.(far, p, n, f2) ** 2]
    end

    grid = fn every, read ->
      for {{i, j}, v} <- values, rem(i, every) == 0 and rem(j, every) == 0, into: %{}, do: {{i, j}, read.(v)}
    end

    {fines, wides} = {grid.(@fine, fine), grid.(@wide, wide)}
    # A small rectangle can have no texel of the wide grid: one value for all of it.
    one = values |> Enum.min() |> elem(1) |> wide.()
    {a, b, c, d} = @parts

    fn i, j ->
      [o1, o2, edge] = between(fines, @fine, i, j) || fine.(Map.fetch!(values, {i, j}))
      [o3, o4] = between(wides, @wide, i, j) || one
      {1.0 - (a * o1 + b * o2 + c * o3 + d * o4), (o1 + o2) / 2, edge}
    end
  end

  # The values at a texel from the texels of a grid round it (by their
  # distances, as in an image), or nil when none of the four has values.
  defp between(grid, every, i, j) do
    {i0, j0} = {i - rem(i, every), j - rem(j, every)}
    {x, y} = {(i - i0) / every, (j - j0) / every}

    near =
      for {a, b, w} <- [
            {i0, j0, (1 - x) * (1 - y)},
            {i0 + every, j0, x * (1 - y)},
            {i0, j0 + every, (1 - x) * y},
            {i0 + every, j0 + every, x * y}
          ],
          v = grid[{a, b}],
          do: {v, w + 1.0e-6}

    case near do
      [] ->
        nil

      [{v, _}] ->
        v

      _ ->
        total = Enum.sum(for {_, w} <- near, do: w)
        near |> Enum.map(fn {v, w} -> Enum.map(v, &(&1 * w / total)) end) |> Enum.zip_with(&Enum.sum/1)
    end
  end

  # The color and the finish of a texel with its dirt and its wear, and
  # how open it is as the fourth part of the finish.
  defp shaded({r, g, b}, {rough, metal, glow}, {open, crease, edge}, %{dirt: dirt, wear: wear} = look) do
    dark = 1.0 - 0.6 * dirt * crease
    light = 0.35 * wear * edge
    tone = fn v -> round(min(v * dark + (255 - v * dark) * light, 255.0)) end
    rough = min(max(rough + 0.3 * dirt * crease - 0.25 * wear * edge, 0.05), 1.0)
    {{tone.(r), tone.(g), tone.(b)}, {rough, metal, glow, if(look.occlusion, do: open, else: 1.0)}}
  end

  # The chart of a triangle with the texels of its corners (the centers
  # of the texels are at their numbers and a half): the place of a texel
  # is `base + i u + j v`; and the frames of its corners.
  defp chart(%{points: {p0, p1, p2}, normals: normals, list: list, limit: limit, step: step}, corners, least) do
    {{x0, y0}, {x1, y1}, {x2, y2}} = corners
    {e1, e2} = {Vec.sub(p1, p0), Vec.sub(p2, p0)}
    cross = Vec.cross(e1, e2)
    {d1x, d1y, d2x, d2y} = {x1 - x0, y1 - y0, x2 - x0, y2 - y0}
    turn = d1x * d2y - d2x * d1y

    # The move on the surface for one texel along a row (u) and along a
    # column (v): the two sides of the triangle are these moves times
    # the texels between its corners.
    moves =
      if abs(turn) >= least do
        {Vec.scale(Vec.sub(Vec.scale(e1, d2y), Vec.scale(e2, d1y)), 1 / turn),
         Vec.scale(Vec.sub(Vec.scale(e2, d1x), Vec.scale(e1, d2x)), 1 / turn)}
      end

    if Vec.len(cross) < 1.0e-18 or moves == nil do
      %{flat: true, moves: moves, normals: normals, corners: corners}
    else
      {u, v} = moves
      base = Vec.sub(p0, Vec.add(Vec.scale(u, x0 - 0.5), Vec.scale(v, y0 - 0.5)))
      {uu, uv, vv} = {Vec.dot(u, u), Vec.dot(u, v), Vec.dot(v, v)}
      det = uu * vv - uv * uv
      off = min(:math.sqrt(:math.sqrt(uu * vv)) / 2, step / 2)

      %{
        flat: false,
        # A long chart: a texel is more than a cell from the next one,
        # and the texels are too far from each other for a gradient. Its
        # texels read the field each with small steps round it.
        long: max(uu, vv) > step * step,
        points: {p0, p1, p2},
        normals: normals,
        moves: moves,
        corners: corners,
        # The numbers for the weights of the corners at a texel.
        corner: {x0, y0},
        sides: {d1x / turn, d1y / turn, d2x / turn, d2y / turn},
        list: list,
        # The list for the hot loop of the value (`World.SDF.fast/1`).
        fast: SDF.fast(list),
        limit: limit,
        base: base,
        u: u,
        v: v,
        # The two vectors in the plane that give the gradient from the
        # changes along u and along v.
        du: Vec.scale(Vec.sub(Vec.scale(u, vv), Vec.scale(v, uv)), 1 / det),
        dv: Vec.scale(Vec.sub(Vec.scale(v, uu), Vec.scale(u, uv)), 1 / det),
        face: Vec.norm(cross),
        off: off
      }
    end
  end

  # The charts of a rectangle with the frames of their corners. An app
  # makes the tangent of a point from each triangle with that point
  # (`World.GLB`: the sum of the moves along u of the triangles). The
  # triangles of a strip have points in common (the same place in the
  # image, and the same normal): the tangent of such a point is from
  # each of them.
  defp framed(charts) do
    sums =
      for %{moves: {u, v}, corners: corners, normals: normals} <- charts, k <- 0..2, reduce: %{} do
        acc ->
          Map.update(acc, {elem(corners, k), elem(normals, k)}, {u, v}, fn {a, b} -> {Vec.add(a, u), Vec.add(b, v)} end)
      end

    for chart <- charts do
      if chart.flat do
        chart
      else
        frames =
          for k <- 0..2 do
            {u, v} = Map.fetch!(sums, {elem(chart.corners, k), elem(chart.normals, k)})
            frame(elem(chart.normals, k), u, v)
          end

        Map.put(chart, :frames, frames)
      end
    end
  end

  # The chart of each texel of a triangle (its place in `charts`), and
  # the weights of the corners of the triangle at the place where the
  # texel reads the field: `%{{i, j} => {chart, weights}}`. A texel with
  # its center in a triangle is of that triangle, and reads the field at
  # its center. A triangle with no center of a texel in it (it is
  # thinner than a texel) has the free texels that it touches: each
  # reads the field at the place of the triangle nearest to its center.
  # A triangle with no area has no texel.
  defp owners(charts, w, h) do
    box = fn {{x0, y0}, {x1, y1}, {x2, y2}}, more ->
      for j <- max(floor(Enum.min([y0, y1, y2]) - 0.5) - more, 0)..min(ceil(Enum.max([y0, y1, y2])) + more, h - 1)//1,
          i <- max(floor(Enum.min([x0, x1, x2]) - 0.5) - more, 0)..min(ceil(Enum.max([x0, x1, x2])) + more, w - 1)//1,
          do: {i, j}
    end

    {owned, thin} =
      for {%{flat: false} = c, k} <- Enum.with_index(Tuple.to_list(charts)), reduce: {%{}, []} do
        {owned, thin} ->
          centers =
            for {i, j} <- box.(c.corners, 0), weights = weights(c, i, j), in?(weights), do: {{i, j}, {k, weights}}

          {Enum.reduce(centers, owned, fn {at, owner}, owned -> Map.put_new(owned, at, owner) end),
           if(centers == [], do: [{c, k} | thin], else: thin)}
      end

    for {%{corners: {{x0, y0}, {x1, y1}, {x2, y2}}} = c, k} <- Enum.reverse(thin),
        {i, j} <- box.(c.corners, 1),
        reduce: owned do
      owned ->
        {l0, l1, l2} = weights = inside(weights(c, i, j))
        {x, y} = {l0 * x0 + l1 * x1 + l2 * x2 - (i + 0.5), l0 * y0 + l1 * y1 + l2 * y2 - (j + 0.5)}
        # (The triangle touches the square of the texel: its nearest place is in the circle round that square.)
        if x * x + y * y <= 0.5, do: Map.put_new(owned, {i, j}, {k, weights}), else: owned
    end
  end

  # The place of a texel of a chart.
  defp at(c, i, j), do: Vec.add(c.base, Vec.add(Vec.scale(c.u, i * 1.0), Vec.scale(c.v, j * 1.0)))

  # A place with these weights of the corners of a triangle is in the triangle.
  defp in?({l0, l1, l2}), do: l0 >= -1.0e-9 and l1 >= -1.0e-9 and l2 >= -1.0e-9

  # The weights of the place of a triangle nearest (about) to a place with these weights: none less than 0.
  defp inside({a, b, c}) do
    {a, b, c} = {max(a, 0.0), max(b, 0.0), max(c, 0.0)}
    sum = a + b + c
    {a / sum, b / sum, c / sum}
  end

  defp mix({p0, p1, p2}, {l0, l1, l2}), do: Vec.add(Vec.add(Vec.scale(p0, l0), Vec.scale(p1, l1)), Vec.scale(p2, l2))

  # The weights of the three corners at a texel.
  defp weights(%{corner: {x0, y0}, sides: {d1x, d1y, d2x, d2y}}, i, j) do
    {x, y} = {i + 0.5 - x0, j + 0.5 - y0}
    {l1, l2} = {x * d2y - d2x * y, d1x * y - x * d1y}
    {1 - l1 - l2, l1, l2}
  end

  # The tangent, the bitangent and the normal of a corner: the tangent is
  # the direction of +u (`t`) at a right angle to the normal; the
  # bitangent is their cross product, away from +v (`b`): up in the image.
  defp frame(n, t, b) do
    t = Vec.sub(t, Vec.scale(n, Vec.dot(n, t)))

    t =
      if Vec.len(t) > 1.0e-9,
        do: Vec.norm(t),
        else: Vec.norm(Vec.cross(n, if(abs(elem(n, 0)) < 0.9, do: {1.0, 0.0, 0.0}, else: {0.0, 1.0, 0.0})))

    side = Vec.cross(n, t)
    {t, if(Vec.dot(side, b) > 0, do: Vec.scale(side, -1.0), else: side), n}
  end

  # The three bytes of the normal of a texel at the place `p` with the
  # value `f`: the gradient of the field there, in the frame of the
  # texel.
  #
  # The gradient is the vector that gives best the changes of the value
  # to the four texels next to the texel (each at its own place on the
  # surface: a texel of another triangle of the patch is on another
  # plane) and to one place off the plane (the least squares). A texel
  # next to it with no value (past the edge of the patch) has the value
  # at its place on the plane of this triangle.
  defp normal(%{long: true} = c, _i, _j, {p, _f, weights}, _values), do: direct(c, p, weights)

  defp normal(c, i, j, {p, f, weights}, values) do
    off = Vec.scale(c.face, c.off)

    steps =
      for {di, dj} <- [{1, 0}, {-1, 0}, {0, 1}, {0, -1}] do
        case values[{i + di, j + dj}] do
          {_, q, g, _, _} -> {Vec.sub(q, p), g - f}
          nil -> (fn q -> {Vec.sub(q, p), SDF.value(c.fast, q, c.limit) - f} end).(at(c, i + di, j + dj))
        end
      end

    bytes(c, slope([{off, SDF.value(c.fast, Vec.add(p, off), c.limit) - f} | steps]), weights)
  end

  # The vector `g` with the least squares of `g . move - change` for the
  # moves and the changes. A small pull to no slope makes the answer
  # sure when the moves do not give all of it (the texels next to a
  # texel of a thin triangle can be on one line): the slope is then 0
  # in the direction that they do not give.
  defp slope(steps) do
    {{xx, xy, xz, yy, yz, zz}, {bx, by, bz}} =
      Enum.reduce(steps, {{0.0, 0.0, 0.0, 0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}}, fn {{x, y, z}, d},
                                                                               {{xx, xy, xz, yy, yz, zz}, {bx, by, bz}} ->
        {{xx + x * x, xy + x * y, xz + x * z, yy + y * y, yz + y * z, zz + z * z}, {bx + x * d, by + y * d, bz + z * d}}
      end)

    pull = 1.0e-6 * (xx + yy + zz) + 1.0e-300
    {xx, yy, zz} = {xx + pull, yy + pull, zz + pull}
    # The rule of Cramer for the symmetric matrix.
    det = xx * (yy * zz - yz * yz) - xy * (xy * zz - yz * xz) + xz * (xy * yz - yy * xz)

    {(bx * (yy * zz - yz * yz) - xy * (by * zz - yz * bz) + xz * (by * yz - yy * bz)) / det,
     (xx * (by * zz - yz * bz) - bx * (xy * zz - yz * xz) + xz * (xy * bz - by * xz)) / det,
     (xx * (yy * bz - by * yz) - xy * (xy * bz - by * xz) + bx * (xy * yz - yy * xz)) / det}
  end

  # The normal of a texel of a long chart (a texel is more than a cell
  # from the next one): the gradient from four values at the corners of
  # a small tetrahedron round its place.
  defp direct(c, p, weights) do
    h = max(c.off, 1.0e-7)

    gradient =
      for {x, y, z} = k <- @tetrahedron, reduce: {0.0, 0.0, 0.0} do
        sum -> Vec.add(sum, Vec.scale(k, SDF.value(c.fast, Vec.add(p, {x * h, y * h, z * h}), c.limit)))
      end

    bytes(c, gradient, weights)
  end

  # The bytes of a gradient in the frame of the chart at the weights of its corners.
  defp bytes(c, gradient, {l0, l1, l2}) do
    [f0, f1, f2] = c.frames
    mean = fn k -> mean(elem(f0, k), elem(f1, k), elem(f2, k), l0, l1, l2) end
    {t, b, n} = {mean.(0), mean.(1), mean.(2)}
    m = if Vec.len(gradient) > 1.0e-9, do: Vec.norm(gradient), else: n

    {x, y, z} = in_frame(m, t, b, n)
    # A normal to the back of the face (the field turns in less than a
    # texel) stays at the side of the face.
    <<byte(x), byte(y), byte(max(z, 0.0))>>
  end

  @doc """
  The three numbers of the vector `m` in the frame of `t`, `b` and `n`
  (`m = x t + y b + z n`, by the rule of Cramer), as a unit vector; `{0,
  0, 1}` for a frame with no volume.
  """
  def in_frame(m, t, b, n) do
    det = Vec.dot(t, Vec.cross(b, n))

    if abs(det) < 1.0e-9 do
      {0.0, 0.0, 1.0}
    else
      Vec.norm(
        {Vec.dot(m, Vec.cross(b, n)) / det, Vec.dot(t, Vec.cross(m, n)) / det, Vec.dot(t, Vec.cross(b, m)) / det}
      )
    end
  end

  defp mean(a, b, c, la, lb, lc),
    do: Vec.norm(Vec.add(Vec.add(Vec.scale(a, la), Vec.scale(b, lb)), Vec.scale(c, lc)))

  defp byte(v), do: min(max(round((v * 0.5 + 0.5) * 255), 0), 255)

  # --- The image --------------------------------------------------------------

  # The rows of the image from the rows of the squares (`which`: 0 for the
  # colors, 1 for the normals), with `blank` where no square is.
  defp image(done, side, which, blank) do
    by_row = Enum.group_by(done, fn {{_, y}, _, _} -> y end)
    fill = fn count -> :binary.copy(blank, count) end

    {rows, y} =
      by_row
      |> Enum.sort()
      |> Enum.reduce({[], 0}, fn {y, squares}, {rows, _} ->
        squares = Enum.sort(squares)
        height = squares |> Enum.map(fn {_, {_, h}, _} -> h end) |> Enum.max()
        width = squares |> Enum.map(fn {_, {w, _}, _} -> w end) |> Enum.sum()
        parts = for {_, {w, h}, texels} <- squares, do: {w, h, List.to_tuple(elem(texels, which))}

        new =
          for r <- 0..(height - 1) do
            [for({w, h, t} <- parts, do: if(r < h, do: elem(t, r), else: fill.(w))), fill.(side - width)]
            |> IO.iodata_to_binary()
          end

        {[new | rows], y + height}
      end)

    Enum.concat(Enum.reverse(rows)) ++ List.duplicate(fill.(side), side - y)
  end
end
