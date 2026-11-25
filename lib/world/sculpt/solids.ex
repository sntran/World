defmodule World.Sculpt.Solids do
  @moduledoc """
  The mesh of a level of a sculpture from the solids of its edits (the
  key `solids` of a sculpture, `World.Skills.Sculpt`): each edit that
  adds is a solid of few flat faces with straight edges, with no field
  and no cut. The solids go into each other where their edits do (a band
  round a wall, a tank on a roof); the faces in another solid do not
  show.

  At a level of few triangles, a part that is thinner than about three
  cells (a slab, a parapet, a band, a blade, a wing) loses its corners or
  its form in the cut of the mesh of the field to the budget. The solids
  keep each outline, and their count of triangles is known before the
  build (`count/1`): a box 12, a cylinder 28 (8 sides), a cone 28 (14 with
  a point), a ball and an ellipsoid 48 (8 sides, 4 rows), a wedge 8, an
  extrude of `n` points `4n - 4`.

  An edit that paints gives no solid: with a bake, its color goes into
  the image from the field, as at the other levels. An edit that takes
  away (`subtract`, `crop`) has no solid, and the other shapes have none
  (`error/1`).
  """
  alias World.{Frame, Mesh, Vec}

  @shapes ~w(ball box cone cylinder ellipsoid extrude wedge)a
  # The sides round a cylinder, a cone and an ellipsoid, and the rows of an ellipsoid from pole to pole.
  @sides 8
  @rows 4

  @doc "The shapes that have a solid."
  def shapes, do: Enum.map(@shapes, &Atom.to_string/1)

  @doc "Why an edit has no solid, or nil."
  def error(%{mode: mode}) when mode in [:subtract, :crop], do: "an edit that takes away has no solid"
  def error(%{mode: :paint}), do: nil
  def error(%{shape: shape}) when shape in @shapes, do: nil
  def error(%{shape: shape}), do: "the shape #{shape} has no solid: the shapes are #{Enum.join(shapes(), ", ")}"

  @doc "The count of the triangles of the solids of the edits that add (an edit with no solid: none)."
  def count(edits),
    do: Enum.sum(for e <- edits, e.mode == :add, e.shape in @shapes, do: length(triangles(e.shape, e.size)))

  @doc """
  The meshes of the solids of the edits that add: one for each
  material, each face with its own three points, its normal, and the
  color of its edit (in sRGB; white with no color).
  """
  def meshes(edits) do
    edits
    |> Enum.filter(&(&1.mode == :add))
    |> Enum.group_by(&(&1.material || :paint))
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {material, es} ->
      faces =
        for e <- es, {a, b, c} <- triangles(e.shape, e.size) do
          {a, b, c} = {Frame.point(e.frame, a), Frame.point(e.frame, b), Frame.point(e.frame, c)}
          corners = if mirror?(e.frame), do: {a, c, b}, else: {a, b, c}
          {corners, look(e, corners)}
        end

      points = for {{a, b, c}, _} <- faces, p <- [a, b, c], do: p
      normals = for {{a, b, c}, _} <- faces, n = Vec.norm(Vec.cross(Vec.sub(b, a), Vec.sub(c, a))), _ <- 1..3, do: n
      lit? = Enum.any?(faces, fn {_, {_, light}} -> light != {0, 0, 0} end)

      material
      |> then(&Mesh.new(points, for(i <- 0..(length(faces) - 1)//1, do: [3 * i, 3 * i + 1, 3 * i + 2]), &1))
      |> Map.put(:angle, 0.0)
      |> Mesh.finish(normals, for({_, {color, _}} <- faces, _ <- 1..3, do: color))
      # (The light of each face, for the flat look: `_LIGHT` only. The other looks make their own finish.)
      |> Map.put(:finish, if(lit?, do: for({_, {_, light}} <- faces, _ <- 1..3, do: {nil, nil, light})))
    end)
  end

  # The color and the light of a face of a solid: the color of its edit, and with a surface of a made thing
  # (windows) or a glow, the mean of the surface over the face and its light (`World.Sculpt.Shade.face/4`).
  defp look(e, {a, b, c}) do
    if e.glow not in [nil, 0.0] or World.SDF.made?([e]) do
      n = Vec.cross(Vec.sub(b, a), Vec.sub(c, a))
      World.Sculpt.Shade.face([e], Vec.scale(Vec.add(Vec.add(a, b), c), 1 / 3), :math.sqrt(Vec.len(n) / 2), Vec.norm(n))
    else
      {color(e.color), {0, 0, 0}}
    end
  end

  # A frame that turns the faces over (a mirror): the order of the corners of each face changes.
  defp mirror?(%Frame{x: x, y: y, z: z}), do: Vec.dot(x, Vec.cross(y, z)) < 0

  defp color(nil), do: {255, 255, 255}
  defp color({r, g, b}), do: {srgb(r), srgb(g), srgb(b)}

  defp srgb(c) do
    c = min(max(c, 0.0), 1.0)
    round(255 * if(c <= 0.0031308, do: 12.92 * c, else: 1.055 * :math.pow(c, 1 / 2.4) - 0.055))
  end

  # The triangles of a shape in its own axes, each with its corners in turn round its normal to the outside.
  defp triangles(:ball, {r}), do: triangles(:ellipsoid, {r, r, r})

  defp triangles(:box, {hx, hy, hz}) do
    # (An outline in x and y, from z = -hz to hz.)
    prism([{-hx, -hy}, {hx, -hy}, {hx, hy}, {-hx, hy}], hz, & &1)
  end

  defp triangles(:cylinder, {r, h}), do: triangles(:cone, {r, r, h})

  defp triangles(:cone, {r1, r2, h}) do
    at = fn r, z ->
      for k <- 0..(@sides - 1), a = 2 * :math.pi() * k / @sides, do: {r * :math.cos(a), r * :math.sin(a), z}
    end

    {low, high} = {at.(r1, -h), at.(r2, h)}
    pairs = Enum.zip([low, tl(low) ++ [hd(low)], high, tl(high) ++ [hd(high)]])

    sides =
      if r2 < 1.0e-9,
        do: for({a, b, _, _} <- pairs, do: {a, b, {0.0, 0.0, h}}),
        else: Enum.flat_map(pairs, fn {a, b, c, d} -> quad(a, b, d, c) end)

    top = if r2 < 1.0e-9, do: [], else: fan(high)
    sides ++ top ++ fan(Enum.reverse(low))
  end

  # The ellipsoid: rows from the top (+z) to the bottom, each with its points round z.
  defp triangles(:ellipsoid, {rx, ry, rz}) do
    point = fn row, k ->
      {t, a} = {:math.pi() * row / @rows, 2 * :math.pi() * k / @sides}
      {rx * :math.sin(t) * :math.cos(a), ry * :math.sin(t) * :math.sin(a), rz * :math.cos(t)}
    end

    {top, bottom} = {{0.0, 0.0, rz}, {0.0, 0.0, -rz}}

    for k <- 0..(@sides - 1), row <- 0..(@rows - 1), reduce: [] do
      acc ->
        k1 = rem(k + 1, @sides)

        cond do
          row == 0 -> [{top, point.(1, k), point.(1, k1)} | acc]
          row == @rows - 1 -> [{bottom, point.(row, k1), point.(row, k)} | acc]
          true -> quad(point.(row, k), point.(row + 1, k), point.(row + 1, k1), point.(row, k1)) ++ acc
        end
    end
  end

  # The wedge: a triangle in y and z (its slope from the top at -y to the bottom at +y), from x = -hx to hx.
  defp triangles(:wedge, {hx, hy, hz}),
    do: prism([{-hy, -hz}, {hy, -hz}, {-hy, hz}], hx, fn {u, v, w} -> {w, u, v} end)

  defp triangles(:extrude, {points, h, _round}), do: prism(points, h, & &1)

  # A prism: an outline (`{u, v}`) from w = -h to h, and the axes of the shape from u, v and w.
  defp prism(outline, h, axes) do
    # (The outline in turn to the left, so the sides face out.)
    outline = if area(outline) < 0, do: Enum.reverse(outline), else: outline
    next = tl(outline) ++ [hd(outline)]
    low = fn {u, v} -> axes.({u, v, -h}) end
    high = fn {u, v} -> axes.({u, v, h}) end

    sides = Enum.flat_map(Enum.zip(outline, next), fn {p, q} -> quad(low.(p), low.(q), high.(q), high.(p)) end)

    caps =
      for {a, b, c} <- ears(outline),
          tri <- [{high.(a), high.(b), high.(c)}, {low.(a), low.(c), low.(b)}],
          do: tri

    sides ++ caps
  end

  # Two triangles of a quad with its corners in turn.
  defp quad(a, b, c, d), do: [{a, b, c}, {a, c, d}]

  # The triangles of a convex polygon from its first point.
  defp fan([a | rest]), do: for([b, c] <- Enum.chunk_every(rest, 2, 1, :discard), do: {a, b, c})

  defp area(points) do
    next = tl(points) ++ [hd(points)]
    Enum.sum(for {{x1, y1}, {x2, y2}} <- Enum.zip(points, next), do: x1 * y2 - x2 * y1) / 2
  end

  # The triangles of a simple polygon in turn to the left (it can be not convex), by ears: a corner that turns
  # left with no other point in its triangle is cut off, until three points are left.
  defp ears([a, b, c]), do: [{a, b, c}]

  defp ears(points) do
    n = length(points)
    at = List.to_tuple(points)

    i =
      Enum.find(0..(n - 1), fn i ->
        {p, q, r} = {elem(at, rem(i + n - 1, n)), elem(at, i), elem(at, rem(i + 1, n))}
        left?(p, q, r) and not Enum.any?(points, &(&1 not in [p, q, r] and inside?(&1, p, q, r)))
      end)

    {p, q, r} = {elem(at, rem(i + n - 1, n)), elem(at, i), elem(at, rem(i + 1, n))}
    [{p, q, r} | ears(List.delete_at(points, i))]
  end

  defp left?({x1, y1}, {x2, y2}, {x3, y3}), do: (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1) > 1.0e-12

  defp inside?(p, a, b, c), do: not left?(a, c, p) and not left?(c, b, p) and not left?(b, a, p)
end
