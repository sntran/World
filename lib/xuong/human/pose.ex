defmodule Xuong.Human.Pose do
  @moduledoc """
  Poses and animations of a person. A pose is a map of a bone to a list
  of turns `{axis, degrees}`. The axis is in the axes of Xưởng (x to the
  right side, y to the front, z up) when the person stands at rest; the
  bone turns around its head.

  The named poses: `"stand"` (the arms down at the sides), `"sit"` (on a
  chair or a stool), `"ride"` (on a scooter or a motorbike: the hands
  forward on the bars), `"ride_bicycle"`. The named animations: `"walk"`
  (one step of each leg in 1.1 s, in a loop).
  """
  alias Xuong.Frame

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
    "ride_bicycle" => %{
      "spine_01" => [{@x, -25}],
      "thigh_l" => [{@x, 70}],
      "thigh_r" => [{@x, 40}],
      "calf_l" => [{@x, -85}],
      "calf_r" => [{@x, -45}],
      "upperarm_l" => [{@y, -30}, {@x, 60}],
      "upperarm_r" => [{@y, 30}, {@x, 60}],
      "lowerarm_l" => [{@x, 15}],
      "lowerarm_r" => [{@x, 15}]
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
  as `Xuong.Human` makes them): the channels of the rotations of the
  bones, with the indices of the nodes of the figure (bone i is node
  i + 1).
  """
  def animation("walk", bones) do
    times = for k <- 0..12, do: k * 1.1 / 12
    world = Map.new(bones, &{&1.name, &1.frame})

    channels =
      for {b, i} <- Enum.with_index(bones, 1), Map.has_key?(walk_turns(0.0), b.name) do
        parent = if b.parent, do: world[b.parent], else: Frame.identity()
        local = Frame.compose(Frame.invert(parent), b.frame)
        values = for t <- times, do: turn(local, b, Map.merge(@arms_down, walk_turns(t / 1.1)))
        %{node: i, path: :rotation, times: times, values: values}
      end

    %{name: "walk", channels: channels}
  end

  def animation(name, _bones), do: raise(ArgumentError, "unknown animation #{inspect(name)}")

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
end
