defmodule World.Faces do
  @moduledoc """
  The faces of a model for a painter of a picture in 2D (an SVG): each
  part that a level keeps, with the node of its joint, its box and its
  faces (`docs/format.md`, "The faces"). A face is one polygon of the
  mesh, not cut into triangles (`World.Mesh.faces/2`), with its material
  role and its normal. So a painter can sort the parts by their boxes,
  and then the faces of each part.

  The points are in the axes of World (x to the right side, y to the
  front, z up), in meters, in the pose of the model.
  """
  alias World.{Build, Frame, GLB, Mesh, Vec}

  @doc """
  The faces of a model as a map. The options: `level` (`:near` by
  default), `pose` and `targets` (as for `World.Build.scene/2`), and
  `materials` (a map of a role to its spec: the colors of an order, as
  the materials of a scene).
  """
  def build(item, opts \\ []) do
    level = Keyword.get(opts, :level, :near)
    overrides = Map.merge(Map.get(item, :materials, %{}), Keyword.get(opts, :materials, %{}))

    parts =
      for {frame, part, path, node} <- Build.pieces(item, opts),
          shapes = for(m <- part.shapes, s = shape(frame, m), s != nil, do: s),
          shapes != [] do
        %{path: path, node: node, box: bounds(Enum.map(shapes, & &1.box)), shapes: shapes}
      end

    roles = parts |> Enum.flat_map(& &1.shapes) |> Enum.map(& &1.role) |> Enum.uniq() |> Enum.sort()
    {lo, hi} = if parts == [], do: {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}}, else: bounds(Enum.map(parts, & &1.box))

    %{
      "name" => item.name,
      "level" => Atom.to_string(level),
      "size" => vec(Vec.sub(hi, lo)),
      "colors" => Map.new(roles, &{Atom.to_string(&1), color(&1, overrides)}),
      "parts" => Enum.map(parts, &part/1)
    }
  end

  @doc "The faces of a model as JSON (`build/2`)."
  def encode(item, opts \\ []), do: JSON.encode!(build(item, opts))

  # A mesh of a part at the place of the part: its role, its points (each
  # once, in mm steps), and its faces as indices into the points, with
  # the normal of each face. A mesh with no face is nil.
  defp shape(frame, %Mesh{} = m) do
    faces =
      for {points, normal} <- Mesh.faces(m),
          do: {Enum.map(points, &vec(Frame.point(frame, &1))), Frame.dir(frame, normal)}

    if faces == [] do
      nil
    else
      {index, points} =
        faces
        |> Enum.flat_map(&elem(&1, 0))
        |> Enum.reduce({%{}, []}, fn p, {index, points} ->
          if Map.has_key?(index, p), do: {index, points}, else: {Map.put(index, p, map_size(index)), [p | points]}
        end)

      points = Enum.reverse(points)

      %{
        role: m.material,
        box: points |> Enum.map(&List.to_tuple/1) |> Vec.bounds(),
        points: points,
        faces: for({ps, _} <- faces, do: Enum.map(ps, &Map.fetch!(index, &1))),
        normals: for({_, n} <- faces, do: vec(n))
      }
    end
  end

  defp part(%{path: path, node: node, box: box, shapes: shapes}) do
    %{
      "path" => path,
      "node" => node,
      "box" => box(box),
      "shapes" =>
        for s <- shapes do
          %{
            "role" => Atom.to_string(s.role),
            "box" => box(s.box),
            "points" => s.points,
            "faces" => s.faces,
            "normals" => s.normals
          }
        end
    }
  end

  defp bounds(boxes), do: boxes |> Enum.flat_map(&Tuple.to_list/1) |> Vec.bounds()

  defp box({lo, hi}), do: [Tuple.to_list(lo), Tuple.to_list(hi)]

  # The color of a role in sRGB (0 to 255) and its alpha (1 is opaque).
  defp color(role, overrides) do
    spec = GLB.spec(role, overrides)
    %{"color" => spec["color"], "alpha" => Map.get(spec, "alpha", 1.0) / 1}
  end

  # A point or a direction with 3 decimals: a step of 1 mm is too small
  # to see in a picture. A zero has no sign (-0.0 + 0.0 is 0.0).
  defp vec({x, y, z}), do: for(v <- [x, y, z], do: Float.round(v / 1, 3) + 0.0)
end
