defmodule World.Shift.PassesTest do
  # The cookies and the passes of the construction shifts on the edge.
  # (Not async: the registry of the labour and the passes of the node.)
  use ExUnit.Case

  alias World.Elements.Store
  alias World.Shift.Passes

  @moduletag timeout: 300_000

  # Passes as on the edge: the functions of the distribution record their calls.
  defp passes(name, opts \\ []) do
    me = self()

    defaults = [
      name: name,
      secret: true,
      alive?: fn -> true end,
      set_cookie: fn node, cookie -> send(me, {:cookie, node, cookie}) end,
      own_cookie: fn cookie -> send(me, {:own, cookie}) end,
      me: fn -> :world@edge end
    ]

    start_supervised!({Passes, Keyword.merge(defaults, opts)}, id: name)
  end

  test "a shift joins: a name for its node, a cookie for that node only, and a pass; the edge has its own secret cookie" do
    p = passes(:passes_a)
    assert_receive {:own, own}
    assert byte_size(Atom.to_string(own)) == 43

    assert {:ok, %{"node" => node, "cookie" => cookie, "pass" => pass, "edge" => "world@edge"}} =
             Passes.join("123-1", p)

    assert node =~ ~r/^shift_1231_\d+_4372@127\.0\.0\.1$/
    assert World.Epmd.port(node) == 4372
    assert byte_size(cookie) == 43 and pass =~ ~r/^[0-9a-f]{64}$/
    node = String.to_atom(node)
    cookie = String.to_atom(cookie)
    assert_receive {:cookie, ^node, ^cookie}
    assert Passes.node_of(pass, p) == node
    assert Passes.node_of("another pass", p) == nil

    # Two runners: two names, two cookies.
    {:ok, other} = Passes.join("123-1", p)
    assert other["node"] != Atom.to_string(node) and other["cookie"] != Atom.to_string(cookie)

    # The start of the distribution of the edge: a new secret cookie, and the cookie of each pass again;
    # another node that comes changes nothing.
    send(p, {:nodeup, :world@edge, node_type: :visible})
    assert_receive {:own, again} when again != own
    assert_receive {:cookie, ^node, ^cookie}
    send(p, {:nodeup, node, node_type: :hidden})
    send(p, :other)
    refute_receive {:own, _}, 50

    # A node that goes keeps its pass and its cookie for a time: it can connect again.
    send(p, {:nodedown, node, node_type: :hidden})
    refute_receive {:cookie, ^node, _}, 50
    assert Passes.node_of(pass, p) == node
    assert Passes.node_of(other["pass"], p) == String.to_atom(other["node"])
  end

  # A store of the passes in an agent (World.Shift.Store on the edge).
  defmodule Rows do
    def start(rows), do: Agent.start_link(fn -> rows end, name: __MODULE__)

    def put(pass, node, cookie, at),
      do: Agent.update(__MODULE__, &Map.put(&1, pass, %{pass: pass, node: node, cookie: cookie, at: at}))

    def drop(pass), do: Agent.update(__MODULE__, &Map.delete(&1, pass))
    def all, do: {:ok, Agent.get(__MODULE__, &Map.values/1)}
    def rows, do: Agent.get(__MODULE__, & &1)
  end

  defmodule NoRows do
    def all, do: :error
  end

  test "the passes in the store: a VM that starts again reads them back, and sets their cookies at the start of its distribution" do
    {:ok, clock} = Agent.start_link(fn -> 10 * 3_600_000 end)
    now = fn -> Agent.get(clock, & &1) end
    fresh = %{pass: String.duplicate("a", 64), node: :"shift_1_1_4372@127.0.0.1", cookie: :c1, at: now.() - 60_000}
    old = %{pass: String.duplicate("b", 64), node: :"shift_2_2_4372@127.0.0.1", cookie: :c2, at: now.() - 7 * 3_600_000}
    # (A second pass of the node of `fresh`, of a later join: its cookie is the one to set.)
    later = %{fresh | pass: String.duplicate("d", 64), cookie: :c3, at: fresh.at + 1}
    {:ok, _} = Rows.start(%{fresh.pass => fresh, old.pass => old, later.pass => later})

    # (The distribution of the edge starts after the passes, with no nodeup of itself: no cookie yet,
    # and a look each `look` ms.)
    {:ok, alive} = Agent.start_link(fn -> false end)
    p = passes(:passes_s, store: Rows, clock: now, alive?: fn -> Agent.get(alive, & &1) end, look: 10, sweep: 10_000)
    refute_receive {:cookie, _, _}, 50
    assert Passes.node_of(fresh.pass, p) == fresh.node and Passes.node_of(old.pass, p) == nil
    # (A read of the store before the distribution: nothing.)
    send(p, :sync)
    refute_receive {:cookie, _, _}, 20
    Agent.update(alive, fn _ -> true end)
    assert_receive {:own, _}
    assert_receive {:cookie, :"shift_1_1_4372@127.0.0.1", :c3}
    refute_receive {:cookie, :"shift_1_1_4372@127.0.0.1", :c1}, 20

    # A join goes to the store; a VM that is a node already sets the cookies at its start.
    q = passes(:passes_t, store: Rows, clock: now)
    assert_receive {:cookie, :"shift_1_1_4372@127.0.0.1", :c3}
    # A VM from a memory image of a time before a join: each read of the store takes the passes it does not have.
    other = %{pass: String.duplicate("e", 64), node: :"shift_5_5_4372@127.0.0.1", cookie: :c5, at: now.()}
    Rows.put(other.pass, other.node, other.cookie, other.at)
    send(q, :sync)
    assert_receive {:cookie, :"shift_5_5_4372@127.0.0.1", :c5}
    assert Passes.node_of(other.pass, q) == other.node
    send(q, :sync)
    refute_receive {:cookie, :"shift_5_5_4372@127.0.0.1", _}, 20

    {:ok, joined} = Passes.join("3-1", q)
    assert %{node: node, cookie: cookie, at: at} = Rows.rows()[joined["pass"]]
    assert Atom.to_string(node) == joined["node"] and at == now.()
    assert_receive {:cookie, ^node, ^cookie}

    # A node that went away 10 minutes ago goes at the next sweep, with its cookie and its row;
    # a node that came back stays.
    send(q, {:nodedown, node, node_type: :hidden})
    send(q, {:nodedown, fresh.node, node_type: :hidden})
    send(q, {:nodeup, fresh.node, node_type: :hidden})
    # (A call: the messages before it are done before the clock moves.)
    assert Passes.node_of(joined["pass"], q) == node
    Agent.update(clock, &(&1 + 10 * 60_000 + 1))
    send(q, :sweep)
    assert_receive {:cookie, ^node, _}
    assert Passes.node_of(joined["pass"], q) == nil and Passes.node_of(fresh.pass, q) == fresh.node
    refute Map.has_key?(Rows.rows(), joined["pass"])

    # A store that does not answer: no passes.
    r = passes(:passes_u, store: NoRows)
    assert Passes.node_of(fresh.pass, r) == nil
  end

  @tag :tmp_dir
  test "the store of the passes on this computer: put, all and drop through its program; nothing with no program", %{
    tmp_dir: dir
  } do
    alias World.Shift.Store
    pass = String.duplicate("c", 64)
    cookie = String.duplicate("K", 43)
    assert Store.put(pass, :"shift_1_1_4372@127.0.0.1", String.to_atom(cookie), 5) == :ok
    assert Store.drop(pass) == :ok and Store.all() == {:ok, []} and not Store.on?()

    Application.put_env(:world, Store,
      program: Path.expand("../../../scripts/shift-store.mjs", __DIR__),
      file: Path.join(dir, "p.json")
    )

    on_exit(fn -> Application.delete_env(:world, Store) end)
    assert Store.put(pass, :"shift_1_1_4372@127.0.0.1", String.to_atom(cookie), 5) == :ok

    assert Store.all() ==
             {:ok, [%{pass: pass, node: :"shift_1_1_4372@127.0.0.1", cookie: String.to_atom(cookie), at: 5}]}

    assert Store.drop(pass) == :ok and Store.all() == {:ok, []}
    # A wrong value: the program ends with the exit status 1.
    assert Store.put("x", :"shift_1_1_4372@127.0.0.1", String.to_atom(cookie), 5) == :error
    assert Store.drop("x") == :error

    Application.put_env(:world, Store, program: "/bin/false", file: Path.join(dir, "p.json"))
    assert Store.all() == :error
  end

  test "no join on a VM with no shifts, or before its distribution; a pass with no node goes after 6 hours" do
    assert Passes.join("1-1", passes(:passes_b, secret: false)) == {:error, :no_shifts}
    refute_receive {:own, _}, 20
    assert Passes.join("1-1", passes(:passes_c, alive?: fn -> false end)) == {:error, :no_distribution}

    {:ok, clock} = Agent.start_link(fn -> 0 end)
    p = passes(:passes_d, clock: fn -> Agent.get(clock, & &1) end)
    {:ok, old} = Passes.join("1-1", p)
    Agent.update(clock, &(&1 + 6 * 3_600_000 + 1))
    {:ok, new} = Passes.join("2-1", p)
    old_node = String.to_atom(old["node"])
    assert_receive {:cookie, ^old_node, _}
    assert Passes.node_of(old["pass"], p) == nil and Passes.node_of(new["pass"], p) != nil
  end

  test "a pass reads and puts only the parts that the edge gave to its shift, their recipes and orders, and the blueprints" do
    p = passes(:passes_e)
    {:ok, %{"node" => node, "pass" => pass}} = Passes.join("9-1", p)
    {:ok, %{"pass" => other}} = Passes.join("9-2", p)
    [given, not_given, no_recipe] = for c <- ["7", "8", "9"], do: String.duplicate(c, 32)

    :ok =
      Store.put_recipe(
        given,
        JSON.encode!(%{"order" => String.duplicate("a", 32), "level" => "mid", "node" => "n", "tile" => nil})
      )

    # (The edge gives a part to the node: World.Labour has it in work on the node.)
    me = self()

    holder =
      spawn_link(fn ->
        {:ok, _} = Registry.register(World.Labour, {World.Crew.Tasks, String.to_atom(node)}, given)
        {:ok, _} = Registry.register(World.Labour, {World.Crew.Tasks, String.to_atom(node)}, no_recipe)
        send(me, :given)
        Process.sleep(:infinity)
      end)

    assert_receive :given
    assert Passes.allowed?(pass, "parts/#{given}.glb", :write, p)
    assert Passes.allowed?(pass, "parts/#{given}.glb", :read, p)
    assert Passes.allowed?(pass, "parts/#{given}.json", :read, p)
    assert Passes.allowed?(pass, "orders/#{String.duplicate("a", 32)}.json", :read, p)
    assert Passes.allowed?(pass, "blueprints/#{String.duplicate("b", 32)}.json", :read, p)
    refute Passes.allowed?(pass, "parts/#{given}.json", :write, p)
    refute Passes.allowed?(pass, "orders/#{String.duplicate("a", 32)}.json", :write, p)
    refute Passes.allowed?(pass, "parts/#{not_given}.glb", :write, p)
    refute Passes.allowed?(pass, "parts/#{not_given}.json", :read, p)
    # Another shift, and a pass that is not a pass.
    refute Passes.allowed?(other, "parts/#{given}.glb", :write, p)
    refute Passes.allowed?("no pass", "parts/#{given}.glb", :read, p)
    # The part is done: no more.
    Process.unlink(holder)
    Process.exit(holder, :kill)
    Process.sleep(20)
    refute Passes.allowed?(pass, "parts/#{given}.glb", :write, p)
  end

  test "the routes of the Worker: a join and a check of a pass" do
    call = fn conn -> World.Service.call(conn, World.Service.init([])) end

    post = fn headers ->
      Enum.reduce(headers, Plug.Test.conn(:post, "/shift/join"), fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
    end

    get = fn query, headers ->
      Enum.reduce(headers, Plug.Test.conn(:get, "/shift/allowed?" <> query), fn {k, v}, c ->
        Plug.Conn.put_req_header(c, k, v)
      end)
    end

    # The passes of this node: no shifts (a server on a computer).
    assert call.(post.([])).status == 403
    assert call.(post.([{"x-world-shift-run", "1-1"}])).resp_body =~ "no shifts on this VM"
    assert call.(get.("key=parts/x.glb", [])).status == 403

    # The passes of an edge.
    Supervisor.terminate_child(World.Supervisor, Passes)
    on_exit(fn -> Supervisor.restart_child(World.Supervisor, Passes) end)
    passes(Passes)
    joined = call.(post.([{"x-world-shift-run", "5-1"}]))
    assert joined.status == 200
    %{"pass" => pass, "node" => node} = JSON.decode!(joined.resp_body)
    key = String.duplicate("6", 32)
    assert call.(get.("key=parts/#{key}.glb&access=write", [{"x-world-shift-pass", pass}])).status == 403
    {:ok, _} = Registry.register(World.Labour, {World.Crew.Tasks, String.to_atom(node)}, key)
    assert call.(get.("key=parts/#{key}.glb&access=write", [{"x-world-shift-pass", pass}])).status == 204
    assert call.(get.("key=parts/#{key}.glb", [{"x-world-shift-pass", pass}])).status == 204
    assert call.(get.("", [{"x-world-shift-pass", pass}])).status == 403
    Registry.unregister(World.Labour, {World.Crew.Tasks, String.to_atom(node)})

    # Before the distribution of the edge.
    stop_supervised!(Passes)
    passes(Passes, alive?: fn -> false end)
    assert call.(post.([{"x-world-shift-run", "5-1"}])).status == 503
  end

  # A VM of its own (mix run, with no application), with the module of the
  # ports of World.
  defp vm(code, opts \\ []) do
    mix = System.find_executable("mix.com") || System.find_executable("mix")
    flags = "-start_epmd false -epmd_module Elixir.World.Epmd -kernel inet_dist_use_interface {127,0,0,1}"
    env = [{~c"ERL_FLAGS", String.to_charlist(flags)}, {~c"MIX_ENV", ~c"test"}]
    args = ["run", "--no-compile", "--no-deps-check", "--no-start", "-e", code]

    if opts[:open] do
      Port.open({:spawn_executable, mix}, [:binary, {:line, 4096}, :exit_status, args: args, env: env])
    else
      {out, _} =
        System.cmd(mix, args, env: Enum.map(env, fn {k, v} -> {to_string(k), to_string(v)} end), stderr_to_stdout: true)

      out
    end
  end

  defp line(port, prefix) do
    receive do
      {^port, {:data, {:eol, <<^prefix::binary-size(byte_size(prefix)), rest::binary>>}}} -> rest
      {^port, {:data, _}} -> line(port, prefix)
    after
      120_000 -> flunk("no #{prefix} from the VM")
    end
  end

  test "with real nodes: the node of a join connects with its cookie; another cookie, or a node with no join, does not" do
    edge =
      vm(
        ~S"""
        {:ok, _} = Node.start(:"edge4391@127.0.0.1", :longnames)
        {:ok, _} = World.Shift.Passes.start_link(secret: true, name: :passes)
        {:ok, a} = World.Shift.Passes.join("test", :passes)
        IO.puts("JOIN " <> JSON.encode!(a))
        :ok = :net_kernel.monitor_nodes(true)
        for _ <- 1..20 do
          receive do
            {:nodeup, n} -> IO.puts("UP #{n}")
            _ -> :ok
          after
            30_000 -> :ok
          end
        end
        """,
        open: true
      )

    joined = JSON.decode!(line(edge, "JOIN "))

    connect = fn node, cookie ->
      vm(
        ~s|{:ok, _} = Node.start(:"#{node}", :longnames); Node.set_cookie(:"#{cookie}"); IO.puts("CONNECT \#{Node.connect(:"#{joined["edge"]}")}")|
      )
    end

    try do
      assert connect.(joined["node"], joined["cookie"]) =~ "CONNECT true"
      assert line(edge, "UP ") == joined["node"]
      assert connect.(joined["node"], "another_cookie") =~ "CONNECT false"
      assert connect.("shift_nojoin_1_4373@127.0.0.1", joined["cookie"]) =~ "CONNECT false"
    after
      {:os_pid, pid} = Port.info(edge, :os_pid)
      System.cmd("kill", [to_string(pid)])
    end
  end
end
