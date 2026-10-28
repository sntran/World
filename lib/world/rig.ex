defmodule World.Rig do
  @moduledoc """
  A figure from bones: the data of a rig in, a `World.Figure` out, with
  a skin that the build makes around the bones. For an animal, or for any
  figure with no mesh of its own.

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

  The skin is a tube around each bone with a body: rings of points at
  the head, the middle and the tail, and a round cap at each end. The
  points at the head follow the bone and its parent (half each), so the
  joint bends smooth; the others follow the bone. The tubes of two bones
  meet inside each other at the joint.
  """
  alias World.{Detail, Figure, Frame, Port, Scene, Vec}
  alias World.People.{Pose, Skeleton}

  @doc """
  A figure from a rig. The options: `bones` (the bones, parents first),
  `limbs` (`World.Limb`s), `joints` (`World.Joint`s), `ports` (a list of
  `{name, bone, port}`: a port in the axes of the figure at rest, on the
  bone, or on no bone with nil), `spheres` (a list of `{center, radius,
  bone, material}`: the eyes, a nose), `materials` (a material role to
  its spec), `pose`, `animations` (a list of functions of the skeleton to
  an animation, as `clip/5`), `kind`, `params` and `sources`.
  """
  def figure(name, opts) do
    bones = Enum.map(Keyword.fetch!(opts, :bones), &frame/1)
    skeleton = Skeleton.new(bones, Keyword.get(opts, :limbs, []))
    pose = Pose.expand(Keyword.get(opts, :pose, %{}))
    index = bones |> Enum.with_index() |> Map.new(fn {b, i} -> {b.name, i} end)
    locals = Skeleton.locals(skeleton, pose)

    bone_nodes =
      for b <- bones,
          do: %Scene.Node{name: b.name, parent: if(b.parent, do: index[b.parent] + 1, else: 0), frame: locals[b.name]}

    prims = skin(bones, index) ++ spheres(Keyword.get(opts, :spheres, []), index)
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

  # A tube around each bone with a body, one primitive for each material.
  defp skin(bones, index) do
    bones
    |> Enum.filter(&Map.get(&1, :radius))
    |> Enum.map(&{Map.get(&1, :material, :fur), tube(&1, index)})
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

  # A small sphere on one bone: an eye, a nose.
  defp spheres(list, index) do
    list
    |> Enum.map(fn {c, r, bone, material} -> {material, ball(Vec.float(c), r, own(index[bone]))} end)
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
      weights: Enum.map(points, &elem(elem(&1, 2), 1))
    }
  end
end
