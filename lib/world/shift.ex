defmodule World.Shift do
  @moduledoc """
  A construction shift (`docs/factory.md`, "Construction shifts"): a
  workflow of this repository on a runner of GitHub Actions
  (`.github/workflows/shift.yml`). Its node joins the node of the edge
  (`World.Crew`), takes whole parts by their key (`World.Labour`), and
  goes home. It is not a server that stays up.

  On the edge, `wanted?/1` tells the Worker to start a shift: parts wait
  in the queue, and no node of a shift takes them, or each one has less
  than 15 minutes left. The Worker starts the workflow
  (`workflow_dispatch`, `shift.js`).

  On the runner, this process keeps the shift (`WORLD_SHIFT_UNTIL`,
  `World.Supervisor`):

  - `until`: the end of the shift (in ms of the system clock), 15 minutes
    before the end of the time of its job. At the end, it stops the parts
    in work: they go back to the queue of the edge.
  - `idle` (60 minutes): with no part in work for this time, the shift
    goes home early.
  - `summary`: the file of the summary (markdown, `$GITHUB_STEP_SUMMARY`
    for the job): each part, its time, the peak memory of the VM while
    it built, its result, and the failures.
  - `stop`: the function that stops the VM at the end (`System.stop/0`).
  """
  # (A shift that ended does not start again: the VM stops.)
  use GenServer, restart: :temporary

  alias World.{Crew, Labour}
  alias World.Elements.Store

  # The edge starts the next shift when the shift has less time left.
  @next 15 * 60_000

  # --- On the edge -----------------------------------------------------------------------

  @doc """
  True when the edge must start a shift: parts of projects wait in the
  queue, and each node that takes parts is a shift with less than 15
  minutes left (or there is no such node). The options `waiting`,
  `nodes` and `left` (the ms left of a node, nil for a node that is not
  a shift) are for a test.
  """
  def wanted?(opts \\ []) do
    waiting = Keyword.get_lazy(opts, :waiting, &Labour.waiting/0)
    nodes = Keyword.get_lazy(opts, :nodes, &Crew.parts/0)
    left = Keyword.get(opts, :left, &left_on/1)

    waiting > 0 and
      Enum.all?(nodes, fn {{_tasks, node}, _workers} ->
        case left.(node) do
          nil -> false
          ms -> ms < @next
        end
      end)
  end

  # The time left of the shift on a node; 0 when it does not answer.
  defp left_on(node) do
    :erpc.call(node, __MODULE__, :left, [], 2_000)
  catch
    _, _ -> 0
  end

  # --- On the runner ---------------------------------------------------------------------

  @doc "The ms left of the shift of this node, or nil when this node is not a shift."
  def left do
    case :persistent_term.get({__MODULE__, :until}, nil) do
      nil -> nil
      until -> max(until - System.system_time(:millisecond), 0)
    end
  end

  @doc """
  The value of `fun`, the make of the part `key` (`World.Labour.make/1`),
  in the record of the shift: its time, the peak memory of the VM while
  it ran, and its result. With no shift, only `fun`.
  """
  def work(key, fun) do
    case Process.whereis(__MODULE__) do
      nil ->
        fun.()

      shift ->
        GenServer.cast(shift, {:begin, key})
        peak = sampler()
        start = System.monotonic_time(:millisecond)

        try do
          result = fun.()
          GenServer.cast(shift, {:done, key, System.monotonic_time(:millisecond) - start, top(peak), result})
          result
        rescue
          e ->
            GenServer.cast(shift, {:done, key, System.monotonic_time(:millisecond) - start, top(peak), {:raised, e}})
            reraise e, __STACKTRACE__
        end
    end
  end

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    until = Keyword.fetch!(opts, :until)
    :persistent_term.put({__MODULE__, :until}, until)
    tick = Keyword.get(opts, :tick, 10_000)
    Process.send_after(self(), :tick, tick)

    {:ok,
     %{
       until: until,
       idle: Keyword.get(opts, :idle, 60 * 60_000),
       summary: opts[:summary],
       stop: Keyword.get(opts, :stop, &System.stop/0),
       tick: tick,
       start: System.system_time(:millisecond),
       last: System.monotonic_time(:millisecond),
       busy: %{},
       done: []
     }}
  end

  @impl true
  def handle_cast({:begin, key}, s), do: {:noreply, %{s | busy: Map.put(s.busy, key, true)}}

  def handle_cast({:done, key, ms, peak, result}, s) do
    {:noreply,
     %{
       s
       | busy: Map.delete(s.busy, key),
         done: [{key, ms, peak, result} | s.done],
         last: System.monotonic_time(:millisecond)
     }}
  end

  @impl true
  def handle_info(:tick, s) do
    cond do
      System.system_time(:millisecond) >= s.until -> finish(s, "the end of the time of the shift")
      s.busy == %{} and System.monotonic_time(:millisecond) - s.last >= s.idle -> finish(s, "no work")
      true -> Process.send_after(self(), :tick, s.tick) && {:noreply, s}
    end
  end

  @impl true
  def terminate(_reason, _s), do: :persistent_term.erase({__MODULE__, :until})

  # The end of the shift: the parts in work stop (and go back to the
  # queue of the edge), the summary, and the stop of the VM.
  defp finish(s, why) do
    for {_, pid, _, _} <- Supervisor.which_children(Crew.Tasks), is_pid(pid), do: Process.exit(pid, :shutdown)
    if s.summary, do: File.write!(s.summary, summary(s, why))
    s.stop.()
    {:stop, :normal, s}
  end

  @doc false
  def summary(s, why) do
    rows =
      for {key, ms, peak, result} <- Enum.reverse(s.done) do
        "| #{label(key)} | `#{key}` | #{Float.round(ms / 1000, 1)} | #{div(peak, 1_000_000)} | #{outcome(result)} |"
      end

    stopped =
      for key <- Map.keys(s.busy), do: "- #{label(key)} (`#{key}`): stopped at the end; it goes back to the queue"

    failed =
      for {key, _, _, result} <- Enum.reverse(s.done),
          outcome(result) != "stored",
          do: "- #{label(key)} (`#{key}`): #{outcome(result)}"

    minutes = div(System.system_time(:millisecond) - s.start, 60_000)

    Enum.join(
      [
        "## The construction shift",
        "",
        "#{length(s.done)} parts in #{minutes} minutes. The end: #{why}.",
        "",
        "| Part | Key | Time (s) | Peak memory of the VM (MB) | Result |",
        "|---|---|---|---|---|"
      ] ++
        rows ++
        ["", "### Failures and stops", ""] ++ if(failed ++ stopped == [], do: ["None."], else: failed ++ stopped),
      "\n"
    ) <> "\n"
  end

  # The name of a part and its level, from its recipe.
  defp label(key) do
    with {:ok, json} <- Store.recipe(key), {:ok, %{"level" => level} = recipe} <- JSON.decode(json) do
      "#{recipe["node"] || recipe["piece"]} (#{level})"
    else
      _ -> "?"
    end
  end

  defp outcome(:stored), do: "stored"
  defp outcome(:none), do: "no recipe"
  defp outcome({:error, errors}), do: "error: " <> Enum.map_join(errors, "; ", & &1["message"])
  defp outcome({:raised, e}), do: "raised: " <> Exception.message(e)

  # A process that keeps the peak of the memory of the VM until `top/1`.
  defp sampler do
    spawn_link(fn -> sample(:erlang.memory(:total)) end)
  end

  defp sample(peak) do
    receive do
      {:top, pid, ref} -> send(pid, {ref, peak})
    after
      100 -> sample(max(peak, :erlang.memory(:total)))
    end
  end

  defp top(pid) do
    ref = make_ref()
    send(pid, {:top, self(), ref})
    receive do: ({^ref, peak} -> peak)
  end
end
