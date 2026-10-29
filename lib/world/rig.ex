defmodule World.Rig do
  @moduledoc """
  A figure from bones: the data of a rig in, a `World.Figure` out, with
  a skin: a base mesh with the weights of its bones, or a skin that the
  build makes around the bones. For an animal, or for any figure with
  bones that is not a person.

  A bone of a rig is a map:

  - `name`, `parent` (nil for the root), `head` and `tail` (points in the
    axes of the figure at rest: x to the right side, y to the front, z
    up, the ground at z = 0);
  - `x`: the hinge of the bone ({1, 0, 0} by default): the axes of the
    bone are y from the head to the tail, x the hinge, z = x × y;
  - `radius`: `{{x, z}, {x, z}}`, the half sizes of the body around the
    bone at its head and at its tail (in its axes x and z), or nil for a
    bone with no body;
  - `material`: the material of its body (`:fur` by default).

  With no base mesh and no `blend`, the skin is a tube around each bone
  with a body: rings of points at the head, the middle and the tail, and
  a round cap at each end. The points at the head follow the bone and
  its parent (half each), so the joint bends smooth; the others follow
  the bone. The tubes of two bones meet inside each other at the joint.
  """
  alias World.{Blob, Detail, Figure, Frame, Port, Scene, Vec}
  alias World.People.{Pose, Skeleton}

  @doc """
  A figure from a rig. The options: `bones` (the bones, parents first),
  `limbs` (`World.Limb`s), `joints` (`World.Joint`s), `ports` (a list of
  `{name, bone, port}`: a port in the axes of the figure at rest, on the
  bone, or on no bone with nil), `spheres` (a list of `{center, radius,
  bone, material}`: the eyes, a nose; a center `{:on, from, dir}` is on
  the skin, on the ray from `from`), `mesh` (a base mesh in place of a
  skin that the build makes: `%{points, faces, weights, smooth,
  material, roles, colors}`, the weights a map of a bone to a list of
  `{point, weight}`, `roles` the material of each face, or one `material`
  for all, `colors` an `{r, g, b}` (0 to 255) for each point: the
  colors of the vertices, that the color of the material multiplies;
  `colored` the roles that have them, all by default),
  `parts` (a list of `{material, bone, points, triangles}`: a shape on
  one bone, each point `{position, normal}` at rest: horns), `blend` and `step` (a smooth skin,
  `World.Blob`: the width of the blend of two bodies, and the step of
  its grid at near, in meters; with no blend, a tube around each bone),
  `materials` (a material role to
  its spec), `pose` (a pose, or a function of the skeleton to a pose), `animations` (a list of functions of the skeleton to
  an animation, as `clip/5`), `kind`, `params` and `sources`.
  """
  def figure(name, opts) do
    bones = Enum.map(Keyword.fetch!(opts, :bones), &frame/1)
    skeleton = Skeleton.new(bones, Keyword.get(opts, :limbs, []))

    pose =
      case Keyword.get(opts, :pose, %{}) do
        f when is_function(f, 1) -> f.(skeleton)
        p -> p
      end
      |> Pose.expand()

    index = bones |> Enum.with_index() |> Map.new(fn {b, i} -> {b.name, i} end)
    locals = Skeleton.locals(skeleton, pose)

    bone_nodes =
      for b <- bones,
          do: %Scene.Node{name: b.name, parent: if(b.parent, do: index[b.parent] + 1, else: 0), frame: locals[b.name]}

    {prims, surface} =
      case Keyword.get(opts, :mesh) do
        nil -> {skin(bones, index, opts), blob_surface(bones, index, opts)}
        mesh -> mesh_skin(mesh, index)
      end

    prims =
      prims ++
        spheres(Keyword.get(opts, :spheres, []), index, surface) ++
        for {material, bone, points, tris} <- Keyword.get(opts, :parts, []),
            do: join(material, [{Enum.map(points, fn {p, n} -> {p, n, own(index[bone])} end), tris}])

    mesh = %Scene.Node{name: name <> "_mesh", skin: 0, primitives: prims}

    skin = %{
      name: name,
      joints: Enum.map(1..length(bones), & &1),
      inverse_bind: Enum.map(bones, &Frame.invert(&1.frame)),
      skeleton: 1
    }

    by_name = Map.new(bones, &{&1.name, &1})

    %Figure{
      name: name,
      kind: Keyword.get(opts, :kind, :animal),
      params: Keyword.get(opts, :params, %{}),
      sources: Keyword.get(opts, :sources, []),
      nodes: [%Scene.Node{name: name} | bone_nodes] ++ [mesh],
      skins: [skin],
      animations: for(a <- Keyword.get(opts, :animations, []), do: a.(skeleton)),
      materials: Keyword.get(opts, :materials, %{}),
      ports:
        Map.new(Keyword.get(opts, :ports, []), fn
          {port_name, nil, port} -> {port_name, %{port | name: port_name}}
          {port_name, bone, port} -> {port_name, on_bone(%{port | name: port_name}, by_name[bone])}
        end),
      skeleton: skeleton,
      pose: pose,
      joints: Keyword.get(opts, :joints, [])
    }
  end

  @doc """
  A port in the axes of a figure at rest, as a port on a bone: in the
  axes of the bone (the bone has its `frame` at rest).
  """
  def on_bone(%Port{} = port, bone) do
    f = Frame.compose(Frame.invert(bone.frame), Port.frame(port))
    %{Port.new(port.name, f.at, f.z, f.y) | bone: bone.name}
  end

  @doc """
  An animation of `steps` frames in `length` seconds: at each time, `at`
  gives a pose on top of the pose `base`. The channels are the bones
  that move (`World.People.Pose.channels/4`).
  """
  def clip(name, %Skeleton{bones: bones} = s, length, steps, at, base \\ %{}) do
    times = for k <- 0..steps, do: k * length / steps
    frames = for t <- times, do: Skeleton.locals(s, Pose.expand(Map.merge(base, at.(t))))
    %{name: name, channels: Pose.channels(bones, Skeleton.locals(s, Pose.expand(base)), frames, times)}
  end

  # The frame of a bone at rest: y from the head to the tail, x the hinge.
  defp frame(b) do
    head = Vec.float(b.head)
    y = Vec.norm(Vec.sub(Vec.float(b.tail), head))
    hint = Vec.float(Map.get(b, :x, {1.0, 0.0, 0.0}))
    x = Vec.norm(Vec.sub(hint, Vec.scale(y, Vec.dot(hint, y))))

    b
    |> Map.merge(%{head: head, tail: Vec.float(b.tail), parent: Map.get(b, :parent)})
    |> Map.put(:frame, Frame.new(head, Vec.cross(x, y), y))
  end

  # The skin: with a `blend`, one smooth surface around the bones with a
  # body (`World.Blob`), and a tube around each bone with `skin: :tube`
  # (a thin ear); with no blend, a tube around each bone. One primitive
  # for each material.
  defp skin(bones, index, opts) do
    {blend, step} = {Keyword.get(opts, :blend), Keyword.get(opts, :step, 0.012)}
    bodies = Enum.filter(bones, &Map.get(&1, :radius))
    {smooth, tubes} = Enum.split_with(bodies, &(blend && Map.get(&1, :skin, :blob) == :blob))

    blob =
      if smooth == [],
        do: [],
        else: [
          {Map.get(hd(smooth), :material, :fur),
           Blob.mesh(Enum.map(smooth, &Map.put(&1, :index, index[&1.name])), Detail.step(step), blend)}
        ]

    (blob ++ Enum.map(tubes, &{Map.get(&1, :material, :fur), tube(&1, index)}))
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort()
    |> Enum.map(fn {material, parts} -> join(material, parts) end)
  end

  # The points of a tube: rings at the head, the middle and the tail, and
  # a pole at each end, a little out of the ring (a round cap).
  defp tube(b, index) do
    n = Detail.sides(12)
    {{xh, zh}, {xt, zt}} = b.radius
    len = Vec.len(Vec.sub(b.tail, b.head))
    me = index[b.name]
    head = if b.parent && index[b.parent], do: {{me, index[b.parent], 0, 0}, {0.5, 0.5, 0.0, 0.0}}, else: own(me)

    rings =
      for {t, w} <- [{0.0, head}, {0.5, own(me)}, {1.0, own(me)}] do
        {rx, rz} = {xh + (xt - xh) * t, zh + (zt - zh) * t}

        for j <- 0..(n - 1) do
          a = 2 * :math.pi() * j / n
          {c, s} = {:math.cos(a), :math.sin(a)}
          {Frame.point(b.frame, {rx * c, t * len, rz * s}), Frame.dir(b.frame, Vec.norm({c / rx, 0.0, s / rz})), w}
        end
      end

    start = {Frame.point(b.frame, {0.0, -0.6 * min(xh, zh), 0.0}), Frame.dir(b.frame, {0.0, -1.0, 0.0}), head}
    finish = {Frame.point(b.frame, {0.0, len + 0.6 * min(xt, zt), 0.0}), Frame.dir(b.frame, {0.0, 1.0, 0.0}), own(me)}
    points = List.flatten(rings) ++ [start, finish]
    k = fn i, j -> i * n + rem(j, n) end
    {p0, p1} = {3 * n, 3 * n + 1}

    tris =
      for(
        i <- 0..1,
        j <- 0..(n - 1),
        t <- [[k.(i, j), k.(i + 1, j), k.(i + 1, j + 1)], [k.(i, j), k.(i + 1, j + 1), k.(i, j + 1)]],
        do: t
      ) ++
        for(j <- 0..(n - 1), do: [k.(0, j), k.(0, j + 1), p0]) ++
        for j <- 0..(n - 1), do: [k.(2, j + 1), k.(2, j), p1]

    {points, tris}
  end

  defp own(bone), do: {{bone, 0, 0, 0}, {1.0, 0.0, 0.0, 0.0}}

  # The point of the smooth skin on a ray (`World.Blob.surface/4`).
  defp blob_surface(bones, index, opts) do
    smooth =
      for b <- bones, Map.get(b, :radius), Map.get(b, :skin, :blob) == :blob, do: Map.put(b, :index, index[b.name])

    fn from, dir -> Blob.surface(smooth, from, dir, Keyword.fetch!(opts, :blend)) end
  end

  # The skin of a base mesh: its points (at rest), its faces, and the
  # weights of each bone (a map of a bone name to a list of `{point,
  # weight}`), smooth `smooth` steps at near (one less at mid, none at
  # far, `World.Subdivision`). Gives the primitive and the point of the
  # mesh on a ray.
  defp mesh_skin(%{points: points, faces: faces, weights: weights} = mesh, index) do
    by_point =
      for {bone, list} <- weights, {i, w} <- list, reduce: %{} do
        acc -> Map.update(acc, i, %{index[bone] => w}, &Map.put(&1, index[bone], w))
      end

    # The color of a point (when the mesh has colors) goes with its
    # weights in the smooth steps, as the keys :r, :g and :b.
    colors = Map.get(mesh, :colors)
    color = fn i -> if colors, do: Enum.at(colors, i) |> then(fn {r, g, b} -> %{r: r, g: g, b: b} end), else: %{} end

    start =
      points
      |> Enum.with_index()
      |> Enum.map(fn {p, i} -> {Vec.float(p), Map.merge(Map.get(by_point, i, %{}), color.(i))} end)

    steps = max(Map.get(mesh, :smooth, 0) - %{near: 0, mid: 1, far: 2}[Detail.level()], 0)
    roles = Map.get(mesh, :roles) || List.duplicate(Map.get(mesh, :material, :fur), length(faces))

    # Each step makes a face of n sides into n faces, in the order of the
    # faces: each new face keeps the role of its face.
    {points, faces, roles} =
      Enum.reduce(List.duplicate(1, steps), {start, faces, roles}, fn 1, {points, faces, roles} ->
        {points, new} = World.Subdivision.smooth(points, faces, 1)
        {points, new, Enum.flat_map(Enum.zip(faces, roles), fn {f, r} -> List.duplicate(r, length(f)) end)}
      end)

    places = points |> Enum.map(&elem(&1, 0)) |> List.to_tuple()
    fan = fn [a | rest] -> rest |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [b, c] -> [a, b, c] end) end
    tris = faces |> Enum.zip(roles) |> Enum.flat_map(fn {f, r} -> Enum.map(fan.(f), &{&1, r}) end)

    # The normal of a point: the sum of the normals of its faces (each as
    # large as its face).
    normals =
      Enum.reduce(tris, %{}, fn {[a, b, c] = t, _}, acc ->
        n = Vec.cross(Vec.sub(elem(places, b), elem(places, a)), Vec.sub(elem(places, c), elem(places, a)))
        Enum.reduce(t, acc, &Map.update(&2, &1, n, fn m -> Vec.add(m, n) end))
      end)

    verts =
      for {{p, ws}, i} <- Enum.with_index(points) do
        top = ws |> Enum.filter(&is_integer(elem(&1, 0))) |> Enum.sort_by(fn {b, w} -> {-w, b} end) |> Enum.take(4)
        sum = top |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        top = if sum > 0, do: Enum.map(top, fn {b, w} -> {b, w / sum} end), else: [{0, 1.0}]
        top = top ++ List.duplicate({0, 0.0}, 4 - length(top))

        {p, Vec.norm(Map.get(normals, i, {0.0, 0.0, 1.0})),
         {List.to_tuple(Enum.map(top, &elem(&1, 0))), List.to_tuple(Enum.map(top, &elem(&1, 1)))},
         if(colors, do: {ws.r, ws.g, ws.b})}
      end
      |> List.to_tuple()

    # One primitive for each role, with the points of its faces only.
    prims =
      tris
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
      |> Enum.sort()
      |> Enum.map(fn {role, ts} ->
        used = ts |> List.flatten() |> Enum.uniq() |> Enum.sort()
        at = used |> Enum.with_index() |> Map.new()
        # The colors of the points only on the roles of `colored` (all by
        # default).
        keep? = role in Map.get(mesh, :colored, [role])
        points = for i <- used, do: if(keep?, do: elem(verts, i), else: put_elem(elem(verts, i), 3, nil))
        join(role, [{points, Enum.map(ts, fn t -> Enum.map(t, &at[&1]) end)}])
      end)

    triangles = for {[a, b, c], _} <- tris, do: {elem(places, a), elem(places, b), elem(places, c)}
    {prims, &hit(triangles, &1, &2)}
  end

  # The nearest point of the triangles on a ray (Möller and Trumbore), or
  # the start of the ray when it meets none.
  defp hit(triangles, from, dir) do
    dir = Vec.norm(dir)

    ts =
      for {a, b, c} <- triangles,
          e1 = Vec.sub(b, a),
          e2 = Vec.sub(c, a),
          p = Vec.cross(dir, e2),
          det = Vec.dot(e1, p),
          abs(det) > 1.0e-12,
          s = Vec.sub(from, a),
          u = Vec.dot(s, p) / det,
          u >= 0 and u <= 1,
          q = Vec.cross(s, e1),
          v = Vec.dot(dir, q) / det,
          v >= 0 and u + v <= 1,
          t = Vec.dot(e2, q) / det,
          t > 0,
          do: t

    Vec.add(from, Vec.scale(dir, Enum.min(ts, fn -> 0.0 end)))
  end

  # A small sphere on one bone: an eye, a nose. A center `{:on, from,
  # dir}` is on the smooth skin, on the ray from `from` in the direction
  # `dir`: the sphere is a third in the skin.
  defp spheres(list, index, surface) do
    center = fn
      {:on, from, dir}, r -> Vec.sub(surface.(Vec.float(from), Vec.float(dir)), Vec.scale(Vec.norm(dir), r / 3))
      c, _r -> Vec.float(c)
    end

    list
    |> Enum.map(fn {c, r, bone, material} -> {material, ball(center.(c, r), r, own(index[bone]))} end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.sort()
    |> Enum.map(fn {material, parts} -> join(material, parts) end)
  end

  defp ball(c, r, w) do
    {rings, n} = {6, Detail.sides(10)}

    points =
      for i <- 0..rings, j <- 0..(n - 1) do
        {lat, lon} = {:math.pi() * i / rings, 2 * :math.pi() * j / n}
        d = {:math.sin(lat) * :math.cos(lon), :math.sin(lat) * :math.sin(lon), -:math.cos(lat)}
        {Vec.add(c, Vec.scale(d, r)), d, w}
      end

    k = fn i, j -> i * n + rem(j, n) end

    tris =
      for i <- 0..(rings - 1),
          j <- 0..(n - 1),
          t <- [[k.(i, j), k.(i, j + 1), k.(i + 1, j + 1)], [k.(i, j), k.(i + 1, j + 1), k.(i + 1, j)]],
          do: t

    {points, tris}
  end

  # The parts of one material in one primitive.
  defp join(material, parts) do
    {points, indices, _} =
      Enum.reduce(parts, {[], [], 0}, fn {points, tris}, {all, indices, offset} ->
        {all ++ points, indices ++ Enum.map(List.flatten(tris), &(&1 + offset)), offset + length(points)}
      end)

    %Scene.Primitive{
      material: material,
      positions: Enum.map(points, &elem(&1, 0)),
      normals: Enum.map(points, &elem(&1, 1)),
      indices: indices,
      joints: Enum.map(points, &elem(elem(&1, 2), 0)),
      weights: Enum.map(points, &elem(elem(&1, 2), 1)),
      colors: if(match?({_, _, _, {_, _, _}}, hd(points)), do: Enum.map(points, &elem(&1, 3)))
    }
  end
end
