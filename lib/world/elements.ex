defmodule World.Elements do
  @moduledoc """
  The parts list of an order at a level (W24 to W27 of `TODO.md`):
  World gives the parts, and a project puts them together. World does
  not join the parts into one model, and it does not keep a whole model
  in its memory.

  The list (the file `elements` of an order, `World.Orders.build/4`):

  - `parts`: each part with its `key`, its `url` (`/p/KEY.glb`), its
    `node` (the id of its node: the path in the plan of the model), its
    `part` (its name), its `matrix` (16 numbers, by columns: its place in
    the axes of the model, Y up as in glTF), its `roles` (the materials
    that it uses), its `joint` (the joint that moves it, or nil) and, for
    a tile of a sculpture, its `tile` (its index and its share of the
    faces of the sculpture);
  - `joints`, `limbs` and `ports` of the model, and `collision` (its
    boxes), as in the extras of its GLB.

  The key of a part (W25) is a hash of the data of the part and of the
  version of its rule (`version/1`: the code of the rule and of each
  module of World that it calls, but the modules of the service). The same data gives the same key, so
  the store keeps each part once, and an edit of an order changes only
  the keys of the parts whose data changed (W27):

  - a sculpture that is one part: the data of its node and of the nodes
    it waits for (`node_keys/2`);
  - a tile of a sculpture (W26, `World.Skills.Sculpt.tiles/3`): the
    edits near the tile, its box, its share, and the other data of the
    sculpture;
  - a part that is made (a node of a drawing with another skill, a model
    of a rule in code: a person, a vehicle): its content (`made_key/4`).
    A part that an edit does not change keeps its key.

  A node of a drawing with a skill other than `sculpt`, and a model of a
  rule in code, are made for the list, and the GLB of each of their
  parts goes into the store at once. A sculpture is not made for the
  list: each of its parts has a recipe in the store (`parts/KEY.json`),
  and `part/1` builds it at its first request. So the list needs little
  memory and time, and each part needs the memory of one part. A
  sculpture with more than `most` faces at its cells (an estimate; the
  application environment `:tile_faces`, #{12_000} by default) is cut
  into tiles, each with a budget of `least` triangles or more
  (`:tile_least`, #{1500} by default), and each made in steps of at most
  `most` faces: so a part fits the memory of the edge, and it has a good
  shape.
  """

  alias World.{Build, Detail, Drawing, Frame, GLB, Guard, Orders, Part}
  alias World.Elements.Store
  alias World.Orders.Blueprints
  alias World.Skills.Sculpt

  @most 12_000
  @least 1500

  @doc "The most faces of a step of a part of a sculpture (an estimate at its cells)."
  def most, do: Application.get_env(:world, :tile_faces, @most)

  @doc "The least budget of a part of a sculpture (triangles)."
  def least, do: Application.get_env(:world, :tile_least, @least)

  @doc """
  The parts list of an order at a level (`"near"`, `"mid"` or `"far"`):
  `{:ok, list}` (a map, as JSON), or `{:error, errors}` as
  `World.Orders.check/1`. It runs in the guard of the memory
  (`World.Guard`).
  """
  def list(order, level) do
    with {:ok, full} <- Orders.check(order),
         {:ok, job} <- Orders.job(full, level) do
      case Guard.run(fn -> make_list(full, job) end) do
        {:ok, list} -> {:ok, list}
        {:error, :memory} -> {:error, Guard.errors()}
      end
    end
  end

  @doc """
  The GLB of a part by its key: from the store, else from its recipe
  (a part of a sculpture, built now and then kept). `{:ok, glb}`,
  `:none` when the store has neither, or `{:error, errors}` (the memory).
  """
  def part(key) do
    case Store.get(key) do
      {:ok, glb} ->
        {:ok, glb}

      _ ->
        with {:ok, json} <- Store.recipe(key),
             {:ok, recipe} <- JSON.decode(json),
             {:ok, raw} <- Orders.Store.get(recipe["order"]),
             {:ok, order} <- JSON.decode(raw) do
          case Guard.run(fn -> from_recipe(order, recipe) end) do
            {:ok, glb} ->
              Store.put(key, glb)
              {:ok, glb}

            {:error, :memory} ->
              {:error, Guard.errors()}
          end
        else
          _ -> :none
        end
    end
  end

  @doc """
  The GLB of a part by its key, for a request: from the store, else its
  build in a process of its own (one for each key, in the line of the
  builds, `World.Line`), for at most `wait` ms. `{:ok, glb}`, `:building`
  when the build goes on after `wait` (the next request gets it; the
  application environment `:part_wait`, 45 s by default), `:none`
  or `{:error, errors}` as `part/1`. The host of the VM at the edge ends a
  request after 60 s, and a large part takes more.
  """
  def fetch(key, wait \\ wait()) do
    with :error <- stored(key),
         {:ok, _} <- Store.recipe(key) do
      case background({:part, key}, fn -> World.Line.run(:now, fn -> part(key) end) end, wait) do
        {:ok, result} -> result
        :building -> :building
        # (The build ended before it got the message: its part is in the store.)
        :gone -> with {:ok, glb} <- Store.get(key), do: {:ok, glb}, else: (_ -> :none)
      end
    else
      {:ok, glb} -> {:ok, glb}
      _ -> :none
    end
  end

  @doc """
  The value of `fun`, made in a process of its own, one for each `key`
  (a second request of the same key waits for the same build), for at
  most `wait` ms (`:part_wait` of the application environment, 45 s by
  default): `{:ok, value}`, `:building` when the build goes on after the
  wait, or `:gone` when the build ended before the request. The host of
  the VM at the edge ends a request after 60 s: a long build (a large
  part, the parts list of a large model at near) goes on, and a request
  after it gets its value from the store.
  """
  def background(key, fun, wait \\ wait()) do
    pid = builder(key, fun)
    ref = Process.monitor(pid)
    send(pid, {:wait, self(), ref})

    receive do
      {^ref, result} ->
        Process.demonitor(ref, [:flush])
        {:ok, result}

      {:DOWN, ^ref, :process, ^pid, _} ->
        :gone
    after
      wait ->
        Process.demonitor(ref, [:flush])
        :building
    end
  end

  defp wait, do: Application.get_env(:world, :part_wait, 45_000)

  # A part from the store, or `:error`.
  defp stored(key) do
    case Store.get(key) do
      {:ok, glb} -> {:ok, glb}
      _ -> :error
    end
  end

  # The process of a build: the one that runs now for the key, or a new one.
  defp builder(key, fun) do
    {me, ref} = {self(), make_ref()}

    Task.start(fn ->
      case Registry.register(World.Names, {:build, key}, nil) do
        {:ok, _} ->
          send(me, {ref, self()})
          answer(fun.())

        {:error, {:already_registered, other}} ->
          send(me, {ref, other})
      end
    end)

    receive do: ({^ref, pid} -> pid)
  end

  # The result of a build to each request that waits for it.
  defp answer(result) do
    receive do
      {:wait, pid, ref} ->
        send(pid, {ref, result})
        answer(result)
    after
      0 -> :ok
    end
  end

  @doc """
  The version of a rule: a hash of the code of its module and of each
  module of World that its code calls, again and again. It changes when
  one of them changes, and not when another module of World changes.
  """
  def version(module) do
    case :persistent_term.get({__MODULE__, :version, module}, nil) do
      nil ->
        sums = for m <- module |> calls(MapSet.new()) |> Enum.sort(), do: m.module_info(:md5)
        version = :crypto.hash(:md5, sums) |> Base.encode16(case: :lower) |> binary_part(0, 12)
        :persistent_term.put({__MODULE__, :version, module}, version)
        version

      version ->
        version
    end
  end

  @doc """
  The key of each node of a drawing at a level: a hash of the data of
  the node (with no name), of the keys of the nodes that it waits for,
  and of the level.
  """
  def node_keys(raw, level) do
    root = hd(raw["nodes"])["name"]
    by_name = Map.new(raw["nodes"], &{&1["name"], &1})

    Enum.reduce(Drawing.order(raw), %{}, fn name, keys ->
      node = by_name[name]
      waits = for w <- Drawing.waits(node, root), do: keys[w]
      Map.put(keys, name, hash({Map.delete(node, "name"), waits, level}))
    end)
  end

  @doc "The key of the part `n` of a node of a drawing whose key is `node_key`, made by the rule `module`."
  def node_part_key(module, node_key, n), do: hash({:node, version(module), node_key, n})

  @doc """
  The key of a part that is made (`glb/4`): a hash of its content (its
  meshes, or the figure; not the levels where it shows), its level,
  the maps of its node, the colors
  of the order, and the version of `World.Build` (the code that writes
  its GLB). The same part has the same key in each model and in each
  construction (W28): a wall of 1,000 bricks of one shape has one key.
  """
  def made_key(thing, level, materials \\ %{}, colors \\ %{}),
    do: hash({:made, version(Build), level, content(thing), materials, colors})

  # The content of a part for its key: not the level of detail where it
  # shows (`World.Build` gives the root of a model `:always`).
  defp content(%Part{} = p), do: %{p | detail: nil}
  defp content(thing), do: thing

  @doc """
  The GLB of one part of a model: the part (or a figure) alone at its
  own origin, at a level, with the materials of `materials` (a role to
  its spec: the maps of a sculpture) and the colors of the order.
  """
  def glb(thing, level, materials \\ %{}, colors \\ %{}) do
    scene = Build.scene(thing, level: level)
    more = Map.new(materials, fn {role, spec} -> {GLB.role(role), Map.merge(GLB.palette()[role] || %{}, spec)} end)

    colors =
      Map.new(colors, fn {role, "#" <> hex} ->
        <<r::8, g::8, b::8>> = Base.decode16!(hex, case: :lower)
        {GLB.role(role), Map.put(GLB.palette()[role] || %{}, "color", [r, g, b])}
      end)

    GLB.encode(%{scene | materials: scene.materials |> Map.merge(more) |> Map.merge(colors)})
  end

  # --- The list ---------------------------------------------------------

  defp make_list(full, %{drawing: nil} = job) do
    {:ok, blueprint} = Blueprints.fetch(full["blueprint"])
    if blueprint.pieces, do: pieces_list(full, job, blueprint), else: item_list(full, job)
  end

  defp make_list(full, job), do: drawing_list(full, job)

  # The pieces of a rule that gives them one by one (a group of people):
  # each made alone, in a process of its own, at its place.
  defp pieces_list(full, job, blueprint) do
    colors = full["colors"] || %{}
    pieces = Detail.with(job.level, fn -> blueprint.pieces.(full["options"]) end)

    parts =
      for {name, make, place} <- pieces do
        Detail.apart(fn ->
          Detail.with(job.level, fn ->
            thing = make.()
            frame = if place, do: placed(thing, place), else: Frame.identity()
            key = made_key(thing, job.level, %{}, colors)
            keep(MapSet.new(), key, fn -> glb(thing, job.level, %{}, colors) end)
            kind = if match?(%World.Figure{}, thing), do: "figure", else: "part"
            entry(key, name, thing.name, roles(thing), nil) |> Map.merge(%{"matrix" => matrix(frame), "kind" => kind})
          end)
        end)
      end

    result(full, job, parts, %{})
  end

  # The frame of a piece with its port `own` at `port` (as `World.Assembly.add/4`, with no turn).
  defp placed(thing, {port, own}),
    do: Frame.compose(World.Port.frame(port), Frame.invert(World.Assembly.item_port_frame(thing, own)))

  defp item_list(full, job) do
    item = job.item.(job.level)
    places = Build.places(item, job.level, job.pose || %{})

    colors = full["colors"] || %{}

    {parts, _} =
      Enum.map_reduce(pieces(places), MapSet.new(), fn {kind, path, frame, thing, joint}, stored ->
        key = made_key(thing, job.level, %{}, colors)
        stored = keep(stored, key, fn -> glb(thing, job.level, %{}, colors) end)

        e =
          entry(key, path, thing.name, roles(thing), joint)
          |> Map.merge(%{"matrix" => matrix(frame), "kind" => Atom.to_string(kind)})

        {e, stored}
      end)

    extras = Build.scene(light(item), level: job.level, pose: job.pose || %{}).extras
    result(full, job, parts, extras)
  end

  defp drawing_list(full, job) do
    raw = job.drawing
    level = job.level
    keys = node_keys(raw, level)
    hash = Orders.hash(full)
    # (The recipe of a part has the hash of the order: the order goes into the store.)
    :ok = Orders.Store.put(hash, Orders.encode(full))

    # Each node in a process of its own: only a light copy of it (its
    # ports and its frames, with no meshes) and the list of its parts
    # come back.
    {made, own} =
      Enum.reduce(Drawing.order(raw), {%{}, %{}}, fn name, {made, own} ->
        inputs = Drawing.inputs(raw, name, made)
        args = %{name: name, key: keys[name], level: level, hash: hash, colors: full["colors"] || %{}}
        {thing, data, extras, list} = Detail.apart(fn -> Detail.with(level, fn -> node(raw, args, inputs) end) end)
        {Map.put(made, name, {thing, data, extras}), Map.put(own, name, list)}
      end)

    model = Drawing.assemble(raw, made)
    places = Build.places(model, level, job.pose || %{})

    parts =
      for n <- raw["nodes"], list = Map.get(own, n["name"], []), list != [] do
        {thing, _, _} = made[n["name"]]
        # The frame of the node: the place of the root of its thing in
        # the model, less the place of that root in the thing alone.
        {root, anchor} = root(thing)
        path = if root, do: n["name"] <> "/" <> root, else: n["name"]
        {_, _, at, _, joint} = Enum.find(pieces(places, true), fn {_, p, _, _, _} -> p == path end)
        base = Frame.compose(at, Frame.invert(anchor))

        for e <- list do
          {f, e} = Map.pop(e, :frame)
          Map.merge(e, %{"matrix" => matrix(Frame.compose(base, f)), "joint" => joint})
        end
      end

    result(full, job, List.flatten(parts), Build.scene(model, level: level, pose: job.pose || %{}).extras)
  end

  defp result(full, job, parts, extras) do
    %{
      "order" => Orders.hash(full),
      "level" => Atom.to_string(job.level),
      "parts" => parts,
      "joints" => Map.get(extras, "joints", []),
      "limbs" => Map.get(extras, "limbs", []),
      "ports" => Map.get(extras, "ports", []),
      "collision" => Map.get(extras, "collision", [])
    }
  end

  # One node of a drawing: `{light thing, data, extras, parts}`. A
  # sculpture is not made: its parts are recipes. Each other node is
  # made, and the GLB of each of its parts goes into the store.
  defp node(raw, args, inputs) do
    drawing = Drawing.node(raw, args.name)

    # (A sculpture with bones is a figure: it is made as the other nodes.)
    case hd(drawing["nodes"]) do
      %{"skill" => %{"sculpt" => data}} when not is_map_key(data, "bones") -> sculpture(data, args)
      _ -> made(drawing, args, inputs)
    end
  end

  defp sculpture(data, args) do
    ports = Drawing.ports(Map.get(data, "ports", %{}))
    light = Part.new(args.name, :part, [], ports, sources: Map.get(data, "sources", []))
    roles = Sculpt.roles(data, args.level)

    list =
      case Sculpt.tiles(data, args.level, most(), least()) do
        nil ->
          key = node_part_key(Sculpt, args.key, 0)
          recipe(key, args, nil)
          [entry(key, args.name, args.name, roles, nil) |> Map.merge(%{"kind" => "part", :frame => Frame.identity()})]

        tiles ->
          for t <- tiles do
            key = hash({:tile, version(Sculpt), Sculpt.tile_key(data, t, args.level), args.level})
            recipe(key, args, t)
            share = %{"index" => t.index, "share" => t.share, "faces" => t.faces}

            entry(key, args.name, "#{args.name}_#{t.index}", roles, nil)
            |> Map.merge(%{"kind" => "part", "tile" => share, :frame => Frame.identity()})
          end
      end

    {light, %{}, %{}, list}
  end

  defp made(drawing, args, inputs) do
    {thing, data, extras} = Drawing.make(drawing, args.name, inputs)
    {materials, data} = Map.pop(data, "materials", %{})

    list =
      if thing do
        places = Build.places(thing, args.level)

        {list, _} =
          Enum.map_reduce(pieces(places), MapSet.new(), fn {kind, _path, frame, piece, _}, stored ->
            key = made_key(piece, args.level, materials, args.colors)
            stored = keep(stored, key, fn -> glb(piece, args.level, materials, args.colors) end)

            {entry(key, args.name, piece.name, roles(piece), nil)
             |> Map.merge(%{"kind" => Atom.to_string(kind), :frame => frame}), stored}
          end)

        list
      else
        []
      end

    {thing && light(thing), data, extras, list}
  end

  # A part into the store, when the store does not have it yet (once for each key of a list).
  defp keep(stored, key, glb) do
    if MapSet.member?(stored, key) or Store.has?(key), do: :ok, else: Store.put(key, glb.())
    MapSet.put(stored, key)
  end

  # The recipe of a part of a sculpture: the order, the level, the node and the tile.
  defp recipe(key, args, tile) do
    unless Store.has?(key) do
      tile = tile && %{tile | box: boxlist(tile.box), steps: for({b, share} <- tile.steps, do: [boxlist(b), share])}

      Store.put_recipe(
        key,
        JSON.encode!(%{
          "order" => args.hash,
          "level" => Atom.to_string(args.level),
          "node" => args.name,
          "tile" => tile
        })
      )
    end
  end

  defp boxlist({lo, hi}), do: [Tuple.to_list(lo), Tuple.to_list(hi)]

  # A part of a sculpture from its recipe: the sculpture of the node, or one of its tiles.
  defp from_recipe(order, %{"level" => l, "node" => name, "tile" => tile}) do
    level = String.to_existing_atom(l)
    {:ok, full} = Orders.check(order)
    raw = Blueprints.drawing(full)
    [node] = Drawing.node(raw, name)["nodes"]
    data = node["skill"]["sculpt"]
    context = %{level: level, name: name}

    {part, more} =
      Detail.with(level, fn ->
        case tile do
          nil ->
            {part, more, _} = Sculpt.make(data, %{}, context)
            {part, more}

          t ->
            [lo, hi] = t["box"]
            box = fn [lo, hi] -> {List.to_tuple(lo), List.to_tuple(hi)} end
            steps = for [b, share] <- t["steps"], do: {box.(b), share}
            tile = %{index: t["index"], share: t["share"], faces: t["faces"], box: box.([lo, hi]), steps: steps}
            Sculpt.tile(data, tile, %{}, context)
        end
      end)

    glb(part, level, Map.get(more, "materials", %{}), full["colors"] || %{})
  end

  # --- Pieces and places ------------------------------------------------

  # The pieces of the places of a model: each figure, and each part with
  # meshes (with `empty: true`, also each part with none: a part of a
  # light copy). Each with the joint that moves it.
  defp pieces(places, empty \\ false) do
    for place <- places, piece = piece(place, empty), piece != nil, do: piece
  end

  defp piece({:figure, _, _, _, _} = figure, _empty), do: figure

  defp piece({:part, _, _, part, _} = place, empty) do
    if empty or part.shapes != [], do: place
  end

  # The root of a thing: the path of its first part under the node (nil
  # for a part or a figure: the node itself), and its frame in the thing.
  defp root(%World.Assembly{nodes: [{name, item, nil} | _], place: place}) do
    {inner, frame} = root(item)
    {if(inner, do: name <> "/" <> inner, else: name), Frame.compose(place, frame)}
  end

  defp root(_thing), do: {nil, Frame.identity()}

  # A light copy of a thing: each part with its ports and no meshes.
  defp light(%Part{} = p), do: %{p | shapes: []}

  defp light(%World.Assembly{nodes: nodes} = a),
    do: %{a | nodes: for({name, item, c} <- nodes, do: {name, light(item), c})}

  defp light(thing), do: thing

  # A part of the list (with no matrix yet).
  defp entry(key, node, name, roles, joint) do
    %{"key" => key, "url" => "/p/#{key}.glb", "node" => node, "part" => name, "roles" => roles, "joint" => joint}
  end

  defp roles(%Part{shapes: shapes}), do: shapes |> Enum.map(&to_string(&1.material)) |> Enum.uniq()
  defp roles(%World.Figure{materials: m}), do: m |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()

  defp matrix(frame), do: frame |> GLB.gl_frame() |> Frame.matrix()

  # --- Hashes and versions ----------------------------------------------

  defp hash(term),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(term)) |> binary_part(0, 16) |> Base.encode16(case: :lower)

  # A module of World that can be a part of a rule: not a module of the
  # service (the orders, the store, the constructions, the files). (A
  # rule calls the orders for an item in a drawing; a change of the
  # service does not change a part.)
  @service ~w(Orders Elements Construction Service MCP Engineers Log Line Guard Files Stream Supervisor Application)
           |> Enum.map(&"Elixir.World.#{&1}")

  defp rule?(module) do
    name = Atom.to_string(module)

    String.starts_with?(name, "Elixir.World.") and
      not Enum.any?(@service, &(name == &1 or String.starts_with?(name, &1 <> ".")))
  end

  # The modules of World that a module calls, again and again (with it).
  defp calls(module, seen) do
    if MapSet.member?(seen, module) do
      seen
    else
      seen = MapSet.put(seen, module)

      with {^module, beam, _} <- :code.get_object_code(module),
           {:ok, {_, [imports: imports]}} <- :beam_lib.chunks(beam, [:imports]) do
        imports
        |> Enum.map(&elem(&1, 0))
        |> Enum.uniq()
        |> Enum.filter(&rule?/1)
        |> Enum.reduce(seen, &calls/2)
      else
        _ -> seen
      end
    end
  end
end
