defmodule World.Mirror do
  @moduledoc """
  The mirror image of a thing across the plane x = 0: the left shoe of a
  right shoe, the left part of a pair.

  A point `{x, y, z}` goes to `{-x, y, z}`. Each face turns over (the
  order of its corners reverses), so the outside stays outside. A port
  keeps its place in the mirror, and a frame `F` becomes `S F D` (`S` the
  mirror of the world, `D` the mirror of the x of the frame): it is still
  a turn, with no mirror in it. So a node of an assembly goes to the
  mirror of its place, if its connection turns the other way: the turn of
  a connection and the value of a hinge change sign, and the limits of a
  hinge `[a, b]` become `[-b, -a]`.
  """
  alias World.{Assembly, Frame, Mesh, Part, Port}

  @doc """
  The mirror of a mesh.

      iex> m = World.Mirror.mesh(World.Shape.box({0.1, 0.0, 0.0}, {0.2, 0.1, 0.1}, :steel))
      iex> World.Mesh.bounds(m)
      {{-0.2, 0.0, 0.0}, {-0.1, 0.1, 0.1}}
      iex> World.Mesh.volume(m.points, m.faces) > 0
      true
  """
  def mesh(%Mesh{points: points, faces: faces} = m),
    do: %{m | points: Enum.map(points, &point/1), faces: Enum.map(faces, &Enum.reverse/1)}

  @doc "The mirror of a port."
  def port(%Port{} = p), do: %{p | at: point(p.at), axis: point(p.axis), up: point(p.up)}

  @doc "The mirror of a frame (still a turn and a move)."
  def frame(%Frame{x: x, y: y, z: z, at: at}),
    do: %Frame{x: World.Vec.scale(point(x), -1.0), y: point(y), z: point(z), at: point(at)}

  @doc """
  The mirror of a part, with a new name (its own by default). It keeps
  the meshes of the part it comes from in `mirror`: a build writes them
  once, with a scale of -1 on x for the mirror. The mirror of a mirror
  is the part it comes from.
  """
  def part(%Part{} = p, name \\ nil) do
    {shapes, mirror} =
      case source(p) do
        nil -> {Enum.map(p.shapes, &mesh/1), p.shapes}
        source -> {source, nil}
      end

    %{
      p
      | name: name || p.name,
        shapes: shapes,
        mirror: mirror,
        ports: Map.new(p.ports, fn {n, port} -> {n, port(port)} end)
    }
  end

  @doc """
  The meshes that a part is the mirror of, or nil: nil for a part that is
  not a mirror, and for a mirror whose meshes changed after the mirror.
  """
  def source(%Part{mirror: nil}), do: nil
  def source(%Part{mirror: source, shapes: shapes}), do: if(Enum.map(source, &mesh/1) == shapes, do: source)

  @doc """
  The mirror of an assembly, with a new name (its own by default): each
  node holds the mirror of its part or of its smaller assembly. An
  assembly with a figure (a person) has no mirror here.
  """
  def assembly(%Assembly{} = a, name \\ nil) do
    nodes =
      for {n, item, conn} <- a.nodes do
        {n, item(item), connection(conn)}
      end

    hinges = for {n, _, %{kind: :hinge}} <- a.nodes, into: MapSet.new(), do: n

    clips =
      for clip <- a.clips do
        %{
          clip
          | keys:
              for(
                {t, values} <- clip.keys,
                do: {t, Map.new(values, fn {j, v} -> {j, if(MapSet.member?(hinges, j), do: -v, else: v)} end)}
              )
        }
      end

    %{a | name: name || a.name, nodes: nodes, place: frame(a.place), clips: clips}
  end

  defp item(%Part{} = p), do: part(p)
  defp item(%Assembly{} = a), do: assembly(a)
  defp item(other), do: raise(ArgumentError, "no mirror of #{inspect(other.__struct__)}")

  defp connection(nil), do: nil

  defp connection(%Assembly.Connection{} = c) do
    limits =
      case {c.kind, c.limits} do
        {:hinge, [a, b]} -> [-b, -a]
        {_, limits} -> limits
      end

    %{c | turn: -c.turn, limits: limits, at: port_or_name(c.at), port: port_or_name(c.port)}
  end

  defp port_or_name(%Port{} = p), do: port(p)
  defp port_or_name(name), do: name

  defp point({x, y, z}), do: {-x / 1, y / 1, z / 1}
end
