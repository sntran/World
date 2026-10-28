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
    "relaxed" => %{fingers: {12, 18, 10}, thumb: {15, 10}},
    "open" => %{fingers: {0, 0, 0}, thumb: {0, 0}},
    "fist" => %{fingers: {85, 100, 70}, thumb: {60, 45}},
    "point" => %{fingers: {85, 100, 70}, index: {0, 0, 0}, thumb: {60, 45}},
    "thumbs_up" => %{fingers: {85, 100, 70}, thumb: {-10, 0}}
  }

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
      {{kind, side}, value} when kind in [:aim, :hand] -> {{kind, other(side)}, mirror_value(value)}
      {:look, dir} -> {:look, flip(dir)}
      {bone, turns} -> {swap(bone), Enum.map(turns, &mirror_turn/1)}
    end)
  end

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
  An animation by its name, for the bones of a person (parents first,
  as `World.People.Human` makes them): the channels of the rotations of the
  bones that move, with the indices of the nodes of the figure (bone i is
  node i + 1).
  """
  def animation("walk", bones), do: clip("walk", bones, 1.1, 12, &{walk_turns(&1 / 1.1), 1.0})
  def animation("wave", bones), do: clip("wave", bones, 2.6, 39, &wave/1)
  def animation("point", bones), do: clip("point", bones, 2.6, 39, &point/1)
  def animation(name, _bones), do: raise(ArgumentError, "unknown animation #{inspect(name)}")

  # A clip of `steps` frames in `length` seconds. At each time, `at` gives
  # a pose (on top of the pose "stand") and how far the person is in it,
  # from 0 (the pose "stand") to 1: each bone turns on the shortest arc.
  # The channels are the bones that move.
  defp clip(name, bones, length, steps, at) do
    skeleton = Skeleton.new(bones)
    stand = @poses["stand"]
    base = Skeleton.locals(skeleton, stand)
    times = for k <- 0..steps, do: k * length / steps

    frames =
      for t <- times do
        {pose, k} = at.(t)
        target = Skeleton.locals(skeleton, expand(Map.merge(stand, pose)))
        Map.new(target, fn {bone, f} -> {bone, Frame.blend(base[bone], f, k)} end)
      end

    channels =
      for {b, i} <- Enum.with_index(bones, 1),
          values = Enum.map(frames, & &1[b.name]),
          Enum.any?(values, &moved?(&1, base[b.name])) do
        %{node: i, path: :rotation, times: times, values: values}
      end

    %{name: name, channels: channels}
  end

  defp moved?(a, b),
    do: Enum.any?([{a.x, b.x}, {a.y, b.y}, {a.z, b.z}], fn {u, v} -> Vec.len(Vec.sub(u, v)) > 1.0e-6 end)

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
end
