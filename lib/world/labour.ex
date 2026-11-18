defmodule World.Labour do
  @moduledoc """
  The labour of the parts of the models (`World.Elements`, W24 to W28):
  where a part builds.

  The edge has 128 MB for a VM and a limit of CPU time for each request
  (`limits.cpu_ms`, 5 minutes at most). A construction shift has neither
  (`World.Shift`, `docs/factory.md`, "Construction shifts"): a workflow
  of the repository on a runner of GitHub Actions, whose node joins the
  node of the edge (`World.Crew`) for some hours. Then:

  - A part that fits the edge (`fits?/1`: a person at mid or far) builds
    here.
  - The edge with shifts (the application environment `:shifts`,
    `WORLD_SHIFTS=true`) builds no other part. A part of an order of a
    project (a request with a project token: the option `project`) waits
    in the queue for a node of a shift (`waiting/0`). Then the edge gives
    it, by its key, to the node with the fewest parts in work for its
    workers. The node builds it from its recipe (`World.Elements.part/1`),
    puts its GLB in the store itself (R2), and gives back only the key
    (`make/1`): the GLB does not go over the link. A part whose node goes
    away goes back to the queue. A part that fails on 3 tries gives
    the error. A part of a public order (no project) gives an error: the
    shifts are for the projects of the owner only.
  - With no shifts (a server on a computer, or native nodes that join
    it), a part goes to the nodes that take parts (on the next node when
    its node goes away), and builds here when no node is left.
  """

  alias World.{Crew, Elements, Line, Shift}
  alias World.Elements.Store

  @tries 3

  @doc "The list of the parts in work on each node and of the parts in the queue, which `build/3` reads (`World.Supervisor`)."
  def children, do: [{Registry, keys: :duplicate, name: __MODULE__}]

  @doc """
  Build the part `key` with its recipe (a map): here, or on another node.
  `{:ok, glb}` when it was built here, `:stored` when another node built
  it and put it in the store, `:none` or `{:error, errors}` as
  `World.Elements.part/1`. The options:

  - `nodes`: the nodes that take parts, each `{supervisor of the tasks,
    workers}`, or a function that gives them now (`World.Crew.parts/0`
    by default).
  - `shifts`: true at the edge with construction shifts (the application
    environment `:shifts` by default).
  - `project`: true for a part of an order of a project.
  - `poll` (1,000 ms): the wait between two looks for a node, and `most`
    (6 hours): the longest wait in the queue.
  """
  def build(key, recipe, opts) do
    shifts = Keyword.get_lazy(opts, :shifts, fn -> Application.get_env(:world, :shifts, false) end)

    cond do
      fits?(recipe) -> here(key)
      shifts and opts[:project] -> queue(key, opts)
      shifts -> {:error, public()}
      true -> away(key, nodes(opts))
    end
  end

  @doc """
  True for a part that the edge builds itself in its memory and its CPU
  limit: a person of a group at mid or far (about 100 MB and 10 s at the
  edge). A part of a sculpture and a person at near do not fit.
  """
  def fits?(%{"piece" => _, "level" => level}) when level in ["mid", "far"], do: true
  def fits?(_recipe), do: false

  @doc """
  True at the edge with shifts for the key of a part with a recipe that
  does not fit the edge: a part of a project of that key waits for a
  shift. (The Worker asks the VM only for a part that R2 does not have.)
  """
  def needs_shift?(key) do
    with true <- Application.get_env(:world, :shifts, false),
         {:ok, json} <- Store.recipe(key),
         {:ok, recipe} <- JSON.decode(json) do
      not fits?(recipe)
    else
      _ -> false
    end
  end

  @doc """
  The part of a key, on the node that gives it the work: `:stored` when
  the store has it already (a part in R2 does not build again), else
  built from its recipe and put in the store (in the record of the shift,
  `World.Shift.work/2`). `:stored`, or the error of
  `World.Elements.part/1`. The GLB stays on this node.
  """
  def make(key) do
    if Store.has?(key) do
      :stored
    else
      Shift.work(key, fn ->
        case Elements.part(key) do
          {:ok, _glb} -> :stored
          other -> other
        end
      end)
    end
  end

  @doc "The count of the parts in work on a node (its supervisor of the tasks)."
  def busy(tasks), do: length(Registry.lookup(__MODULE__, tasks))

  @doc "The count of the parts that wait in the queue for a node of a shift."
  def waiting, do: length(Registry.lookup(__MODULE__, :queue))

  @doc "The error of a part of a public order that does not fit the edge."
  def public,
    do: [
      %{
        "path" => "",
        "message" =>
          "this part does not fit the memory and the CPU time of the edge, and a construction shift builds only the orders of the projects of the owner (docs/factory.md, \"Construction shifts\")"
      }
    ]

  defp here(key), do: Line.run(:now, fn -> Elements.part(key) end)

  defp nodes(opts) do
    case Keyword.get(opts, :nodes, &Crew.parts/0) do
      fun when is_function(fun, 0) -> fun.()
      nodes -> nodes
    end
  end

  # With no shifts: the node with the fewest parts in work for its
  # workers; then the next ones when it goes away; then here.
  defp away(key, []), do: here(key)

  defp away(key, nodes) do
    {tasks, _} = pick(nodes)

    case try_on(key, tasks) do
      {:ok, done} -> done
      _ -> away(key, List.keydelete(nodes, tasks, 0))
    end
  end

  # A part of a project at the edge with shifts: in the queue until a
  # node of a shift builds it.
  defp queue(key, opts) do
    {:ok, _} = Registry.register(__MODULE__, :queue, key)
    until = System.monotonic_time(:millisecond) + Keyword.get(opts, :most, 6 * 3_600_000)

    try do
      turn(key, opts, 0, until)
    after
      Registry.unregister(__MODULE__, :queue)
    end
  end

  defp turn(key, opts, tries, until) do
    poll = Keyword.get(opts, :poll, 1_000)

    case nodes(opts) do
      [] ->
        if System.monotonic_time(:millisecond) > until do
          {:error, [%{"path" => "", "message" => "no construction shift came for this part: send the request again"}]}
        else
          Process.sleep(poll)
          turn(key, opts, tries, until)
        end

      nodes ->
        {tasks, _} = pick(nodes)

        case try_on(key, tasks) do
          {:ok, done} ->
            done

          # (The node went away, or its shift ended: the part goes back to the queue.)
          :gone ->
            Process.sleep(poll)
            turn(key, opts, tries, until)

          {:failed, _} when tries + 1 >= @tries ->
            {:error, [%{"path" => "", "message" => "the part failed on #{@tries} nodes of a construction shift"}]}

          {:failed, _} ->
            turn(key, opts, tries + 1, until)
        end
    end
  end

  defp pick(nodes), do: Enum.min_by(nodes, fn {tasks, workers} -> busy(tasks) / workers end)

  # The make of a part on a node: `{:ok, result}`, `:gone` when the node
  # went away or stopped its tasks (the end of a shift), or `{:failed,
  # reason}` when the make raised there.
  defp try_on(key, tasks) do
    {:ok, _} = Registry.register(__MODULE__, tasks, key)

    try do
      task = Task.Supervisor.async_nolink(tasks, __MODULE__, :make, [key])

      case Task.yield(task, :infinity) do
        {:ok, done} -> {:ok, done}
        {:exit, reason} -> if gone?(reason), do: :gone, else: {:failed, reason}
      end
    catch
      # (The supervisor of the node is not there: the node went away.)
      :exit, _ -> :gone
    after
      Registry.unregister(__MODULE__, tasks)
    end
  end

  defp gone?(reason),
    do:
      reason in [:noconnection, :noproc, :shutdown, :killed] or
        match?({tag, _} when tag in [:shutdown, :nodedown], reason)
end
