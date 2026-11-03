defmodule World.Mass do
  @moduledoc """
  The mass of the things of the world (`docs/world.md`, step P4): a part
  has the mass of its meshes, each the volume of the mesh times the
  density of its material (`priv/standards/materials.json`, with the
  source of each density). An assembly has the mass of its parts at
  their places, and its center of mass.

  Only a closed mesh has a volume (each edge in two faces). A part with
  an open mesh, or a mesh of a role with no density (a paint, a color),
  has no mass: `part/1` gives `nil`, and `of/1` names it in `unknown`.
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
        with d when is_number(d) <- density(m.material), {v, c} <- mesh(m), do: {d * v, c}
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
