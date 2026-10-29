defmodule World.Animals do
  @moduledoc """
  The animals of the world: figures from bones (`World.Rig`). An animal
  is a species of a body plan.

  - The body plan (code) gives the bones of World, the joints, the
    limbs, the ports and the gaits: `World.Animals.Quadruped` (four legs
    and a tail) and `World.Animals.Biped` (two legs, two arms and a
    tail).
  - The species (data, `priv/animals/species/NAME.json`) is numbers on
    a template (`priv/animals/templates/NAME.json`: one mesh for a body
    plan, and `World.Animals.Shape`), or a species on its own mesh
    (`priv/animals/meshes/`, from `scripts/fbx_figure.exs`).

  The keys of a species (`docs/format.md`, "An animal"): `name`,
  `about`, `plan`, `sources`, `height` (in meters, at the withers for a
  quadruped, at the top of the head for a biped), `colors` (a role to
  its color; `fur` is the base color of the coat), `gait`; on a
  template, `template`, `shape` (numbers) and `markings` (a region of
  the coat to its color); on a mesh, `mesh`, `bones` (a bone of World to
  the bone of the mesh), `materials` (a material of the mesh to a role)
  and `smooth`. `spheres` (the eyes and a nose) come from the template
  or the species.
  """
  alias World.{Rig, Vec}
  alias World.Animals.Shape

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

  @plans %{"quadruped" => World.Animals.Quadruped, "biped" => World.Animals.Biped}
  @roles %{
    "fur" => :fur,
    "marking" => :marking,
    "skin" => :skin,
    "eye" => :eye,
    "nose" => :nose,
    "dark" => :dark,
    "white" => :white,
    "horn" => :horn
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

    # A species of a template takes the mesh, the bones and the eyes of
    # the template.
    t = if s["template"], do: Map.merge(@templates[s["template"]], s), else: s

    data =
      Path.join([:code.priv_dir(:world), "animals", "meshes", t["mesh"] <> ".json"]) |> File.read!() |> JSON.decode!()

    to_world = Map.new(t["bones"], fn {world, file} -> {file, world} end)
    file_bones = Map.new(data["bones"], &{&1["name"], &1})
    # The bone of World of a bone of the mesh: its own, or of the nearest
    # bone above it.
    owner = fn file ->
      Stream.iterate(file, &file_bones[&1]["parent"]) |> Enum.take_while(& &1) |> Enum.find_value(&to_world[&1])
    end

    weights =
      for {file, list} <- data["weights"], reduce: %{} do
        acc ->
          Map.update(acc, owner.(file), Map.new(list, &List.to_tuple/1), fn m ->
            Enum.reduce(list, m, fn [i, w], m -> Map.update(m, i, w, &(&1 + w)) end)
          end)
      end

    points = Enum.map(data["points"], &List.to_tuple/1)
    bones = bones(plan, t["bones"], file_bones, owner)
    coat = Keyword.get(opts, :coat) || s["colors"]["fur"]

    # A template: the shape from the numbers, and the colors of the coat
    # by region.
    # The eyes and the nose start on a ray from a point of a bone. On a
    # template, the point moves with the bone, as a point of the skin.
    spheres = Map.get(t, "spheres", [])
    by0 = Map.new(bones, &{&1.name, &1})
    unit0 = Vec.len(Vec.sub(by0["head"].tail, by0["head"].head))
    origins = if s["template"], do: for(sp <- spheres, do: origin(sp, by0, unit0)), else: []

    {bones, points, colors, shape} =
      if s["template"] do
        shape = Map.merge(s["shape"], Keyword.get(opts, :shape, %{}))
        regions = Shape.regions(bones, points, weights, t)
        n = length(points)
        on_bones = for {sp, j} <- Enum.with_index(spheres), into: %{}, do: {n + j, sp["bone"]}

        all =
          Enum.reduce(on_bones, weights, fn {i, bone}, acc ->
            Map.update(acc, bone, %{i => 1.0}, &Map.put(&1, i, 1.0))
          end)

        {bones, moved} = Shape.apply(bones, points ++ origins, all, shape, t)
        colors = Shape.colors(regions, coat, Map.merge(s["markings"], Keyword.get(opts, :markings, %{})))
        {bones, moved, colors, shape}
      else
        {bones, points, nil, %{}}
      end

    {points, origins} = Enum.split(points, length(points) - length(origins))

    scale = s["height"] * k / plan.height(points, weights)
    at = &Vec.scale(&1, scale)

    bones =
      for b <- bones do
        {head, tail} = {at.(b.head), at.(b.tail)}
        %{b | head: head, tail: tail, x: plan.hinge(b.name, Vec.norm(Vec.sub(tail, head)))}
      end

    points = Enum.map(points, at)
    by = Map.new(bones, &{&1.name, &1})
    head_length = Vec.len(Vec.sub(by["head"].tail, by["head"].head))

    # The unit of the sizes of the spheres: meters times the size, or the
    # length of the head of the template times the scale of the head.
    unit = if s["template"], do: unit0 * scale * Map.get(shape, "head_size", 1.0), else: k
    origins = if s["template"], do: Enum.map(origins, at), else: for(sp <- spheres, do: origin(sp, by, k))
    template_colors = if s["template"], do: @templates[s["template"]]["colors"], else: %{}
    roles = Enum.map(data["face_materials"], &material_role(t, data, &1))
    parts = horns(Map.get(shape, "horns", 0) * head_length, by["head"], points, weights)

    # The colors of the roles that the animal uses.
    used = MapSet.new(roles ++ Enum.map(spheres, &@roles[&1["role"]]) ++ Enum.map(parts, &elem(&1, 0)))

    colors_of =
      Map.merge(template_colors, s["colors"])
      |> Map.put("fur", if(colors, do: [255, 255, 255], else: coat))
      |> Map.filter(fn {role, _} -> @roles[role] in used end)

    Rig.figure(plan.figure_name(name),
      bones: bones,
      mesh: %{
        points: points,
        faces: data["faces"],
        weights: Map.new(weights, fn {bone, m} -> {bone, Enum.sort(m)} end),
        smooth: Map.get(t, "smooth", 0),
        roles: roles,
        colors: colors
      },
      limbs: plan.limbs(by),
      joints: plan.joints(by),
      ports: plan.ports(by),
      spheres:
        for(
          {sp, o} <- Enum.zip(spheres, origins),
          do: {{:on, o, List.to_tuple(sp["dir"])}, sp["radius"] * unit, sp["bone"], @roles[sp["role"]]}
        ),
      parts: parts,
      materials:
        Map.new(colors_of, fn {role, color} ->
          {@roles[role],
           %{
             "color" => color,
             "roughness" => if(role in ~w(eye dark nose horn), do: 0.3, else: 0.9),
             "metalness" => 0.0
           }}
        end),
      animations: for(a <- names, do: &plan.animation(a, &1, k * s["height"], Map.get(s, "gait", %{}))),
      kind: :animal,
      params: %{"coat" => coat, "size" => k},
      sources: [data["source"] <> " " <> data["license"], s["about"] | s["sources"]]
    )
  end

  # The horns: on the highest points of the head.
  defp horns(length, _head, _points, _weights) when length == 0, do: []

  defp horns(length, head, points, weights) do
    top = for {i, w} <- weights["head"], w > 0.5, do: Enum.at(points, i)
    {ps, tris} = Shape.horns(head, length, top)
    [{:horn, "head", ps, tris}]
  end

  # The role of a material of the mesh (by its index).
  defp material_role(s, data, i) do
    name = data["materials"] |> Enum.at(i) |> Map.fetch!("name")
    @roles[Map.get(s["materials"], name, "fur")]
  end

  # The bones of World, parents first, in the units of the mesh: the head
  # from the mesh; the tail at the head of the next bone of the body plan,
  # else at the end of the bone of the mesh, else at the head of a bone
  # under it, else as far again as from its parent.
  defp bones(plan, map, file_bones, owner) do
    for name <- plan.bones(), file = map[name], file != nil do
      f = file_bones[file]
      next = plan.next(name)
      kid = Enum.find(Map.values(file_bones), &(&1["parent"] == file))
      parent = f["parent"] && owner.(f["parent"])

      tail =
        cond do
          next && map[next] -> file_bones[map[next]]["head"]
          f["tail"] -> f["tail"]
          kid -> kid["head"]
          true -> Enum.zip_with(f["head"], file_bones[map[parent]]["head"], &(&1 + 0.5 * (&1 - &2)))
        end

      %{name: name, parent: parent, head: List.to_tuple(f["head"]), tail: List.to_tuple(tail), x: nil}
    end
  end

  # The start of the ray of an eye or a nose: `up` times `unit` above a
  # part of the bone (a species of a mesh: meters times the size; a
  # template: lengths of the head of the template, before the shape).
  defp origin(sp, by, unit) do
    b = by[sp["bone"]]
    Vec.add(Vec.lerp(b.head, b.tail, sp["at"]), {0.0, 0.0, Map.get(sp, "up", 0.0) * unit})
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
