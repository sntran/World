defmodule World.Mesh do
  @moduledoc """
  A mesh of one material: points, and faces as lists of point indices.
  Each face turns counterclockwise when the eye is outside the shape.

  The core of Wings 3D builds the mesh (`wings_we:build/2`), smooths it
  `smooth` times (Catmull-Clark, `wings_subdiv:smooth/1`), and cuts it
  into triangles (`wings_tesselation:triangulate/2`).
  """
  alias World.{Frame, Vec}

  defstruct points: [],
            faces: [],
            material: :paint,
            smooth: 0,
            angle: 40.0,
            skin: nil,
            matter: nil,
            normals: nil,
            colors: nil

  @type t :: %__MODULE__{
          points: [Vec.t()],
          faces: [[non_neg_integer]],
          material: atom,
          smooth: non_neg_integer,
          angle: number,
          skin: number | nil,
          matter: atom | nil,
          normals: [Vec.t()] | nil,
          colors: [{0..255, 0..255, 0..255}] | nil
        }

  @doc """
  A mesh that is the skin of a thing, of a thickness (m) and a material
  (`World.Mass`): a panel of a body, a shell of a light. Its mass is its
  area times the thickness times the density of the material; it has no
  inside (`World.Check`). The thickness is on each face: a closed mesh
  around a sheet has two faces, so it takes half of the sheet.

      iex> m = World.Mesh.skin(World.Shape.box({0, 0, 0}, {1, 1, 1}, :paint), 0.001, :plastic)
      iex> {m.skin, m.matter, m.material}
      {0.001, :plastic, :paint}
  """
  def skin(%__MODULE__{} = mesh, thickness, matter), do: %{mesh | skin: thickness / 1, matter: matter}

  @doc """
  A mesh of a material for its mass, when its material role is a color
  (`:paint`, `:trim`): a seat of foam in the color of the trim.

      iex> World.Mesh.matter(World.Shape.box({0, 0, 0}, {1, 1, 1}, :trim), :plastic).matter
      :plastic
  """
  def matter(%__MODULE__{} = mesh, matter), do: %{mesh | matter: matter}

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

  @doc """
  A mesh of triangles with the normal of each point (unit vectors: the
  normals of the true surface, where the mesh comes from a field) and,
  or, the color of each point (`{r, g, b}`, 0 to 255, which the color of
  the material multiplies). A corner takes the normal of its point when
  it is within the angle of the mesh from the normal of its face (a hard
  edge stays hard: there the rule of the angle holds, `triangles/2`).
  """
  def finish(%__MODULE__{} = mesh, normals, colors), do: %{mesh | normals: normals, colors: colors}

  @doc "The mesh, moved by a frame."
  def transform(%__MODULE__{points: ps, normals: ns} = m, %Frame{} = f),
    do: %{m | points: Enum.map(ps, &Frame.point(f, &1)), normals: ns && Enum.map(ns, &Frame.dir(f, &1))}

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
  A mesh with the colors of its points (`finish/3`) gives corners
  `{point, normal, color}`.
  """
  def triangles(%__MODULE__{} = m, level \\ nil) do
    level = if level == nil, do: m.smooth, else: level
    {tris, pos} = wings_triangles(m, level)
    corners = normals(tris, pos, if(level > 0, do: 180.0, else: m.angle))
    if m.normals || m.colors, do: own(m, corners), else: corners
  end

  # The corners with the normals and the colors of the points of the mesh
  # (a mesh of triangles: its faces are its triangles, in their order).
  defp own(%__MODULE__{faces: faces, normals: normals, colors: colors, angle: angle}, corners) do
    limit = :math.cos(angle * :math.pi() / 180) - 1.0e-6
    {nt, ct} = {normals && List.to_tuple(normals), colors && List.to_tuple(colors)}

    faces
    |> Enum.zip(Enum.chunk_every(corners, 3))
    |> Enum.flat_map(fn {vs, [{a, _}, {b, _}, {c, _}] = cs} ->
      face = Vec.norm(Vec.cross(Vec.sub(b, a), Vec.sub(c, a)))

      for {v, {p, n}} <- Enum.zip(vs, cs) do
        n = if nt && Vec.dot(elem(nt, v), face) >= limit, do: elem(nt, v), else: n
        if ct, do: {p, n, elem(ct, v)}, else: {p, n}
      end
    end)
  end

  # A mesh of triangles only (a cast, a skin of surface nets) needs no
  # pass of Wings: its faces are its triangles.
  defp wings_triangles(%__MODULE__{points: ps, faces: fs}, 0)
       when fs != [] and is_list(hd(fs)) and length(hd(fs)) == 3 do
    if Enum.all?(fs, &match?([_, _, _], &1)) do
      t = List.to_tuple(ps)
      {fs, &elem(t, &1)}
    else
      wings(ps, fs, 0)
    end
  end

  defp wings_triangles(%__MODULE__{points: ps, faces: fs}, level), do: wings(ps, fs, level)

  defp wings(ps, fs, level) do
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
