defmodule World.Animals.Primate do
  @moduledoc """
  The body plan of a primate: two arms with hands, two legs, a tail. Its
  bones have the names of the bones of a person (`World.People.Skeleton`),
  so the joints, the hips, the feet, the reach of an arm and the look of
  a person work on it.

  The bones of World: `pelvis`, `spine_01`, `spine_02`, `spine_03`,
  `neck_01`, `head`, the tail (`tail_01` ...), and for each side (`_l`,
  `_r`) `clavicle`, `upperarm`, `lowerarm`, `hand`, the three bones of
  each finger (`thumb_01_l` ... `pinky_03_l`, as a person) and `thigh`,
  `calf`, `foot`, `ball`.

  The joints (the values add to the pose): the hinges `elbow_l`,
  `wrist_l`, `knee_l`, `ankle_l` (and `_r`), the balls `shoulder_l`,
  `hip_l` (and `_r`), `neck`, `spine` and `tail`. The limbs: `arm_l`,
  `arm_r` (the end is the wrist, the elbow goes to the back), `leg_l`,
  `leg_r` (the end is the ankle, the knee goes to the front), `tail` and
  `head` (chains). The ports: `ground`, `grip_l`, `grip_r` (in the
  hands), `back` (a bag).

  The pose of the animal is on four limbs (`pose/2`): the back near
  level, the hands flat under the shoulders, the feet under the hips,
  the head over the line of the back, the face to the front, the tail
  up and then down in a curve. With `"upright"` in the gait (`stance/2`),
  the animal stands on two legs with the arms up and out (`upright/2`).
  The animations: `walk` (on four limbs, in the order of a primate: hind
  left, front right, hind right, front left; each hand or foot is on the
  ground for 0.6 of the step; upright, on the two legs), `sit` (on the
  seat, the back bent, the knees up, the hands together in front of the
  feet, the head turns to look around), `climb` (up a trunk in front of
  the animal, the hands grip), `hang` (from a branch by the two hands)
  and `jump` (a crouch, a flight, a landing). The numbers of the gait of
  a species (`gait`): `period` (the time of a step, s), `stride` and
  `lift` (parts of the length of the animal), and `upright`.
  """
  alias World.{Animals, Joint, Limb, Part, Rig, Vec}

  @sides ~w(l r)
  @chain ~w(pelvis spine_01 spine_02 spine_03 neck_01 head) ++ [nil]
  @arm ~w(clavicle upperarm lowerarm hand) ++ [nil]
  @leg ~w(thigh calf foot ball) ++ [nil]
  @fingers ~w(thumb index middle ring pinky)

  @doc false
  def figure_name(species), do: species

  @doc "The bones of the body plan, parents first."
  def bones do
    ~w(pelvis spine_01 spine_02 spine_03 neck_01 head) ++
      for(i <- 1..9, do: "tail_0#{i}") ++
      for(side <- @sides, name <- (@arm -- [nil]) ++ (@leg -- [nil]), do: "#{name}_#{side}") ++
      for side <- @sides, f <- @fingers, n <- 1..3, do: "#{f}_0#{n}_#{side}"
  end

  @doc "The bone whose head is the tail of a bone (nil: the end of the bone of the mesh)."
  def next("tail_0" <> i), do: "tail_0#{String.to_integer(i) + 1}"

  def next(name) do
    case {Enum.find_index(@chain, &(&1 == name)), String.split(name, "_")} do
      {nil, [f, n, side]} when f in @fingers ->
        if n == "03", do: nil, else: "#{f}_0#{String.to_integer(n) + 1}_#{side}"

      {nil, [part, side]} ->
        list = if part in @arm, do: @arm, else: @leg
        with n when n != nil <- Enum.at(list, Enum.find_index(list, &(&1 == part)) + 1), do: "#{n}_#{side}"

      {i, _} ->
        Enum.at(@chain, i + 1)
    end
  end

  @doc "The hinge of a bone: a bend of a calf takes the foot to the back."
  def hinge(name, _dir), do: if(String.starts_with?(name, "calf_"), do: {-1.0, 0.0, 0.0}, else: {1.0, 0.0, 0.0})

  @doc """
  The length of the head and the body (at rest, when it stands): from the
  top of the head to the lowest point of the pelvis.
  """
  def height(points, weights) do
    seat = for {i, w} <- weights["pelvis"], w >= 0.5, do: elem(Enum.at(points, i), 2)
    (points |> Enum.map(&elem(&1, 2)) |> Enum.max()) - Enum.min(seat)
  end

  @doc "The names of the animations."
  def animations, do: ~w(walk sit climb hang jump)

  @doc "The animations that are clips of the template: none."
  def clips, do: []

  def limbs(by) do
    tail = Enum.filter(bones(), &(String.starts_with?(&1, "tail_") and Map.has_key?(by, &1)))

    for(
      side <- @sides,
      do: Limb.new("arm_#{side}", ["upperarm_#{side}", "lowerarm_#{side}"], role: :arm, pole: {0.0, -1.0, 0.0})
    ) ++
      for(
        side <- @sides,
        do: Limb.new("leg_#{side}", ["thigh_#{side}", "calf_#{side}"], role: :leg, pole: {0.0, 1.0, 0.0})
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
            bone: "upperarm_#{side}",
            limits: %{flex: {-60, 170}, spread: {-120, 120}, twist: {-60, 60}}
          ),
          Joint.new("elbow_#{side}", :hinge, role: :elbow, bone: "lowerarm_#{side}", limits: {0, 150}),
          Joint.new("wrist_#{side}", :hinge, role: :wrist, bone: "hand_#{side}", limits: {-80, 80}),
          Joint.new("hip_#{side}", :ball,
            role: :hip,
            bone: "thigh_#{side}",
            limits: %{flex: {-30, 140}, spread: {-40, 40}, twist: {-30, 30}}
          ),
          Joint.new("knee_#{side}", :hinge, role: :knee, bone: "calf_#{side}", limits: {0, 150}),
          Joint.new("ankle_#{side}", :hinge, role: :ankle, bone: "foot_#{side}", limits: {-40, 40})
        ]
      end

    List.flatten(sides) ++
      [
        Joint.new("neck", :ball,
          role: :neck,
          bone: "neck_01",
          limits: %{flex: {-60, 60}, spread: {-70, 70}, twist: {-70, 70}}
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

  # The neck goes up from the shoulders, so the head is over the line of
  # the back; the tail goes up from its root and then down in a curve.
  @carry %{
    "neck_01" => [flex: 60],
    "tail_03" => [flex: 15],
    "tail_04" => [flex: 15],
    "tail_05" => [flex: 15],
    "tail_06" => [flex: 12],
    "tail_07" => [flex: 10]
  }

  @doc """
  The pose on four limbs: the hips go down and turn to the front, the
  ankles stay under the hips, the wrists go to the ground under the
  shoulders, the hands lie flat with the fingers to the front, the neck
  goes up, the face looks to the front, and the tail goes up and then
  down in a curve. `moves` moves the hands and the feet from
  their places in the pose (`{:hand, side}` and `{:foot, side}` to a
  move), `:body` moves up all the animal (the hips, the hands and the
  feet: in the air), `:crouch` moves the hips only (down: the limbs
  bend).
  """
  def pose(skeleton, moves \\ %{}) do
    r = skeleton.rest
    span = fn a, b -> Vec.len(Vec.sub(r[b].at, r[a].at)) end
    hip = r["pelvis"].at
    ground = elem(r["foot_l"].at, 2)
    legs = span.("thigh_l", "calf_l") + span.("calf_l", "foot_l")
    arms = span.("upperarm_l", "lowerarm_l") + span.("lowerarm_l", "hand_l")
    trunk = Vec.sub(Vec.lerp(r["upperarm_l"].at, r["upperarm_r"].at, 0.5), hip)

    # The hips at 0.88 of the legs (the knees a little bent), the shoulders
    # at 0.93 of the arms (the arms near straight), as in photos of a
    # macaque that walks: the turn of the body from the height of the
    # shoulders over the hips.
    lift = Map.get(moves, :body, 0.0)
    up = ground + 0.88 * legs
    cos = ((ground + 0.93 * arms - up) / Vec.len(trunk)) |> max(-0.3) |> min(0.6)
    t = :math.acos(cos)
    back = -0.5 * Vec.len(trunk) * :math.sin(t)
    pitch = fn {x, y, z} -> {x, y * cos + z * :math.sin(t), -y * :math.sin(t) + z * cos} end
    at = fn p -> Vec.add({0.0, back, up}, pitch.(Vec.sub(p, hip))) end
    move = fn key -> Vec.add(Map.get(moves, key, {0.0, 0.0, 0.0}), {0.0, 0.0, lift}) end

    feet =
      for side <- @sides, into: %{} do
        {x, _, _} = r["foot_#{side}"].at
        {{:foot, String.to_atom(side)}, %{at: Vec.add({x, back, ground}, move.({:foot, side})), flat: true}}
      end

    # The hands flat on the ground, the fingers to the front: the palm is
    # on the side of x of the left hand, of -x of the right hand.
    hands =
      for side <- @sides, into: %{} do
        {x, y, _} = at.(r["upperarm_#{side}"].at)
        target = Vec.add({x, y, ground}, move.({:hand, side}))
        palm = if side == "l", do: {0.0, 0.0, -1.0}, else: {0.0, 0.0, 1.0}

        {{:limb, "arm_#{side}"}, %{at: target, pole: {0.0, -1.0, 0.0}, flat: true, lay: {{0.0, 1.0, 0.0}, palm}}}
      end

    flat =
      for side <- @sides, into: %{} do
        sign = if side == "l", do: 1, else: -1
        {"lowerarm_#{side}", [twist: sign * 80]}
      end

    hips = {0.0, back, up - elem(hip, 2) + lift + Map.get(moves, :crouch, 0.0)}

    %{:hips => %{at: hips, turn: [flex: t * 180 / :math.pi()]}, :look => {0.0, 1.0, -0.1}}
    |> Map.merge(@carry)
    |> Map.merge(feet)
    |> Map.merge(hands)
    |> Map.merge(flat)
  end

  @doc """
  The pose of the animal with the numbers of the gait of its species:
  on four limbs (`pose/2`), or upright for a species with `"upright":
  true` (`upright/2`).
  """
  def stance(skeleton, %{"upright" => true}), do: upright(skeleton)
  def stance(skeleton, _gait), do: pose(skeleton)

  @doc """
  The pose upright, as a gibbon on the ground: the body up over the
  feet, the knees a little bent, the arms up and out for balance, the
  hands relaxed. `moves` moves the feet (`{:foot, side}` to a move) and
  the hips (`:hips` to a move).
  """
  def upright(skeleton, moves \\ %{}) do
    r = skeleton.rest
    %{legs: legs, arms: arms, shoulder: shoulder} = sizes(skeleton)

    for side <- @sides, into: %{} do
      sign = if side == "l", do: 1.0, else: -1.0
      {x, _, _} = r["upperarm_#{side}"].at
      {fx, _, fz} = r["foot_#{side}"].at

      {side,
       %{
         {:foot, String.to_atom(side)} => %{
           at: Vec.add({fx, 0.0, fz}, Map.get(moves, {:foot, side}, {0.0, 0.0, 0.0})),
           flat: true
         },
         {:limb, "arm_#{side}"} => %{
           at: {x + sign * 0.6 * arms, 0.1 * legs, shoulder + 0.55 * arms},
           pole: {sign, -0.5, 0.0}
         },
         {:hand, String.to_atom(side)} => "relaxed"
       }}
    end
    |> Map.values()
    |> Enum.reduce(
      %{
        :hips => %{at: Vec.add({0.0, 0.0, -0.04 * legs}, Map.get(moves, :hips, {0.0, 0.0, 0.0})), turn: [flex: 5]},
        :look => {0.0, 1.0, 0.0}
      },
      &Map.merge/2
    )
  end

  @doc "The speed of the walk of an animal of length `h` (m) with the numbers of the gait of its species (m/s)."
  def speeds(h, gait), do: %{"walk_speed" => Float.round(stride(h, gait) / (0.6 * period(gait)), 2)}

  defp period(gait), do: Map.get(gait, "period", 0.7)
  defp stride(h, gait), do: Map.get(gait, "stride", 0.45) * h

  @doc "An animation of the body plan, for an animal of length `h` (m) and the numbers of the gait of its species."
  def animation("walk", skeleton, h, %{"upright" => true} = gait) do
    {period, stride, lift} = {period(gait), stride(h, gait), Map.get(gait, "lift", 0.1) * h}
    %{legs: legs} = sizes(skeleton)

    Rig.clip("walk", skeleton, period, 16, fn t ->
      u = t / period

      moves =
        Map.new([{"l", 0.0}, {"r", 0.5}], fn {side, phase} ->
          {{:foot, side}, Animals.foot(:math.fmod(u + phase, 1.0), stride, lift, 0.6).by}
        end)

      # The hips go down from the stance, not up: a straight leg cannot
      # reach the ground under hips that go up.
      bob = 0.015 * legs * (:math.cos(4 * :math.pi() * u) - 1)
      upright(skeleton, Map.put(moves, :hips, {0.0, 0.0, bob}))
    end)
  end

  def animation("walk", skeleton, h, gait) do
    {period, stride, lift} = {period(gait), stride(h, gait), Map.get(gait, "lift", 0.1) * h}
    # A limb lands at the part 1 - phase of the step.
    phases = %{{:foot, "l"} => 0.0, {:hand, "r"} => 0.75, {:foot, "r"} => 0.5, {:hand, "l"} => 0.25}

    Rig.clip("walk", skeleton, period, 16, fn t ->
      moves =
        Map.new(phases, fn {key, phase} ->
          {key, Animals.foot(:math.fmod(t / period + phase, 1.0), stride, lift, 0.6).by}
        end)

      wave = :math.sin(2 * :math.pi() * t / period)
      Map.merge(pose(skeleton, moves), %{"tail_01" => [spread: 8 * wave], "tail_02" => [spread: 6 * wave]})
    end)
  end

  def animation("sit", skeleton, _h, _gait) do
    r = skeleton.rest
    hip = r["pelvis"].at
    ground = elem(r["foot_l"].at, 2)
    span = fn a, b -> Vec.len(Vec.sub(r[b].at, r[a].at)) end
    legs = span.("thigh_l", "calf_l") + span.("calf_l", "foot_l")
    # The seat on the ground: the hips as high as the lowest point of the
    # pelvis is under them. The back bends to the front, the feet are near
    # the seat and the knees go up and out, the hands are together in
    # front of the feet.
    seat = 0.3 * legs

    base =
      %{
        :hips => %{at: {0.0, 0.0, seat - elem(hip, 2)}, turn: [flex: 20]},
        "spine_02" => [flex: 30],
        "spine_03" => [flex: 30]
      }
      |> Map.merge(
        for side <- @sides, into: %{} do
          {x, _, _} = r["foot_#{side}"].at

          {{:foot, String.to_atom(side)},
           %{at: {x * 1.2, 0.3 * legs, ground}, flat: true, pole: Vec.norm({4 * x, 0.3, 1.0})}}
        end
      )
      |> Map.merge(
        for side <- @sides, into: %{} do
          {x, _, _} = r["upperarm_#{side}"].at
          {{:reach, String.to_atom(side)}, %{at: {x * 0.3, 0.5 * legs, ground + 0.05 * legs}, pole: {0.0, -1.0, 0.0}}}
        end
      )

    # The tail lies on the ground to the back, and curls a little.
    tail = %{"tail_01" => [{{1.0, 0.0, 0.0}, -85}], "tail_04" => [spread: 25], "tail_06" => [spread: 25]}

    Rig.clip("sit", skeleton, 4.0, 24, fn t ->
      a = 0.9 * :math.sin(2 * :math.pi() * t / 4.0)
      base |> Map.merge(tail) |> Map.put(:look, {:math.sin(a), :math.cos(a), -0.1})
    end)
  end

  # The climb: the trunk of a tree is a plane in front of the chest; the
  # body is upright on it, and the hands and the feet go up it in the
  # order of the walk.
  def animation("climb", skeleton, _h, gait) do
    r = skeleton.rest
    %{legs: legs, arms: arms, shoulder: shoulder} = sizes(skeleton)
    {period, step} = {period(gait), 0.35 * legs}
    hip = r["pelvis"].at
    # The hips 0.5 of the legs over their rest, the trunk 0.3 of the legs
    # in front of the hips.
    lift = 0.5 * legs
    front = elem(hip, 1) + 0.3 * legs
    phases = %{{:foot, "l"} => 0.0, {:hand, "r"} => 0.75, {:foot, "r"} => 0.5, {:hand, "l"} => 0.25}

    # A hand or a foot on the trunk goes down by a step (the body goes up)
    # for 0.6 of a step; then it goes up by a step, off the trunk.
    move = fn key, t ->
      u = :math.fmod(t / period + phases[key], 1.0)

      if u < 0.6,
        do: {step * (0.5 - u / 0.6), 0.0},
        else: {step * ((u - 0.6) / 0.4 - 0.5), 0.12 * legs * :math.sin(:math.pi() * (u - 0.6) / 0.4)}
    end

    Rig.clip("climb", skeleton, period, 16, fn t ->
      limbs =
        for side <- @sides do
          sign = if side == "l", do: 1.0, else: -1.0
          {x, _, _} = r["upperarm_#{side}"].at
          {{fx, _, _}, {dz, off}} = {r["foot_#{side}"].at, move.({:foot, side}, t)}
          {hz, hoff} = move.({:hand, side}, t)

          [
            {{:limb, "arm_#{side}"},
             %{
               at: {0.8 * x, front - hoff, shoulder + lift + 0.5 * arms + hz},
               pole: {sign, -0.3, 0.0},
               lay: {{0.0, 0.0, 1.0}, {0.0, sign, 0.0}}
             }},
            {{:foot, String.to_atom(side)},
             %{
               at: {2.2 * fx, front - 0.05 * legs - off, elem(hip, 2) + lift - 0.55 * legs + dz},
               pole: {sign, 0.5, 0.2}
             }},
            {{:hand, String.to_atom(side)}, "grip"}
          ]
        end
        |> Enum.concat()
        |> Map.new()

      Map.merge(limbs, %{:hips => %{at: {0.0, 0.0, lift}, turn: []}, :look => {0.0, 1.0, 0.5}})
    end)
  end

  # The hang: both hands grip a branch over the head, the arms straight,
  # the body hangs under them with the feet off the ground and swings a
  # little; the head looks around.
  def animation("hang", skeleton, _h, _gait) do
    r = skeleton.rest
    %{legs: legs, arms: arms, shoulder: shoulder} = sizes(skeleton)
    hip = r["pelvis"].at
    lift = 0.6 * legs
    branch = shoulder + lift + 0.95 * arms

    Rig.clip("hang", skeleton, 3.0, 24, fn t ->
      swing = 8 * :math.sin(2 * :math.pi() * t / 3.0)
      a = 0.6 * :math.sin(2 * :math.pi() * t / 3.0 + 1.0)

      limbs =
        for side <- @sides, into: %{} do
          sign = if side == "l", do: 1.0, else: -1.0
          {x, _, _} = r["upperarm_#{side}"].at
          {fx, _, _} = r["foot_#{side}"].at

          {side,
           %{
             {:limb, "arm_#{side}"} => %{
               at: {0.7 * x, 0.0, branch},
               pole: {sign, -1.0, 0.0},
               lay: {{0.0, 0.0, 1.0}, {0.0, sign, 0.0}}
             },
             {:foot, String.to_atom(side)} => %{
               at: {1.3 * fx, 0.15 * legs, elem(hip, 2) + lift - 0.85 * legs},
               pole: {0.0, 1.0, 0.0}
             },
             {:hand, String.to_atom(side)} => "grip"
           }}
        end
        |> Map.values()
        |> Enum.reduce(&Map.merge/2)

      Map.merge(limbs, %{
        :hips => %{at: {0.0, 0.0, lift}, turn: [flex: swing]},
        :look => {:math.sin(a), :math.cos(a), 0.0}
      })
    end)
  end

  # The jump: on four limbs, the hips go down (0 to 0.3 of the time), the
  # animal leaps up (0.35 to 0.75: in the air, 0.5 of the legs at the
  # top) and lands, the hips down a little.
  def animation("jump", skeleton, _h, _gait) do
    %{legs: legs} = sizes(skeleton)

    Rig.clip("jump", skeleton, 1.4, 28, fn t ->
      u = t / 1.4

      {crouch, body} =
        cond do
          u < 0.35 -> {-0.18 * legs * :math.sin(:math.pi() * u / 0.35), 0.0}
          u < 0.75 -> {0.0, 0.5 * legs * 4 * ((u - 0.35) / 0.4) * (1 - (u - 0.35) / 0.4)}
          true -> {-0.1 * legs * :math.sin(:math.pi() * (u - 0.75) / 0.25), 0.0}
        end

      pose(skeleton, %{crouch: crouch, body: body})
    end)
  end

  # The lengths of the legs and the arms, the height of the ground and of
  # the shoulders at rest.
  defp sizes(%{rest: r}) do
    span = fn a, b -> Vec.len(Vec.sub(r[b].at, r[a].at)) end

    %{
      legs: span.("thigh_l", "calf_l") + span.("calf_l", "foot_l"),
      arms: span.("upperarm_l", "lowerarm_l") + span.("lowerarm_l", "hand_l"),
      ground: elem(r["foot_l"].at, 2),
      shoulder: elem(r["upperarm_l"].at, 2)
    }
  end
end
