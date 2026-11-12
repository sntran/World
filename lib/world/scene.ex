defmodule World.Scene do
  @moduledoc """
  A scene for the GLB writer: a list of nodes (each with its parent, its
  frame and its primitives), skins and animations. `World.Build` makes it
  from a model; `World.GLB` writes it.

  The points and the frames are in the axes of World (x to the right
  side, y to the front, z up). The writer turns them to the axes of glTF.
  """
  alias World.{Frame, Vec}
  defstruct name: "model", extras: %{}, nodes: [], skins: [], animations: [], materials: %{}

  defmodule Node do
    @moduledoc """
    A node: its name, the index of its parent (or nil), its frame relative
    to the parent, and its scale after the frame: a number (the same on
    each axis: the size of the head of a person) or `{x, y, z}` (`{-1.0,
    1.0, 1.0}`: a mirror).

    - `mesh`: a key of its primitives, or nil. The nodes with one key
      have the same primitives: the GLB has them once.
    - `instances`: nil, or a list of frames in the node: the node shows
      its primitives at each frame (a wall of bricks), in place of once.
    """
    defstruct name: "node",
              parent: nil,
              frame: %World.Frame{},
              scale: 1.0,
              primitives: [],
              extras: %{},
              skin: nil,
              mesh: nil,
              instances: nil
  end

  defmodule Primitive do
    @moduledoc """
    The triangles of one material: points, normals, an index list, and
    optional UV, joints (4 for each point), weights (4 for each point),
    colors (`{r, g, b}`, 0 to 255, for each point), the length of the
    fur of each point (m) and the direction of the fur of each point (a
    unit vector along the skin, at rest), and the morph targets (a list of
    `{name, moves}` or `{name, moves, normals}`, a move for each point and
    a change of each normal: the shapes of a face). The moves (or the
    changes) can also be a map of the index of a point to its move: the
    points not in the map do not move (a shape of the face moves few of
    the points of a body). `uvs2` is a second UV set (`TEXCOORD_1`), and
    `data` a list of `{r, g, b, a}` (0 to 1) for each point that goes
    into `COLOR_0` as it is: numbers for a shader of an app, not colors
    (`World.Surface`).
    """
    defstruct material: :paint,
              positions: [],
              normals: [],
              indices: [],
              uvs: nil,
              joints: nil,
              weights: nil,
              colors: nil,
              fur: nil,
              fur_dirs: nil,
              targets: nil,
              uvs2: nil,
              data: nil
  end

  @doc """
  A primitive from the corners of `World.Mesh.triangles/2` (three for
  each triangle). Corners with the same point and normal share an index.
  """
  def primitive(material, corners), do: primitive(material, [corners], & &1)

  @doc """
  A primitive from many lists of corners, with no list of all of them:
  `place` gives the corners of each item of `items` when it comes to it
  (a mesh at its place), so only the points of the primitive are live,
  not each corner. The same primitive as `primitive/2` of all the corners
  in their order.
  """
  def primitive(material, items, place) do
    {indices, verts, _seen, _count} =
      Enum.reduce(items, {[], [], %{}, 0}, fn item, acc ->
        Enum.reduce(place.(item), acc, fn {p, n}, {indices, verts, seen, count} ->
          {rp, rn} = {round6(p), round6(n)}
          key = key(rp, rn)

          case seen do
            %{^key => i} -> {[i | indices], verts, seen, count}
            _ -> {[count | indices], [{rp, rn} | verts], Map.put(seen, key, count), count + 1}
          end
        end)
      end)

    verts = Enum.reverse(verts)

    %Primitive{
      material: material,
      positions: Enum.map(verts, &elem(&1, 0)),
      normals: Enum.map(verts, &elem(&1, 1)),
      indices: Enum.reverse(indices)
    }
  end

  # The key of a corner in the map of the points seen: a binary of its six
  # numbers (smaller than two tuples of boxed floats; the same keys:
  # 0.0 and -0.0 are two keys in each).
  defp key({a, b, c}, {d, e, f}), do: <<a::float-64, b::float-64, c::float-64, d::float-64, e::float-64, f::float-64>>

  defp round6({x, y, z}), do: {Float.round(x / 1, 6), Float.round(y / 1, 6), Float.round(z / 1, 6)}

  @doc """
  The number of triangles that a scene draws: each instance of a node
  counts, and a collision box (`extras.collision`) does not.
  """
  def triangles(%__MODULE__{nodes: nodes}) do
    for n <- nodes, not Map.has_key?(n.extras, "collision"), p <- n.primitives, reduce: 0 do
      sum -> sum + div(length(p.indices), 3) * length(n.instances || [nil])
    end
  end

  @doc """
  The frame of each node in the axes of the scene, by index. The frame of
  a node with a scale has the scale in its axes.
  """
  def world_frames(%__MODULE__{nodes: nodes}) do
    nodes
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {n, i}, acc ->
      local = scaled(n.frame, n.scale)
      Map.put(acc, i, if(n.parent == nil, do: local, else: Frame.compose(acc[n.parent], local)))
    end)
  end

  defp scaled(frame, 1.0), do: frame

  defp scaled(%Frame{x: x, y: y, z: z} = f, {a, b, c}),
    do: %{f | x: Vec.scale(x, a), y: Vec.scale(y, b), z: Vec.scale(z, c)}

  defp scaled(f, s), do: scaled(f, {s, s, s})

  @doc """
  The box of all points of the scene, in its axes: `{min, max}`. The
  points of a skinned mesh move with their bones. A collision box
  (`extras.collision`) is not in it.
  """
  def bounds(%__MODULE__{nodes: nodes, skins: skins} = scene) do
    frames = world_frames(scene)

    nodes
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {%{extras: %{"collision" => _}}, _} ->
        []

      {%{skin: nil} = n, i} ->
        for f <- places(frames[i], n.instances), p <- n.primitives, pt <- p.positions, do: Frame.point(f, pt)

      {n, _} ->
        skinned(n, Enum.at(skins, n.skin), frames)
    end)
    |> Vec.bounds()
  end

  defp places(frame, nil), do: [frame]
  defp places(frame, instances), do: Enum.map(instances, &Frame.compose(frame, &1))

  defp skinned(node, skin, frames) do
    bones =
      skin.joints
      |> Enum.zip(skin.inverse_bind)
      |> Enum.map(fn {j, ib} -> Frame.compose(frames[j], ib) end)
      |> List.to_tuple()

    for p <- node.primitives, {pt, js, ws} <- Enum.zip([p.positions, p.joints, p.weights]) do
      Enum.zip(Tuple.to_list(js), Tuple.to_list(ws))
      |> Enum.map(fn {j, w} -> Vec.scale(Frame.point(elem(bones, j), pt), w) end)
      |> Enum.reduce(&Vec.add/2)
    end
  end
end
