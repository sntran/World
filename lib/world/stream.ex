defmodule World.Stream do
  @moduledoc """
  A stream of events over HTTP, as server-sent events
  (`docs/plans/0001-people-build-on-demand.md`, R17 and R19): one event
  of the log of the node (`World.Log.Server`) in each message, with its
  id, so a client that comes back with `Last-Event-ID` gets the events
  after it. A comment each #{15} s (`:ping` of the application
  environment for this module) keeps the connection open, and tells when
  the client went away.

  `open/2` watches first, and `follow/4` sends the events of the past
  and then each new event: no event falls between the two.
  """
  import Plug.Conn

  @doc "Watch `key` (the id of a construction, or `:world`), and open the stream of the response."
  def open(conn, key) do
    World.watch(key)
    Process.set_label({:stream, key})

    conn
    |> put_resp_header("content-type", "text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> send_chunked(200)
  end

  @doc """
  Send the events of `key` after the id `after_id`: the events of the
  past from the log of the node, then each new event, until `last?` is
  true for an event (the end of a construction), or the client goes
  away.
  """
  def follow(conn, key, after_id, last? \\ fn _ -> false end) do
    past = for e <- World.Log.Server.history(after_id), key == :world or e["order"] == key, do: e
    run(conn, past, key, after_id, last?)
  end

  # Send the events in hand, then wait for the next one, or for the time
  # of a ping. The watchers of `key` get only the events of `key`; an
  # event that the past had already comes again live, and goes.
  defp run(conn, [e | rest], key, seen, last?) do
    case chunk(conn, frame(e)) do
      {:ok, conn} -> if e != :ping and last?.(e), do: conn, else: run(conn, rest, key, seen(e, seen), last?)
      {:error, _} -> conn
    end
  end

  defp run(conn, [], key, seen, last?) do
    receive do
      {:world, %{"id" => id} = e} when id > seen -> run(conn, [e], key, seen, last?)
      {:world, _} -> run(conn, [], key, seen, last?)
    after
      ping() -> run(conn, [:ping], key, seen, last?)
    end
  end

  defp frame(:ping), do: ": ping\n\n"
  defp frame(e), do: "id: #{e["id"]}\ndata: #{JSON.encode!(e)}\n\n"

  defp seen(:ping, seen), do: seen
  defp seen(e, _), do: e["id"]

  defp ping, do: Keyword.get(Application.get_env(:world, __MODULE__, []), :ping, 15_000)
end
