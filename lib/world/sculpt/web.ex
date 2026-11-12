defmodule World.Sculpt.Web do
  @moduledoc """
  A live sculpture over MCP and HTTP (`docs/plans/0008-model-from-edits.md`,
  step 6; `World.Sculpt.Live`): the tools `open_sculpture`,
  `edit_sculpture` and `close_sculpture` of `World.MCP`, the stream of
  the pieces of a sculpture (`GET /sculptures/ID/events`, server-sent
  events), and the GLB of its surface now (`GET /sculptures/ID.glb`).

  The edits are the edits of the skill `sculpt` (`docs/format.md`, "A
  sculpture"), each error with its path. The id of a sculpture is its
  `name`, or the hash of its first edits and its level: the same edits
  open the same sculpture. The node has at most 8 live sculptures at one
  time (`:world, World.Sculpt.Web, most:`), for the memory of the edge.
  """
  import Plug.Conn

  alias World.{Mesh, Orders, Part}
  alias World.Skills.Sculpt, as: Skill
  alias World.Sculpt.Live

  @levels ~w(near mid far)

  @doc """
  Open a live sculpture: the arguments `edits`, `level` (`near` by
  default) and `name`. `{:ok, data}` with its id, its version and the
  URLs of its events and of its GLB (after `origin`), or `{:error,
  errors}`.
  """
  def open(args, origin) do
    level = Map.get(args, "level", "near")
    name = args["name"]

    errors =
      Skill.check(%{"edits" => args["edits"]}, "") ++
        if(level in @levels, do: [], else: [{".level", "must be one of: near, mid, far"}]) ++
        if(name == nil or (is_binary(name) and name =~ ~r/^[a-z0-9_-]{1,64}$/),
          do: [],
          else: [{".name", "must be a name of 1 to 64 letters a-z, digits, _ or -"}]
        )

    if errors == [] do
      id = name || Orders.hash(%{"edits" => args["edits"], "level" => level})
      start(id, Skill.edits(args["edits"]), String.to_existing_atom(level), origin)
    else
      {:error, paths(errors)}
    end
  end

  defp start(id, edits, level, origin) do
    case Live.info(id) do
      %{version: v} ->
        {:ok, view(id, v, origin)}

      {:error, :none} ->
        if DynamicSupervisor.count_children(World.Sculptures).active >= most() do
          {:error, [%{"path" => "", "message" => "the node has #{most()} live sculptures; close one first"}]}
        else
          {:ok, _} = Live.start(id, edits, level: level)
          {:ok, view(id, 0, origin)}
        end
    end
  end

  defp most, do: Application.get_env(:world, __MODULE__, []) |> Keyword.get(:most, 8)

  defp view(id, version, origin) do
    %{
      "sculpture" => id,
      "version" => version,
      "events" => "#{origin}/sculptures/#{id}/events",
      "glb" => "#{origin}/sculptures/#{id}.glb"
    }
  end

  @doc """
  Change one edit of a live sculpture: the arguments `sculpture`,
  `index` and `edit` (null takes the edit away; the index of the count
  of the edits adds one at the end). `{:ok, %{"sculpture", "version"}}`,
  or `{:error, errors}`.
  """
  def edit(%{"sculpture" => id, "index" => i} = args) when is_binary(id) and is_integer(i) do
    edit = args["edit"]
    errors = if edit == nil, do: [], else: Skill.check(%{"edits" => [edit]}, "") |> Enum.map(&at_edit/1)

    with [] <- errors,
         {:ok, v} <- Live.edit(id, i, edit && hd(Skill.edits([edit]))) do
      {:ok, %{"sculpture" => id, "version" => v}}
    else
      {:error, :index} ->
        {:error, [%{"path" => "index", "message" => "must be an index of an edit, or the count of the edits"}]}

      {:error, :none} ->
        {:error, [%{"path" => "sculpture", "message" => "no such live sculpture"}]}

      errors ->
        {:error, paths(errors)}
    end
  end

  def edit(_args),
    do:
      {:error,
       [%{"path" => "", "message" => ~s<the arguments are "sculpture" (a text), "index" (an integer) and "edit">}]}

  # An error of the edit in a list of one: its path from `edit`.
  defp at_edit({".edits.0" <> rest, message}), do: {".edit" <> rest, message}

  @doc "Close a live sculpture: `:ok`, or `{:error, errors}`."
  def close(%{"sculpture" => id}) do
    case Live.stop(id) do
      :ok -> :ok
      {:error, :none} -> {:error, [%{"path" => "sculpture", "message" => "no such live sculpture"}]}
    end
  end

  defp paths(errors), do: for({"." <> path, message} <- errors, do: %{"path" => path, "message" => message})

  @doc "The GLB of the surface of a live sculpture now, or `:error`."
  def glb(id) do
    case Live.meshes(id) do
      {:error, :none} -> :error
      meshes -> {:ok, World.Build.glb(Part.new(id, :part, meshes, []))}
    end
  end

  @doc """
  The stream of a live sculpture, as server-sent events: a `piece` for
  each brick that it has now, then `state` (its version, and if a work
  is in progress), then each event as it comes (`piece`, `gone`, `done`,
  `failed`), and `closed` when the sculpture stops. With `until` (a
  version), the stream ends after the `done` (or `failed`) of that
  version. A comment each 15 s (`:ping` of `World.Stream`) keeps the
  connection open. 404 when there is no such sculpture.
  """
  def follow(conn, id, until) do
    Live.watch(id)

    with [{pid, _}] <- Registry.lookup(World.Names, {:sculpture, id}),
         %{version: v, busy: busy} <- Live.info(id),
         pieces when is_list(pieces) <- Live.pieces(id) do
      ref = Process.monitor(pid)

      conn =
        conn
        |> put_resp_header("content-type", "text/event-stream")
        |> put_resp_header("cache-control", "no-cache")
        |> send_chunked(200)

      now = for({at, piece} <- pieces, do: piece(at, piece)) ++ [%{"kind" => "state", "version" => v, "busy" => busy}]
      over = until != nil and not busy and v >= until
      send_all(conn, now, fn conn -> if over, do: conn, else: run(conn, id, ref, until) end)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json", nil)
        |> send_resp(404, Orders.encode(%{"errors" => [%{"path" => "", "message" => "no such live sculpture"}]}))
    end
  end

  defp send_all(conn, [], next), do: next.(conn)

  defp send_all(conn, [e | rest], next) do
    case chunk(conn, frame(e)) do
      {:ok, conn} -> send_all(conn, rest, next)
      {:error, _} -> conn
    end
  end

  defp run(conn, id, ref, until) do
    receive do
      {:sculpture, ^id, event} ->
        e = json(event)
        last = until != nil and e["kind"] in ~w(done failed) and e["version"] >= until
        send_all(conn, [e], fn conn -> if last, do: conn, else: run(conn, id, ref, until) end)

      {:DOWN, ^ref, :process, _, _} ->
        send_all(conn, [%{"kind" => "closed"}], & &1)
    after
      ping() ->
        case chunk(conn, ": ping\n\n") do
          {:ok, conn} -> run(conn, id, ref, until)
          {:error, _} -> conn
        end
    end
  end

  defp ping, do: Keyword.get(Application.get_env(:world, World.Stream, []), :ping, 15_000)

  defp frame(e), do: "data: #{JSON.encode!(e)}\n\n"

  @doc "An event of a live sculpture as JSON."
  def json({:piece, at, piece}), do: piece(at, piece)
  def json({:gone, at}), do: %{"kind" => "gone", "at" => Tuple.to_list(at)}
  def json({:done, v}), do: %{"kind" => "done", "version" => v}
  def json({:failed, v, reason}), do: %{"kind" => "failed", "version" => v, "reason" => inspect(reason)}

  # A piece as JSON: the brick, and the mesh of each material.
  defp piece(at, piece) do
    meshes =
      for %Mesh{} = m <- World.Sculpt.Surface.meshes([piece]) do
        %{
          "material" => Atom.to_string(m.material),
          "points" => for({x, y, z} <- m.points, do: [round5(x), round5(y), round5(z)]),
          "faces" => m.faces
        }
      end

    %{"kind" => "piece", "at" => Tuple.to_list(at), "meshes" => meshes}
  end

  defp round5(x), do: Float.round(x / 1, 5)
end
