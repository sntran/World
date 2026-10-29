defmodule World.Animals do
  @moduledoc """
  The animals of the world: figures from bones (`World.Rig`). An animal
  is a species of a body plan: the body plan gives the bones, the
  joints, the limbs, the ports and the gaits; the species gives its
  sizes, its colors and its sources. The body plans now: a quadruped
  with a tail (a dog). A cat or a water buffalo is the same plan with
  other sizes; a bird is another plan.

  - `"street_dog"` (`dog/1`): a street dog of Việt Nam (chó cỏ): a
    medium dog of mixed breed with a short coat, about 50 cm at the
    shoulder, a tail that it holds up. The sizes are a guess from the photos of the street dogs
    of Việt Nam and from the medium breeds (about 15 kg): no
    measurements.
  """
  alias World.{Joint, Limb, Part, Rig, Vec}

  @coat [200, 150, 90]
  @species ~w(street_dog)

  @doc "The names of the species."
  def species, do: @species

  @doc "An animal of a species, with the options of its function (`dog/1`)."
  def animal("street_dog", opts), do: dog(opts)
  def animal(name, _opts), do: raise(ArgumentError, "unknown species #{inspect(name)}: #{Enum.join(@species, ", ")}")

  # The bones of World from the bones of the base mesh: the name, the bone
  # of the mesh, and the bone whose head is the tail (nil: the end node
  # of the mesh).
  @bones [
           {"pelvis", "Bone", "Bone.001"},
           {"spine_01", "Bone.001", "Bone.002"},
           {"neck_01", "Bone.002", "Bone.003"},
           {"head", "Bone.003", nil},
           {"tail_01", "Bone.004", "Bone.005"},
           {"tail_02", "Bone.005", "Bone.006"},
           {"tail_03", "Bone.006", "Bone.007"},
           {"tail_04", "Bone.007", nil}
         ] ++
           for(
             {side, hind, front} <- [
               {"l", ~w(Bone.008 Bone.009 Bone.010), ~w(Bone.017 Bone.018 Bone.019)},
               {"r", ~w(Bone.011 Bone.012 Bone.013), ~w(Bone.014 Bone.015 Bone.016)}
             ],
             {part, chain} <- [{"hind", hind}, {"front", front}],
             {{name, from}, to} <- Enum.zip(Enum.zip(~w(upper lower foot), chain), tl(chain) ++ [nil]),
             do: {"#{part}_#{name}_#{side}", from, to}
           )

  @names Map.new(@bones, fn {name, from, _} -> {from, name} end)

  @doc """
  A street dog. The options: `coat` (`[r, g, b]`, a tan coat by default),
  `size` (a scale of all the dog: 1 is about 50 cm at the shoulder), and
  `animations` (a list of `"walk"` and `"wag"`).

  The body is the base mesh of a dog of Quaternius (CC0,
  `priv/animals/dog.json`, from `scripts/fbx_figure.exs`) with its
  weights, on the bones of World, smooth at near and at mid
  (`World.Subdivision`). The eyes and the nose are on the mesh.

  The joints (the values add to the rest): the hinges `elbow_l`,
  `wrist_l`, `knee_l`, `hock_l` (and `_r`; more bends the elbow and the
  knee, and swings the paw to the front at the wrist and at the hock),
  the balls `shoulder_l`, `hip_l` (and `_r`), `neck`, `spine` and `tail` (flex lifts the tail, spread wags it to the right
  side). The limbs: `front_l`, `front_r` (the end is the wrist), `hind_l`,
  `hind_r` (the end is the hock), `tail` and `head`.
  """
  def dog(opts) do
    k = Keyword.get(opts, :size, 1.0) / 1
    coat = Keyword.get(opts, :coat, @coat)
    names = Keyword.get(opts, :animations, [])
    data = Path.join([:code.priv_dir(:world), "animals", "dog.json"]) |> File.read!() |> JSON.decode!()

    # The scale: the top of the back (the points of the spine) at 50 cm.
    spine = for [i, w] <- data["weights"]["Bone.001"], w >= 0.5, into: MapSet.new(), do: i

    withers =
      data["points"]
      |> Enum.with_index()
      |> Enum.filter(&(elem(&1, 1) in spine))
      |> Enum.map(&Enum.at(elem(&1, 0), 2))
      |> Enum.max()

    scale = 0.5 * k / withers
    at = fn [x, y, z] -> {x * scale, y * scale, z * scale} end
    source = Map.new(data["bones"], &{&1["name"], &1})
    bones = for {name, from, to} <- @bones, do: bone(name, source[from], to && source[to], at)
    by = Map.new(bones, &{&1.name, &1})

    Rig.figure("dog",
      bones: bones,
      mesh: %{
        points: Enum.map(data["points"], at),
        faces: data["faces"],
        weights: for({from, list} <- data["weights"], into: %{}, do: {@names[from], Enum.map(list, &List.to_tuple/1)}),
        smooth: 2
      },
      limbs: limbs(),
      joints: joints(),
      ports: ports(by),
      spheres: spheres(by, k),
      materials: %{
        fur: %{"color" => coat, "roughness" => 0.95, "metalness" => 0.0},
        eye: %{"color" => [24, 18, 16], "roughness" => 0.25, "metalness" => 0.0}
      },
      animations: for(name <- names, do: &animation(name, &1, k)),
      kind: :animal,
      params: %{"coat" => coat, "size" => k},
      sources: [
        data["source"] <> " " <> data["license"],
        "A street dog of Việt Nam (chó cỏ): about 50 cm at the shoulder. The size is a guess from photos and from the medium breeds of dogs; the gait is the walk of a dog (the feet in the order hind left, front left, hind right, front right)."
      ]
    )
  end

  defp bone(name, from, to, at) do
    parent = from["parent"] && @names[from["parent"]]
    tail = if to, do: to["head"], else: from["tail"]
    # The hinge of a lower leg: a bend takes its end to the back, and the
    # knee or the elbow to the front (the side of the pole of the limb).
    x = if String.contains?(name, "_lower_"), do: {-1.0, 0.0, 0.0}, else: {1.0, 0.0, 0.0}
    %{name: name, parent: parent, head: at.(from["head"]), tail: at.(tail), x: x}
  end

  # The eyes and the nose: on the mesh, on rays from the inside of the
  # head.
  defp spheres(by, k) do
    head = by["head"]
    along = fn t, up -> Vec.add(Vec.lerp(head.head, head.tail, t), {0.0, 0.0, up * k}) end

    [
      {{:on, along.(0.35, 0.02), {-0.55, 1.0, 0.35}}, 0.016 * k, "head", :eye},
      {{:on, along.(0.35, 0.02), {0.55, 1.0, 0.35}}, 0.016 * k, "head", :eye},
      {{:on, along.(0.8, -0.01), {0.0, 1.0, 0.1}}, 0.02 * k, "head", :eye}
    ]
  end

  defp limbs do
    for(
      side <- ~w(l r),
      do: [
        Limb.new("front_#{side}", ["front_upper_#{side}", "front_lower_#{side}"], role: :leg, pole: {0.0, 1.0, 0.0}),
        Limb.new("hind_#{side}", ["hind_upper_#{side}", "hind_lower_#{side}"], role: :leg, pole: {0.0, 1.0, 0.0})
      ]
    )
    |> List.flatten()
    |> Kernel.++([
      Limb.new("tail", ~w(tail_01 tail_02 tail_03 tail_04), role: :tail, solver: :chain),
      Limb.new("head", ~w(neck_01 head), role: :neck, solver: :chain)
    ])
  end

  defp joints do
    limbs =
      for side <- ~w(l r) do
        [
          Joint.new("elbow_#{side}", :hinge, role: :elbow, bone: "front_lower_#{side}", limits: {-60, 90}),
          Joint.new("wrist_#{side}", :hinge, role: :wrist, bone: "front_foot_#{side}", limits: {-40, 90}),
          Joint.new("knee_#{side}", :hinge, role: :knee, bone: "hind_lower_#{side}", limits: {-90, 60}),
          Joint.new("hock_#{side}", :hinge, role: :ankle, bone: "hind_foot_#{side}", limits: {-60, 90}),
          Joint.new("shoulder_#{side}", :ball,
            role: :shoulder,
            bone: "front_upper_#{side}",
            limits: %{flex: {-60, 90}, spread: {-20, 30}, twist: {-20, 20}}
          ),
          Joint.new("hip_#{side}", :ball,
            role: :hip,
            bone: "hind_upper_#{side}",
            limits: %{flex: {-60, 90}, spread: {-20, 40}, twist: {-20, 20}}
          )
        ]
      end

    List.flatten(limbs) ++
      [
        Joint.new("neck", :ball,
          role: :neck,
          bone: "neck_01",
          limits: %{flex: {-40, 60}, spread: {-45, 45}, twist: {-60, 60}}
        ),
        Joint.new("spine", :ball,
          role: :spine,
          bone: "spine_01",
          limits: %{flex: {-20, 30}, spread: {-20, 20}, twist: {-15, 15}}
        ),
        Joint.new("tail", :ball,
          role: :tail,
          bone: "tail_01",
          limits: %{flex: {-60, 40}, spread: {-60, 60}, twist: {-30, 30}}
        )
      ]
  end

  # The ports: the ground, a collar on the neck, the back (a bag), and
  # the mouth (a stick), from the bones.
  defp ports(by) do
    {neck, spine, head} = {by["neck_01"], by["spine_01"], by["head"]}
    along = Vec.norm(Vec.sub(neck.tail, neck.head))

    [
      {"ground", nil, Part.port("ground", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})},
      {"collar", "neck_01",
       Part.port("collar", Vec.lerp(neck.head, neck.tail, 0.5), along, {0.0, -elem(along, 2), elem(along, 1)})},
      {"back", "spine_01", Part.port("back", Vec.lerp(spine.head, spine.tail, 0.5), {0, 0, 1}, {0, 1, 0})},
      {"mouth", "head", Part.port("mouth", head.tail, {1, 0, 0}, {0, 0, 1})}
    ]
  end

  # The walk: each foot goes back on the ground for 0.6 of the step, and
  # to the front in the air for the rest; the feet in the order hind left,
  # front left, hind right, front right. The tail wags a little, the head
  # nods. A step of 0.7 s with a stride of 16 cm (the legs are about 32
  # cm long): about 0.23 m/s (an app moves the dog at that speed). The
  # wag: the tail wags twice in 0.8 s.
  defp animation("walk", skeleton, k) do
    period = 0.7
    phases = %{"hind_l" => 0.0, "front_l" => 0.25, "hind_r" => 0.5, "front_r" => 0.75}

    Rig.clip("walk", skeleton, period, 14, fn t ->
      feet =
        for {limb, phase} <- phases, into: %{} do
          {{:limb, limb}, foot(:math.fmod(t / period + phase, 1.0), 0.16 * k, 0.05 * k)}
        end

      # A paw in the air folds back at the wrist (more at the front).
      folds =
        for {limb, phase} <- phases, u = :math.fmod(t / period + phase, 1.0), u >= 0.6, into: %{} do
          [part, side] = String.split(limb, "_")
          fold = if part == "front", do: -40, else: -15
          {"#{part}_foot_#{side}", [flex: fold * :math.sin(:math.pi() * (u - 0.6) / 0.4)]}
        end

      wave = :math.sin(2 * :math.pi() * t / period)

      # The body is 1.5 cm lower than at rest: the legs bend a little, so
      # each paw can reach its point on the ground.
      feet
      |> Map.merge(folds)
      |> Map.merge(%{:hips => %{at: {0.0, 0.0, -0.015 * k}}, {:foot, :l} => :free, {:foot, :r} => :free})
      |> Map.merge(%{
        "tail_01" => [spread: 12 * wave],
        "tail_02" => [spread: 8 * wave],
        "neck_01" => [flex: 3 * wave]
      })
    end)
  end

  defp animation("wag", skeleton, _k) do
    Rig.clip("wag", skeleton, 0.8, 16, fn t ->
      wave = :math.sin(2 * :math.pi() * t / 0.4)
      %{"tail_01" => [spread: 25 * wave], "tail_02" => [spread: 20 * wave], "tail_03" => [spread: 15 * wave]}
    end)
  end

  defp animation(name, _skeleton, _k), do: raise(ArgumentError, "unknown animation of a dog #{inspect(name)}")

  # The move of a foot from its place at rest at a part of the step: on
  # the ground, the paw stays flat.
  defp foot(u, stride, _lift) when u < 0.6, do: %{by: {0.0, stride * (0.5 - u / 0.6), 0.0}, flat: true}

  defp foot(u, stride, lift) do
    v = (u - 0.6) / 0.4
    %{by: {0.0, stride * (v - 0.5), lift * :math.sin(:math.pi() * v)}}
  end
end
