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
  """
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
            joints: []

  @doc "A port of the figure, by its name."
  def port!(%__MODULE__{ports: ports, name: name}, port) do
    Map.get(ports, port) || raise ArgumentError, "the figure #{name} has no port #{inspect(port)}"
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
