defmodule World.Animals do
  @moduledoc """
  The animals of the world: figures from bones (`World.Rig`). An animal
  is a species of a body plan: the body plan gives the bones, the
  joints, the limbs, the ports and the gaits; the species gives its
  sizes, its colors and its sources. The body plans now: a quadruped
  with a tail (a dog). A cat or a water buffalo is the same plan with
  other sizes; a bird is another plan.

  - `"street_dog"` (`dog/1`): a street dog of Việt Nam (chó cỏ): a medium dog of mixed
    breed with a short coat, about 50 cm at the shoulder, a tail that it
    holds up. The sizes are a guess from the photos of the street dogs
    of Việt Nam and from the medium breeds (about 15 kg): no
    measurements.
  """
  alias World.{Joint, Limb, Part, Rig}

  @coat [200, 150, 90]
  @species ~w(street_dog)

  @doc "The names of the species."
  def species, do: @species

  @doc "An animal of a species, with the options of its function (`dog/1`)."
  def animal("street_dog", opts), do: dog(opts)
  def animal(name, _opts), do: raise(ArgumentError, "unknown species #{inspect(name)}: #{Enum.join(@species, ", ")}")

  @doc """
  A street dog. The options: `coat` (`[r, g, b]`, a tan coat by default),
  `size` (a scale of all the dog: 1 is about 50 cm at the shoulder), and
  `animations` (a list of `"walk"` and `"wag"`).

  The joints (the values add to the rest): the hinges `elbow_l`,
  `wrist_l`, `knee_l`, `hock_l` (and `_r`; more swings the lower bone to
  the front), the balls `shoulder_l`, `hip_l` (and `_r`), `neck`,
  `spine` and `tail` (flex lifts the tail, spread wags it to the right
  side). The limbs: `front_l`, `front_r` (the end is the wrist), `hind_l`,
  `hind_r` (the end is the hock), `tail` and `head`.
  """
  def dog(opts) do
    k = Keyword.get(opts, :size, 1.0) / 1
    coat = Keyword.get(opts, :coat, @coat)
    bones = for b <- bones(), do: scale(b, k)
    names = Keyword.get(opts, :animations, [])

    Rig.figure("dog",
      bones: bones,
      limbs: limbs(),
      joints: joints(),
      ports: ports(k),
      spheres: for({c, r, bone} <- spheres(), do: {scale_spot(c, k), r * k, bone, :eye}),
      blend: 0.03 * k,
      step: 0.012 * k,
      materials: %{
        fur: %{"color" => coat, "roughness" => 0.95, "metalness" => 0.0},
        eye: %{"color" => [24, 18, 16], "roughness" => 0.25, "metalness" => 0.0}
      },
      animations: for(name <- names, do: &animation(name, &1, k)),
      kind: :animal,
      params: %{"coat" => coat, "size" => k},
      sources: [
        "A street dog of Việt Nam (chó cỏ): about 50 cm at the shoulder and 15 kg. The sizes and the bones are a guess from photos and from the medium breeds of dogs; the gait is the walk of a dog (the feet in the order hind left, front left, hind right, front right)."
      ]
    )
  end

  # The bones of the dog: head, tail, radius at the head and at the tail
  # ({x, z}: the half width and the half height of the body).
  defp bones do
    trunk = [
      {"pelvis", nil, {0, -0.27, 0.42}, {0, -0.14, 0.43}, {{0.085, 0.10}, {0.09, 0.11}}},
      {"spine_01", "pelvis", {0, -0.14, 0.43}, {0, 0.0, 0.43}, {{0.09, 0.11}, {0.095, 0.12}}},
      {"spine_02", "spine_01", {0, 0.0, 0.43}, {0, 0.13, 0.43}, {{0.095, 0.12}, {0.10, 0.13}}},
      {"spine_03", "spine_02", {0, 0.13, 0.43}, {0, 0.24, 0.44}, {{0.10, 0.13}, {0.085, 0.11}}},
      {"neck_01", "spine_03", {0, 0.24, 0.44}, {0, 0.34, 0.56}, {{0.065, 0.075}, {0.05, 0.06}}},
      {"head", "neck_01", {0, 0.34, 0.56}, {0, 0.45, 0.57}, {{0.06, 0.065}, {0.05, 0.055}}},
      {"muzzle", "head", {0, 0.43, 0.55}, {0, 0.54, 0.51}, {{0.035, 0.035}, {0.022, 0.022}}},
      {"tail_01", "pelvis", {0, -0.27, 0.43}, {0, -0.34, 0.48}, {{0.025, 0.025}, {0.022, 0.022}}},
      {"tail_02", "tail_01", {0, -0.34, 0.48}, {0, -0.39, 0.55}, {{0.022, 0.022}, {0.017, 0.017}}},
      {"tail_03", "tail_02", {0, -0.39, 0.55}, {0, -0.40, 0.63}, {{0.017, 0.017}, {0.007, 0.007}}}
    ]

    # A leg of a dog: the shoulder blade goes down to the front from the
    # withers, the upper arm goes back to the elbow under the chest, and
    # the forearm goes down to the wrist; the thigh goes to the front to
    # the knee, the shin back to the hock. The upper bones are in the
    # body: the leg comes out of it at the elbow and at the knee. A paw is
    # a small round pad.
    paw = {{0.026, 0.02}, {0.024, 0.016}}

    sides =
      for {side, s} <- [{"l", -1}, {"r", 1}] do
        x = fn v -> s * v end

        [
          {"ear_#{side}", "head", {x.(0.04), 0.37, 0.61}, {x.(0.055), 0.35, 0.69}, {{0.022, 0.006}, {0.004, 0.003}},
           :tube},
          {"shoulder_blade_#{side}", "spine_03", {x.(0.055), 0.20, 0.47}, {x.(0.065), 0.27, 0.36},
           {{0.025, 0.045}, {0.04, 0.045}}},
          {"front_upper_#{side}", "shoulder_blade_#{side}", {x.(0.065), 0.27, 0.36}, {x.(0.065), 0.19, 0.27},
           {{0.04, 0.048}, {0.03, 0.03}}},
          {"front_lower_#{side}", "front_upper_#{side}", {x.(0.065), 0.19, 0.27}, {x.(0.062), 0.19, 0.09},
           {{0.026, 0.028}, {0.019, 0.019}}},
          {"front_foot_#{side}", "front_lower_#{side}", {x.(0.062), 0.19, 0.09}, {x.(0.062), 0.205, 0.03},
           {{0.019, 0.019}, {0.018, 0.018}}},
          {"front_toe_#{side}", "front_foot_#{side}", {x.(0.062), 0.205, 0.03}, {x.(0.062), 0.245, 0.022}, paw},
          {"hind_upper_#{side}", "pelvis", {x.(0.065), -0.21, 0.40}, {x.(0.068), -0.13, 0.26},
           {{0.07, 0.09}, {0.036, 0.038}}},
          {"hind_lower_#{side}", "hind_upper_#{side}", {x.(0.068), -0.13, 0.26}, {x.(0.066), -0.25, 0.12},
           {{0.032, 0.034}, {0.02, 0.02}}},
          {"hind_foot_#{side}", "hind_lower_#{side}", {x.(0.066), -0.25, 0.12}, {x.(0.066), -0.235, 0.03},
           {{0.019, 0.019}, {0.018, 0.018}}},
          {"hind_toe_#{side}", "hind_foot_#{side}", {x.(0.066), -0.235, 0.03}, {x.(0.066), -0.195, 0.022}, paw}
        ]
      end

    for bone <- trunk ++ List.flatten(sides) do
      [name, parent, head, tail, radius | skin] = Tuple.to_list(bone)

      %{
        name: name,
        parent: parent,
        head: head,
        tail: tail,
        radius: radius,
        skin: List.first(skin, :blob),
        group: group(name)
      }
    end
  end

  # The groups of the skin: the bones of a group join with no blend.
  defp group(name) do
    cond do
      name in ~w(pelvis spine_01 spine_02 spine_03) -> "trunk"
      name in ~w(neck_01 head) -> "neck"
      String.starts_with?(name, "tail") -> "tail"
      String.contains?(name, ~w(front_upper front_lower front_foot)) -> "front_" <> String.last(name)
      String.contains?(name, ~w(hind_upper hind_lower hind_foot)) -> "hind_" <> String.last(name)
      true -> name
    end
  end

  # The eyes and the nose.
  defp spheres do
    [
      {{:on, {-0.02, 0.4, 0.58}, {-0.5, 1.0, 0.3}}, 0.012, "head"},
      {{:on, {0.02, 0.4, 0.58}, {0.5, 1.0, 0.3}}, 0.012, "head"},
      {{:on, {0.0, 0.49, 0.53}, {0.0, 1.0, -0.35}}, 0.014, "muzzle"}
    ]
  end

  defp scale(b, k),
    do: %{b | head: scale_point(b.head, k), tail: scale_point(b.tail, k), radius: scale_radius(b.radius, k)}

  defp scale_point({x, y, z}, k), do: {x * k, y * k, z * k}
  defp scale_spot({:on, from, dir}, k), do: {:on, scale_point(from, k), dir}
  defp scale_radius({{a, b}, {c, d}}, k), do: {{a * k, b * k}, {c * k, d * k}}

  defp limbs do
    for(
      side <- ~w(l r),
      do: [
        Limb.new("front_#{side}", ["front_upper_#{side}", "front_lower_#{side}"], role: :leg, pole: {0.0, -1.0, 0.0}),
        Limb.new("hind_#{side}", ["hind_upper_#{side}", "hind_lower_#{side}"], role: :leg, pole: {0.0, 1.0, 0.0})
      ]
    )
    |> List.flatten()
    |> Kernel.++([
      Limb.new("tail", ~w(tail_01 tail_02 tail_03), role: :tail, solver: :chain),
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
  # the mouth (a stick).
  defp ports(k) do
    [
      {"ground", nil, Part.port("ground", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})},
      {"collar", "neck_01", Part.port("collar", scale_point({0.0, 0.27, 0.48}, k), {0, 0.6, 0.8}, {0, -0.8, 0.6})},
      {"back", "spine_02", Part.port("back", scale_point({0.0, 0.06, 0.55}, k), {0, 0, 1}, {0, 1, 0})},
      {"mouth", "muzzle", Part.port("mouth", scale_point({0.0, 0.52, 0.5}, k), {1, 0, 0}, {0, 0, 1})}
    ]
  end

  # The walk: each foot goes back on the ground for 0.6 of the step, and
  # to the front in the air for the rest; the feet in the order hind left,
  # front left, hind right, front right. The tail wags a little, the head
  # nods. A step of 0.7 s with a stride of 30 cm: about 0.43 m/s (an app
  # moves the dog at that speed). The wag: the tail wags twice in 0.8 s.
  defp animation("walk", skeleton, k) do
    period = 0.7
    phases = %{"hind_l" => 0.0, "front_l" => 0.25, "hind_r" => 0.5, "front_r" => 0.75}

    Rig.clip("walk", skeleton, period, 14, fn t ->
      feet =
        for {limb, phase} <- phases, into: %{} do
          {{:limb, limb}, foot(:math.fmod(t / period + phase, 1.0), 0.3 * k, 0.06 * k)}
        end

      # A paw in the air folds back at the wrist (more at the front).
      folds =
        for {limb, phase} <- phases, u = :math.fmod(t / period + phase, 1.0), u >= 0.6, into: %{} do
          [part, side] = String.split(limb, "_")
          fold = if part == "front", do: -70, else: -25
          {"#{part}_foot_#{side}", [flex: fold * :math.sin(:math.pi() * (u - 0.6) / 0.4)]}
        end

      wave = :math.sin(2 * :math.pi() * t / period)

      feet
      |> Map.merge(folds)
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
