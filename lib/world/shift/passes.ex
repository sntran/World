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
    that part to the node of the pass (`allowed?/2`).

  The edge has a cookie of its own that nobody knows: random, made at the
  start of its distribution (the option `secret`, `WORLD_SHIFTS=true`).
  At the end of a shift (its node goes away), the edge forgets the cookie
  of its node (a new random one) and its pass. A pass with no node after
  6 hours goes too.
  """
  use GenServer

  alias World.Elements.Store

  @most 6 * 3_600_000

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

  @doc "The node of a pass, or nil."
  def node_of(pass, passes \\ __MODULE__), do: GenServer.call(passes, {:node_of, pass})

  @doc """
  True when the shift of `pass` can read (`:read`) or put (`:write`) the
  key `key` of the store. It puts only the GLB of a part that the edge
  gave to its node now (`World.Labour`). It reads that GLB, the recipe of
  the part, its order, and the blueprints in data of the projects (an
  order can name one).
  """
  def allowed?(pass, key, access, passes \\ __MODULE__) do
    with node when node != nil <- node_of(pass, passes) do
      parts = for {_, part} <- Registry.lookup(World.Labour, {World.Crew.Tasks, node}), do: part

      case access do
        :write ->
          Enum.any?(parts, &(key == "parts/#{&1}.glb"))

        :read ->
          String.starts_with?(key, "blueprints/") or
            Enum.any?(parts, &(key in ["parts/#{&1}.glb", "parts/#{&1}.json", order_key(&1)]))
      end
    else
      nil -> false
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
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      passes: %{}
    }

    if s.secret and s.alive?.(), do: s.own_cookie.(random())
    {:ok, s}
  end

  @impl true
  def handle_call({:join, _run}, _from, %{secret: false} = s), do: {:reply, {:error, :no_shifts}, s}

  def handle_call({:join, run}, _from, s) do
    if s.alive?.() do
      s = expire(s)
      node = :"shift_#{name(run)}_#{:erlang.unique_integer([:positive])}_4372@127.0.0.1"
      cookie = random()
      s.set_cookie.(node, cookie)
      pass = Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
      passes = Map.put(s.passes, pass, %{node: node, at: s.clock.()})

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

  def handle_call({:node_of, pass}, _from, s) do
    case s.passes do
      %{^pass => %{node: node}} -> {:reply, node, s}
      _ -> {:reply, nil, s}
    end
  end

  # The start of the distribution of this node: the secret cookie of the edge.
  @impl true
  def handle_info({:nodeup, node, _info}, s) do
    if s.secret and node == s.me.(), do: s.own_cookie.(random())
    {:noreply, s}
  end

  # The end of a shift: its node goes; the cookie of that node and its pass go too.
  def handle_info({:nodedown, node, _info}, s) do
    {gone, kept} = Enum.split_with(s.passes, fn {_, p} -> p.node == node end)
    for {_, p} <- gone, do: s.set_cookie.(p.node, random())
    {:noreply, %{s | passes: Map.new(kept)}}
  end

  def handle_info(_other, s), do: {:noreply, s}

  # The passes whose node did not come in 6 hours (their cookies go too).
  defp expire(s) do
    now = s.clock.()
    {old, kept} = Enum.split_with(s.passes, fn {_, p} -> now - p.at > @most and p.node not in Node.list(:connected) end)
    for {_, p} <- old, do: s.set_cookie.(p.node, random())
    %{s | passes: Map.new(kept)}
  end

  # A cookie: 32 random bytes, as an atom of letters and digits.
  defp random, do: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false) |> String.to_atom()

  # The run in the name of a node: its letters and digits only.
  defp name(run), do: run |> to_string() |> String.replace(~r/[^A-Za-z0-9]/, "") |> String.slice(0, 40)
end
