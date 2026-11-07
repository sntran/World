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
  or `{:failed, person, id, message}` when the work raises.
  """
  def work(person, id, work) when is_function(work, 0), do: GenServer.cast(person, {:work, self(), id, work})

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
  def handle_cast({:work, from, id, work}, s) do
    result =
      try do
        {:done, self(), id, work.()}
      rescue
        e -> {:failed, self(), id, Exception.message(e)}
      end

    send(from, result)
    # The result is with the construction now: the person gives its
    # memory back before the next task (the edge has 128 MB).
    {:noreply, s, :hibernate}
  end
end
