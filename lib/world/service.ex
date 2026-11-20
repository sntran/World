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
    `{"errors"}`, or 503 when the store failed. The header
    `x-world-started` (the id) marks the answer to the caller that opened
    the construction (`World.open/1`): the Worker gives that caller the
    control key (`docs/factory.md`, "The control key").
  - `GET /builds/ID`: the state of a construction from the log of the
    node: its status, its tasks, the tasks done and its elements (404
    when the log has none).
  - `GET /builds/ID/events`: the stream of a construction until its end,
    after the id of `Last-Event-ID` or of `?after=N`.
  - `GET /builds/ID/elements/KEY.glb`: the GLB of an element (from the
    construction, else from the store of the parts).
  - `GET /p/KEY.glb`: a part of a model by its key (`World.Elements`):
    from the store of the parts, else built from its recipe in the line
    and kept (404 for a key with neither, 422 for a part that needs
    more memory than the VM has). A build that takes more than 45 s goes
    on: the answer is 202 with `retry-after`, and a request after it
    gets the part.
  - `GET /events`: the stream of the whole world, after the id of
    `Last-Event-ID` or of `?after=N`.
  - `GET /census`: the people of the node (`World.census/0`).
  - `GET /sculptures/ID/events`: the stream of the pieces of a live
    sculpture (`World.Sculpt.Web.follow/3`), until the end of the version
    of `?until=V`.
  - `GET /sculptures/ID.glb`: the GLB of the surface of a live sculpture
    now.

  - `GET /o/HASH.glb` (and `.mid.glb`, `.far.glb`, `.parts.json`,
    `.elements.json`, `.mid.elements.json`, `.far.elements.json`,
    `.receipt.json`, `.solids.json`, `.drawing.json`, `.log.json`,
    `.replay.glb`, and
    `.flat.glb`, `.mid.flat.glb`, `.far.flat.glb`, `.light.glb`,
    `.mid.light.glb`, `.far.light.glb`): a file
    of an order of `POST /orders`. `GET /m/BLUEPRINT.glb?OPTION=VALUE`
    (and the other files): a file of an order in the URL
    (`color.ROLE`, `joint.NAME`, `target.LIMB=X,Y,Z`, `OPTION.FIELD`).
    The file comes from the store of the node (`World.Files`), else the
    node builds it in its line (`World.Line`; `?class=batch` or the
    header `x-world-class: batch` for a build that no person waits for)
    and keeps it. A file from an older version of World goes out at
    once, with the header `x-world-stale`, and the node builds it again
    one time. A parts list that takes more than 45 s builds on: 202 with
    `retry-after`, and a request after it gets the file. The answer has an ETag (304 for the same one), and it is
    in gzip for a client that accepts gzip. A file of the flat look
    or of the light look takes `?triangles=N` (the most faces of its
    mesh) and `?wrap=1` (one closed skin round the model).
  - Each other `GET`: a file of the site (the application environment
    `:site`, from `WORLD_SITE`: the folder that `scripts/site.sh`
    makes), with `index.html` for `/`.

  Each answer has the headers of CORS, and `OPTIONS` gives 204.

  A body that is not JSON gives 400. A body of more than 1 MB gives 413.
  The header `x-world-origin` (from the Worker) is the start of the URLs
  of an order: `https://world.mkfifo.com`.
  """
  use Plug.Router

  alias World.{Construction, Files, Line, MCP, Orders, Stream}
  alias World.Orders.{Blueprint, Blueprints, Set, Store}

  plug(:cors)
  plug(:match)
  plug(:dispatch)

  # The suffix of each file of an order: its level and its file.
  @suffixes [
    {".mid.flat.glb", "mid", "flat"},
    {".far.flat.glb", "far", "flat"},
    {".flat.glb", "near", "flat"},
    {".mid.light.glb", "mid", "light"},
    {".far.light.glb", "far", "light"},
    {".light.glb", "near", "light"},
    {".mid.elements.json", "mid", "elements"},
    {".far.elements.json", "far", "elements"},
    {".elements.json", "near", "elements"},
    {".mid.glb", "mid", "glb"},
    {".far.glb", "far", "glb"},
    {".parts.json", "near", "parts"},
    {".receipt.json", "near", "receipt"},
    {".solids.json", "near", "solids"},
    {".drawing.json", "near", "drawing"},
    {".log.json", "near", "log"},
    {".replay.glb", "near", "replay"},
    {".glb", "near", "glb"}
  ]
  @cache "public, max-age=300, stale-while-revalidate=86400"

  @types %{
    "glb" => "model/gltf-binary",
    "replay" => "model/gltf-binary",
    "log" => "application/json",
    "parts" => "application/json",
    "elements" => "application/json",
    "receipt" => "application/json",
    "solids" => "application/json",
    "drawing" => "application/json",
    "flat" => "model/gltf-binary",
    "light" => "model/gltf-binary"
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

  # The heights of the real Earth at the points of a project (World.Earth).
  post "/earth/heights" do
    with_order(conn, fn body ->
      case World.Earth.heights(is_map(body) && body["points"]) do
        {:ok, heights} -> json(conn, 200, %{"heights" => heights, "unit" => "m", "source" => World.Earth.source()})
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

  post "/orders/:hash/edits" do
    with_order(conn, fn body ->
      case Orders.Edits.place(hash, is_map(body) && body["edits"], origin(conn)) do
        {:ok, placed} ->
          json(conn, 200, placed)

        {:error, :store} ->
          json(conn, 503, %{"errors" => [%{"path" => "", "message" => "the store of the orders failed"}]})

        {:error, [%{"path" => "order"} | _] = errors} ->
          json(conn, 404, %{"errors" => errors})

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
      case build(conn, order, level, file) do
        :building ->
          conn |> put_resp_header("retry-after", "15") |> json(202, %{"building" => file})

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

  # The build of a file of POST /build in the line, with its time. A parts
  # list builds in the background (`World.Elements.background/3`): a large
  # model at near takes more than the 60 s of a request at the edge.
  # (Its file goes into the files of the node: the request after a 202 gets it there.)
  defp build(_conn, order, level, "elements") do
    hash = with {:ok, full} <- Orders.check(order), do: Orders.hash(full), else: (_ -> nil)

    keep = fn ->
      result = timed(:now, order, level, "elements")
      with {_, {:ok, body}} when hash != nil <- result, do: Files.put(hash, level, "elements", body)
      result
    end

    with {:ok, entry} <- Files.get(hash, level, "elements"),
         true <- Files.fresh?(entry) do
      {0, {:ok, entry.body}}
    else
      _ ->
        case World.Elements.background({:file, hash, level}, keep) do
          {:ok, result} -> result
          :building -> :building
          :gone -> {0, listed(hash, level)}
        end
    end
  end

  defp build(conn, order, level, file), do: timed(class(conn), order, level, file)

  # The parts list after another build of it, which ended before it got
  # the message: in the files, else the error of a build that stopped.
  defp listed(hash, level) do
    case Files.get(hash, level, "elements") do
      {:ok, entry} -> {:ok, entry.body}
      :error -> {:error, World.Elements.stopped()}
    end
  end

  defp timed(class, order, level, file),
    do: Line.run(class, fn -> :timer.tc(Orders, :build, [order, level, file], :millisecond) end)

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
         {:ok, glb} <- element(id, key) do
      conn |> put_resp_content_type("model/gltf-binary", nil) |> send_resp(200, glb)
    else
      _ -> json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such element"}]})
    end
  end

  get "/events" do
    conn = conn |> fetch_query_params() |> Stream.open(:world)
    Stream.follow(conn, :world, after_id(conn))
  end

  get "/sculptures/:id/events" do
    conn = fetch_query_params(conn)

    until =
      case Integer.parse(conn.query_params["until"] || "") do
        {n, ""} when n >= 0 -> n
        _ -> nil
      end

    World.Sculpt.Web.follow(conn, id, until)
  end

  get "/sculptures/:file" do
    with [id, "glb"] <- String.split(file, ".", parts: 2),
         {:ok, glb} <- World.Sculpt.Web.glb(id) do
      conn |> put_resp_content_type("model/gltf-binary", nil) |> send_resp(200, glb)
    else
      _ -> json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such live sculpture"}]})
    end
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

  get "/o/:name" do
    with {hash, level, file} <- split(name),
         true <- hash =~ ~r/^[0-9a-f]{32}$/,
         {:ok, order} <- Store.get(hash) do
      serve(conn, JSON.decode!(order), level, file)
    else
      :error -> json(conn, 503, %{"errors" => [%{"path" => "", "message" => "the store of the orders failed"}]})
      _ -> json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such file"}]})
    end
  end

  # A part of a model by its key (`World.Elements`): from the store, else
  # built from its recipe in the line, and kept. The key is a hash of its
  # data: the file does not change. The Worker gives the header
  # x-world-project for a request with a project token; the answer has
  # x-world-shift: wanted when the edge needs a construction shift
  # (`World.Shift.wanted?/1`), and the Worker starts one.
  # A construction shift joins (`World.Shift.Passes`): the Worker checked
  # the ID token of its job, and gives its run in x-world-shift-run. The
  # answer: the name of its node, the cookie of that node, the pass of
  # the store, and the name of the node of the edge.
  post "/shift/join" do
    with [run] <- get_req_header(conn, "x-world-shift-run"),
         {:ok, answer} <- World.Shift.Passes.join(run) do
      json(conn, 200, answer)
    else
      [] ->
        json(conn, 403, %{"errors" => [%{"path" => "", "message" => "no shift"}]})

      {:error, :no_shifts} ->
        json(conn, 403, %{"errors" => [%{"path" => "", "message" => "no shifts on this VM"}]})

      {:error, :no_distribution} ->
        json(conn, 503, %{"errors" => [%{"path" => "", "message" => "the edge is not a node yet"}]})
    end
  end

  # The check of the Worker for /store/KEY with a pass: 204 when the
  # shift of the pass can read (or write) the key, else 403.
  get "/shift/allowed" do
    conn = fetch_query_params(conn)
    access = if conn.query_params["access"] == "write", do: :write, else: :read

    case get_req_header(conn, "x-world-shift-pass") do
      [pass] ->
        if World.Shift.Passes.allowed?(pass, conn.query_params["key"] || "", access),
          do: send_resp(conn, 204, ""),
          else: send_resp(conn, 403, "")

      _ ->
        send_resp(conn, 403, "")
    end
  end

  get "/p/:file" do
    project = get_req_header(conn, "x-world-project") != []
    # (A part that needs a shift when no shift takes parts: the answer comes at once, with
    # the mark, so that the Worker starts the shift now, not after the wait.)
    first = project and World.Labour.needs_shift?(file |> String.split(".") |> hd()) and World.Shift.wanted?(waiting: 1)
    conn = if first, do: put_resp_header(conn, "x-world-shift", "wanted"), else: conn
    wait = if first, do: 0, else: World.Elements.wait()

    with [key, "glb"] <- String.split(file, "."),
         true <- key =~ ~r/^[0-9a-f]{32}$/,
         {:ok, glb} <- part_of(conn, key, World.Elements.fetch(key, wait, project)) do
      conn
      |> put_resp_header("etag", ~s("#{key}"))
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> put_resp_content_type("model/gltf-binary", nil)
      |> send_resp(200, glb)
    else
      # (A node of a shift put the part in the store: the Worker reads it from R2, with no VM.)
      :stored -> send_resp(conn, 204, "")
      :building -> conn |> shift() |> put_resp_header("retry-after", "15") |> json(202, %{"building" => file})
      {:error, errors} -> json(conn, 422, %{"errors" => errors})
      _ -> json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such part"}]})
    end
  end

  # The mark of a construction shift that the edge needs, for the Worker.
  defp shift(conn), do: if(World.Shift.wanted?(), do: put_resp_header(conn, "x-world-shift", "wanted"), else: conn)

  # A part that another node put in the store: the Worker in front of the
  # VM (its header x-world-origin) reads it from R2; a server with no
  # Worker reads it from its store.
  defp part_of(conn, key, :stored) do
    if get_req_header(conn, "x-world-origin") == [],
      do: with(:none <- World.Elements.Store.get(key), do: :stored),
      else: :stored
  end

  defp part_of(_conn, _key, result), do: result

  get "/m/:name" do
    case split(name) do
      {blueprint, level, file} -> serve(conn, order_of(blueprint, conn.query_string), level, file)
      nil -> json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such file"}]})
    end
  end

  match _ do
    case site_file(conn) do
      nil ->
        json(conn, 404, %{"errors" => [%{"path" => "", "message" => "no such page"}]})

      path ->
        conn
        |> put_resp_content_type(MIME.from_path(path), nil)
        |> put_resp_header("cache-control", @cache)
        |> send_file(200, path)
    end
  end

  # The headers of CORS on each answer, and 204 for OPTIONS.
  defp cors(conn, _opts) do
    conn =
      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
      |> put_resp_header(
        "access-control-allow-headers",
        "content-type, accept, mcp-protocol-version, mcp-session-id, last-event-id"
      )

    if conn.method == "OPTIONS",
      do: conn |> put_resp_header("access-control-max-age", "86400") |> send_resp(204, "") |> halt(),
      else: conn
  end

  # The name, the level and the file of a path: "ford.mid.glb" is {"ford", "mid", "glb"}.
  defp split(name) do
    Enum.find_value(@suffixes, fn {suffix, level, file} ->
      if String.ends_with?(name, suffix) and byte_size(name) > byte_size(suffix),
        do: {binary_part(name, 0, byte_size(name) - byte_size(suffix)), level, file}
    end)
  end

  # The order of a URL /m/BLUEPRINT.EXT?...: `color.ROLE`, `joint.NAME` and
  # `target.LIMB` (a point X,Y,Z), and the options. `OPTION.FIELD` is a
  # field of an option that is an object (`origin.asian=1`).
  defp order_of(blueprint, query) do
    Enum.reduce(URI.query_decoder(query), %{"blueprint" => blueprint, "options" => %{}}, fn
      {"color." <> role, value}, order ->
        put_in(order, [Access.key("colors", %{}), role], value)

      {"joint." <> name, value}, order ->
        put_in(order, [Access.key("joints", %{}), name], number(value))

      {"target." <> limb, value}, order ->
        put_in(order, [Access.key("targets", %{}), limb], Enum.map(String.split(value, ","), &number/1))

      {key, _}, order when key in ["class", "triangles", "wrap"] ->
        order

      {key, value}, order ->
        case String.split(key, ".", parts: 2) do
          [option, field] ->
            update_in(order, ["options", option], &Map.put(if(is_map(&1), do: &1, else: %{}), field, value))

          [option] ->
            put_in(order, ["options", option], value)
        end
    end)
  end

  # A whole number of a URL, or the text when it is not one (the build gives the error).
  defp whole(text) do
    case Integer.parse(text) do
      {n, ""} -> n
      _ -> text
    end
  end

  # A number of a URL, or the text when it is not a number (the check of the order gives the error).
  defp number(text) do
    case Float.parse(text) do
      {n, ""} -> n
      _ -> text
    end
  end

  # A file of an order: from the store of the node, else the node builds
  # it in its line and keeps it. A file of an older version of World goes
  # out at once, and the node builds it again one time.
  defp serve(conn, order, level, kind) do
    # (The flat or the light look with a budget of triangles or a wrap is a file of its own in the store.)
    conn = fetch_query_params(conn)
    small? = kind in ["flat", "light"]
    count = if small?, do: conn.query_params["triangles"]
    wrap? = small? and conn.query_params["wrap"] in ["1", "true"]
    opts = if(count, do: [triangles: whole(count)], else: []) ++ if(wrap?, do: [wrap: true], else: [])
    file = Enum.join([kind] ++ if(count, do: [count], else: []) ++ if(wrap?, do: ["wrap"], else: []), ".")

    case Orders.check(order) do
      {:error, errors} ->
        json(conn, 422, %{"errors" => errors})

      {:ok, full} ->
        hash = Orders.hash(full)

        case Files.get(hash, level, file) do
          {:ok, entry} ->
            fresh? = Files.fresh?(entry)
            unless fresh?, do: refresh(full, hash, level, file, kind, opts)
            send_entry(conn, entry, hash, kind, not fresh?)

          :error when kind == "elements" ->
            # (The parts list of a large model can take more than the 60 s of
            # a request at the edge: its build goes on, and keeps its file.)
            build = fn ->
              Line.run(:now, fn ->
                with {:ok, body} <- Orders.build(full, level, kind, opts), do: {:ok, Files.put(hash, level, file, body)}
              end)
            end

            case World.Elements.background({:file, hash, level, file}, build) do
              {:ok, {:ok, entry}} -> send_entry(conn, entry, hash, kind, false)
              {:ok, {:error, errors}} -> json(conn, 422, %{"errors" => errors})
              :building -> conn |> put_resp_header("retry-after", "15") |> json(202, %{"building" => file})
              :gone -> json(conn, 500, %{"errors" => World.Elements.stopped()})
            end

          :error ->
            case Line.run(class(conn), fn -> Orders.build(full, level, kind, opts) end) do
              {:ok, body} -> send_entry(conn, Files.put(hash, level, file, body), hash, kind, false)
              {:error, errors} -> json(conn, 422, %{"errors" => errors})
            end
        end
    end
  end

  # A new build of a stale file, in a process of its own; one for a file at one time.
  defp refresh(full, hash, level, file, kind, opts) do
    spawn(fn ->
      with {:ok, _} <- Registry.register(World.Names, {:refresh, hash, level, file}, nil),
           {:ok, body} <- Line.run(:batch, fn -> Orders.build(full, level, kind, opts) end) do
        Files.put(hash, level, file, body)
      end
    end)
  end

  defp send_entry(conn, entry, hash, file, stale?) do
    conn =
      conn
      |> put_resp_header("etag", entry.etag)
      |> put_resp_header("cache-control", @cache)
      |> put_resp_header("vary", "accept-encoding")
      |> put_resp_header("x-world-order", hash)
      |> put_resp_header("x-world-version", entry.version)

    conn = if stale?, do: put_resp_header(conn, "x-world-stale", "true"), else: conn
    gzip? = Enum.any?(get_req_header(conn, "accept-encoding"), &String.contains?(&1, "gzip"))

    cond do
      entry.etag in get_req_header(conn, "if-none-match") ->
        send_resp(conn, 304, "")

      gzip? ->
        conn
        |> put_resp_content_type(Map.fetch!(@types, file), nil)
        |> put_resp_header("content-encoding", "gzip")
        |> send_resp(200, entry.gzip)

      true ->
        conn |> put_resp_content_type(Map.fetch!(@types, file), nil) |> send_resp(200, entry.body)
    end
  end

  # The class of the build of a request in the line: `batch` when the request says so.
  defp class(conn) do
    conn = fetch_query_params(conn)

    if conn.query_params["class"] == "batch" or get_req_header(conn, "x-world-class") == ["batch"],
      do: :batch,
      else: :now
  end

  # The file of the site for a GET, when the node has a site and the file is in it.
  defp site_file(%{method: "GET", path_info: info}) do
    with dir when is_binary(dir) <- Application.get_env(:world, :site),
         true <- Enum.all?(info, &(&1 =~ ~r/\A[A-Za-z0-9_][A-Za-z0-9_.-]*\z/)),
         path = Path.join([dir | if(info == [], do: ["index.html"], else: info)]),
         true <- File.regular?(path) do
      path
    else
      _ -> nil
    end
  end

  defp site_file(_conn), do: nil

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

        # (The stream reads the log after `after_id`: the events from the
        # start of the construction to the open of the stream come too.)
        {who, id} = World.open(job)
        conn = if who == :new, do: put_resp_header(conn, "x-world-started", id), else: conn

        if "text/event-stream" in get_req_header(conn, "accept") do
          conn |> Stream.open(id) |> Stream.follow(id, after_id, &over?/1)
        else
          json(conn, 202, Orders.started(id, placed, after_id))
        end

      {:error, :store} ->
        json(conn, 503, %{"errors" => [%{"path" => "", "message" => "the store of the orders failed"}]})

      {:error, errors} ->
        json(conn, 422, %{"errors" => errors})
    end
  end

  # The GLB of an element of a construction: from the construction while
  # it keeps its elements, else from the store of the parts (W28: the key
  # of an element is the key of its part).
  defp element(id, key) do
    case Construction.element(id, key) do
      {:ok, glb} -> {:ok, glb}
      :none -> if key =~ ~r/^[0-9a-f]{32}$/, do: World.Elements.Store.get(key), else: :none
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
