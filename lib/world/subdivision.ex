defmodule World.Subdivision do
  @moduledoc """
  The smooth steps of a mesh of faces with any number of sides
  (Catmull-Clark), with the data of each point: its place and a map of
  numbers (the weight of each bone, a color). Each new point is a mean
  of old points, so the weights of a skin stay a sum of 1.

  After one step each face of n sides is n faces of 4 sides. A point
  on a border (an edge of one face) stays where it is, and a new point
  on a border edge is at its middle.
  """
  alias World.Vec

  @doc """
  The mesh after `steps` smooth steps: `{points, faces}`, each point
  `{place, weights}`.
  """
  def smooth(points, faces, 0), do: {points, faces}

  def smooth(points, faces, steps) do
    {points, faces} = step(List.to_tuple(points), faces)
    smooth(points, faces, steps - 1)
  end

  defp step(points, faces) do
    n = tuple_size(points)
    centers = Enum.map(faces, fn f -> mean(Enum.map(f, &elem(points, &1))) end)

    # The faces of each edge, and of each point.
    edge_faces =
      faces
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {f, i}, acc ->
        Enum.reduce(edges(f), acc, &Map.update(&2, key(&1), [i], fn l -> [i | l] end))
      end)

    point_faces =
      faces
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {f, i}, acc -> Enum.reduce(f, acc, &Map.update(&2, &1, [i], fn l -> [i | l] end)) end)

    point_edges =
      edge_faces
      |> Map.keys()
      |> Enum.reduce(%{}, fn {a, b} = e, acc ->
        acc |> Map.update(a, [e], &[e | &1]) |> Map.update(b, [e], &[e | &1])
      end)

    centers_t = List.to_tuple(centers)

    # The new point of each edge: the mean of its two points and of the
    # centers of its two faces (the middle of a border edge).
    edge_index = edge_faces |> Map.keys() |> Enum.sort() |> Enum.with_index(n) |> Map.new()

    edge_points =
      for {{a, b} = e, _} <- Enum.sort_by(edge_index, &elem(&1, 1)) do
        case edge_faces[e] do
          [f, g] -> mean([elem(points, a), elem(points, b), elem(centers_t, f), elem(centers_t, g)])
          _ -> mean([elem(points, a), elem(points, b)])
        end
      end

    # The new place of each old point: (F + 2R + (n - 3) P) / n.
    moved =
      for i <- 0..(n - 1) do
        p = elem(points, i)
        fs = Map.get(point_faces, i, [])
        es = Map.get(point_edges, i, [])

        if fs == [] or Enum.any?(es, &(length(edge_faces[&1]) != 2)) do
          p
        else
          k = length(fs)
          f = mean(Enum.map(fs, &elem(centers_t, &1)))
          r = mean(Enum.map(es, fn {a, b} -> mean([elem(points, a), elem(points, b)]) end))
          combine([{1 / k, f}, {2 / k, r}, {(k - 3) / k, p}])
        end
      end

    first = n + map_size(edge_index)

    new_faces =
      faces
      |> Enum.with_index()
      |> Enum.flat_map(fn {f, i} ->
        c = first + i
        m = length(f)

        for j <- 0..(m - 1) do
          {prev, v, next} = {Enum.at(f, rem(j - 1 + m, m)), Enum.at(f, j), Enum.at(f, rem(j + 1, m))}
          [v, edge_index[key({v, next})], c, edge_index[key({prev, v})]]
        end
      end)

    {moved ++ edge_points ++ centers, new_faces}
  end

  defp edges(f), do: Enum.zip(f, tl(f) ++ [hd(f)])
  defp key({a, b}), do: {min(a, b), max(a, b)}

  defp mean(ps), do: combine(Enum.map(ps, &{1 / length(ps), &1}))

  # A sum of points with their parts: the places and the weights.
  defp combine(parts) do
    place = Enum.reduce(parts, {0.0, 0.0, 0.0}, fn {k, {p, _}}, acc -> Vec.add(acc, Vec.scale(p, k)) end)

    weights =
      Enum.reduce(parts, %{}, fn {k, {_, ws}}, acc ->
        Enum.reduce(ws, acc, fn {b, w}, acc -> Map.update(acc, b, k * w, &(&1 + k * w)) end)
      end)

    {place, weights}
  end
end
