defmodule World.Service do
  @moduledoc """
  The HTTP service of the factory in the VM (`docs/factory.md`). The
  Worker (`worker.js`) gives it the orders that are not in its cache, and
  keeps the files in R2.

  - `GET /blueprints`: each blueprint with its options, as JSON.
  - `POST /check`: an order in the body. 200 with `{"hash", "order"}` (the
    full order), or 422 with `{"errors"}`.
  - `POST /orders`: an order in the body. The full order goes into the
    store of the orders (`World.Orders.place/2`): 200 with `{"hash",
    "order", "files", "replay"}`, 422 with `{"errors"}`, or 503 when the
    store failed.
  - `POST /sets`: a set of orders in the body (`World.Orders.Set`): each
    order goes into the store, 200 with `{"set", "variants"}` (each
    variant with its hash, its full order, its files and its lot), 422
    with `{"errors"}`, or 503 when the store failed.
  - `POST /build?level=near&file=glb`: an order in the body, or
    `&hash=HASH` with no body for an order of `POST /orders` (404 when
    the store has no order of the hash). 200 with the file
    (`World.Orders.files/0`: `glb`, `log`, `replay`, `parts` or
    `receipt`), or 422 with `{"errors"}`. The header `server-timing`
    has the time of the build in the VM (`build;dur=MS`), with no wait
    for the build before it, and the header `x-world-order` the hash of
    the full order (the Worker keeps the file of a URL `/m/` by it).
  - `POST /mcp`: the MCP server (`World.MCP`). The other methods give
    405.
  - `POST /builds`: a job in the body: `{"order", "level", "budget"}`
    (`World.budget/1`). The order goes into the store of the orders, and
    a construction of the people of the node builds it
    (`World.build/1`). With `accept: text/event-stream`, the response is
    the stream of the construction until its end; else 202 with
    `{"build", "hash", "after", "events", "files"}`. 422 with
    `{"errors"}`, or 503 when the store failed.
  - `GET /builds/ID`: the state of a construction from the log of the
    node: its status, its tasks, the tasks done and its elements (404
    when the log has none).
  - `GET /builds/ID/events`: the stream of a construction until its end,
    after the id of `Last-Event-ID` or of `?after=N`.
  - `GET /builds/ID/elements/KEY.glb`: the GLB of an element.
  - `GET /events`: the stream of the whole world, after the id of
    `Last-Event-ID` or of `?after=N`.
  - `GET /census`: the people of the node (`World.census/0`).

  A body that is not JSON gives 400. A body of more than 1 MB gives 413.
  The header `x-world-origin` (from the Worker) is the start of the URLs
  of an order: `https://world.mkfifo.com`.
  """
  use Plug.Router

  alias World.{Construction, MCP, Orders, Stream}
  alias World.Orders.{Blueprint, Blueprints, Set, Store}

  plug(:match)
  plug(:dispatch)

  @types %{
    "glb" => "model/gltf-binary",
    "replay" => "model/gltf-binary",
    "log" => "application/json",
    "parts" => "application/json",
    "receipt" => "application/json"
  }

  get "/blueprints" do
    json(conn, 200, Enum.map(Blueprints.all(), &Blueprint.describe/1))
  end

  # A blueprint in data of a project (plan 0002, D1): the store keeps it,
  # and an order gives {"hash": HASH} as its blueprint.
  post "/blueprints" do
    with_order(conn, fn raw ->
      case Orders.keep_blueprint(raw) do
        {:ok, kept} ->
          json(conn, 201, kept)

        {:error, :store} ->
          json(conn, 503, %{"errors" => [%{"path" => "", "message" => "the store of the blueprints failed"}]})

        {:error, errors} ->
          json(conn, 422, %{"errors" => errors})
      end
    end)
  end

  post "/check" do
    with_order(conn, fn order ->
      case Orders.check(order) do
        {:ok, full} -> json(conn, 200, %{"hash" => Orders.hash(full), "order" => full})
        {:error, errors} -> json(conn, 422, %{"errors" => errors})
      end
    end)
  end

  post "/orders" do
    with_order(conn, fn order ->
      case Orders.place(order, origin(conn)) do
        {:ok, placed} ->
          json(conn, 200, placed)

        {:error, :store} ->
          json(conn, 503, %{"errors" => [%{"path" => "", "message" => "the store of the orders failed"}]})

        {:error, errors} ->
          json(conn, 422, %{"errors" => errors})
      end
    end)
  end

  post "/sets" do
    with_order(conn, fn set ->
      case Set.place(set, origin(conn)) do
        {:ok, placed} ->
          json(conn, 200, placed)

        {:error, :store} ->
          json(conn, 503, %{"errors" => [%{"path" => "", "message" => "the store of the orders failed"}]})

        {:error, errors} ->
          json(conn, 422, %{"errors" => errors})
      end
    end)
  end

  post "/mcp" do
    case read_body(conn, length: 1_000_000) do
      {:ok, body, conn} ->
        version = conn |> get_req_header("mcp-protocol-version") |> List.first()

        case MCP.answer(body, version, origin(conn)) do
          {202, nil} -> send_resp(conn, 202, "")
          {status, message} -> json(conn, status, message)
        end

      {:more, _, conn} ->
        json(conn, 413, %{
          "jsonrpc" => "2.0",
          "id" => nil,
          "error" => %{"code" => -32600, "message" => "the body is more than 1 MB"}
        })
    end
  end

  match "/mcp" do
    conn
    |> put_resp_header("allow", "POST")
    |> json(405, %{
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => %{"code" => -32000, "message" => "use POST: this server sends no event stream"}
    })
  end

  post "/build" do
    conn = fetch_query_params(conn)
    file = Map.get(conn.query_params, "file", "glb")
    level = Map.get(conn.query_params, "level", "near")

    with_order(conn, fn order ->
      case one_at_a_time(fn -> :timer.tc(Orders, :build, [order, level, file], :millisecond) end) do
        {ms, {:ok, out}} ->
          {:ok, full} = Orders.check(order)

          conn
          |> put_resp_header("server-timing", "build;dur=#{ms}")
          |> put_resp_header("x-world-order", Orders.hash(full))
          |> put_resp_content_type(Map.fetch!(@types, file), nil)
          |> send_resp(200, out)

        {_, {:error, errors}} ->
          json(conn, 422, %{"errors" => errors})
      end
    end)
  end

  post "/builds" do
    with_order(conn, fn job -> builds(conn, job) end)
  end

  get "/builds/:id" do
    case summary(id) do
      nil -> json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such construction"}]})
      state -> json(conn, 200, state)
    end
  end

  # A pause, a resume or a cancel: messages of priority to the construction.
  post "/builds/:id/:act" when act in ["pause", "resume", "cancel"] do
    fun = %{"pause" => &World.pause/1, "resume" => &World.resume/1, "cancel" => &World.cancel/1}[act]

    case fun.(id) do
      :ok -> json(conn, 202, %{"build" => id, "asked" => act})
      {:error, :none} -> json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such construction"}]})
    end
  end

  # A change in a pause: a new order, into the store, for the construction.
  post "/builds/:id/change" do
    with_order(conn, fn body ->
      case Orders.construction(body, origin(conn)) do
        {:ok, job, placed} ->
          changed(conn, id, World.change(id, job), placed)

        {:error, :store} ->
          json(conn, 503, %{"errors" => [%{"path" => "", "message" => "the store of the orders failed"}]})

        {:error, errors} ->
          json(conn, 422, %{"errors" => errors})
      end
    end)
  end

  get "/builds/:id/events" do
    conn = conn |> fetch_query_params() |> Stream.open(id)
    Stream.follow(conn, id, after_id(conn), &over?/1)
  end

  get "/builds/:id/elements/:file" do
    with [key, "glb"] <- String.split(file, "."),
         {:ok, glb} <- Construction.element(id, key) do
      conn |> put_resp_content_type("model/gltf-binary", nil) |> send_resp(200, glb)
    else
      _ -> json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such element"}]})
    end
  end

  get "/events" do
    conn = conn |> fetch_query_params() |> Stream.open(:world)
    Stream.follow(conn, :world, after_id(conn))
  end

  get "/census" do
    json(conn, 200, World.census())
  end

  # The places of the yard, for the map of the world page.
  get "/places" do
    json(conn, 200, %{"places" => World.Places.view(), "speed_kmh" => World.Places.data()["speed_kmh"]})
  end

  # The ground of a place with a terrain (plan 0006, D3), made once.
  get "/places/:name/ground.glb" do
    case World.Places.fetch(name) do
      {:ok, %{"terrain" => _} = p} ->
        glb =
          with nil <- :persistent_term.get({World.Places, :ground, name}, nil) do
            glb = World.Build.glb(World.Places.ground(p))
            :persistent_term.put({World.Places, :ground, name}, glb)
            glb
          end

        conn |> put_resp_content_type("model/gltf-binary", nil) |> send_resp(200, glb)

      _ ->
        json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such ground"}]})
    end
  end

  match _ do
    json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such page"}]})
  end

  defp changed(conn, id, :ok, placed),
    do: json(conn, 200, %{"build" => id, "hash" => placed["hash"], "files" => placed["files"]})

  defp changed(conn, _id, {:error, :none}, _),
    do: json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such construction"}]})

  defp changed(conn, _id, {:error, reason}, _) do
    message = %{
      not_paused: "the construction is not in a pause",
      not_a_drawing: "the construction is not a drawing",
      other_nodes: "the drawing has other nodes"
    }

    json(conn, 409, %{"errors" => [%{"path" => "", "message" => message[reason]}]})
  end

  # A job of a request: its order into the store, then a construction.
  defp builds(conn, body) do
    case Orders.construction(body, origin(conn)) do
      {:ok, job, placed} ->
        after_id = World.Log.Server.last()

        if "text/event-stream" in get_req_header(conn, "accept") do
          conn = Stream.open(conn, job.id)
          {:ok, id} = World.build(job)
          Stream.follow(conn, id, after_id, &over?/1)
        else
          {:ok, id} = World.build(job)
          json(conn, 202, Orders.started(id, placed, after_id))
        end

      {:error, :store} ->
        json(conn, 503, %{"errors" => [%{"path" => "", "message" => "the store of the orders failed"}]})

      {:error, errors} ->
        json(conn, 422, %{"errors" => errors})
    end
  end

  # The end of a construction.
  defp over?(e), do: e["kind"] in ~w(done stopped failed)

  # The id after which a stream starts: `Last-Event-ID`, else `?after=N`, else 0.
  defp after_id(conn) do
    text = List.first(get_req_header(conn, "last-event-id")) || conn.query_params["after"] || "0"

    case Integer.parse(text) do
      {n, ""} when n >= 0 -> n
      _ -> 0
    end
  end

  # The state of a construction: its last run in the log of the node.
  defp summary(id) do
    events = for e <- World.Log.Server.history(0), e["order"] == id, do: e

    case Enum.split_while(Enum.reverse(events), &(&1["kind"] != "requested")) do
      {_, []} ->
        nil

      {after_request, [requested | _]} ->
        run = [requested | Enum.reverse(after_request)]
        plan = Enum.find(run, &(&1["kind"] == "plan_made"))
        last = List.last(run)
        over = Enum.find(Enum.reverse(run), &over?/1)

        %{
          "build" => id,
          "status" => status(run, over),
          "level" => (plan || requested)["data"]["level"],
          "tasks" => if(plan, do: length(plan["data"]["tasks"]), else: 0),
          "done" => Enum.count(run, &(&1["kind"] == "task_done")),
          "elements" => for(e <- run, e["kind"] == "element", do: Map.take(e["data"], ~w(task part glb matrix))),
          "last" => last["id"]
        }
    end
  end

  # The state of a construction: the kind of its end, or paused, or building.
  defp status(_run, %{"kind" => kind}), do: kind

  defp status(run, nil) do
    case Enum.find(Enum.reverse(run), &(&1["kind"] in ~w(paused resumed))) do
      %{"kind" => "paused"} -> "paused"
      _ -> "building"
    end
  end

  # One build at a time in the VM: the edge has 128 MB, and two builds of
  # a near level at one time need more. A second build waits for the lock
  # (`:global.trans/4` tries again until it has it).
  defp one_at_a_time(fun), do: :global.trans({__MODULE__, self()}, fun, [node()], :infinity)

  # The start of the URLs of an order: from the Worker, else this server.
  defp origin(conn) do
    case get_req_header(conn, "x-world-origin") do
      [origin | _] -> origin
      [] -> "#{conn.scheme}://#{conn.host}:#{conn.port}"
    end
  end

  # The order of a request: the full order of `hash=HASH` from the store,
  # else the JSON of the body.
  defp with_order(%{query_params: %{"hash" => hash}} = conn, fun) do
    with true <- hash =~ ~r/^[0-9a-f]{32}$/,
         {:ok, json} <- Store.get(hash) do
      fun.(JSON.decode!(json))
    else
      :error -> json(conn, 503, %{"errors" => [%{"path" => "", "message" => "the store of the orders failed"}]})
      _ -> json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such order: send it to POST /orders"}]})
    end
  end

  defp with_order(conn, fun) do
    case read_body(conn, length: 1_000_000) do
      {:ok, body, conn} ->
        case JSON.decode(body) do
          {:ok, order} -> fun.(order)
          {:error, _} -> json(conn, 400, %{"errors" => [%{"path" => "", "message" => "the body is not JSON"}]})
        end

      {:more, _, conn} ->
        json(conn, 413, %{"errors" => [%{"path" => "", "message" => "the body is more than 1 MB"}]})
    end
  end

  defp json(conn, status, body) do
    conn |> put_resp_content_type("application/json", nil) |> send_resp(status, Orders.encode(body))
  end
end
