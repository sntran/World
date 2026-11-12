defmodule World.Build do
  @moduledoc """
  The build of a model (a part or an assembly) into a `World.Scene`, at a
  level of detail and in a pose, and the list of its parts.

  - The parts that connect with `:fixed` go into the node of their
    parent. Each joint (`:hinge`, `:slide`) is a node: its frame is the
    port of its parent, and it turns or moves along its own z axis (the
    y axis in glTF).
  - The levels (`docs/format.md`, "The levels of detail"): `:near` has
    each part; `:mid` drops the parts shorter than 2 cm or thinner than
    3 mm, and the parts `inside`; `:far` drops the parts shorter than
    10 cm or thinner than 1 cm. Each level smooths one step less. The
    root part of the model stays at each level. A part with `detail: :low`
    is only in mid and far: it stands in for many small parts (one wall
    in place of its bricks).
  """
  alias World.{Assembly, Detail, Figure, Frame, GLB, Joint, Mesh, Mirror, Part, Port, Scene, Shape, Vec}
  alias World.Assembly.Connection

  @limits %{near: {0.0, 0.0}, mid: {0.02, 0.003}, far: {0.10, 0.01}}

  # The scale of a mirror, and the least copies of a mesh in one node for
  # instances.
  @mirror {-1.0, 1.0, 1.0}
  @instances 16
  @share 100

  @doc """
  The scene of a model. The options: `level` (`:near`, `:mid` or `:far`),
  `pose` (a map of a joint name to its value: degrees or meters),
  `targets` (a map of a limb of a figure to the point of its end, in the
  axes of the figure: `World.Limb`), and
  `split` (`true`: each part in a node of its own, with the id of its task
  of `World.Plan.flat/1` in the `"task"` of its extras, for the replay of
  a run), `instances` (`false`: no node with instances, for an app that
  does not read `EXT_mesh_gpu_instancing`), `triangles` (the triangles
  of meshes that are made already) and `parallel` (`true`: a process for
  each material, for the join of a construction).

  A mesh of #{@share} triangles or more that is in the model more than
  once (a wheel, a shoe and its mirror) is in the scene once: each part
  with it is a node with its frame, and the nodes share the mesh. A
  mirror is a scale of -1 on x. #{@instances} copies or more of a mesh
  in one node (a wall of bricks) are one node with instances.
  """
  def scene(item, opts \\ []) do
    # The triangles that the people of a construction made (a map of a
    # mesh to its triangles): the build takes them, and makes the others.
    old = Process.put(:world_triangles, Keyword.get(opts, :triangles, %{}))
    parallel = Process.put(:world_parallel, Keyword.get(opts, :parallel, false))

    try do
      build(item, opts)
    after
      restore(:world_triangles, old)
      restore(:world_parallel, parallel)
    end
  end

  defp restore(key, old), do: if(old == nil, do: Process.delete(key), else: Process.put(key, old))

  # The texture of a role (`World.Textures`) at the level of the scene: its
  # images at near, none at mid and far. With `panel` [u0, v0, u1, v1]
  # (in the UVs in metres of World.Surface), the image is once on that
  # rectangle: u0 at its column 0, v0 at its row 0.
  defp textures(materials, level) do
    Map.new(materials, fn {role, spec} ->
      {panel, spec} = Map.pop(spec, "panel")

      case Map.pop(spec, "texture") do
        {nil, _} -> {role, spec}
        {name, rest} -> {role, rest |> Map.merge(World.Textures.spec(name, level) || %{}) |> on_panel(panel)}
      end
    end)
  end

  defp on_panel(spec, [u0, v0, u1, v1]) when is_map_key(spec, "image") do
    {su, sv} = {1 / (u1 - u0), 1 / (v1 - v0)}
    Map.put(spec, "image_transform", %{"scale" => [su, sv], "offset" => [-u0 * su, -v0 * sv]})
  end

  defp on_panel(spec, _panel), do: spec

  defp build(item, opts) do
    level = Keyword.get(opts, :level, :near)
    pose = Keyword.get(opts, :pose, %{})
    targets = Keyword.get(opts, :targets, %{})
    name = item.name
    acc = walk(keep_root(item), Frame.identity(), 0, start(item, targets), level, pose)
    # A part that stretches to a node that is not in the item (a part of
    # a model alone, as a person makes it) stays at rest.
    names = MapSet.new(acc.nodes, & &1.name)

    {stretches, _alone} =
      Enum.split_with(acc.stretches, fn {_, p, _} -> MapSet.member?(names, p.params["stretch"]["to"]) end)

    acc = %{acc | stretches: stretches}
    skinned = MapSet.new(stretches, fn {_, p, _} -> p end)

    fixed = %{
      acc
      | parts:
          Map.new(acc.parts, fn {i, ps} -> {i, Enum.reject(ps, fn {_, p, _} -> MapSet.member?(skinned, p) end)} end)
    }

    {nodes, _} = finish(fixed, {Keyword.get(opts, :split, false), Keyword.get(opts, :instances, true)})
    {nodes, skins} = stretched(nodes, acc.skins, Enum.reverse(acc.stretches), acc.moves)

    materials = textures(Map.merge(Map.get(item, :materials, %{}), acc.materials), level)
    animations = join(acc.animations ++ Enum.map(acc.clips, &clip(&1, acc.moves)))
    scene = %Scene{name: name, nodes: nodes, skins: skins, animations: animations, materials: materials}
    {lo, hi} = if Scene.triangles(scene) > 0, do: Scene.bounds(scene), else: {{0.0, 0.0, 0.0}, {0.0, 0.0, 0.0}}
    size = Vec.sub(hi, lo)

    extras = %{
      "name" => name,
      "kind" => Atom.to_string(Map.get(item, :kind, :part)),
      "level" => Atom.to_string(level),
      "size" => for(v <- Tuple.to_list(size), do: Float.round(v / 1, 4)),
      "sources" => Map.get(item, :sources, []),
      "joints" => for(n <- nodes, n.extras["role"], do: n.name) ++ acc.joints,
      "limbs" => acc.limbs
    }

    # The ports of the small parts go into the list of the parts
    # (`parts_file/2`), not into the GLB; the collision boxes are nodes.
    own = Map.get(item, :extras, %{})
    extras = Map.merge(extras, Map.drop(own, ["ports", "collision"]))

    scene =
      case extras do
        %{"surface" => %{"corners" => corners}} -> %{World.Surface.apply(scene, corners) | extras: extras}
        _ -> %{scene | extras: extras}
      end

    collision(scene, Map.get(own, "collision", []))
  end

  # The collision boxes of a model (a house, W20 of Vũng Tàu): each a node
  # of its own with the name `NAME-colonly` (Godot makes a collision
  # shape of such a node, and shows no mesh), a box of the role
  # `collision`, and `extras.collision` and `extras.size` (in glTF) for an
  # app that reads them. A box is `%{"name", "at", "size"}` in the axes of
  # the model, with `axis` and `up` (its z and y axes) when it is turned,
  # and `node` (the name of the node that it moves with: a shutter). They
  # are not in the size of the model, and not in its triangles
  # (`World.Scene.triangles/1`).
  defp collision(scene, []), do: scene

  defp collision(scene, boxes) do
    frames = Scene.world_frames(scene)
    index = scene.nodes |> Enum.with_index() |> Map.new(fn {n, i} -> {n.name, i} end)

    nodes =
      for b <- boxes do
        {sx, sy, sz} = b["size"]
        at = Frame.new(b["at"], Map.get(b, "axis", {0.0, 0.0, 1.0}), Map.get(b, "up", {0.0, 1.0, 0.0}))
        parent = Map.get(index, b["node"], 0)
        box = Shape.box({-sx / 2, -sy / 2, -sz / 2}, {sx / 2, sy / 2, sz / 2}, :collision)

        %Scene.Node{
          name: b["name"] <> "-colonly",
          parent: parent,
          frame: Frame.compose(Frame.invert(frames[parent]), at),
          primitives: [Scene.primitive(:collision, Mesh.triangles(box))],
          extras: %{"collision" => "box", "size" => Enum.map([sx, sz, sy], &Float.round(&1 / 1, 4))}
        }
      end

    %{scene | nodes: scene.nodes ++ nodes}
  end

  # The start of a walk of a model: the root node, and no parts yet.
  defp start(item, targets) do
    %{
      nodes: [%Scene.Node{name: item.name}],
      parts: %{0 => []},
      skins: [],
      animations: [],
      materials: %{},
      joints: [],
      limbs: [],
      moves: %{},
      clips: [],
      stretches: [],
      targets: targets,
      path: item.name,
      prefix: ""
    }
  end

  @doc """
  The parts of a model at their places: a list of `{frame, part}`, the
  frame of each part in the axes of the model (at near, with each joint
  at its value in `pose`, else at 0). `World.Mass` adds their masses.
  """
  def placed(item, pose \\ %{}) do
    acc = walk(keep_root(item), Frame.identity(), 0, start(item, %{}), :near, pose)
    frames = frames(acc.nodes)

    for {i, parts} <- Enum.sort(acc.parts), {f, p, _} <- Enum.reverse(parts), do: {Frame.compose(frames[i], f), p}
  end

  @doc """
  The elements of a model at a level, in a pose: for each node with
  meshes, its path (the id of its task in `World.Plan.flat/1`), its frame
  in the axes of the model, its part, and the meshes that it shows (the
  meshes of the source of a mirror) with the scale of the mirror. A part
  that the level drops is not an element.
  """
  def elements(item, level, pose \\ %{}) do
    acc = walk(keep_root(item), Frame.identity(), 0, start(item, %{}), level, pose)
    frames = frames(acc.nodes)
    for {i, f, p, path, shown} <- all_placed(acc.nodes, acc.parts), do: {path, Frame.compose(frames[i], f), p, shown}
  end

  # The frame of each node in the axes of the model.
  defp frames(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {n, i}, frames ->
      Map.put(frames, i, if(n.parent, do: Frame.compose(frames[n.parent], n.frame), else: n.frame))
    end)
  end

  @doc "Write the GLB of a model at a level, in a pose."
  def glb(item, opts \\ []), do: GLB.encode(scene(item, opts))

  # The root of the figure goes under the node; a skinned mesh stays a
  # root node (its bones place it).
  # The animations of the same name (the routine of each person of a
  # group) become one animation: an app plays them together.
  defp join(animations) do
    animations
    |> Enum.group_by(& &1.name)
    |> Enum.map(fn {name, [a | _] = all} ->
      {Enum.find_index(animations, &(&1 == a)), %{name: name, channels: Enum.flat_map(all, & &1.channels)}}
    end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  defp figure_parent(0, _, node, _), do: node
  defp figure_parent(_, %{parent: nil}, _, _), do: nil
  defp figure_parent(_, %{parent: p}, _, offset), do: p + offset

  # Walk the tree of a model. A part goes into the list of its node; a
  # node of an assembly goes into the node of its parent, or into a new
  # node for a joint.
  # A figure (a person) brings its own nodes, skin, animations and
  # materials: its root goes at the frame, under the node. The values of
  # its joints have the path of its node in front ("rider/elbow_l"), but
  # not for a figure that is the model.
  defp walk(%Figure{} = f, frame, node, acc, level, pose) do
    values =
      for {k, v} <- pose,
          String.starts_with?(k, acc.prefix),
          into: %{},
          do: {String.replace_prefix(k, acc.prefix, ""), v}

    targets =
      for {k, v} <- acc.targets,
          String.starts_with?(k, acc.prefix),
          into: %{},
          do: {String.replace_prefix(k, acc.prefix, ""), v}

    f = Figure.pose(f, Map.take(values, Figure.values(f)), Map.take(targets, Figure.limbs(f)))
    offset = length(acc.nodes)
    skins = length(acc.skins)

    nodes =
      for {n, i} <- Enum.with_index(f.nodes) do
        %{
          n
          | parent: figure_parent(i, n, node, offset),
            frame: if(i == 0, do: Frame.compose(frame, n.frame), else: n.frame),
            skin: n.skin && n.skin + skins
        }
      end

    %{
      acc
      | nodes: acc.nodes ++ nodes,
        parts: Map.merge(acc.parts, Map.new(offset..(offset + length(nodes) - 1), &{&1, []})),
        skins:
          acc.skins ++
            for(s <- f.skins, do: %{s | joints: Enum.map(s.joints, &(&1 + offset)), skeleton: s.skeleton + offset}),
        animations:
          acc.animations ++
            for(a <- f.animations, do: %{a | channels: Enum.map(a.channels, &%{&1 | node: &1.node + offset})}),
        materials: Map.merge(acc.materials, f.materials),
        joints: acc.joints ++ Enum.map(Figure.values(f), &(acc.prefix <> &1)),
        limbs: acc.limbs ++ Enum.map(Figure.limbs(f), &(acc.prefix <> &1))
    }
    |> props(f, offset, level, pose)
  end

  defp walk(%Part{} = p, frame, node, acc, level, _pose) do
    cond do
      not keep?(p, level) ->
        acc

      stretch?(p) ->
        %{update_in(acc.parts[node], &[{frame, p, acc.path} | &1]) | stretches: [{frame, p, node} | acc.stretches]}

      true ->
        update_in(acc.parts[node], &[{frame, p, acc.path} | &1])
    end
  end

  defp walk(
         %Assembly{nodes: [{root, root_item, nil} | rest], place: place, clips: clips},
         frame,
         node,
         acc,
         level,
         pose
       ) do
    frame = Frame.compose(frame, place)
    acc = %{acc | clips: acc.clips ++ clips}
    # The path of a node is its id in World.Plan.flat/1: the names of the
    # nodes of the smaller assemblies, with "/" between them.
    prefix = acc.prefix
    at = fn acc, name -> %{acc | path: prefix <> name, prefix: prefix <> name <> "/"} end
    places = %{root => {node, frame, length(acc.nodes)}}
    acc = acc |> at.(root) |> then(&walk(root_item, frame, node, &1, level, pose))

    {acc, _} =
      Enum.reduce(rest, {acc, places}, fn {name, item, %Connection{} = c}, {acc, places} ->
        a = %Assembly{nodes: [{root, root_item, nil} | rest], place: Frame.identity()}
        {parent_node, port} = attach(a, c, places)

        acc = at.(acc, name)

        if c.kind == :fixed do
          f = Frame.compose(port, Assembly.placement(c, item, 0.0))
          {walk(item, f, parent_node, acc, level, pose), Map.put(places, name, {parent_node, f, length(acc.nodes)})}
        else
          # The name of a joint is its own name: three.js removes "/" from
          # the names of nodes. Two joints of a model cannot have one name.
          if Enum.any?(acc.nodes, &(&1.name == name)), do: raise(ArgumentError, "two joints have the name #{name}")
          j = Joint.new(name, c.kind, role: c.role, limits: c.limits)
          value = Joint.clamp(j, nil, Map.get(pose, name, 0.0) / 1)

          joint = %Scene.Node{
            name: name,
            parent: parent_node,
            frame: Frame.compose(port, motion(c.kind, value)),
            extras: Map.put(Joint.extras(j), "axis", [0.0, 1.0, 0.0])
          }

          id = length(acc.nodes)

          acc = %{
            acc
            | nodes: acc.nodes ++ [joint],
              parts: Map.put(acc.parts, id, []),
              moves: Map.put(acc.moves, name, {id, port, j})
          }

          f = Assembly.placement(c, item, 0.0)
          {walk(item, f, id, acc, level, pose), Map.put(places, name, {id, f, length(acc.nodes)})}
        end
      end)

    %{acc | prefix: prefix}
  end

  # The props of a figure: each in the node of the bone of its port (or
  # of the root of the figure).
  defp props(acc, %Figure{props: props} = f, offset, level, pose) do
    Enum.reduce(props, acc, fn {port, item, item_port}, acc ->
      {node, frame} = on_figure(f, offset, port)
      walk(item, Frame.compose(frame, Frame.invert(Assembly.item_port_frame(item, item_port))), node, acc, level, pose)
    end)
  end

  # The node and the frame in it of a port of a figure whose first node
  # is `offset`: a port on a bone is in the node of the bone.
  defp on_figure(f, offset, port) do
    case Figure.port!(f, port) do
      %Port{bone: nil} = p -> {offset, Port.frame(p)}
      %Port{bone: bone} = p -> {offset + Figure.bone_node(f, bone), Port.frame(p)}
    end
  end

  # The node of the parent of a connection, and the frame of its port in
  # that node. A port on a bone of a figure is in the node of the bone.
  defp attach(%Assembly{nodes: nodes} = a, %Connection{to: to, at: at} = c, places) do
    {parent_node, parent_frame, first} = Map.fetch!(places, to)

    case List.keyfind(nodes, to, 0) do
      {_, %Figure{} = f, _} when is_binary(at) ->
        if Figure.port!(f, at).bone,
          do: on_figure(f, first, at),
          else: {parent_node, Frame.compose(parent_frame, port_in_node(a, c))}

      _ ->
        {parent_node, Frame.compose(parent_frame, port_in_node(a, c))}
    end
  end

  # The frame of the port `at` of the node `to`, in the axes of that node.
  defp port_in_node(%Assembly{nodes: nodes}, %Connection{to: to, at: at}) do
    {_, item, _} = List.keyfind(nodes, to, 0)
    Assembly.item_port_frame(item, at)
  end

  # A clip of the joints of an assembly: at each time of a key, the value
  # of each joint of the clip (from its keys, in a line between two keys,
  # and the first or the last value out of them). A hinge gives a turn of
  # its node, a slide a move.
  defp clip(%{name: name, keys: keys}, moves) do
    times = Enum.map(keys, &elem(&1, 0))
    names = keys |> Enum.flat_map(fn {_, joints} -> Map.keys(joints) end) |> Enum.uniq() |> Enum.sort()

    channels =
      for joint <- names do
        {id, port, j} = moves[joint]
        points = for {t, joints} <- keys, Map.has_key?(joints, joint), do: {t, joints[joint]}
        frames = for t <- times, do: Frame.compose(port, motion(j.kind, Joint.clamp(j, nil, between(points, t))))

        if j.kind == :slide,
          do: %{node: id, path: :translation, times: times, values: Enum.map(frames, & &1.at)},
          else: %{node: id, path: :rotation, times: times, values: frames}
      end

    %{name: name, channels: channels}
  end

  defp between(points, t) do
    case Enum.split_while(points, fn {pt, _} -> pt <= t end) do
      {[], [{_, v} | _]} -> v
      {before, []} -> elem(List.last(before), 1)
      {before, [{t1, v1} | _]} -> then(List.last(before), fn {t0, v0} -> v0 + (v1 - v0) * (t - t0) / (t1 - t0) end)
    end
  end

  # The motion of a joint: a turn around its z axis, or a move along it.
  defp motion(:hinge, deg), do: Frame.turn({0.0, 0.0, 1.0}, deg)
  defp motion(:slide, d), do: Frame.move({0.0, 0.0, d})

  # The parts whose meshes are in the scene more than once (a wheel, the
  # two shoes of a pair) go into nodes of their own, under the node of
  # their joint, with one key of their mesh: the GLB has the mesh once.
  # A mirror has the key of the part it comes from, and a scale of -1 on
  # x. Only a mesh of @share triangles or more, or @instances copies or
  # more in one node (with `instances`: one node with an instance for
  # each copy, a wall of bricks). The other parts go into the mesh of
  # their node, at their places.
  defp finish(%{nodes: nodes, parts: parts}, {false, instances}) do
    all = all_placed(nodes, parts)
    counts = Enum.frequencies_by(all, fn {_, _, _, _, {shapes, _}} -> shapes end)
    copies = Enum.filter(all, fn {_, _, _, _, {shapes, _}} -> counts[shapes] > 1 end)
    keys = keys(copies)
    groups = Enum.frequencies_by(copies, fn {i, _, _, _, shown} -> {i, shown} end)

    # A node of its own costs a draw of the app: only for a big mesh, or
    # for the instances of many copies.
    {many, once} =
      Enum.split_with(all, fn {i, _, _, _, {shapes, _} = shown} ->
        counts[shapes] > 1 and
          (keys[shapes].triangles >= @share or (instances and groups[{i, shown}] >= @instances))
      end)

    once = Enum.group_by(once, &elem(&1, 0), fn {_, f, p, _, _} -> {f, p.shapes} end)

    nodes =
      for {n, i} <- Enum.with_index(nodes),
          do: %{n | primitives: n.primitives ++ primitives(Map.get(once, i, []))}

    {nodes ++ shared(many, keys, instances), parts}
  end

  # Each part in a node of its own, under the node of its joint, with the
  # id of its task; the parts with one mesh share it, as above.
  defp finish(%{nodes: nodes, parts: parts}, {true, _}) do
    all = all_placed(nodes, parts)
    keys = keys(all)

    split =
      for {i, f, _, path, {shapes, scale}} <- all do
        %Scene.Node{
          name: path,
          parent: i,
          frame: f,
          scale: scale,
          extras: %{"task" => path},
          primitives: keys[shapes].primitives,
          mesh: keys[shapes].id
        }
      end

    {nodes ++ split, parts}
  end

  # Each part with meshes: its node, frame, part, path and the meshes it
  # shows with their scale (the meshes of its source for a mirror).
  defp all_placed(nodes, parts) do
    for {_, i} <- Enum.with_index(nodes), {f, p, path} <- Enum.reverse(parts[i]), p.shapes != [] do
      shown =
        case Mirror.source(p) do
          nil -> {p.shapes, 1.0}
          source -> {source, @mirror}
        end

      {i, f, p, path, shown}
    end
  end

  # The id (in the order of the first part) and the primitives (in the
  # axes of the part) of each list of meshes.
  defp keys(all) do
    {keys, _} =
      Enum.reduce(all, {%{}, 0}, fn {_, _, _, _, {shapes, _}}, {keys, n} ->
        if Map.has_key?(keys, shapes),
          do: {keys, n},
          else: {Map.put(keys, shapes, key(n, primitives([{Frame.identity(), shapes}]))), n + 1}
      end)

    keys
  end

  defp key(id, primitives),
    do: %{
      id: id,
      primitives: primitives,
      triangles: primitives |> Enum.map(&length(&1.indices)) |> Enum.sum() |> div(3)
    }

  # The nodes of the parts with a shared mesh: one for each part, or one
  # with instances for each group of @instances parts or more with one
  # node, one mesh and one scale (a mirror in the scale of the node: an
  # app turns the faces of the node over, not of each instance).
  defp shared(many, keys, instances) do
    groups = Enum.group_by(many, fn {i, _, _, _, shown} -> {i, shown} end)

    {nodes, _} =
      Enum.flat_map_reduce(many, MapSet.new(), fn {i, f, p, path, {shapes, scale} = shown}, done ->
        group = groups[{i, shown}]

        cond do
          not instances or length(group) < @instances ->
            node = %Scene.Node{name: path, parent: i, frame: f, scale: scale, primitives: keys[shapes].primitives}
            {[%{node | mesh: keys[shapes].id}], done}

          MapSet.member?(done, {i, shown}) ->
            {[], done}

          true ->
            # A mirror in the scale of the node: each frame in the node
            # is the mirror of the frame of its part (S F S, a turn).
            frames = for {_, g, _, _, _} <- group, do: if(scale == 1.0, do: g, else: Mirror.frame(g))

            node = %Scene.Node{
              name: p.name,
              parent: i,
              scale: scale,
              primitives: keys[shapes].primitives,
              mesh: keys[shapes].id,
              instances: frames,
              extras: %{"count" => length(group)}
            }

            {[node], MapSet.put(done, {i, shown})}
        end
      end)

    nodes
  end

  # One material at a time: the corners of one material are live, not
  # the corners of all the parts, and a full collection after each
  # primitive keeps the peak low (`World.Detail.collect/1`).
  #
  # With `parallel: true` (the join of a construction), a process for each
  # material makes its primitive, with the triangles of its meshes only.
  defp primitives(placed) do
    given = Process.get(:world_triangles, %{})

    groups =
      placed
      |> Enum.flat_map(fn {f, shapes} -> for m <- shapes, do: {m.material, {f, m}} end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.sort_by(&elem(&1, 0))

    if Process.get(:world_parallel, false) do
      lean = Process.get(:world_lean, true)

      groups
      |> Enum.map(fn {_, shapes} = g -> {g, Map.take(given, for({_, m} <- shapes, uniq: true, do: m))} end)
      |> Task.async_stream(fn {g, given} -> Detail.lean(lean, fn -> primitive(g, given) end) end,
        ordered: true,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, p} -> p end)
    else
      Enum.map(groups, &primitive(&1, given))
    end
  end

  defp primitive({mat, shapes}, given) do
    # The triangles of a mesh, kept for the next part with the same mesh,
    # for this material only.
    {corners, _} =
      Enum.flat_map_reduce(shapes, %{}, fn {f, m}, memo ->
        tris = Map.get_lazy(memo, m, fn -> Map.get_lazy(given, m, fn -> Mesh.triangles(m) end) end)
        {place(tris, f), Map.put(memo, m, tris)}
      end)

    mat |> Scene.primitive(corners) |> Detail.collect()
  end

  defp place(corners, f), do: for({p, n} <- corners, do: {Frame.point(f, p), Frame.dir(f, n)})

  # A part that stretches between its node and another node (a spring):
  # `"stretch"` in its params, `%{"to" => node, "from" => point, "end" =>
  # point}` (the points in the axes of the part).
  defp stretch?(%Part{params: %{"stretch" => _}}), do: true
  defp stretch?(_), do: false

  # Each part that stretches is a skinned mesh: its points from `from` to
  # `end` go from its own node to the node `to` (a weight from 0 to 1
  # along the line; the points out of the line stay with the nearer
  # node). The bind is the frame of each node at rest (a joint at 0): a
  # joint at its value moves the points by its weight, so the part
  # stretches as the joint moves, in each app that plays a skin.
  defp stretched(nodes, skins, stretches, moves) do
    frames = Scene.world_frames(%Scene{nodes: nodes})
    joints = Map.new(moves, fn {_, {id, port, _}} -> {id, port} end)

    rest = fn i ->
      case joints do
        %{^i => port} -> Frame.compose(frames[Enum.at(nodes, i).parent], port)
        _ -> frames[i]
      end
    end

    Enum.reduce(stretches, {nodes, skins}, fn {f, p, node}, {nodes, skins} ->
      %{"to" => to, "from" => a, "end" => b} = p.params["stretch"]
      j = Enum.find_index(nodes, &(&1.name == to))
      {ra, rb} = {rest.(node), rest.(j)}
      place = Frame.compose(ra, f)
      {pa, pb} = {Frame.point(place, List.to_tuple(a)), Frame.point(place, List.to_tuple(b))}
      ab = Vec.sub(pb, pa)

      prims =
        for prim <- primitives([{place, p.shapes}]) do
          ts = for q <- prim.positions, do: min(max(Vec.dot(Vec.sub(q, pa), ab) / Vec.dot(ab, ab), 0.0), 1.0)
          # A point at an end goes with one node alone (no joint with no weight).
          joints = Enum.map(ts, &if(&1 == 1.0, do: {1, 0, 0, 0}, else: {0, 1, 0, 0}))
          weights = Enum.map(ts, &if(&1 == 1.0 or &1 == 0.0, do: {1.0, 0.0, 0.0, 0.0}, else: {1.0 - &1, &1, 0.0, 0.0}))

          %{
            prim
            | joints: Enum.map(Enum.zip(ts, joints), fn {t, j} -> if t == 0.0, do: {0, 0, 0, 0}, else: j end),
              weights: weights
          }
        end

      skin = %{joints: [node, j], inverse_bind: [Frame.invert(ra), Frame.invert(rb)], skeleton: node}
      {nodes ++ [%Scene.Node{name: p.name, skin: length(skins), primitives: prims}], skins ++ [skin]}
    end)
  end

  # The root part of a model stays at each level: a small model (a
  # switch of 7 cm) keeps its body at far.
  defp keep_root(%Part{detail: nil} = p), do: %{p | detail: :always}

  defp keep_root(%Assembly{nodes: [{root, item, nil} | rest]} = a),
    do: %{a | nodes: [{root, keep_root(item), nil} | rest]}

  defp keep_root(item), do: item

  defp keep?(%Part{shapes: []}, _), do: true
  defp keep?(%Part{detail: :always}, _), do: true
  defp keep?(%Part{detail: :low}, level), do: level != :near
  defp keep?(%Part{}, :near), do: true
  defp keep?(%Part{detail: :near}, _), do: false
  defp keep?(%Part{inside: true}, _), do: false

  defp keep?(%Part{} = p, level) do
    {long, thin} = Map.fetch!(@limits, level)
    {lo, hi} = Part.bounds(p)
    sides = Tuple.to_list(Vec.sub(hi, lo))
    Enum.max(sides) >= long and Enum.min(sides) >= thin
  end

  @doc """
  The list of the parts of a model, each with its count and, when its
  materials have densities and its meshes are closed, the mass of one
  (kg, `World.Mass`), in the order of the names.
  """
  def parts(item) do
    all = all_parts(item)
    masses = Map.new(all, &{{&1.name, &1.kind, &1.params, &1.sources}, mass(&1)})

    all
    |> Enum.frequencies_by(&{&1.name, &1.kind, &1.params, &1.sources})
    |> Enum.map(fn {{name, kind, params, sources} = key, count} ->
      %{"name" => name, "kind" => Atom.to_string(kind), "count" => count, "params" => params, "sources" => sources}
      |> then(fn row -> if m = masses[key], do: Map.put(row, "mass", m), else: row end)
    end)
    # Two parts can have one name with other params: all the fields fix the order.
    |> Enum.sort_by(&{&1["name"], &1["kind"], &1["params"], &1["sources"]})
  end

  @doc """
  The data of the file `NAME.parts.json` of a model: its name, the list
  of its parts (`parts/1`) and, for a model with `"ports"` in its extras
  (a house, W18 of Vũng Tàu), its ports in the axes of the GLB (glTF: +y
  up, the front to +z): each with its kind, its `position` and its
  `normal`, its `size` and the other fields of the model.
  """
  def parts_file(name, item) do
    base = %{"name" => name, "parts" => parts(item)}

    case Map.get(item, :extras, %{}) do
      %{"ports" => ports} -> Map.put(base, "ports", Enum.map(ports, &gltf_port/1))
      _ -> base
    end
  end

  # Each point and direction (a tuple) of a port goes into glTF; `at` is
  # its `position`.
  defp gltf_port(p) do
    for {k, v} <- p, into: %{} do
      case {k, v} do
        {"at", v} -> {"position", gltf(v)}
        {k, {_, _, _}} -> {k, gltf(v)}
        kv -> kv
      end
    end
  end

  # A point of World (x, y, z) in glTF is (-x, z, y) (`World.GLB`).
  defp gltf({x, y, z}), do: Enum.map([-x, z, y], &(Float.round(&1 / 1, 4) + 0.0))

  defp mass(%Part{} = p), do: with(%{mass: m} <- World.Mass.part(p), do: Float.round(m, 4))

  # A part with no shapes is a mark (the origin of a build), and a part of
  # the low levels stands in for other parts: not things to buy.
  defp all_parts(%Part{shapes: []}), do: []
  defp all_parts(%Part{detail: :low}), do: []
  defp all_parts(%Part{} = p), do: [p]

  defp all_parts(%Figure{} = f),
    do: [
      %Part{name: f.name, kind: f.kind, params: f.params, sources: f.sources}
      | Enum.flat_map(f.props, fn {_, item, _} -> all_parts(item) end)
    ]

  defp all_parts(%Assembly{nodes: nodes}), do: Enum.flat_map(nodes, fn {_, item, _} -> all_parts(item) end)
end
