defmodule World.Mesh do
  @moduledoc """
  A mesh of one material: points, and faces as lists of point indices.
  Each face turns counterclockwise when the eye is outside the shape.

  The core of Wings 3D builds the mesh (`wings_we:build/2`), smooths it
  `smooth` times (Catmull-Clark, `wings_subdiv:smooth/1`), and cuts it
  into triangles (`wings_tesselation:triangulate/2`).
  """
  alias World.{Frame, Vec}
  defstruct points: [], faces: [], material: :paint, smooth: 0, angle: 40.0

  @type t :: %__MODULE__{
          points: [Vec.t()],
          faces: [[non_neg_integer]],
          material: atom,
          smooth: non_neg_integer,
          angle: number
        }

  @doc """
  A mesh. The options: `smooth` (the number of smooth steps, 0 by
  default; less at the levels `:mid` and `:far`, `World.Detail`) and `angle` (in degrees: two faces with a larger angle between
  them have a hard edge; 40 by default).
  """
  def new(points, faces, material, opts \\ []) do
    %__MODULE__{
      points: Enum.map(points, &Vec.float/1),
      faces: faces,
      material: material,
      smooth: World.Detail.smooth(Keyword.get(opts, :smooth, 0)),
      angle: Keyword.get(opts, :angle, 40.0)
    }
  end

  @doc "The mesh, moved by a frame."
  def transform(%__MODULE__{points: ps} = m, %Frame{} = f), do: %{m | points: Enum.map(ps, &Frame.point(f, &1))}

  @doc "The box of the points: `{min, max}`."
  def bounds(%__MODULE__{points: ps}), do: Vec.bounds(ps)

  @doc """
  The faces, all turned to the outside: when the volume of the mesh is
  less than 0, each face turns the other way. Use it for a closed mesh.
  """
  def outside(points, faces) do
    if volume(points, faces) >= 0, do: faces, else: Enum.map(faces, &Enum.reverse/1)
  end

  @doc "Six times the signed volume of a closed mesh (positive when its faces look out)."
  def volume(points, faces) do
    pt = List.to_tuple(points)

    Enum.sum(
      for [a | rest] <- faces, [b, c] <- Enum.chunk_every(rest, 2, 1, :discard) do
        Vec.dot(elem(pt, a), Vec.cross(elem(pt, b), elem(pt, c)))
      end
    )
  end

  @doc """
  The triangles of the mesh at a smooth level (the level of the mesh by
  default): a list of corners `{point, normal}`, three for each triangle.
  """
  def triangles(%__MODULE__{} = m, level \\ nil) do
    level = if level == nil, do: m.smooth, else: level
    {tris, pos} = wings_triangles(m, level)
    normals(tris, pos, if(level > 0, do: 180.0, else: m.angle))
  end

  defp wings_triangles(%__MODULE__{points: ps, faces: fs}, level) do
    we =
      try do
        :wings_we.build(fs, ps)
      catch
        kind, reason -> raise ArgumentError, "the core of Wings refused the mesh: #{inspect({kind, reason}, limit: 6)}"
      end

    we = Enum.reduce(List.duplicate(nil, level), we, fn _, w -> :wings_subdiv.smooth(w) end)
    # The core of Wings closes an open shape with hidden faces (holes):
    # only the visible faces are a part of the shape.
    we = :wings_tesselation.triangulate(:wings_we.visible(we), we)
    vp = elem(we, 10)
    tris = for f <- :wings_we.visible(we), do: :wings_face.vertices_ccw(f, we)
    {tris, fn v -> :array.get(v, vp) end}
  end

  # A corner takes the mean normal of the faces at its point that are
  # within `angle` of its own face: so a box has hard edges and a
  # cylinder has a smooth side.
  defp normals(tris, pos, angle) do
    face_n = Enum.map(tris, fn [a, b, c] -> Vec.cross(Vec.sub(pos.(b), pos.(a)), Vec.sub(pos.(c), pos.(a))) end)

    at_vertex =
      tris
      |> Enum.zip(face_n)
      |> Enum.flat_map(fn {vs, n} -> for v <- vs, do: {v, n} end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    limit = :math.cos(angle * :math.pi() / 180) - 1.0e-6

    for {vs, n} <- Enum.zip(tris, face_n), v <- vs do
      unit = Vec.norm(n)
      near = for other <- at_vertex[v], Vec.dot(Vec.norm(other), unit) >= limit, do: other
      {pos.(v), Vec.norm(Enum.reduce(near, &Vec.add/2))}
    end
  end
end
