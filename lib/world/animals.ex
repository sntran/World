defmodule World.Animals do
  @moduledoc """
  The animals of the world: figures from bones (`World.Rig`) on a base
  mesh. An animal is a species of a body plan.

  - The body plan (code) gives the bones of World, the joints, the
    limbs, the ports and the gaits: `World.Animals.Quadruped` (four legs
    and a tail: a dog, a cat) and `World.Animals.Biped` (two legs, two
    arms and a tail: a monkey).
  - The species (data, `priv/animals/species/NAME.json`) gives its base
    mesh (`priv/animals/meshes/`, from `scripts/fbx_figure.exs`), the
    bone of the mesh for each bone of World, its height, its colors, its
    eyes, the numbers of its gaits and its sources.

  So a new species of a known body plan is two files of data and no
  code. The keys of a species:

  - `name`, `about`, `plan` (`quadruped` or `biped`), `mesh` (the name
    of the file in `meshes/`), `sources`;
  - `bones`: a bone of World to the bone of the mesh. A bone of the mesh
    with no bone of World gives its weights to the nearest bone above it
    with a bone of World (the fingers go to the hand). The bones of the
    tail are `tail_01`, `tail_02` ... (as many as the mesh has);
  - `height`: in meters, at the withers (the top of the back above the
    front legs: the highest point of `spine_01`) for a quadruped, at the
    top of the head for a biped. The option `size` scales it;
  - `materials`: a material of the mesh to a role (`fur`, `marking`,
    `skin`, `eye`, `dark`, `white`), and `colors`: a role to its color.
    The option `coat` is the color of `fur`;
  - `smooth`: the smooth steps of the mesh at near (`World.Subdivision`);
  - `spheres`: the eyes or a nose that the mesh does not have: on a ray
    from a point of a bone (`at`: a part of the bone from its head,
    `up`: meters above it) in the direction `dir`, with a `radius` and
    a `role`;
  - `gait`: the numbers of the gaits of the body plan (see its module).
  """
  alias World.{Rig, Vec}

  @root Path.join([__DIR__, "..", "..", "priv", "animals"])
  @species_files Path.wildcard(Path.join([@root, "species", "*.json"]))
  for f <- @species_files, do: @external_resource(f)
  @species Map.new(@species_files, fn f -> {Path.basename(f, ".json"), f |> File.read!() |> JSON.decode!()} end)
  @hash :erlang.md5(Enum.join(@species_files))

  # A new file of a species compiles the module again.
  @doc false
  def __mix_recompile__?, do: :erlang.md5(Enum.join(Path.wildcard(Path.join([@root, "species", "*.json"])))) != @hash

  @plans %{"quadruped" => World.Animals.Quadruped, "biped" => World.Animals.Biped}
  @roles %{"fur" => :fur, "marking" => :marking, "skin" => :skin, "eye" => :eye, "dark" => :dark, "white" => :white}

  @doc "The names of the species."
  def species, do: @species |> Map.keys() |> Enum.sort()

  @doc "The data of a species (its JSON)."
  def spec(name) do
    Map.get(@species, name) || raise ArgumentError, "unknown species #{inspect(name)}: #{Enum.join(species(), ", ")}"
  end

  @doc "The names of the animations of a species (of its body plan)."
  def animations(name), do: @plans[spec(name)["plan"]].animations()

  @doc """
  An animal of a species. The options: `coat` (`[r, g, b]`, the color of
  `fur`; the color of the species by default), `size` (a scale of all
  the animal: 1 is the height of the species), and `animations` (names
  of the animations of its body plan).
  """
  def animal(name, opts) do
    s = spec(name)
    plan = @plans[s["plan"]]
    k = Keyword.get(opts, :size, 1.0) / 1
    names = Keyword.get(opts, :animations, [])

    for a <- names,
        a not in plan.animations(),
        do: raise(ArgumentError, "unknown animation of a #{name} #{inspect(a)}: #{Enum.join(plan.animations(), ", ")}")

    data =
      Path.join([:code.priv_dir(:world), "animals", "meshes", s["mesh"] <> ".json"]) |> File.read!() |> JSON.decode!()

    to_world = Map.new(s["bones"], fn {world, file} -> {file, world} end)
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

    scale = s["height"] * k / plan.height(data["points"], weights)
    at = fn [x, y, z] -> {x * scale, y * scale, z * scale} end
    bones = bones(plan, s["bones"], file_bones, owner, at)
    by = Map.new(bones, &{&1.name, &1})
    coat = Keyword.get(opts, :coat) || s["colors"]["fur"]
    colors = Map.put(s["colors"], "fur", coat)
    roles = Enum.map(data["face_materials"], &material_role(s, data, &1))

    Rig.figure(plan.figure_name(name),
      bones: bones,
      mesh: %{
        points: Enum.map(data["points"], at),
        faces: data["faces"],
        weights: Map.new(weights, fn {bone, m} -> {bone, Enum.sort(m)} end),
        smooth: Map.get(s, "smooth", 0),
        roles: roles
      },
      limbs: plan.limbs(by),
      joints: plan.joints(by),
      ports: plan.ports(by),
      spheres: for(sp <- Map.get(s, "spheres", []), do: sphere(sp, by, k)),
      materials:
        Map.new(colors, fn {role, color} ->
          {@roles[role],
           %{"color" => color, "roughness" => if(role in ~w(eye dark), do: 0.25, else: 0.9), "metalness" => 0.0}}
        end),
      animations: for(a <- names, do: &plan.animation(a, &1, k * s["height"], Map.get(s, "gait", %{}))),
      kind: :animal,
      params: %{"coat" => coat, "size" => k},
      sources: [data["source"] <> " " <> data["license"], s["about"] | s["sources"]]
    )
  end

  # The role of a material of the mesh (by its index).
  defp material_role(s, data, i) do
    name = data["materials"] |> Enum.at(i) |> Map.fetch!("name")
    @roles[Map.get(s["materials"], name, "fur")]
  end

  # The bones of World, parents first: the head from the mesh; the tail at
  # the head of the next bone of the body plan, else at the end of the
  # bone of the mesh, else at the head of a bone under it, else as far
  # again as from its parent.
  defp bones(plan, map, file_bones, owner, at) do
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

      head = at.(f["head"])
      tail = at.(tail)
      %{name: name, parent: parent, head: head, tail: tail, x: plan.hinge(name, Vec.norm(Vec.sub(tail, head)))}
    end
  end

  defp sphere(sp, by, k) do
    b = by[sp["bone"]]
    from = Vec.add(Vec.lerp(b.head, b.tail, sp["at"]), {0.0, 0.0, Map.get(sp, "up", 0.0) * k})
    {{:on, from, List.to_tuple(sp["dir"])}, sp["radius"] * k, sp["bone"], @roles[sp["role"]]}
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
