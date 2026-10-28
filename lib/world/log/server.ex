defmodule World.Log.Server do
  @moduledoc """
  The process that keeps the log of a run (`World.Log`). Each person and
  each vehicle records an event when it acts; the server gives the event
  its wall time when it gets it, so the log is in the order of the
  events. A record is a call: the person goes on only after the event is
  in the log.
  """
  use GenServer

  alias World.{Clock, Log}

  @doc "Start a log with its clock."
  def start_link(%Clock{} = clock), do: GenServer.start_link(__MODULE__, clock)

  @doc "Record an event (the options of `World.Log.add/3`, with no `wall`)."
  def record(server, kind, opts \\ []), do: GenServer.call(server, {:record, kind, opts})

  @doc "The log."
  def log(server), do: GenServer.call(server, :log)

  @impl true
  def init(clock), do: {:ok, Log.new(clock)}

  @impl true
  def handle_call({:record, kind, opts}, _from, log) do
    # The wall clock of the system can go back a little: an event is
    # never before the last one.
    last = List.first(log.events)
    wall = max(Clock.wall(), if(last, do: last.wall, else: 0))
    {:ok, log} = Log.add(log, kind, [wall: wall] ++ opts)
    {:reply, :ok, log}
  end

  def handle_call(:log, _from, log), do: {:reply, log, log}
end
