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
    frame `at`, `axis`, `up`), its `ports`, its `sources`;
  - `nodes`: the tree of the model, the root first. A node holds a part
    (`part`) or an item of another blueprint (`item`: an order with its
    `blueprint` and its `options`: a model of the catalog, a person, an
    animal, a drawing). It connects its port `port` to the port `at` of
    the node `to` (a name, or a port in the data: `at`, `axis`, `up`; the
    origin by default), with a `turn` and an `offset`, and can be a
    `joint` (`kind` hinge or slide, `role`, `limits`);
  - `clips`: animations of the joints: a `name`, a `length` in seconds,
    and `keys`, each a time `t` and the values of some `joints`.

  The limits keep a drawing small for the builder at the edge: 64 parts,
  256 shapes, 128 nodes, 64 points in a list, 8 clips of 64 keys, points
  within 50 m, and 3 drawings one in the other.
  """
  alias World.{Assembly, Frame, GLB, Part, Port, Shape, Vec}
  alias World.Orders.Blueprints

  @kinds ~w(appliance building electrical furniture item prop vehicle)
  @roles ~w(crank door drawer handle knob lid pedal recline slide spin stand steer suspension vane wheel)
  @shapes ~w(box cylinder sphere prism lathe tube)
  @keys ~w(name kind materials parts nodes clips sources)
  @name ~r/^[a-z0-9_]{1,40}$/
  @size 50.0
  @depth 3

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
            parts(Map.get(raw, "parts", %{}), "#{path}.parts")

        errors = errors ++ if(errors == [], do: nodes(raw, path), else: [])
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
          object(part, p, ~w(shapes ports sources), fn part ->
            required(part, "shapes", p, &list(&1, &2, 1, 64, fn s, sp -> shape(s, sp) end)) ++
              optional(part, "ports", p, &ports/2) ++ optional(part, "sources", p, &sources/2)
          end)
      end)

    if count > 256, do: errors ++ [{path, "must have at most 256 shapes in all"}], else: errors
  end

  defp parts(_v, path), do: [{path, "must be an object of at most 64 parts"}]

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
        unknown(v, [kind | ~w(material at axis up)], path) ++
          optional(v, "material", path, &material/2) ++
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
    keys = ~w(name part item to at port joint turn offset)
    base = unknown(node, keys, path) ++ required(node, "name", path, &name/2)
    name = node["name"]

    base =
      if is_binary(name) and Map.has_key?(known, name),
        do: base ++ [{"#{path}.name", "is the name of another node"}],
        else: base

    {errors, item} =
      case {node["part"], node["item"]} do
        {part, nil} when is_binary(part) ->
          if Map.has_key?(parts, part),
            do: {[], {:part, parts[part]}},
            else: {[{"#{path}.part", "is not a part of the drawing"}], nil}

        {nil, order} when is_map(order) ->
          item(order, "#{path}.item")

        _ ->
          {[{path, "must have a part or an item"}], nil}
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

  # The connection of a node to its parent: the parent, the ports, the joint.
  defp links(node, path, item, known) do
    case Map.fetch(known, node["to"]) do
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
  The assembly of a drawing of the catalog: the file
  `priv/drawings/NAME.json`. A drawing that does not check raises.
  """
  def file(name) do
    raw = Path.join([:code.priv_dir(:world), "drawings", name <> ".json"]) |> File.read!() |> JSON.decode!()

    case check(raw, name) do
      {:ok, raw} -> build(raw)
      {:error, errors} -> raise ArgumentError, "the drawing #{name} has errors: #{inspect(errors)}"
    end
  end

  @doc "The assembly of a drawing that `check/2` accepts."
  def build(raw) do
    parts = Map.new(Map.get(raw, "parts", %{}), fn {name, p} -> {name, part(name, p)} end)
    [root | rest] = raw["nodes"]

    materials =
      Map.new(Map.get(raw, "materials", %{}), fn {role, spec} ->
        spec = if spec["color"], do: Map.put(spec, "color", rgb(spec["color"])), else: spec
        {GLB.role(role), Map.merge(GLB.palette()[role], spec)}
      end)

    a =
      Assembly.new(Map.get(raw, "name", "drawing"), built(root, parts),
        root: root["name"],
        kind: String.to_existing_atom(Map.get(raw, "kind", "item")),
        materials: materials,
        sources: Map.get(raw, "sources", []),
        clips: for(c <- Map.get(raw, "clips", []), do: clip(c))
      )

    Enum.reduce(rest, a, fn node, a ->
      joint = node["joint"]

      opts =
        [
          to: node["to"],
          at: ref(node["at"]),
          port: ref(node["port"]),
          turn: Map.get(node, "turn", 0),
          offset: Map.get(node, "offset", 0)
        ] ++
          if joint,
            do: [
              kind: String.to_existing_atom(joint["kind"]),
              role: String.to_existing_atom(joint["role"]),
              limits: joint["limits"]
            ],
            else: []

      Assembly.add(a, node["name"], built(node, parts), opts)
    end)
  end

  defp built(%{"part" => name}, parts), do: parts[name]

  defp built(%{"item" => order}, _parts) do
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

  defp part(name, p) do
    ports = for {n, port} <- Map.get(p, "ports", %{}), do: new_port(n, port)
    Part.new(name, :part, Enum.map(p["shapes"], &shape/1), ports, sources: Map.get(p, "sources", []))
  end

  defp shape(s) do
    material = GLB.role(Map.get(s, "material", "gray"))
    frame = [frame: frame(s)]
    [kind] = for k <- @shapes, Map.has_key?(s, k), do: k
    d = s[kind]

    case kind do
      "box" -> Shape.box(List.to_tuple(d["from"]), List.to_tuple(d["to"]), material, frame)
      "cylinder" -> Shape.cylinder(d["radius"], d["length"], material, frame)
      "sphere" -> Shape.sphere(d["radius"], material, frame)
      "prism" -> Shape.prism(Enum.map(d["loop"], &List.to_tuple/1), d["length"], material, frame)
      "lathe" -> Shape.lathe(Enum.map(d["profile"], &List.to_tuple/1), material, frame)
      "tube" -> Shape.sweep(Enum.map(d["line"], &List.to_tuple/1), d["radius"], material, frame)
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
