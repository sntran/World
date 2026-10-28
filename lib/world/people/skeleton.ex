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
  - `:spine` to a list of `{:flex, deg}` (a bend to the front),
    `{:spread, deg}` (a bend to the right side) and `{:twist, deg}` (a
    turn to the left side): a third on each bone of the spine.
  - `:hips` to `%{at: move, turn: turns}`: the hips (and all the body)
    move by `at`, and turn as the spine (`flex`, `spread`, `twist`).
    When the hips move, the feet stay on the ground (as `{:foot, side}`
    with no value).
  - `{:reach, side}` to `%{at: point, pole: dir}` (or `by: move`, from
    the shoulder at rest): the wrist goes to the point, and the elbow to
    the side of `pole` (down and back by default). The elbow bends as much
    as it must.
  - `{:limb, name}` to `%{at: point, pole: dir}` (or `by: move`, from
    the end of the limb at rest): the end of the limb (`World.Limb`,
    `limbs/1`) goes to the point, by the solver of the limb. `{:reach,
    side}` and `{:foot, side}` are the arms and the legs with more: the
    collarbone that lifts, the flat foot.
  - `{:foot, side}` to `%{at: point, pole: dir, flat: true, toe: deg}`
    (or `by: move`, from the ankle at rest): the ankle goes to the point
    (its place at rest by default), the knee
    to the side of `pole` (the front by default), and a flat foot keeps
    its sole level, with the toes turned out by `toe`. `:free` leaves the
    foot as the other turns put it.

  The directions and the points are in the axes of World of the person
  at rest (the ground under the person at z = 0).
  """
  alias World.{Frame, Limb, Vec}
  alias World.People.Joints

  defstruct bones: [], rest: %{}, local: %{}, flex0: %{}, by_name: %{}, tails: %{}, limbs: %{}

  @spine ~w(spine_01 spine_02 spine_03)

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

  @doc """
  A skeleton from bones (parents first, each with its `name`, `parent`,
  `frame` at rest, and `tail`), and its limbs (`World.Limb`): the limbs
  of a person (`World.People.Joints.limbs/0`) whose bones are in the
  skeleton by default.
  """
  def new(bones, limbs \\ nil) do
    rest = Map.new(bones, &{&1.name, &1.frame})
    names = MapSet.new(bones, & &1.name)
    limbs = limbs || Enum.filter(Joints.limbs(), fn l -> Enum.all?(l.bones, &(&1 in names)) end)

    local =
      Map.new(bones, fn b ->
        parent = if b.parent, do: rest[b.parent], else: Frame.identity()
        {b.name, Frame.compose(Frame.invert(parent), b.frame)}
      end)

    s = %__MODULE__{
      bones: bones,
      rest: rest,
      local: local,
      by_name: Map.new(bones, &{&1.name, &1}),
      tails: Map.new(bones, &{&1.name, Frame.point(Frame.invert(&1.frame), &1.tail)}),
      limbs: Map.new(limbs, &{&1.name, &1})
    }

    %{s | flex0: for(b <- bones, hinge?(b.name), into: %{}, do: {b.name, flex(s, rest, b.name)})}
  end

  @doc """
  The flex of a bone in the frames `world` (of `world/2`): the angle from
  its parent bone to the bone around its hinge, in degrees.
  """
  def flex(%__MODULE__{by_name: by_name}, world, name) do
    parent = by_name[name].parent
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
    targets = feet(s, pose)
    pose = spread_spine(pose)
    locals = Map.new(s.bones, fn b -> {b.name, turns(s, b, Map.get(pose, b.name, []))} end)

    locals
    |> hips(s, Map.get(pose, :hips))
    |> aim(s, "l", Map.get(pose, {:aim, :l}))
    |> aim(s, "r", Map.get(pose, {:aim, :r}))
    |> reach(s, "l", Map.get(pose, {:reach, :l}), Map.get(pose, "lowerarm_l", []))
    |> reach(s, "r", Map.get(pose, {:reach, :r}), Map.get(pose, "lowerarm_r", []))
    |> limbs(s, pose)
    |> place_feet(s, targets)
    |> look(s, Map.get(pose, :look))
  end

  @doc """
  The targets of the feet of a pose: for `:l` and `:r`, `%{at, pole,
  flat, toe}`, or nil for a foot with no target (`place_feet/3`).
  """
  def feet(%__MODULE__{} = s, pose) do
    for side <- [:l, :r], into: %{} do
      spec =
        case Map.get(pose, {:foot, side}) do
          :free -> nil
          nil -> if Map.has_key?(pose, :hips), do: %{}
          %{} = spec -> spec
        end

      {side, spec && target(s, side, spec)}
    end
  end

  defp target(s, side, spec) do
    rest = s.rest["foot_#{side}"].at

    %{
      at: Map.get(spec, :at, Vec.add(rest, Map.get(spec, :by, {0.0, 0.0, 0.0}))),
      pole: Map.get(spec, :pole, {0.0, 1.0, 0.0}),
      flat: Map.get(spec, :flat, true),
      toe: Map.get(spec, :toe, 0)
    }
  end

  @doc """
  The legs bend so that each ankle is at its target (`feet/2`), and a
  flat foot keeps its sole level.
  """
  def place_feet(locals, %__MODULE__{} = s, targets) do
    Enum.reduce(targets, locals, fn
      {_side, nil}, locals ->
        locals

      {side, t}, locals ->
        [thigh, calf, foot] = Enum.map(~w(thigh calf foot), &"#{&1}_#{side}")
        locals = two_bone(locals, s, {thigh, calf, foot}, t.at, t.pole, [])

        if t.flat do
          w = world(s, locals)
          at = w[foot].at
          out = if side == :r, do: -t.toe, else: t.toe
          want = Frame.compose(Frame.turn({0.0, 0.0, 1.0}, out, at), %{s.rest[foot] | at: at})
          Map.put(locals, foot, Frame.compose(Frame.invert(w[calf]), want))
        else
          locals
        end
    end)
  end

  # The bend of the back: a third on each bone of the spine, around the
  # axes of World.
  defp spread_spine(pose) do
    case Map.pop(pose, :spine) do
      {nil, pose} ->
        pose

      {turns, pose} ->
        third = for {kind, deg} <- turns, do: {body_axis(kind), deg / 3}
        Enum.reduce(@spine, pose, fn b, pose -> Map.update(pose, b, third, &(&1 ++ third)) end)
    end
  end

  # The axes of the body: a bend to the front, a bend to the right side,
  # a turn to the left side.
  defp body_axis(:flex), do: {-1.0, 0.0, 0.0}
  defp body_axis(:spread), do: {0.0, 1.0, 0.0}
  defp body_axis(:twist), do: {0.0, 0.0, 1.0}

  # The hips move and turn; all the body comes with them.
  defp hips(locals, _s, nil), do: locals

  defp hips(locals, s, spec) do
    at = world(s, locals)["pelvis"].at

    turn =
      Enum.reduce(Map.get(spec, :turn, []), Frame.identity(), fn {kind, deg}, f ->
        Frame.compose(Frame.turn(body_axis(kind), deg, at), f)
      end)

    rotate(locals, s, "pelvis", Frame.compose(Frame.move(Map.get(spec, :at, {0.0, 0.0, 0.0})), turn))
  end

  # The wrist of a side goes to a point. The forearm keeps its other
  # turns (a twist that turns the palm).
  defp reach(locals, _s, _side, nil, _turns), do: locals

  defp reach(locals, s, side, spec, turns) do
    [up, low, hand] = Enum.map(~w(upperarm lowerarm hand), &"#{&1}_#{side}")
    at = Map.get_lazy(spec, :at, fn -> Vec.add(s.rest[up].at, spec.by) end)
    locals = lift(locals, s, side, Vec.sub(at, world(s, locals)[up].at))

    two_bone(
      locals,
      s,
      {up, low, hand},
      at,
      Map.get(spec, :pole, {0.0, -0.3, -1.0}),
      Enum.reject(turns, &match?({:flex, _}, &1))
    )
  end

  # Two bones (a thigh and a calf, an upper arm and a forearm): the
  # middle joint bends so that the end is as far from the start as the
  # target, then the first bone turns to the target, with the middle joint
  # to the side of `pole`. The bend comes from the law of cosines, then a
  # few steps of Newton for the small angle out of the plane of the hinge.
  defp two_bone(locals, s, {a, b, c}, target, pole, more) do
    w = world(s, locals)
    {la, lb} = {Vec.len(Vec.sub(w[b].at, w[a].at)), Vec.len(Vec.sub(w[c].at, w[b].at))}
    d = Vec.len(Vec.sub(target, w[a].at)) |> max(abs(la - lb) + 1.0e-3) |> min(la + lb - 1.0e-4)
    flex = 180 - :math.acos((la * la + lb * lb - d * d) / (2 * la * lb)) * 180 / :math.pi()
    locals = bend(locals, s, {a, b, c}, d, flex, more, 4)
    chain(locals, s, a, c, b, Vec.sub(target, w[a].at), pole)
  end

  defp bend(locals, s, {a, b, c}, d, flex, more, steps) do
    locals = Map.put(locals, b, turns(s, s.by_name[b], [{:flex, flex} | more]))
    span = fn locals -> world(s, locals) |> then(&Vec.len(Vec.sub(&1[c].at, &1[a].at))) end
    g = span.(locals)
    slope = span.(Map.put(locals, b, turns(s, s.by_name[b], [{:flex, flex + 1.0} | more]))) - g

    if steps == 0 or abs(g - d) < 1.0e-5 or abs(slope) < 1.0e-9,
      do: locals,
      else: bend(locals, s, {a, b, c}, d, flex + (d - g) / slope, more, steps - 1)
  end

  @doc "The names of the limbs of the skeleton."
  def limbs(%__MODULE__{limbs: limbs}), do: limbs |> Map.keys() |> Enum.sort()

  @doc "The end of a limb (the tail of its last bone) in the frames `world` of `world/2`."
  def tip(%__MODULE__{} = s, world, %Limb{bones: bones}), do: tip(s, world, List.last(bones))
  def tip(%__MODULE__{tails: tails}, world, bone), do: Frame.point(world[bone], tails[bone])

  # The ends of the limbs go to their points, in the order of the names.
  defp limbs(locals, s, pose) do
    for({{:limb, name}, spec} <- pose, do: {name, spec})
    |> Enum.sort()
    |> Enum.reduce(locals, fn {name, spec}, locals ->
      limb = Map.get(s.limbs, name) || raise ArgumentError, "the skeleton has no limb #{inspect(name)}"
      at = Map.get_lazy(spec, :at, fn -> Vec.add(tip(s, s.rest, limb), spec.by) end)
      solve(locals, s, limb, at, Map.get(spec, :pole, limb.pole), pose)
    end)
  end

  # Two bones: the hinge bends, the first bone turns, the hinge goes to
  # the side of the pole. The bone of the hinge keeps its other turns.
  defp solve(locals, s, %Limb{solver: :two_bone, bones: [a, b]}, at, pole, pose) do
    c = Enum.find(s.bones, &(&1.parent == b)).name
    two_bone(locals, s, {a, b, c}, at, pole, Enum.reject(Map.get(pose, b, []), &match?({:flex, _}, &1)))
  end

  defp solve(locals, s, %Limb{solver: :chain, bones: bones}, at, _pole, _pose), do: descent(locals, s, bones, at, 48)

  # Cyclic coordinate descent: each bone, from the end to the root, turns
  # so that the end of the chain is in the direction of the point.
  defp descent(locals, s, bones, target, steps) do
    last = List.last(bones)

    if steps == 0 or Vec.len(Vec.sub(tip(s, world(s, locals), last), target)) < 1.0e-4 do
      locals
    else
      bones
      |> Enum.reverse()
      |> Enum.reduce(locals, fn bone, locals ->
        w = world(s, locals)
        at = w[bone].at
        to = Vec.sub(target, at)

        if Vec.len(to) < 1.0e-9,
          do: locals,
          else: rotate(locals, s, bone, between(Vec.sub(tip(s, w, last), at), Vec.norm(to), at))
      end)
      |> descent(s, bones, target, steps - 1)
    end
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
    [up, low, hand] = Enum.map(~w(upperarm lowerarm hand), &"#{&1}_#{side}")
    {tip, other} = if Map.get(spec, :end, :wrist) == :elbow, do: {low, hand}, else: {hand, low}

    locals
    |> lift(s, side, to)
    |> chain(s, up, tip, other, to, Map.get(spec, :pole, {0.0, 0.0, -1.0}))
  end

  # The collarbone lifts with the arm: a fifth of the angle of `to` over
  # the horizon, at most 20 degrees.
  defp lift(locals, s, side, to) do
    clav = "clavicle_#{side}"
    {_, _, up_z} = Vec.norm(to)
    deg = min(20.0, max(0.0, :math.asin(up_z) * 180 / :math.pi()) / 5)
    rotate(locals, s, clav, Frame.turn({0.0, side(clav) * 1.0, 0.0}, deg, world(s, locals)[clav].at))
  end

  # The bone `up` turns so that `tip` is in the direction `to` from its
  # head, then around that line so that `other` goes to the side of
  # `pole`.
  defp chain(locals, s, up, tip, other, to, pole) do
    to = Vec.norm(to)
    w = world(s, locals)
    at = w[up].at
    locals = rotate(locals, s, up, between(Vec.sub(w[tip].at, at), to, at))

    w = world(s, locals)
    bend = across(Vec.sub(w[other].at, at), to)
    pole = across(pole, to)

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
    b = s.by_name[name]
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
