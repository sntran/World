defmodule World.Guard do
  @moduledoc """
  The guard of the memory of the VM: no order stops the VM.

  The VM at the edge has 128 MB, and the edge stops all of the VM when
  its memory is full: each order and each stream of the node stops with
  it. So a build of an order runs in a process of its own (`run/1`),
  and the guard looks at the memory of the VM (`World.memory/0`) each
  #{25} ms while it works. When the memory is more than the limit,
  the guard stops the build (and the processes that it started and that
  are linked to it): the order gets an error, and the VM and the other
  orders go on. The heap of the process of the build has the same limit
  (`max_heap_size`), so a process that grows fast stops before the next
  look.

  The limit is the key `:memory_mb` of the application environment of
  `:world` (from `WORLD_MEMORY_MB`), in MB. With no limit, `run/1` only
  runs the function.
  """

  @look 25

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

    {pid, ref} =
      spawn_monitor(fn ->
        words = div(bytes, :erlang.system_info(:wordsize))
        Process.flag(:max_heap_size, %{size: words, kill: true, error_logger: false})

        result =
          try do
            {:ok, World.Detail.with(level, fun)}
          rescue
            e -> {:raise, e, __STACKTRACE__}
          end

        exit({:guard, result})
      end)

    wait(pid, ref, bytes)
  end

  defp wait(pid, ref, bytes) do
    receive do
      {:DOWN, ^ref, :process, ^pid, {:guard, {:ok, value}}} -> {:ok, value}
      {:DOWN, ^ref, :process, ^pid, {:guard, {:raise, e, stack}}} -> reraise e, stack
      {:DOWN, ^ref, :process, ^pid, :killed} -> {:error, :memory}
      {:DOWN, ^ref, :process, ^pid, reason} -> exit(reason)
    after
      @look ->
        {_, now} = World.memory()

        if now > bytes do
          Process.exit(pid, :kill)
          receive do: ({:DOWN, ^ref, :process, ^pid, _} -> :ok)
          :erlang.garbage_collect()
          {:error, :memory}
        else
          wait(pid, ref, bytes)
        end
    end
  end
end
