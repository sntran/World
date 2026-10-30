defmodule World.People.Human do
  @moduledoc """
  People from the data of MakeHuman (CC0, `World.People.Data`): a body of
  real shape from its numbers (sex, age, muscle, weight, height, origin),
  a skeleton of 53 bones ("game_engine"), skin weights, eyes, eyebrows,
  eyelashes, hair and clothes fitted to the body, and the textures of a
  skin.

  The levels of detail (`World.Detail`):
  - `:near`: the full base mesh, and the clothes and the hair;
  - `:mid`: a body of about 1,600 faces, with the colors of the clothes on
    it, and the hair;
  - `:far`: a body of 730 faces, with the colors of the clothes on it.
  """
  alias World.{Detail, Figure, Frame, Part, Port, Scene, Vec}
  alias World.People.{Data, Face, Joints, Pose, Skeleton}

  @defaults [
    gender: 1.0,
    age: 30,
    muscle: 0.5,
    weight: 0.5,
    height: 0.5,
    race: %{"asian" => 1.0},
    skin: "young_asian_male",
    eyes: "brown",
    eyebrows: "eyebrow001",
    hair: "short02",
    clothes: ["male_casualsuit01", "shoes01"],
    hair_color: nil,
    clothes_colors: [],
    head: 1.0,
    helmet: nil,
    pose: %{},
    hold: [],
    speech: false
  ]

  @doc """
  A person. The options (with their defaults in `@defaults`): `gender`
  (0 is a woman, 1 a man), `age` (years, 25 to 90), `muscle`, `weight`
  and `height` (0 to 1, 0.5 is the mean), `race` (a map of
  "african", "asian", "caucasian" to a weight), `skin`, `eyes`,
  `eyebrows`, `hair` (or nil), `clothes` (a list), `hair_color` (`[r, g,
  b]`, or nil for the color of the hair), `clothes_colors` (a list of
  `[r, g, b]` in the order of the clothes: at mid and far the color of
  the item, at near a tint of its texture), `head` (the size of the head:
  1 is the size of the body, more is the bigger head of a game), `helmet`
  (`[r, g, b]`: a helmet of a rider of that color, or nil), `pose` (a map
  of a bone to `{axis, degrees}`, or a name of `World.People.Pose`), and
  `animations` (a list of names of `World.People.Pose`, or of `{name,
  opts}`: `delay` in seconds and `mirror` for a routine), and `hold` (a
  list of `{port, item}`: a prop on a port of a bone, as
  `World.Figure.hold/4`, by the port of the prop with the name of the
  port of the person with no side (`grip` for `grip_r`); a hand that
  holds a prop closes on it, in the pose and in each animation), and
  `speech` (true: at near, the teeth and the tongue, and the 15 visemes of
  `World.People.Face` as morph targets of the skin, the teeth and the
  tongue, for an app that moves the mouth with the voice).
  """
  def person(name, opts \\ []) do
    o = Map.new(Keyword.merge(@defaults, opts))
    o = Map.put(o, :colors, chosen_colors(o))
    base = Data.base()
    points = morph(base.points, o)
    clothes = Enum.map(o.clothes, &Data.asset("clothes", &1))
    o = Map.put(o, :ground, ground(base, points, clothes))
    bones = skeleton(points, o.ground)
    weights = vertex_weights(Enum.map(bones, & &1.name))
    level = Detail.level()

    {prims, materials} =
      case level do
        :near -> near(base, points, weights, o, clothes)
        _ -> proxy(points, weights, o, clothes, level)
      end

    {prims, materials} = helmet({prims, materials}, points, weights, bones, o)

    skeleton = Skeleton.new(bones)
    hands = for {"grip_" <> side, _} <- o.hold, into: %{}, do: {String.to_existing_atom(side), "grip"}
    pose = Pose.expand(Map.merge(Pose.resolve(o.pose), Map.new(hands, fn {side, shape} -> {{:hand, side}, shape} end)))
    {nodes, skin} = nodes(name, skeleton, prims, pose, o.head)

    %Figure{
      name: name,
      kind: :person,
      params:
        Map.take(o, [
          :gender,
          :age,
          :muscle,
          :weight,
          :height,
          :race,
          :skin,
          :hair,
          :clothes,
          :hair_color,
          :clothes_colors,
          :head
        ])
        |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end),
      sources: [
        "MakeHuman (CC0): the base mesh, the targets, the skeleton game_engine, and the assets #{Enum.join([o.skin | o.clothes], ", ")}."
      ],
      nodes: nodes,
      skins: [skin],
      animations:
        for(
          a <- Map.get(o, :animations, []),
          do:
            if(is_tuple(a),
              do: Pose.animation(elem(a, 0), bones, [hands: hands] ++ elem(a, 1)),
              else: Pose.animation(a, bones, hands: hands)
            )
        ),
      materials: materials,
      ports: ports(bones, points, weights, o.ground),
      skeleton: skeleton,
      pose: pose,
      joints: Joints.all()
    }
    |> then(fn f ->
      Enum.reduce(o.hold, f, fn {port, item}, f -> Figure.hold(f, port, item, String.replace(port, ~r/_[lr]$/, "")) end)
    end)
  end

  @doc """
  The skeleton (`World.People.Skeleton`) of a person with the options of
  `person/2`, with no mesh: to try a pose and measure it.
  """
  def skeleton(opts \\ []) do
    o = Map.new(Keyword.merge(@defaults, opts))
    base = Data.base()
    points = morph(base.points, o)
    clothes = Enum.map(o.clothes, &Data.asset("clothes", &1))
    Skeleton.new(skeleton(points, ground(base, points, clothes)))
  end

  # --- The shape of the body ----------------------------------------------------

  @doc """
  The weight of each target for the numbers of a person: a list of
  `{target name, weight}` (MakeHuman, "macrodetails").
  """
  def target_weights(o) do
    g = [{"female", 1 - o.gender}, {"male", o.gender}]
    a = (min(max(o.age, 25), 90) - 25) / 65
    age = [{"young", 1 - a}, {"old", a}]
    muscle = three(o.muscle, "minmuscle", "averagemuscle", "maxmuscle")
    weight = three(o.weight, "minweight", "averageweight", "maxweight")
    h = o.height
    height = if h < 0.5, do: [{"minheight", 1 - 2 * h}], else: [{"maxheight", 2 * h - 1}]
    total = o.race |> Map.values() |> Enum.sum()
    race = for {r, w} <- o.race, do: {r, w / total}

    racegenderage = for {r, wr} <- race, {gn, wg} <- g, {an, wa} <- age, do: {"#{r}-#{gn}-#{an}", wr * wg * wa}

    universal =
      for {gn, wg} <- g, {an, wa} <- age, {mn, wm} <- muscle, {wn, ww} <- weight do
        {"universal-#{gn}-#{an}-#{mn}-#{wn}", wg * wa * wm * ww}
      end

    heights =
      for {gn, wg} <- g, {an, wa} <- age, {mn, wm} <- muscle, {wn, ww} <- weight, {hn, wh} <- height do
        {"height/#{gn}-#{an}-#{mn}-#{wn}-#{hn}", wg * wa * wm * ww * wh}
      end

    Enum.filter(racegenderage ++ universal ++ heights, fn {_, w} -> w > 1.0e-4 end)
  end

  defp three(v, low, mid, _high) when v < 0.5, do: [{low, 1 - 2 * v}, {mid, 2 * v}]
  defp three(v, _low, mid, high), do: [{mid, 2 - 2 * v}, {high, 2 * v - 1}]

  # The points of the base mesh with the targets, in the axes of MakeHuman.
  defp morph(points, o) do
    arr = :array.from_list(Tuple.to_list(points))

    target_weights(o)
    |> Enum.reduce(arr, fn {name, w}, arr ->
      Enum.reduce(Data.target(name), arr, fn {i, {dx, dy, dz}}, arr ->
        {x, y, z} = :array.get(i, arr)
        :array.set(i, {x + w * dx, y + w * dy, z + w * dz}, arr)
      end)
    end)
    |> :array.to_list()
    |> List.to_tuple()
  end

  @doc "A point of MakeHuman (decimeters, +Y up, front +Z) in the axes of World (meters)."
  def to_world({x, y, z}), do: {-x * 0.1, z * 0.1, y * 0.1}

  # --- The skeleton ------------------------------------------------------------

  # The bones, parents first: name, parent, head and tail (in the axes of
  # World, with the feet on z = 0 later), and the frame of the bone.
  defp skeleton(points, ground) do
    base = Data.base()
    rig = Data.rig()

    center = fn cube ->
      faces = Map.fetch!(base.groups, cube)
      idx = faces |> List.flatten() |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
      idx |> Enum.map(&elem(points, &1)) |> Vec.mean() |> to_world() |> Vec.sub({0.0, 0.0, ground})
    end

    at = fn spec ->
      case spec do
        %{"strategy" => "CUBE", "cube_name" => cube} ->
          center.(cube)

        %{"strategy" => "MEAN", "vertex_indices" => idx} ->
          idx |> Enum.map(&elem(points, &1)) |> Vec.mean() |> to_world() |> Vec.sub({0.0, 0.0, ground})
      end
    end

    rig
    |> order_bones()
    |> Enum.map(fn name ->
      spec = Map.fetch!(rig, name)
      head = at.(spec["head"])
      tail = at.(spec["tail"])

      %{
        name: name,
        parent: if(spec["parent"] == "", do: nil, else: spec["parent"]),
        head: head,
        tail: tail,
        frame: bone_frame(head, tail, spec["roll"])
      }
    end)
  end

  defp order_bones(rig) do
    Stream.iterate({[], MapSet.new()}, fn {done, seen} ->
      ready =
        for {name, spec} <- rig,
            not MapSet.member?(seen, name),
            spec["parent"] == "" or MapSet.member?(seen, spec["parent"]),
            do: name

      ready = Enum.sort(ready)
      {done ++ ready, MapSet.union(seen, MapSet.new(ready))}
    end)
    |> Enum.find(fn {done, _} -> length(done) == map_size(rig) end)
    |> elem(0)
  end

  # The frame of a bone as in Blender (MPFB makes the skeleton there): its
  # y axis from the head to the tail, turned by the roll. Blender has the
  # axes of World turned 180 degrees around z.
  defp bone_frame(head, tail, roll) do
    flip = fn {x, y, z} -> {-x, -y, z} end
    nor = Vec.norm(flip.(Vec.sub(tail, head)))
    y = {0.0, 1.0, 0.0}
    axis = Vec.cross(y, nor)

    b =
      if Vec.len(axis) > 1.0e-9,
        do: Frame.turn(axis, :math.acos(max(min(Vec.dot(y, nor), 1.0), -1.0)) * 180 / :math.pi()),
        else: if(Vec.dot(y, nor) > 0, do: Frame.identity(), else: Frame.turn({0.0, 0.0, 1.0}, 180.0))

    m = Frame.compose(Frame.turn(nor, roll * 180 / :math.pi()), b)
    %Frame{x: flip.(m.x), y: flip.(m.y), z: flip.(m.z), at: head}
  end

  # The height of the ground (meters): under the lowest point of the body
  # or of the clothes (the soles of the shoes).
  defp ground(base, points, clothes) do
    body = for f <- Map.fetch!(base.groups, "body"), {v, _} <- f, do: elem(points, v)
    worn = Enum.flat_map(clothes, &Tuple.to_list(fit_positions(&1, points)))
    (body ++ worn) |> Enum.map(&elem(&1, 1)) |> Enum.min() |> Kernel.*(0.1)
  end

  # --- Weights -----------------------------------------------------------------

  # The 4 largest weights of each point of the base mesh: a map of a point
  # to `[{bone index, weight}]`, the sum 1.
  defp vertex_weights(bone_names) do
    index = bone_names |> Enum.with_index() |> Map.new()

    Data.weights()
    |> Enum.flat_map(fn {bone, list} -> for [v, w] <- list, Map.has_key?(index, bone), do: {v, {index[bone], w}} end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {v, ws} -> {v, top4(ws)} end)
  end

  @doc """
  The 4 largest weights of a list of `{bone, weight}`, with the sum 1.
  The weights of a blend can be less than zero: they go. A point with no
  weight follows the root bone.
  """
  def top4(ws) do
    ws = ws |> Enum.filter(&(elem(&1, 1) > 1.0e-4)) |> Enum.sort_by(fn {b, w} -> {-w, b} end) |> Enum.take(4)
    total = ws |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    if ws == [], do: [{0, 1.0}], else: for({b, w} <- ws, do: {b, w / total})
  end

  defp blend(weights, refs) do
    refs
    |> Enum.flat_map(fn {v, k} -> for {b, w} <- Map.get(weights, v, [{0, 1.0}]), do: {b, w * k} end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {b, ws} -> {b, Enum.sum(ws)} end)
    |> top4()
  end

  # --- The meshes --------------------------------------------------------------

  # The near level: the base mesh with no hidden faces, and the assets.
  defp near(base, points, weights, o, clothes) do
    hidden = clothes |> Enum.map(& &1.fit.delete) |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    faces =
      for f <- Map.fetch!(base.groups, "body"), not Enum.any?(f, fn {v, _} -> MapSet.member?(hidden, v) end), do: f

    # With speech: the moves of the visemes, for each point of the base
    # mesh, and the teeth and the tongue (helper groups of the base mesh,
    # which the targets of the mouth move).
    shapes =
      if o.speech, do: for({n, moves} <- Face.visemes(o.race), do: {n, &Map.get(moves, &1, {0.0, 0.0, 0.0})}), else: []

    part = fn role, group ->
      mesh(role, base.groups[group], &elem(points, &1), nil, &Map.get(weights, &1, [{0, 1.0}]), o.ground, shapes)
    end

    body =
      mesh(:skin, faces, &elem(points, &1), &elem(base.uvs, &1), &Map.get(weights, &1, [{0, 1.0}]), o.ground, shapes)

    mouth =
      if o.speech,
        do: [part.(:teeth, "helper-upper-teeth"), part.(:teeth, "helper-lower-teeth"), part.(:tongue, "helper-tongue")],
        else: []

    assets =
      [
        {:eyes, Data.asset("eyes", "high-poly"), Data.asset("eye_materials", o.eyes)},
        {:eyebrows, Data.asset("eyebrows", o.eyebrows), nil},
        {:eyelashes, Data.asset("eyelashes", "eyelashes01"), nil}
      ] ++
        if(o.hair, do: [{:hair, Data.asset("hair", o.hair), nil}], else: []) ++
        for(c <- clothes, do: {String.to_atom("clothes_" <> c.name), c, nil})

    prims = [body | mouth] ++ for({role, a, _} <- assets, do: fitted(role, a, points, weights, o.ground))

    materials =
      Map.new(
        [{:skin, textured(Data.asset("skins", o.skin).texture, false)}] ++
          if(o.speech,
            do: [
              {:teeth, %{"color" => [236, 230, 214], "roughness" => 0.3, "metalness" => 0.0}},
              {:tongue, %{"color" => [178, 86, 92], "roughness" => 0.5, "metalness" => 0.0}}
            ],
            else: []
          ) ++
          for(
            {role, a, mat} <- assets,
            do:
              {role, tint(textured((mat || a).texture, a.transparent or role in [:eyebrows, :eyelashes, :hair]), a, o)}
          )
      )

    {prims, materials}
  end

  # The levels mid and far: a low-poly body. Each face under clothes has
  # the mean color of those clothes; the hair stays at mid.
  defp proxy(points, weights, o, clothes, level) do
    name = if level == :far, do: "proxy741", else: if(o.gender >= 0.5, do: "male1591", else: "female1605")
    p = Data.asset("proxies", name)
    {pts, wts} = fit_points(p, points, weights)
    ring = neighbors(Data.base())
    covers = Enum.map(clothes, &{&1, grow(cover(&1), ring)})
    # At far there is no hair: the scalp has the color of the hair.
    covers =
      if level == :far and o.hair,
        do: [{Data.asset("hair", o.hair), cover(Data.asset("hair", o.hair))} | covers],
        else: covers

    # The clothes that cover the most of the points of the body under a face.
    owner = fn face ->
      body = Enum.flat_map(face, fn {v, _} -> elem(elem(p.fit.refs, v), 0) end)

      covers
      |> Enum.map(fn {c, set} -> {c, Enum.count(body, &MapSet.member?(set, &1))} end)
      |> Enum.filter(fn {_, n} -> n * 2 > length(body) end)
      |> Enum.max_by(&elem(&1, 1), &>=/2, fn -> {nil, 0} end)
      |> elem(0)
    end

    uv = fn i -> if i, do: elem(p.mesh.uvs, i), else: {0.0, 0.0} end
    groups = p.mesh.groups |> Map.values() |> Enum.concat() |> Enum.group_by(owner)
    role = fn c -> if c, do: String.to_atom("color_" <> c.name), else: :skin end

    prims =
      for {c, faces} <- groups,
          do: mesh(role.(c), faces, &elem(pts, &1), if(c, do: nil, else: uv), &elem(wts, &1), o.ground)

    hair =
      if level == :mid and o.hair, do: [fitted(:hair, Data.asset("hair", o.hair), points, weights, o.ground)], else: []

    colors =
      for {c, _} <- covers,
          do: {role.(c), %{"color" => Map.get(o.colors, c.name, c.color), "roughness" => 0.9, "metalness" => 0.0}}

    materials = Map.new([{:skin, textured(Data.asset("skins", o.skin).texture, false)} | colors])

    materials =
      if hair == [],
        do: materials,
        else:
          Map.put(
            materials,
            :hair,
            tint(textured(Data.asset("hair", o.hair).texture, true), Data.asset("hair", o.hair), o)
          )

    {Enum.sort_by(prims, & &1.material) ++ hair, materials}
  end

  # --- The helmet ----------------------------------------------------------------

  # A half helmet of a rider (the helmet of Việt Nam): a dome over the top
  # of the head from the line of the brows, a little larger than the head
  # and the hair over that line (at most 4 cm more). It is a part of the
  # skinned mesh on the bone "head", so it follows the head, its pose and
  # its size.
  defp helmet(prims_materials, _points, _weights, _bones, %{helmet: nil}), do: prims_materials

  defp helmet({prims, materials}, points, weights, bones, o) do
    head = Enum.find_index(bones, &(&1.name == "head"))
    at = fn p -> Vec.sub(to_world(p), {0.0, 0.0, o.ground}) end

    skull =
      for {v, ws} <- weights, Enum.any?(ws, fn {b, w} -> b == head and w >= 0.5 end), do: at.(elem(points, v))

    {{x0, y0, z0}, {x1, y1, z1}} = Vec.bounds(skull)
    brow = z0 + 0.62 * (z1 - z0)
    c = {(x0 + x1) / 2, (y0 + y1) / 2 - 0.08 * (y1 - y0), brow}

    hair =
      if o.hair,
        do:
          for(
            p <- Tuple.to_list(fit_positions(Data.asset("hair", o.hair), points)),
            q = at.(p),
            elem(q, 2) > brow,
            do: q
          ),
        else: []

    reach = fn axis, half ->
      out = Enum.map(hair, &abs(elem(Vec.sub(&1, c), axis)))
      min(max(half, Enum.max(out, fn -> 0.0 end)), half + 0.04) + 0.012
    end

    r = {reach.(0, (x1 - x0) / 2), reach.(1, (y1 - y0) / 2 + 0.08 * (y1 - y0)), reach.(2, z1 - brow)}
    prim = dome(c, r, head)
    paint = %{"color" => o.helmet, "roughness" => 0.35, "metalness" => 0.0, "double_sided" => true}
    {prims ++ [prim], Map.put(materials, :helmet, paint)}
  end

  # The upper half of an ellipsoid (center `c`, radii `r`), a little under
  # the middle at its rim, on one bone.
  defp dome({cx, cy, cz}, {rx, ry, rz}, bone) do
    {rings, steps} = {8, 24}

    verts =
      for i <- 0..rings, j <- 0..(steps - 1) do
        lat = :math.pi() / 2 * (1.08 * i / rings)
        lon = 2 * :math.pi() * j / steps
        {u, v, w} = {:math.sin(lat) * :math.cos(lon), :math.sin(lat) * :math.sin(lon), :math.cos(lat)}
        {{cx + rx * u, cy + ry * v, cz + rz * w}, Vec.norm({u / rx, v / ry, w / rz})}
      end

    k = fn i, j -> i * steps + rem(j, steps) end

    indices =
      for i <- 0..(rings - 1),
          j <- 0..(steps - 1),
          tri <- [[k.(i, j), k.(i + 1, j), k.(i + 1, j + 1)], [k.(i, j), k.(i + 1, j + 1), k.(i, j + 1)]],
          do: tri

    %Scene.Primitive{
      material: :helmet,
      positions: Enum.map(verts, &elem(&1, 0)),
      normals: Enum.map(verts, &elem(&1, 1)),
      indices: List.flatten(indices),
      joints: List.duplicate({bone, 0, 0, 0}, length(verts)),
      weights: List.duplicate({1.0, 0.0, 0.0, 0.0}, length(verts))
    }
  end

  # The points of the body next to each point (in the faces of the body).
  defp neighbors(base) do
    for f <- Map.fetch!(base.groups, "body"), {a, _} <- f, {b, _} <- f, a != b, reduce: %{} do
      acc -> Map.update(acc, a, [b], &[b | &1])
    end
  end

  defp grow(set, ring), do: set |> Enum.flat_map(&Map.get(ring, &1, [])) |> MapSet.new() |> MapSet.union(set)

  # The points of the body under clothes: the points that the clothes
  # hide, and the points that hold the clothes.
  defp cover(%{fit: fit}) do
    fit.refs |> Tuple.to_list() |> Enum.flat_map(&elem(&1, 0)) |> MapSet.new() |> MapSet.union(fit.delete)
  end

  # An asset on the body: its points from the points of the body, its
  # weights from theirs.
  defp fitted(role, a, points, weights, ground) do
    {pts, wts} = fit_points(a, points, weights)
    faces = a.mesh.groups |> Map.values() |> Enum.concat()
    uv = fn i -> if i, do: elem(a.mesh.uvs, i), else: {0.0, 0.0} end
    mesh(role, faces, &elem(pts, &1), uv, &elem(wts, &1), ground)
  end

  defp fit_points(%{fit: fit} = a, points, weights) do
    weights = for {vs, ws, _} <- Tuple.to_list(fit.refs), do: blend(weights, Enum.zip(vs, ws))
    {fit_positions(a, points), List.to_tuple(weights)}
  end

  # The points of an asset on the body (MakeHuman, "mhclo"): the sum of
  # three points of the body with their weights, and an offset in the
  # scale of the body.
  defp fit_positions(%{fit: fit}, points) do
    # A scale is the distance of two points of the body over their
    # distance in the base mesh; with no scale, 1.
    scale = fn axis, k ->
      with {a, b, d} <- Map.get(fit.scales, axis, 1.0), do: abs(elem(elem(points, a), k) - elem(elem(points, b), k)) / d
    end

    s = {scale.("x_scale", 0), scale.("y_scale", 1), scale.("z_scale", 2)}

    fit.refs
    |> Tuple.to_list()
    |> Enum.map(fn {vs, ws, {dx, dy, dz}} ->
      p = Enum.zip(vs, ws) |> Enum.map(fn {v, w} -> Vec.scale(elem(points, v), w) end) |> Enum.reduce(&Vec.add/2)
      Vec.add(p, {dx * elem(s, 0), dy * elem(s, 1), dz * elem(s, 2)})
    end)
    |> List.to_tuple()
  end

  # A primitive from faces of `{point, uv}`: one vertex for each pair, the
  # normal of each point from its faces, and the 4 weights.
  # `shapes`: a list of `{name, move}`, the move of a point of the base
  # mesh (in the units of MakeHuman): the morph targets of the mesh.
  defp mesh(role, faces, pos, uv, wts, ground, shapes \\ []) do
    tris = Enum.flat_map(faces, fn [a, b, c | rest] -> fan(a, [b, c | rest]) end)
    p = fn v -> Vec.sub(to_world(pos.(v)), {0.0, 0.0, ground}) end

    normals =
      tris
      |> Enum.flat_map(fn [{a, _}, {b, _}, {c, _}] ->
        n = Vec.cross(Vec.sub(p.(b), p.(a)), Vec.sub(p.(c), p.(a)))
        [{a, n}, {b, n}, {c, n}]
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {v, ns} -> {v, Vec.norm(Enum.reduce(ns, &Vec.add/2))} end)

    {indices, {_, verts}} =
      tris
      |> List.flatten()
      |> Enum.map_reduce({%{}, []}, fn key, {seen, verts} ->
        case seen do
          %{^key => i} -> {i, {seen, verts}}
          _ -> {map_size(seen), {Map.put(seen, key, map_size(seen)), [key | verts]}}
        end
      end)

    verts = Enum.reverse(verts)
    joints = for {v, _} <- verts, do: pad4(wts.(v))

    %Scene.Primitive{
      material: role,
      positions: for({v, _} <- verts, do: p.(v)),
      normals: for({v, _} <- verts, do: normals[v]),
      uvs: if(uv, do: for({_, t} <- verts, do: flip_v(uv.(t)))),
      joints: for(js <- joints, do: List.to_tuple(Enum.map(js, &elem(&1, 0)))),
      weights: for(js <- joints, do: List.to_tuple(Enum.map(js, &(elem(&1, 1) / 1)))),
      indices: indices,
      targets: if(shapes != [], do: for({n, move} <- shapes, do: {n, for({v, _} <- verts, do: to_world(move.(v)))}))
    }
  end

  defp fan(a, [b, c | rest]), do: [[a, b, c] | fan(a, [c | rest])]
  defp fan(_, [_]), do: []

  defp pad4(ws), do: Enum.take(ws ++ List.duplicate({0, 0.0}, 4), 4)
  defp flip_v({u, v}), do: {u, 1.0 - v}

  # The colors that the order chose, by the name of the asset.
  defp chosen_colors(o) do
    hair = if o.hair && o.hair_color, do: [{o.hair, o.hair_color}], else: []
    Map.new(hair ++ Enum.zip(o.clothes, o.clothes_colors))
  end

  # The factor of a textured material. A gray texture (a hair) takes the
  # color of the order, or the mean color of the texture before it was
  # gray. Another texture takes the ratio of the color of the order to its
  # mean color: a tint, which can only make it darker.
  defp tint(spec, %{gray: gray} = a, o) when is_number(gray),
    do: Map.put(spec, "color", Enum.map(Map.get(o.colors, a.name, a.color), &min(255, round(&1 * 255 / gray))))

  defp tint(spec, a, o) do
    case Map.fetch(o.colors, a.name) do
      {:ok, c} -> Map.put(spec, "color", Enum.zip_with(c, a.color, &min(255, round(&1 * 255 / max(&2, 1)))))
      :error -> spec
    end
  end

  defp textured(path, alpha) do
    mime = if String.ends_with?(path, ".png"), do: "image/png", else: "image/jpeg"
    spec = %{"color" => [255, 255, 255], "roughness" => 0.75, "metalness" => 0.0, "image" => {mime, File.read!(path)}}
    if alpha, do: Map.merge(spec, %{"alpha_mode" => "MASK", "double_sided" => true}), else: spec
  end

  # --- The nodes of the figure ---------------------------------------------------

  defp nodes(name, %Skeleton{bones: bones} = skeleton, prims, pose, head) do
    index = bones |> Enum.with_index(1) |> Map.new(fn {b, i} -> {b.name, i} end)
    locals = Skeleton.locals(skeleton, pose)

    bone_nodes =
      for b <- bones do
        %Scene.Node{
          name: b.name,
          parent: if(b.parent, do: index[b.parent], else: 0),
          frame: locals[b.name],
          scale: if(b.name == "head", do: head / 1, else: 1.0)
        }
      end

    # glTF ignores the frame of a skinned mesh: the mesh is a root node.
    mesh = %Scene.Node{name: name <> "_mesh", skin: 0, primitives: prims}
    root = %Scene.Node{name: name}

    skin = %{
      name: name,
      joints: Enum.map(bones, &index[&1.name]),
      inverse_bind: Enum.map(bones, &Frame.invert(&1.frame)),
      skeleton: 1
    }

    {[root | bone_nodes] ++ [mesh], skin}
  end

  # The ports of a person: the ground and the hips (at rest), and the
  # ports on the bones for the props (`World.Figure.hold/4`).
  defp ports(bones, points, weights, ground) do
    by = Map.new(bones, &{&1.name, &1})
    index = bones |> Enum.with_index() |> Map.new(fn {b, i} -> {b.name, i} end)
    at = fn v -> Vec.sub(to_world(elem(points, v)), {0.0, 0.0, ground}) end
    # The points of the skin that follow a bone (half or more).
    skin = fn bone ->
      for {v, ws} <- weights, Enum.any?(ws, fn {b, w} -> b == index[bone] and w >= 0.5 end), do: at.(v)
    end

    {{x0, y0, _}, {x1, y1, top}} = Vec.bounds(skin.("head"))
    back = skin.("spine_03")
    {_, ymin, _} = Vec.bounds(back) |> elem(0)
    spine = by["spine_03"]

    on_bones =
      [
        {"crown", "head", Part.port("crown", {(x0 + x1) / 2, (y0 + y1) / 2, top}, {0, 0, 1}, {0, 1, 0})},
        {"back", "spine_03",
         Part.port("back", {0.0, ymin - 0.01, (elem(spine.head, 2) + elem(spine.tail, 2)) / 2}, {0, -1, 0}, {0, 0, 1})}
      ] ++
        for side <- ~w(l r), {name, bone, port} <- [grip(by, side), sole(by, side)], do: {name, bone, port}

    pelvis = by["pelvis"]

    Map.merge(
      %{
        "ground" => Part.port("ground", {0.0, 0.0, 0.0}, {0, 0, 1}, {0, 1, 0}),
        "hips" => Part.port("hips", pelvis.head, {0, 0, 1}, {0, 1, 0})
      },
      Map.new(on_bones, fn {name, bone, port} -> {name, on_bone(port, by[bone])} end)
    )
  end

  # The grip of a hand: in the palm, where a closed hand holds a handle.
  # The axis is the line of the handle, to the side of the thumb; `up`
  # goes out of the palm.
  defp grip(by, side) do
    [hand, middle, index, pinky] = Enum.map(~w(hand middle_01 index_01 pinky_01), &by["#{&1}_#{side}"])
    along = Vec.norm(Vec.sub(middle.head, hand.head))
    across = Vec.norm(Vec.sub(index.head, pinky.head))
    palm = Vec.scale(Vec.norm(Vec.cross(along, across)), if(side == "l", do: 1.0, else: -1.0))
    at = Vec.add(Vec.lerp(hand.head, middle.head, 0.55), Vec.scale(palm, 0.03))
    axis = Vec.norm(Vec.sub(across, Vec.scale(palm, Vec.dot(across, palm))))
    {"grip_#{side}", "hand_#{side}", Part.port("grip_#{side}", at, axis, palm)}
  end

  # The sole of a foot: on the ground under the middle of the foot, its
  # axis down, `up` to the toes.
  defp sole(by, side) do
    {foot, ball} = {by["foot_#{side}"], by["ball_#{side}"]}
    {x, y, _} = Vec.lerp(foot.head, ball.head, 0.5)
    {dx, dy, _} = Vec.sub(ball.head, foot.head)
    {"sole_#{side}", "foot_#{side}", Part.port("sole_#{side}", {x, y, 0.0}, {0, 0, -1}, {dx, dy, 0.0})}
  end

  # A port in the axes of World of the person at rest, as a port on a
  # bone: in the axes of the bone.
  defp on_bone(port, bone) do
    f = Frame.compose(Frame.invert(bone.frame), Port.frame(port))
    %{Port.new(port.name, f.at, f.z, f.y) | bone: bone.name}
  end
end
