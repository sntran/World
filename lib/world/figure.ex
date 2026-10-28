defmodule World.Figure do
  @moduledoc """
  A figure with a skeleton: a person. It is a part of a scene that is
  ready: its nodes (the root, the bones, and the mesh with its skin),
  its skin, its animations and its materials. An assembly can hold a
  figure as a node, as a part (`World.Build`).

  The indices of nodes are local: node 0 is the root of the figure, and
  the parent of each other node is a local index.
  """
  defstruct name: "figure",
            kind: :person,
            params: %{},
            sources: [],
            nodes: [],
            skins: [],
            animations: [],
            materials: %{},
            ports: %{}

  @doc "A port of the figure, by its name."
  def port!(%__MODULE__{ports: ports, name: name}, port) do
    Map.get(ports, port) || raise ArgumentError, "the figure #{name} has no port #{inspect(port)}"
  end
end
