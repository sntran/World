defmodule World.Census do
  @moduledoc """
  The census of the node (`docs/plans/0001-people-build-on-demand.md`,
  D14 and R5): the people, their trades, and the construction that holds
  each one.

  A construction asks for a person of a trade (`hire/4`). The census
  gives it a free person of that trade, or a new person while the node
  has fewer people than its limit. At the limit, a free person of another
  trade leaves the node and a new person of the trade takes its place.
  With no free person at all, the construction waits. When a person is
  free again (`release/3`), the census gives it to the construction that
  waits and holds the fewest people; two that hold the same count go in
  the order of their requests. So the constructions of the node share
  the people.

  The census watches each construction and each person: a construction
  that stops lets its people go, and a person that stops leaves the
  census (its construction gets `{:lost, person}`).
  """
  use GenServer

  alias World.Person

  @limit 10_000

  @doc """
  Start the census. The options: `name` (`World.Census` by default),
  `limit` (the most people of the node; the application environment
  `:world, :people`, else #{@limit}).
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Ask for a person of `trade` for `construction`: it gets `{:hired, ref, person}`."
  def hire(trade, construction, ref, server \\ __MODULE__),
    do: GenServer.cast(server, {:hire, trade, construction, ref})

  @doc "A person that `construction` lets go."
  def release(person, construction, server \\ __MODULE__),
    do: GenServer.cast(server, {:release, person, construction})

  @doc """
  The people of the node: each with its name, its trade, its job and the
  construction that holds it (its name, or nil), and the requests that
  wait (the construction and the trade).
  """
  def people(server \\ __MODULE__), do: GenServer.call(server, :people)

  @impl true
  def init(opts) do
    limit = Keyword.get_lazy(opts, :limit, fn -> Application.get_env(:world, :people, @limit) end)
    {:ok, %{people: %{}, waiting: [], watched: MapSet.new(), limit: limit, count: 0}}
  end

  @impl true
  def handle_cast({:hire, trade, c, ref}, s) do
    s = %{s | waiting: s.waiting ++ [{c, trade, ref, s.count}], count: s.count + 1}
    {:noreply, serve(s)}
  end

  def handle_cast({:release, p, c}, s) do
    case s.people do
      %{^p => %{by: ^c} = info} -> {:noreply, serve(put_in(s.people[p], %{info | by: nil}))}
      _ -> {:noreply, s}
    end
  end

  @impl true
  def handle_call(:people, _from, s) do
    people =
      for {p, info} <- Enum.sort(s.people) do
        %{"name" => Person.name(p), "trade" => info.trade, "job" => info.job, "by" => info.by && Person.name(info.by)}
      end

    waiting = for {c, trade, _, _} <- s.waiting, do: %{"by" => Person.name(c), "trade" => trade}
    {:reply, %{"people" => people, "waiting" => waiting}, s}
  end

  @impl true
  def handle_info({:DOWN, _, :process, pid, _}, s) do
    case Map.pop(s.people, pid) do
      {nil, _} ->
        # A construction: its people are free, its requests go.
        people = Map.new(s.people, fn {p, info} -> {p, if(info.by == pid, do: %{info | by: nil}, else: info)} end)
        waiting = Enum.reject(s.waiting, fn {c, _, _, _} -> c == pid end)
        {:noreply, serve(%{s | people: people, waiting: waiting, watched: MapSet.delete(s.watched, pid)})}

      {info, people} ->
        if info.by, do: send(info.by, {:lost, pid})
        {:noreply, serve(%{s | people: people})}
    end
  end

  # Give a person to each request that can have one now: the request of
  # the construction that holds the fewest people first.
  defp serve(s) do
    held = Enum.frequencies(for {_, %{by: c}} <- s.people, c, do: c)
    order = Enum.sort_by(s.waiting, fn {c, _, _, n} -> {Map.get(held, c, 0), n} end)

    case Enum.find_value(order, &give(s, &1)) do
      nil -> s
      s -> serve(s)
    end
  end

  # A person for the request, or nil: a free person of the trade, a new
  # person under the limit, or a new person in the place of a free person
  # of another trade.
  defp give(s, {c, trade, ref, _} = request) do
    free = for {p, %{by: nil} = info} <- s.people, do: {p, info.trade}

    s =
      cond do
        p = Enum.find_value(free, fn {p, t} -> t == trade && p end) -> {p, s}
        map_size(s.people) < s.limit -> born(s, trade)
        free != [] -> s |> leave(elem(hd(free), 0)) |> born(trade)
        true -> nil
      end

    with {p, s} <- s do
      send(c, {:hired, ref, p})
      s = if MapSet.member?(s.watched, c), do: s, else: watch(s, c)
      %{put_in(s.people[p].by, c) | waiting: List.delete(s.waiting, request)}
    end
  end

  defp born(s, trade) do
    {:ok, p} = DynamicSupervisor.start_child(World.Persons, {Person, trade: trade})
    {p, put_in(s.people[p], %{trade: trade, job: :worker, by: nil, ref: Process.monitor(p)})}
  end

  defp leave(s, p) do
    Process.demonitor(s.people[p].ref, [:flush])
    DynamicSupervisor.terminate_child(World.Persons, p)
    %{s | people: Map.delete(s.people, p)}
  end

  defp watch(s, c) do
    Process.monitor(c)
    %{s | watched: MapSet.put(s.watched, c)}
  end
end
