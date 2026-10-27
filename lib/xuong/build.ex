defmodule Xuong.Build do
  @moduledoc """
  The build of a model (a part or an assembly) into a `Xuong.Scene`, at a
  level of detail and in a pose, and the list of its parts.

  - The parts that connect with `:fixed` go into the node of their
    parent. Each joint (`:turns`, `:slides`) is a node: its frame is the
    port of its parent, and it turns or moves along its own z axis (the
    y axis in glTF).
  - The levels (`docs/format.md`, "The levels of detail"): `:near` has
    each part; `:mid` drops the parts shorter than 2 cm or thinner than
    3 mm, and the parts `inside`; `:far` drops the parts shorter than
    10 cm or thinner than 1 cm. Each level smooths one step less.
  """
  alias Xuong.{Assembly, Figure, Frame, GLB, Mesh, Part, Scene, Vec}
  alias Xuong.Assembly.Connection

  @limits %{near: {0.0, 0.0}, mid: {0.02, 0.003}, far: {0.10, 0.01}}

  @doc """
  The scene of a model. The options: `level` (`:near`, `:mid` or `:far`)
  and `pose` (a map of a joint name to its value: degrees or meters).
  """
  def scene(item, opts \\ []) do
    level = Keyword.get(opts, :level, :near)
    pose = Keyword.get(opts, :pose, %{})
    name = item.name
    root = %Scene.Node{name: name}

    acc =
      walk(
        item,
        Frame.identity(),
        0,
        %{nodes: [root], parts: %{0 => []}, skins: [], animations: [], materials: %{}},
        level,
        pose
      )

    {nodes, _} = finish(acc)

    scene = %Scene{name: name, nodes: nodes, skins: acc.skins, animations: acc.animations, materials: acc.materials}
    {lo, hi} = if Scene.triangles(scene) > 0, do: Scene.bounds(scene), else: {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}}
    size = Vec.sub(hi, lo)

    extras = %{
      "name" => name,
      "kind" => Atom.to_string(Map.get(item, :kind, :part)),
      "level" => Atom.to_string(level),
      "size" => for(v <- Tuple.to_list(size), do: Float.round(v / 1, 4)),
      "sources" => Map.get(item, :sources, []),
      "joints" => for(n <- nodes, n.extras["role"], do: n.name)
    }

    %{scene | extras: Map.merge(extras, Map.get(item, :extras, %{}))}
  end

  @doc "Write the GLB of a model at a level, in a pose."
  def glb(item, opts \\ []), do: GLB.encode(scene(item, opts))

  # The root of the figure goes under the node; a skinned mesh stays a
  # root node (its bones place it).
  defp figure_parent(0, _, node, _), do: node
  defp figure_parent(_, %{parent: nil}, _, _), do: nil
  defp figure_parent(_, %{parent: p}, _, offset), do: p + offset

  # Walk the tree of a model. A part goes into the list of its node; a
  # node of an assembly goes into the node of its parent, or into a new
  # node for a joint.
  # A figure (a person) brings its own nodes, skin, animations and
  # materials: its root goes at the frame, under the node.
  defp walk(%Figure{} = f, frame, node, acc, _level, _pose) do
    offset = length(acc.nodes)
    skins = length(acc.skins)

    nodes =
      for {n, i} <- Enum.with_index(f.nodes) do
        %{
          n
          | parent: figure_parent(i, n, node, offset),
            frame: if(i == 0, do: Frame.compose(frame, n.frame), else: n.frame),
            skin: n.skin && n.skin + skins
        }
      end

    %{
      acc
      | nodes: acc.nodes ++ nodes,
        parts: Map.merge(acc.parts, Map.new(offset..(offset + length(nodes) - 1), &{&1, []})),
        skins:
          acc.skins ++
            for(s <- f.skins, do: %{s | joints: Enum.map(s.joints, &(&1 + offset)), skeleton: s.skeleton + offset}),
        animations:
          acc.animations ++
            for(a <- f.animations, do: %{a | channels: Enum.map(a.channels, &%{&1 | node: &1.node + offset})}),
        materials: Map.merge(acc.materials, f.materials)
    }
  end

  defp walk(%Part{} = p, frame, node, acc, level, _pose) do
    if keep?(p, level), do: update_in(acc.parts[node], &[{frame, p} | &1]), else: acc
  end

  defp walk(%Assembly{nodes: [{root, root_item, nil} | rest], place: place}, frame, node, acc, level, pose) do
    frame = Frame.compose(frame, place)
    acc = walk(root_item, frame, node, acc, level, pose)
    places = %{root => {node, frame}}

    {acc, _} =
      Enum.reduce(rest, {acc, places}, fn {name, item, %Connection{} = c}, {acc, places} ->
        {parent_node, parent_frame} = Map.fetch!(places, c.to)
        a = %Assembly{nodes: [{root, root_item, nil} | rest], place: Frame.identity()}
        port = Frame.compose(parent_frame, port_in_node(a, c))

        if c.kind == :fixed do
          f = Frame.compose(port, Assembly.placement(c, item, 0.0))
          {walk(item, f, parent_node, acc, level, pose), Map.put(places, name, {parent_node, f})}
        else
          # The name of a joint is its own name: three.js removes "/" from
          # the names of nodes. Two joints of a model cannot have one name.
          if Enum.any?(acc.nodes, &(&1.name == name)), do: raise(ArgumentError, "two joints have the name #{name}")
          value = Map.get(pose, name, 0.0) / 1

          joint = %Scene.Node{
            name: name,
            parent: parent_node,
            frame: Frame.compose(port, motion(c.kind, value)),
            extras: %{
              "role" => Atom.to_string(c.role),
              "kind" => Atom.to_string(c.kind),
              "axis" => [0.0, 1.0, 0.0],
              "limits" => c.limits
            }
          }

          id = length(acc.nodes)
          acc = %{acc | nodes: acc.nodes ++ [joint], parts: Map.put(acc.parts, id, [])}
          f = Assembly.placement(c, item, 0.0)
          {walk(item, f, id, acc, level, pose), Map.put(places, name, {id, f})}
        end
      end)

    acc
  end

  # The frame of the port `at` of the node `to`, in the axes of that node.
  defp port_in_node(%Assembly{nodes: nodes}, %Connection{to: to, at: at}) do
    {_, item, _} = List.keyfind(nodes, to, 0)
    Assembly.item_port_frame(item, at)
  end

  # The motion of a joint: a turn around its z axis, or a move along it.
  defp motion(:turns, deg), do: Frame.turn({0.0, 0.0, 1.0}, deg)
  defp motion(:slides, d), do: Frame.move({0.0, 0.0, d})

  defp finish(%{nodes: nodes, parts: parts}) do
    nodes =
      for {n, i} <- Enum.with_index(nodes) do
        corners =
          parts[i]
          |> Enum.reverse()
          |> Enum.flat_map(fn {f, p} -> for m <- p.shapes, do: {m.material, place(triangles(m), f)} end)
          |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

        prims = for {mat, lists} <- Enum.sort_by(corners, &elem(&1, 0)), do: Scene.primitive(mat, Enum.concat(lists))
        %{n | primitives: n.primitives ++ prims}
      end

    {nodes, parts}
  end

  defp place(corners, f), do: for({p, n} <- corners, do: {Frame.point(f, p), Frame.dir(f, n)})

  # The triangles of a mesh, kept for the next part with the same mesh.
  defp triangles(%Mesh{} = m) do
    key = {:xuong_tris, :erlang.phash2(m)}

    case Process.get(key) do
      nil -> tap(Mesh.triangles(m), &Process.put(key, &1))
      tris -> tris
    end
  end

  defp keep?(%Part{detail: :always}, _), do: true
  defp keep?(%Part{}, :near), do: true
  defp keep?(%Part{detail: :near}, _), do: false
  defp keep?(%Part{inside: true}, _), do: false

  defp keep?(%Part{} = p, level) do
    {long, thin} = Map.fetch!(@limits, level)
    {lo, hi} = Part.bounds(p)
    sides = Tuple.to_list(Vec.sub(hi, lo))
    Enum.max(sides) >= long and Enum.min(sides) >= thin
  end

  @doc "The list of the parts of a model, each with its count, in the order of the names."
  def parts(item) do
    item
    |> all_parts()
    |> Enum.frequencies_by(&{&1.name, &1.kind, &1.params, &1.sources})
    |> Enum.map(fn {{name, kind, params, sources}, count} ->
      %{"name" => name, "kind" => Atom.to_string(kind), "count" => count, "params" => params, "sources" => sources}
    end)
    |> Enum.sort_by(& &1["name"])
  end

  defp all_parts(%Part{} = p), do: [p]
  defp all_parts(%Figure{} = f), do: [%Part{name: f.name, kind: f.kind, params: f.params, sources: f.sources}]
  defp all_parts(%Assembly{nodes: nodes}), do: Enum.flat_map(nodes, fn {_, item, _} -> all_parts(item) end)
end
