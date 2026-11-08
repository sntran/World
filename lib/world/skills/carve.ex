defmodule World.Skills.Carve do
  @moduledoc """
  The skill `carve` of a sculptor (plan 0004, D4): the head and the
  hands of a statue at near, carved in its stone from the full mesh of
  the person (the `carved` pieces of the node `figure`). A face cannot be
  cast in cells of 0.32 m; on a real statue a sculptor makes the head and
  the hands. At mid and far the cast has them. Its data: `meshes`.
  """
  @behaviour World.Skill
  alias World.Mesh
  alias World.Skills.Statue

  @names ~w(material)

  @impl true
  def name, do: "carve"

  @impl true
  def trade, do: :sculptor

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  # The head with its eyes and the two hands of the full mesh.
  @impl true
  def estimate(_data, :near), do: 12_000
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, %{"figure" => %{"figure" => fig}}, _context) do
    o = Statue.o(data, @names)
    {look, matter} = Statue.material(o.material)

    meshes =
      for {_name, {points, tris}} <- Map.get(fig, :carved, []),
          tris != [],
          do: Mesh.new(points, tris, look) |> Mesh.matter(matter)

    {nil, %{"meshes" => meshes}, %{}}
  end
end
