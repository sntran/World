defmodule World.Figure do
  @moduledoc """
  A figure with a skeleton: a person. It is a part of a scene that is
  ready: its nodes (the root, the bones, and the mesh with its skin),
  its skin, its animations and its materials. An assembly can hold a
  figure as a node, as a part (`World.Build`).

  The indices of nodes are local: node 0 is the root of the figure, and
  the parent of each other node is a local index.

  A figure keeps its `skeleton` and its `pose` (`World.People.Skeleton`)
  and its `joints` (`World.Joint`s): an order can change the values of
  its joints (`pose/2`).

  A port of a figure can be on a bone (`World.Port`, `bone`). The props
  of a figure (`hold/4`) are on such ports: the build puts each prop in
  the node of its bone, so it follows the bone in each pose and
  animation. A node of an assembly that connects to a port on a bone
  also goes in the node of the bone.
  """
  alias World.{Assembly, Frame, Port}
  alias World.People.{Joints, Skeleton}

  defstruct name: "figure",
            kind: :person,
            params: %{},
            sources: [],
            nodes: [],
            skins: [],
            animations: [],
            materials: %{},
            ports: %{},
            skeleton: nil,
            pose: %{},
            joints: [],
            props: []

  @doc "A port of the figure, by its name."
  def port!(%__MODULE__{ports: ports, name: name}, port) do
    Map.get(ports, port) || raise ArgumentError, "the figure #{name} has no port #{inspect(port)}"
  end

  @doc """
  The frame of a port of the figure, in the axes of the figure, in its
  pose: a port on a bone moves with the bone.
  """
  def port_frame(%__MODULE__{} = f, name) do
    case port!(f, name) do
      %Port{bone: nil} = p -> Port.frame(p)
      %Port{bone: bone} = p -> Frame.compose(bone_frame(f, bone), Port.frame(p))
    end
  end

  @doc "The index of the node of a bone in the nodes of the figure."
  def bone_node(%__MODULE__{nodes: [_ | bones], name: name}, bone) do
    case Enum.find_index(bones, &(&1.name == bone)) do
      nil -> raise ArgumentError, "the figure #{name} has no bone #{inspect(bone)}"
      i -> i + 1
    end
  end

  @doc "The frame of a bone in the axes of the figure, in its pose."
  def bone_frame(%__MODULE__{nodes: nodes} = f, bone), do: chain(List.to_tuple(nodes), bone_node(f, bone))

  defp chain(nodes, i) do
    case elem(nodes, i) do
      %{parent: nil, frame: frame} -> frame
      %{parent: p, frame: frame} -> Frame.compose(chain(nodes, p), frame)
    end
  end

  @doc """
  The figure with a prop (a part or an assembly) on its port `port`: the
  port `item_port` of the prop (`"grip"` by default) on the port of the
  figure.
  """
  def hold(%__MODULE__{} = f, port, item, item_port \\ "grip") do
    _ = port!(f, port)
    _ = Assembly.item_port_frame(item, item_port)
    %{f | props: f.props ++ [{port, item, item_port}]}
  end

  @doc "The names of the values of the joints of the figure, for an order."
  def values(%__MODULE__{joints: joints}), do: Enum.flat_map(joints, &World.Joint.values/1)

  @doc """
  The figure with the values of its joints (a map of a value name to a
  number, `World.People.Joints`): its bones turn to the new pose.
  """
  def pose(%__MODULE__{} = f, values) when values == %{}, do: f

  def pose(%__MODULE__{skeleton: s} = f, values) do
    locals = Skeleton.locals(s, Joints.pose(f.pose, values))

    nodes =
      for {n, i} <- Enum.with_index(f.nodes),
          do: if(i > 0 and Map.has_key?(locals, n.name), do: %{n | frame: locals[n.name]}, else: n)

    %{f | nodes: nodes}
  end
end
