defmodule World.People.Pose do
  @moduledoc """
  Poses and animations of a person. A pose is a map of a bone to a list
  of turns `{axis, degrees}`. The axis is in the axes of World (x to the
  right side, y to the front, z up) when the person stands at rest; the
  bone turns around its head.

  The named poses: `"stand"` (the arms down at the sides), `"sit"` (on a
  chair or a stool), `"ride"` (on a scooter or a motorbike: the hands
  forward on the bars), `"ride_bicycle"`, `"drive"` (in the seat of a
  car or a van: the hands forward on the wheel). The named animations: `"walk"`
  (one step of each leg in 1.1 s, in a loop); `"wave"` (the right hand
  goes up and waves three times, in 2.6 s, once); `"point"` (an excited
  point: the left arm goes up fast to the left side of the person, with
  the index finger out and the other fingers in the fist, and jabs three
  times; the body leans there and the head looks there; in 2.6 s, once). A clip that plays once starts and stops in the pose
  "stand".
  """
  alias World.Frame

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

  @doc """
  The frame of a bone (relative to its parent) in a pose: its frame at
  rest, then its turns around its own head.
  """
  def turn(local, bone, pose) do
    to_bone = Frame.invert(%{bone.frame | at: {0.0, 0.0, 0.0}})

    pose
    |> Map.get(bone.name, [])
    |> Enum.reduce(local, fn {axis, deg}, f -> Frame.compose(f, Frame.turn(Frame.dir(to_bone, axis), deg)) end)
  end

  @doc """
  An animation by its name, for the bones of a person (parents first,
  as `World.People.Human` makes them): the channels of the rotations of the
  bones, with the indices of the nodes of the figure (bone i is node
  i + 1).
  """
  def animation("walk", bones), do: clip("walk", bones, 1.1, 12, &walk_turns(&1 / 1.1))
  def animation("wave", bones), do: clip("wave", bones, 2.6, 39, &wave_turns/1)
  def animation("point", bones), do: clip("point", bones, 2.6, 39, &point_turns/1)
  def animation(name, _bones), do: raise(ArgumentError, "unknown animation #{inspect(name)}")

  # A clip of `steps` frames in `length` seconds: the turns at each time
  # (on top of the arms down) of the bones that the turns name.
  defp clip(name, bones, length, steps, turns) do
    times = for k <- 0..steps, do: k * length / steps
    world = Map.new(bones, &{&1.name, &1.frame})

    channels =
      for {b, i} <- Enum.with_index(bones, 1), Map.has_key?(turns.(0.0), b.name) do
        parent = if b.parent, do: world[b.parent], else: Frame.identity()
        local = Frame.compose(Frame.invert(parent), b.frame)
        values = for t <- times, do: turn(local, b, Map.merge(@arms_down, turns.(t)))
        %{node: i, path: :rotation, times: times, values: values}
      end

    %{name: name, channels: channels}
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

  # A wave of the right hand: the arm goes up to the side, the forearm
  # goes up, and the hand moves from side to side three times. The rest
  # pose has the arms 45 degrees down: -38 is down, -57 is a little up.
  defp wave_turns(t) do
    k = lift(t, 0.45, 2.1, 2.6)
    swing = 22 * :math.sin(2 * :math.pi() * 3 * max(0.0, t - 0.45) / 1.65)

    %{
      "upperarm_r" => [{@y, 38 - 95 * k}, {@x, 15 * k}],
      "lowerarm_r" => [{@y, k * (-65 + swing)}],
      "head" => [{@y, 8 * k}]
    }
  end

  # The axis that curls the fingers of the left hand into the palm: the
  # fingers at rest go forward and down, and the palm looks to the body.
  @curl_l {-0.44, -0.56, -0.69}

  # An excited point: the left arm goes up fast to the left side of the
  # person, a little forward and up, straight, with the index finger out
  # and the other fingers in the fist. The forearm jabs three times to
  # get attention, the body leans and turns there, and the head looks
  # there. (The rest pose bends the elbow forward: -55 about x makes the
  # arm straight.)
  defp point_turns(t) do
    k = lift(t, 0.3, 2.1, 2.6)
    jab = if t > 0.35 and t < 1.85, do: 35 * (1 - :math.cos(2 * :math.pi() * 3 * (t - 0.35) / 1.5)) / 2, else: 0.0

    Map.merge(left_fist(k), %{
      "upperarm_l" => [{@z, -20 * k}, {@y, -38 + 118 * k}],
      "lowerarm_l" => [{@x, (-55 + jab) * k}],
      "hand_l" => [{@curl_l, -30 * k}],
      "spine_02" => [{@y, -7 * k}, {@z, 12 * k}],
      "head" => [{@z, 30 * k}, {@x, 8 * k}]
    })
  end

  # The middle, ring and little fingers of the left hand in the fist, and
  # the thumb folded under the index finger, as far as `k` (0 to 1): the
  # index finger stays out.
  defp left_fist(k) do
    curl =
      for f <- ~w(middle ring pinky),
          {n, deg} <- [{"01", 75}, {"02", 95}, {"03", 65}],
          do: {"#{f}_#{n}_l", [{@curl_l, deg * k}]}

    Map.new(curl ++ [{"thumb_02_l", [{@curl_l, -40 * k}]}, {"thumb_03_l", [{@curl_l, -40 * k}]}])
  end
end
