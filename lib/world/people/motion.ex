defmodule World.People.Motion do
  @moduledoc """
  The measures of a clip of a person (`docs/plans/0021-people-who-move-like-people.md`,
  D8): the places of the feet, of the hips and of the head at each key,
  and the angles of the hips, the knees and the arms, on the skeleton of
  the person (`World.People.Skeleton`).

  Three points of each foot touch the ground: the heel (6 cm behind the
  ankle), the ball (under the joint of the toes) and the tip of the toes,
  each at its place on the ground at rest. A clip in place (a walk: the
  root does not go forward) has a `speed`: a person who walks moves
  forward (+y) at that speed, so a foot on the ground stays at its place
  when the clip goes back by the speed.

  `faults/3` gives what is not right in a clip, by the checks of D8:

  - `ground`: at each key, a foot is on the ground (its lowest point
    within 1 cm of it), and no point is more than 1 cm under it; with
    `air`, the times when the feet can be in the air (a jump);
  - `slide`: a point of a foot on the ground (within 1 cm of it) moves
    at most 1 cm while it is there;
  - `loop`: the first and the last key are the same;
  - with `walk: :walk`, the limits of a walk (D1): the hips go up and down
    3 cm to 7 cm and to the sides 2 cm to 6 cm; the hip bends to the
    front 20° to 40° and goes back 8° to 22°; the knee bends 3° to 25°
    when the heel of its foot is on the ground (the leg takes the weight)
    and 50° to 70° when the foot is in the air; the arm
    swings 10° to 30° to the front and 3° to 18° to the back, at most 15°
    out from the side; the head turns at most 5° from level. With `walk:
    :slow` (a stroll), the hips go up and down 1.5 cm to 7 cm, and the hip
    goes back 5° to 22°: shorter steps.
  """
  alias World.{Frame, Vec}
  alias World.People.{Pose, Skeleton}

  @sides [:l, :r]
  # The limits of a walk (D1, at about 1.2 m/s), and of a slow walk (about 0.8 m/s): its steps are shorter, so the
  # hips go up and down less and the hip goes back less (2.7 cm at 0.7 m/s, Orendurff and others, 2004).
  @walk %{
    up: {0.03, 0.07},
    side: {0.02, 0.06},
    front: {20, 40},
    back: {8, 22},
    stance: {3, 25},
    swing: {50, 70},
    arm_front: {10, 30},
    arm_back: {3, 18},
    out: 15,
    head: 5
  }
  @limits %{walk: @walk, slow: %{@walk | up: {0.015, 0.07}, back: {5, 22}}}

  @doc "The frames of each bone in the axes of the person at each key of a clip: `[{time, frames}]`."
  def frames(%Skeleton{} = s, %{channels: channels}) do
    # (A clip with no channel is the stand: one key.)
    times = if channels == [], do: [0.0], else: hd(channels).times

    base = Skeleton.locals(s, Pose.expand(Pose.resolve("stand")))
    names = s.bones |> Enum.with_index(1) |> Map.new(fn {b, i} -> {i, b.name} end)
    columns = Enum.map(channels, fn c -> {c, List.to_tuple(c.values)} end)

    for {t, k} <- Enum.with_index(times) do
      locals =
        Enum.reduce(columns, base, fn
          {%{node: i, path: :rotation}, values}, acc -> Map.put(acc, names[i], elem(values, k))
          {%{node: i, path: :translation}, values}, acc -> Map.update!(acc, names[i], &%{&1 | at: elem(values, k)})
        end)

      {t, Skeleton.world(s, locals)}
    end
  end

  @doc """
  The three points of each foot that touch the ground: `%{side =>
  [{name, {bone, point}}]}`, each point in the axes of its bone.
  """
  def points(%Skeleton{} = s) do
    for side <- @sides, into: %{} do
      {foot, ball} = {"foot_#{side}", "ball_#{side}"}
      {ax, ay, _} = s.rest[foot].at
      {bx, by, _} = s.rest[ball].at
      {tx, ty, _} = Frame.point(s.rest[ball], s.tails[ball])
      back = Vec.scale(Vec.norm({bx - ax, by - ay, 0.0}), 0.06)
      local = fn bone, p -> Frame.point(Frame.invert(s.rest[bone]), p) end

      {side,
       [
         heel: {foot, local.(foot, Vec.sub({ax, ay, 0.0}, back))},
         ball: {foot, local.(foot, {bx, by, 0.0})},
         toe: {ball, local.(ball, {tx, ty, 0.0})}
       ]}
    end
  end

  @doc """
  The measures of a clip: at each key, the places of the points of the
  feet (`feet`: side to name to point, with the move of the person at
  `speed`), of the hips (`hips`) and the angles (`thigh`, `knee`, `arm`
  and `out` of each side, `head`). The angles of the thighs and the arms
  (to the front for more than 0) are from their angles in the pose
  "stand".
  """
  def measure(%Skeleton{} = s, clip, opts \\ []) do
    speed = Keyword.get(opts, :speed, 0.0)
    pts = points(s)
    # (The angles of the hips and the arms from their angles in the stand.)
    stand = Skeleton.world(s, Skeleton.locals(s, Pose.expand(Pose.resolve("stand"))))
    zero = fn name -> front(bone(s, stand, name)) end

    for {t, w} <- frames(s, clip) do
      forward = {0.0, speed * t, 0.0}

      %{
        t: t,
        feet:
          Map.new(pts, fn {side, list} ->
            {side, Map.new(list, fn {n, {b, p}} -> {n, Vec.add(Frame.point(w[b], p), forward)} end)}
          end),
        hips: w["pelvis"].at,
        thigh: Map.new(@sides, &{&1, front(bone(s, w, "thigh_#{&1}")) - zero.("thigh_#{&1}")}),
        knee: Map.new(@sides, &{&1, Skeleton.flex(s, w, "calf_#{&1}")}),
        arm: Map.new(@sides, &{&1, front(bone(s, w, "upperarm_#{&1}")) - zero.("upperarm_#{&1}")}),
        out: Map.new(@sides, &{&1, out(bone(s, w, "upperarm_#{&1}"))}),
        head: tilt(bone(s, w, "head")),
        world: w
      }
    end
  end

  # The direction of a bone from its head to its tail.
  defp bone(s, w, name), do: Vec.sub(Skeleton.tip(s, w, name), w[name].at)

  # The angle of a bone that points down to the front (+y), in degrees: 0 straight down.
  defp front({_, y, z}), do: :math.atan2(y, -z) * 180 / :math.pi()
  # The angle of a bone that points down out to the side, in degrees.
  defp out({x, _, z}), do: :math.atan2(abs(x), -z) * 180 / :math.pi()
  # The angle of a bone that points up from the vertical, in degrees.
  defp tilt(d), do: :math.acos(min(max(elem(Vec.norm(d), 2), -1.0), 1.0)) * 180 / :math.pi()

  @doc """
  What is not right in a clip (the checks of D8): a list of `{check,
  message}`. The options: `speed` (m/s), `air` (a list of `{from, to}`
  in seconds when the feet can be in the air), `walk` (`:walk` or `:slow`:
  the limits of a walk).
  """
  def faults(%Skeleton{} = s, clip, opts \\ []) do
    keys = measure(s, clip, opts)
    air = Keyword.get(opts, :air, [])
    on = fn t -> not Enum.any?(air, fn {a, b} -> t >= a and t <= b end) end
    lows = for k <- keys, do: {k.t, Enum.min(for {_, ps} <- k.feet, {_, {_, _, z}} <- ps, do: z)}
    high = for {t, z} <- lows, on.(t), do: z
    under = Enum.min(Enum.map(lows, &elem(&1, 1)))

    ground =
      cond do
        high != [] and Enum.max(high) > 0.01 -> [{:ground, "the feet are #{cm(Enum.max(high))} over the ground"}]
        under < -0.01 -> [{:ground, "a foot is #{cm(-under)} under the ground"}]
        true -> []
      end

    slide = slide(keys)
    slides = if slide > 0.01, do: [{:slide, "a foot on the ground moves #{cm(slide)}"}], else: []

    loop =
      if same?(hd(keys).world, List.last(keys).world),
        do: [],
        else: [{:loop, "the first and the last key are not the same"}]

    ground ++ slides ++ loop ++ if(opts[:walk], do: walk(keys, Map.fetch!(@limits, opts[:walk])), else: [])
  end

  # The most move of a point of a foot while it is on the ground (within 1 cm of it), in each stretch of time
  # when it is there.
  defp slide(keys) do
    for side <- @sides, name <- [:heel, :ball, :toe], reduce: 0.0 do
      most ->
        keys
        |> Enum.map(& &1.feet[side][name])
        |> Enum.chunk_by(fn {_, _, z} -> z <= 0.01 end)
        |> Enum.filter(fn [{_, _, z} | _] -> z <= 0.01 end)
        |> Enum.reduce(most, fn run, most ->
          max(
            most,
            Enum.max(for {x1, y1, _} <- run, {x2, y2, _} <- run, do: :math.sqrt((x1 - x2) ** 2 + (y1 - y2) ** 2))
          )
        end)
    end
  end

  # (Two frames are the same within 1 mm and about 0.06 degrees.)
  defp same?(a, b) do
    Enum.all?(a, fn {name, f} ->
      g = b[name]
      Enum.all?([{f.at, g.at}, {f.x, g.x}, {f.y, g.y}, {f.z, g.z}], fn {u, v} -> Vec.len(Vec.sub(u, v)) <= 1.0e-3 end)
    end)
  end

  # The limits of a walk (D1).
  defp walk(keys, l) do
    range = fn list -> Enum.max(list) - Enum.min(list) end
    within = fn v, {a, b} -> v >= a and v <= b end
    hips = Enum.map(keys, & &1.hips)
    {up, side} = {range.(Enum.map(hips, &elem(&1, 2))), range.(Enum.map(hips, &elem(&1, 0)))}
    thigh = for k <- keys, s <- @sides, do: k.thigh[s]
    arm = for k <- keys, s <- @sides, do: k.arm[s]
    contact = fn k, s -> Enum.min(for {_, {_, _, z}} <- k.feet[s], do: z) <= 0.01 end
    stance = for k <- keys, s <- @sides, elem(k.feet[s].heel, 2) <= 0.01, do: k.knee[s]
    swing = for k <- keys, s <- @sides, not contact.(k, s), do: k.knee[s]
    out = Enum.max(for k <- keys, s <- @sides, do: k.out[s])
    head = range.(Enum.map(keys, & &1.head))

    [
      {:hips, "the hips go up and down #{cm(up)}", within.(up, l.up)},
      {:hips, "the hips go to the sides #{cm(side)}", within.(side, l.side)},
      {:hip, "the hip bends #{deg(Enum.max(thigh))} to the front", within.(Enum.max(thigh), l.front)},
      {:hip, "the hip goes #{deg(-Enum.min(thigh))} back", within.(-Enum.min(thigh), l.back)},
      {:knee, "the knee bends #{deg(Enum.max([0.0 | stance]))} with the heel on the ground",
       stance != [] and within.(Enum.max(stance), l.stance)},
      {:knee, "the knee bends #{deg(Enum.max([0.0 | swing]))} in the swing",
       swing != [] and within.(Enum.max(swing), l.swing)},
      {:arm, "the arm swings #{deg(Enum.max(arm))} to the front", within.(Enum.max(arm), l.arm_front)},
      {:arm, "the arm swings #{deg(-Enum.min(arm))} to the back", within.(-Enum.min(arm), l.arm_back)},
      {:arm, "the arm is #{deg(out)} out from the side", out <= l.out},
      {:head, "the head turns #{deg(head)} from level", head <= l.head}
    ]
    |> Enum.reject(&elem(&1, 2))
    |> Enum.map(fn {check, message, _} -> {check, message} end)
  end

  defp cm(m), do: "#{Float.round(m * 100, 1)} cm"
  defp deg(d), do: "#{Float.round(d / 1, 1)}°"
end
