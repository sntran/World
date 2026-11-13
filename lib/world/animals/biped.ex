defmodule World.Animals.Biped do
  @moduledoc """
  The body plan of a body on two legs: a puppet, a robot, a person of a
  sculptor (`docs/plans/0010-sculpture-maps.md`, D12).

  The bones have the names of a person of World: `pelvis` (the root),
  `spine_01`, `neck_01`, `head`, and for each side (`_l`, `_r`) the arm
  (`upperarm`, `lowerarm`, `hand`) and the leg (`thigh`, `calf`, `foot`).
  The body can have more bones (a `ball` for the toes, a tail, an ear):
  they follow their parents.

  The joints (the values add to the rest): the balls `shoulder_l`,
  `shoulder_r`, `hip_l`, `hip_r` and `neck`, and the hinges `elbow_l`,
  `elbow_r`, `knee_l` and `knee_r`. The limbs: `arm_l`, `arm_r` (the end
  is the wrist), `leg_l`, `leg_r` (the end is the ankle). The ports:
  `ground`, `head` (the top of the head), `grip_l` and `grip_r` (the
  hands).

  The animations: `walk` (the feet in turn, each on the ground for 0.6
  of the step; the hips are as high as the legs let them, so they go up
  over the foot on the ground and down between two steps; the arms hang
  and swing against the legs), `run` (each foot on the ground for 0.35 of
  the step, so the body is in the air between two steps; the elbows
  bent, the body to the front) and `idle` (the body stands, and goes
  down and up a little as it breathes). The numbers of the gait
  (`gait`): `period` (s), `stride` and `lift` (parts of the height), for
  the walk.

  The sculptor can make the body in any pose: with the arms out to the
  sides (a T) or down. The hinge of an elbow takes the hand to the
  front, and the hinge of a knee takes the foot to the back, in each
  pose.
  """
  alias World.{Animals, Joint, Limb, Part, Rig, Vec}

  @sides ~w(l r)
  @arm ~w(upperarm lowerarm hand)
  @leg ~w(thigh calf foot)
  # A leg is not more straight than this part of its length: the knee keeps a small bend.
  @reach 0.98

  @doc "The bones of the body plan, parents first."
  def bones, do: ~w(pelvis spine_01 neck_01 head) ++ for(s <- @sides, n <- @arm ++ @leg, do: "#{n}_#{s}")

  @doc """
  The hinge of a bone that points to `dir`: a bend of a forearm takes
  the hand to the front, a bend of a calf takes the foot to the back.
  """
  def hinge("lowerarm_" <> _, dir), do: across(dir, 1.0)
  def hinge("calf_" <> _, dir), do: across(dir, -1.0)
  def hinge(_name, _dir), do: {1.0, 0.0, 0.0}

  # The axis whose turn takes the end of a bone to the front (or to the
  # back, with -1). A bone that points to the front or to the back has
  # the hinge across the body.
  defp across(dir, sign) do
    axis = Vec.cross(dir, {0.0, 1.0, 0.0})
    if Vec.len(axis) < 0.1, do: {sign, 0.0, 0.0}, else: Vec.scale(Vec.norm(axis), sign)
  end

  @doc "The height of the mesh: its highest point with a weight."
  def height(points, weights) do
    points = List.to_tuple(points)
    for(m <- Map.values(weights), {i, _} <- m, do: elem(elem(points, i), 2)) |> Enum.max()
  end

  @doc "The speeds of the walk and of the run (`walk_speed`, `run_speed`, m/s), for a body of height `h`."
  def speeds(h, gait) do
    %{
      "walk_speed" => Float.round(stride(h, gait) / (0.6 * period(gait)), 2),
      "run_speed" => Float.round(1.5 * stride(h, gait) / (0.35 * 0.65 * period(gait)), 2)
    }
  end

  @doc "The names of the animations."
  def animations, do: ~w(walk run idle)

  def limbs(_by) do
    for(s <- @sides, do: Limb.new("arm_#{s}", ["upperarm_#{s}", "lowerarm_#{s}"], role: :arm, pole: {0.0, -1.0, 0.0})) ++
      for s <- @sides, do: Limb.new("leg_#{s}", ["thigh_#{s}", "calf_#{s}"], role: :leg, pole: {0.0, 1.0, 0.0})
  end

  def joints(_by) do
    List.flatten(
      for s <- @sides do
        [
          Joint.new("shoulder_#{s}", :ball,
            role: :shoulder,
            bone: "upperarm_#{s}",
            limits: %{flex: {-60, 170}, spread: {-120, 120}, twist: {-60, 60}}
          ),
          Joint.new("elbow_#{s}", :hinge, role: :elbow, bone: "lowerarm_#{s}", limits: {0, 150}),
          Joint.new("hip_#{s}", :ball,
            role: :hip,
            bone: "thigh_#{s}",
            limits: %{flex: {-30, 140}, spread: {-40, 40}, twist: {-30, 30}}
          ),
          Joint.new("knee_#{s}", :hinge, role: :knee, bone: "calf_#{s}", limits: {0, 150})
        ]
      end
    ) ++
      [
        Joint.new("neck", :ball,
          role: :neck,
          bone: "neck_01",
          limits: %{flex: {-60, 60}, spread: {-70, 70}, twist: {-70, 70}}
        )
      ]
  end

  def ports(by) do
    head = by["head"]

    grips =
      for s <- @sides do
        hand = by["hand_#{s}"]
        along = Vec.norm(Vec.sub(hand.tail, hand.head))
        {"grip_#{s}", "hand_#{s}", Part.port("grip_#{s}", Vec.lerp(hand.head, hand.tail, 0.5), {0, 1, 0}, along)}
      end

    [
      {"ground", nil, Part.port("ground", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})},
      {"head", "head", Part.port("head", head.tail, {0, 0, 1}, {0, 1, 0})}
    ] ++ grips
  end

  @doc "An animation of the body plan, for a body of height `h` (m) and the numbers of its gait."
  def animation("walk", skeleton, h, gait) do
    {period, stride, lift} = {period(gait), stride(h, gait), lift(h, gait)}
    %{arms: arms} = sizes(skeleton)

    Rig.clip("walk", skeleton, period, 16, fn t ->
      u = t / period
      # The hand of a side is to the back when the foot of that side is to the front.
      swing = 0.22 * arms * :math.cos(2 * :math.pi() * u)
      steps(skeleton, u, {stride, lift, 0.6}, %{"l" => {0.15, -swing, -0.93}, "r" => {0.15, swing, -0.93}})
    end)
  end

  def animation("run", skeleton, h, gait) do
    {period, stride, lift} = {0.65 * period(gait), 1.5 * stride(h, gait), 2.5 * lift(h, gait)}
    %{arms: arms} = sizes(skeleton)

    Rig.clip("run", skeleton, period, 16, fn t ->
      u = t / period
      swing = 0.3 * arms * :math.cos(2 * :math.pi() * u)

      # The elbows bent: the hands in front of the body, at the height of the waist.
      steps(skeleton, u, {stride, lift, 0.35}, %{
        "l" => {0.1, 0.25 * arms - swing, -0.6},
        "r" => {0.1, 0.25 * arms + swing, -0.6}
      })
      |> Map.update!(:hips, &Map.put(&1, :turn, flex: 8))
    end)
  end

  def animation("idle", skeleton, _h, _gait) do
    %{legs: legs} = sizes(skeleton)

    Rig.clip("idle", skeleton, 3.0, 12, fn t ->
      breath = 0.004 * legs * (1 - :math.cos(2 * :math.pi() * t / 3.0))

      steps(skeleton, 0.3, {0.0, 0.0, 0.6}, %{"l" => {0.15, 0.0, -0.93}, "r" => {0.15, 0.0, -0.93}})
      |> Map.update!(:hips, fn %{at: {x, y, z}} -> %{at: {x, y, z - breath}} end)
    end)
  end

  # The pose at the part `u` of a step: each foot on its path (on the
  # ground for the part `stance` of the step, the right foot half a step
  # after the left one), the hips as high as the two legs let them, and
  # each hand at its place from its shoulder: `{out, front, up}`, with
  # `out` and `up` in lengths of the arm and `front` in meters.
  defp steps(skeleton, u, {stride, lift, stance}, hands) do
    r = skeleton.rest
    %{legs: legs, arms: arms} = sizes(skeleton)

    feet =
      for {s, phase} <- [{"l", 0.0}, {"r", 0.5}],
          do: {s, Animals.foot(:math.fmod(u + phase, 1.0), stride, lift, stance).by}

    # The hips of a body at rest are the highest: they go down from there.
    down = feet |> Enum.map(fn {s, by} -> room(r, s, by, @reach * legs) end) |> Enum.min() |> min(0.0)

    arms =
      for s <- @sides, into: %{} do
        {x, y, z} = r["upperarm_#{s}"].at
        {out, front, up} = hands[s]
        # The left side of a body is at -x; a body with its shoulders on its middle line has the left hand at -x.
        side = if x < 0 or (x == 0 and s == "l"), do: -1.0, else: 1.0

        {{:limb, "arm_#{s}"}, %{at: {x + side * out * arms, y + front, z + down + up * arms}, pole: {0.0, -1.0, 0.0}}}
      end

    feet
    |> Map.new(fn {s, by} -> {{:foot, String.to_atom(s)}, %{by: by, flat: true}} end)
    |> Map.merge(arms)
    |> Map.put(:hips, %{at: {0.0, 0.0, down}})
  end

  # How far up the hips can go when the ankle of a side moves by `by`
  # from its rest: the leg has the length `reach` then.
  defp room(r, s, {_, by, bz}, reach) do
    {ax, ay, az} = Vec.sub(r["thigh_#{s}"].at, r["foot_#{s}"].at)
    bz - az + :math.sqrt(max(reach * reach - ax * ax - (ay - by) * (ay - by), 0.0))
  end

  # The lengths of a leg and of an arm (the mean of the two sides).
  defp sizes(skeleton) do
    r = skeleton.rest

    chain = fn names ->
      names
      |> Enum.map(&r[&1].at)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> Vec.len(Vec.sub(b, a)) end)
      |> Enum.sum()
    end

    mean = fn parts -> Enum.sum(for s <- @sides, do: chain.(Enum.map(parts, &"#{&1}_#{s}"))) / 2 end
    %{legs: mean.(@leg), arms: mean.(@arm)}
  end

  defp period(gait), do: Map.get(gait, "period", 1.1)
  defp stride(h, gait), do: Map.get(gait, "stride", 0.36) * h
  defp lift(h, gait), do: Map.get(gait, "lift", 0.05) * h
end
