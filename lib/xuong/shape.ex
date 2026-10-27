defmodule Xuong.Shape do
  @moduledoc """
  The shapes that make the meshes of parts. Each function gives a closed
  `Xuong.Mesh` with its faces to the outside.

  Most functions take a `frame` option (`Xuong.Frame`): the shape is made
  in its own axes, then the frame puts it in the axes of the part. Each
  function also takes the options of `Xuong.Mesh.new/4` (`smooth`,
  `angle`).
  """
  alias Xuong.{Detail, Frame, Mesh, Vec}

  @doc """
  A box from its two corners. With `round: e` (0 < e < 0.5), the box has
  edge loops at the part `e` of each side, and `smooth: 2` gives round
  edges that keep the shape of the box.
  """
  def box({x0, y0, z0}, {x1, y1, z1}, material, opts \\ []) do
    cage(
      [{x0, y0, z0}, {x1, y0, z0}, {x1, y1, z0}, {x0, y1, z0}, {x0, y0, z1}, {x1, y0, z1}, {x1, y1, z1}, {x0, y1, z1}],
      material,
      opts
    )
  end

  @doc """
  A cage of 8 corners: 0 to 3 at the bottom and 4 to 7 at the top, each
  counterclockwise from above. The `round` option is as for `box/4`.
  """
  def cage(corners, material, opts \\ []) do
    ts =
      case Keyword.get(opts, :round) do
        nil -> [0.0, 1.0]
        e -> [0.0, e, 1.0 - e, 1.0]
      end

    c = List.to_tuple(Enum.map(corners, &Vec.float/1))
    last = length(ts) - 1

    at = fn u, v, w ->
      bottom = Vec.lerp(Vec.lerp(elem(c, 0), elem(c, 1), u), Vec.lerp(elem(c, 3), elem(c, 2), u), v)
      top = Vec.lerp(Vec.lerp(elem(c, 4), elem(c, 5), u), Vec.lerp(elem(c, 7), elem(c, 6), u), v)
      Vec.lerp(bottom, top, w)
    end

    keys =
      for i <- 0..last, j <- 0..last, k <- 0..last, i in [0, last] or j in [0, last] or k in [0, last], do: {i, j, k}

    index = keys |> Enum.with_index() |> Map.new()
    t = List.to_tuple(ts)
    points = for {i, j, k} <- keys, do: at.(elem(t, i), elem(t, j), elem(t, k))

    faces =
      for {axis, side} <- [{0, 0}, {0, last}, {1, 0}, {1, last}, {2, 0}, {2, last}],
          a <- 0..(last - 1),
          b <- 0..(last - 1) do
        quad =
          for {da, db} <- [{0, 0}, {1, 0}, {1, 1}, {0, 1}],
              do: index[List.to_tuple(List.insert_at([a + da, b + db], axis, side))]

        # The order of the corners of a quad on a side at 0, and on the
        # side across from it, are opposite.
        flip = if axis == 1, do: side != 0, else: side == 0
        if flip, do: Enum.reverse(quad), else: quad
      end

    place(Mesh.new(points, Mesh.outside(points, faces), material, opts), opts)
  end

  @doc """
  A prism: a loop of points `{x, y}` (counterclockwise from +z, convex or
  not) from z = 0 to z = `length`, in the axes of `frame`.
  """
  def prism(loop, length, material, opts \\ []) do
    n = length(loop)
    points = for z <- [0.0, length / 1], {x, y} <- loop, do: {x / 1, y / 1, z}
    sides = for k <- 0..(n - 1), do: [k, rem(k + 1, n), n + rem(k + 1, n), n + k]
    faces = [Enum.to_list((n - 1)..0//-1), Enum.to_list(n..(2 * n - 1)) | sides]
    place(Mesh.new(points, Mesh.outside(points, faces), material, opts), opts)
  end

  @doc "A regular polygon of `n` sides around the origin, of radius `r` (to its corners)."
  def polygon(r, n, turn \\ 0.0) do
    for k <- 0..(n - 1) do
      a = turn * :math.pi() / 180 + 2 * :math.pi() * k / n
      {r * :math.cos(a), r * :math.sin(a)}
    end
  end

  @doc "A cylinder of radius `r` from z = 0 to z = `length` (option `sides`, 24 by default)."
  def cylinder(r, length, material, opts \\ []) do
    prism(polygon(r, Detail.sides(Keyword.get(opts, :sides, 24))), length, material, opts)
  end

  @doc """
  A lathe: a profile of points `{r, z}` turns around the z axis.

  - `kind: :solid` (by default): the profile goes from one end to the
    other. An end with r = 0 is a point on the axis, else a flat cap.
  - `kind: :ring`: the profile is a closed loop (a tire, a washer).
  """
  def lathe(profile, material, opts \\ []) do
    n = Detail.sides(Keyword.get(opts, :sides, 24))

    ring = fn {r, z} ->
      for k <- 0..(n - 1), do: {r * :math.cos(2 * :math.pi() * k / n), r * :math.sin(2 * :math.pi() * k / n), z / 1}
    end

    {points, faces} =
      case Keyword.get(opts, :kind, :solid) do
        :ring -> ring_lathe(Enum.map(profile, ring), n)
        :solid -> solid_lathe(profile, ring, n)
      end

    place(Mesh.new(points, Mesh.outside(points, faces), material, opts), opts)
  end

  defp ring_lathe(rings, n) do
    m = length(rings)
    points = List.flatten(rings)
    faces = for j <- 0..(m - 1), k <- 0..(n - 1), do: quad(j, rem(j + 1, m), k, rem(k + 1, n), n)
    {points, faces}
  end

  defp solid_lathe(profile, ring, n) do
    # The rings in the middle, and at each end a pole (r = 0) or a cap.
    {first, last} = {hd(profile), List.last(profile)}
    middle = profile |> Enum.drop(if pole?(first), do: 1, else: 0) |> Enum.drop(if pole?(last), do: -1, else: 0)
    rings = Enum.map(middle, ring)
    m = length(rings)
    points = List.flatten(rings)
    sides = for j <- 0..(m - 2)//1, k <- 0..(n - 1), do: quad(j, j + 1, k, rem(k + 1, n), n)
    {points, start} = end_faces(points, first, 0, n, :start)
    {points, finish} = end_faces(points, last, (m - 1) * n, n, :finish)
    {points, start ++ finish ++ sides}
  end

  defp pole?({r, _}), do: abs(r) < 1.0e-9

  defp end_faces(points, {_, z} = p, base, n, which) do
    if pole?(p) do
      i = length(points)

      fan =
        for k <- 0..(n - 1),
            do: if(which == :start, do: [i, base + rem(k + 1, n), base + k], else: [i, base + k, base + rem(k + 1, n)])

      {points ++ [{0.0, 0.0, z / 1}], fan}
    else
      cap = Enum.to_list(base..(base + n - 1))
      {points, [if(which == :start, do: Enum.reverse(cap), else: cap)]}
    end
  end

  defp quad(j, j1, k, k1, n), do: [j * n + k, j * n + k1, j1 * n + k1, j1 * n + k]

  @doc "A sphere of radius `r` (options `sides` and `rings`)."
  def sphere(r, material, opts \\ []) do
    rings = Detail.sides(Keyword.get(opts, :rings, 12))
    profile = for i <- 0..rings, do: {r * :math.sin(:math.pi() * i / rings), -r * :math.cos(:math.pi() * i / rings)}
    lathe(profile, material, opts)
  end

  @doc """
  A loft: a ring for each section, and a flat cap at each end. A section
  is `{center, u, v, half_u, half_v, power}`: a superellipse in the plane
  of the directions `u` and `v` (power 2 is an ellipse, 4 is a box with
  round corners). Option `sides`: the points of each ring (16).
  """
  def loft(sections, material, opts \\ []) do
    n = Detail.sides(Keyword.get(opts, :sides, 16))

    rings =
      for {c, u, v, hu, hv, p} <- sections do
        for k <- 0..(n - 1) do
          t = 2 * :math.pi() * k / n

          Vec.add(
            Vec.add(Vec.float(c), Vec.scale(u, hu * curve(:math.cos(t), p))),
            Vec.scale(v, hv * curve(:math.sin(t), p))
          )
        end
      end

    m = length(sections)
    points = List.flatten(rings)
    sides = for j <- 0..(m - 2), k <- 0..(n - 1), do: quad(j, j + 1, k, rem(k + 1, n), n)
    caps = [Enum.to_list((n - 1)..0//-1), Enum.to_list(((m - 1) * n)..(m * n - 1))]
    place(Mesh.new(points, Mesh.outside(points, caps ++ sides), material, opts), opts)
  end

  @doc """
  Loft sections along y (the side and the top of a body): each row is
  `{y, z_low, z_high, half_width, power}`, centered at x = `x0`.
  """
  def rows_y(rows, x0 \\ 0.0),
    do:
      for(
        {y, z0, z1, hw, p} <- rows,
        do: {{x0, y, (z0 + z1) / 2}, {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, hw, (z1 - z0) / 2, p}
      )

  @doc "Loft sections along z (a shield that stands): each row is `{z, y_back, y_front, half_width, power}`."
  def rows_z(rows, x0 \\ 0.0),
    do:
      for(
        {z, y0, y1, hw, p} <- rows,
        do: {{x0, (y0 + y1) / 2, z}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, hw, (y1 - y0) / 2, p}
      )

  @doc """
  Loft sections on an arc around an axis along x (a fender over a wheel):
  from the angle `a0` to `a1` (degrees from up, to the front), at a
  radius around the point `{y, z}`, each section `half_width` by
  `half_thickness`.
  """
  def arc({cy, cz}, radius, a0, a1, steps, hw, ht, p \\ 4) do
    for i <- 0..steps do
      a = (a0 + (a1 - a0) * i / steps) * :math.pi() / 180
      out = {0.0, :math.sin(a), :math.cos(a)}
      {Vec.add({0.0, cy / 1, cz / 1}, Vec.scale(out, radius)), {1.0, 0.0, 0.0}, out, hw, ht, p}
    end
  end

  defp curve(t, p), do: if(t < 0, do: -1, else: 1) * :math.pow(abs(t), 2 / p)

  @doc """
  A tube of radius `r` along a line of points (a frame of a bicycle, a
  bar, a cable), with a flat cap at each end. Option `sides` (8). The
  ring at a bend lies on the plane between the two segments.
  """
  def sweep([_, _ | _] = line, r, material, opts \\ []) do
    n = Detail.sides(Keyword.get(opts, :sides, 8))
    line = Enum.map(line, &Vec.float/1)
    dirs = line |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> Vec.norm(Vec.sub(b, a)) end)
    # The direction in and out of each point.
    ins = [hd(dirs) | dirs]
    outs = dirs ++ [List.last(dirs)]

    # A frame that moves along the line with no twist.
    {rings, _} =
      Enum.zip([line, ins, outs])
      |> Enum.map_reduce(Vec.perpendicular(hd(dirs)), fn {p, din, dout}, prev ->
        t = Vec.norm(Vec.add(din, dout))
        side = Vec.norm(Vec.sub(prev, Vec.scale(t, Vec.dot(prev, t))))
        up = Vec.cross(t, side)
        stretch = miter(t, din, dout)
        ring = for j <- 0..(n - 1), do: Vec.add(p, stretch.(ring_offset(side, up, r, 2 * :math.pi() * j / n)))
        {ring, side}
      end)

    m = length(rings)
    points = List.flatten(rings)
    sides = for j <- 0..(m - 2), k <- 0..(n - 1), do: quad(j, j + 1, k, rem(k + 1, n), n)
    caps = [Enum.to_list((n - 1)..0//-1), Enum.to_list(((m - 1) * n)..(m * n - 1))]
    place(Mesh.new(points, Mesh.outside(points, caps ++ sides), material, opts), opts)
  end

  defp ring_offset(side, up, r, a), do: Vec.add(Vec.scale(side, r * :math.cos(a)), Vec.scale(up, r * :math.sin(a)))

  # At a bend, the ring lies on the plane between the two segments: it is
  # longer in the direction of the bend, so that the tube keeps its radius.
  defp miter(t, din, dout) do
    bend = Vec.sub(dout, din)
    bend = Vec.sub(bend, Vec.scale(t, Vec.dot(bend, t)))

    if Vec.len(bend) < 1.0e-9 do
      & &1
    else
      b = Vec.norm(bend)
      k = 1 / max(Vec.dot(t, din), 0.2) - 1
      fn off -> Vec.add(off, Vec.scale(b, Vec.dot(off, b) * k)) end
    end
  end

  # The mesh in the axes of the frame option.
  defp place(mesh, opts) do
    case Keyword.get(opts, :frame) do
      nil -> mesh
      %Frame{} = f -> Mesh.transform(mesh, f)
    end
  end
end
