defmodule World.Animals.FourLegs do
  @moduledoc """
  The body plan of a body on four legs for a sculpture with bones
  (`docs/plans/0011-any-model.md`, D5): a dog, a cat, a horse, a table
  that walks. Its clips come from code, so a sculpture needs no clips of
  a template (the animals of the catalog have those:
  `World.Animals.Quadruped`).

  The bones have the names of a four-legged animal of World: `pelvis`
  (the root, at the hips), `spine_01` (to the shoulders), `neck_01`,
  `head`, and for each side (`_l`, `_r`) the front leg (`front_upper`,
  `front_lower`, `front_foot`) and the hind leg (`hind_upper`,
  `hind_lower`, `hind_foot`). The body can have more bones (a tail from
  `tail_01`, the ears): they follow their parents, and a tail has its
  joint and its limb.

  The joints, the limbs and the ports are those of
  `World.Animals.Quadruped`: the limbs `front_l`, `front_r` (the end is
  the wrist, the elbow goes to the back), `hind_l`, `hind_r` (the end is
  the hock, the knee goes to the front); the ports `ground`, `collar`,
  `back` and `mouth`.

  The animations: `walk` (one foot after the other, in the order of a
  real walk: the left hind foot, the left front foot, the right hind
  foot, the right front foot, each on the ground for 0.7 of the step,
  so three feet are on the ground at most times), `trot` (the two feet
  of a diagonal at one time, each pair on the ground for half of the
  step, a shorter step in time and a longer one in length) and `idle`
  (the feet stay, the head goes down and up a little). A foot on the
  ground does not turn: the paw stays level. The numbers of the gait
  (`gait`): `period` (s), `stride` and `lift` (parts of the height), for
  the walk.

  The body does not go down for a long stride as the body on two legs
  does: make the legs with a small bend at rest (as an animal stands),
  so each foot reaches the two ends of its path.
  """
  alias World.{Animals, Rig, Vec}
  alias World.Animals.Quadruped

  @sides ~w(l r)
  # The part of a step where each foot starts its time on the ground, for the walk and for the trot.
  @walk %{"hind_l" => 0.0, "front_l" => 0.25, "hind_r" => 0.5, "front_r" => 0.75}
  @trot %{"hind_l" => 0.0, "front_r" => 0.0, "hind_r" => 0.5, "front_l" => 0.5}

  @doc "The bones of the body plan, parents first."
  def bones do
    ~w(pelvis spine_01 neck_01 head) ++
      for side <- @sides, part <- ~w(front hind), name <- ~w(upper lower foot), do: "#{part}_#{name}_#{side}"
  end

  @doc """
  The hinge of a bone that points to `dir`: a bend of a front lower leg
  takes the wrist to the front (the elbow goes to the back), a bend of a
  hind lower leg takes the hock to the back (the knee goes to the
  front).
  """
  def hinge("front_lower_" <> _, dir), do: across(dir, 1.0)
  def hinge("hind_lower_" <> _, dir), do: across(dir, -1.0)
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

  @doc "The speeds of the walk and of the trot (`walk_speed`, `trot_speed`, m/s), for a body of height `h`."
  def speeds(h, gait) do
    %{
      "walk_speed" => Float.round(stride(h, gait) / (0.7 * period(gait)), 2),
      "trot_speed" => Float.round(1.4 * stride(h, gait) / (0.5 * 0.6 * period(gait)), 2)
    }
  end

  @doc "The names of the animations."
  def animations, do: ~w(walk trot idle)

  defdelegate limbs(by), to: Quadruped
  defdelegate joints(by), to: Quadruped
  defdelegate ports(by), to: Quadruped

  @doc "An animation of the body plan, for a body of height `h` (m) and the numbers of its gait."
  def animation("walk", skeleton, h, gait) do
    {period, stride, lift} = {period(gait), stride(h, gait), lift(h, gait)}

    Rig.clip("walk", skeleton, period, 16, fn t ->
      u = t / period
      # The head goes down and up two times in a step, and the back turns a little with the hind feet.
      Map.merge(feet(skeleton, u, @walk, {stride, lift, 0.7}), %{
        "neck_01" => [flex: 3 * :math.sin(4 * :math.pi() * u)],
        "spine_01" => [spread: 2 * :math.sin(2 * :math.pi() * u)]
      })
    end)
  end

  def animation("trot", skeleton, h, gait) do
    {period, stride, lift} = {0.6 * period(gait), 1.4 * stride(h, gait), 1.5 * lift(h, gait)}

    Rig.clip("trot", skeleton, period, 16, fn t ->
      u = t / period

      Map.merge(feet(skeleton, u, @trot, {stride, lift, 0.5}), %{"neck_01" => [flex: 4 * :math.sin(4 * :math.pi() * u)]})
    end)
  end

  def animation("idle", skeleton, _h, _gait) do
    Rig.clip("idle", skeleton, 3.0, 12, fn t ->
      Map.merge(feet(skeleton, 0.0, @walk, {0.0, 0.0, 0.7}), %{
        "neck_01" => [flex: -4 * (1 - :math.cos(2 * :math.pi() * t / 3.0)) / 2]
      })
    end)
  end

  # Each foot on its path at the part `u` of a step: the end of each leg
  # (the wrist, the hock) at its place at rest and the move of its foot,
  # with the paw level.
  defp feet(skeleton, u, starts, {stride, lift, stance}) do
    for {limb, start} <- starts, into: %{} do
      [part, side] = String.split(limb, "_")
      rest = skeleton.rest["#{part}_foot_#{side}"].at
      by = Animals.foot(:math.fmod(u + start, 1.0), stride, lift, stance).by

      {{:limb, limb},
       %{at: Vec.add(rest, by), pole: if(part == "front", do: {0.0, -1.0, 0.0}, else: {0.0, 1.0, 0.0}), flat: true}}
    end
  end

  defp period(gait), do: Map.get(gait, "period", 1.0)
  defp stride(h, gait), do: Map.get(gait, "stride", 0.3) * h
  defp lift(h, gait), do: Map.get(gait, "lift", 0.06) * h
end
