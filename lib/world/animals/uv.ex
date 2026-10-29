defmodule World.Animals.UV do
  @moduledoc """
  The UV coordinates of a template: charts for each bone, from the
  template at rest. The UVs are for a texture that repeats (the noise of
  fur), not for a painted texture.

  - Each face goes to the bone that moves its corners most (the sum of
    the weights of its corners).
  - Each bone has six charts, one for each side of a box around it: the
    axes x and z of the bone, and its two ends (the axis y). A face goes
    to the chart of the axis that its normal is nearest to, flat on the
    plane at a right angle to that axis (a box projection). So no face
    turns over, and a length on a face is at most 1.73 times its length
    in UV, in one direction.
  - On the four charts of the sides, v is the length along the bone. On
    the bones of the body, the neck and the head (`pelvis`, `spine_`,
    `neck_`, `head`), v goes to the back of the animal; on the other
    bones (the legs, the tail, the ears), away from the body. So +v is
    the direction in which the fur lies.
  - One scale for all the charts: a length on the skin is the same length
    in UV. The charts go in rows into the square 0 to 1 (the tallest
    first), with a gap between them.
  """
  alias World.Vec

  @back ~r/^(pelvis|spine_|neck_|head$)/

  @doc """
  The UV of each corner of each face: a list for each face of `{u, v}`.
  `bones` are maps with `name`, `head` and `tail`; `weights` a bone to a
  map of a point to its weight.
  """
  def charts(bones, points, weights, faces) do
    points = List.to_tuple(points)
    by = Map.new(bones, &{&1.name, frame(&1)})

    owner =
      for {bone, m} <- weights, Map.has_key?(by, bone), {i, w} <- m, reduce: %{} do
        acc -> Map.update(acc, i, [{bone, w}], &[{bone, w} | &1])
      end

    # The bone of each face, and its chart: the axis of the bone nearest
    # to its normal. The corners flat on the plane of the chart, in the
    # order that keeps the turn of the face.
    placed =
      for f <- faces do
        bone =
          f
          |> Enum.flat_map(&Map.get(owner, &1, []))
          |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
          |> Enum.max_by(fn {b, ws} -> {Enum.sum(ws), b} end, fn -> {hd(bones).name, []} end)
          |> elem(0)

        corners = Enum.map(f, &elem(points, &1))
        {o, x, y, z} = by[bone]

        local =
          Enum.map(corners, fn p ->
            d = Vec.sub(p, o)
            {Vec.dot(d, x), Vec.dot(d, y), Vec.dot(d, z)}
          end)

        n = normal(corners)
        side = [{:x, Vec.dot(n, x)}, {:y, Vec.dot(n, y)}, {:z, Vec.dot(n, z)}] |> Enum.max_by(&abs(elem(&1, 1)))
        sign = if Regex.match?(@back, bone), do: -1, else: 1
        {{bone, side_name(side)}, Enum.map(local, &flat(side, &1, sign))}
      end

    pack(placed)
  end

  # The frame of a bone: its head, and its axes x (to the side), y (along
  # the bone) and z. A bone along the side takes z up in place of x.
  defp frame(%{head: head, tail: tail}) do
    y = Vec.norm(Vec.sub(tail, head))
    ref = if abs(elem(y, 0)) > 0.9, do: {0.0, 0.0, 1.0}, else: {1.0, 0.0, 0.0}
    x = Vec.norm(Vec.sub(ref, Vec.scale(y, Vec.dot(ref, y))))
    x = if abs(elem(y, 0)) > 0.9, do: Vec.cross(y, x), else: x
    {head, x, y, Vec.cross(x, y)}
  end

  # The normal of a face (Newell): the sum of the cross products of its
  # edges, as a unit.
  defp normal(corners) do
    corners
    |> Enum.zip(tl(corners) ++ [hd(corners)])
    |> Enum.reduce({0.0, 0.0, 0.0}, fn {a, b}, acc -> Vec.add(acc, Vec.cross(a, b)) end)
    |> Vec.norm()
  end

  defp side_name({axis, d}), do: {axis, d > 0}

  # A corner on the plane of its chart: for each side, the two axes of the
  # plane in the order that keeps the turn of a face that looks to that
  # side (u, v: v along the bone on the four sides).
  defp flat({axis, d}, {a, b, c}, sign) do
    {u, v} =
      case {axis, d > 0} do
        {:x, true} -> {-c, b}
        {:x, false} -> {c, b}
        {:z, true} -> {a, b}
        {:z, false} -> {-a, b}
        {:y, true} -> {c, a}
        {:y, false} -> {a, c}
      end

    {sign * u, sign * v}
  end

  # The charts in rows into the square 0 to 1, the tallest first, with a
  # gap between them: one scale for all.
  defp pack(placed) do
    boxes =
      placed
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {chart, faces} ->
        {us, vs} = faces |> Enum.concat() |> Enum.unzip()
        {u0, u1} = Enum.min_max(us)
        {v0, v1} = Enum.min_max(vs)
        {chart, {u0, v0, u1 - u0, v1 - v0}}
      end)

    area = boxes |> Map.values() |> Enum.map(fn {_, _, w, h} -> w * h end) |> Enum.sum()
    gap = 0.02 * :math.sqrt(area)
    width = max(1.2 * :math.sqrt(area), boxes |> Map.values() |> Enum.map(&elem(&1, 2)) |> Enum.max())

    {at, {_, row_top, row_height, used}} =
      boxes
      |> Enum.sort_by(fn {chart, {_, _, w, h}} -> {-h, -w, chart} end)
      |> Enum.map_reduce({0.0, 0.0, 0.0, 0.0}, fn {chart, {_, _, w, h}}, {x, top, row, used} ->
        {x, top, row} = if x > 0 and x + w > width, do: {0.0, top + row + gap, 0.0}, else: {x, top, row}
        {{chart, {x, top}}, {x + w + gap, top, max(row, h), max(used, x + w)}}
      end)

    at = Map.new(at)
    size = max(used, row_top + row_height)

    for {chart, corners} <- placed do
      {u0, v0, _, _} = boxes[chart]
      {x, y} = at[chart]
      Enum.map(corners, fn {u, v} -> {(u - u0 + x) / size, (v - v0 + y) / size} end)
    end
  end

  @doc """
  The length on the skin of one unit of UV: the square root of the area
  of the faces over their area in UV.
  """
  def size(points, faces, uvs) do
    points = List.to_tuple(points)

    {skin, flat} =
      faces
      |> Enum.zip(uvs)
      |> Enum.reduce({0.0, 0.0}, fn {f, u}, {skin, flat} ->
        ps = Enum.map(f, &elem(points, &1))
        {skin + area(ps), flat + area(Enum.map(u, fn {a, b} -> {a, b, 0.0} end))}
      end)

    :math.sqrt(skin / flat)
  end

  defp area([a | rest]) do
    rest
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [b, c] -> Vec.len(Vec.cross(Vec.sub(b, a), Vec.sub(c, a))) / 2 end)
    |> Enum.sum()
  end
end
