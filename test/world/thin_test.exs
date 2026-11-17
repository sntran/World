defmodule World.People.ThinTest do
  use ExUnit.Case, async: true

  alias World.People.{Data, Thin}

  doctest Thin

  # An asset of a grid of n by n quads on a dome (decimeters), in two parts of its UV map: the left half
  # (u to 0.45) and the right half (u from 0.55) have their own UVs. Each point has its line of the fit, with
  # its index as its offset, so a test can find the line of each point.
  defp grid(n) do
    point = fn i, j -> {i / n, j / n, 0.2 * :math.sin(:math.pi() * i / n) * :math.sin(:math.pi() * j / n)} end
    id = fn i, j -> j * (n + 1) + i + 1 end
    half = div(n, 2)
    # The UVs: one for each point in each part.
    uv = fn i, j, right -> if right, do: (n + 1) * (n + 1) + id.(i, j), else: id.(i, j) end

    vs = for j <- 0..n, i <- 0..n, {x, y, z} = point.(i, j), do: "v #{x} #{y} #{z}"

    vts =
      for(j <- 0..n, i <- 0..n, do: "vt #{i / n * 0.45} #{j / n}") ++
        for(j <- 0..n, i <- 0..n, do: "vt #{0.55 + i / n * 0.45} #{j / n}")

    fs =
      for j <- 0..(n - 1), i <- 0..(n - 1) do
        right = i >= half
        corners = [{i, j}, {i + 1, j}, {i + 1, j + 1}, {i, j + 1}]
        "f " <> Enum.map_join(corners, " ", fn {a, b} -> "#{id.(a, b)}/#{uv.(a, b, right)}" end)
      end

    obj = Enum.join(["# a grid"] ++ vs ++ vts ++ ["g grid"] ++ fs, "\n") <> "\n"
    refs = for k <- 0..((n + 1) * (n + 1) - 1), do: "1 2 3 0.2 0.3 0.5 #{k} 0.0 0.0"

    fit =
      Enum.join(
        ["# a fit", "name grid", "x_scale 5399 11998 1.4", "verts 0"] ++ refs ++ ["delete_verts", "7", "9 - 12"],
        "\n"
      )

    {obj, fit}
  end

  test "a thin asset: at most the budget, each point with its line of the fit, each face in one part of the UV map" do
    {obj, fit} = grid(20)
    assert Thin.triangles(obj) == 800
    {thin, thin_fit} = Thin.thin(obj, fit, 200)
    assert Thin.triangles(thin) <= 200 and Thin.triangles(thin) > 100

    mesh = Data.parse_obj(thin)
    parsed = Data.parse_fit(thin_fit)
    assert tuple_size(parsed.refs) == tuple_size(mesh.points)
    # The lines before and after the fit stay: the scale and the points that the item hides.
    assert parsed.scales["x_scale"] == {5399, 11998, 1.4}
    assert parsed.delete == Data.parse_fit(fit).delete

    # Each point is a point of the grid at its place, and its line of the fit is the line of that point.
    before = Data.parse_obj(obj)
    places = before.points |> Tuple.to_list() |> Enum.with_index() |> Map.new()

    for {p, k} <- mesh.points |> Tuple.to_list() |> Enum.with_index() do
      assert {_, _, {offset, _, _}} = elem(parsed.refs, k)
      assert places[p] == round(offset)
    end

    # The faces of each part of the UV map keep the UVs of their part.
    for f <- mesh.groups["grid"] do
      us = Enum.map(f, fn {_, t} -> elem(elem(mesh.uvs, t), 0) end)
      assert Enum.all?(us, &(&1 <= 0.45)) or Enum.all?(us, &(&1 >= 0.55)), inspect(us)
    end
  end

  test "an asset in the budget stays as it is; a face with no UV" do
    {obj, fit} = grid(4)
    assert Thin.thin(obj, fit, 32) == {obj, fit}

    flat = "v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nv 2 0 0\nv 2 1 0\nf 1 2 3 4\nf 2 5 6 3\n"
    fit = "verts 0\n" <> String.duplicate("1 2 3 0.2 0.3 0.5 0.0 0.0 0.0\n", 6) <> "delete_verts\n"
    {thin, thin_fit} = Thin.thin(flat, fit, 2)
    assert Thin.triangles(thin) == 2
    assert %{groups: %{"default" => [_, _]}, points: points} = Data.parse_obj(thin)
    assert tuple_size(Data.parse_fit(thin_fit).refs) == tuple_size(points)
  end

  # The rule of the data: a person in an item of many triangles stopped the builder at the edge
  # (scripts/thin.exs makes each item thin).
  test "each asset of MakeHuman has at most the budget of triangles" do
    for {kind, entries} <- Data.assets(), {name, %{"obj" => obj}} <- entries do
      text = :zlib.gunzip(File.read!(Path.join([Data.dir(), kind, obj])))
      assert Thin.triangles(text) <= Thin.budget(), "#{kind}/#{name}"
    end
  end
end
