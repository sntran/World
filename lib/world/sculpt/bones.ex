defmodule World.Sculpt.Bones do
  @moduledoc """
  A sculpture with bones (`docs/plans/0009-sculpture-finish.md`, D6): the
  meshes of a sculpture and its bones in, a `World.Figure` out, with one
  skinned mesh and its clips.

  A bone is a map of `name`, `parent` (nil for the root), `head` and
  `tail` (points in the axes of the sculpture: x to the right, y to the
  front, z up), parents first. Each point of the meshes follows the bones
  near it: the nearest bone (the distance to the line from its head to
  its tail), and each other bone less as it is farther, down to nothing
  at `blend` more than the nearest (at most four bones, `World.Rig`).

  The clips come from two places:

  - a body plan (`plans/0`), when the bones have its names: its limbs,
    its joints, its ports and its animations (a fish swims);
  - the `clips` of the data: each a name, a length (s) and keys, each key
    a time and a pose (a bone to its turns in degrees: `flex`, `spread`,
    `twist`). The pose between two keys is the mean by the time.
  """
  alias World.{Mesh, Rig, Vec}

  # The body plans whose animations need no clips of a template.
  @plans %{"fish" => World.Animals.Fish}
  @turns %{"flex" => :flex, "spread" => :spread, "twist" => :twist}
  # The frames of a clip from keys in one second.
  @rate 12

  @doc "The names of the body plans of a sculpture."
  def plans, do: @plans |> Map.keys() |> Enum.sort()

  @doc "The bones of a body plan."
  def bones(plan), do: @plans[plan].bones()

  @doc "The names of the animations of a body plan."
  def animations(plan), do: @plans[plan].animations()

  @doc "The names of the turns of a bone in a pose."
  def turns, do: @turns |> Map.keys() |> Enum.sort()

  @doc """
  The figure of the meshes of a sculpture (`World.Sculpt.model/2`) with
  `bones`. The options: `plan` (the name of a body plan), `gait` (its
  numbers), `clips` (`[%{name, length, keys: [{time, pose}]}]`), `blend`
  (m; half the mean length of the bones by default), `ports` (a list of
  `World.Port`, each on the nearest bone), `sources`.
  """
  def figure(name, meshes, bones, opts \\ []) do
    plan = @plans[Keyword.get(opts, :plan)]
    bones = Enum.map(bones, &bone(&1, plan))
    by = Map.new(bones, &{&1.name, &1})
    blend = Keyword.get(opts, :blend) || mean_length(bones) / 2
    mesh = join(meshes)
    weights = weights(mesh.points, bones, blend)
    gait = Keyword.get(opts, :gait, %{})

    planned =
      if plan do
        h = plan.height(mesh.points, weights)
        for a <- plan.animations(), do: &plan.animation(a, &1, h, gait)
      else
        []
      end

    Rig.figure(name,
      bones: bones,
      mesh: Map.put(mesh, :weights, weights),
      limbs: if(plan, do: plan.limbs(by), else: []),
      joints: if(plan, do: plan.joints(by), else: []),
      ports:
        if(plan, do: plan.ports(by), else: []) ++
          for(p <- Keyword.get(opts, :ports, []), do: {p.name, nearest(p.at, bones), p}),
      animations: planned ++ for(c <- Keyword.get(opts, :clips, []), do: &clip(c, &1)),
      kind: :item,
      sources: Keyword.get(opts, :sources, [])
    )
  end

  # A bone of the rig: its hinge is the hinge of its plan, or across the
  # body (x); for a bone that lies along its hinge, z.
  defp bone(b, plan) do
    {head, tail} = {Vec.float(b.head), Vec.float(b.tail)}
    dir = Vec.norm(Vec.sub(tail, head))
    hint = if plan, do: plan.hinge(b.name, dir), else: {1.0, 0.0, 0.0}
    x = if abs(Vec.dot(hint, dir)) > 0.9, do: {0.0, 0.0, 1.0}, else: hint
    %{name: b.name, parent: Map.get(b, :parent), head: head, tail: tail, x: x}
  end

  defp mean_length(bones), do: Enum.sum(for b <- bones, do: Vec.len(Vec.sub(b.tail, b.head))) / length(bones)

  # One mesh from the meshes of the sculpture (one for each material):
  # the points in one list, with the role of each face.
  defp join(meshes) do
    {points, faces, roles, normals, colors, _} =
      Enum.reduce(meshes, {[], [], [], [], [], 0}, fn %Mesh{} = m, {ps, fs, rs, ns, cs, offset} ->
        count = length(m.points)

        {[m.points | ps], [Enum.map(m.faces, fn f -> Enum.map(f, &(&1 + offset)) end) | fs],
         [List.duplicate(m.material, length(m.faces)) | rs], [m.normals || [] | ns],
         [m.colors || List.duplicate({255, 255, 255}, count) | cs], offset + count}
      end)

    all = fn lists -> lists |> Enum.reverse() |> Enum.concat() end
    {points, normals} = {all.(points), all.(normals)}

    %{
      points: points,
      faces: all.(faces),
      roles: all.(roles),
      normals: if(length(normals) == length(points), do: normals),
      colors: if(Enum.any?(meshes, & &1.colors), do: all.(colors))
    }
  end

  # The weights of the points: a bone to its `{point, weight}`.
  defp weights(points, bones, blend) do
    for {p, i} <- Enum.with_index(points), reduce: Map.new(bones, &{&1.name, []}) do
      acc ->
        near = for b <- bones, do: {b.name, distance(p, b)}
        {_, best} = Enum.min_by(near, &elem(&1, 1))

        for {name, d} <- near, w = max(0.0, 1 - (d - best) / blend) ** 2, w > 0, reduce: acc do
          acc -> Map.update!(acc, name, &[{i, w} | &1])
        end
    end
    |> Map.new(fn {name, list} -> {name, Enum.reverse(list)} end)
  end

  # The distance from a point to the line of a bone, from its head to its tail.
  defp distance(p, %{head: head, tail: tail}) do
    along = Vec.sub(tail, head)
    t = Vec.dot(Vec.sub(p, head), along) / Vec.dot(along, along)
    Vec.len(Vec.sub(p, Vec.add(head, Vec.scale(along, min(max(t, 0.0), 1.0)))))
  end

  defp nearest(p, bones), do: Enum.min_by(bones, &distance(Vec.float(p), &1)).name

  # A clip from keys: the pose at a time is the mean of the two keys
  # round it, by the time.
  defp clip(%{name: name, length: length, keys: keys}, skeleton) do
    keys = Enum.sort_by(keys, &elem(&1, 0))
    Rig.clip(name, skeleton, length, max(round(length * @rate), 1), &pose(keys, &1))
  end

  defp pose([{_, only}], _t), do: turns(only, only, 0.0)
  defp pose([{t0, a}, _ | _], t) when t <= t0, do: turns(a, a, 0.0)
  defp pose([{t0, a}, {t1, b} | _], t) when t <= t1, do: turns(a, b, (t - t0) / (t1 - t0))
  defp pose([_ | rest], t), do: pose(rest, t)

  # The turns of each bone of two poses, a part `k` of the way from the
  # first to the second. A bone or a turn that a pose does not have is at
  # its rest there.
  defp turns(a, b, k) do
    for name <- Enum.uniq(Map.keys(a) ++ Map.keys(b)), into: %{} do
      {from, to} = {Map.get(a, name, %{}), Map.get(b, name, %{})}

      {name,
       for kind <- turns(), Map.has_key?(from, kind) or Map.has_key?(to, kind) do
         {v0, v1} = {Map.get(from, kind, 0), Map.get(to, kind, 0)}
         {@turns[kind], v0 + (v1 - v0) * k}
       end}
    end
  end
end
