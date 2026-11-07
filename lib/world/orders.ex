defmodule World.Orders do
  @moduledoc """
  The factory (`docs/factory.md`): an order in, the files of a model out.

  An order is a map (from JSON):

  - `"blueprint"`: the name of a blueprint (`World.Orders.Blueprints`),
    or a blueprint in data from a project (`docs/format.md`, "A
    blueprint in data"; `World.Orders.Blueprint.check_data/2`), or
    `{"hash": HASH}` of a blueprint that `POST /blueprints` keeps (plan
    0002, D1). The full order has the blueprint in data itself, so its
    hash names the blueprint and its options;
  - `"options"`: the options of the blueprint;
  - `"colors"`: a color `#rrggbb` for a material role (`"paint"`);
  - `"joints"`: the value of a joint at rest, in degrees or meters
    (`{"hood": 50}`);
  - `"targets"`: the point of the end of a limb of a figure, `[x, y, z]`
    in meters in the axes of the figure (`{"arm_r": [0.3, 0.4, 1.3]}`).
    The full order has this key only when it has a target: the hash of
    an order with no target stays the same.

  `check/1` gives the full order: each option with its value, and the
  keys in one order. `hash/1` is the name of its files: the same order
  gives the same hash, and the same files.
  """
  alias World.{Build, Detail, GLB, Log}
  alias World.Orders.{Blueprint, Blueprints, Store}
  @keys ~w(blueprint options colors joints targets)
  @levels %{"near" => :near, "mid" => :mid, "far" => :far}
  @files ~w(glb log replay parts receipt)

  @doc "The names of the levels of detail."
  def levels, do: Map.keys(@levels) |> Enum.sort()

  @doc """
  Check an order. Gives `{:ok, order}`, the full order, or `{:error,
  errors}`: each error is a map with its `"path"` and its `"message"`.
  """
  def check(order) when is_map(order) do
    case full(order) do
      {:ok, full} -> {:ok, full}
      {:error, errors} -> {:error, for({path, message} <- errors, do: %{"path" => path, "message" => message})}
    end
  end

  def check(_order), do: {:error, [%{"path" => "", "message" => "must be an object"}]}

  defp full(order) do
    unknown = for key <- Enum.sort(Map.keys(order)), key not in @keys, do: {key, "is not a key of an order"}

    with [] <- unknown,
         {:ok, blueprint, given} <- blueprint(order["blueprint"]),
         {:ok, options} <- Blueprint.check_options(blueprint.options, Map.get(order, "options", %{}), "options"),
         [] <- if(blueprint.check, do: blueprint.check.(options), else: []),
         {:ok, colors} <- colors(Map.get(order, "colors", %{})),
         {:ok, joints} <- joints(Map.get(order, "joints", %{})),
         {:ok, targets} <- targets(Map.get(order, "targets", %{})) do
      full = %{"blueprint" => given, "options" => options, "colors" => colors, "joints" => joints}
      {:ok, if(targets == %{}, do: full, else: Map.put(full, "targets", targets))}
    else
      errors when is_list(errors) -> {:error, errors}
      {:error, errors} -> {:error, errors}
    end
  end

  defp blueprint(%{"hash" => hash} = given) when map_size(given) == 1 do
    with true <- is_binary(hash) and hash =~ ~r/^[0-9a-f]{32}$/,
         {:ok, json} <- Store.get_key(Store.blueprint(hash)) do
      blueprint(JSON.decode!(json))
    else
      :error -> {:error, [{"blueprint.hash", "the store of the blueprints failed"}]}
      _ -> {:error, [{"blueprint.hash", "is not a blueprint of the store: send it to POST /blueprints"}]}
    end
  end

  defp blueprint(%{} = raw) do
    case Blueprint.check_data(raw, "blueprint") do
      [] -> {:ok, Blueprint.from_data(raw), raw}
      errors -> {:error, errors}
    end
  end

  defp blueprint(name) do
    case Blueprints.fetch(name) do
      {:ok, b} ->
        {:ok, b, b.name}

      :error ->
        {:error, [{"blueprint", "must be one of: #{Enum.join(Blueprints.names(), ", ")}, or a blueprint in data"}]}
    end
  end

  @doc """
  Keep a blueprint in data of a project (`POST /blueprints`): `{:ok,
  %{"hash", "name"}}`, `{:error, errors}`, or `{:error, :store}`. An order
  can then give `{"hash": HASH}` as its blueprint.
  """
  def keep_blueprint(raw) do
    case Blueprint.check_data(raw, "blueprint") do
      [] ->
        hash = hash(raw)

        case Store.put_key(Store.blueprint(hash), encode(raw)) do
          :ok -> {:ok, %{"hash" => hash, "name" => raw["name"]}}
          :error -> {:error, :store}
        end

      errors ->
        {:error, for({path, message} <- errors, do: %{"path" => path, "message" => message})}
    end
  end

  defp colors(colors) when is_map(colors) do
    roles = GLB.palette() |> Map.keys() |> Enum.sort()
    color = Blueprint.option("color", :color)

    errors =
      Enum.flat_map(Enum.sort(colors), fn {role, c} ->
        if role in roles,
          do: elem_errors(Blueprint.value(color, c, "colors.#{role}")),
          else: [{"colors.#{role}", "must be a role: #{Enum.join(roles, ", ")}"}]
      end)

    if errors == [], do: {:ok, Map.new(colors, fn {k, v} -> {k, String.downcase(v)} end)}, else: {:error, errors}
  end

  defp colors(_), do: {:error, [{"colors", "must be an object"}]}

  defp joints(joints) when is_map(joints) do
    errors =
      for {name, v} <- Enum.sort(joints), not is_number(v), do: {"joints.#{name}", "must be a number"}

    if errors == [], do: {:ok, Map.new(joints, fn {k, v} -> {k, v / 1} end)}, else: {:error, errors}
  end

  defp joints(_), do: {:error, [{"joints", "must be an object"}]}

  defp targets(targets) when is_map(targets) do
    errors =
      for {name, v} <- Enum.sort(targets),
          not match?([x, y, z] when is_number(x) and is_number(y) and is_number(z), v),
          do: {"targets.#{name}", "must be a point: [x, y, z] in meters"}

    if errors == [], do: {:ok, Map.new(targets, fn {k, v} -> {k, Enum.map(v, &(&1 / 1))} end)}, else: {:error, errors}
  end

  defp targets(_), do: {:error, [{"targets", "must be an object"}]}

  defp elem_errors({:ok, _}), do: []
  defp elem_errors({:error, errors}), do: errors

  @doc "The hash of a full order: 32 hex digits of its SHA-256."
  def hash(order), do: :crypto.hash(:sha256, encode(order)) |> Base.encode16(case: :lower) |> binary_part(0, 32)

  @doc """
  The JSON of a value with the keys of each object in order: the same
  value gives the same bytes.
  """
  def encode(map) when is_map(map) do
    pairs =
      for {k, v} <- Enum.sort_by(map, fn {k, _} -> to_string(k) end), do: [JSON.encode!(to_string(k)), ?:, encode(v)]

    IO.iodata_to_binary([?{, Enum.intersperse(pairs, ?,), ?}])
  end

  def encode(list) when is_list(list),
    do: IO.iodata_to_binary([?[, Enum.intersperse(Enum.map(list, &encode/1), ?,), ?]])

  def encode(value), do: JSON.encode!(value)

  @doc "The files of an order."
  def files, do: @files

  # The URL of each file of a placed order: the suffix of /o/HASH (the
  # names that the Worker serves, handler.js), the level and the file.
  @urls ~w(glb mid.glb far.glb parts.json receipt.json log.json replay.glb)

  @doc """
  Place an order (`POST /orders`, and the tool `place_order` of
  `World.MCP`): check it, and keep the full order in the store
  (`World.Orders.Store`), so that its files can build later at their
  URLs. `origin` is the start of the URLs (`https://world.mkfifo.com`).

  The model of the order must be true (`World.Check`, at the level
  `far`: it has few parts): it stands, its parts are not in one place,
  its joints are in their limits, and it goes out of the door of its
  workshop. Else the order is refused, with each reason at the path
  `"model"`.

  Gives `{:ok, %{"hash", "order", "files", "replay"}}`, `{:error,
  errors}` as `check/1`, or `{:error, :store}` when the store failed.
  """
  def place(order, origin) do
    with {:ok, full} <- check(order),
         :ok <- sound(full) do
      hash = hash(full)

      case World.Orders.Store.put(hash, encode(full)) do
        :ok ->
          files = Map.new(@urls, &{&1, "#{origin}/o/#{hash}.#{&1}"})
          {:ok, %{"hash" => hash, "order" => full, "files" => files, "replay" => "#{origin}/replay.html?order=#{hash}"}}

        :error ->
          {:error, :store}
      end
    end
  end

  @doc """
  Build a file of an order at a level (`"near"`, `"mid"` or `"far"`). The
  files (`files/0`):

  - `"glb"`: the model. The people of the node build it
    (`World.Construction`), with the pose and the colors of the order.
  - `"log"`: the log of the construction of the order, in JSON
    (`World.Log`).
  - `"replay"`: the model with each part in a node of its own, with the id
    of its task, for the replay of the log.
  - `"parts"`: the list of the parts. `"receipt"`: the receipt.

  Gives `{:ok, binary}`, or `{:error, errors}` as `check/1`.
  """
  def build(order, level, file) do
    with {:ok, order} <- check(order),
         {:ok, lvl} <- level(level),
         :ok <- file(file) do
      job = new_job(order, lvl)
      # The item is a function: a construction makes it, so the memory
      # holds one item only (the edge has 128 MB).
      item = fn -> job.item.(lvl) end

      with :ok <- known(order, fn opts -> job.scene.(item.(), opts) end) do
        {:ok, make(file, order, lvl, item, job)}
      end
    end
  end

  @doc """
  The job of an order at a level, for a construction (`World.build/1`):
  its id (the hash of the order and the level), the item at a level, the
  scene with the pose and the colors of the order, and the hash.
  `{:ok, job}`, or `{:error, errors}` as `check/1`.
  """
  def job(order, level) do
    with {:ok, order} <- check(order), {:ok, lvl} <- level(level), do: {:ok, new_job(order, lvl)}
  end

  @doc """
  A construction of a request (`POST /builds`, the MCP tool `build`): the
  budget of `body` (`World.budget/1`), its `order` into the store, and the
  job at its `level` (`near` by default): `{:ok, job, placed}`, or
  `{:error, errors}` (`{:error, :store}` when the store fails).
  """
  def construction(%{"order" => order} = body, origin) do
    with {:ok, budget} <- World.budget(body["budget"]),
         {:ok, placed} <- place(order, origin),
         {:ok, job} <- job(placed["order"], Map.get(body, "level", "near")) do
      {:ok, Map.put(job, :budget, budget), placed}
    end
  end

  def construction(_body, _origin), do: {:error, [%{"path" => "order", "message" => "is required"}]}

  @doc "The answer of a construction that started: its id, its hash, its events after `after_id`, its files."
  def started(id, placed, after_id) do
    %{
      "build" => id,
      "hash" => placed["hash"],
      "after" => after_id,
      "events" => "/builds/#{id}/events?after=#{after_id}",
      "files" => placed["files"]
    }
  end

  @doc """
  The plan of the people for an order at a level, before a build (the MCP
  tool `plan_build`): the tasks (each with its trade and the tasks it
  waits for), the people of each trade that it needs at most, and the
  estimate of its triangles. A drawing with skills is not made for it:
  the estimate of each skill counts.
  """
  def plan(order, level) do
    with {:ok, job} <- job(order, level) do
      {plan, triangles} =
        if job.drawing do
          {World.Plan.of_drawing(job.drawing), World.Drawing.estimate(job.drawing, job.level)}
        else
          item = job.item.(job.level)
          {World.Plan.flat(item), World.Construction.estimate(item, job.level, job.pose)}
        end

      tasks = World.Plan.to_data(plan)["tasks"]

      {:ok,
       %{
         "hash" => job.hash,
         "level" => Atom.to_string(job.level),
         "tasks" => tasks,
         "trades" => Enum.frequencies(for t <- tasks, do: t["trade"]),
         "triangles" => triangles
       }}
    end
  end

  defp new_job(order, lvl) do
    {:ok, blueprint} = Blueprints.fetch(order["blueprint"])
    targets = Map.new(Map.get(order, "targets", %{}), fn {k, [x, y, z]} -> {k, {x, y, z}} end)

    scene = fn item, opts ->
      # The options of the call come first: a construction gives its level.
      s = Build.scene(item, opts ++ [level: lvl, pose: order["joints"], targets: targets])
      %{s | materials: Map.merge(s.materials, materials(order["colors"]))}
    end

    %{
      id: "#{hash(order)}-#{lvl}",
      hash: hash(order),
      level: lvl,
      item: fn level -> Detail.with(level, fn -> blueprint.build.(order["options"]) end) end,
      scene: scene,
      pose: order["joints"],
      drawing: skilled(Blueprints.drawing(order))
    }
  end

  # A drawing with a node that a skill makes: the people make it node by
  # node (`World.Construction`).
  defp skilled(%{"nodes" => nodes} = d), do: if(Enum.any?(nodes, &Map.has_key?(&1, "skill")), do: d)
  defp skilled(nil), do: nil

  defp make(file, _order, _lvl, _item, job) when file in ["glb", "log"] do
    {glb, log} = world(job)
    if file == "glb", do: glb, else: log
  end

  defp make("replay", _order, _lvl, item, job), do: GLB.encode(job.scene.(item.(), split: true))
  defp make("parts", _order, _lvl, item, _job), do: parts(item.())
  defp make("receipt", order, lvl, item, job), do: receipt(order, lvl, job.scene.(item.(), []))

  # A construction of the order by the people of the node: the files of
  # the model and the log of the construction, with its time (run_done).
  # Two requests of one order at one level are one construction.
  defp world(job) do
    {:ok, id} = World.build(job)
    {:ok, result} = World.await(id)
    {result.glb, Log.to_json(result.log)}
  end

  # The checks of a true model, on the item at the level far.
  defp sound(order) do
    {:ok, blueprint} = Blueprints.fetch(order["blueprint"])
    item = Detail.with(:far, fn -> blueprint.build.(order["options"]) end)

    case World.Check.model(item, order["joints"]) do
      :ok -> :ok
      {:error, reasons} -> {:error, for(r <- reasons, do: %{"path" => "model", "message" => World.Check.message(r)})}
    end
  end

  # A joint of the order must be a joint of the model, and a target a
  # limb of the model.
  defp known(order, scene) do
    names = for key <- ~w(joints targets), name <- Map.keys(Map.get(order, key, %{})), do: {key, name}

    if names == [] do
      :ok
    else
      extras = scene.([]).extras
      what = %{"joints" => {"joints", "a joint"}, "targets" => {"limbs", "a limb"}}

      errors =
        for {key, name} <- Enum.sort(names),
            {extra, noun} = what[key],
            name not in extras[extra],
            do: %{"path" => "#{key}.#{name}", "message" => "is not #{noun}: #{Enum.join(extras[extra], ", ")}"}

      if errors == [], do: :ok, else: {:error, errors}
    end
  end

  defp file(file) do
    if file in @files,
      do: :ok,
      else: {:error, [%{"path" => "file", "message" => "must be one of: #{Enum.join(@files, ", ")}"}]}
  end

  defp level(name) do
    case Map.fetch(@levels, name) do
      {:ok, l} -> {:ok, l}
      :error -> {:error, [%{"path" => "level", "message" => "must be one of: #{Enum.join(levels(), ", ")}"}]}
    end
  end

  # A color of an order keeps the roughness and the metalness of its role.
  defp materials(colors) do
    Map.new(colors, fn {role, "#" <> hex} ->
      <<r::8, g::8, b::8>> = Base.decode16!(hex, case: :lower)
      {String.to_existing_atom(role), Map.put(GLB.palette()[role], "color", [r, g, b])}
    end)
  end

  defp parts(item), do: encode(Build.parts_file(item.name, item))

  # The receipt of an order; a model with sizes from an order (a statue)
  # gives each size with its source.
  defp receipt(order, level, scene) do
    sizes = if scene.extras["sizes"], do: %{"sizes" => scene.extras["sizes"]}, else: %{}

    encode(
      Map.merge(sizes, %{
        "order" => order,
        "hash" => hash(order),
        "level" => Atom.to_string(level),
        "world" => to_string(Application.spec(:world, :vsn)),
        "name" => scene.extras["name"],
        "kind" => scene.extras["kind"],
        "size" => scene.extras["size"],
        "joints" => scene.extras["joints"],
        "limbs" => scene.extras["limbs"],
        "sources" => scene.extras["sources"]
      })
    )
  end
end
