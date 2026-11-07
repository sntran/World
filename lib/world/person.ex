defmodule World.Person do
  @moduledoc """
  A person of the node: one process with a job and a trade
  (`docs/plans/0001-people-build-on-demand.md`, R4). A worker does one
  task at a time: it runs the work of the task and gives the result back
  to the construction that holds it. The name of a person is its PID
  (D23): `"<0.123.0>"`.

  A construction hires a person of a trade from the census (`hire/2`),
  gives it tasks (`work/3`), and lets it go (`release/1`). A free person
  stays in the census, and the next construction can hire it.
  """
  use GenServer, restart: :temporary

  @doc "Start a person. The options: `trade` (an atom), `job` (`:worker` by default)."
  def start_link(opts), do: GenServer.start_link(__MODULE__, Map.new(opts))

  @doc "The name of a person in the log: its PID as text."
  def name(pid) when is_pid(pid), do: pid |> :erlang.pid_to_list() |> List.to_string()

  @doc """
  Ask the census for a person of `trade`, for the process that calls.
  The census sends `{:hired, ref, person}` when a person is free; the
  result is `ref`.
  """
  def hire(trade, ref \\ make_ref()) do
    World.Census.hire(trade, self(), ref)
    ref
  end

  @doc "Let a person go back to the census."
  def release(person), do: World.Census.release(person, self())

  @doc """
  Give a task to a person: `work` is a function with no arguments. The
  person sends `{:done, person, id, result}` to the process that calls,
  or `{:failed, person, id, message}` when the work raises. With `heap`
  (words), the work runs in a process of its own with that limit of its
  heap and of the binaries that it holds (`max_heap_size`, Erlang/OTP
  27): over it, the work stops alone, and the message is `"memory"`.
  """
  def work(person, id, work, heap \\ nil) when is_function(work, 0),
    do: GenServer.cast(person, {:work, self(), id, work, heap})

  @doc "The job and the trade of a person."
  def info(person), do: GenServer.call(person, :info)

  @impl true
  def init(opts) do
    s = %{trade: Map.fetch!(opts, :trade), job: Map.get(opts, :job, :worker)}
    Process.set_label({:person, s.job, s.trade})
    {:ok, s}
  end

  @impl true
  def handle_call(:info, _from, s), do: {:reply, s, s}

  @impl true
  def handle_cast({:work, from, id, work, heap}, s) do
    send(from, run(id, work, heap))
    # The result is with the construction now: the person gives its
    # memory back before the next task (the edge has 128 MB).
    {:noreply, s, :hibernate}
  end

  defp run(id, work, nil), do: tag(outcome(work), id)

  defp run(id, work, heap) do
    me = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Process.flag(:max_heap_size, %{size: heap, kill: true, error_logger: false, include_shared_binaries: true})
        send(me, {self(), outcome(work)})
      end)

    receive do
      {^pid, outcome} ->
        Process.demonitor(ref, [:flush])
        tag(outcome, id)

      {:DOWN, ^ref, :process, ^pid, :killed} ->
        {:failed, me, id, "memory"}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:failed, me, id, inspect(reason)}
    end
  end

  defp outcome(work) do
    {:ok, work.()}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp tag({:ok, result}, id), do: {:done, self(), id, result}
  defp tag({:error, message}, id), do: {:failed, self(), id, message}
end
