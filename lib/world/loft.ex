defmodule World.Loft do
  @moduledoc """
  The mold shop of the world (`docs/world.md`, step P6): a shell of one
  thickness over sections along a spine, as a mold gives it (a shell of
  ABS from an injection mold, a liner of EPS from a steam mold, a hull of
  glass fiber laid up in a mold).

  The spine is a line of points. At each point of the spine, a section is
  a superellipse `{half_u, half_v, power}` in the plane of the directions
  `u` and `v` (power 2 is an ellipse, 4 is a box with round corners), or a
  closed ring of points `{a, b}` (a measured section: a list of the same
  length at each point). A section of the half sizes 0 is an apex: one
  point (the crown of a dome).

  The directions move along the spine with no twist (a parallel
  transport): `u` starts at the option `up` (a direction perpendicular to
  the spine by default), and `v` is the tangent times `u`.

  The option `arc`: the part of each section, from the angle `a0` to `a1`
  (degrees from `u`, toward `v`; `{0, 360}` by default: a full ring). An
  open arc gives an open shell (the pan and the back of a seat).

  `shell/3` gives the closed mesh: the outside is the surface of the
  sections, and the inside is the thickness in from it, along the normal
  of the surface. A rim closes each open edge. `grow/2` moves the surface
  out along its normal (the outside of a layer over a surface).
  """
  alias World.{Detail, Mesh, Part, Vec}

  defstruct spine: [], sections: [], sides: 24, arc: {0.0, 360.0}, up: nil, rows: nil

  @doc """
  A loft of a spine (two or more points) and a section at each point. The
  options: `sides` (the points of a full ring, 24), `arc` and `up`.
  """
  def new([_, _ | _] = spine, sections, opts \\ []) do
    if length(spine) != length(sections),
      do: raise(ArgumentError, "a loft has a section at each point of its spine")

    {a0, a1} = Keyword.get(opts, :arc, {0, 360})

    %__MODULE__{
      spine: Enum.map(spine, &Vec.float/1),
      sections: Enum.map(sections, &section/1),
      sides: Keyword.get(opts, :sides, 24),
      arc: {a0 / 1, a1 / 1},
      up: Keyword.get(opts, :up)
    }
  end

  defp section({hu, hv, p}), do: {hu / 1, hv / 1, p / 1}
  defp section([{_, _}, _, _ | _] = ring), do: Enum.map(ring, fn {a, b} -> {a / 1, b / 1} end)

  @doc """
  The rows of the outside: a list of points for each point of the spine
  (one point for an apex), and the frames `{center, tangent, u, v}`.
  """
  def rows(%__MODULE__{rows: rows} = l) when is_list(rows), do: {rows, frames(l)}

  def rows(%__MODULE__{} = l) do
    frames = frames(l)
    n = columns(l)
    {a0, a1} = l.arc

    rows =
      for {{c, _t, u, v}, section} <- Enum.zip(frames, l.sections) do
        case section do
          ring when is_list(ring) ->
            for {a, b} <- ring, do: c |> Vec.add(Vec.scale(u, a)) |> Vec.add(Vec.scale(v, b))

          {hu, hv, _} when hu == 0 and hv == 0 ->
            [c]

          {hu, hv, p} ->
            for k <- 0..(n - 1) do
              a = (a0 + (a1 - a0) * k / if(full?(l), do: n, else: n - 1)) * :math.pi() / 180

              c
              |> Vec.add(Vec.scale(u, hu * curve(:math.cos(a), p)))
              |> Vec.add(Vec.scale(v, hv * curve(:math.sin(a), p)))
            end
        end
      end

    {rows, frames}
  end

  @doc """
  The loft of the surface `d` out from this one, along its normal (an
  apex moves along the spine). A negative `d` moves it in.
  """
  def grow(%__MODULE__{} = l, d) do
    {rows, frames} = rows(l)
    moved = for {row, j} <- Enum.with_index(rows), do: offset(row, j, rows, frames, l, -d)

    spine =
      for {{c, _, _, _}, row} <- Enum.zip(frames, moved), do: if(length(row) == 1, do: hd(row), else: c)

    %{l | rows: moved, spine: spine}
  end

  @doc """
  The closed mesh of the shell: `t` in from the outside (m), of a
  material. The options of `World.Mesh.new/4`.
  """
  def shell(%__MODULE__{} = l, t, material, opts \\ []) do
    {rows, frames} = rows(l)
    n = width(rows)
    m = length(rows)
    outer = rows
    inner = for {row, j} <- Enum.with_index(rows), do: offset(row, j, rows, frames, l, t)

    # The index of each point: the outside, then the inside.
    starts = rows |> Enum.map(&length/1) |> Enum.scan(0, &+/2) |> then(&[0 | Enum.drop(&1, -1)])
    total = Enum.sum(Enum.map(rows, &length/1))
    st = List.to_tuple(starts)
    size = List.to_tuple(Enum.map(rows, &length/1))
    o = fn j, k -> elem(st, j) + if(elem(size, j) == 1, do: 0, else: rem(k, n)) end
    i = fn j, k -> total + o.(j, k) end

    ks = if full?(l), do: 0..(n - 1), else: 0..(n - 2)//1

    quads =
      for j <- 0..(m - 2), k <- ks do
        [o.(j, k), o.(j, k + 1), o.(j + 1, k + 1), o.(j + 1, k)]
      end

    insides = for [a, b, c, d] <- quads, do: [d + total, c + total, b + total, a + total]

    ends =
      if(elem(size, 0) > 1, do: for(k <- ks, do: [o.(0, k + 1), o.(0, k), i.(0, k), i.(0, k + 1)]), else: []) ++
        if elem(size, m - 1) > 1,
          do: for(k <- ks, do: [o.(m - 1, k), o.(m - 1, k + 1), i.(m - 1, k + 1), i.(m - 1, k)]),
          else: []

    sides =
      if full?(l),
        do: [],
        else:
          for(j <- 0..(m - 2), do: [o.(j, 0), o.(j + 1, 0), i.(j + 1, 0), i.(j, 0)]) ++
            for(j <- 0..(m - 2), do: [o.(j + 1, n - 1), o.(j, n - 1), i.(j, n - 1), i.(j + 1, n - 1)])

    points = List.flatten(outer) ++ List.flatten(inner)
    faces = (quads ++ insides ++ ends ++ sides) |> Enum.map(&dedup/1) |> Enum.filter(&(length(&1) >= 3))
    Mesh.new(points, Mesh.outside(points, faces), material, opts)
  end

  @doc "The area of the outside (m2)."
  def area(%__MODULE__{} = l) do
    {rows, _} = rows(l)
    n = width(rows)
    ks = if full?(l), do: 0..(n - 1), else: 0..(n - 2)//1
    at = fn row, k -> if length(row) == 1, do: hd(row), else: Enum.at(row, rem(k, n)) end

    Enum.sum(
      for [r0, r1] <- Enum.chunk_every(rows, 2, 1, :discard), k <- ks do
        {a, b, c, d} = {at.(r0, k), at.(r0, k + 1), at.(r1, k + 1), at.(r1, k)}
        tri(a, b, c) + tri(a, c, d)
      end
    )
  end

  @doc """
  The part of a shell: its name, its kind, its ports, the thickness `t`
  and the material. The options: `matter` (the material of the mass when
  the material is a color), `sources`, and the options of `shell/4`. Its
  params: the area of the outside and the thickness.
  """
  def part(%__MODULE__{} = l, name, kind, ports, t, material, opts \\ []) do
    mesh = shell(l, t, material, Keyword.drop(opts, [:matter, :sources]))
    mesh = if m = opts[:matter], do: Mesh.matter(mesh, m), else: mesh

    Part.new(name, kind, [mesh], ports,
      params: %{"area" => Float.round(area(l), 4), "thickness" => t / 1},
      sources: Keyword.get(opts, :sources, [])
    )
  end

  # --- The frames and the normals ---------------------------------------------------------------

  defp full?(%{arc: {a0, a1}}), do: abs(a1 - a0 - 360) < 1.0e-9

  # The points of the widest row.
  defp width(rows), do: rows |> Enum.map(&length/1) |> Enum.max()

  defp columns(%__MODULE__{} = l) do
    n = Detail.sides(l.sides)
    if full?(l), do: n, else: n + 1
  end

  # The frames along the spine: the tangent at each point (between the
  # segments in and out), and u carried from point to point with no twist.
  defp frames(%__MODULE__{spine: spine, up: up}) do
    dirs = spine |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> Vec.norm(Vec.sub(b, a)) end)
    tangents = Enum.zip_with([hd(dirs) | dirs], dirs ++ [List.last(dirs)], &Vec.norm(Vec.add(&1, &2)))
    u0 = if up, do: Vec.float(up), else: Vec.perpendicular(hd(tangents))

    {frames, _} =
      Enum.zip(spine, tangents)
      |> Enum.map_reduce(u0, fn {c, t}, prev ->
        u = Vec.norm(Vec.sub(prev, Vec.scale(t, Vec.dot(prev, t))))
        {{c, t, u, Vec.cross(t, u)}, u}
      end)

    frames
  end

  # The points of a row moved `t` in from the outside, along the normal of
  # the surface (out from the spine). The normal of an apex is along the
  # spine.
  defp offset([apex], j, _rows, frames, _l, t) do
    {_, tangent, _, _} = Enum.at(frames, j)
    out = if j == 0, do: Vec.scale(tangent, -1.0), else: tangent
    [Vec.sub(apex, Vec.scale(out, t))]
  end

  defp offset(row, j, rows, frames, l, t) do
    {c, _, _, _} = Enum.at(frames, j)
    n = length(row)
    prev = Enum.at(rows, max(j - 1, 0))
    next = Enum.at(rows, min(j + 1, length(rows) - 1))
    at = fn r, k -> if length(r) == 1, do: hd(r), else: Enum.at(r, k) end

    for {p, k} <- Enum.with_index(row) do
      {k0, k1} =
        if full?(l), do: {rem(k - 1 + n, n), rem(k + 1, n)}, else: {max(k - 1, 0), min(k + 1, n - 1)}

      around = Vec.sub(Enum.at(row, k1), Enum.at(row, k0))
      along = Vec.sub(at.(next, k), at.(prev, k))
      normal = Vec.cross(around, along)
      normal = if Vec.len(normal) < 1.0e-12, do: Vec.sub(p, c), else: normal
      normal = Vec.norm(normal)
      normal = if Vec.dot(normal, Vec.sub(p, c)) < 0, do: Vec.scale(normal, -1.0), else: normal
      Vec.sub(p, Vec.scale(normal, t))
    end
  end

  # A face with no point twice in a row (a quad at an apex is a triangle).
  defp dedup(face) do
    face
    |> Enum.chunk_by(& &1)
    |> Enum.map(&hd/1)
    |> then(fn f -> if length(f) > 1 and hd(f) == List.last(f), do: Enum.drop(f, -1), else: f end)
  end

  defp tri(a, b, c), do: Vec.len(Vec.cross(Vec.sub(b, a), Vec.sub(c, a))) / 2

  defp curve(t, p), do: if(t < 0, do: -1, else: 1) * :math.pow(abs(t), 2 / p)
end
