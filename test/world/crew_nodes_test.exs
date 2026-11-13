defmodule World.CrewNodesTest do
  # Two Erlang nodes share their crews (plan 0012, D8; R6): each node is
  # a VM of its own (`test/world/crew_node.exs`), with no port mapper
  # daemon (`World.Epmd`).
  use ExUnit.Case, async: false

  alias World.{Crew, Epmd}

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

  test "the options of the crews from the environment; crews with a node to join try until it answers, and again when it comes back" do
    assert World.Supervisor.crews(%{}) == []

    assert World.Supervisor.crews(%{"WORLD_NODE" => "a4371@127.0.0.1", "WORLD_COOKIE" => "c", "WORLD_JOIN" => "b@h"}) ==
             [node: :"a4371@127.0.0.1", cookie: :c, join: :b@h]

    # The crews start the node with their name (here: a function in the place of the start of a node).
    me = self()

    started = fn name, kind ->
      send(me, {:node, name, kind})
      {:ok, me}
    end

    cookie = Node.get_cookie()

    named =
      start_supervised!({Crew, name: nil, workers: 1, node: :"a4371@127.0.0.1", cookie: cookie, distribution: started},
        id: :named
      )

    assert_receive {:node, :"a4371@127.0.0.1", :longnames}
    assert Crew.state(named).workers == 1
    # (A try with no node to join changes nothing.)
    send(named, :join)
    assert Crew.state(named).workers == 1

    # Crews with a node to join: no answer at first, then the other crews come.
    {:ok, lead} = Crew.start_link(name: :crew_nodes_lead, workers: 2)
    Process.unlink(lead)
    guest = start_supervised!({Crew, name: nil, workers: 3, join: {:global, :crew_nodes_later}, retry: 20}, id: :guest)
    Process.sleep(60)
    assert Crew.state(guest).workers == 3
    :yes = :global.register_name(:crew_nodes_later, lead)
    wait = fn wait, done? -> if done?.(), do: :ok, else: Process.sleep(5) && wait.(wait, done?) end
    wait.(wait, fn -> Crew.state(lead).workers == 5 end)
    assert Crew.state(guest).workers == 0
    assert Crew.map(1..50, & &1, guest) == Enum.to_list(1..50)

    # The other crews stop: the crews are at home, and try again. New crews with that name: they join.
    GenServer.stop(lead)
    wait.(wait, fn -> Crew.state(guest).workers == 3 end)
    {:ok, again} = Crew.start_link(name: nil, workers: 1)
    :yes = :global.register_name(:crew_nodes_later, again)
    wait.(wait, fn -> Crew.state(again).workers == 4 end)
    # A leave by a call: no more tries.
    assert Crew.leave(guest) == :ok
    Process.sleep(60)
    assert Crew.state(guest).workers == 3 and Crew.state(again).workers == 1
    GenServer.stop(again)
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

  test "a second node gives its workers to the sites of the first; a model has the same bytes with two nodes, and when the second node stops in the middle" do
    {a, b} = {"lead#{free_port()}@127.0.0.1", "guest#{free_port()}@127.0.0.1"}
    lead = vm("lead", a, [])
    guest = vm("guest", b, [{"WORLD_JOIN", a}])
    {:os_pid, guest_pid} = Port.info(guest, :os_pid)

    try do
      {status, seen, lines} = results(lead)
      assert status == 0, Enum.join(lines, "\n")
      own = 2 * System.schedulers_online()
      # The first node has the workers of both.
      assert seen["workers"] == "#{2 * own}"
      # The jobs of one site: the workers of each node did some.
      {here, there} = {String.to_integer(seen["jobs_here"]), String.to_integer(seen["jobs_there"])}
      assert here + there == 20_000 and here > 0 and there > 0
      # The model, as the file of the catalog: with the workers of two nodes, with a
      # node that stops in the middle, and alone.
      file = Base.encode16(:crypto.hash(:sha256, File.read!("priv/models/dog_edits.glb")), case: :lower)
      assert seen["first"] == file and seen["second"] == file and seen["third"] == file
      assert String.to_integer(seen["looks_with_their_workers"]) > 10
      assert seen["halted_in_the_build"] == "true"
      assert seen["workers_after"] == "#{own}"
    after
      System.cmd("kill", ["-9", "#{guest_pid}"], stderr_to_stdout: true)
    end
  end
end
