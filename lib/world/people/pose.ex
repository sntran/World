defmodule World.People.Pose do
  @moduledoc """
  Poses and animations of a person. A pose is a pose of
  `World.People.Skeleton`: a map of a bone to a list of turns (the flex,
  the spread and the twist of its joint, or a turn around an axis of
  World), an aim of an arm, a look of the face, and here also the shape
  of a hand (`{:hand, side}` to a name of `hands/0`). `mirror/1` makes
  the pose of the other side.

  The named poses: `"stand"` (the arms down at the sides), `"sit"` (on a
  chair or a stool), `"ride"` (on a scooter or a motorbike: the hands
  forward on the bars), `"ride_bicycle"`, `"drive"` (in the seat of a
  car or a van: the hands forward on the wheel). The named animations: `"walk"`
  (one step of each leg in 1.1 s, in a loop); `"wave"` (the right hand
  goes up and waves three times, in 2.6 s, once); `"point"` (an excited
  point: the left arm goes up fast to the left side of the person, with
  the index finger out and the other fingers in the fist, and jabs three
  times; the body leans there and the head looks there; in 2.6 s, once).
  The routines of a morning of exercise (`routines/0`, `routine/1`):
  `"tai_chi"`, `"yoga"` and `"aerobics"`, in a loop, with the options
  `delay` (seconds late) and `mirror` (the leader who faces the group).
  A clip blends each bone from the pose "stand" to the pose of the clip
  on the shortest arc; a clip that plays once starts and stops in the
  pose "stand".
  """
  alias World.{Frame, Vec}
  alias World.People.Skeleton

  @x {1.0, 0.0, 0.0}
  @y {0.0, 1.0, 0.0}
  @z {0.0, 0.0, 1.0}

  @arms_down %{"upperarm_l" => [{@y, -38}], "upperarm_r" => [{@y, 38}]}

  @poses %{
    "rest" => %{},
    "stand" => @arms_down,
    "sit" =>
      Map.merge(@arms_down, %{
        "thigh_l" => [{@x, 88}],
        "thigh_r" => [{@x, 88}],
        "calf_l" => [{@x, -88}],
        "calf_r" => [{@x, -88}],
        "lowerarm_l" => [{@x, 35}],
        "lowerarm_r" => [{@x, 35}]
      }),
    "ride" => %{
      "spine_01" => [{@x, -8}],
      "thigh_l" => [{@x, 78}, {@y, -6}],
      "thigh_r" => [{@x, 78}, {@y, 6}],
      "calf_l" => [{@x, -62}],
      "calf_r" => [{@x, -62}],
      "foot_l" => [{@x, -12}],
      "foot_r" => [{@x, -12}],
      # The hands on the grips of the Honda Vision (a fit of the turns).
      "upperarm_l" => [{@y, -50}, {@x, 48}, {@z, -25}],
      "upperarm_r" => [{@y, 50}, {@x, 48}, {@z, 25}],
      "lowerarm_l" => [{@x, -12}],
      "lowerarm_r" => [{@x, -12}]
    },
    # The legs go forward to the pedals, under the dashboard, not down to
    # the floor.
    "drive" => %{
      "thigh_l" => [{@x, 85}],
      "thigh_r" => [{@x, 85}],
      "calf_l" => [{@x, -45}],
      "calf_r" => [{@x, -45}],
      "upperarm_l" => [{@y, -45}, {@x, 45}, {@z, -20}],
      "upperarm_r" => [{@y, 45}, {@x, 45}, {@z, 20}],
      "lowerarm_l" => [{@x, -25}],
      "lowerarm_r" => [{@x, -25}]
    },
    "ride_bicycle" => %{
      "spine_01" => [{@x, -40}],
      "thigh_l" => [{@x, 70}],
      "thigh_r" => [{@x, 40}],
      "calf_l" => [{@x, -85}],
      "calf_r" => [{@x, -45}],
      "upperarm_l" => [{@y, -30}, {@x, 35}],
      "upperarm_r" => [{@y, 30}, {@x, 35}],
      "lowerarm_l" => [{@x, 10}],
      "lowerarm_r" => [{@x, 10}]
    }
  }

  @doc "The names of the poses."
  def names, do: Map.keys(@poses) |> Enum.sort()

  @doc "A pose: a map is a pose; a name is a named pose."
  def resolve(pose) when is_map(pose), do: pose
  def resolve(name) when is_map_key(@poses, name), do: @poses[name]
  def resolve(name), do: raise(ArgumentError, "unknown pose #{inspect(name)}")

  # The shapes of a hand: the flex of the three joints of each finger
  # (from straight), of the index finger when it has its own, and of the
  # two last joints of the thumb.
  @hands %{
    "relaxed" => %{fingers: {25, 20, 8}, thumb: {15, 10}},
    "open" => %{fingers: {0, 0, 0}, thumb: {0, 0}},
    "fist" => %{fingers: {85, 100, 70}, thumb: {60, 45}},
    "point" => %{fingers: {85, 100, 70}, index: {0, 0, 0}, thumb: {60, 45}},
    "thumbs_up" => %{fingers: {85, 100, 70}, thumb: {-10, 0}},
    "grip" => %{fingers: {70, 80, 45}, thumb: {40, 30}}
  }

  # The routines of a morning of exercise (`routine/1`).
  @routines ~w(aerobics tai_chi yoga)

  @doc "The names of the routines: animations in a loop."
  def routines, do: @routines

  @doc "The names of the shapes of a hand."
  def hands, do: Map.keys(@hands) |> Enum.sort()

  @doc """
  The turns of the fingers of a hand (`:l` or `:r`) in a shape of
  `hands/0`, as a pose.
  """
  def hand(side, shape) when is_map_key(@hands, shape) do
    %{fingers: {a, b, c}, thumb: {t2, t3}} = h = @hands[shape]

    fingers =
      for f <- ~w(index middle ring pinky),
          {d1, d2, d3} = if(f == "index", do: Map.get(h, :index, {a, b, c}), else: {a, b, c}),
          {n, deg} <- [{"01", d1}, {"02", d2}, {"03", d3}],
          do: {"#{f}_#{n}_#{side}", [flex: deg]}

    Map.new(fingers ++ [{"thumb_02_#{side}", [flex: t2]}, {"thumb_03_#{side}", [flex: t3]}])
  end

  def hand(_side, shape), do: raise(ArgumentError, "unknown hand #{inspect(shape)}")

  @doc """
  A pose for `World.People.Skeleton`: each `{:hand, side}` becomes the
  turns of its fingers (`hand/2`), before the other turns of the bone.
  """
  def expand(pose) do
    Enum.reduce(pose, %{}, fn
      {{:hand, side}, shape}, acc -> Map.merge(hand(side, shape), acc, fn _, a, b -> a ++ b end)
      {key, value}, acc -> Map.update(acc, key, value, &(&1 ++ value))
    end)
  end

  @doc """
  The mirror of a pose: the left side becomes the right side. A turn
  around an axis of World mirrors its axis; `flex`, `spread` and `twist`
  stay (the skeleton mirrors them).
  """
  def mirror(pose) do
    Map.new(pose, fn
      {{kind, side}, value} when kind in [:aim, :hand, :reach, :foot] -> {{kind, other(side)}, mirror_value(value)}
      {:look, dir} -> {:look, flip(dir)}
      {:spine, turns} -> {:spine, Enum.map(turns, &mirror_body/1)}
      {:hips, spec} -> {:hips, Map.new(spec, &mirror_hips/1)}
      {bone, turns} -> {swap(bone), Enum.map(turns, &mirror_turn/1)}
    end)
  end

  # A pose of the left side, and the same pose of the right side.
  defp sym(pose), do: Map.merge(pose, mirror(pose))

  defp mirror_hips({:turn, turns}), do: {:turn, Enum.map(turns, &mirror_body/1)}
  defp mirror_hips({key, move}), do: {key, flip(move)}

  # A bend of the body to the front stays; a bend to the side and a turn
  # go the other way.
  defp mirror_body({:flex, deg}), do: {:flex, deg}
  defp mirror_body({kind, deg}), do: {kind, -deg}

  defp other(:l), do: :r
  defp other(:r), do: :l

  defp swap(bone) do
    cond do
      String.ends_with?(bone, "_l") -> String.replace_suffix(bone, "_l", "_r")
      String.ends_with?(bone, "_r") -> String.replace_suffix(bone, "_r", "_l")
      true -> bone
    end
  end

  defp mirror_value(%{} = aim), do: Map.new(aim, fn {k, v} -> {k, if(is_tuple(v), do: flip(v), else: v)} end)
  defp mirror_value(shape), do: shape

  # A direction in the mirror.
  defp flip({x, y, z}), do: {-x, y, z}

  # A turn in the mirror: its axis is a direction of turn (the mirror
  # keeps x, and changes the sign of y and z).
  defp mirror_turn({{x, y, z}, deg}), do: {{x, -y, -z}, deg}
  defp mirror_turn(turn), do: turn

  @doc """
  An animation by its name (or a routine of the caller, `{name, {length,
  fps, keys}}` as `routine/1`), for the bones of a person (parents first,
  as `World.People.Human` makes them): the channels of the rotations of the
  bones that move, with the indices of the nodes of the figure (bone i is
  node i + 1).
  """
  def animation(name, bones, opts \\ [])
  def animation("walk", bones, opts), do: clip("walk", bones, 1.1, 12, &{walk_turns(&1 / 1.1), 1.0}, hands(opts))
  def animation("wave", bones, opts), do: clip("wave", bones, 2.6, 39, &wave/1, hands(opts))
  def animation("point", bones, opts), do: clip("point", bones, 2.6, 39, &point/1, hands(opts))

  def animation(name, bones, opts) when name in @routines, do: animation({name, routine(name)}, bones, opts)

  # A routine of the caller: `{name, {length, fps, keys}}` as `routine/1`.
  def animation({name, {length, fps, keys}}, bones, opts) do
    keys = if Keyword.get(opts, :mirror, false), do: for({t, pose} <- keys, do: {t, mirror(pose)}), else: keys
    loop(name, bones, length, fps, keys, Keyword.get(opts, :delay, 0.0), hands(opts))
  end

  def animation(name, _bones, _opts), do: raise(ArgumentError, "unknown animation #{inspect(name)}")

  # The hands that hold a prop keep their shape in all the animation:
  # the option `hands` is a map of a side to a shape.
  defp hands(opts), do: Map.new(Keyword.get(opts, :hands, %{}), fn {side, shape} -> {{:hand, side}, shape} end)

  # A clip of `steps` frames in `length` seconds. At each time, `at` gives
  # a pose (on top of the pose "stand") and how far the person is in it,
  # from 0 (the pose "stand") to 1: each bone turns on the shortest arc.
  # The channels are the bones that move.
  defp clip(name, bones, length, steps, at, hands) do
    skeleton = Skeleton.new(bones)
    stand = Map.merge(@poses["stand"], hands)
    base = Skeleton.locals(skeleton, expand(stand))
    times = for k <- 0..steps, do: k * length / steps

    frames =
      for t <- times do
        {pose, k} = at.(t)
        target = Skeleton.locals(skeleton, expand(stand |> Map.merge(pose) |> Map.merge(hands)))
        Map.new(target, fn {bone, f} -> {bone, Frame.blend(base[bone], f, k)} end)
      end

    %{name: name, channels: channels(bones, base, frames, times)}
  end

  # The channels of the bones that move: their turns, and the moves of the
  # bones that move (the hips).
  defp channels(bones, base, frames, times) do
    for {b, i} <- Enum.with_index(bones, 1),
        values = Enum.map(frames, & &1[b.name]),
        {path, values, moved?} <- [
          {:rotation, values, &turned?(&1, base[b.name])},
          {:translation, Enum.map(values, & &1.at), &(Vec.len(Vec.sub(&1, base[b.name].at)) > 1.0e-6)}
        ],
        Enum.any?(values, moved?) do
      %{node: i, path: path, times: times, values: values}
    end
  end

  defp turned?(a, b),
    do: Enum.any?([{a.x, b.x}, {a.y, b.y}, {a.z, b.z}], fn {u, v} -> Vec.len(Vec.sub(u, v)) > 1.0e-6 end)

  # A routine in a loop: its poses at their times (on top of the pose
  # "stand"), with a smooth move from each pose to the next, and from the
  # last to the first. The feet stay on their targets during each move,
  # and a foot that goes to a new place lifts on the way. A person late
  # by `delay` seconds is at the time `t - delay` of the routine.
  defp loop(name, bones, length, fps, keys, delay, hands) do
    skeleton = Skeleton.new(bones)
    stand = Map.merge(@poses["stand"], hands)

    solved =
      for {t, pose} <- keys ++ [{length, elem(hd(keys), 1)}] do
        pose = expand(stand |> Map.merge(pose) |> Map.merge(hands))
        {t, Skeleton.locals(skeleton, pose), Skeleton.feet(skeleton, pose)}
      end

    steps = round(length * fps)
    times = for k <- 0..steps, do: k * length / steps
    frames = for t <- times, do: sample(skeleton, solved, fmod(t - delay, length))
    %{name: name, channels: channels(bones, Skeleton.locals(skeleton, expand(stand)), frames, times)}
  end

  defp fmod(t, length), do: t - Float.floor(t / length) * length

  defp sample(skeleton, solved, u) do
    [{t0, l0, f0}, {t1, l1, f1}] =
      solved |> Enum.chunk_every(2, 1, :discard) |> Enum.find(fn [{t0, _, _}, {t1, _, _}] -> u >= t0 and u <= t1 end)

    k = (u - t0) / (t1 - t0)
    k = k * k * (3 - 2 * k)
    frames = Map.new(l0, fn {bone, f} -> {bone, Frame.blend(f, l1[bone], k)} end)
    Skeleton.place_feet(frames, skeleton, Map.new([:l, :r], &{&1, step(f0[&1], f1[&1], k)}))
  end

  # The target of a foot on the way from one place to the next: a foot
  # that moves more than 3 cm lifts on an arc (at most 12 cm high).
  defp step(nil, _b, _k), do: nil
  defp step(_a, nil, _k), do: nil

  defp step(a, b, k) do
    far = Vec.len(Vec.sub(b.at, a.at))
    lift = if far > 0.03, do: min(0.12, far / 2) * :math.sin(:math.pi() * k), else: 0.0

    %{
      at: Vec.add(Vec.lerp(a.at, b.at, k), {0.0, 0.0, lift}),
      pole: Vec.norm(Vec.lerp(a.pole, b.pole, k)),
      flat: a.flat and b.flat,
      toe: a.toe + (b.toe - a.toe) * k
    }
  end

  # How far a clip that plays once is in its move, from 0 (the pose
  # "stand") to 1: up from 0 to `up` s, down from `down` s to `stop` s, with
  # a smooth start and a smooth stop.
  defp lift(t, up, down, stop) do
    k = min(1.0, t / up) |> min((stop - t) / (stop - down)) |> max(0.0)
    k * k * (3 - 2 * k)
  end

  # The turns of a walk at a phase from 0 to 1: the legs swing in turn,
  # the knee bends after the leg goes back, the arms swing against the
  # legs.
  defp walk_turns(phase) do
    a = 2 * :math.pi() * phase
    s = :math.sin(a)
    knee = fn p -> -45 * max(0.0, :math.sin(a + p)) end

    %{
      "thigh_l" => [{@x, 24 * s}],
      "thigh_r" => [{@x, -24 * s}],
      "calf_l" => [{@x, knee.(-:math.pi() / 2)}],
      "calf_r" => [{@x, knee.(:math.pi() / 2)}],
      "upperarm_l" => [{@y, -38}, {@x, -18 * s}],
      "upperarm_r" => [{@y, 38}, {@x, 18 * s}],
      "lowerarm_l" => [{@x, 12}],
      "lowerarm_r" => [{@x, 12}]
    }
  end

  # A wave of the right hand: the upper arm goes out to the side and a
  # little up, the elbow bends, and the forearm swings from side to side
  # three times around the upper arm, as a person waves. The hand is open.
  defp wave(t) do
    sway = 0.5 * :math.sin(2 * :math.pi() * 3 * max(0.0, t - 0.45) / 1.65)

    {%{
       {:aim, :r} => %{to: {0.92, 0.12, 0.36}, end: :elbow, pole: {sway, 0.2, 1.0}},
       "lowerarm_r" => [flex: 95],
       {:hand, :r} => "open",
       "head" => [{@y, 8}]
     }, lift(t, 0.45, 2.1, 2.6)}
  end

  # An excited point: the left arm goes up fast, straight, to the left
  # side of the person, a little forward and up, with the index finger
  # out. The forearm jabs three times (the wrist stays on the line), the
  # body leans and turns there, and the face looks there.
  defp point(t) do
    jab = if t > 0.35 and t < 1.85, do: 35 * (1 - :math.cos(2 * :math.pi() * 3 * (t - 0.35) / 1.5)) / 2, else: 0.0

    {%{
       {:aim, :l} => %{to: {-0.85, 0.35, 0.4}, pole: {0.0, -0.3, -1.0}},
       "lowerarm_l" => [flex: jab],
       "hand_l" => [flex: 0],
       {:hand, :l} => "point",
       "spine_02" => [{@y, -7}, {@z, 12}],
       :look => {-0.75, 0.6, 0.15}
     }, lift(t, 0.3, 2.1, 2.6)}
  end

  @doc """
  A routine: `{length, frames per second, [{time, pose}]}`, the poses at
  their times in seconds, in a loop. The person faces the front (+y).

  - `"tai_chi"` (16 s): the opening of tai chi, slow, on bent knees: the
    arms rise and sink, then "wave hands like clouds" to the left and to
    the right, with the weight from one leg to the other and the waist
    turning.
  - `"yoga"` (24 s): mountain with the hands together at the chest, the
    arms up, a forward fold, the tree on the left leg, then warrior II to
    the left.
  - `"aerobics"` (8 s, 120 beats a minute): a march with the knees up
    and the arms pumping, jumping jacks, steps to the side with punches,
    and knee lifts with a clap.
  """
  def routine("tai_chi") do
    stance = sym(%{{:foot, :l} => %{by: {-0.08, 0.0, 0.0}, toe: 10}, {:hand, :l} => "relaxed"})
    at = fn z, more -> Map.merge(stance, Map.merge(%{:hips => %{at: {0.0, 0.0, z}}}, more)) end
    # The forearms turn the palms down (+70).
    arms = fn to, flex, wrist ->
      sym(%{
        {:aim, :l} => %{to: to, pole: {0.0, -0.3, -1.0}},
        "lowerarm_l" => [flex: flex, twist: 70],
        "hand_l" => [flex: wrist]
      })
    end

    clouds =
      Map.merge(stance, %{
        :hips => %{at: {-0.06, 0.0, -0.13}, turn: [twist: 15]},
        :spine => [twist: 10],
        {:reach, :l} => %{by: {0.15, 0.38, 0.0}},
        "lowerarm_l" => [twist: -30],
        {:reach, :r} => %{by: {-0.15, 0.28, -0.35}},
        "lowerarm_r" => [twist: -60],
        :look => {-0.45, 1.0, 0.05}
      })

    {16.0, 10,
     [
       {0.0, at.(-0.03, %{})},
       {2.5, at.(-0.06, arms.({-0.3, 1.0, 0.0}, 20, 10))},
       {5.0, at.(-0.14, arms.({-0.35, 0.8, -0.55}, 40, -35))},
       {7.5, clouds},
       {10.0, at.(-0.13, sym(%{{:reach, :l} => %{by: {0.05, 0.32, -0.15}}}))},
       {12.5, mirror(clouds)},
       {14.5, at.(-0.05, arms.({-0.25, 0.5, -0.85}, 20, 0))}
     ]}
  end

  def routine("yoga") do
    together = &together/2
    open = fn wrist -> sym(%{{:hand, :l} => "open", "hand_l" => [flex: wrist]}) end
    # The hands together, palm to palm (`together/2`).
    namaste = together.({0.135, 0.26, -0.12}, 55)
    mountain = Map.put(namaste, :hips, %{at: {0.0, 0.0, 0.0}})

    raised =
      [open.(0), sym(%{{:aim, :l} => %{to: {-0.15, 0.05, 1.0}}, "lowerarm_l" => [flex: 0]})]
      |> merge(%{:hips => %{at: {0.0, 0.0, 0.0}}, :spine => [flex: -10], :look => {0.0, 1.0, 0.35}})

    fold =
      [open.(0), sym(%{{:aim, :l} => %{to: {0.05, 0.15, -1.0}}, "lowerarm_l" => [flex: 5]})]
      |> merge(%{:hips => %{at: {0.0, -0.05, -0.04}, turn: [flex: 55]}, :spine => [flex: 30]})

    tree =
      [together.({0.15, 0.06, 0.45}, 10)]
      |> merge(%{
        :hips => %{at: {-0.04, 0.0, -0.01}},
        {:foot, :r} => %{by: {-0.24, 0.03, 0.4}, flat: false, pole: {1.0, 0.3, 0.0}}
      })

    warrior =
      [open.(0), sym(%{{:aim, :l} => %{to: {-1.0, 0.0, 0.03}}, "lowerarm_l" => [flex: 0]})]
      |> merge(%{
        :hips => %{at: {-0.1, 0.0, -0.18}},
        {:foot, :l} => %{by: {-0.42, 0.02, 0.0}, toe: 85, pole: {-1.0, 0.2, 0.0}},
        {:foot, :r} => %{by: {0.3, -0.02, 0.0}, toe: 5},
        :look => {-1.0, 0.1, 0.0}
      })

    {24.0, 10,
     [
       {0.0, mountain},
       {3.0, raised},
       {6.0, fold},
       {8.5, fold},
       {10.5, raised},
       {12.0, mountain},
       {14.0, tree},
       {16.5, tree},
       {18.0, mountain},
       {19.5, warrior},
       {22.0, warrior}
     ]}
  end

  def routine("aerobics") do
    fists = sym(%{{:hand, :l} => "fist"})
    open = sym(%{{:hand, :l} => "open"})
    arm = fn side, to, flex -> %{{:aim, side} => %{to: to}, "lowerarm_#{side}" => [flex: flex]} end

    march =
      [fists, arm.(:l, {-0.15, -0.5, -0.85}, 80), arm.(:r, {0.15, 0.7, -0.7}, 95)]
      |> merge(%{:hips => %{at: {0.0, 0.0, -0.02}}, {:foot, :l} => %{by: {0.02, 0.12, 0.25}, flat: false}})

    jack = fn width, to, z ->
      merge([open, sym(%{{:foot, :l} => %{by: {width, 0.0, 0.0}, toe: 15}} |> Map.merge(arm.(:l, to, 10)))], %{
        :hips => %{at: {0.0, 0.0, z}}
      })
    end

    out = jack.(-0.18, {-0.4, 0.0, 0.92}, -0.04)
    in_ = jack.(0.05, {-0.2, 0.05, -1.0}, -0.02)

    side =
      [fists, arm.(:r, {0.05, 1.0, 0.1}, 0), arm.(:l, {-0.3, 0.6, -0.5}, 120)]
      |> merge(%{:hips => %{at: {0.1, 0.0, -0.06}}, {:foot, :r} => %{by: {0.28, 0.0, 0.0}, toe: 10}})

    punch =
      merge([fists, arm.(:l, {-0.05, 1.0, 0.1}, 0), arm.(:r, {0.3, 0.6, -0.5}, 120)], %{
        :hips => %{at: {0.0, 0.0, -0.03}}
      })

    knee =
      [open, sym(arm.(:l, {-0.15, 0.1, 1.0}, 10))]
      |> merge(%{:hips => %{at: {0.0, 0.0, -0.02}}, {:foot, :l} => %{by: {0.02, 0.12, 0.28}, flat: false}})

    clap = Map.put(together({0.14, 0.32, -0.05}, 25), :hips, %{at: {0.0, 0.0, -0.04}})

    {8.0, 15,
     [
       {0.0, march},
       {0.5, mirror(march)},
       {1.0, march},
       {1.5, mirror(march)},
       {2.0, out},
       {2.5, in_},
       {3.0, out},
       {3.5, in_},
       {4.0, side},
       {4.5, punch},
       {5.0, mirror(side)},
       {5.5, mirror(punch)},
       {6.0, knee},
       {6.5, clap},
       {7.0, mirror(knee)},
       {7.5, clap}
     ]}
  end

  def routine(name), do: raise(ArgumentError, "unknown routine #{inspect(name)}")

  # The two hands together, palm to palm: the wrists at `by` from the
  # shoulders (a little apart), the forearms turned so that the palms
  # face each other (-60), the wrists bent by `wrist` (up for the fingers).
  defp together(by, wrist) do
    sym(%{{:reach, :l} => %{by: by}, "lowerarm_l" => [twist: -60], "hand_l" => [flex: wrist], {:hand, :l} => "open"})
  end

  # One pose from many: the maps in order, then `more`.
  defp merge(maps, more), do: Enum.reduce(maps ++ [more], %{}, &Map.merge(&2, &1))
end
