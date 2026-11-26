defmodule World.People.Gait do
  @moduledoc """
  The walks and the clip to stand of a person
  (`docs/plans/0021-people-who-move-like-people.md`, D1 to D5, D7): the
  feet lead the legs. A walk is one cycle of two steps in a loop, in
  place (the root does not go forward): a foot on the ground goes back at
  the speed of the walk, so a project that moves the person at that
  speed sees the foot stay at its place.

  - **The feet** (D1, D2): each foot is on the ground 60 % of the cycle
    and in the air 40 %, the right foot half a cycle after the left one.
    On the ground the foot rolls: the heel touches with the toes 12° up,
    and the foot turns round its heel to flat by a tenth of the cycle; the
    heel goes up from 35 % of the cycle, and the foot turns round its
    ball (the toes flat on the ground) to 30°, then round the tip of its
    toes to 50° at the toe-off. In the air the foot goes up from the
    ground first and down to it last, with no move over the ground at
    each end, and the ankle goes up to 5 cm over its line.
  - **The hips** (D1, D2): while the heel of a foot is on the ground,
    its leg carries the hips with the knee bent 4°, and 16° when the leg
    takes the weight: the hips go over the foot as on a stick, highest
    when the foot is under the body and lowest when the two feet are on
    the ground (two times in a cycle). The legs come from the feet
    (`World.People.Skeleton`, two bones to each ankle), and the hips go
    down more where a leg on the ground must reach its foot. The hips go
    2 cm to the side of the foot on the ground, and turn 4° to each side;
    the chest turns against them.
  - **The arms and the head**: the arms hang at the sides and swing
    against the legs (to about 20° to the front and 10° to the back), with
    the elbow bent more in front. The head stays level and looks to the
    front.
  - **The step** (D3, D5): the length of a step comes from the legs (the
    height of the hip): 0.76 of it in a walk, 0.64 in a stroll, at 105
    and 86 steps a minute for a hip of 0.9 m; shorter legs take more
    steps, as a shorter pendulum (80 to 110 steps a minute in all). The
    heel touches 0.44 of a step in front of the hip in a walk, 0.36 in a
    stroll. An old person (over 60) takes shorter and slower steps, and
    bends the back more. The seed changes the step (2 %), the cadence
    (3 %), the swing of the arms (15 %) and the bend of the back (0° to
    4°).
  - **The keys** (D7): 24 each second, with straight lines between them
    (the option `fps`).
  - **The numbers** (D4): `numbers/3`, and the extras of the clip: the
    speed (m/s), the stride (m, two steps), the cadence, and the times of
    the contact of the heel and of the toe-off of each foot (s).

  `idle/2` is the clip to stand (6 s in a loop): the weight goes from one
  foot to the other, the chest moves with the breath (two times), and
  the head turns a little.
  """
  alias World.Vec
  alias World.People.Gait.Vec2
  alias World.People.{Pose, Skeleton}

  @x {1.0, 0.0, 0.0}
  @y {0.0, 1.0, 0.0}
  @fps 24
  @kinds %{"walk" => {0.76, 105, 0.44}, "stroll" => {0.64, 86, 0.36}}
  # The parts of the cycle of a foot (from the contact of its heel): the foot flat, the heel up, the turn round
  # the tip of the toes, the toe-off.
  @flat 0.1
  @heel_off 0.35
  @toe_roll 0.5
  @toe_off 0.6
  # The roll of the foot (degrees): the toes up at the contact of the heel; the heel up when the foot starts to
  # turn round the tip of its toes, and at the toe-off; and the toes up from the ground at the toe-off.
  @toes_up 12.0
  @heel_up 30.0
  @heel_off_up 50.0
  @tip_up 30.0

  @doc "The kinds of walk."
  def kinds, do: @kinds |> Map.keys() |> Enum.sort()

  @doc """
  The numbers of a walk of a person (`kind`: `"walk"` or `"stroll"`), with
  the options `age` (years) and `seed`: the length of a step and of a
  stride (m), the cadence (steps a minute), the speed (m/s), the time of
  a cycle (s), the swing of the arms (a part of 1) and the bend of the
  back (degrees).
  """
  def numbers(%Skeleton{} = s, kind, opts \\ []) do
    {part, cadence, front} = Map.fetch!(@kinds, kind)
    age = Keyword.get(opts, :age, 30)
    [r1, r2, r3, r4] = random(Keyword.get(opts, :seed, 1), kind)
    {_, _, hip} = s.rest["thigh_l"].at
    old = if age > 60, do: min(0.25, (age - 60) * 0.01), else: 0.0
    step = hip * part * (1 - old) * (1 + 0.02 * r1)
    # (Short legs swing faster, as a short pendulum: the cadence goes as one over the root of the height of the
    # hip, from 0.9 m.)
    cadence = min(max(cadence * :math.sqrt(0.9 / hip) * (1 - old / 2) * (1 + 0.03 * r2), 80.0), 110.0)

    {thigh, calf} =
      {Vec.len(Vec.sub(s.rest["calf_l"].at, s.rest["thigh_l"].at)),
       Vec.len(Vec.sub(s.rest["foot_l"].at, s.rest["calf_l"].at))}

    %{
      step: step,
      stride: 2 * step,
      # (The reach of a leg with the knee bent 3°, where the heel touches in front of the hip (a part of a step),
      # and how high the ankle goes over its line in the swing.)
      leg: :math.sqrt(thigh ** 2 + calf ** 2 + 2 * thigh * calf * :math.cos(3 * :math.pi() / 180)),
      front: front,
      lift: 0.05,
      cadence: cadence,
      speed: step * cadence / 60,
      period: 120 / cadence,
      arms: 1 + 0.15 * r3,
      bend: 2 + 2 * r4 + 8 * old
    }
  end

  # Four numbers from -1 to 1 from a seed and a kind.
  defp random(seed, kind) do
    <<a::16, b::16, c::16, d::16, _::binary>> = :crypto.hash(:sha256, "#{seed}/#{kind}")
    for n <- [a, b, c, d], do: n / 32_767.5 - 1
  end

  @doc """
  The clip of a walk (`kind`) for the bones of a person (parents first):
  `%{name, channels, extras}` (`World.People.Pose.animation/3`). The
  options: `age`, `seed`, `hands` (the shape of each hand that holds a
  prop), `fps` (the keys each second).
  """
  def walk(bones, kind, opts \\ []) do
    s = Skeleton.new(bones)
    n = numbers(s, kind, opts)
    keys = round(n.period * Keyword.get(opts, :fps, @fps))
    times = for k <- 0..keys, do: k * n.period / keys
    poses = for k <- 0..keys, do: walk_pose(s, n, rem(k, keys) / keys)
    t = n.period

    %{
      name: kind,
      channels: channels(s, bones, poses, times, Keyword.get(opts, :hands, %{})),
      extras: %{
        "speed" => r3(n.speed),
        "stride" => r3(n.stride),
        "cadence" => r3(n.cadence),
        "contacts" => %{
          "l" => %{"heel" => 0.0, "toe_off" => r3(@toe_off * t)},
          "r" => %{"heel" => r3(0.5 * t), "toe_off" => r3((@toe_off - 0.5) * t)}
        }
      }
    }
  end

  @doc "The clip to stand (6 s in a loop) for the bones of a person: `%{name, channels, extras}`."
  def idle(bones, opts \\ []) do
    s = Skeleton.new(bones)
    length = 6.0
    keys = round(length * Keyword.get(opts, :fps, @fps))
    times = for k <- 0..keys, do: k * length / keys

    poses =
      for t <- times do
        a = 2 * :math.pi() * t / length

        %{
          :hips => %{at: {0.03 * :math.sin(a), 0.0, -0.01}},
          {:foot, :l} => %{},
          {:foot, :r} => %{},
          # (The breath: two in the loop.)
          :spine => [{:flex, 0.8 * :math.sin(2 * a)}],
          :look => {0.1 * :math.sin(a + 1.0), 1.0, -0.02}
        }
      end

    %{name: "idle", channels: channels(s, bones, poses, times, Keyword.get(opts, :hands, %{}))}
  end

  defp channels(s, bones, poses, times, hands) do
    stand = Map.merge(Pose.resolve("stand"), hands)
    base = Skeleton.locals(s, Pose.expand(stand))
    frames = for pose <- poses, do: Skeleton.locals(s, Pose.expand(merge(stand, pose)))
    Pose.channels(bones, base, frames, times)
  end

  # A pose on the stand: the turns of a bone add to its turns in the stand.
  defp merge(stand, pose), do: Map.merge(stand, pose, fn _, a, b -> if is_list(a), do: a ++ b, else: b end)

  # The pose of a walk at a phase of its cycle (0 to 1: the contact of the left heel at 0).
  defp walk_pose(s, n, phase) do
    a = 2 * :math.pi() * phase
    {sway, turn} = body(phase)
    feet = %{l: foot(s, :l, n, own(:l, phase)), r: foot(s, :r, n, own(:r, phase))}
    swing = fn side -> if(side == :l, do: -1, else: 1) * :math.cos(a) end
    arm = fn side -> 6 + 19 * n.arms * swing.(side) end

    %{
      :hips => %{at: {sway, 0.0, -drop(s, n, phase, feet)}, turn: [{:twist, turn}]},
      {:foot, :l} => Map.delete(feet.l, :ground),
      {:foot, :r} => Map.delete(feet.r, :ground),
      :spine => [{:twist, -1.75 * turn}, {:flex, n.bend}],
      :look => {0.0, 1.0, 0.0},
      "upperarm_l" => [{@x, arm.(:l)}],
      "upperarm_r" => [{@x, arm.(:r)}],
      "lowerarm_l" => [{:flex, 12 + 0.4 * (arm.(:l) + 13)}],
      "lowerarm_r" => [{:flex, 12 + 0.4 * (arm.(:r) + 13)}]
    }
  end

  # The phase of a foot in its own cycle: the right foot is half a cycle after the left one.
  defp own(:l, phase), do: phase
  defp own(:r, phase), do: fmod(phase + 0.5)

  defp fmod(p), do: p - Float.floor(p)

  # The hips go to the side of the foot on the ground (2 cm), and turn (4°) to the front on the side of the front
  # foot: `{sway, turn}`.
  defp body(phase), do: {-0.02 * :math.sin(2 * :math.pi() * (phase - 0.05)), -4 * :math.cos(2 * :math.pi() * phase)}

  # How far the hips go down. While the heel of a foot is on the ground, its leg carries the hips, with the knee
  # bent 4°, and 16° when the leg takes the weight (D1); the hips go over the foot as on a stick, so they are
  # highest when the foot is under the body and lowest when the two feet are on the ground. Between, a smooth
  # curve. And at least as far as each leg on the ground must, so that its foot reaches its place (D2).
  defp drop(s, n, phase, feet) do
    {_, _, top} = s.rest["thigh_l"].at
    gap = @toe_roll - @heel_off

    z =
      cond do
        phase <= @heel_off ->
          carry(s, n, :l, phase)

        phase >= 0.5 and phase <= 0.5 + @heel_off ->
          carry(s, n, :r, phase)

        true ->
          # (From the leg that lifts its heel to the leg that puts its heel down.)
          {side, other, from} = if phase < 0.5, do: {:l, :r, @heel_off}, else: {:r, :l, 0.5 + @heel_off}
          to = from + gap
          d = 1.0e-3
          {a, b} = {carry(s, n, side, from), carry(s, n, other, fmod(to))}
          {ma, mb} = {(a - carry(s, n, side, from - d)) / d * gap, (carry(s, n, other, fmod(to) + d) - b) / d * gap}
          hermite(a, b, ma, mb, (phase - from) / gap)
      end

    reach =
      for side <- [:l, :r], feet[side].ground, reduce: 0.0 do
        most -> max(most, top - height(s, side, phase, feet[side].at, n.leg))
      end

    max(top - z, reach)
  end

  # The height of the joint of the hip that the leg of a side gives at a phase of the cycle, with its heel on the
  # ground and its knee bent as the weight asks.
  defp carry(s, n, side, phase) do
    p = own(side, phase)
    knee = 4 + 12 * :math.exp(-(((p - 0.12) / 0.06) ** 2))
    height(s, side, phase, foot(s, side, n, p).at, length(s, knee))
  end

  # The height of the joint of the hip over a point of the ankle, for a leg of a length.
  defp height(s, side, phase, {ax, ay, az}, leg) do
    {sway, turn} = body(phase)
    {x, y, _} = hip(s, side, sway, turn)
    az + :math.sqrt(max(leg ** 2 - (x - ax) ** 2 - (y - ay) ** 2, 0.0))
  end

  # The length from the hip to the ankle of a leg with its knee bent by `knee` degrees.
  defp length(s, knee) do
    thigh = Vec.len(Vec.sub(s.rest["calf_l"].at, s.rest["thigh_l"].at))
    calf = Vec.len(Vec.sub(s.rest["foot_l"].at, s.rest["calf_l"].at))
    :math.sqrt(thigh ** 2 + calf ** 2 + 2 * thigh * calf * :math.cos(knee * :math.pi() / 180))
  end

  # The joint of a hip after the sway and the turn of the hips.
  defp hip(s, side, sway, turn) do
    {px, py, _} = s.rest["pelvis"].at
    {x, y, z} = s.rest["thigh_#{side}"].at
    r = turn * :math.pi() / 180
    {dx, dy} = {x - px, y - py}
    {px + dx * :math.cos(r) - dy * :math.sin(r) + sway, py + dx * :math.sin(r) + dy * :math.cos(r), z}
  end

  # The target of a foot at a phase of its own cycle (0: the contact of its heel): its ankle, the pitch of its
  # sole, and the bend of its toes. A point of the foot on the ground goes back at the speed of the walk.
  defp foot(s, side, n, phase) do
    {ax, ay, az} = s.rest["foot_#{side}"].at
    {_, by, bz} = s.rest["ball_#{side}"].at
    {_, ty, _} = Skeleton.tip(s, s.rest, "ball_#{side}")
    {_, hy, _} = s.rest["thigh_#{side}"].at
    {heel, ball, toes} = {0.06, by - ay, ty - by}
    # (The ankle of the flat foot in the stance: its heel `n.front` of a step in front of the hip at the contact.)
    flat_y = fn p -> hy + n.front * n.step + heel - n.stride * p end
    # (The foot turns round the tip of its toes: the point of the toes on the ground stays where the turn round
    # the ball put it, and the toes go up from the ground by `q`; the ankle from the joint of the toes.)
    tip = fn p, pitch, q ->
      {jy, jz} = turn(flat_y.(p) + ball, 0.0, bz, 0.0, @heel_up)
      {py, pz} = Vec2.add({jy, jz}, {toes, -bz})
      {jy, jz} = Vec2.sub({py, pz}, rot({toes, -bz}, q))
      Vec2.add({jy, jz}, rot({-ball, az - bz}, pitch))
    end

    {y, z, pitch, bend, ground} =
      cond do
        phase < @flat ->
          # (The foot turns round its heel, from the toes up to flat.)
          p = -@toes_up * (1 - smooth(phase / @flat))
          {y, z} = turn(flat_y.(phase) - heel, 0.0, az, -heel, p)
          {y, z, p, 0.0, true}

        phase < @heel_off ->
          {flat_y.(phase), az, 0.0, 0.0, true}

        phase < @toe_roll ->
          # (The heel goes up: the foot turns round its ball, and the toes stay flat on the ground.)
          p = @heel_up * smooth((phase - @heel_off) / (@toe_roll - @heel_off))
          {y, z} = turn(flat_y.(phase) + ball, 0.0, az, ball, p)
          {y, z, p, p, true}

        phase < @toe_off ->
          # (The foot turns round the tip of its toes.)
          u = smooth((phase - @toe_roll) / (@toe_off - @toe_roll))
          {p, q} = {@heel_up + (@heel_off_up - @heel_up) * u, @tip_up * u}
          {y, z} = tip.(phase, p, q)
          {y, z, p, p - q, true}

        true ->
          # (In the air: from the toe-off to the next contact. The foot goes up from the ground first, and goes
          # down to it last, with no move over the ground at each end.)
          u = (phase - @toe_off) / (1 - @toe_off)
          {y0, z0} = tip.(@toe_off, @heel_off_up, @tip_up)
          {y1, z1} = turn(flat_y.(0.0) - heel, 0.0, az, -heel, -@toes_up)
          back = n.speed * (1 - @toe_off) * n.period
          w = smooth(min(max((u - 0.06) / 0.86, 0.0), 1.0))
          y = y0 - back * u + (y1 - y0 + back) * w
          z = z0 + (z1 - z0) * smooth(u) + n.lift * :math.sin(:math.pi() * u) * (1 - 0.3 * u)
          p = @heel_off_up + (-@toes_up - @heel_off_up) * smooth(u)
          {y, z, p, (@heel_off_up - @tip_up) * (1 - smooth(min(u / 0.5, 1.0))), false}
      end

    %{at: {ax, y, z}, pitch: pitch, toes: bend, pole: @y, flat: true, ground: ground}
  end

  # The ankle of a foot that turns round a point of its sole (at `y` and `z`; at rest `back` along the foot from
  # the ankle, and `az` under it), by a pitch (degrees; the heel up for more than 0): `{y, z}` of the ankle.
  defp turn(y, z, az, back, pitch), do: Vec2.add({y, z}, rot({-back, az}, pitch))

  # A move in y and z of a point of a foot, turned with the foot by a pitch (degrees; the heel up for more than 0).
  defp rot({dy, dz}, pitch) do
    r = pitch * :math.pi() / 180
    {dy * :math.cos(r) + dz * :math.sin(r), -dy * :math.sin(r) + dz * :math.cos(r)}
  end

  defp smooth(u), do: u * u * (3 - 2 * u)

  # A cubic of Hermite: from `a` to `b`, with the slopes `ma` and `mb` (for u from 0 to 1).
  defp hermite(a, b, ma, mb, u) do
    {u2, u3} = {u * u, u * u * u}
    (2 * u3 - 3 * u2 + 1) * a + (u3 - 2 * u2 + u) * ma + (-2 * u3 + 3 * u2) * b + (u3 - u2) * mb
  end

  defp r3(v), do: Float.round(v / 1, 3)
end

defmodule World.People.Gait.Vec2 do
  @moduledoc false
  def add({a, b}, {c, d}), do: {a + c, b + d}
  def sub({a, b}, {c, d}), do: {a - c, b - d}
end
