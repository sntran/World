defmodule World.Buildings.Panel do
  @moduledoc """
  The panel of a wall, a slab or a roof of a building: one closed slab
  with holes (`sheet/8`), with the knots of `World.Surface` at its edges.
  A wall of a lot house (`World.Buildings.Lot`) and the walls of a house
  that the people build (`World.Skills.House`) are panels.
  """
  alias World.{Mesh, Vec}

  @doc """
  A sheet: a closed slab on the rectangle from `at` along `u` (its
  length) and `v` (its height); its outside face is to u × v
  (`inward: true` turns it to the other side), and its back is the
  thickness of `skin` (`{thickness, matter}`) in. The holes are `{u0,
  v0, u1, v1, depth}` through the slab (the depth is the place of the
  window or the door in it). The points are at each edge of a hole, at
  the knots `us` and `vs`, and at the corners, 4 m from them and at the
  middle of the length (`World.Surface`; `ends`: the corner of the
  building is this far past each end). `relief` moves each point of the
  outside face out by a function of u and v (the ribs of metal, the
  courses of tiles).
  """
  def sheet(at, u, v, len, ht, holes, role, opts) do
    inward = Keyword.get(opts, :inward, false)
    {t, matter} = Keyword.fetch!(opts, :skin)
    n = Vec.norm(Vec.cross(u, v))
    n = if inward, do: Vec.scale(n, -1.0), else: n
    corner = min(World.Surface.reach_scale() - Keyword.get(opts, :ends, 0.0), len / 2)

    us =
      knots(
        [0.0, len, corner, len / 2, len - corner] ++
          Keyword.get(opts, :us, []) ++ Enum.flat_map(holes, fn {a, _, b, _, _} -> [a, b] end),
        len
      )

    vs = knots([0.0, ht] ++ Keyword.get(opts, :vs, []) ++ Enum.flat_map(holes, fn {_, a, _, b, _} -> [a, b] end), ht)
    {tu, tv} = {List.to_tuple(us), List.to_tuple(vs)}
    {nu, nv} = {tuple_size(tu), tuple_size(tv)}
    relief = Keyword.get(opts, :relief) || fn _, _ -> 0.0 end

    point = fn {side, i, j} ->
      {a, b} = {elem(tu, i), elem(tv, j)}
      base = at |> Vec.add(Vec.scale(u, a)) |> Vec.add(Vec.scale(v, b))
      if side == :f, do: Vec.add(base, Vec.scale(n, relief.(a, b))), else: Vec.add(base, Vec.scale(n, -t))
    end

    hole_at = fn x, y -> Enum.any?(holes, fn {a, b, c, d, _} -> x > a and x < c and y > b and y < d end) end

    solid = fn i, j ->
      i >= 0 and j >= 0 and i < nu - 1 and j < nv - 1 and
        not hole_at.((elem(tu, i) + elem(tu, i + 1)) / 2, (elem(tv, j) + elem(tv, j + 1)) / 2)
    end

    cells = for i <- 0..(nu - 2), j <- 0..(nv - 2), solid.(i, j), do: {i, j}

    # Each cell: its face out, its face at the back, and a face on each
    # edge that has no cell next to it (the rim, and the reveal of a hole).
    faces =
      Enum.flat_map(cells, fn {i, j} ->
        [
          [{:f, i, j}, {:f, i + 1, j}, {:f, i + 1, j + 1}, {:f, i, j + 1}],
          [{:k, i, j + 1}, {:k, i + 1, j + 1}, {:k, i + 1, j}, {:k, i, j}]
        ] ++
          if(solid.(i, j - 1), do: [], else: [[{:f, i + 1, j}, {:f, i, j}, {:k, i, j}, {:k, i + 1, j}]]) ++
          if(solid.(i + 1, j), do: [], else: [[{:f, i + 1, j + 1}, {:f, i + 1, j}, {:k, i + 1, j}, {:k, i + 1, j + 1}]]) ++
          if(solid.(i, j + 1), do: [], else: [[{:f, i, j + 1}, {:f, i + 1, j + 1}, {:k, i + 1, j + 1}, {:k, i, j + 1}]]) ++
          if(solid.(i - 1, j), do: [], else: [[{:f, i, j}, {:f, i, j + 1}, {:k, i, j + 1}, {:k, i, j}]])
      end)

    faces = if inward, do: Enum.map(faces, &Enum.reverse/1), else: faces
    keys = faces |> List.flatten() |> Enum.uniq()
    index = keys |> Enum.with_index() |> Map.new()
    points = Enum.map(keys, point)
    faces = Enum.map(faces, fn f -> Enum.map(f, &index[&1]) end)
    Mesh.new(points, Mesh.outside(points, faces), role) |> Mesh.matter(matter)
  end

  defp knots(list, max) do
    list
    |> Enum.map(&Float.round(min(max(&1 / 1, 0.0), max / 1), 5))
    |> Enum.sort()
    |> Enum.dedup()
  end
end
