defmodule World.People.Skeleton do
  @moduledoc """
  The skeleton of a person (the 53 bones of the MakeHuman skeleton
  `game_engine`) and the turns of its joints. A bone has its own axes
  (from the roll of the rig): y goes from its head to its tail, and x is
  the hinge of its joint. The left and the right bones are mirrors.

  A pose is a map:

  - a bone name to a list of turns, in order. A turn is one of:
    - `{:flex, deg}`: the bend of the joint around its hinge (x; -z for
      the thumb). On a hinge (`hinge?/1`: the elbow, the wrist, the knee
      and the joints of the fingers) the value is the angle from straight
      (0 is a straight joint), in its limits (`limits/1`); on other bones
      it adds to the rest pose;
    - `{:spread, deg}`: the turn to the side (z; x for the thumb);
    - `{:twist, deg}`: the turn around the bone (y);
    - `{axis, deg}`: a turn around an axis of World (x to the right side,
      y to the front, z up) of the person at rest.

    `spread` and `twist` have the same meaning on the two sides (the
    right side turns the other way), so a pose of the left side is also a
    pose of the right side.
  - `{:aim, side}` (`:l` or `:r`) to `%{to: dir, pole: dir, end: :wrist |
    :elbow}`: the shoulder turns so that the wrist (or the elbow) is in
    the direction `to` from the shoulder, and the other joint (the elbow,
    or the wrist) goes to the side of `pole`. The collarbone lifts a
    little when the arm goes up. Two bones, as inverse kinematics: the
    bend of the elbow comes from the flex of the forearm.
  - `:look` to a direction: the neck and the head turn so that the face
    looks there (two parts of five in the neck).

  The directions are in the axes of World of the person at rest.
  """
  alias World.{Frame, Vec}

  defstruct bones: [], rest: %{}, local: %{}, flex0: %{}

  @type t :: %__MODULE__{}

  # The hinges, and the limits of their flex from straight, in degrees.
  @limits %{
    "lowerarm" => {0, 150},
    "hand" => {-70, 80},
    "calf" => {0, 150},
    "finger_01" => {-15, 90},
    "finger_02" => {0, 110},
    "finger_03" => {0, 80},
    "thumb_02" => {-20, 60},
    "thumb_03" => {-10, 80}
  }

  @fingers ~w(index middle ring pinky)

  @doc "A skeleton from the bones of `World.People.Human` (parents first)."
  def new(bones) do
    rest = Map.new(bones, &{&1.name, &1.frame})

    local =
      Map.new(bones, fn b ->
        parent = if b.parent, do: rest[b.parent], else: Frame.identity()
        {b.name, Frame.compose(Frame.invert(parent), b.frame)}
      end)

    s = %__MODULE__{bones: bones, rest: rest, local: local}
    %{s | flex0: for(b <- bones, hinge?(b.name), into: %{}, do: {b.name, flex(s, rest, b.name)})}
  end

  @doc """
  The flex of a bone in the frames `world` (of `world/2`): the angle from
  its parent bone to the bone around its hinge, in degrees.
  """
  def flex(%__MODULE__{bones: bones}, world, name) do
    parent = Enum.find(bones, &(&1.name == name)).parent
    {axis, _, _} = axes(name)
    angle(world[parent].y, world[name].y, Frame.dir(world[name], axis))
  end

  @doc "A hinge: its flex is the angle from straight, in its limits."
  def hinge?(name), do: Map.has_key?(@limits, kind(name))

  @doc "The limits of the flex of a hinge, from straight, in degrees."
  def limits(name), do: Map.fetch!(@limits, kind(name))

  @doc "The flex of a hinge at rest, from straight, in degrees."
  def rest_flex(%__MODULE__{flex0: flex0}, name), do: Map.fetch!(flex0, name)

  # The kind of a bone for its limits: the joints of the four fingers are
  # the same.
  defp kind(name) do
    base = String.replace(name, ~r/_[lr]$/, "")

    case String.split(base, "_") do
      [f, n] when f in @fingers -> "finger_" <> n
      _ -> base
    end
  end

  # The axes of a bone in its own axes: flex, spread, twist. The thumb
  # bends around -z. A turn of the right side is the mirror of the same
  # turn of the left side: around x it is the same, around y and z it is
  # the other way.
  defp axes(name) do
    axes =
      if String.starts_with?(name, "thumb"),
        do: [{0.0, 0.0, -1.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}],
        else: [{1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, {0.0, 1.0, 0.0}]

    axes |> Enum.map(fn {x, y, z} -> if side(name) < 0, do: {x, -y, -z}, else: {x, y, z} end) |> List.to_tuple()
  end

  defp side(name), do: if(String.ends_with?(name, "_r"), do: -1, else: 1)

  @doc "The frame of each bone (relative to its parent) in a pose."
  def locals(%__MODULE__{} = s, pose) do
    locals = Map.new(s.bones, fn b -> {b.name, turns(s, b, Map.get(pose, b.name, []))} end)

    locals
    |> aim(s, "l", Map.get(pose, {:aim, :l}))
    |> aim(s, "r", Map.get(pose, {:aim, :r}))
    |> look(s, Map.get(pose, :look))
  end

  @doc "The frame of each bone in the axes of the person, from its local frames."
  def world(%__MODULE__{bones: bones}, locals) do
    Enum.reduce(bones, %{}, fn b, w ->
      parent = if b.parent, do: w[b.parent], else: Frame.identity()
      Map.put(w, b.name, Frame.compose(parent, locals[b.name]))
    end)
  end

  defp turns(s, b, list) do
    {flex, spread, twist} = axes(b.name)

    Enum.reduce(list, s.local[b.name], fn
      {:flex, deg}, f ->
        deg = if hinge?(b.name), do: clamp(deg, limits(b.name)) - s.flex0[b.name], else: deg
        Frame.compose(f, Frame.turn(flex, deg))

      {:spread, deg}, f ->
        Frame.compose(f, Frame.turn(spread, deg))

      {:twist, deg}, f ->
        Frame.compose(f, Frame.turn(twist, deg))

      {{_, _, _} = axis, deg}, f ->
        to_bone = Frame.invert(%{s.rest[b.name] | at: {0.0, 0.0, 0.0}})
        Frame.compose(f, Frame.turn(Frame.dir(to_bone, axis), deg))
    end)
  end

  defp clamp(v, {lo, hi}), do: v |> max(lo) |> min(hi)

  # The arm of a side: the shoulder turns the wrist (or the elbow) to `to`,
  # then around that line so that the other joint goes to `pole`.
  defp aim(locals, _s, _side, nil), do: locals

  defp aim(locals, s, side, %{to: to} = spec) do
    [clav, up, low, hand] = Enum.map(~w(clavicle upperarm lowerarm hand), &"#{&1}_#{side}")
    to = Vec.norm(to)
    {tip, other} = if Map.get(spec, :end, :wrist) == :elbow, do: {low, hand}, else: {hand, low}

    # The collarbone lifts with the arm: a fifth of the angle over the
    # horizon, at most 20 degrees.
    {_, _, up_z} = to
    lift = min(20.0, max(0.0, :math.asin(up_z) * 180 / :math.pi()) / 5)
    locals = rotate(locals, s, clav, Frame.turn({0.0, side(clav) * 1.0, 0.0}, lift, world(s, locals)[clav].at))

    w = world(s, locals)
    at = w[up].at
    locals = rotate(locals, s, up, between(Vec.sub(w[tip].at, at), to, at))

    w = world(s, locals)
    bend = across(Vec.sub(w[other].at, at), to)
    pole = across(Map.get(spec, :pole, {0.0, 0.0, -1.0}), to)

    if Vec.len(bend) > 1.0e-6 and Vec.len(pole) > 1.0e-6,
      do: rotate(locals, s, up, Frame.turn(to, angle(bend, pole, to), at)),
      else: locals
  end

  # The face looks to `dir`: two parts of five in the neck, then the rest
  # in the head.
  defp look(locals, _s, nil), do: locals

  defp look(locals, s, dir) do
    face = Frame.dir(Frame.invert(%{s.rest["head"] | at: {0.0, 0.0, 0.0}}), {0.0, 1.0, 0.0})
    dir = Vec.norm(dir)

    Enum.reduce([{"neck_01", 0.4}, {"head", 1.0}], locals, fn {bone, part}, locals ->
      w = world(s, locals)
      now = Frame.dir(w["head"], face)
      axis = Vec.cross(now, dir)

      if Vec.len(axis) < 1.0e-9,
        do: locals,
        else: rotate(locals, s, bone, Frame.turn(axis, part * angle(now, dir, Vec.norm(axis)), w[bone].at))
    end)
  end

  # A bone turns by `r`, a turn in the axes of the person.
  defp rotate(locals, s, name, r) do
    w = world(s, locals)
    b = Enum.find(s.bones, &(&1.name == name))
    parent = if b.parent, do: w[b.parent], else: Frame.identity()
    Map.put(locals, name, Frame.compose(Frame.invert(parent), Frame.compose(r, w[name])))
  end

  # The smallest turn from the direction `v` to `t`, at a point.
  defp between(v, t, at) do
    axis = Vec.cross(Vec.norm(v), t)
    if Vec.len(axis) < 1.0e-9, do: Frame.identity(), else: Frame.turn(axis, angle(v, t, Vec.norm(axis)), at)
  end

  # The part of `v` at a right angle to the unit `t`.
  defp across(v, t), do: Vec.sub(v, Vec.scale(t, Vec.dot(v, t)))

  # The angle from `u` to `v` around the unit `axis`, in degrees.
  defp angle(u, v, axis) do
    {u, v} = {across(u, axis), across(v, axis)}
    :math.atan2(Vec.dot(axis, Vec.cross(u, v)), Vec.dot(u, v)) * 180 / :math.pi()
  end
end
