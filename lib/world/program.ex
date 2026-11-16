defmodule World.Program do
  @moduledoc """
  A port program of the VM: a program on this computer, or a binding of
  the Durable Object at the edge (`/env/NAME`, BEAM.com "Ports to
  bindings"). The stores of the orders and of the log run through it
  (`World.Orders.Store`, `World.Log.Store`).
  """

  @doc """
  Run `program` with `args` and the input `input` (with the environment
  `env`, a list of `{name, value}` texts): `{:ok, output}` when it ends
  with the exit status 0, else `:error` (also after `timeout` ms).
  """
  def run(program, args, input, env, timeout) do
    with {:ok, port} <- open(program, args, env) do
      # A monitor in place of the link, so that this process (a request)
      # does not end with the port. A message, not Port.command/2: a
      # program that ended takes no input, and its exit status tells it.
      Process.unlink(port)
      ref = Port.monitor(port)
      if input != "", do: send(port, {self(), {:command, input}})
      result = collect(port, ref, [], nil, timeout)
      Port.demonitor(ref, [:flush])
      result
    end
  end

  defp open(program, args, env) do
    env = for {k, v} <- env, do: {String.to_charlist(k), String.to_charlist(v)}
    {:ok, Port.open({:spawn_executable, program}, [:binary, :exit_status, args: args, env: env])}
  rescue
    ErlangError -> :error
  end

  # The output of the program until its port ends: the exit status comes
  # before the end, and a port that ends with no exit status is an error.
  defp collect(port, ref, data, status, timeout) do
    receive do
      {^port, {:data, part}} -> collect(port, ref, [data | part], status, timeout)
      {^port, {:exit_status, code}} -> collect(port, ref, data, code, timeout)
      {:DOWN, ^ref, :port, ^port, _} -> if status == 0, do: {:ok, IO.iodata_to_binary(data)}, else: :error
    after
      timeout ->
        Port.close(port)
        :error
    end
  end
end
