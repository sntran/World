# The reader of a glTF file for the scripts (scripts/gltf_figure.exs,
# scripts/gltf_clips.exs): the buffers, the values of an accessor, and
# the frames of the nodes in the axes of the file.
defmodule GLTF do
  @doc "The JSON of a glTF file and its buffers (in the file or next to it)."
  def load(path) do
    gltf = path |> File.read!() |> JSON.decode!()

    buffers =
      for b <- gltf["buffers"] do
        case b["uri"] do
          "data:" <> data -> data |> String.split(",", parts: 2) |> List.last() |> Base.decode64!()
          file -> File.read!(Path.join(Path.dirname(path), file))
        end
      end

    Map.put(gltf, :buffers, buffers)
  end

  @doc "The values of an accessor: a list of tuples (or of numbers for a scalar)."
  def read(gltf, index) do
    a = Enum.at(gltf["accessors"], index)
    view = Enum.at(gltf["bufferViews"], a["bufferView"])
    n = %{"SCALAR" => 1, "VEC2" => 2, "VEC3" => 3, "VEC4" => 4, "MAT4" => 16}[a["type"]]

    {size, take} =
      case a["componentType"] do
        5126 -> {4, fn <<v::little-float-32>> -> v end}
        5125 -> {4, fn <<v::little-32>> -> v end}
        5123 -> {2, fn <<v::little-16>> -> v end}
        5121 -> {1, fn <<v::8>> -> v end}
      end

    stride = view["byteStride"] || size * n
    start = Map.get(view, "byteOffset", 0) + Map.get(a, "byteOffset", 0)
    bin = Enum.at(gltf.buffers, view["buffer"])

    for i <- 0..(a["count"] - 1) do
      values = for k <- 0..(n - 1), do: take.(binary_part(bin, start + i * stride + k * size, size))
      if n == 1, do: hd(values), else: List.to_tuple(values)
    end
  end

  @doc "The parent of each node that has one."
  def parents(gltf) do
    for {n, i} <- Enum.with_index(gltf["nodes"]), c <- Map.get(n, "children", []), into: %{}, do: {c, i}
  end

  @doc """
  The place and the turn (a quaternion) of each node in the axes of the
  file, from the moves, turns and scales of the nodes: of the file, or
  of `local` (a map of a node to `%{"translation", "rotation",
  "scale"}`, over the values of the file).
  """
  def world(gltf, local \\ %{}) do
    parents = parents(gltf)
    nodes = gltf["nodes"]

    Enum.reduce(order(gltf), %{}, fn i, acc ->
      n = Map.merge(Enum.at(nodes, i), Map.get(local, i, %{}))
      t = List.to_tuple(n["translation"] || [0.0, 0.0, 0.0])
      q = List.to_tuple(n["rotation"] || [0.0, 0.0, 0.0, 1.0])
      s = List.to_tuple(n["scale"] || [1.0, 1.0, 1.0])

      case acc[parents[i]] do
        nil ->
          Map.put(acc, i, {t, q, s})

        {pt, pq, ps} ->
          at = add(pt, rotate(pq, mul(ps, t)))
          Map.put(acc, i, {at, qmul(pq, q), mul(ps, s)})
      end
    end)
  end

  # The nodes, parents first.
  defp order(gltf) do
    parents = parents(gltf)
    depth = fn i -> Stream.iterate(i, &parents[&1]) |> Enum.take_while(& &1) |> length() end
    gltf["nodes"] |> Enum.with_index() |> Enum.map(&elem(&1, 1)) |> Enum.sort_by(depth)
  end

  def qmul({ax, ay, az, aw}, {bx, by, bz, bw}) do
    {aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz}
  end

  def conj({x, y, z, w}), do: {-x, -y, -z, w}
  def dot({a, b, c, d}, {e, f, g, h}), do: a * e + b * f + c * g + d * h

  def rotate(q, {x, y, z}) do
    {rx, ry, rz, _} = qmul(qmul(q, {x, y, z, 0.0}), conj(q))
    {rx, ry, rz}
  end

  def add({a, b, c}, {d, e, f}), do: {a + d, b + e, c + f}
  def sub({a, b, c}, {d, e, f}), do: {a - d, b - e, c - f}
  defp mul({a, b, c}, {d, e, f}), do: {a * d, b * e, c * f}
end
