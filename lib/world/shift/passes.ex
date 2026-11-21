defmodule World.Shift.Passes do
  @moduledoc """
  The passes of the construction shifts, on the edge (`docs/factory.md`,
  "Construction shifts"). No secret of the repository proves a shift:
  the Worker checks the ID token of the job of GitHub Actions, and then
  the edge gives the runner what it needs (`join/2`):

  - a name for its node (each runner its own);
  - a cookie of 32 random bytes for that node only
    (`:erlang.set_cookie/2`): the runner sets the same cookie, and only
    that node connects with it;
  - a pass: the token of the store of the Worker (`/store/KEY`) for this
    shift. The Worker takes a key with the pass only when the edge gave
    that part to the node of the pass (`allowed?/4`).

  The VM keeps only the SHA-256 of each pass (`hash/1`), here and in its
  store, and the Worker sends only that hash to the VM (the header
  `x-world-shift-pass-hash` of `/shift/allowed`). So the pass is not in
  the Workers Logs, and not in the SQLite of the Durable Object.

  The edge has a cookie of its own that nobody knows: random, made at the
  start of its distribution (the option `secret`, `WORLD_SHIFTS=true`).

  The passes are in a store too (`World.Shift.Store`, the SQLite of the
  Durable Object): the VM of the edge can start again (a deploy, the
  limit of its memory). The runtime of the edge starts each new VM from
  a memory image of the first VM of its deploy, so the start of this
  process is not the start of each VM: each 10 seconds, it reads the
  store and takes each pass that it does not have, with the cookie of its
  node. So the node of a shift that runs connects again (`World.Crew`
  tries each 3 s).

  A node that goes away (the end of its shift, a break of its
  connection) keeps its pass and its cookie for 10 minutes: it can
  connect again. Then the edge forgets them (a new random cookie for that
  node). A pass with no node after 6 hours goes too.
  """
  use GenServer

  alias World.Elements.Store

  @most 6 * 3_600_000
  # The time that a node that went away keeps its pass and its cookie.
  @grace 10 * 60_000
  # The time between two sweeps of the passes that go.
  @sweep 60_000
  # The wait between two looks for the start of the distribution of the edge.
  @look 500
  # The time between two reads of the store (a VM from a memory image).
  @sync 10_000

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  @doc """
  A shift joins: `{:ok, %{"node", "cookie", "pass", "edge"}}` for the run
  `run` (the id and the attempt of the run of GitHub Actions, or a word
  for a test), `{:error, :no_shifts}` on a VM with no shifts (a server on
  a computer has no Worker in front of it), or `{:error,
  :no_distribution}` when this VM is not a node yet.
  """
  def join(run, passes \\ __MODULE__), do: GenServer.call(passes, {:join, run})

  @doc "The SHA-256 of a pass, in hex: the VM knows a pass only by it."
  def hash(pass), do: :crypto.hash(:sha256, pass) |> Base.encode16(case: :lower)

  @doc "The node of the hash of a pass (`hash/1`), or nil."
  def node_of(hash, passes \\ __MODULE__), do: GenServer.call(passes, {:node_of, hash})

  @doc """
  True when the shift of the hash of a pass (`hash/1`) can read (`:read`)
  or put (`:write`) the key `key` of the store. It puts only the GLB of a part that the edge
  gave to its node (`World.Labour`): in work on the node now, or, in the
  store of the queue, given to that node (`World.Labour.Store`: a new VM
  before it puts its queue back). It reads that GLB, the recipe of the
  part, its order, and the blueprints in data of the projects (an order
  can name one).
  """
  def allowed?(hash, key, access, passes \\ __MODULE__) do
    with node when node != nil <- node_of(hash, passes) do
      in_work = for {_, part} <- Registry.lookup(World.Labour, {World.Crew.Tasks, node}), do: part
      # (The store of the queue only when the parts in work do not allow it: a port call.)
      allows?(in_work, key, access) or allows?(given(node), key, access)
    else
      nil -> false
    end
  end

  defp allows?(parts, key, :write), do: Enum.any?(parts, &(key == "parts/#{&1}.glb"))

  defp allows?(parts, key, :read),
    do:
      String.starts_with?(key, "blueprints/") or
        Enum.any?(parts, &(key in ["parts/#{&1}.glb", "parts/#{&1}.json", order_key(&1)]))

  # The parts that the store of the queue gives to `node`.
  defp given(node) do
    case World.Labour.Store.all() do
      {:ok, rows} -> for %{node: ^node, key: key} <- rows, do: key
      :error -> []
    end
  end

  defp order_key(part) do
    with {:ok, json} <- Store.recipe(part), {:ok, %{"order" => hash}} <- JSON.decode(json) do
      "orders/#{hash}.json"
    else
      _ -> nil
    end
  end

  @impl true
  def init(opts) do
    :ok = :net_kernel.monitor_nodes(true, node_type: :all)

    s = %{
      secret: Keyword.get(opts, :secret, false),
      alive?: Keyword.get(opts, :alive?, &Node.alive?/0),
      set_cookie: Keyword.get(opts, :set_cookie, &:erlang.set_cookie/2),
      own_cookie: Keyword.get(opts, :own_cookie, &Node.set_cookie/1),
      me: Keyword.get(opts, :me, &node/0),
      # (The time of the Unix clock: a time in the store means the same after a start again.)
      clock: Keyword.get(opts, :clock, fn -> System.system_time(:millisecond) end),
      store: Keyword.get(opts, :store, World.Shift.Store),
      sweep: Keyword.get(opts, :sweep, @sweep),
      # The wait between two looks for the start of the distribution.
      look: Keyword.get(opts, :look, @look),
      sync: Keyword.get(opts, :sync, @sync),
      passes: %{}
    }

    s = if s.secret, do: %{s | passes: stored(s)}, else: s
    if s.secret, do: send(self(), :start)
    if s.secret, do: Process.send_after(self(), :sync, s.sync)
    Process.send_after(self(), :sweep, s.sweep)
    {:ok, s}
  end

  # The passes of the store that did not go (a VM that starts again).
  defp stored(s) do
    case s.store.all() do
      {:ok, rows} ->
        now = s.clock.()

        for r <- rows,
            now - r.at <= @most,
            into: %{},
            do: {r.pass, %{node: r.node, cookie: r.cookie, at: r.at, gone: nil}}

      :error ->
        %{}
    end
  end

  # The start of the distribution of the edge: its secret cookie, and the
  # cookie of the node of each pass again.
  # (A node with two passes gets the cookie of its last join.)
  defp start(s) do
    s.own_cookie.(random())

    for {node, passes} <- Enum.group_by(Map.values(s.passes), & &1.node),
        do: s.set_cookie.(node, Enum.max_by(passes, & &1.at).cookie)
  end

  @impl true
  def handle_call({:join, _run}, _from, %{secret: false} = s), do: {:reply, {:error, :no_shifts}, s}

  def handle_call({:join, run}, _from, s) do
    if s.alive?.() do
      s = expire(s)
      # (A random number, not a count of this VM: a VM that starts again
      # gives no name of a pass that it read back.)
      node = :"shift_#{name(run)}_#{:binary.decode_unsigned(:crypto.strong_rand_bytes(4))}_4372@127.0.0.1"
      cookie = random()
      s.set_cookie.(node, cookie)
      pass = Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
      at = s.clock.()
      # (Only the hash of the pass stays: the pass goes to the runner in the answer.)
      s.store.put(hash(pass), node, cookie, at)
      passes = Map.put(s.passes, hash(pass), %{node: node, cookie: cookie, at: at, gone: nil})

      answer = %{
        "node" => Atom.to_string(node),
        "cookie" => Atom.to_string(cookie),
        "pass" => pass,
        "edge" => Atom.to_string(s.me.())
      }

      {:reply, {:ok, answer}, %{s | passes: passes}}
    else
      {:reply, {:error, :no_distribution}, s}
    end
  end

  def handle_call({:node_of, hash}, _from, s) do
    case s.passes do
      %{^hash => %{node: node}} -> {:reply, node, s}
      _ -> {:reply, nil, s}
    end
  end

  # The start of the distribution of this node: the secret cookie of the
  # edge, and the cookies of the passes. A node of a pass that comes back
  # keeps its pass.
  @impl true
  def handle_info({:nodeup, node, _info}, s) do
    if s.secret and node == s.me.(), do: start(s)
    {:noreply, mark(s, node, nil)}
  end

  # A node goes (the end of its shift, or a break): its pass and its cookie
  # stay for a time, so that it can connect again.
  def handle_info({:nodedown, node, _info}, s), do: {:noreply, mark(s, node, s.clock.())}

  # The runtime of the edge starts its distribution after the application,
  # and a node gets no nodeup of itself: a look each 500 ms until it is a
  # node, then its secret cookie and the cookies of the passes.
  def handle_info(:start, s) do
    if s.alive?.(), do: start(s), else: Process.send_after(self(), :start, s.look)
    {:noreply, s}
  end

  # The passes of the store that this VM does not have (a VM from a memory
  # image of a time before their joins), with the cookies of their nodes.
  def handle_info(:sync, s) do
    Process.send_after(self(), :sync, s.sync)

    if s.alive?.() do
      new = Map.drop(stored(s), Map.keys(s.passes))
      for {_, p} <- new, do: s.set_cookie.(p.node, p.cookie)
      {:noreply, %{s | passes: Map.merge(s.passes, new)}}
    else
      {:noreply, s}
    end
  end

  def handle_info(:sweep, s) do
    Process.send_after(self(), :sweep, s.sweep)
    {:noreply, expire(s)}
  end

  def handle_info(_other, s), do: {:noreply, s}

  # The time when the node of each pass of `node` went (nil: it is here).
  defp mark(s, node, gone) do
    %{s | passes: Map.new(s.passes, fn {k, p} -> {k, if(p.node == node, do: %{p | gone: gone}, else: p)} end)}
  end

  # The passes that go, with their cookies (a new random one) and their
  # rows of the store: a node that went away more than 10 minutes ago, or
  # a pass of more than 6 hours whose node is not here.
  defp expire(s) do
    now = s.clock.()

    {old, kept} =
      Enum.split_with(s.passes, fn {_, p} ->
        (p.gone != nil and now - p.gone > @grace) or (now - p.at > @most and p.node not in Node.list(:connected))
      end)

    for {pass, p} <- old do
      s.set_cookie.(p.node, random())
      s.store.drop(pass)
    end

    %{s | passes: Map.new(kept)}
  end

  # A cookie: 32 random bytes, as an atom of letters and digits.
  defp random, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false) |> String.to_atom()

  # The run in the name of a node: its letters and digits only.
  defp name(run), do: run |> to_string() |> String.replace(~r/[^A-Za-z0-9]/, "") |> String.slice(0, 40)
end
