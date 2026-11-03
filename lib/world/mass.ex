defmodule World.Mass do
  @moduledoc """
  The mass of the things of the world (`docs/world.md`, step P4): a part
  has the mass of its meshes, each the volume of the mesh times the
  density of its material (`priv/standards/materials.json`, with the
  source of each density). An assembly has the mass of its parts at
  their places, and its center of mass.

  Only a closed mesh has a volume (each edge in two faces). A skin
  (`World.Mesh.skin/3`: a panel, open or closed) has its area times its
  thickness. A mesh of a color role (`:paint`, `:trim`) takes the density
  of its `matter` (`World.Mesh.matter/2`). A part with an open mesh that
  is not a skin, or a mesh with no density, has no mass: `part/1` gives
  `nil`, and `of/1` names it in `unknown`.
  """
  alias World.{Build, Frame, Mesh, Part, Standards, Vec}

  @doc """
  The density of a material role (kg/m³), or nil.

      iex> World.Mass.density(:steel)
      7820
      iex> World.Mass.density(:paint)
      nil
  """
  def density(role) do
    case Map.get(Standards.table("materials", "density")["sizes"], Atom.to_string(role)) do
      [d | _] -> d
      nil -> nil
    end
  end

  @doc """
  The volume (m³) and the centroid of a closed mesh, or nil for an open
  one.

      iex> {v, c} = World.Mass.mesh(World.Shape.box({0, 0, 0}, {1, 2, 3}, :steel))
      iex> {Float.round(v, 6), c}
      {6.0, {0.5, 1.0, 1.5}}
  """
  def mesh(%Mesh{points: points, faces: faces}) do
    if closed?(faces) do
      pt = List.to_tuple(points)

      {v, m} =
        for [a | rest] <- faces, [b, c] <- Enum.chunk_every(rest, 2, 1, :discard), reduce: {0.0, {0.0, 0.0, 0.0}} do
          {v, m} ->
            {pa, pb, pc} = {elem(pt, a), elem(pt, b), elem(pt, c)}
            t = Vec.dot(pa, Vec.cross(pb, pc)) / 6
            {v + t, Vec.add(m, Vec.scale(Vec.add(Vec.add(pa, pb), pc), t / 4))}
        end

      if v > 0, do: {v, Vec.scale(m, 1 / v)}, else: nil
    end
  end

  # The volume and the center of a mesh: of its skin, or of its inside.
  defp volume(%Mesh{skin: nil} = m), do: mesh(m)
  defp volume(%Mesh{skin: t} = m), do: with({a, c} <- area(m), do: {a * t, c})

  @doc """
  The area (m²) and the center of the area of a mesh, or nil for a mesh
  with no area.

      iex> {a, c} = World.Mass.area(World.Shape.box({0, 0, 0}, {1, 2, 3}, :steel))
      iex> {Float.round(a, 6), c}
      {22.0, {0.5, 1.0, 1.5}}
  """
  def area(%Mesh{points: points, faces: faces}) do
    pt = List.to_tuple(points)

    {a, m} =
      for [i | rest] <- faces, [j, k] <- Enum.chunk_every(rest, 2, 1, :discard), reduce: {0.0, {0.0, 0.0, 0.0}} do
        {a, m} ->
          {pa, pb, pc} = {elem(pt, i), elem(pt, j), elem(pt, k)}
          t = Vec.len(Vec.cross(Vec.sub(pb, pa), Vec.sub(pc, pa))) / 2
          {a + t, Vec.add(m, Vec.scale(Vec.add(Vec.add(pa, pb), pc), t / 3))}
      end

    if a > 0, do: {a, Vec.scale(m, 1 / a)}, else: nil
  end

  # Each edge of a closed mesh is in two faces.
  defp closed?(faces) do
    faces
    |> Enum.flat_map(fn f -> Enum.zip(f, tl(f) ++ [hd(f)]) end)
    |> Enum.frequencies_by(fn {a, b} -> {min(a, b), max(a, b)} end)
    |> Enum.all?(fn {_, n} -> n == 2 end)
  end

  @doc """
  The mass of a part (kg) and its center of mass (in the axes of the
  part), or nil: `%{mass, center}`.
  """
  def part(%Part{shapes: shapes}) do
    parts =
      Enum.map(shapes, fn m ->
        with d when is_number(d) <- density(m.matter || m.material), {v, c} <- volume(m), do: {d * v, c}
      end)

    if shapes != [] and Enum.all?(parts, &is_tuple/1) do
      mass = parts |> Enum.map(&elem(&1, 0)) |> Enum.sum()
      center = parts |> Enum.map(fn {m, c} -> Vec.scale(c, m) end) |> Enum.reduce(&Vec.add/2) |> Vec.scale(1 / mass)
      %{mass: mass, center: center}
    end
  end

  @doc """
  The mass of a model (kg), its center of mass (in the axes of the model)
  and the names of its parts with no mass: `%{mass, center, unknown}`.
  """
  def of(item) do
    {known, unknown} =
      item
      |> Build.placed()
      |> Enum.map(fn {f, p} -> {p.name, part(p), f} end)
      |> Enum.split_with(fn {_, m, _} -> m end)

    mass = known |> Enum.map(fn {_, m, _} -> m.mass end) |> Enum.sum() |> Kernel.*(1.0)

    center =
      if mass > 0,
        do:
          known
          |> Enum.map(fn {_, m, f} -> Vec.scale(Frame.point(f, m.center), m.mass) end)
          |> Enum.reduce(&Vec.add/2)
          |> Vec.scale(1 / mass),
        else: nil

    %{mass: mass, center: center, unknown: unknown |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()}
  end
end
