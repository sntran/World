defmodule World do
  @moduledoc """
  The door of the node (`docs/plans/0001-people-build-on-demand.md`, R1):
  the people of the node build each model, and a game watches them.

  - `build/1` opens a construction for a job (`World.Construction`).
  - `watch/1` sends each event of a construction, or of the whole world
    (`:world`), to the process that calls: `{:world, event}`.
  - `await/2` waits for the result of a job.
  - `pause/1`, `resume/1` and `cancel/1` go to a construction as messages
    of priority; `change/2` gives it a new job in a pause.
  - `census/0` gives the people of the node.
  """
  alias World.Construction

  @doc """
  Open a construction for a job (`World.Construction.start/1`; `reply`
  is the process that calls, by default). `{:ok, id}`; a construction
  with the same id that runs now is the same build. When the yard runs
  (`World.Yard`), a model in data goes to the place of its kind, and
  waits until the place is open.
  """
  def build(job) do
    case World.Yard.place(Map.put_new(job, :reply, self())) do
      {:held, id} -> {:ok, id}
      {:start, job} -> start(job)
    end
  end

  defp start(job) do
    with {:error, {:already_started, _}} <- Construction.start(job),
         :ok <- join(job) do
      {:ok, job.id}
    else
      {:ok, _} -> {:ok, job.id}
      # The construction ended before the join: a new one builds again.
      :gone -> start(job)
    end
  end

  defp join(job) do
    Construction.join(job.id, job.reply)
  catch
    :exit, _ -> :gone
  end

  @doc """
  Pause a construction: it gives no task, its free people go, and the
  people end the tasks in hand. `:ok`, or `{:error, :none}` when no
  construction of the id runs.
  """
  def pause(id), do: urgent(id, :pause)

  @doc "Resume a construction after a pause: `:ok` or `{:error, :none}`."
  def resume(id), do: urgent(id, :resume)

  @doc "Cancel a construction: it stops (`stopped`, the reason `cancelled`) and keeps nothing."
  def cancel(id), do: urgent(id, :cancel)

  # A message of priority to the alias of the construction, the value of
  # its name (World.Construction).
  defp urgent(id, message) do
    case Registry.lookup(World.Names, id) do
      [{_, alias}] when is_reference(alias) -> :erlang.send(alias, message, [:priority]) && :ok
      _ -> {:error, :none}
    end
  end

  @doc """
  Change the job of a construction in a pause (a new order of the same
  blueprint in data): each node whose data is the same stays made, and
  the people make the others again when the construction resumes. `:ok`,
  or `{:error, reason}`: `:not_paused`, `:not_a_drawing`, `:other_nodes`
  (the nodes of the drawing are not the same) or `:none`.
  """
  def change(id, job) do
    GenServer.call({:via, Registry, {World.Names, id}}, {:change, job})
  catch
    :exit, _ -> {:error, :none}
  end

  @doc "Send each event of a construction (its id), or of the world (`:world`), to the process that calls."
  def watch(key) do
    {:ok, _} = Registry.register(World.Events, key, nil)
    :ok
  end

  @doc """
  Wait for the result of a job: `{:ok, result}` (the files and the log),
  `{:error, {:failed, message}}` or `{:error, {:stopped, reason}}`.
  """
  def await(id, timeout \\ :infinity) do
    receive do
      {:built, ^id, result} -> {:ok, result}
      {:failed, ^id, message} -> {:error, {:failed, message}}
      {:stopped, ^id, reason} -> {:error, {:stopped, reason}}
    after
      timeout -> {:error, :timeout}
    end
  end

  @doc """
  The budget of a job from its data (`docs/plans/0001-people-build-on-demand.md`,
  D2): `"workers"` (1 to 64), `"seconds"` (more than 0), `"triangles"`
  (1 to 10,000,000) and `"memory_mb"` (1 to 4,096: each person has its
  part for the heap of a task), each one optional. `{:ok, budget}`, or `{:error,
  errors}` with the path of each error.
  """
  def budget(nil), do: {:ok, %{}}

  def budget(raw) when is_map(raw) do
    errors =
      for {key, value} <- Enum.sort(raw),
          message = wrong(key, value),
          do: %{"path" => "budget.#{key}", "message" => message}

    if errors == [], do: {:ok, raw}, else: {:error, errors}
  end

  def budget(_raw), do: {:error, [%{"path" => "budget", "message" => "must be an object"}]}

  defp wrong("workers", n) when :erlang.is_integer(n, 1, 64), do: nil
  defp wrong("workers", _), do: "must be a whole number from 1 to 64"
  defp wrong("seconds", n) when is_number(n) and n > 0, do: nil
  defp wrong("seconds", _), do: "must be a number of seconds more than 0"
  defp wrong("triangles", n) when :erlang.is_integer(n, 1, 10_000_000), do: nil
  defp wrong("triangles", _), do: "must be a whole number from 1 to 10,000,000"
  defp wrong("memory_mb", n) when :erlang.is_integer(n, 1, 4096), do: nil
  defp wrong("memory_mb", _), do: "must be a whole number of MB from 1 to 4,096"
  defp wrong(_key, _), do: "is not a part of a budget: workers, seconds, triangles, memory_mb"

  @doc """
  The memory of the VM, in bytes: `{"total", bytes}` (`:erlang.memory/1`).
  An emulator with no allocators of ERTS (`-Mea min`, at the edge) does
  not have it: then `{"processes", bytes}`, the memory of each process
  and of each binary that a process holds (one time each). `total` is
  the function of the memory of all of the VM.
  """
  def memory(total \\ &:erlang.memory/1) do
    {"total", total.(:total)}
  rescue
    ErlangError ->
      infos = for p <- Process.list(), info = Process.info(p, [:memory, :binary]), do: info
      binaries = for info <- infos, {id, size, _} <- info[:binary], into: %{}, do: {id, size}
      {"processes", Enum.sum(for info <- infos, do: info[:memory]) + Enum.sum(Map.values(binaries))}
  end

  @doc "The people of the node and the requests that wait (`World.Census.people/1`)."
  def census, do: World.Census.people()
end
