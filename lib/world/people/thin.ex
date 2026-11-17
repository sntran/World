defmodule World.People.Thin do
  @moduledoc """
  A thin copy of an asset of MakeHuman (an item of clothes, a hair): the
  same item in fewer triangles, for the memory of a build.

  An asset of MakeHuman is a mesh (OBJ) and its fit to the base mesh
  (MHCLO: a line for each point of the mesh). Most items have 1,000 to
  31,000 triangles, but some have many more: `elvs_caesar_sandals1` has
  91,704, and its load alone took 94 MB, so a person in it stopped the
  builder at the edge (128 MB). Each asset in `priv/makehuman/` has at
  most `budget/0` triangles: `mix run scripts/thin.exs` makes a larger
  one thin.

  `thin/3` makes the edge collapse of `World.Simplify` to the budget.
  Each part of the UV map of the item (the faces that share a point and
  its UV) is a material of the collapse, so a face stays in its part
  and the borders of the parts stay. Then each point that stays goes
  back to its place in the item, so its line of the fit is the same
  line, and its UV is the one of its part.
  """
  alias World.People.Data
  alias World.{Simplify, Vec}

  @budget 17_000

  @doc """
  The most triangles of an asset of MakeHuman.

      iex> World.People.Thin.budget()
      17000
  """
  def budget, do: @budget

  @doc """
  The triangles of the mesh of an OBJ text (a face of n points is n - 2
  triangles).

      iex> World.People.Thin.triangles("v 0 0 0\\nf 1 2 3 4\\nf 1 2 3\\n")
      3
  """
  def triangles(obj) do
    for line <- String.split(obj, "\n"), ["f" | corners] <- [String.split(line)], reduce: 0 do
      n -> n + length(corners) - 2
    end
  end

  @doc """
  An asset (the texts of its OBJ and of its MHCLO) with at most `budget`
  triangles: `{obj, mhclo}`. An asset with no more triangles than the
  budget stays as it is.
  """
  def thin(obj, fit, budget) do
    if triangles(obj) <= budget, do: {obj, fit}, else: collapse(obj, fit, budget)
  end

  defp collapse(obj, fit, budget) do
    mesh = Data.parse_obj(obj)

    tris =
      for f <- mesh.groups |> Map.values() |> Enum.concat(),
          [a | rest] = f,
          [b, c] <- Enum.chunk_every(rest, 2, 1, :discard),
          do: [a, b, c]

    part = parts(tris)
    # (World.Simplify is in meters: MakeHuman is in decimeters.)
    points = mesh.points |> Tuple.to_list() |> Enum.map(&Vec.scale(&1, 0.1))
    faces = for {t, i} <- Enum.with_index(tris), do: {Enum.map(t, &elem(&1, 0)), part[i]}
    %{faces: faces, ids: ids} = Simplify.collapse(points, faces, budget, [])
    old = List.to_tuple(ids)

    # The UV of a point in a part.
    uv = for {t, i} <- Enum.with_index(tris), {v, w} <- t, reduce: %{}, do: (acc -> Map.put_new(acc, {v, part[i]}, w))
    faces = for {vs, m} <- faces, do: Enum.map(vs, fn k -> {elem(old, k), uv[{elem(old, k), m}]} end)

    {obj_text(obj, ids, faces), fit_text(fit, ids)}
  end

  # The parts of the UV map: a face and the faces that share a point with
  # the same UV are in one part. A map of the index of a face to its part
  # (the index of a face of the part).
  defp parts(tris) do
    corners =
      for {t, i} <- Enum.with_index(tris), c <- t, reduce: %{} do
        acc -> Map.update(acc, c, [i], &[i | &1])
      end

    roots =
      Enum.reduce(corners, %{}, fn {_, [f | rest]}, p ->
        Enum.reduce(rest, p, fn g, p ->
          {a, b} = {root(p, f), root(p, g)}
          if a == b, do: p, else: Map.put(p, a, b)
        end)
      end)

    Map.new(0..(length(tris) - 1)//1, &{&1, root(roots, &1)})
  end

  defp root(p, x) do
    case Map.get(p, x, x) do
      ^x -> x
      y -> root(p, y)
    end
  end

  # The OBJ of the points that stay and of the UVs of the faces (their
  # lines as in the item), and the faces.
  defp obj_text(obj, ids, faces) do
    lines = String.split(obj, "\n")
    vs = lines |> Enum.filter(&String.starts_with?(&1, "v ")) |> List.to_tuple()
    vts = lines |> Enum.filter(&String.starts_with?(&1, "vt ")) |> List.to_tuple()
    index = ids |> Enum.with_index(1) |> Map.new()
    ts = faces |> Enum.flat_map(fn f -> for {_, t} <- f, t != nil, do: t end) |> Enum.uniq() |> Enum.sort()
    tindex = ts |> Enum.with_index(1) |> Map.new()

    corner = fn {v, t} ->
      [" ", Integer.to_string(index[v]) | if(t, do: ["/", Integer.to_string(tindex[t])], else: [])]
    end

    IO.iodata_to_binary([
      for(line <- lines, String.starts_with?(line, "#"), do: [line, "\n"]),
      Enum.map(ids, &[elem(vs, &1), "\n"]),
      Enum.map(ts, &[elem(vts, &1), "\n"]),
      for(line <- Enum.take(Enum.filter(lines, &String.starts_with?(&1, "g ")), 1), do: [line, "\n"]),
      for(f <- faces, do: ["f", Enum.map(f, corner), "\n"])
    ])
  end

  # The MHCLO with the line of the fit of each point that stays, in the
  # new order; the lines before and after the fit stay.
  defp fit_text(fit, ids) do
    lines = String.split(fit, "\n")
    {head, rest} = Enum.split_while(lines, &(not String.starts_with?(&1, "verts")))
    [verts | rest] = rest
    {refs, tail} = Enum.split_while(rest, &(not String.starts_with?(&1, "delete_verts")))
    {pre, refs} = Enum.split_while(refs, &(length(String.split(&1)) not in [1, 9]))
    refs = Enum.filter(refs, &(length(String.split(&1)) in [1, 9])) |> List.to_tuple()
    Enum.join(head ++ [verts] ++ pre ++ Enum.map(ids, &elem(refs, &1)) ++ tail, "\n")
  end
end
