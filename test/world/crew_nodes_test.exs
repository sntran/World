defmodule World.CrewNodesTest do
  # Two Erlang nodes share their crews (plan 0012, D8; R6): each node is
  # a VM of its own (`test/world/crew_node.exs`), with no port mapper
  # daemon (`World.Epmd`).
  use ExUnit.Case, async: false

  alias World.Epmd

  @moduletag timeout: 300_000

  test "the port of a node is in its name; the module answers as the mapper of Erlang does" do
    assert Epmd.port(:"world4371@10.0.0.2") == 4371
    assert Epmd.port("b20044@127.0.0.1") == 20_044 and Epmd.port(~c"lead7") == 7
    assert Epmd.port(:world@host) == 4370 and Epmd.port("a1b@host") == 4370
    assert Epmd.start_link() == :ignore
    assert {:ok, creation} = Epmd.register_node(~c"a4371", 4371)
    assert {:ok, other} = Epmd.register_node(~c"a4371", 4371, :inet)
    assert creation > 3 and other > 3
    assert Epmd.listen_port_please(~c"a4371", ~c"127.0.0.1") == {:ok, 4371}
    assert Epmd.port_please(~c"b4372", {127, 0, 0, 1}) == {:port, 4372, 5}
    assert Epmd.port_please(~c"b4372", {127, 0, 0, 1}, 1_000) == {:port, 4372, 5}
    assert Epmd.address_please(~c"b4372", ~c"127.0.0.1", :inet) == {:ok, {127, 0, 0, 1}}
    assert Epmd.names(~c"127.0.0.1") == {:error, :address}
  end

  # A port that no program uses now.
  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  # The VM of a node of the test, as a port: its lines come as messages.
  defp vm(role, name, more) do
    mix = System.find_executable("mix.com") || System.find_executable("mix")

    env =
      [
        {"MIX_ENV", "test"},
        {"ERL_FLAGS", "-start_epmd false -epmd_module Elixir.World.Epmd"},
        {"WORLD_NODE", name},
        {"WORLD_COOKIE", "world_crew_nodes_test"}
      ] ++ more

    Port.open({:spawn_executable, mix}, [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      {:line, 4_096},
      args: ["run", "--no-compile", "--no-deps-check", "test/world/crew_node.exs", role],
      env: for({k, v} <- env, do: {String.to_charlist(k), String.to_charlist(v)})
    ])
  end

  # The results of a VM (`RESULT key value`) until it ends, with its other lines.
  defp results(port, seen \\ %{}, lines \\ []) do
    receive do
      {^port, {:data, {_, "RESULT " <> line}}} ->
        [key, value] = String.split(line, " ", parts: 2)
        results(port, Map.put(seen, key, value), lines)

      {^port, {:data, {_, line}}} ->
        results(port, seen, [line | lines])

      {^port, {:exit_status, status}} ->
        {status, seen, Enum.reverse(lines)}
    after
      240_000 -> {:timeout, seen, Enum.reverse(lines)}
    end
  end

  test "two nodes share their workers: a model has the same bytes with two nodes, and when the second node stops in the middle" do
    {a, b} = {"lead#{free_port()}@127.0.0.1", "guest#{free_port()}@127.0.0.1"}
    lead = vm("lead", a, [])
    guest = vm("guest", b, [{"WORLD_JOIN", a}])
    {:os_pid, guest_pid} = Port.info(guest, :os_pid)

    try do
      {status, seen, lines} = results(lead)
      assert status == 0, Enum.join(lines, "\n")
      assert seen["workers"] == "#{2 * System.schedulers_online()}"
      # The jobs of one site: the tasks of each node did some.
      {here, there} = {String.to_integer(seen["jobs_here"]), String.to_integer(seen["jobs_there"])}
      assert here + there == 20_000 and here > 0 and there > 0
      # The model, as the file of the catalog: with the workers of two nodes, with a
      # node that stops in the middle, and alone.
      file = Base.encode16(:crypto.hash(:sha256, File.read!("priv/models/dog_edits.glb")), case: :lower)
      assert seen["first"] == file and seen["second"] == file and seen["third"] == file
      assert String.to_integer(seen["looks_with_their_tasks"]) > 10
      assert seen["halted_in_the_build"] == "true"
    after
      System.cmd("kill", ["-9", "#{guest_pid}"], stderr_to_stdout: true)
    end
  end
end
