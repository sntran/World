defmodule World.MCP do
  @moduledoc """
  The MCP server of the factory (`POST /mcp` of `World.Service`,
  `docs/factory.md`, "The MCP server"): an MCP client of another project
  finds the blueprints, checks an order and places it, with the tools of
  the Model Context Protocol.

  The transport is the Streamable HTTP of MCP, with no state: each POST
  is one JSON-RPC message, and the answer is one JSON message (no event
  stream and no session). A notification or a response from the client
  gets 202 with no body.
  """
  alias World.Orders
  alias World.Orders.{Blueprint, Blueprints}

  @doc "The versions of the protocol that this server knows, the newest first."
  def versions, do: ~w(2025-11-25 2025-06-18 2025-03-26 2024-11-05)

  @instructions """
  World is a factory of 3D models (GLB). An order is JSON data: a blueprint and its options, colors and joints.
  1. Call list_blueprints, then get_blueprint for the options of one blueprint.
  2. Call check_order with the order until it has no errors. Each error has the path of the wrong value and the rule.
  3. Call place_order. The answer has the hash of the order and the URLs of its files: the GLB at the near, mid and far levels, the list of the parts, the receipt, and the log of the people of the world that built it.
  The factory builds each file at its first GET (this can take some seconds; 503 means that the order needs more memory than the edge has), and keeps it. The same order always gives the same hash and the same URLs.
  To watch the people build a model: call plan_build for the tasks, the trades and the triangles of an order at a level, then build with a budget. The answer has the URL of the stream of the events of the construction (server-sent events), and each element as it comes.
  A new model for the catalog (an engineer): get_blueprint drawing gives the format of a drawing (its shapes, their materials and matter, standard parts, nodes and joints). Call check_drawing until the drawing has no errors and passes the checks of a true model (it stands, no two parts in one place, the joints in their limits, it goes through the door of its workshop, each part has a mass). Then call propose_drawing with the request: the owner reviews the proposal, and accepts or refuses it.
  """

  # The schema of an order (docs/factory.md, "The URLs").
  @order %{
    "type" => "object",
    "description" =>
      ~s(An order: {"blueprint": NAME, "options": {...}, "colors": {ROLE: "#rrggbb"}, "joints": {NAME: DEGREES}, "targets": {LIMB: [X, Y, Z]}}. Only "blueprint" is necessary: each option that the order does not give has its default.),
    "properties" => %{
      "blueprint" => %{"type" => "string", "description" => "The name of a blueprint (list_blueprints)."},
      "options" => %{
        "type" => "object",
        "description" => "The options of the blueprint (get_blueprint), by their names."
      },
      "colors" => %{"type" => "object", "description" => ~s(A color for each material role, as "#rrggbb".)},
      "joints" => %{"type" => "object", "description" => "The angle of each joint, in degrees."},
      "targets" => %{"type" => "object", "description" => "The end of each limb, as a point [x, y, z] in meters."}
    },
    "required" => ["blueprint"]
  }

  @read %{"readOnlyHint" => true, "openWorldHint" => false}

  @level %{"type" => "string", "enum" => ~w(near mid far), "description" => "The level of detail: near by default."}

  @budget %{
    "type" => "object",
    "description" =>
      "The budget of the construction: workers (the most people at one time, 1 to 64, 4 by default), seconds (the deadline; no model after it), triangles (the most triangles: the most detailed level that fits)."
  }

  @drawing %{
    "type" => "object",
    "description" =>
      "A drawing (docs/format.md, \"A drawing\"): name, kind, materials, parts (shapes or a standard part), nodes, clips, sources."
  }

  @tools [
    %{
      "name" => "list_blueprints",
      "title" => "List the blueprints",
      "description" =>
        "Gives the name and the description of each blueprint of the factory. A blueprint is a family of models with options (van, person, house, animal, catalog, drawing, and more).",
      "inputSchema" => %{"type" => "object", "properties" => %{}},
      "annotations" => @read
    },
    %{
      "name" => "get_blueprint",
      "title" => "Get a blueprint",
      "description" =>
        "Gives the options of one blueprint: for each option, its type, default, unit, range, values or presets, and its description.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string", "description" => "The name of the blueprint."}},
        "required" => ["name"]
      },
      "annotations" => @read
    },
    %{
      "name" => "check_order",
      "title" => "Check an order",
      "description" =>
        "Checks an order and does not keep it. Gives the hash and the full order (with each default), or the errors: each error has the path of the wrong value and the rule.",
      "inputSchema" => %{"type" => "object", "properties" => %{"order" => @order}, "required" => ["order"]},
      "annotations" => @read
    },
    %{
      "name" => "place_order",
      "title" => "Place an order",
      "description" =>
        "Checks an order and keeps it. Gives the hash, the full order, the URLs of its files (GLB at the near, mid and far levels, parts, receipt, log, replay GLB) and the URL of its replay page; or the errors. The factory builds each file at its first GET. The same order gives the same hash.",
      "inputSchema" => %{"type" => "object", "properties" => %{"order" => @order}, "required" => ["order"]},
      "annotations" => %{
        "readOnlyHint" => false,
        "destructiveHint" => false,
        "idempotentHint" => true,
        "openWorldHint" => false
      }
    },
    %{
      "name" => "check_drawing",
      "title" => "Check a new drawing",
      "description" =>
        "Checks a drawing of a new model and does not keep it: the errors of the data (each with its path), then the checks of a true model (it stands, no two parts in one place, the joints in their limits, it goes through the door of its workshop), its mass (and the parts with no mass), its size and its parts.",
      "inputSchema" => %{"type" => "object", "properties" => %{"drawing" => @drawing}, "required" => ["drawing"]},
      "annotations" => @read
    },
    %{
      "name" => "plan_build",
      "title" => "Plan a build",
      "description" =>
        "Gives the plan of the people for an order at a level, with no build: each task with its trade and the tasks that it waits for, the count of the tasks of each trade, and the estimate of the triangles of the model. A node of a drawing that a skill makes is one task.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"order" => @order, "level" => @level},
        "required" => ["order"]
      },
      "annotations" => @read
    },
    %{
      "name" => "build",
      "title" => "Build an order",
      "description" =>
        "Keeps an order and starts its construction: the people of the node build it element by element, in its budget. Gives the id of the build, the hash of the order, the URL of the stream of its events (server-sent events: plan_made, hired, task_started, element, done, stopped), and the URLs of its files; or the errors.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"order" => @order, "level" => @level, "budget" => @budget},
        "required" => ["order"]
      },
      "annotations" => %{
        "readOnlyHint" => false,
        "destructiveHint" => false,
        "idempotentHint" => true,
        "openWorldHint" => false
      }
    },
    %{
      "name" => "propose_drawing",
      "title" => "Propose a new drawing",
      "description" =>
        "Checks a drawing as check_drawing does and, when it passes, keeps it as a proposal for the owner, with the request that it answers. Gives the hash of the proposal and its review. The owner accepts or refuses it: a proposal is not in the catalog before the owner accepts it.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "drawing" => @drawing,
          "request" => %{"type" => "string", "description" => "The request that the drawing answers, in words."}
        },
        "required" => ["drawing", "request"]
      },
      "annotations" => %{
        "readOnlyHint" => false,
        "destructiveHint" => false,
        "idempotentHint" => true,
        "openWorldHint" => false
      }
    }
  ]

  @doc "The tools of the server."
  def tools, do: @tools

  @doc """
  The answer to the body of a POST: `{status, message}`, or `{202, nil}`
  for a notification or a response of the client. `version` is the
  header `mcp-protocol-version` (nil when the request has none), and
  `origin` the start of the URLs of `place_order`.
  """
  def answer(body, version, origin) do
    with :ok <- version(version),
         {:ok, message} <- decode(body) do
      if Map.has_key?(message, "id") and is_binary(message["method"]) do
        {200, Map.merge(%{"jsonrpc" => "2.0", "id" => message["id"]}, reply(message, origin))}
      else
        {202, nil}
      end
    end
  end

  defp version(nil), do: :ok

  defp version(v) do
    if v in versions(),
      do: :ok,
      else: {400, failure(-32600, "the protocol version #{v} is not known; use one of #{Enum.join(versions(), ", ")}")}
  end

  defp decode(body) do
    case JSON.decode(body) do
      {:ok, %{"jsonrpc" => "2.0"} = message} -> {:ok, message}
      {:ok, _} -> {400, failure(-32600, "the body is not one JSON-RPC 2.0 message")}
      {:error, _} -> {400, failure(-32700, "the body is not JSON")}
    end
  end

  defp failure(code, message),
    do: %{"jsonrpc" => "2.0", "id" => nil, "error" => %{"code" => code, "message" => message}}

  defp error(code, message), do: %{"error" => %{"code" => code, "message" => message}}

  defp reply(%{"method" => "initialize"} = message, _origin) do
    asked = object(message["params"])["protocolVersion"]

    %{
      "result" => %{
        "protocolVersion" => if(asked in versions(), do: asked, else: hd(versions())),
        "capabilities" => %{"tools" => %{"listChanged" => false}},
        "serverInfo" => %{"name" => "world", "title" => "World, the factory of 3D models", "version" => version()},
        "instructions" => @instructions
      }
    }
  end

  defp reply(%{"method" => "ping"}, _origin), do: %{"result" => %{}}
  defp reply(%{"method" => "tools/list"}, _origin), do: %{"result" => %{"tools" => @tools}}

  defp reply(%{"method" => "tools/call"} = message, origin) do
    params = object(message["params"])
    name = params["name"]
    names = Enum.map(@tools, & &1["name"])

    if name in names,
      do: %{"result" => call(name, object(params["arguments"]), origin)},
      else: error(-32602, "no tool #{name}; the tools are #{Enum.join(names, ", ")}")
  end

  defp reply(%{"method" => method}, _origin), do: error(-32601, "no method #{method}")

  defp object(%{} = map), do: map
  defp object(_), do: %{}

  defp call("list_blueprints", _args, _origin),
    do: result(%{"blueprints" => Enum.map(Blueprints.all(), &%{"name" => &1.name, "doc" => &1.doc})})

  defp call("get_blueprint", args, _origin) do
    case Blueprints.fetch(args["name"]) do
      {:ok, b} ->
        result(Blueprint.describe(b))

      :error ->
        wrong("no blueprint #{args["name"]}; the blueprints are #{Enum.map_join(Blueprints.all(), ", ", & &1.name)}")
    end
  end

  defp call("check_drawing", %{"drawing" => drawing}, _origin) do
    case World.Engineers.review(drawing) do
      {:ok, review} -> result(review)
      {:error, review} -> result(review, true)
    end
  end

  defp call("propose_drawing", %{"drawing" => drawing} = args, _origin) do
    case World.Engineers.propose(drawing, args["request"]) do
      {:ok, data} -> result(data)
      {:error, :store} -> wrong("the store of the proposals failed; try again later")
      {:error, review} -> result(review, true)
    end
  end

  defp call("plan_build", %{"order" => order} = args, _origin) when is_map(order) do
    case Orders.plan(order, Map.get(args, "level", "near")) do
      {:ok, data} -> result(data)
      {:error, errors} -> result(%{"errors" => errors}, true)
    end
  end

  defp call("build", %{"order" => order} = args, origin) when is_map(order) do
    case Orders.construction(args, origin) do
      {:ok, job, placed} ->
        after_id = World.Log.Server.last()
        {:ok, id} = World.build(job)
        result(Orders.started(id, placed, after_id))

      {:error, :store} ->
        wrong("the store of the orders failed; try again later")

      {:error, errors} ->
        result(%{"errors" => errors}, true)
    end
  end

  defp call(tool, _args, _origin) when tool in ~w(check_drawing propose_drawing),
    do: wrong(~s(the argument "drawing" must be a JSON object))

  defp call(tool, %{"order" => order}, origin) when is_map(order) do
    case if(tool == "check_order", do: check(order), else: Orders.place(order, origin)) do
      {:ok, data} -> result(data)
      {:error, :store} -> wrong("the store of the orders failed; try again later")
      {:error, errors} -> result(%{"errors" => errors}, true)
    end
  end

  defp call(_tool, _args, _origin), do: wrong(~s(the argument "order" must be a JSON object))

  defp check(order) do
    with {:ok, full} <- Orders.check(order), do: {:ok, %{"hash" => Orders.hash(full), "order" => full}}
  end

  # A tool result: the data as JSON text, and as structured content.
  defp result(data, error? \\ false) do
    r = %{"content" => [%{"type" => "text", "text" => Orders.encode(data)}], "structuredContent" => data}
    if error?, do: Map.put(r, "isError", true), else: r
  end

  defp wrong(message), do: result(%{"errors" => [%{"path" => "", "message" => message}]}, true)

  defp version, do: to_string(Application.spec(:world, :vsn))
end
