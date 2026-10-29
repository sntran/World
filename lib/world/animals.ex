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
  color), `without` (roles whose faces go) and `gait`. The keys of a
  template: `mesh`, `bones` (a bone of World to the bones of the mesh),
  `materials` (a material of the mesh to a role), `smooth`, `parents`,
  `muzzle` and `brow`.
  """
  alias World.{Frame, Rig, Vec}
  alias World.Animals.Shape
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

  @doc "The names of the animations of a species (of its body plan)."
  def animations(name), do: @plans[spec(name)["plan"]].animations()

  @doc """
  An animal of a species. The options: `coat` (`[r, g, b]`: the color
  of `fur`, or the base color of the coat of a template; the color of
  the species by default), `markings` (a template: a region of the coat
  to its color, over the colors of the species), `shape` (a template:
  numbers of `World.Animals.Shape` over the numbers of the species),
  `size` (a scale of all the animal: 1 is the height of the species),
  and `animations` (names of the animations of its body plan).
  """
  def animal(name, opts) do
    s = spec(name)
    plan = @plans[s["plan"]]
    k = Keyword.get(opts, :size, 1.0) / 1
    names = Keyword.get(opts, :animations, [])

    for a <- names,
        a not in plan.animations(),
        do: raise(ArgumentError, "unknown animation of a #{name} #{inspect(a)}: #{Enum.join(plan.animations(), ", ")}")

    # A species takes the mesh, the bones and the materials of its
    # template.
    t = Map.merge(@templates[s["template"]], s)

    {data, bones, points, weights} = rest(t, plan)

    # The faces that the species keeps (a pig has no horns of a cow), and
    # the role of each.
    without = Enum.map(Map.get(s, "without", []), &@roles[&1])

    {faces, roles} =
      data["faces"]
      |> Enum.zip(Enum.map(data["face_materials"], &material_role(t, data, &1)))
      |> Enum.reject(fn {_, role} -> role in without end)
      |> Enum.unzip()

    # The colors: of the materials of the mesh, of the template, of the
    # species, and the coat of the order.
    mesh_colors =
      for m <- data["materials"], m["color"], reduce: %{} do
        acc -> Map.put_new(acc, Map.get(t["materials"], m["name"], "fur"), m["color"])
      end

    coat = Keyword.get(opts, :coat) || get_in(s, ["colors", "fur"]) || mesh_colors["fur"]
    markings = Map.merge(Map.get(s, "markings", %{}), Keyword.get(opts, :markings, %{}))

    shape = Map.merge(s["shape"], Keyword.get(opts, :shape, %{}))
    regions = Shape.regions(bones, points, weights)
    {bones, points} = Shape.apply(bones, points, weights, shape, t)
    colors = if markings != %{}, do: Shape.colors(regions, coat, markings)

    scale = s["height"] * k / plan.height(points, weights)
    at = &Vec.scale(&1, scale)
    clips = clips(t["mesh"])

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
        colored: [:fur, :marking]
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
            do: &retarget(a, &1, clip, scale, plan.feet()),
            else: &plan.animation(a, &1, k * s["height"], Map.get(s, "gait", %{}))
        end,
      pose: &plan.pose/1,
      kind: :animal,
      params:
        %{"coat" => coat, "size" => k}
        |> Map.merge(plan.speeds(k * s["height"], Map.get(s, "gait", %{})))
        |> Map.merge(speeds(clips, scale)),
      sources: [data["source"] <> " " <> data["license"], s["about"] | s["sources"]]
    )
  end

  @doc """
  A template at rest, before the numbers of a shape: `%{template, bones,
  points, weights}` (in the units of its mesh; the bones of World, the
  weights of each bone of World).
  """
  def template(name) do
    t = Map.fetch!(@templates, name)
    {_, bones, points, weights} = rest(t, @plans[t["plan"]])
    %{template: t, bones: bones, points: points, weights: weights}
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

  # The clips of a template (`scripts/gltf_clips.exs`), or none.
  defp clips(mesh) do
    path = Path.join([:code.priv_dir(:world), "animals", "clips", mesh <> ".json"])
    if File.exists?(path), do: path |> File.read!() |> JSON.decode!() |> Map.fetch!("clips"), else: %{}
  end

  # The speeds of the clips that move the animal (m/s): an app moves the
  # animal at this speed.
  defp speeds(clips, scale) do
    for {name, c} <- clips, c["speed"] > 0, into: %{}, do: {"#{name}_speed", Float.round(c["speed"] * scale, 2)}
  end

  @doc """
  A clip of a template on the bones of an animal (its skeleton, the
  meters for each unit of the mesh of the template, and the bones of its
  feet). Each bone turns from its rest by the turn of its bones of the
  file, in the axes of the animal; the pelvis also moves by its move of
  the file; the other bones keep their place on their parent, so the
  bones keep their lengths of the shape. The legs of the shape are not
  the legs of the file: when the lowest end of the feet goes below the
  lowest end at rest, all the animal goes up, so no foot goes into the
  ground.
  """
  def retarget(name, %Skeleton{bones: bones} = s, clip, scale, feet) do
    low = fn world -> feet |> Enum.map(&elem(Skeleton.tip(s, world, &1), 2)) |> Enum.min() end
    ground = low.(s.rest)

    frames =
      for k <- 0..(length(clip["times"]) - 1) do
        moved =
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

        up = max(ground - low.(moved), 0.0)
        world = Map.new(moved, fn {bone, f} -> {bone, %{f | at: Vec.add(f.at, {0.0, 0.0, up})}} end)

        Map.new(bones, fn b ->
          {b.name, if(b.parent, do: Frame.compose(Frame.invert(world[b.parent]), world[b.name]), else: world[b.name])}
        end)
      end

    %{name: name, channels: Pose.channels(bones, s.local, frames, clip["times"])}
  end

  # New horns: on the highest points of the head that the animal keeps.
  defp horns(length, _spread, _head, _points, _weights, _kept) when length == 0, do: []

  defp horns(length, spread, head, points, weights, kept) do
    top = for {i, w} <- weights["head"], w > 0.5, i in kept, do: Enum.at(points, i)
    {ps, tris} = Shape.horns(head, length, spread, top)
    [{:horn, "head", ps, tris}]
  end

  # The role of a material of the mesh (by its index).
  defp material_role(s, data, i) do
    name = data["materials"] |> Enum.at(i) |> Map.fetch!("name")
    @roles[Map.get(s["materials"], name, "fur")]
  end

  # The bones of World, parents first, in the units of the mesh: the head
  # from the mesh; the parent from `parents`, else of the bone of the
  # mesh; the tail at the head of the next bone of the body plan, else at
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
        parent = parents[name] || (f["parent"] && owner.(f["parent"]))
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
