defmodule World.Animals.Biped do
  @moduledoc """
  The body plan of an animal that stands on two legs, with two arms and
  a tail: a monkey.

  The bones of World: `pelvis`, `spine_01`, `spine_02`, `spine_03`,
  `neck_01`, `head`, the tail (`tail_01` ...), and for each side (`_l`,
  `_r`) `clavicle`, `upper_arm`, `forearm`, `hand` and `thigh`, `shin`,
  `foot`, `toes`.

  The joints (the values add to the rest): the hinges `elbow_l`,
  `wrist_l`, `knee_l`, `ankle_l` (and `_r`; more takes the forearm, the
  hand and the toes to the front, and the foot to the back at the
  knee), the balls `shoulder_l`, `hip_l` (and `_r`), `neck`, `spine`
  and `tail`. The limbs: `arm_l`, `arm_r` (the end is the wrist, the
  elbow goes to the back), `leg_l`, `leg_r` (the end is the ankle, the
  knee goes to the front), `tail` and `head` (chains). The ports:
  `ground`, `grip_l`, `grip_r` (in the hands: a banana), `back` (a bag).

  The animations: `walk` (on two legs: each foot is on the ground for
  0.6 of the step, and flat all the step; the arms swing against the legs, the tail
  sways), `wave` (the right hand waves above the shoulder) and `wag`
  (the tail swings). The numbers of the gait of a species (`gait`):
  `period` (the time of a step, s), `stride`, `lift` and `drop` (parts
  of the height), `swing` (the swing of the arms, degrees).
  """
  alias World.{Animals, Joint, Limb, Part, Rig, Vec}

  @sides ~w(l r)

  @doc false
  def figure_name(species), do: species

  @doc "The bones of the body plan, parents first."
  def bones do
    ~w(pelvis spine_01 spine_02 spine_03 neck_01 head) ++
      for(i <- 1..9, do: "tail_0#{i}") ++
      for side <- @sides, name <- ~w(clavicle upper_arm forearm hand thigh shin foot toes), do: "#{name}_#{side}"
  end

  @chain ~w(pelvis spine_01 spine_02 spine_03 neck_01 head) ++ [nil]
  @arm ~w(clavicle upper_arm forearm hand) ++ [nil]
  @leg ~w(thigh shin foot toes) ++ [nil]

  @doc "The bone whose head is the tail of a bone (nil: the end of the bone of the mesh)."
  def next("tail_0" <> i), do: "tail_0#{String.to_integer(i) + 1}"

  def next(name) do
    case Enum.find_index(@chain, &(&1 == name)) do
      nil ->
        [side | rest] = name |> String.split("_") |> Enum.reverse()
        part = rest |> Enum.reverse() |> Enum.join("_")
        list = if part in @arm, do: @arm, else: @leg
        with n when n != nil <- Enum.at(list, Enum.find_index(list, &(&1 == part)) + 1), do: "#{n}_#{side}"

      i ->
        Enum.at(@chain, i + 1)
    end
  end

  @doc "The hinge of a bone: a bend of a shin takes the foot to the back."
  def hinge(name, _dir), do: if(String.starts_with?(name, "shin_"), do: {-1.0, 0.0, 0.0}, else: {1.0, 0.0, 0.0})

  @doc "The height of the mesh: its highest point."
  def height(points, _weights), do: points |> Enum.map(fn [_, _, z] -> z end) |> Enum.max()

  @doc "The names of the animations."
  def animations, do: ~w(walk wave wag)

  def limbs(by) do
    tail = Enum.filter(bones(), &(String.starts_with?(&1, "tail_") and Map.has_key?(by, &1)))

    for(
      side <- @sides,
      do: Limb.new("arm_#{side}", ["upper_arm_#{side}", "forearm_#{side}"], role: :arm, pole: {0.0, -1.0, 0.0})
    ) ++
      for(
        side <- @sides,
        do: Limb.new("leg_#{side}", ["thigh_#{side}", "shin_#{side}"], role: :leg, pole: {0.0, 1.0, 0.0})
      ) ++
      [
        Limb.new("tail", tail, role: :tail, solver: :chain),
        Limb.new("head", ~w(neck_01 head), role: :neck, solver: :chain)
      ]
  end

  def joints(_by) do
    sides =
      for side <- @sides do
        [
          Joint.new("shoulder_#{side}", :ball,
            role: :shoulder,
            bone: "upper_arm_#{side}",
            limits: %{flex: {-60, 170}, spread: {-120, 120}, twist: {-60, 60}}
          ),
          Joint.new("elbow_#{side}", :hinge, role: :elbow, bone: "forearm_#{side}", limits: {0, 150}),
          Joint.new("wrist_#{side}", :hinge, role: :wrist, bone: "hand_#{side}", limits: {-70, 70}),
          Joint.new("hip_#{side}", :ball,
            role: :hip,
            bone: "thigh_#{side}",
            limits: %{flex: {-30, 120}, spread: {-40, 40}, twist: {-30, 30}}
          ),
          Joint.new("knee_#{side}", :hinge, role: :knee, bone: "shin_#{side}", limits: {0, 150}),
          Joint.new("ankle_#{side}", :hinge, role: :ankle, bone: "foot_#{side}", limits: {-40, 40})
        ]
      end

    List.flatten(sides) ++
      [
        Joint.new("neck", :ball,
          role: :neck,
          bone: "neck_01",
          limits: %{flex: {-40, 60}, spread: {-70, 70}, twist: {-70, 70}}
        ),
        Joint.new("spine", :ball,
          role: :spine,
          bone: "spine_02",
          limits: %{flex: {-30, 60}, spread: {-30, 30}, twist: {-30, 30}}
        ),
        Joint.new("tail", :ball,
          role: :tail,
          bone: "tail_01",
          limits: %{flex: {-60, 60}, spread: {-60, 60}, twist: {-30, 30}}
        )
      ]
  end

  def ports(by) do
    spine = by["spine_02"]

    grips =
      for side <- @sides do
        hand = by["hand_#{side}"]
        along = Vec.norm(Vec.sub(hand.tail, hand.head))

        {"grip_#{side}", "hand_#{side}",
         Part.port("grip_#{side}", Vec.lerp(hand.head, hand.tail, 0.5), {0, 1, 0}, along)}
      end

    [{"ground", nil, Part.port("ground", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})}] ++
      grips ++ [{"back", "spine_02", Part.port("back", Vec.lerp(spine.head, spine.tail, 0.5), {0, -1, 0}, {0, 0, 1})}]
  end

  @doc "An animation of the body plan, for an animal of height `h` (m) and the numbers of the gait of its species."
  def animation("walk", skeleton, h, gait) do
    period = Map.get(gait, "period", 0.8)

    {stride, lift, drop} =
      {Map.get(gait, "stride", 0.25) * h, Map.get(gait, "lift", 0.06) * h, Map.get(gait, "drop", 0.02) * h}

    swing = Map.get(gait, "swing", 20)

    Rig.clip("walk", skeleton, period, 16, fn t ->
      for side <- @sides, into: %{} do
        u = :math.fmod(t / period + if(side == "l", do: 0.0, else: 0.5), 1.0)
        # The foot stays flat in the air too: the toes do not hang.
        {{:limb, "leg_#{side}"}, Map.put(Animals.foot(u, stride, lift, 0.6), :flat, true)}
      end
      |> Map.merge(
        for side <- @sides, into: %{} do
          u = t / period + if(side == "l", do: 0.0, else: 0.5)
          {"upper_arm_#{side}", [flex: -swing * :math.cos(2 * :math.pi() * u)]}
        end
      )
      |> Map.merge(%{
        :hips => %{at: {0.0, 0.0, -drop}},
        {:foot, :l} => :free,
        {:foot, :r} => :free,
        "tail_01" => [spread: 10 * :math.sin(2 * :math.pi() * t / period)]
      })
    end)
  end

  def animation("wave", skeleton, h, _gait) do
    shoulder = skeleton.rest["upper_arm_r"].at

    Rig.clip("wave", skeleton, 1.2, 24, fn t ->
      side = 0.08 * h * :math.sin(2 * :math.pi() * t / 0.6)
      %{{:limb, "arm_r"} => %{at: Vec.add(shoulder, {0.12 * h + side, 0.06 * h, 0.22 * h}), pole: {1.0, 0.0, -1.0}}}
    end)
  end

  def animation("wag", skeleton, _h, _gait) do
    tail = Enum.filter(~w(tail_01 tail_02 tail_03 tail_04), &Map.has_key?(skeleton.rest, &1))

    Rig.clip("wag", skeleton, 1.6, 16, fn t ->
      wave = :math.sin(2 * :math.pi() * t / 1.6)
      tail |> Enum.zip([15, 12, 10, 8]) |> Map.new(fn {bone, a} -> {bone, [spread: a * wave]} end)
    end)
  end
end
