defmodule World.Skills.Grille do
  @moduledoc """
  The skill `grille` of a smith: the grille of each window of a hollow
  statue, at near, in the openings of its shell (the node `shell`). By
  eye from the photos: a square pattern in each opening, a frame and a
  cross of bars, 0.15 m in from the front of the robe round the opening.
  Its data: `meshes`.
  """
  @behaviour World.Skill
  alias World.{Mesh, Shape}
  alias World.Skills.Statue

  @names ~w(material hollow windows)

  @impl true
  def name, do: "grille"

  @impl true
  def trade, do: :smith

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  # Seven boxes of 12 triangles for each window.
  @impl true
  def estimate(data, :near), do: 84 * length(Map.get(data, "windows", []))
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, %{"shell" => %{"shell" => shell}}, %{level: level}) do
    o = Statue.o(data, @names)
    {look, matter} = Statue.material(o.material)
    meshes = if o.hollow and level == :near, do: Enum.flat_map(o.windows, &grille(shell, &1, look, matter)), else: []
    {nil, %{"meshes" => meshes}, %{}}
  end

  defp grille(shell, {z, w, h}, look, matter) do
    front =
      shell.points
      |> Enum.filter(fn {x, y, pz} -> abs(x) < w / 2 + 0.5 and abs(pz - z) < h / 2 + 0.5 and y > 0 end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.max()

    {y0, y1, t} = {front - 0.25, front - 0.15, 0.1}
    {x0, x1, z0, z1} = {-w / 2, w / 2, z - h / 2, z + h / 2}

    [
      {{x0, y0, z0}, {x1, y1, z0 + t}},
      {{x0, y0, z1 - t}, {x1, y1, z1}},
      {{x0, y0, z0 + t}, {x0 + t, y1, z1 - t}},
      {{x1 - t, y0, z0 + t}, {x1, y1, z1 - t}},
      {{-t / 2, y0, z0 + t}, {t / 2, y1, z1 - t}},
      {{x0 + t, y0, z - t / 2}, {-t / 2, y1, z + t / 2}},
      {{t / 2, y0, z - t / 2}, {x1 - t, y1, z + t / 2}}
    ]
    |> Enum.map(fn {a, b} -> Shape.box(a, b, look) |> Mesh.matter(matter) end)
  end
end
