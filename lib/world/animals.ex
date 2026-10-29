defmodule World.Animals do
  @moduledoc """
  The animals of the world: figures from bones (`World.Rig`). An animal
  is a species of a body plan.

  - The body plan (code) gives the bones of World, the joints, the
    limbs, the ports, the pose and the gaits: `World.Animals.Quadruped`
    (four legs and a tail) and `World.Animals.Primate` (two arms with
    hands, two legs and a tail).
  - The species (data, `priv/animals/species/NAME.json`) is numbers on
    a template (`priv/animals/templates/NAME.json`: one mesh for a body
    plan, and `World.Animals.Shape`). The templates of four legs are the
    animals of the Ultimate pack of Quaternius, on one rig, from
    `scripts/gltf_figure.exs`, with their clips from
    `scripts/gltf_clips.exs`; the template of primates is the body of
    MakeHuman with a tail, from `scripts/primate_template.exs`.

  The keys of a species (`docs/format.md`, "An animal"): `name`,
  `about`, `plan`, `template`, `sources`, `height` (in meters: at the
  withers for a quadruped, the length of the head and the body for a
  primate), `shape` (numbers), `colors` (a role to its color; `fur` is
  the base color of the coat), `markings` (a region of the coat to its
  color), `fur` (the length of the fur, m: `coat` and a region to its
  length), `space` (the coefficients of the shape space of the template,
  `World.Animals.Space`), `without` (roles whose faces go) and `gait`. Each animal has
  the UVs of its template (`World.Animals.UV`), `_FUR` and `_FUR_DIR` on
  its fur, its mane and its dark parts (`World.Animals.Shape.fur/3`,
  `fur_dirs/3`), and
  `uv_size` in its params (the length of one unit of UV on the skin, m).
  The keys of a
  template: `mesh`, `bones` (a bone of World to the bones of the mesh),
  `materials` (a material of the mesh to a role), `smooth`, `parents`,
  `muzzle` and `brow`.
  """
  alias World.{Frame, Rig, Vec}
  alias World.Animals.{Shape, Space, UV}
  alias World.People.{Pose, Skeleton}

  @root Path.join([__DIR__, "..", "..", "priv", "animals"])
  @species_files Path.wildcard(Path.join([@root, "species", "*.json"]))
  for f <- @species_files, do: @external_resource(f)
  @species Map.new(@species_files, fn f -> {Path.basename(f, ".json"), f |> File.read!() |> JSON.decode!()} end)
  @hash :erlang.md5(Enum.join(@species_files))

  # A new file of a species compiles the module again.
  @doc false
  def __mix_recompile__?, do: :erlang.md5(Enum.join(Path.wildcard(Path.join([@root, "species", "*.json"])))) != @hash

  @template_files Path.wildcard(Path.join([@root, "templates", "*.json"]))
  for f <- @template_files, do: @external_resource(f)
  @templates Map.new(@template_files, fn f -> {Path.basename(f, ".json"), f |> File.read!() |> JSON.decode!()} end)

  # The colors of the roles that no mesh, template or species gives.
  @colors %{"horn" => [172, 161, 117], "eye" => [24, 24, 24], "nose" => [40, 34, 32], "white" => [240, 240, 240]}

  @plans %{"quadruped" => World.Animals.Quadruped, "primate" => World.Animals.Primate}
  @roles %{
    "fur" => :fur,
    "marking" => :marking,
    "skin" => :skin,
    "eye" => :eye,
    "nose" => :nose,
    "dark" => :dark,
    "white" => :white,
    "horn" => :horn,
    "hoof" => :hoof,
    "muzzle" => :muzzle,
    "iris" => :iris,
    "mane" => :mane
  }

  @doc "The names of the species."
  def species, do: @species |> Map.keys() |> Enum.sort()

  @doc "The data of a species (its JSON)."
  def spec(name) do
    Map.get(@species, name) || raise ArgumentError, "unknown species #{inspect(name)}: #{Enum.join(species(), ", ")}"
  end

  @doc """
  The names of the animations of a species: of its body plan, but a clip
  only when the clips of its template have it, and `wag` only when its
  template has a tail.
  """
  def animations(name) do
    s = spec(name)
    plan = @plans[s["plan"]]
    t = @templates[s["template"]]
    clips = clips(t)

    plan.animations()
    |> Enum.reject(&(&1 in plan.clips() and not Map.has_key?(clips, &1)))
    |> Enum.reject(&(&1 == "wag" and not Map.has_key?(t["bones"], "tail_01")))
  end

  @doc """
  An animal of a species. The options: `coat` (`[r, g, b]`: the color
  of `fur`, or the base color of the coat of a template; the color of
  the species by default), `markings` (a template: a region of the coat
  to its color, over the colors of the species), `shape` (a template:
  numbers of `World.Animals.Shape` over the numbers of the species),
  `space` (the coefficients of the shape space of the template, over
  the space of the species; an `ArgumentError` for a template with no
  space), `size` (a scale of all the animal: 1 is the height of the
  species),
  and `animations` (names of `animations/1`).
  """
  def animal(name, opts) do
    s = spec(name)
    plan = @plans[s["plan"]]
    k = Keyword.get(opts, :size, 1.0) / 1
    names = Keyword.get(opts, :animations, [])

    for a <- names,
        a not in animations(name),
        do: raise(ArgumentError, "unknown animation of a #{name} #{inspect(a)}: #{Enum.join(animations(name), ", ")}")

    # A species takes the mesh, the bones and the materials of its
    # template.
    t = Map.merge(@templates[s["template"]], s)

    {data, bones, points, weights} = rest(t, plan)

    # The faces that the species keeps (a pig has no horns of a cow), and
    # the role of each.
    without = Enum.map(Map.get(s, "without", []), &@roles[&1])

    # The UVs of the template (`World.Animals.UV`), at rest.
    {faces, roles, uvs} =
      [
        data["faces"],
        Enum.map(data["face_materials"], &material_role(t, data, &1)),
        UV.charts(bones, points, weights, data["faces"])
      ]
      |> Enum.zip()
      |> Enum.reject(fn {_, role, _} -> role in without end)
      |> unzip3()

    # The colors: of the materials of the mesh, of the template, of the
    # species, and the coat of the order.
    mesh_colors =
      for m <- data["materials"], m["color"], reduce: %{} do
        acc -> Map.put_new(acc, Map.get(t["materials"], m["name"], "fur"), m["color"])
      end

    coat = Keyword.get(opts, :coat) || get_in(s, ["colors", "fur"]) || mesh_colors["fur"]
    markings = Map.merge(Map.get(s, "markings", %{}), Keyword.get(opts, :markings, %{}))

    shape = Map.merge(s["shape"], Keyword.get(opts, :shape, %{}))
    regions = Shape.regions(bones, points, weights, eyes(t, data))
    # The coefficients of the shape space of the template.
    moves =
      case Keyword.get(opts, :space) || s["space"] do
        nil ->
          nil

        cs ->
          Space.moves(Space.get(t["mesh"]) || raise(ArgumentError, "the template #{t["mesh"]} has no shape space"), cs)
      end

    {bones, points} = Shape.apply(bones, points, weights, shape, t, moves)
    colors = if markings != %{}, do: Shape.colors(regions, coat, markings)
    fur = if f = s["fur"], do: Shape.fur(regions, f["coat"], Map.delete(f, "coat"))

    scale = s["height"] * k / plan.height(points, weights)
    at = &Vec.scale(&1, scale)
    clips = clips(t)

    bones =
      for b <- bones do
        {head, tail} = {at.(b.head), at.(b.tail)}
        %{b | head: head, tail: tail, x: plan.hinge(b.name, Vec.norm(Vec.sub(tail, head)))}
      end

    points = Enum.map(points, at)
    by = Map.new(bones, &{&1.name, &1})
    head_length = Vec.len(Vec.sub(by["head"].tail, by["head"].head))
    kept = faces |> List.flatten() |> MapSet.new()

    parts =
      horns(
        Map.get(shape, "horns", 0) * head_length,
        Map.get(shape, "horn_spread", 0),
        by["head"],
        points,
        weights,
        kept
      )

    # The colors of the roles that the animal uses; with markings, the
    # coat is in the colors of the points of the fur and of its lighter
    # parts, on a white material.
    used = MapSet.new(roles ++ Enum.map(parts, &elem(&1, 0)))

    colors_of =
      @colors
      |> Map.merge(mesh_colors)
      |> Map.merge(Map.get(t, "colors", %{}))
      |> Map.merge(Map.get(s, "colors", %{}))
      |> Map.put("fur", if(colors, do: [255, 255, 255], else: coat))
      |> then(&if(colors, do: Map.put(&1, "marking", [255, 255, 255]), else: &1))
      |> Map.filter(fn {role, _} -> @roles[role] in used end)

    Rig.figure(plan.figure_name(name),
      bones: bones,
      mesh: %{
        points: points,
        faces: faces,
        weights: Map.new(weights, fn {bone, m} -> {bone, Enum.sort(m)} end),
        smooth: Map.get(t, "smooth", 0),
        roles: roles,
        colors: colors,
        fur: fur && Enum.map(fur, &(&1 * k)),
        fur_dirs: fur && Shape.fur_dirs(bones, points, weights),
        uvs: uvs,
        # The colors of the coat on the fur and its lighter parts; the fur
        # also on the mane (of a horse) and the dark parts (the legs of a
        # fox).
        colored: [:fur, :marking],
        furred: [:fur, :marking, :mane, :dark]
      },
      limbs: plan.limbs(by),
      joints: plan.joints(by),
      ports: plan.ports(by),
      parts: parts,
      materials:
        Map.new(colors_of, fn {role, color} ->
          {@roles[role],
           %{
             "color" => color,
             "roughness" => if(role in ~w(eye dark nose horn hoof), do: 0.4, else: 0.9),
             "metalness" => 0.0
           }}
        end),
      animations:
        for a <- names do
          if clip = clips[a],
            do: &retarget(a, &1, clip, scale, skin(points, weights)),
            else: &plan.animation(a, &1, k * s["height"], Map.get(s, "gait", %{}))
        end,
      pose: &plan.stance(&1, Map.get(s, "gait", %{})),
      kind: :animal,
      params:
        %{"coat" => coat, "size" => k, "uv_size" => Float.round(UV.size(points, faces, uvs), 3)}
        |> Map.merge(plan.speeds(k * s["height"], Map.get(s, "gait", %{})))
        |> Map.merge(speeds(clips, scale)),
      sources: [data["source"] <> " " <> data["license"], s["about"] | s["sources"]]
    )
  end

  @doc "The shape space of the template of a species (`World.Animals.Space`), or nil."
  def space(name), do: Space.get(@templates[spec(name)["template"]]["mesh"])

  @doc """
  A template at rest, before the numbers of a shape: `%{template, bones,
  points, weights, eyes}` (in the units of its mesh; the bones of World,
  the weights of each bone of World, the points of the eyes).
  """
  def template(name) do
    t = Map.fetch!(@templates, name)
    {data, bones, points, weights} = rest(t, @plans[t["plan"]])
    %{template: t, bones: bones, points: points, weights: weights, eyes: eyes(t, data)}
  end

  # The points of the eyes of a mesh.
  defp eyes(t, data) do
    for {f, m} <- Enum.zip(data["faces"], data["face_materials"]),
        material_role(t, data, m) == :eye,
        i <- f,
        uniq: true,
        do: i
  end

  # The mesh of a species or a template, its bones of World and the
  # weights of each.
  defp rest(t, plan) do
    data =
      Path.join([:code.priv_dir(:world), "animals", "meshes", t["mesh"] <> ".json"]) |> File.read!() |> JSON.decode!()

    # A bone of World is one bone of the mesh, or a list: the first, and
    # bones that give it their weights.
    map = Map.new(t["bones"], fn {world, file} -> {world, List.wrap(file)} end)
    to_world = for {world, files} <- map, file <- files, into: %{}, do: {file, world}
    file_bones = Map.new(data["bones"], &{&1["name"], &1})
    # The bone of World of a bone of the mesh: its own, or of the nearest
    # bone above it.
    owner = fn file ->
      Stream.iterate(file, &file_bones[&1]["parent"]) |> Enum.take_while(& &1) |> Enum.find_value(&to_world[&1])
    end

    weights =
      for {file, list} <- data["weights"], world = owner.(file), world != nil, reduce: %{} do
        acc ->
          Map.update(acc, world, Map.new(list, &List.to_tuple/1), fn m ->
            Enum.reduce(list, m, fn [i, w], m -> Map.update(m, i, w, &(&1 + w)) end)
          end)
      end

    points = Enum.map(data["points"], &List.to_tuple/1)
    {data, bones(plan, map, Map.get(t, "parents", %{}), file_bones, owner, points, weights), points, weights}
  end

  # The clips of a template (`scripts/gltf_clips.exs`), or none. A
  # template with `clips` (a file with no clips for a walk) has the clips
  # of that template: the moves of the pelvis, the heights of the paws
  # and the speeds go to the units of its own mesh, by the heights of
  # the hips (the head of `hind_upper_l`).
  defp clips(%{"clips" => from} = t) do
    from = @templates[from]
    k = hip(t) / hip(from)

    Map.new(clips(from), fn {name, c} ->
      {name,
       %{
         c
         | "pelvis" => Enum.map(c["pelvis"], fn m -> Enum.map(m, &(&1 * k)) end),
           "feet" => Map.new(c["feet"], fn {f, hs} -> {f, Enum.map(hs, &(&1 * k))} end),
           "speed" => c["speed"] * k
       }}
    end)
  end

  defp clips(t) do
    path = Path.join([:code.priv_dir(:world), "animals", "clips", t["mesh"] <> ".json"])
    if File.exists?(path), do: path |> File.read!() |> JSON.decode!() |> Map.fetch!("clips"), else: %{}
  end

  defp hip(t) do
    name = hd(List.wrap(t["bones"]["hind_upper_l"]))

    data =
      Path.join([:code.priv_dir(:world), "animals", "meshes", t["mesh"] <> ".json"]) |> File.read!() |> JSON.decode!()

    data["bones"] |> Enum.find(&(&1["name"] == name)) |> Map.fetch!("head") |> Enum.at(2)
  end

  # The speeds of the clips that move the animal (m/s): an app moves the
  # animal at this speed.
  defp speeds(clips, scale) do
    for {name, c} <- clips, c["speed"] > 0, into: %{}, do: {"#{name}_speed", Float.round(c["speed"] * scale, 2)}
  end

  @doc """
  A clip of a template on the bones of an animal (its skeleton, the
  meters for each unit of the mesh of the template, and the points of
  the skin of each bone at rest). Each bone turns from its rest by the
  turn of its bones of the file, in the axes of the animal; the pelvis
  also moves by its move of the file; the other bones keep their place
  on their parent, so the bones keep their lengths of the shape.

  The legs of the shape are not the legs of the file, so the feet go
  into the ground or above it. A clip with `"ground": "body"` (a death)
  moves all the animal up or down, so that the lowest point of its skin
  is on the ground at each time. In a clip with `"ground": "feet"` the
  paws carry the animal. The height of a foot is the lowest point of its
  skin, over that point at rest, and the steps are:

  1. The clip gives the height of the paw of each foot in the file over
     its height at rest (`feet`). A foot is on the ground at the times
     when its paw is less than 1% of the height of the pelvis above it.
  2. The body goes down by the mean height of the feet on the ground
     over the heights of their paws. At a time with no foot on the
     ground (in a gallop), the move changes linearly in time between the
     times around it (in a loop, around the end; in a clip that does not
     loop, the first and the last moves stay at the ends). When a leg on the ground is too short for its
     place, the body goes down more, until the leg is straight.
  3. Each foot goes to the height of its paw (at the scale of the
     animal, and never below the ground): the upper and the lower bone
     of its leg turn (two-bone inverse kinematics, the knee in the plane
     of its bend), and the foot keeps its turn.
  """
  def retarget(name, %Skeleton{bones: bones} = s, clip, scale, skin) do
    # The points of the skin of each bone in the axes of the bone, and
    # the lowest of them at a time.
    local =
      for {b, ps} <- skin, ps != [], Map.has_key?(s.rest, b), into: %{} do
        {b, Enum.map(ps, &Frame.point(Frame.invert(s.rest[b]), &1))}
      end

    low = fn world, b -> local[b] |> Enum.map(&elem(Frame.point(world[b], &1), 2)) |> Enum.min() end

    moved =
      for k <- 0..(length(clip["times"]) - 1) do
        Enum.reduce(bones, %{}, fn b, w ->
          rest = s.rest[b.name]
          # The file has 4 decimals: a unit quaternion again.
          [qx, qy, qz, qw] = Enum.at(clip["bones"][b.name], k)
          l = :math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
          q = Frame.from_quaternion({qx / l, qy / l, qz / l, qw / l}, {0.0, 0.0, 0.0})

          at =
            if b.parent,
              do: Frame.point(w[b.parent], s.local[b.name].at),
              else: Vec.add(rest.at, Vec.scale(List.to_tuple(Enum.at(clip["pelvis"], k)), scale))

          Map.put(w, b.name, %Frame{x: Frame.dir(q, rest.x), y: Frame.dir(q, rest.y), z: Frame.dir(q, rest.z), at: at})
        end)
      end

    # The times of the clip (of a loop, with no last time: it is the
    # first), the move up of the body and of each foot at each time.
    times = if clip["loop"], do: Enum.drop(moved, -1), else: moved

    {body, by_foot} =
      case clip["ground"] do
        "feet" -> on_feet(times, s, clip, scale, low)
        "body" -> on_body(times, s, Map.keys(local), low)
      end

    frames =
      for {w, k} <- Enum.with_index(moved) do
        k = rem(k, length(times))
        w = Map.new(w, fn {bone, f} -> {bone, %{f | at: Vec.add(f.at, {0.0, 0.0, Enum.at(body, k)})}} end)
        world = Enum.reduce(by_foot, w, fn {f, dz}, w -> reach(w, bones, f, Enum.at(dz, k)) end)

        Map.new(bones, fn b ->
          {b.name, if(b.parent, do: Frame.compose(Frame.invert(world[b.parent]), world[b.name]), else: world[b.name])}
        end)
      end

    %{name: name, channels: Pose.channels(bones, s.local, frames, clip["times"])}
  end

  # The paws carry the animal: the move up of the body at each time, and
  # of each foot (by the turns of its leg).
  defp on_feet(times, %Skeleton{bones: bones} = s, clip, scale, low) do
    by = Map.new(bones, &{&1.name, &1})
    feet = clip["feet"] |> Map.keys() |> Enum.sort()
    h = elem(s.rest["pelvis"].at, 2)
    cycle = clip["loop"]

    # The height of each foot over its height at rest (in the clip, and of
    # its paw in the file, never below the ground), and the times when its
    # paw is on the ground.
    up = Map.new(feet, fn f -> {f, Enum.map(times, &(low.(&1, f) - low.(s.rest, f)))} end)

    lift =
      Map.new(feet, fn f -> {f, clip["feet"][f] |> Enum.take(length(times)) |> Enum.map(&max(&1 * scale, 0.0))} end)

    on = Map.new(feet, fn f -> {f, Enum.map(lift[f], &(&1 <= 0.01 * h))} end)
    error = fn f, k -> Enum.at(up[f], k) - Enum.at(lift[f], k) end

    body =
      times
      |> Enum.with_index()
      |> Enum.map(fn {_, k} ->
        case for(f <- feet, Enum.at(on[f], k), do: error.(f, k)) do
          [] -> nil
          errors -> -Enum.sum(errors) / length(errors)
        end
      end)
      |> between(cycle)

    # A leg on the ground that is too short to go to its place: the body
    # goes down more, until the leg is straight.
    body =
      for {{w, b}, k} <- Enum.with_index(Enum.zip(times, body)) do
        short = for f <- feet, Enum.at(on[f], k), do: short(w, by, f, -(error.(f, k) + b))
        b - Enum.max([0.0 | short])
      end

    {body, Map.new(feet, fn f -> {f, for({b, k} <- Enum.with_index(body), do: -(error.(f, k) + b))} end)}
  end

  # The animal falls: the lowest point of its skin is on the ground at
  # each time, and the legs keep the turns of the clip.
  defp on_body(times, s, parts, low) do
    lowest = fn world -> parts |> Enum.map(&low.(world, &1)) |> Enum.min() end
    ground = lowest.(s.rest)
    {Enum.map(times, &(ground - lowest.(&1))), %{}}
  end

  # The points of the skin of each bone: the points that it moves most.
  defp skin(points, weights) do
    points = List.to_tuple(points)
    Map.new(weights, fn {bone, m} -> {bone, for({i, w} <- m, w >= 0.5, do: elem(points, i))} end)
  end

  # Values with a value at some times (nil at the others): a value at
  # each time, linear in time between the values around it. In a loop
  # the values go around; else the first and the last values stay.
  defp between(values, cycle) do
    n = length(values)
    known = for {v, k} <- Enum.with_index(values), v != nil, do: {k, v}
    {{k0, first}, {k1, last}} = {hd(known), List.last(known)}
    ends = if cycle, do: [{k1 - n, last}, {k0 + n, first}], else: [{-1, first}, {n, last}]
    known = [hd(ends) | known] ++ tl(ends)

    for {v, k} <- Enum.with_index(values) do
      if v do
        v
      else
        {k0, a} = known |> Enum.filter(&(elem(&1, 0) < k)) |> List.last()
        {k1, b} = Enum.find(known, &(elem(&1, 0) > k))
        a + (b - a) * (k - k0) / (k1 - k0)
      end
    end
  end

  # A foot goes up by dz: the lower bone of its leg turns at the knee to
  # make the leg as long as it must be, then the upper bone turns at the
  # hip to the new place; the foot (and the bones under it) keep their
  # turn.
  defp reach(w, bones, foot, dz) do
    {upper, lower, hip, knee, ankle} = leg(w, Map.new(bones, &{&1.name, &1}), foot)
    target = Vec.add(ankle, {0.0, 0.0, dz})
    {l1, l2} = {Vec.len(Vec.sub(knee, hip)), Vec.len(Vec.sub(ankle, knee))}
    d = Vec.len(Vec.sub(target, hip)) |> max(abs(l1 - l2)) |> min(l1 + l2)

    # The bend: the angle between the upper and the lower bone, now and
    # for the length d. A little of the axis x of the lower bone gives a
    # plane to a straight leg.
    plane = Vec.add(Vec.cross(Vec.sub(knee, hip), Vec.sub(ankle, knee)), Vec.scale(w[lower].x, 1.0e-6))
    now = angle(Vec.sub(knee, hip), Vec.sub(ankle, knee))
    cos = ((l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2)) |> max(-1.0) |> min(1.0)
    bent = turn(w, bones, lower, plane, :math.pi() - :math.acos(cos) - now, knee)

    from = Vec.sub(bent[foot].at, hip)
    to = Vec.sub(target, hip)
    swung = turn(bent, bones, upper, Vec.cross(from, to), angle(from, to), hip)

    move = Vec.sub(swung[foot].at, ankle)
    Enum.reduce(under(bones, foot), swung, &Map.put(&2, &1, %{w[&1] | at: Vec.add(w[&1].at, move)}))
  end

  # How much lower the body must go so that the leg of a foot is long
  # enough to move the foot up by dz (the hip and the place of the foot
  # move with the body, and the place of the foot stays).
  defp short(w, by, foot, dz) do
    {_, _, hip, knee, ankle} = leg(w, by, foot)
    l = 0.999 * (Vec.len(Vec.sub(knee, hip)) + Vec.len(Vec.sub(ankle, knee)))
    {x, y, z} = Vec.sub(Vec.add(ankle, {0.0, 0.0, dz}), hip)
    -:math.sqrt(max(l * l - x * x - y * y, 0.0)) - z
  end

  # The upper and the lower bone of the leg of a foot, and the places of
  # the hip, the knee and the ankle.
  defp leg(w, by, foot) do
    lower = by[foot].parent
    upper = by[lower].parent
    {upper, lower, w[upper].at, w[lower].at, w[foot].at}
  end

  # The angle between two directions (radians).
  defp angle(u, v), do: :math.atan2(Vec.len(Vec.cross(u, v)), Vec.dot(u, v))

  # A bone and the bones under it turn by an angle (radians) around an
  # axis through a point.
  defp turn(w, bones, root, axis, angle, at) do
    r = Frame.turn(axis, angle * 180 / :math.pi(), at)
    Enum.reduce(under(bones, root), w, &Map.put(&2, &1, Frame.compose(r, &2[&1])))
  end

  # A bone and all the bones under it (the bones are parents first).
  defp under(bones, root) do
    Enum.reduce(bones, [root], fn b, acc -> if b.parent in acc, do: [b.name | acc], else: acc end)
  end

  # New horns: on the highest points of the head that the animal keeps.
  defp horns(length, _spread, _head, _points, _weights, _kept) when length == 0, do: []

  defp horns(length, spread, head, points, weights, kept) do
    top = for {i, w} <- weights["head"], w > 0.5, i in kept, do: Enum.at(points, i)
    {ps, tris} = Shape.horns(head, length, spread, top)
    [{:horn, "head", ps, tris}]
  end

  # The role of a material of the mesh (by its index).
  defp unzip3(list), do: {Enum.map(list, &elem(&1, 0)), Enum.map(list, &elem(&1, 1)), Enum.map(list, &elem(&1, 2))}

  defp material_role(s, data, i) do
    name = data["materials"] |> Enum.at(i) |> Map.fetch!("name")
    @roles[Map.get(s["materials"], name, "fur")]
  end

  # The bones of World, parents first, in the units of the mesh: the head
  # from the mesh; the parent from `parents`, else from the bones above
  # the bone of the mesh; the tail at the head of the next bone of the body plan, else at
  # the end of the bone of the mesh, else at the head of a bone under it
  # with no bone of World of its own, else at the point of its skin
  # farthest on, from its parent.
  defp bones(plan, map, parents, file_bones, owner, points, weights) do
    for name <- plan.bones(), [file | _] <- [Map.get(map, name, [nil])], f = file_bones[file], f != nil, reduce: [] do
      acc ->
        next = plan.next(name)
        # A bone under it that gives it its weights (not the root of an
        # ear under the head).
        kid = Enum.find(Map.values(file_bones), &(&1["parent"] == file and owner.(&1["name"]) == name))
        # The parent: the bone of World of the nearest bone above it that
        # is not its own (a body of the file under its hips).
        parent =
          parents[name] ||
            (f["parent"] &&
               Stream.iterate(f["parent"], &file_bones[&1]["parent"])
               |> Enum.take_while(& &1)
               |> Enum.map(owner)
               |> Enum.find(&(&1 != name)))

        head = List.to_tuple(f["head"])

        tail =
          cond do
            next && map[next] && file_bones[hd(map[next])] -> List.to_tuple(file_bones[hd(map[next])]["head"])
            f["tail"] -> List.to_tuple(f["tail"])
            kid -> List.to_tuple(kid["head"])
            true -> farthest(head, Enum.find(acc, &(&1.name == parent)).head, Map.get(weights, name, %{}), points)
          end

        acc ++ [%{name: name, parent: parent, head: head, tail: tail, x: nil}]
    end
  end

  # The point of the skin of a bone (weight 0.5 or more) farthest from
  # its head in the direction from the head of its parent.
  defp farthest(head, from, weights, points) do
    dir = Vec.norm(Vec.sub(head, from))
    points = List.to_tuple(points)

    weights
    |> Enum.filter(fn {_, w} -> w >= 0.5 end)
    |> Enum.map(fn {i, _} -> elem(points, i) end)
    |> Enum.max_by(&Vec.dot(Vec.sub(&1, head), dir))
  end

  @doc """
  The move of a foot from its place at rest at a part `u` of a step (0
  to 1): on the ground for the part `stance` (it goes back, flat), and to
  the front in the air for the rest, `lift` high at the middle.
  """
  def foot(u, stride, _lift, stance) when u < stance, do: %{by: {0.0, stride * (0.5 - u / stance), 0.0}, flat: true}

  def foot(u, stride, lift, stance) do
    v = (u - stance) / (1 - stance)
    %{by: {0.0, stride * (v - 0.5), lift * :math.sin(:math.pi() * v)}}
  end
end
