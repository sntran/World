defmodule World.Animals.Bird do
  @moduledoc """
  The body plan of a bird that walks: a body, a neck and a head with a
  beak, a tail, two wings and two legs.

  The bones of World: `pelvis` (the root, the back of the body),
  `spine_01` (the breast), `neck_01`, `head`, `beak`, `tail_01`, and for each
  side (`_l`, `_r`) the wing (`upperarm`, `lowerarm`, `hand`: folded
  along the body, to the back) and the leg (`thigh` in the body, `calf`:
  the drumstick, `foot`: the bare shank, `ball`: the toes).

  The joints (the values add to the rest): the balls `neck`, `tail`,
  `shoulder_l` and `shoulder_r` (spread opens the wing), `hip_l` and
  `hip_r`, and the hinge `hock_l` and `hock_r` (the joint of the
  drumstick and the shank). The limbs: `leg_l`, `leg_r` (the drumstick
  and the shank: the end is the root of the toes, the hock goes to the
  back), `head` (a chain). The ports: `ground`, `beak`, `back`.

  The animations: `walk` (the feet in turn, each on the ground for 0.6
  of the step; the head stays and then goes to the front, as a chicken
  walks), `idle` (the head turns to look, in short jerks), `peck` (the
  head down to the ground and up, twice) and `flap` (the wings open and
  beat). The numbers of the gait of a species (`gait`): `period`,
  `stride` and `lift`, as a four-legged animal.
  """
  alias World.{Animals, Joint, Limb, Part, Rig, Vec}

  @sides ~w(l r)
  @wing ~w(upperarm lowerarm hand)
  @leg ~w(thigh calf foot ball)

  @doc false
  def figure_name(species), do: species

  @doc "The bones of the body plan, parents first."
  def bones, do: ~w(pelvis spine_01 neck_01 head beak tail_01) ++ for(s <- @sides, n <- @wing ++ @leg, do: "#{n}_#{s}")

  @doc "The bone whose head is the tail of a bone (nil: the end of the bone of the mesh)."
  def next("pelvis"), do: "spine_01"
  def next("spine_01"), do: "neck_01"
  def next("neck_01"), do: "head"
  def next("head"), do: "beak"

  def next(name) do
    with [part, side] <- String.split(name, "_"),
         list when list != nil <- Enum.find([@wing, @leg], &(part in &1)),
         n when n != nil <- Enum.at(list, Enum.find_index(list, &(&1 == part)) + 1) do
      "#{n}_#{side}"
    else
      _ -> nil
    end
  end

  @doc "The hinge of a bone: a bend of a shank takes the toes to the front."
  def hinge(name, _dir), do: if(String.starts_with?(name, "foot_"), do: {-1.0, 0.0, 0.0}, else: {1.0, 0.0, 0.0})

  @doc """
  The height of the mesh: its highest point with a weight (the top of the
  head or of the comb; not of the faces that a species does not keep).
  """
  def height(points, weights) do
    points = List.to_tuple(points)
    for(m <- Map.values(weights), {i, _} <- m, do: elem(elem(points, i), 2)) |> Enum.max()
  end

  @doc "The pose of the bird: its rest."
  def stance(_skeleton, _gait), do: %{}

  @doc "The speed of the walk (`walk_speed`, m/s), for a bird of height `h`."
  def speeds(h, gait), do: %{"walk_speed" => Float.round(stride(h, gait) / period(gait), 2)}

  @doc "The names of the animations."
  def animations, do: ~w(walk idle peck flap)

  @doc "The animations that are clips of the template: none."
  def clips, do: []

  def limbs(_by) do
    for(s <- @sides, do: Limb.new("leg_#{s}", ["calf_#{s}", "foot_#{s}"], role: :leg, pole: {0.0, -1.0, 0.0})) ++
      [Limb.new("head", ~w(neck_01 head), role: :neck, solver: :chain)]
  end

  def joints(_by) do
    List.flatten(
      for s <- @sides do
        [
          Joint.new("shoulder_#{s}", :ball,
            role: :shoulder,
            bone: "upperarm_#{s}",
            limits: %{flex: {-30, 60}, spread: {-10, 120}, twist: {-30, 30}}
          ),
          Joint.new("hip_#{s}", :ball,
            role: :hip,
            bone: "thigh_#{s}",
            limits: %{flex: {-40, 60}, spread: {-20, 20}, twist: {-20, 20}}
          ),
          Joint.new("hock_#{s}", :hinge, role: :ankle, bone: "foot_#{s}", limits: {-60, 90})
        ]
      end
    ) ++
      [
        Joint.new("neck", :ball,
          role: :neck,
          bone: "neck_01",
          limits: %{flex: {-60, 90}, spread: {-90, 90}, twist: {-60, 60}}
        ),
        Joint.new("tail", :ball,
          role: :tail,
          bone: "tail_01",
          limits: %{flex: {-30, 40}, spread: {-30, 30}, twist: {-20, 20}}
        )
      ]
  end

  def ports(by) do
    {beak, spine} = {by["beak"], by["spine_01"]}

    [
      {"ground", nil, Part.port("ground", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})},
      {"beak", "beak", Part.port("beak", beak.tail, Vec.norm(Vec.sub(beak.tail, beak.head)), {0, 0, 1})},
      {"back", "spine_01", Part.port("back", Vec.lerp(spine.head, spine.tail, 0.5), {0, 0, 1}, {0, 1, 0})}
    ]
  end

  @doc "An animation of the body plan, for a bird of height `h` (m) and the numbers of the gait of its species."
  def animation("walk", skeleton, h, gait) do
    {period, stride, lift} = {period(gait), stride(h, gait), Map.get(gait, "lift", 0.08) * h}
    r = skeleton.rest

    Rig.clip("walk", skeleton, period, 16, fn t ->
      u = t / period

      legs =
        Map.new([{"l", 0.0}, {"r", 0.5}], fn {s, phase} ->
          step = Animals.foot(:math.fmod(u + phase, 1.0), stride, lift, 0.6).by
          {{:limb, "leg_#{s}"}, %{at: Vec.add(r["ball_#{s}"].at, step), pole: {0.0, -1.0, 0.0}}}
        end)

      # The head stays in the air while the body walks under it, then
      # goes to the front: twice in a step, once for each foot.
      v = :math.fmod(2 * u, 1.0)
      head = if v < 0.7, do: 20 * v / 0.7 - 10, else: 10 - 20 * (v - 0.7) / 0.3

      # The body rocks from side to side with the steps. (No move of the
      # hips: it would keep the feet of a person at their rest.)
      Map.merge(legs, %{
        "pelvis" => [twist: 4 * :math.sin(2 * :math.pi() * u)],
        "neck_01" => [flex: head],
        "head" => [flex: -head],
        "tail_01" => [spread: 4 * :math.sin(2 * :math.pi() * u)]
      })
    end)
  end

  def animation("idle", skeleton, _h, _gait) do
    # The head turns to a side, holds, turns to the other side, in jerks.
    turns = [0, 0, 35, 35, 35, -10, -10, -40, -40, -40, 0, 0]

    Rig.clip("idle", skeleton, 3.0, 12, fn t ->
      a = Enum.at(turns, min(trunc(t / 3.0 * 12), 11))
      Map.merge(planted(skeleton), %{"neck_01" => [spread: a * 0.6], "head" => [spread: a * 0.4, twist: a * 0.2]})
    end)
  end

  def animation("peck", skeleton, _h, _gait) do
    Rig.clip("peck", skeleton, 1.6, 16, fn t ->
      # Two pecks: the neck goes down to the ground, and the body leans a
      # little to the front.
      d = :math.pow(:math.sin(2 * :math.pi() * t / 0.8), 2)

      Map.merge(planted(skeleton), %{
        "pelvis" => [flex: -10 * d],
        "neck_01" => [flex: -100 * d],
        "head" => [flex: -10 * d],
        "tail_01" => [flex: 15 * d]
      })
    end)
  end

  def animation("flap", skeleton, _h, _gait) do
    Rig.clip("flap", skeleton, 1.2, 24, fn t ->
      # The wings open out to the sides, beat up and down three times,
      # and fold again.
      open = :math.sin(:math.pi() * t / 1.2)
      beat = :math.sin(2 * :math.pi() * t / 0.4)

      for s <- @sides, into: %{} do
        sign = if s == "l", do: -1, else: 1
        {"upperarm_#{s}", [spread: sign * (80 * open + 25 * open * beat), flex: 20 * open]}
      end
      |> Map.merge(planted(skeleton))
      |> Map.merge(%{"neck_01" => [flex: 10 * open]})
    end)
  end

  # The feet stay at their places at rest, on the ground, when the body
  # moves.
  defp planted(skeleton) do
    Map.new(@sides, &{{:limb, "leg_#{&1}"}, %{at: skeleton.rest["ball_#{&1}"].at, pole: {0.0, -1.0, 0.0}}})
  end

  defp period(gait), do: Map.get(gait, "period", 0.5)
  defp stride(h, gait), do: Map.get(gait, "stride", 0.3) * h
end
