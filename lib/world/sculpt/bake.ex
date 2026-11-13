defmodule World.Sculpt.Bake do
  @moduledoc """
  The maps of a sculpture (`docs/plans/0010-sculpture-maps.md`, D1 to
  D4): a color map and a normal map for its meshes, made from the field
  of its edits at each texel. So the detail of the model is the detail
  of the edits at the size of a texel, not at the size of a cell or of a
  triangle.

  **A chart for each triangle.** A triangle has a right triangle of
  texels, two in a square of `n` texels on a side. The first is at the
  corner of the square, the second is the first turned by a half turn.
  The legs of a triangle are `n - 4` texels; each texel of the square
  belongs to the triangle on its side of the diagonal, so each chart has
  a border of one texel or more with the values of the field past its
  edges, and a texel of one chart is never in the next one. The legs
  follow the area of the triangle; the squares go into the image in
  rows, the largest first, and the scale is the largest one that fits.

  **A texel** is a place on the plane of its triangle. Its color is the
  color of the edits there (`World.SDF.sample/3`). Its normal is the
  gradient of the field there: the change of the value to the next
  texels of the chart gives the part in the plane, and one value off the
  plane gives the rest. The edits of a triangle are the edits that reach
  its ball (`World.SDF.prune/4`), so a texel takes two values of a short
  list.

  **The normal map** has the normal in the tangent space of glTF: at a
  texel, the tangent, the bitangent and the normal are the means of
  those of the three corners of the triangle, as an app makes them. The
  tangent of a corner is the direction of +u in the chart, at a right
  angle to the normal of the corner, with the rule of `World.GLB` for
  its sign.
  """

  alias World.{Mesh, SDF, Sculpt, Vec}

  # The least and the most legs of a chart, in texels.
  @least 2
  @most 252
  # The squares of one process.
  @group 24
  # The texel of a place with no chart: a mean gray, and the normal of the face.
  @gray <<128, 128, 128>>
  @flat <<128, 128, 255>>
  # The finish of a place with no chart: rough, no metal (the red is not in use).
  @plain <<255, 153, 0>>

  @doc """
  The least side of an image (texels) for `faces` triangles: each pair
  of triangles needs a square of 6 texels, and the rows lose some.
  """
  def least(faces), do: ceil(:math.sqrt(faces * 18 * 1.1)) + 6

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
  def maps(meshes, edits, step, side), do: maps([{meshes, edits, step}], side)

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
  """
  def maps(parts, side, defaults \\ %{}) do
    colors? = Enum.any?(parts, fn {_, edits, _} -> Enum.any?(edits, & &1.color) end)
    finish? = Enum.any?(parts, fn {_, edits, _} -> SDF.finished?(edits) end)
    glow? = Enum.any?(parts, fn {_, edits, _} -> Enum.any?(edits, &((&1.glow || 0.0) > 0.0)) end)
    # The finish of the materials, when a texel needs it (nil with no finish of an edit).
    defaults = if finish?, do: defaults
    meshes = Enum.flat_map(parts, &elem(&1, 0))
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

      squares ->
        # The legs of the chart of each triangle: its texels go 1.5 texels past its corners.
        legs = for s <- squares, t <- [s.lower, s.upper], t != nil, into: %{}, do: {t.id, s.n - 4}

        lists =
          triangles
          |> Enum.group_by(fn %{id: {mi, _}} -> mi end)
          |> Enum.map(fn {mi, group} -> lists(group, legs, elem(fields, mi)) end)
          |> Enum.reduce(&Map.merge/2)

        all = List.to_tuple(edits)

        # A message is a copy: a process gets the edits of its squares one
        # time, and the short list of each triangle as places in them.
        done =
          squares
          |> Enum.chunk_every(@group)
          |> Stream.map(fn group ->
            used = for(s <- group, t <- [s.lower, s.upper], t != nil, i <- Map.fetch!(lists, t.id), uniq: true, do: i)
            place = used |> Enum.with_index() |> Map.new()
            listed = fn t -> t && Map.put(t, :list, Enum.map(Map.fetch!(lists, t.id), &Map.fetch!(place, &1))) end

            {Enum.map(used, &elem(all, &1)),
             Enum.map(group, &%{&1 | lower: listed.(&1.lower), upper: listed.(&1.upper)})}
          end)
          |> Task.async_stream(
            fn {some, group} ->
              some = List.to_tuple(some)
              edits = fn t -> t && %{t | list: Enum.map(t.list, &elem(some, &1))} end
              for s <- group, do: {s.at, s.n, texels(%{s | lower: edits.(s.lower), upper: edits.(s.upper)}, defaults)}
            end,
            max_concurrency: System.schedulers_online(),
            timeout: :infinity
          )
          |> Enum.flat_map(fn {:ok, group} -> group end)

        uvs =
          for s <- squares,
              {t, half} <- [{s.lower, :lower}, {s.upper, :upper}],
              t != nil,
              into: %{},
              do: {t.id, uv(s, half, side)}

        meshes =
          for {m, mi} <- Enum.with_index(meshes) do
            # Each corner takes the normal of its point: the normal map has the hard edges.
            Mesh.map(
              %{m | colors: nil, angle: 180.0},
              for({_, fi} <- Enum.with_index(m.faces), do: Map.fetch!(uvs, {mi, fi}))
            )
          end

        {meshes,
         %{
           side: side,
           color: if(colors?, do: image(done, side, 0, @gray)),
           normal: image(done, side, 1, @flat),
           finish: if(finish?, do: image(done, side, 2, @plain)),
           glow: if(glow?, do: image(done, side, 3, <<0, 0, 0>>))
         }}
    end
  end

  # --- The charts -------------------------------------------------------------

  # The squares of the triangles in the image: `[%{at: {x, y}, n: n,
  # lower: triangle, upper: triangle or nil}]`, at the largest scale that
  # fits (a search by halves), or `:small`.
  defp pack(triangles, side) do
    if place(triangles, 0.0, side) == :small do
      :small
    else
      mean = Enum.sum(Enum.map(triangles, &:math.sqrt(2 * &1.area))) / max(length(triangles), 1)
      high = @most / max(mean, 1.0e-9)

      {scale, _} =
        Enum.reduce(1..24, {0.0, high}, fn _, {lo, hi} ->
          mid = (lo + hi) / 2
          if place(triangles, mid, side) == :small, do: {lo, mid}, else: {mid, hi}
        end)

      place(triangles, scale, side)
    end
  end

  # The squares at a scale (texels for each meter), in rows.
  defp place(triangles, scale, side) do
    sized =
      triangles
      |> Enum.map(&{legs(&1.area, scale), &1})
      |> Enum.sort_by(fn {legs, t} -> {-legs, t.id} end)
      |> Enum.chunk_every(2)

    {squares, _, y, height} =
      Enum.reduce(sized, {[], 0, 0, 0}, fn [{legs, lower} | rest], {squares, x, y, height} ->
        n = legs + 4
        upper = with [{_, t}] <- rest, do: t, else: (_ -> nil)
        # A new row when the square does not fit in this one.
        {x, y, height} = if x + n > side, do: {0, y + height, n}, else: {x, y, max(height, n)}
        {[%{at: {x, y}, n: n, lower: lower, upper: upper} | squares], x + n, y, height}
      end)

    if y + height > side, do: :small, else: Enum.reverse(squares)
  end

  # The legs of the chart of a triangle (an even count of texels): the
  # legs of a right triangle of its area, at the scale.
  defp legs(area, scale), do: min(max(2 * round(scale * :math.sqrt(2 * area) / 2), @least), @most)

  # The UVs of the three corners of a triangle in its square (v down
  # from the top of the image).
  defp uv(%{at: {x, y}, n: n}, :lower, side),
    do: for({i, j} <- [{1, 1}, {n - 3, 1}, {1, n - 3}], do: {(x + i) / side, (y + j) / side})

  defp uv(%{at: {x, y}, n: n}, :upper, side),
    do: for({i, j} <- [{n - 1, n - 1}, {3, n - 1}, {n - 1, 3}], do: {(x + i) / side, (y + j) / side})

  # --- The edits of each triangle ---------------------------------------------

  # The short list of each triangle: the edits that reach its ball (their
  # places in the list of the edits). First
  # the edits of each cube of a grid of the triangles (a cube of 8 times
  # the mean size of a triangle), then the edits of each triangle from
  # the list of its cube.
  defp lists(triangles, legs, %{edits: edits, limit: limit, first: first}) do
    balls = for t <- triangles, do: {t.id, ball(t, legs[t.id])}
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
      timeout: :infinity
    )
    |> Enum.flat_map(fn {:ok, group} -> group end)
    |> Map.new()
  end

  # The ball of the texels of a triangle: its center, and the most
  # distance to a corner of its chart with its border (1.5 texels past
  # each corner of the triangle, for legs of that many texels; a small
  # chart goes far past its triangle), and a part more for the value off
  # the plane.
  defp ball(%{points: {p0, p1, p2}}, legs) do
    c = Vec.scale(Vec.add(Vec.add(p0, p1), p2), 1 / 3)
    far = Enum.max(for p <- [p0, p1, p2], do: Vec.len(Vec.sub(p, c)))
    {c, far * (1 + 4.5 / legs) * 1.1 + 1.0e-9}
  end

  # --- The texels of a square -------------------------------------------------

  # The rows of a square: `{colors, normals}`, each a list of `n`
  # binaries from the top.
  defp texels(%{n: n, lower: lower, upper: upper}, defaults) do
    charts = {chart(lower, :lower, n), upper && chart(upper, :upper, n)}
    owner = fn i, j -> if i + j <= n - 2, do: elem(charts, 0), else: elem(charts, 1) end
    # The texels (i, j) and (k, l) are of one chart.
    same = fn i, j, k, l -> i + j <= n - 2 == k + l <= n - 2 end

    # The value and the color of the field at each texel of the square.
    values =
      for j <- 0..(n - 1), i <- 0..(n - 1), c = owner.(i, j), c != nil, c.flat == false, into: %{} do
        p = at(c, i, j)
        {{i, j}, SDF.sample(c.list, p, c.limit)}
      end

    rows =
      for j <- 0..(n - 1) do
        for i <- 0..(n - 1), reduce: {<<>>, <<>>, <<>>, <<>>} do
          {colors, normals, finishes, glows} ->
            case {owner.(i, j), values[{i, j}]} do
              {c, {f, {r, g, b}}} ->
                # The finish of the texel, with the finish of an edit only.
                {finish, glow} = if defaults, do: finish(c, i, j, {r, g, b}, defaults), else: {<<>>, <<>>}

                {<<colors::binary, r, g, b>>, <<normals::binary, normal(c, i, j, f, values, same)::binary>>,
                 <<finishes::binary, finish::binary>>, <<glows::binary, glow::binary>>}

              _ ->
                {<<colors::binary, @gray::binary>>, <<normals::binary, @flat::binary>>,
                 <<finishes::binary, @plain::binary>>, <<glows::binary, 0, 0, 0>>}
            end
        end
      end

    {Enum.map(rows, &elem(&1, 0)), Enum.map(rows, &elem(&1, 1)), Enum.map(rows, &elem(&1, 2)),
     Enum.map(rows, &elem(&1, 3))}
  end

  # The bytes of the finish of a texel (the roughness in the green, the
  # metal in the blue), and of its glow (its color times its glow).
  defp finish(c, i, j, {r, g, b}, defaults) do
    {rough, metal, glow} = SDF.finish(c.list, at(c, i, j), defaults)
    {<<255, round(rough * 255), round(metal * 255)>>, <<round(r * glow), round(g * glow), round(b * glow)>>}
  end

  # The chart of a triangle in a square of n texels: the place of a
  # texel is `base + i u + j v`; and the frames of its corners.
  defp chart(%{points: {p0, p1, p2}, normals: {n0, n1, n2}, list: list, limit: limit, step: step}, half, n) do
    legs = n - 4
    {e1, e2} = {Vec.sub(p1, p0), Vec.sub(p2, p0)}
    cross = Vec.cross(e1, e2)

    if Vec.len(cross) < 1.0e-18 do
      %{flat: true}
    else
      face = Vec.norm(cross)
      # The first chart: the corner at the texel (1, 1). The second one:
      # at (n - 1, n - 1), with its legs to the other side.
      {sign, first} = if half == :lower, do: {1.0, -0.5}, else: {-1.0, n - 1.5}
      {u, v} = {Vec.scale(e1, sign / legs), Vec.scale(e2, sign / legs)}
      base = Vec.add(p0, Vec.scale(Vec.add(e1, e2), first / legs))
      {uu, uv, vv} = {Vec.dot(u, u), Vec.dot(u, v), Vec.dot(v, v)}
      det = uu * vv - uv * uv
      off = min(:math.sqrt(:math.sqrt(uu * vv)) / 2, step / 2)

      %{
        flat: false,
        half: half,
        legs: legs,
        n: n,
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
        face: face,
        off: off,
        frames: for(k <- [n0, n1, n2], do: frame(k, Vec.scale(e1, sign), Vec.scale(e2, sign)))
      }
    end
  end

  # The place of a texel of a chart.
  defp at(c, i, j), do: Vec.add(c.base, Vec.add(Vec.scale(c.u, i * 1.0), Vec.scale(c.v, j * 1.0)))

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

  # The three bytes of the normal of a texel: the gradient of the field
  # there, in the frame of the texel.
  defp normal(c, i, j, f, values, same) do
    # The change of the value for one texel along a side of the square:
    # from the texels on the two sides. At the edge of the chart, the
    # next texel is of the other chart: the value at that place then.
    value = fn k, l ->
      with true <- same.(i, j, k, l), {g, _} <- values[{k, l}] do
        g
      else
        _ -> SDF.value(c.fast, at(c, k, l), c.limit)
      end
    end

    slope = fn di, dj -> (value.(i + di, j + dj) - value.(i - di, j - dj)) / 2 end

    p = at(c, i, j)
    up = (SDF.value(c.fast, Vec.add(p, Vec.scale(c.face, c.off)), c.limit) - f) / c.off

    gradient =
      Vec.add(Vec.add(Vec.scale(c.du, slope.(1, 0)), Vec.scale(c.dv, slope.(0, 1))), Vec.scale(c.face, up))

    # The weights of the three corners at the texel.
    {l1, l2} =
      if c.half == :lower,
        do: {(i - 0.5) / c.legs, (j - 0.5) / c.legs},
        else: {(c.n - 1.5 - i) / c.legs, (c.n - 1.5 - j) / c.legs}

    [f0, f1, f2] = c.frames
    mean = fn k -> mean(elem(f0, k), elem(f1, k), elem(f2, k), 1 - l1 - l2, l1, l2) end
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
        height = squares |> Enum.map(&elem(&1, 1)) |> Enum.max()
        width = squares |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        parts = for {_, n, texels} <- squares, do: {n, List.to_tuple(elem(texels, which))}

        new =
          for r <- 0..(height - 1) do
            [for({n, t} <- parts, do: if(r < n, do: elem(t, r), else: fill.(n))), fill.(side - width)]
            |> IO.iodata_to_binary()
          end

        {[new | rows], y + height}
      end)

    Enum.concat(Enum.reverse(rows)) ++ List.duplicate(fill.(side), side - y)
  end
end
