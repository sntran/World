defmodule World.Drawing do
  @moduledoc """
  A drawing: a model in the data of an order (`docs/format.md`, "A
  drawing"), for a thing that has no blueprint of its own. The blueprint
  `drawing` checks it (`check/2`, each error with its path) and builds it
  (`build/1`) into a `World.Assembly`.

  - `name`, `kind` (`item` by default), `sources`;
  - `materials`: a role of the palette to its `color`, `roughness` and
    `metalness` in this model;
  - `parts`: a name to a part: its `shapes` (`box`, `cylinder`,
    `sphere`, `prism`, `lathe`, `tube`, each with its `material` and its
    frame `at`, `axis`, `up`; for its mass, a `matter` when the material
    is a color, and a `skin`: the thickness of a wall, for a tube of
    bamboo or a panel), its `ports`, its `sources`; or a standard part
    (`standard`: `"bolt M8x40"`, `"cap_screw M6x20"`, `"nut M8"`,
    `"washer M8"`, `"bearing 6204"`), with its own ports;
  - `nodes`: the tree of the model, the root first. A node holds a part
    (`part`) or an item of another blueprint (`item`: an order with its
    `blueprint` and its `options`: a model of the catalog, a person, an
    animal, a drawing). It connects its port `port` to the port `at` of
    the node `to` (a name, or a port in the data: `at`, `axis`, `up`; the
    origin by default), with a `turn` and an `offset`, and can be a
    `joint` (`kind` hinge or slide, `role`, `limits`);
  - `clips`: animations of the joints: a `name`, a `length` in seconds,
    and `keys`, each a time `t` and the values of some `joints`;
  - `extras`: the data of the model for an app (`site`, `ports`,
    `collision`, `surface`, `weathering`: `docs/format.md`).

  A node can also be an element that a person of a trade makes with a
  skill (`World.Skill`): `skill` is `{NAME: data}`, `trade` the trade of
  the person (the trade of the skill by default), `from` the nodes whose
  data it takes, and `after` the nodes that it comes after (as on a real
  site: the base, then the figure, then the cast). A skill gives the part
  of its node (or nil: a node of data only, not in the model), its data
  for the nodes that take it, and the extras of the model. A node to a
  node with no part goes to the root, the first node with a part.

  The limits keep a drawing small for the builder at the edge: 64 parts,
  256 shapes, 128 nodes, 64 points in a list, 8 clips of 64 keys, points
  within 50 m, and 3 drawings one in the other.
  """
  alias World.{Assembly, Detail, Frame, GLB, Part, Port, Shape, Vec}
  alias World.Orders.Blueprints

  @kinds ~w(appliance building electrical furniture house item prop statue tower vehicle)
  @roles ~w(crank door drawer handle knob lid open pedal recline slide spin stand steer suspension vane wheel)
  @shapes ~w(box cylinder sphere prism lathe tube)
  @standards ~w(bolt cap_screw nut washer bearing)

  # The atom of each name of a list of the checks: a drawing names only
  # these, and the atoms exist when the drawing builds.
  @atoms Map.new(@kinds ++ @roles ++ @standards ++ ~w(hinge slide), &{&1, String.to_atom(&1)})
  @keys ~w(name kind materials parts nodes clips sources extras)
  @name ~r/^[a-z0-9_]{1,40}$/
  @size 50.0
  @depth 3

  # The drawings of the catalog (`priv/drawings/NAME.json`), read when the
  # module compiles (a new file compiles the module again). Their check
  # needs the catalog (a drawing holds other models), so a test checks
  # each one (`check_all!/1`).
  @root Path.expand("../../priv/drawings", __DIR__)
  @files Path.wildcard(Path.join(@root, "*.json"))
  for f <- @files, do: @external_resource(f)
  @drawings Map.new(@files, fn f -> {Path.basename(f, ".json"), f |> File.read!() |> JSON.decode!()} end)
  @hash :erlang.md5(Enum.join(@files))

  @doc false
  def __mix_recompile__?, do: :erlang.md5(Enum.join(Path.wildcard(Path.join(@root, "*.json")))) != @hash

  @doc """
  Check a drawing. Gives `{:ok, drawing}` (the same data), or `{:error,
  errors}`: each error is `{path, message}`, with the path from `path`.
  """
  def check(raw, path) when is_map(raw) do
    depth = Process.get(:world_drawing, 0)

    if depth >= @depth do
      {:error, [{path, "must not hold more than #{@depth} drawings one in the other"}]}
    else
      Process.put(:world_drawing, depth + 1)

      try do
        errors =
          unknown(raw, @keys, path) ++
            optional(raw, "name", path, &name/2) ++
            optional(raw, "kind", path, &choice(&1, &2, @kinds)) ++
            optional(raw, "sources", path, &sources/2) ++
            optional(raw, "materials", path, &materials/2) ++
            optional(raw, "extras", path, &extras/2) ++
            parts(Map.get(raw, "parts", %{}), "#{path}.parts")

        errors = errors ++ if(errors == [], do: nodes(raw, path), else: [])
        errors = errors ++ if(errors == [], do: check_waits(raw["nodes"], path), else: [])
        if errors == [], do: {:ok, raw}, else: {:error, errors}
      after
        Process.put(:world_drawing, depth)
      end
    end
  end

  def check(_raw, path), do: {:error, [{path, "must be an object"}]}

  # --- The checks ---------------------------------------------------------------------------

  defp unknown(map, keys, path),
    do: for(k <- Enum.sort(Map.keys(map)), k not in keys, do: {"#{path}.#{k}", "is not a key"})

  defp optional(map, key, path, check) do
    case Map.fetch(map, key) do
      {:ok, v} -> check.(v, "#{path}.#{key}")
      :error -> []
    end
  end

  defp required(map, key, path, check) do
    case Map.fetch(map, key) do
      {:ok, v} -> check.(v, "#{path}.#{key}")
      :error -> [{"#{path}.#{key}", "is required"}]
    end
  end

  defp name(v, path),
    do: if(is_binary(v) and v =~ @name, do: [], else: [{path, "must be a name: a to z, 0 to 9 and _, at most 40"}])

  defp choice(v, path, values),
    do: if(v in values, do: [], else: [{path, "must be one of: #{Enum.join(values, ", ")}"}])

  defp number(v, path, lo, hi) do
    if is_number(v) and v >= lo and v <= hi, do: [], else: [{path, "must be a number from #{lo} to #{hi}"}]
  end

  defp positive(v, path),
    do: if(is_number(v) and v > 0 and v <= @size, do: [], else: [{path, "must be a length from 0 to #{@size} m"}])

  defp point(v, path) do
    if match?([_, _, _], v) and Enum.all?(v, &(is_number(&1) and abs(&1) <= @size)),
      do: [],
      else: [{path, "must be a point [x, y, z] in meters, at most #{@size} m"}]
  end

  defp direction(v, path) do
    case point(v, path) do
      [] -> if Vec.len(Vec.float(List.to_tuple(v))) > 1.0e-6, do: [], else: [{path, "must not be zero"}]
      errors -> errors
    end
  end

  defp list(v, path, lo, hi, check) do
    if is_list(v) and length(v) >= lo and length(v) <= hi,
      do: v |> Enum.with_index() |> Enum.flat_map(fn {x, i} -> check.(x, "#{path}.#{i}") end),
      else: [{path, "must be a list of #{lo} to #{hi} items"}]
  end

  defp object(v, path, keys, check) do
    if is_map(v), do: unknown(v, keys, path) ++ check.(v), else: [{path, "must be an object"}]
  end

  defp extras(v, path), do: if(is_map(v), do: [], else: [{path, "must be an object"}])

  defp sources(v, path),
    do:
      list(v, path, 0, 16, fn s, p ->
        if is_binary(s) and byte_size(s) <= 500, do: [], else: [{p, "must be a text of at most 500 bytes"}]
      end)

  defp materials(v, path) when is_map(v) do
    roles = GLB.palette() |> Map.keys() |> Enum.sort()

    Enum.flat_map(Enum.sort(v), fn {role, spec} ->
      p = "#{path}.#{role}"

      if role in roles do
        object(spec, p, ~w(color roughness metalness), fn spec ->
          optional(spec, "color", p, &color/2) ++
            optional(spec, "roughness", p, &number(&1, &2, 0, 1)) ++
            optional(spec, "metalness", p, &number(&1, &2, 0, 1))
        end)
      else
        [{p, "must be a role of the palette: #{Enum.join(roles, ", ")}"}]
      end
    end)
  end

  defp materials(_v, path), do: [{path, "must be an object"}]

  defp color(v, path),
    do: if(is_binary(v) and v =~ ~r/^#[0-9a-fA-F]{6}$/, do: [], else: [{path, "must be a color #rrggbb"}])

  defp material(v, path), do: choice(v, path, GLB.palette() |> Map.keys() |> Enum.sort())

  defp parts(v, path) when is_map(v) and map_size(v) <= 64 do
    count = v |> Map.values() |> Enum.map(&if(is_map(&1), do: length(List.wrap(&1["shapes"])), else: 0)) |> Enum.sum()

    errors =
      Enum.flat_map(Enum.sort(v), fn {name, part} ->
        p = "#{path}.#{name}"

        name(name, p) ++
          case part do
            %{"standard" => _} ->
              object(part, p, ~w(standard), &required(&1, "standard", p, fn v, sp -> standard(v, sp) end))

            _ ->
              object(part, p, ~w(shapes ports sources), fn part ->
                required(part, "shapes", p, &list(&1, &2, 1, 64, fn s, sp -> shape(s, sp) end)) ++
                  optional(part, "ports", p, &ports/2) ++ optional(part, "sources", p, &sources/2)
              end)
          end
      end)

    if count > 256, do: errors ++ [{path, "must have at most 256 shapes in all"}], else: errors
  end

  defp parts(_v, path), do: [{path, "must be an object of at most 64 parts"}]

  # A standard part by its kind and its name: "bolt M8x40".
  defp standard(v, path) do
    with true <- is_binary(v),
         [kind, _name] <- String.split(v, " ", parts: 2),
         true <- kind in @standards,
         %Part{} <- standard_part(v) do
      []
    else
      _ ->
        [{path, "must be a standard part: #{Enum.join(@standards, ", ")} and its name, as \"bolt M8x40\""}]
    end
  rescue
    _ -> [{path, "is not a size of the standard: #{v}"}]
  end

  defp standard_part(v) do
    [kind, name] = String.split(v, " ", parts: 2)
    World.Standards.part({Map.fetch!(@atoms, kind), name})
  end

  defp ports(v, path) when is_map(v),
    do:
      Enum.flat_map(Enum.sort(v), fn {name, port} -> name(name, "#{path}.#{name}") ++ port(port, "#{path}.#{name}") end)

  defp ports(_v, path), do: [{path, "must be an object"}]

  defp port(v, path) do
    object(v, path, ~w(at axis up), fn port ->
      required(port, "at", path, &point/2) ++
        optional(port, "axis", path, &direction/2) ++ optional(port, "up", path, &direction/2)
    end)
  end

  defp shape(v, path) when is_map(v) do
    case for k <- @shapes, Map.has_key?(v, k), do: k do
      [kind] ->
        unknown(v, [kind | ~w(material matter skin at axis up)], path) ++
          optional(v, "material", path, &material/2) ++
          optional(v, "matter", path, &choice(&1, &2, World.Mass.materials())) ++
          optional(v, "skin", path, &number(&1, &2, 0.0001, 0.1)) ++
          optional(v, "at", path, &point/2) ++
          optional(v, "axis", path, &direction/2) ++
          optional(v, "up", path, &direction/2) ++ dims(kind, v[kind], "#{path}.#{kind}")

      _ ->
        [{path, "must have one shape: #{Enum.join(@shapes, ", ")}"}]
    end
  end

  defp shape(_v, path), do: [{path, "must be an object"}]

  defp dims("box", v, path),
    do:
      object(
        v,
        path,
        ~w(from to),
        &(required(&1, "from", path, fn x, p -> point(x, p) end) ++ required(&1, "to", path, fn x, p -> point(x, p) end))
      )

  defp dims("sphere", v, path),
    do: object(v, path, ~w(radius), &required(&1, "radius", path, fn x, p -> positive(x, p) end))

  defp dims("cylinder", v, path),
    do:
      object(
        v,
        path,
        ~w(radius length),
        &(required(&1, "radius", path, fn x, p -> positive(x, p) end) ++
            required(&1, "length", path, fn x, p -> positive(x, p) end))
      )

  defp dims("prism", v, path),
    do:
      object(v, path, ~w(loop length), fn d ->
        required(d, "loop", path, &list(&1, &2, 3, 64, fn x, p -> pair(x, p, -@size) end)) ++
          required(d, "length", path, &positive/2)
      end)

  defp dims("lathe", v, path),
    do:
      object(
        v,
        path,
        ~w(profile),
        &required(&1, "profile", path, fn x, p -> list(x, p, 2, 64, fn y, q -> pair(y, q, 0) end) end)
      )

  defp dims("tube", v, path),
    do:
      object(v, path, ~w(line radius), fn d ->
        required(d, "line", path, &list(&1, &2, 2, 64, fn x, p -> point(x, p) end)) ++
          required(d, "radius", path, &positive/2)
      end)

  # A point of a plane: [x, y] (a loop), or [r, z] with r from 0 (a profile).
  defp pair(v, path, lo) do
    if match?([a, b] when is_number(a) and is_number(b) and a >= lo and a <= @size and abs(b) <= @size, v),
      do: [],
      else: [{path, "must be [a, b]: two numbers in meters, the first from #{lo}"}]
  end

  defp nodes(raw, path) do
    case Map.get(raw, "nodes") do
      nodes when is_list(nodes) and nodes != [] and length(nodes) <= 128 ->
        parts = Map.get(raw, "parts", %{})

        {errors, known} =
          nodes
          |> Enum.with_index()
          |> Enum.reduce({[], %{}}, fn {node, i}, {errors, known} ->
            p = "#{path}.nodes.#{i}"
            {more, item} = node(node, p, i, parts, known)
            name = is_map(node) && node["name"]
            # A node with an error is known still: the errors of its
            # children are their own.
            known =
              if is_binary(name) and not Map.has_key?(known, name), do: Map.put(known, name, {item, node}), else: known

            known = if i == 0, do: Map.put(known, :root, name), else: known

            {errors ++ more, known}
          end)

        errors ++ if(errors == [], do: optional(raw, "clips", path, &clips(&1, &2, joints(known))), else: [])

      _ ->
        [{"#{path}.nodes", "must be a list of 1 to 128 nodes, the root first"}]
    end
  end

  defp joints(known), do: for({name, {_, node}} <- known, Map.has_key?(node, "joint"), do: name)

  # A node: its errors, and its item (the part, or the item of the order).
  defp node(node, path, i, parts, known) when is_map(node) do
    keys = ~w(name part item skill trade after from to at port joint turn offset)

    base =
      unknown(node, keys, path) ++
        required(node, "name", path, &name/2) ++ optional(node, "trade", path, &choice(&1, &2, World.Plan.trades()))

    name = node["name"]

    base =
      if is_binary(name) and Map.has_key?(known, name),
        do: base ++ [{"#{path}.name", "is the name of another node"}],
        else: base

    {errors, item} =
      case {node["part"], node["item"], node["skill"]} do
        {part, nil, nil} when is_binary(part) ->
          if Map.has_key?(parts, part),
            do: {[], {:part, parts[part]}},
            else: {[{"#{path}.part", "is not a part of the drawing"}], nil}

        {nil, order, nil} when is_map(order) ->
          item(order, "#{path}.item")

        {nil, nil, skill} ->
          skill(skill, "#{path}.skill")

        _ ->
          {[{path, "must have a part, an item or a skill"}], nil}
      end

    root =
      if i == 0,
        do:
          for(k <- ~w(to at port joint turn offset), Map.has_key?(node, k), do: {"#{path}.#{k}", "is not for the root"}),
        else: []

    links = if i > 0 and errors == [], do: links(node, path, item, known), else: []
    {base ++ errors ++ root ++ links, item}
  end

  defp node(_node, path, _i, _parts, _known), do: {[{path, "must be an object"}], nil}

  # An item of another blueprint: the order checks. The item is built (at
  # far) only to know a port of it by its name.
  defp item(order, path) do
    case Map.keys(order) -- ["blueprint", "options"] do
      [] ->
        case World.Orders.check(order) do
          {:ok, full} ->
            {[], {:item, full}}

          {:error, errors} ->
            {for(%{"path" => p, "message" => m} <- errors, do: {"#{path}.#{p}", m}), nil}
        end

      extra ->
        {for(k <- Enum.sort(extra), do: {"#{path}.#{k}", "is not a key: an item has only blueprint and options"}), nil}
    end
  end

  # A skill of a trade with its data: `{NAME: data}`.
  defp skill(v, path) do
    with %{} <- v,
         [{name, data}] <- Map.to_list(v),
         {:ok, mod} <- World.Skills.fetch(name) do
      {mod.check(data, "#{path}.#{name}"), {:skill, mod}}
    else
      _ -> {[{path, "must be one skill and its data: #{Enum.join(World.Skills.names(), ", ")}"}], nil}
    end
  end

  # The waits of the nodes: `after` and `from` name nodes of the drawing,
  # and no node waits for itself through them (a graph with no cycle).
  defp check_waits(nodes, path) do
    names = for n <- nodes, do: n["name"]

    errors =
      for {n, i} <- Enum.with_index(nodes),
          key <- ~w(after from),
          Map.has_key?(n, key),
          p = "#{path}.nodes.#{i}.#{key}" do
        case n[key] do
          l when is_list(l) and length(l) <= 128 ->
            for(x <- l, x not in names, do: {p, "must be the names of nodes of the drawing"}) |> Enum.take(1)

          _ ->
            [{p, "must be a list of the names of nodes"}]
        end
      end

    case List.flatten(errors) do
      [] -> cycle(nodes, path)
      errors -> errors
    end
  end

  defp cycle(nodes, path) do
    g = graph(nodes)

    if :graph.is_acyclic(g) do
      []
    else
      # The first node of the drawing that is on a cycle.
      {cycle, i} =
        nodes |> Enum.with_index() |> Enum.find_value(fn {n, i} -> (c = :graph.get_cycle(g, n["name"])) && {c, i} end)

      [{"#{path}.nodes.#{i}", "must not wait for itself: #{Enum.join(cycle, ", ")}"}]
    end
  end

  # The graph of the waits: an edge from each node to each node that waits for it.
  defp graph(nodes) do
    g = Enum.reduce(nodes, :graph.new(), &:graph.add_vertex(&2, &1["name"]))
    root = hd(nodes)["name"]
    Enum.reduce(nodes, g, fn n, g -> Enum.reduce(waits(n, root), g, &:graph.add_edge(&2, &1, n["name"])) end)
  end

  @doc """
  The names of the nodes that a node waits for: its parent (the root
  `root` when it has none), its `after` and its `from`.
  """
  def waits(node, root) do
    parent = if node["name"] == root, do: [], else: [node["to"] || root]
    Enum.uniq(parent ++ Map.get(node, "after", []) ++ Map.get(node, "from", []))
  end

  # The connection of a node to its parent: the parent, the ports, the joint.
  defp links(node, path, item, known) do
    case Map.fetch(known, node["to"] || known[:root]) do
      {:ok, {parent, _}} ->
        port(node, "at", path, parent) ++
          port(node, "port", path, item) ++
          optional(node, "joint", path, &joint/2) ++
          optional(node, "turn", path, &number(&1, &2, -360, 360)) ++
          optional(node, "offset", path, &number(&1, &2, -@size, @size))

      :error ->
        [{"#{path}.to", "must be the name of a node before it"}]
    end
  end

  defp port(_node, _key, _path, nil), do: []

  defp port(node, key, path, item) do
    p = "#{path}.#{key}"

    case Map.get(node, key) do
      nil -> []
      %{} = port -> port(port, p)
      name when is_binary(name) -> if has_port?(item, name), do: [], else: [{p, "is not a port of the #{kind(item)}"}]
      _ -> [{p, "must be the name of a port, or a port"}]
    end
  end

  defp kind({:part, _}), do: "part"
  defp kind({:item, _}), do: "item"

  # A part that a skill makes is not known before: any name of a port.
  defp has_port?({:skill, _}, _name), do: true

  defp has_port?({:part, %{"standard" => s}}, name), do: Map.has_key?(standard_part(s).ports, name)
  defp has_port?({:part, part}, name), do: Map.has_key?(Map.get(part, "ports", %{}), name)

  defp has_port?({:item, full}, name) do
    {:ok, blueprint} = Blueprints.fetch(full["blueprint"])
    _ = Assembly.item_port_frame(World.Detail.with(:far, fn -> blueprint.build.(full["options"]) end), name)
    true
  rescue
    ArgumentError -> false
  end

  defp joint(v, path) do
    object(v, path, ~w(kind role limits), fn j ->
      required(j, "kind", path, &choice(&1, &2, ~w(hinge slide))) ++
        required(j, "role", path, &choice(&1, &2, @roles)) ++
        optional(j, "limits", path, fn l, p ->
          if match?([a, b] when is_number(a) and is_number(b) and a <= b, l), do: [], else: [{p, "must be [min, max]"}]
        end)
    end)
  end

  defp clips(v, path, joints) do
    list(v, path, 0, 8, fn clip, p ->
      object(clip, p, ~w(name length keys), fn c ->
        length = c["length"]

        required(c, "name", p, &name/2) ++
          required(c, "length", p, &number(&1, &2, 0.1, 600)) ++
          required(c, "keys", p, &list(&1, &2, 2, 64, fn key, kp -> key(key, kp, length, joints) end)) ++
          optional(c, "keys", p, &order/2)
      end)
    end)
  end

  # The times of the keys go up.
  defp order(keys, path) do
    times = for %{"t" => t} <- List.wrap(keys), is_number(t), do: t
    if times == Enum.uniq(Enum.sort(times)), do: [], else: [{path, "must have keys at times that go up"}]
  end

  defp key(v, path, length, joints) do
    object(v, path, ~w(t joints), fn k ->
      required(k, "t", path, &number(&1, &2, 0, if(is_number(length), do: length, else: 600))) ++
        required(k, "joints", path, fn js, p ->
          if is_map(js),
            do:
              Enum.flat_map(Enum.sort(js), fn {name, value} ->
                if(name in joints,
                  do: [],
                  else: [{"#{p}.#{name}", "is not a joint of the drawing: #{Enum.join(Enum.sort(joints), ", ")}"}]
                ) ++
                  if(is_number(value), do: [], else: [{"#{p}.#{name}", "must be a number"}])
              end),
            else: [{p, "must be an object"}]
        end)
    end)
  end

  # --- The build ----------------------------------------------------------------------------

  @doc """
  The assembly of a model of the catalog in `priv/drawings/NAME.json`: a
  drawing, or an order of a blueprint (a blueprint in data with its
  options: the statue on Núi Nhỏ). A name with no file raises.
  """
  def file(name) do
    case raw(name) || raise(ArgumentError, "no drawing #{inspect(name)}") do
      %{"blueprint" => _} = order ->
        {:ok, full} = World.Orders.check(order)
        {:ok, blueprint} = Blueprints.fetch(full["blueprint"])
        blueprint.build.(full["options"])

      raw ->
        {:ok, raw} = check(raw, name)
        build(raw)
    end
  end

  @doc "The data of the file `priv/drawings/NAME.json`, or nil."
  def raw(name), do: Map.get(@drawings, name)

  @doc "The names of the drawings of the catalog, in order."
  def names, do: @drawings |> Map.keys() |> Enum.sort()

  @doc """
  The names of the drawings (of `drawings`, by default the drawings of the
  catalog), after a check of each one (an order of a blueprint with
  `World.Orders.check/1`): a drawing with errors raises an
  `ArgumentError` with its errors.
  """
  def check_all!(drawings \\ @drawings) do
    for {name, raw} <- Enum.sort(drawings) do
      result = if raw["blueprint"], do: World.Orders.check(raw), else: check(raw, name)

      case result do
        {:ok, _} -> name
        {:error, errors} -> raise ArgumentError, "the drawing #{name} has errors: #{inspect(errors)}"
      end
    end
  end

  @doc """
  The drawing of a blueprint in data (`World.Orders.Blueprint.from_data/1`)
  with the options of an order: each `{"param": NAME}` takes the value of
  its option, and each `{"sum": [...]}` the sum of its numbers. The texts
  of the option of the type `sources`, in the order of their names, go
  after the sources of the drawing, and the `sizes` of the blueprint go
  into its extras (`"sizes"`): each with its value, its unit and its
  source, or `World.Sizes.none/0`. A size with `row` gives each item of a
  list as the list of the values of its fields.
  """
  def fill(blueprint, options) do
    drawing = put(blueprint["drawing"], options)
    params = Map.get(blueprint, "params", [])
    sources = Enum.find_value(params, %{}, &(&1["type"] == "sources" && options[&1["name"]]))

    sizes =
      for s <- Map.get(blueprint, "sizes", []), v = options[s["name"]], v != nil do
        v = if s["row"], do: for(item <- v, do: Enum.map(s["row"], &item[&1])), else: v
        entry = %{"name" => s["name"], "value" => v, "source" => sources[s["name"]] || World.Sizes.none()}
        if s["unit"], do: Map.put(entry, "unit", s["unit"]), else: entry
      end

    texts = for {_, v} <- Enum.sort(sources), do: v
    drawing = Map.update(drawing, "sources", texts, &(&1 ++ texts))
    if sizes == [], do: drawing, else: Map.update(drawing, "extras", %{"sizes" => sizes}, &Map.put(&1, "sizes", sizes))
  end

  defp put(%{"param" => name} = m, o) when map_size(m) == 1, do: Map.fetch!(o, name)
  defp put(%{"sum" => l} = m, o) when map_size(m) == 1, do: l |> Enum.map(&put(&1, o)) |> Enum.sum()
  defp put(%{} = m, o), do: Map.new(m, fn {k, v} -> {k, put(v, o)} end)
  defp put(l, o) when is_list(l), do: Enum.map(l, &put(&1, o))
  defp put(v, _o), do: v

  @doc """
  The assembly of a drawing that `check/2` accepts, at the level of
  detail of the process: each node made in the order of its waits
  (`make/3`), then put together (`assemble/2`).
  """
  def build(raw) do
    g = graph(raw["nodes"])

    made =
      Enum.reduce(:graph.topsort(g), %{}, fn name, made ->
        Map.put(made, name, make(raw, name, inputs(raw, name, made)))
      end)

    assemble(raw, made)
  end

  @doc "The names of the nodes in the order of their waits: each node after the nodes that it waits for."
  def order(raw), do: :graph.topsort(graph(raw["nodes"]))

  @doc """
  The key of each node of a drawing, by its name: a hash of its data and
  of the keys of the nodes that it waits for. A change of a node changes
  the key of each node that waits for it.
  """
  def keys(raw) do
    root = hd(raw["nodes"])["name"]
    by_name = Map.new(raw["nodes"], &{&1["name"], &1})

    Enum.reduce(order(raw), %{}, fn name, keys ->
      node = by_name[name]
      waits = for w <- waits(node, root), do: keys[w]
      Map.put(keys, name, :erlang.phash2({Map.delete(node, "name"), waits}, 4_294_967_296))
    end)
  end

  @doc "The data of the nodes `from` of a node, by their names, from the nodes made."
  def inputs(raw, name, made) do
    node = Enum.find(raw["nodes"], &(&1["name"] == name))
    Map.new(Map.get(node, "from", []), &{&1, elem(made[&1], 1)})
  end

  @doc """
  Make one node of a drawing, at the level of detail of the process, with
  the data of its nodes `from` (`inputs`): `{thing, data, extras}`. The
  thing is the part or the item of the node, or what its skill makes (nil:
  a node of data only).
  """
  def make(raw, name, inputs) do
    node = Enum.find(raw["nodes"], &(&1["name"] == name))

    case node do
      %{"skill" => skill} ->
        [{skill, data}] = Map.to_list(skill)
        {:ok, mod} = World.Skills.fetch(skill)
        context = %{level: Detail.level(), sources: Map.get(raw, "sources", []), from: Map.get(node, "from", [])}
        mod.make(data, inputs, context)

      %{"part" => p} ->
        {part(p, raw["parts"][p]), %{}, %{}}

      _ ->
        {built(node), %{}, %{}}
    end
  end

  @doc """
  The triangles of a drawing at a level, an estimate before the people
  make it: the estimate of each skill (`World.Skill`), and the faces of
  each part and item (each of n corners is n - 2).
  """
  def estimate(raw, level) do
    for node <- raw["nodes"], reduce: 0 do
      n ->
        case node do
          %{"skill" => skill} ->
            [{skill, data}] = Map.to_list(skill)
            {:ok, mod} = World.Skills.fetch(skill)
            n + mod.estimate(data, level)

          _ ->
            {thing, _, _} = Detail.with(level, fn -> make(raw, node["name"], %{}) end)
            n + World.Construction.estimate(thing, level)
        end
    end
  end

  @doc """
  The assembly of the nodes made (`made`: a name to `{thing, data,
  extras}`), in the order of the nodes: each node with a thing, the extras
  of the drawing and of each node in order. A node to a node with no
  thing goes to the parent of that node, or to the root.
  """
  def assemble(raw, made) do
    nodes = for n <- raw["nodes"], Map.has_key?(made, n["name"]), elem(made[n["name"]], 0) != nil, do: n
    [root | rest] = nodes
    by_name = Map.new(raw["nodes"], &{&1["name"], &1})
    thing = fn n -> elem(made[n["name"]], 0) end

    extras =
      Enum.reduce(
        raw["nodes"],
        extras(Map.get(raw, "extras", %{})),
        &Map.merge(&2, elem(Map.get(made, &1["name"], {nil, nil, %{}}), 2))
      )

    materials =
      Map.new(Map.get(raw, "materials", %{}), fn {role, spec} ->
        spec = if spec["color"], do: Map.put(spec, "color", rgb(spec["color"])), else: spec
        {GLB.role(role), Map.merge(GLB.palette()[role], spec)}
      end)

    a =
      Assembly.new(Map.get(raw, "name", "drawing"), thing.(root),
        root: root["name"],
        kind: Map.fetch!(@atoms, Map.get(raw, "kind", "item")),
        materials: materials,
        sources: Map.get(raw, "sources", []),
        clips: for(c <- Map.get(raw, "clips", []), do: clip(c)),
        extras: extras
      )

    Enum.reduce(rest, a, fn node, a ->
      joint = node["joint"]

      opts =
        [
          to: parent(node["to"], by_name, made, root["name"]),
          at: ref(node["at"]),
          port: ref(node["port"]),
          turn: Map.get(node, "turn", 0),
          offset: Map.get(node, "offset", 0)
        ] ++
          if joint,
            do: [
              kind: Map.fetch!(@atoms, joint["kind"]),
              role: Map.fetch!(@atoms, joint["role"]),
              limits: joint["limits"]
            ],
            else: []

      Assembly.add(a, node["name"], thing.(node), opts)
    end)
  end

  # The node to connect to: the parent, or the nearest node over it with a
  # thing, or the root.
  defp parent(nil, _by_name, _made, root), do: root

  defp parent(name, by_name, made, root) do
    case made[name] do
      {nil, _, _} -> parent(by_name[name]["to"], by_name, made, root)
      _ -> name
    end
  end

  # The extras of the data: the points of the ports and of the collision
  # boxes as tuples (`World.Build`).
  defp extras(e) do
    tuples = fn m, keys ->
      Map.new(m, fn {k, v} -> {k, if(k in keys and is_list(v), do: List.to_tuple(v), else: v)} end)
    end

    e
    |> Map.replace_lazy("ports", fn ps -> for(p <- ps, do: tuples.(p, ~w(at normal))) end)
    |> Map.replace_lazy("collision", fn bs -> for(b <- bs, do: tuples.(b, ~w(at size axis up))) end)
  end

  defp built(%{"item" => order}) do
    {:ok, full} = World.Orders.check(order)
    {:ok, blueprint} = Blueprints.fetch(full["blueprint"])
    blueprint.build.(full["options"])
  end

  defp ref(nil), do: Port.new("origin", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})
  defp ref(name) when is_binary(name), do: name
  defp ref(%{} = p), do: new_port("port", p)

  defp new_port(name, p) do
    axis = List.to_tuple(Map.get(p, "axis", [0, 0, 1]))
    up = p["up"] && List.to_tuple(p["up"])
    up = if up && Vec.len(Vec.cross(Vec.float(up), Vec.float(axis))) > 1.0e-6, do: up
    Port.new(name, List.to_tuple(p["at"]), axis, up)
  end

  defp part(_name, %{"standard" => s}), do: standard_part(s)

  defp part(name, p) do
    ports = for {n, port} <- Map.get(p, "ports", %{}), do: new_port(n, port)
    Part.new(name, :part, Enum.map(p["shapes"], &shape/1), ports, sources: Map.get(p, "sources", []))
  end

  defp shape(s) do
    material = GLB.role(Map.get(s, "material", "gray"))
    frame = [frame: frame(s)]
    [kind] = for k <- @shapes, Map.has_key?(s, k), do: k
    d = s[kind]

    mesh =
      case kind do
        "box" -> Shape.box(List.to_tuple(d["from"]), List.to_tuple(d["to"]), material, frame)
        "cylinder" -> Shape.cylinder(d["radius"], d["length"], material, frame)
        "sphere" -> Shape.sphere(d["radius"], material, frame)
        "prism" -> Shape.prism(Enum.map(d["loop"], &List.to_tuple/1), d["length"], material, frame)
        "lathe" -> Shape.lathe(Enum.map(d["profile"], &List.to_tuple/1), material, frame)
        "tube" -> Shape.sweep(Enum.map(d["line"], &List.to_tuple/1), d["radius"], material, frame)
      end

    # The name is one of the list of `World.Mass.materials/0` (the check).
    matter = if m = s["matter"], do: String.to_atom(m), else: material

    case s["skin"] do
      nil -> if s["matter"], do: World.Mesh.matter(mesh, matter), else: mesh
      t -> World.Mesh.skin(mesh, t, matter)
    end
  end

  # The frame of a shape: its origin at `at`, its z on `axis`, its y on
  # `up` (any direction at a right angle to the axis by default).
  defp frame(s) do
    if Map.has_key?(s, "at") or Map.has_key?(s, "axis"),
      do: Port.frame(new_port("shape", Map.put_new(s, "at", [0, 0, 0]))),
      else: Frame.identity()
  end

  defp clip(c) do
    keys =
      c["keys"]
      |> Enum.map(&{&1["t"] / 1, Map.new(&1["joints"], fn {k, v} -> {k, v / 1} end)})
      |> Enum.sort_by(&elem(&1, 0))

    %{name: c["name"], length: c["length"] / 1, keys: keys}
  end

  defp rgb("#" <> hex), do: for(<<c::binary-size(2) <- hex>>, do: String.to_integer(c, 16))
end
