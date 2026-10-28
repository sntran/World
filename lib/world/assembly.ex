defmodule World.Assembly do
  @moduledoc """
  An assembly: a tree of named nodes. The first node is the root. Each
  other node holds a part or a smaller assembly, and connects to a node
  that comes before it: a port of the child on a port of that node.
  `docs/format.md`, "An assembly".

  A port of an assembly has a path: `"fork/axle_left"` is the port
  `axle_left` of the node `fork`. A name with no node is a port of the
  root. In place of a name, `at` and `port` can be a `World.Port`: a port
  at any point of the item.
  """
  alias World.{Frame, Part, Port}

  defstruct name: "assembly",
            kind: :item,
            sources: [],
            extras: %{},
            materials: %{},
            nodes: [],
            ports: %{},
            place: %Frame{},
            clips: []

  defmodule Connection do
    @moduledoc """
    How a node connects: the node and its port (`to`, `at`), the port of
    the child (`port`), the kind (`:fixed`, `:hinge`, `:slide`), the turn
    around the axis (degrees) and the move along it (meters) at rest, and
    for a joint its `role` and `limits`.
    """
    defstruct to: nil, at: nil, port: nil, kind: :fixed, turn: 0.0, offset: 0.0, role: nil, limits: nil
  end

  @doc """
  An assembly with its root. The options: `root` (the name of the root
  node, `"body"` by default), `kind`, `sources`, `extras`, `materials` (the
  default of a material role for this model: the white paint of a van),
  `place`: a
  frame that moves the whole assembly (for example, a model made with its
  back at y = 0 moves to its center), and `clips`: animations of its
  joints, each `%{name, length, keys}` with `keys` a list of `{time,
  %{joint => value}}` (`World.Build`).
  """
  def new(name, root_item, opts \\ []) do
    %__MODULE__{
      name: name,
      kind: Keyword.get(opts, :kind, :item),
      sources: Keyword.get(opts, :sources, []),
      extras: Keyword.get(opts, :extras, %{}),
      materials: Keyword.get(opts, :materials, %{}),
      place: Keyword.get(opts, :place, Frame.identity()),
      clips: Keyword.get(opts, :clips, []),
      nodes: [{Keyword.get(opts, :root, "body"), root_item, nil}]
    }
  end

  @doc """
  Add a node. The options: `to` (the node, the root by default), `at` (its
  port), `port` (the port of the child), `kind`, `turn`, `offset`,
  `role`, `limits`.
  """
  def add(%__MODULE__{nodes: nodes} = a, name, item, opts) do
    if List.keymember?(nodes, name, 0), do: raise(ArgumentError, "the assembly #{a.name} has a node #{name} already")
    %{a | nodes: nodes ++ [node(a, name, item, opts)]}
  end

  @doc """
  Add many nodes at one time (the bricks of a wall): a list of `{name,
  item, opts}`, as for `add/4`. Each node connects to a node that is in
  the assembly before the call.
  """
  def add_all(%__MODULE__{nodes: nodes} = a, children) do
    {new, _} =
      Enum.map_reduce(children, MapSet.new(nodes, &elem(&1, 0)), fn {name, item, opts}, names ->
        if MapSet.member?(names, name), do: raise(ArgumentError, "the assembly #{a.name} has a node #{name} already")
        {node(a, name, item, opts), MapSet.put(names, name)}
      end)

    %{a | nodes: nodes ++ new}
  end

  defp node(%__MODULE__{nodes: nodes} = a, name, item, opts) do
    to = Keyword.get(opts, :to, root_name(a))
    unless List.keymember?(nodes, to, 0), do: raise(ArgumentError, "the assembly #{a.name} has no node #{to}")
    kind = Keyword.get(opts, :kind, :fixed)

    if kind != :fixed and Keyword.get(opts, :role) == nil,
      do: raise(ArgumentError, "the joint #{name} of #{a.name} has no role")

    conn = %Connection{
      to: to,
      at: Keyword.fetch!(opts, :at),
      port: Keyword.fetch!(opts, :port),
      kind: kind,
      turn: Keyword.get(opts, :turn, 0.0) / 1,
      offset: Keyword.get(opts, :offset, 0.0) / 1,
      role: Keyword.get(opts, :role),
      limits: Keyword.get(opts, :limits)
    }

    # Each port must exist now: a wrong name stops the code that makes the model.
    _ = port_frame(a, to, conn.at)
    _ = item_port_frame(item, conn.port)
    {name, item, conn}
  end

  @doc """
  Add a port to the assembly at a port of one of its nodes, with a new
  name: so a larger assembly can connect to it by that name.
  """
  def expose(%__MODULE__{ports: ports} = a, name, path), do: %{a | ports: Map.put(ports, name, path)}

  @doc "The name of the root node."
  def root_name(%__MODULE__{nodes: [{name, _, _} | _]}), do: name

  @doc """
  The frame of a port of an item (a part or an assembly), by its path, in
  the axes of the item, at rest.
  """
  def item_port_frame(_item, %Port{} = port), do: Port.frame(port)
  def item_port_frame(%Part{} = p, path), do: Port.frame(Part.port!(p, path))
  def item_port_frame(%World.Figure{} = f, path), do: World.Figure.port_frame(f, path)

  def item_port_frame(%__MODULE__{place: place} = a, path), do: Frame.compose(place, inner_port_frame(a, path))

  defp inner_port_frame(%__MODULE__{ports: ports} = a, path) do
    case Map.fetch(ports, path) do
      {:ok, inner} ->
        inner_port_frame(a, inner)

      :error ->
        case String.split(path, "/", parts: 2) do
          [node, rest] ->
            if List.keymember?(a.nodes, node, 0), do: port_frame(a, node, rest), else: port_frame(a, root_name(a), path)

          [_] ->
            port_frame(a, root_name(a), path)
        end
    end
  end

  # The frame of a port of a node, in the axes of the assembly, at rest.
  defp port_frame(a, node, path) do
    {_, item, _} = List.keyfind(a.nodes, node, 0)
    Frame.compose(node_frame(a, node), item_port_frame(item, path))
  end

  @doc "The frame of a node in the axes of the assembly, at rest."
  def node_frame(%__MODULE__{nodes: nodes} = a, node) do
    case List.keyfind(nodes, node, 0) do
      {_, _, nil} -> Frame.identity()
      {_, item, conn} -> Frame.compose(port_frame(a, conn.to, conn.at), placement(conn, item, 0.0))
      nil -> raise ArgumentError, "the assembly #{a.name} has no node #{node}"
    end
  end

  @doc """
  The frame of a child relative to the port of its parent: the turn and
  the move of the connection, a joint value, and the inverse of the port
  of the child.
  """
  def placement(%Connection{} = c, item, value) do
    {turn, offset} = if c.kind == :slide, do: {c.turn, c.offset + value}, else: {c.turn + value, c.offset}
    motion = Frame.compose(Frame.move({0.0, 0.0, offset}), Frame.turn({0.0, 0.0, 1.0}, turn))
    Frame.compose(motion, Frame.invert(item_port_frame(item, c.port)))
  end
end
