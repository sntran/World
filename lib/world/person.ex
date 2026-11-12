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
  person does it in a hand (a process of its own that it watches), so it
  can take a stop while the hand works (plan 0007, D5). The hand sends
  `{:done, person, id, result}` to the process that calls, or the person
  sends `{:failed, person, id, message}` when the work raises. With
  `heap` (words), the hand has that limit of its heap and of the binaries
  that it holds (`max_heap_size`, Erlang/OTP 27): over it, the work stops
  alone, and the message is `"memory"`.
  """
  def work(person, id, work, heap \\ nil) when is_function(work, 0),
    do: GenServer.cast(person, {:work, self(), id, work, heap})

  @doc """
  Stop the task of a person at once: a message of priority to its alias,
  so it comes before the other messages (Erlang/OTP 28). The hand stops,
  no result goes, and the person is free. Nothing for a person with no
  task.
  """
  def stop(person) do
    case Registry.lookup(World.Names, {:person, person}) do
      [{_, alias}] -> :erlang.send(alias, :stop, [:priority])
      [] -> :ok
    end

    :ok
  end

  @doc "The job and the trade of a person, and its hand (`nil` with no task)."
  def info(person), do: GenServer.call(person, :info)

  @impl true
  def init(opts) do
    s = %{trade: Map.fetch!(opts, :trade), job: Map.get(opts, :job, :worker), hand: nil}
    Process.set_label({:person, s.job, s.trade})
    # The alias of priority of the person: a stop comes before the rest.
    {:ok, _} = Registry.register(World.Names, {:person, self()}, :erlang.alias([:priority]))
    {:ok, s}
  end

  @impl true
  def handle_call(:info, _from, s), do: {:reply, s, s}

  @impl true
  def handle_cast({:work, from, id, work, heap}, s) do
    me = self()

    {pid, ref} =
      spawn_monitor(fn ->
        if heap,
          do:
            Process.flag(:max_heap_size, %{size: heap, kill: true, error_logger: false, include_shared_binaries: true})

        # The result goes to the construction from the hand: one copy.
        send(from, tag(outcome(work), id, me))
      end)

    {:noreply, %{s | hand: {pid, ref, from, id}}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, %{hand: {pid, ref, from, id}} = s) do
    cond do
      reason == :normal -> :ok
      reason == :killed -> send(from, {:failed, self(), id, "memory"})
      true -> send(from, {:failed, self(), id, inspect(reason)})
    end

    # The result is with the construction now: the person gives its
    # memory back before the next task (the edge has 128 MB).
    {:noreply, %{s | hand: nil}, :hibernate}
  end

  # A stop: the hand stops, and no result goes.
  def handle_info(:stop, %{hand: {pid, ref, _, _}} = s) do
    Process.demonitor(ref, [:flush])
    Process.exit(pid, :kill)
    {:noreply, %{s | hand: nil}, :hibernate}
  end

  def handle_info(_message, s), do: {:noreply, s}

  defp outcome(work) do
    {:ok, work.()}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp tag({:ok, result}, id, person), do: {:done, person, id, result}
  defp tag({:error, message}, id, person), do: {:failed, person, id, message}
end
