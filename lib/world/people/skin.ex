defmodule World.People.Skin do
  @moduledoc """
  The skin of a person, so that it does not look like plastic:

  - `material/1`: a rough skin with less reflection (KHR_materials_specular),
    a red glow at the edges, where light goes into the skin and comes out
    (KHR_materials_sheen), and near, the pores (a normal texture that
    repeats).
  - `creases/1`: the creases of the skin (the corners of the eyes, the
    sides of the nose, the lips) are darker and warmer, as in a soft
    shadow: the colors of the points.
  - `pores/0`: the normal texture of the pores, which World makes: each
    build gives the same bytes.

  The values are a guess, from renders against photos of skin.
  """

  alias World.Scene.Primitive
  alias World.Vec

  import Bitwise

  # The pores: a texture of 128 pixels, a pit in each cell of 8 pixels.
  @size 128
  @cell 8

  @doc """
  The material of the skin at a level, to merge into the material of
  the texture of the skin. Only `:near` has the pores.
  """
  def material(level) do
    spec = %{"roughness" => 0.55, "specular" => 0.5, "sheen" => [170, 104, 97], "sheen_roughness" => 0.5}

    if level == :near,
      do:
        Map.merge(spec, %{"normal_image" => {"image/png", pores()}, "normal_scale" => 0.3, "normal_image_scale" => 60}),
      else: spec
  end

  @doc """
  The primitive with a color for each point: white on flat or round skin,
  a darker and warmer color in a crease. The concavity of a point is the
  distance of the mean of its neighbors in front of it, in lengths of its
  edges, smooth over 3 rings. Points at the same place (the seams of the
  UVs) are one point.
  """
  def creases(%Primitive{} = p) do
    pos = List.to_tuple(p.positions)
    nrm = List.to_tuple(p.normals)
    key = fn {x, y, z} -> {round(x * 1.0e5), round(y * 1.0e5), round(z * 1.0e5)} end

    one =
      p.positions
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {v, i}, acc -> Map.put_new(acc, key.(v), i) end)

    weld = for v <- p.positions, do: Map.fetch!(one, key.(v))
    weld = List.to_tuple(weld)

    ring =
      p.indices
      |> Enum.chunk_every(3)
      |> Enum.flat_map(fn tri ->
        [a, b, c] = Enum.map(tri, &elem(weld, &1))
        [{a, b}, {a, c}, {b, a}, {b, c}, {c, a}, {c, b}]
      end)
      |> Enum.uniq()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    concavity =
      Map.new(ring, fn {i, ns} ->
        o = elem(pos, i)
        mean = ns |> Enum.map(&elem(pos, &1)) |> Enum.reduce(&Vec.add/2) |> Vec.scale(1 / length(ns))
        edge = Enum.sum(for n <- ns, do: Vec.len(Vec.sub(elem(pos, n), o))) / length(ns)
        {i, Vec.dot(Vec.sub(mean, o), elem(nrm, i)) / max(edge, 1.0e-9)}
      end)

    smooth = fn c ->
      Map.new(ring, fn {i, ns} -> {i, (c[i] + Enum.sum(for n <- ns, do: c[n])) / (1 + length(ns))} end)
    end

    concavity = concavity |> smooth.() |> smooth.() |> smooth.()

    colors =
      for i <- Tuple.to_list(weld) do
        v = 1.0 - min(max(Map.get(concavity, i, 0.0) * 5, 0.0), 0.25)
        {round(255 * (0.35 + 0.65 * v)), round(255 * v), round(255 * (0.05 + 0.95 * v))}
      end

    %{p | colors: colors}
  end

  @doc """
  The PNG of the pores: a normal texture of glTF (red is to the right,
  green is up in the image, blue is out of the skin) that repeats with
  no seam. A small round pit in each cell of 8
  pixels, at a random place in the cell, with a random size and depth,
  on fine noise.
  """
  def pores do
    case :persistent_term.get({__MODULE__, :pores}, nil) do
      nil ->
        png = make_pores()
        :persistent_term.put({__MODULE__, :pores}, png)
        png

      png ->
        png
    end
  end

  defp make_pores do
    cells = div(@size, @cell)

    pits =
      for cx <- 0..(cells - 1), cy <- 0..(cells - 1), into: %{} do
        {{cx, cy},
         {(cx + 0.2 + 0.6 * hash(cx, cy, 1)) * @cell, (cy + 0.2 + 0.6 * hash(cx, cy, 2)) * @cell,
          1.0 + 1.2 * hash(cx, cy, 3), 0.5 + 0.5 * hash(cx, cy, 4)}}
      end

    heights =
      for y <- 0..(@size - 1), x <- 0..(@size - 1), into: %{} do
        {cx, cy} = {div(x, @cell), div(y, @cell)}

        pit =
          for dx <- -1..1, dy <- -1..1, reduce: 0.0 do
            sum ->
              {px, py, r, depth} = pits[{rem(cx + dx + cells, cells), rem(cy + dy + cells, cells)}]
              ddx = wrap(x - px)
              ddy = wrap(y - py)
              sum - depth * :math.exp(-(ddx * ddx + ddy * ddy) / (r * r))
          end

        {{x, y}, pit + 0.15 * noise(x, y)}
      end

    h = fn x, y -> heights[{rem(x + @size, @size), rem(y + @size, @size)}] end

    rows =
      for y <- 0..(@size - 1) do
        for x <- 0..(@size - 1), into: <<>> do
          {nx, ny, nz} =
            Vec.norm({-1.5 * (h.(x + 1, y) - h.(x - 1, y)) / 2, 1.5 * (h.(x, y + 1) - h.(x, y - 1)) / 2, 1.0})

          <<byte(nx), byte(ny), byte(nz)>>
        end
      end

    World.PNG.encode(rows, 3)
  end

  # The distance on a texture that repeats.
  defp wrap(d) when d > @size / 2, do: d - @size
  defp wrap(d) when d < -@size / 2, do: d + @size
  defp wrap(d), do: d

  # Smooth noise: random values at each 4 pixels, mixed between them.
  defp noise(x, y) do
    {gx, fx} = {div(x, 4), rem(x, 4) / 4}
    {gy, fy} = {div(y, 4), rem(y, 4) / 4}
    n = div(@size, 4)
    at = fn i, j -> hash(rem(i, n), rem(j, n), 5) - 0.5 end
    top = at.(gx, gy) * (1 - fx) + at.(gx + 1, gy) * fx
    bottom = at.(gx, gy + 1) * (1 - fx) + at.(gx + 1, gy + 1) * fx
    top * (1 - fy) + bottom * fy
  end

  # A number from 0 to 1 from three integers, the same on each build.
  defp hash(a, b, c) do
    h = band(bxor(bxor(a * 73_856_093, b * 19_349_663), c * 83_492_791), 0xFFFFFFFF)
    h = band(bxor(h, bsr(h, 13)) * 1_274_126_177, 0xFFFFFFFF)
    bxor(h, bsr(h, 16)) / 0xFFFFFFFF
  end

  defp byte(n), do: round((n + 1) * 127.5)
end
