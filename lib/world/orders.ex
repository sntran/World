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
  - `"mipmaps"`: true gives each sculpture of the drawing of the order
    the key `mipmaps` (`World.Skills.Sculpt`): its maps have a sampler
    with smaller copies of the image. The full order has this key only
    when it is true.

  `check/1` gives the full order: each option with its value, and the
  keys in one order. `hash/1` is the name of its files: the same order
  gives the same hash, and the same files.
  """
  alias World.{Build, Detail, GLB, Log}
  alias World.Orders.{Blueprint, Blueprints, Store}
  @keys ~w(blueprint options colors joints targets mipmaps)
  @levels %{"near" => :near, "mid" => :mid, "far" => :far}
  @files ~w(glb log replay parts receipt solids flat light drawing elements)

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
         {:ok, options} <- if(blueprint.resolve, do: blueprint.resolve.(options), else: {:ok, options}),
         [] <- if(blueprint.check, do: blueprint.check.(options), else: []),
         {:ok, colors} <- colors(Map.get(order, "colors", %{})),
         {:ok, joints} <- joints(Map.get(order, "joints", %{})),
         {:ok, targets} <- targets(Map.get(order, "targets", %{})),
         {:ok, mipmaps} <- mipmaps(Map.get(order, "mipmaps", false)) do
      full = %{"blueprint" => given, "options" => options, "colors" => colors, "joints" => joints}
      full = if(targets == %{}, do: full, else: Map.put(full, "targets", targets))
      {:ok, if(mipmaps, do: Map.put(full, "mipmaps", true), else: full)}
    else
      errors when is_list(errors) -> {:error, errors}
      {:error, errors} -> {:error, errors}
    end
  end

  defp mipmaps(v) when is_boolean(v), do: {:ok, v}
  defp mipmaps(_v), do: {:error, [{"mipmaps", "must be true or false"}]}

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
  @urls ~w(glb mid.glb far.glb parts.json receipt.json log.json replay.glb solids.json drawing.json flat.glb mid.flat.glb far.flat.glb light.glb mid.light.glb far.light.glb elements.json mid.elements.json far.elements.json)

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
  - `"flat"`: the model at the level with the flat look, as a GLB
    (`World.Flat`): one mesh, a color at each point, no image. A drawing
    from edits is built with the look `flat` of each of its sculptures
    (the color of each face is the color of its edits). With the option
    `triangles` (12 to 200,000), the mesh has that count of faces at the
    most. With the option `wrap`, the mesh is one closed skin round the
    whole model (a cast of the model in a grid): for a model of many
    thin parts in a small budget (a scooter in 500 triangles).
  - `"light"`: the model at the level with the light look, as a GLB
    (`World.Flat`, `roles: true`): one mesh with a primitive for each
    role, no image and no skin, for a project that gives each role its
    own material. It takes `triangles` and `wrap` too.
  - `"drawing"`: the drawing of the model in JSON
    (`World.Orders.Blueprints.free/1`), with the options of the order in
    it: each part with its shapes or its skill, the nodes, the joints. A
    project that cannot correct a model with the options of its rule
    orders this drawing (the blueprint `drawing`, or the edit `free`),
    and then changes any shape of it (`World.Orders.Edits`). A model that
    the code of a rule makes (a plant, a person, an animal) is one node
    of its drawing: a project adds parts to it.
  - `"elements"`: the parts list of the model at the level in JSON
    (`World.Elements`): each part with its key, the URL of its GLB, its
    node, its place and its roles, and the joints and the ports of the
    model. The factory does not join the parts: a project puts them
    together.
  - `"solids"`: the simple solids of the model in JSON (`World.Solids`):
    the shapes of a drawing from edits with no build, or one box for
    each node and material of another model.

  Gives `{:ok, binary}`, or `{:error, errors}` as `check/1`.
  """
  def build(order, level, file, opts \\ [])

  def build(order, level, "elements", _opts) do
    with {:ok, list} <- World.Elements.list(order, level), do: {:ok, encode(list)}
  end

  def build(order, level, file, opts) do
    with {:ok, order} <- check(order),
         {:ok, lvl} <- level(level),
         :ok <- file(file),
         :ok <- triangles(opts[:triangles]),
         :ok <- wrap(opts[:wrap]) do
      job = Map.merge(new_job(order, lvl), %{triangles: opts[:triangles], wrap: opts[:wrap] == true})
      # The item is a function: a construction makes it, so the memory
      # holds one item only (the edge has 128 MB).
      item = fn -> job.item.(lvl) end

      # (In the guard of the memory: an order that needs more memory than
      # the VM has gets an error, and the VM goes on.)
      guarded(fn ->
        with :ok <- known(order, fn opts -> job.scene.(item.(), opts) end) do
          {:ok, make(file, order, lvl, item, job)}
        end
      end)
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

  # An order with the option `method` (plan 0006, D6) has its method, the
  # most people on its site, and the stages of its site (World.Method):
  # the job of a stage with options is the order with them, and the job
  # starts with the job of its first stage.
  defp new_job(%{"options" => %{"method" => method}} = order, lvl) do
    stages =
      for st <- World.Method.stages(order) do
        if st.options,
          do: Map.put(st, :job, one_job(update_in(order, ["options"], &Map.merge(&1, st.options)), lvl)),
          else: st
      end

    job = one_job(order, lvl)
    first = hd(stages)
    start = if first[:job], do: Map.take(first.job, [:item, :scene, :drawing]), else: %{}

    # The drawing of the model at the end, for its replay.
    job
    |> Map.merge(start)
    |> Map.merge(%{method: method, stages: stages, workers: World.Method.workers(method), model: job.drawing})
    |> then(&if(first.lot, do: Map.put(&1, :lot, first.lot), else: &1))
  end

  defp new_job(order, lvl), do: one_job(order, lvl)

  defp one_job(order, lvl) do
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
      colors: order["colors"],
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

  # The replay of a drawing has each node that a person sees on the site
  # (plan 0006, D9): the temporary nodes too (the scaffold, the forms, the
  # rough bands), each with the task that puts it up and the task that
  # takes it down (`from`, `to` of its extras).
  defp make("replay", _order, lvl, _item, %{drawing: d} = job) when d != nil do
    d = Map.get(job, :model, d)
    stream = Detail.with(lvl, fn -> World.Drawing.build(d, stream: true) end)
    scene = job.scene.(stream, split: true)
    downs = Map.new(for n <- d["nodes"], n["down"], do: {n["name"], n["down"]})

    nodes =
      for n <- scene.nodes do
        case n.extras do
          %{"task" => task} -> %{n | extras: Map.merge(n.extras, from_to(task, downs[task]))}
          _ -> n
        end
      end

    GLB.encode(%{scene | nodes: nodes})
  end

  defp make("replay", _order, _lvl, item, job), do: GLB.encode(job.scene.(item.(), split: true))
  defp make("parts", _order, _lvl, item, _job), do: parts(item.())
  defp make("receipt", order, lvl, item, job), do: receipt(order, lvl, job.scene.(item.(), []))

  defp make("flat", _order, lvl, item, job) do
    item =
      if World.Solids.edits?(job.drawing) do
        flat = update_in(job.drawing, ["nodes", Access.all(), "skill", "sculpt"], &Map.put(&1, "look", "flat"))
        Detail.with(lvl, fn -> World.Drawing.build(flat) end)
      else
        item.()
      end

    GLB.encode(World.Flat.scene(job.scene.(item, []), budget: job.triangles, wrap: job.wrap))
  end

  defp make("light", _order, _lvl, item, job),
    do: GLB.encode(World.Flat.scene(job.scene.(item.(), []), budget: job.triangles, wrap: job.wrap, roles: true))

  defp make("drawing", order, _lvl, _item, _job), do: encode(Blueprints.free(order))

  defp make("solids", _order, _lvl, item, job) do
    solids =
      if World.Solids.edits?(job.drawing),
        do: World.Solids.of(job.drawing),
        else: World.Solids.boxes(job.scene.(item.(), []))

    encode(solids)
  end

  defp from_to(task, nil), do: %{"from" => task}
  defp from_to(task, down), do: %{"from" => task, "to" => down}

  # A construction of the order by the people of the node: the files of
  # the model and the log of the construction, with its time (run_done).
  # Two requests of one order at one level are one construction.
  defp world(job) do
    {:ok, id} = World.build(job)
    {:ok, result} = World.await(id)
    {result.glb, Log.to_json(result.log)}
  end

  # A function in the guard of the memory (`World.Guard`): its value, or the error of the memory.
  defp guarded(fun) do
    case World.Guard.run(fun) do
      {:ok, value} -> value
      {:error, :memory} -> {:error, World.Guard.errors()}
    end
  end

  # The checks of a true model, on the item at the level far, in the guard of the memory: for the
  # data of a project (a drawing) and for a pose (`joints`). A rule in code with no pose is checked
  # by the tests of its rule (a group of people with fans took 150 MB at the edge for nothing). A
  # model with a sculpture of more faces than a step of a part (W26: a large building) is not built
  # for them: its build needs more memory than the edge has, and its parts are built one by one.
  # The check of its data stays.
  defp sound(order) do
    drawing = Blueprints.drawing(order)

    cond do
      drawing == nil and Map.get(order, "joints", %{}) == %{} -> :ok
      large?(drawing) -> :ok
      true -> guarded(fn -> sound_now(order) end)
    end
  end

  defp large?(%{"nodes" => nodes}) do
    Enum.any?(nodes, fn
      %{"skill" => %{"sculpt" => data}} -> World.Skills.Sculpt.faces(data, :far) > World.Elements.most()
      _ -> false
    end)
  end

  defp large?(_drawing), do: false

  defp sound_now(order) do
    {:ok, blueprint} = Blueprints.fetch(order["blueprint"])
    item = Detail.with(:far, fn -> blueprint.build.(order["options"]) end)

    case World.Check.model(item, order["joints"], base: base(Blueprints.drawing(order))) do
      :ok -> :ok
      {:error, reasons} -> {:error, for(r <- reasons, do: %{"path" => "model", "message" => World.Check.message(r)})}
    end
  end

  # The height of the base of a model for its check: 2 mm, and for a model from edits the largest cell of
  # its sculptures at the far level (the surface of a sculpture is true to about a cell).
  defp base(%{"nodes" => nodes}) do
    cells =
      for %{"skill" => %{"sculpt" => %{"cells" => cells}}} <- nodes,
          do: if(is_map(cells), do: cells |> Map.values() |> Enum.max(), else: cells)

    Enum.max([0.002 | cells])
  end

  defp base(_drawing), do: 0.002

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

  # The budget of the flat look: no budget, or a count of triangles.
  defp triangles(nil), do: :ok
  defp triangles(n) when is_integer(n) and n >= 12 and n <= 200_000, do: :ok
  defp triangles(_n), do: {:error, [%{"path" => "triangles", "message" => "must be a whole number from 12 to 200000"}]}

  defp wrap(wrap) when wrap in [nil, true, false], do: :ok
  defp wrap(_wrap), do: {:error, [%{"path" => "wrap", "message" => "must be true or false"}]}

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
