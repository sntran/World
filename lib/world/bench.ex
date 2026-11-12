defmodule World.Bench do
  @moduledoc """
  The measure of the builds (`docs/plans/0007-actors-build-faster.md`,
  D1 and R1): each order goes through the people (`World.build/1`), one
  at a time, and gives its result, its wall time, the most memory of
  the VM, the use of the schedulers, its tasks, its elements and its
  triangles.

  The scale of the world clock is that of the call (one day in 1 ms by
  default), so the days of the tasks do not hide the work of the
  computer. `mix world.bench` prints the table.
  """

  alias World.{Log, Orders}

  @doc """
  The orders to measure, each `{name, kind, order}`: each model of the
  catalog (`"catalog"`; the drawings of `priv/drawings` are models of
  the catalog), and each blueprint in data with its default options
  (`"blueprint"`).
  """
  def orders do
    catalog =
      for {name, _} <- World.Catalog.models(),
          do: {name, "catalog", %{"blueprint" => "catalog", "options" => %{"name" => name}}}

    blueprints =
      for b <- Orders.Blueprints.data(), do: {b["name"], "blueprint", %{"blueprint" => b["name"], "options" => %{}}}

    catalog ++ blueprints
  end

  @doc """
  The orders of some names (in the order of `orders/0`), or each order
  with no names: `{:ok, orders}`, or `{:error, unknown}`.
  """
  def select([]), do: {:ok, orders()}

  def select(names) do
    all = orders()
    known = MapSet.new(all, &elem(&1, 0))

    case Enum.reject(names, &MapSet.member?(known, &1)) do
      [] -> {:ok, Enum.filter(all, &(elem(&1, 0) in names))}
      unknown -> {:error, unknown}
    end
  end

  @doc """
  Build each order and measure it. The options: `level` (`"mid"`),
  `workers` (4), `budget` (more of the budget of each build), `scale`
  (the world seconds in a second of the wall: 86,400,000, one day in
  1 ms), `timeout` (ms for each build: 600,000), and `each` (a function
  that takes each result when it is ready). The result: a list of maps.
  """
  def run(orders, opts \\ []) do
    level = Keyword.get(opts, :level, "mid")
    budget = Map.merge(%{"workers" => Keyword.get(opts, :workers, 4)}, Keyword.get(opts, :budget, %{}))
    timeout = Keyword.get(opts, :timeout, 600_000)
    each = Keyword.get(opts, :each, fn _ -> :ok end)
    old = Application.get_env(:world, :scale)
    Application.put_env(:world, :scale, Keyword.get(opts, :scale, 86_400_000))
    :erlang.system_flag(:scheduler_wall_time, true)

    try do
      for order <- orders do
        result = measure(order, level, budget, timeout)
        each.(result)
        result
      end
    after
      Application.put_env(:world, :scale, old)
    end
  end

  defp measure({name, kind, order}, level, budget, timeout) do
    base = %{"name" => name, "kind" => kind}

    case Orders.job(order, level) do
      {:error, errors} ->
        Map.merge(base, %{"result" => "order", "error" => inspect(errors)})

      {:ok, job} ->
        id = "bench-#{name}-#{System.unique_integer([:positive])}"
        sampler = sampler()
        s0 = :erlang.statistics(:scheduler_wall_time)
        t0 = System.monotonic_time(:millisecond)
        {:ok, ^id} = World.build(Map.put(%{job | id: id}, :budget, budget))
        outcome = World.await(id, timeout)
        ms = System.monotonic_time(:millisecond) - t0
        use = schedulers(s0, :erlang.statistics(:scheduler_wall_time))
        peak = peak(sampler)
        if outcome == {:error, :timeout}, do: stop(id)

        base
        |> Map.merge(outcome(outcome))
        |> Map.merge(%{"ms" => ms, "peak_mb" => Float.round(peak / 1_048_576, 1)})
        |> Map.merge(use)
    end
  end

  # A build that takes too long stops, and its message does not stay.
  defp stop(id) do
    World.cancel(id)
    World.await(id, 5_000)
  end

  defp outcome({:ok, r}) do
    events = Log.events(r.log)

    %{
      "result" => "built",
      "tasks" => Enum.count(events, &(&1.kind == "task_started")),
      "elements" => Enum.count(events, &(&1.kind == "element")),
      "triangles" => triangles(r.glb),
      "bytes" => byte_size(r.glb)
    }
  end

  defp outcome({:error, {:failed, message}}), do: %{"result" => "failed", "error" => message}
  defp outcome({:error, {:stopped, reason}}), do: %{"result" => "stopped", "error" => inspect(reason)}
  defp outcome({:error, :timeout}), do: %{"result" => "timeout"}

  # The use of the normal schedulers between two samples of their wall
  # time: `busy`, the part of the time that they work (0 to 1), and
  # `cores`, how many of them work on average.
  defp schedulers(s0, s1) do
    n = :erlang.system_info(:schedulers)
    before = Map.new(s0, fn {id, active, total} -> {id, {active, total}} end)

    parts =
      for {id, active, total} <- s1, id <= n, {a0, t0} = before[id], total > t0, do: {active - a0, total - t0}

    {active, total} = Enum.reduce(parts, {0, 0}, fn {a, t}, {sa, st} -> {sa + a, st + t} end)
    cores = parts |> Enum.map(fn {a, t} -> a / t end) |> Enum.sum()
    %{"busy" => Float.round(active / max(total, 1), 3), "cores" => Float.round(cores / 1, 2)}
  end

  # The most memory of the VM while a build runs: a sample each 10 ms.
  defp sampler do
    spawn_link(fn -> sample(:erlang.memory(:total)) end)
  end

  defp sample(most) do
    receive do
      {:peak, to} -> send(to, {:peak, self(), max(most, :erlang.memory(:total))})
    after
      10 -> sample(max(most, :erlang.memory(:total)))
    end
  end

  defp peak(pid) do
    send(pid, {:peak, self()})

    receive do
      {:peak, ^pid, most} -> most
    end
  end

  @doc "The triangles of a GLB: the indices (or the points) of each primitive, in threes."
  def triangles(<<"glTF", _::binary-8, n::little-32, "JSON", json::binary-size(n), _::binary>>) do
    gltf = JSON.decode!(json)
    accessors = gltf["accessors"] || []

    for mesh <- gltf["meshes"] || [], p <- mesh["primitives"], reduce: 0 do
      sum ->
        index = p["indices"] || p["attributes"]["POSITION"]
        sum + div(Enum.at(accessors, index)["count"], 3)
    end
  end

  @doc "The table of the results, and a line of the sums: the lines of text."
  def table(results) do
    head = ["name", "kind", "result", "ms", "peak MB", "busy", "cores", "tasks", "triangles"]

    rows =
      for r <- results do
        [r["name"], r["kind"], r["result"], r["ms"], r["peak_mb"], r["busy"], r["cores"], r["tasks"], r["triangles"]]
        |> Enum.map(&to_string(&1 || ""))
      end

    built = Enum.count(results, &(&1["result"] == "built"))
    ms = results |> Enum.map(&(&1["ms"] || 0)) |> Enum.sum()
    widths = for i <- 0..(length(head) - 1), do: Enum.max(for(row <- [head | rows], do: String.length(Enum.at(row, i))))

    line = fn row ->
      row
      |> Enum.zip(widths)
      |> Enum.map_join("  ", fn {v, w} -> String.pad_trailing(v, w) end)
      |> String.trim_trailing()
    end

    Enum.map([head | rows], line) ++ ["#{built} of #{length(results)} built, #{ms} ms"]
  end
end
