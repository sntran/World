defmodule World.Guard do
  @moduledoc """
  The guard of the memory of the VM: no order stops the VM.

  The VM at the edge has 128 MB, and the edge stops all of the VM when
  its memory is full: each order and each stream of the node stops with
  it. So a build of an order runs in a process of its own (`run/1`),
  and the guard looks at the memory of the VM each #{25} ms while it
  works. When the memory is more than the limit, the guard stops the
  build (and the processes that it started and that are linked to it):
  the order gets an error, and the VM and the other orders go on. The
  heap of the process of the build, with its binaries, has the same
  limit (`max_heap_size` with `include_shared_binaries`), so a process
  that grows fast stops before the next look. A build that starts work
  in processes that are not linked to it (a construction: `World.build/1`)
  gives the guard the stop of that work (`on_stop/1`), and the guard runs
  it when it stops the build.

  In WebAssembly (the edge), the guard reads the memory of WebAssembly
  (`World.wasm_memory/1`): the edge counts its size against the 128 MB,
  and the size never gets smaller. The guard stops a build when the
  memory that the VM uses is more than the limit, or when the size is
  more than the limit and less than #{8} MB of it is free: the next
  growth would go over the limit. On a native VM, it reads
  `World.memory/0`.

  The limit is the key `:memory_mb` of the application environment of
  `:world` (from `WORLD_MEMORY_MB`), in MB. With no limit, `run/1` only
  runs the function.
  """

  @look 25
  # The free memory of WebAssembly under which the next growth comes.
  @reserve 8_000_000

  @doc "The limit of the memory of the VM, in bytes, or nil."
  def limit do
    case Application.get_env(:world, :memory_mb) do
      nil -> nil
      mb -> mb * 1_000_000
    end
  end

  @doc """
  Run `fun` in a process of its own with the level of detail of this
  process: `{:ok, value}`, or `{:error, :memory}` when the memory of the
  VM went over the limit and the guard stopped it. An error of `fun` is
  raised here again.
  """
  def run(fun) do
    case limit() do
      nil -> {:ok, fun.()}
      bytes -> guarded(fun, bytes)
    end
  end

  @doc """
  In a build in the guard: `fun` runs (in the process of the caller of
  `run/1`) when the guard stops the build for the memory, so work that
  the build started and that is not linked to it stops too (the
  construction of a file, `World.cancel/1`). Outside a build in the
  guard it does nothing. `:ok`.
  """
  def on_stop(fun) when is_function(fun, 0) do
    case Process.get({__MODULE__, :waiter}) do
      nil ->
        :ok

      waiter ->
        send(waiter, {__MODULE__, :on_stop, self(), fun})
        :ok
    end
  end

  @doc "The error of an order that needs more memory than the VM has, as the errors of `World.Orders.check/1`."
  def errors do
    [
      %{
        "path" => "",
        "message" =>
          "needs more memory than the factory has (#{div(limit() || 0, 1_000_000)} MB): " <>
            "order its parts list (the file elements) and get each part alone"
      }
    ]
  end

  defp guarded(fun, bytes) do
    level = World.Detail.level()
    waiter = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Process.put({__MODULE__, :waiter}, waiter)
        words = div(bytes, :erlang.system_info(:wordsize))
        # (With its binaries: the bake of a sculpture keeps large ones.)
        Process.flag(:max_heap_size, %{size: words, kill: true, error_logger: false, include_shared_binaries: true})

        result =
          try do
            {:ok, World.Detail.with(level, fun)}
          rescue
            e -> {:raise, e, __STACKTRACE__}
          end

        exit({:guard, result})
      end)

    wait(pid, ref, bytes, [])
  end

  @doc false
  # Over the limit: the memory that the VM uses, or the next growth of the memory of WebAssembly.
  def over?(bytes, {size, used}), do: used > bytes or (size > bytes and size - used < @reserve)
  def over?(bytes, nil), do: elem(World.memory(), 1) > bytes

  defp wait(pid, ref, bytes, stops) do
    receive do
      {__MODULE__, :on_stop, ^pid, fun} -> wait(pid, ref, bytes, [fun | stops])
      {:DOWN, ^ref, :process, ^pid, {:guard, {:ok, value}}} -> {:ok, value}
      {:DOWN, ^ref, :process, ^pid, {:guard, {:raise, e, stack}}} -> reraise e, stack
      {:DOWN, ^ref, :process, ^pid, :killed} -> stopped(stops)
      {:DOWN, ^ref, :process, ^pid, reason} -> exit(reason)
    after
      @look ->
        # (After the kill, the end of the build comes after each message of the build: its stops.)
        if over?(bytes, World.wasm_memory()), do: Process.exit(pid, :kill)
        wait(pid, ref, bytes, stops)
    end
  end

  # The build stopped for the memory: the stop of each work that it started, then the error.
  defp stopped(stops) do
    Enum.each(Enum.reverse(stops), & &1.())
    :erlang.garbage_collect()
    {:error, :memory}
  end
end
