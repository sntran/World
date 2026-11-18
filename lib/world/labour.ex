defmodule World.Labour do
  @moduledoc """
  The labour of the parts of the models (`World.Elements`, W24 to W28):
  where a part builds.

  The edge has 128 MB for a VM and a limit of CPU time for each request
  (`limits.cpu_ms`, 5 minutes at most). Native nodes have neither limit.
  A native node joins the node of the edge (`World.Crew`, the option
  `join`; the link is a WebSocket of the Worker with a token, so no node
  has an open port: `docs/factory.md`, "The labour of native nodes").
  Then:

  - The edge builds a part only when it fits its memory and its CPU
    limit (`here?/2`: a person at mid or far), or when no native node
    takes parts.
  - It gives each other part, by its key, to the native node with the
    fewest parts in work for its workers. The native node builds it from
    its recipe (`World.Elements.part/1`), puts its GLB in the store
    itself (R2, through the store of the Worker), and gives back only
    the key (`make/1`): the GLB does not go over the link.
  - A part whose node goes away (or that raises there) is built on the
    next node, and on the edge when no node is left.
  """

  alias World.{Crew, Elements, Line}

  @doc "The list of the parts in work on each node, which `build/3` reads (`World.Supervisor`)."
  def children, do: [{Registry, keys: :duplicate, name: __MODULE__}]

  @doc """
  Build the part `key` with its recipe (a map): here, or on a native
  node. `{:ok, glb}` when it was built here, `:stored` when a native node
  built it and put it in the store, `:none` or `{:error, errors}` as
  `World.Elements.part/1`. The option `nodes`: the nodes that take parts
  (`World.Crew.parts/1` by default), each `{supervisor of the tasks,
  workers}`.
  """
  def build(key, recipe, opts \\ []) do
    nodes = Keyword.get_lazy(opts, :nodes, &Crew.parts/0)
    if here?(recipe, nodes), do: here(key), else: away(key, nodes)
  end

  @doc """
  True when this node builds the part of a recipe: when no native node
  takes parts, or for a person of a group at mid or far (about 100 MB
  and 10 s at the edge). A part of a sculpture and a person at near go
  to the native nodes.
  """
  def here?(_recipe, []), do: true
  def here?(%{"piece" => _, "level" => level}, _nodes) when level in ["mid", "far"], do: true
  def here?(_recipe, _nodes), do: false

  @doc """
  The part of a key, on the native node that gives it the work: built
  from its recipe and put in the store. `:stored`, or the error of
  `World.Elements.part/1`. The GLB stays on this node.
  """
  def make(key) do
    case Elements.part(key) do
      {:ok, _glb} -> :stored
      other -> other
    end
  end

  @doc "The count of the parts in work on a node (its supervisor of the tasks)."
  def busy(tasks), do: length(Registry.lookup(__MODULE__, tasks))

  defp here(key), do: Line.run(:now, fn -> Elements.part(key) end)

  # The node with the fewest parts in work for its workers; then the next ones when it goes away.
  defp away(key, []), do: here(key)

  defp away(key, nodes) do
    {tasks, _} = Enum.min_by(nodes, fn {tasks, workers} -> busy(tasks) / workers end)
    {:ok, _} = Registry.register(__MODULE__, tasks, key)

    result =
      try do
        task = Task.Supervisor.async_nolink(tasks, __MODULE__, :make, [key])
        Task.yield(task, :infinity)
      catch
        # (The supervisor of the node is not there: the node went away.)
        :exit, _ -> nil
      after
        Registry.unregister(__MODULE__, tasks)
      end

    case result do
      {:ok, done} -> done
      _ -> away(key, List.keydelete(nodes, tasks, 0))
    end
  end
end
