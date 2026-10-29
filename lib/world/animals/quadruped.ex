defmodule World.Animals.Quadruped do
  @moduledoc """
  The body plan of an animal on four legs: a dog, a cat, a goat, a
  horse, a cow, a pig, a sheep.

  The bones of World: `pelvis`, `spine_01`, `neck_01`, `head`, `ear_l`
  and `ear_r` and the tail (`tail_01` ...) when the template has them,
  and for each side (`_l`, `_r`) `front_upper`, `front_lower`,
  `front_foot` (the upper arm, the forearm, the paw or the hoof) and
  `hind_upper`, `hind_lower`, `hind_foot` (the thigh, the shin, the
  bones below the hock).

  The joints (the values add to the rest): the hinges `elbow_l`,
  `wrist_l`, `knee_l`, `hock_l` (and `_r`; more bends the elbow and the
  knee, and swings the paw to the front at the wrist and at the hock),
  the balls `shoulder_l`, `hip_l` (and `_r`), `neck`, `spine` and `tail`
  (with a tail: flex lifts the tail, spread wags it to the right side). The limbs:
  `front_l`, `front_r` (the end is the wrist), `hind_l`, `hind_r` (the
  end is the hock): the elbow goes to the back, the knee to the front.
  `tail` (with a tail) and `head` are chains. The ports: `ground`, `collar` (on the neck), `back`
  (on the spine, for a bag), `mouth` (for a stick).

  The animations: `walk`, `run` (a gallop), `idle`, `idle_low` (the
  head low), `eat` (the head down to the ground), `attack`, `kick` (the
  hind legs kick to the back: only the animals with hooves), `jump` (in
  a gallop), `jump_stop` (a jump up and a stop), `hit_l` and `hit_r` (a
  hit on the left or the right side) and `death` are the clips of the
  template (`World.Animals.retarget/5`); `wag` (the tail wags twice,
  with a tail) is code. The
  number of the gait of a species (`gait`): `wag` (the time of a wag,
  s).
  """
  alias World.{Joint, Limb, Part, Rig, Vec}

  @sides ~w(l r)

  @doc false
  def figure_name(species), do: species |> String.split("_") |> List.last()

  @doc "The bones of the body plan, parents first."
  def bones do
    ~w(pelvis spine_01 neck_01 head ear_l ear_r) ++
      for(i <- 1..9, do: "tail_0#{i}") ++
      for side <- @sides, part <- ~w(front hind), name <- ~w(upper lower foot), do: "#{part}_#{name}_#{side}"
  end

  @doc "The bone whose head is the tail of a bone (nil: the end of the bone of the mesh)."
  def next("pelvis"), do: "spine_01"
  def next("spine_01"), do: "neck_01"
  def next("neck_01"), do: "head"
  def next("tail_0" <> i), do: "tail_0#{String.to_integer(i) + 1}"
  def next(name), do: next_leg(String.split(name, "_"))

  defp next_leg([part, "upper", side]), do: "#{part}_lower_#{side}"
  defp next_leg([part, "lower", side]), do: "#{part}_foot_#{side}"
  defp next_leg(_), do: nil

  @doc """
  The hinge of a bone: a bend of a hind lower leg takes the hock to the
  back (the knee goes to the front); a bend of a front lower leg takes
  the wrist to the front (the elbow goes to the back).
  """
  def hinge(name, _dir), do: if(String.starts_with?(name, "hind_lower_"), do: {-1.0, 0.0, 0.0}, else: {1.0, 0.0, 0.0})

  @doc "The height of the mesh at the withers: the highest point of the spine."
  def height(points, weights) do
    spine = weights["spine_01"]

    points
    |> Enum.with_index()
    |> Enum.filter(fn {_, i} -> Map.get(spine, i, 0) >= 0.5 end)
    |> Enum.map(fn {{_, _, z}, _} -> z end)
    |> Enum.max()
  end

  @doc "The bones of the feet: the paws or the hooves."
  def feet, do: for(side <- @sides, part <- ~w(front hind), do: "#{part}_foot_#{side}")

  @doc "The pose of the animal (with the numbers of the gait of its species): its rest."
  def stance(_skeleton, _gait), do: %{}

  @doc "The speeds of the gaits that are code: none (the walk and the run are clips)."
  def speeds(_h, _gait), do: %{}

  @doc "The names of the animations."
  def animations, do: clips() ++ ~w(wag)

  @doc """
  The animations that are clips of the template: a species has one of
  them only when the clips of its template have it (`kick` is only in
  the files of the animals with hooves).
  """
  def clips, do: ~w(walk run idle idle_low eat attack kick jump jump_stop hit_l hit_r death)

  def limbs(by) do
    tail = Enum.filter(bones(), &(String.starts_with?(&1, "tail_") and Map.has_key?(by, &1)))

    for(
      side <- @sides,
      part <- ~w(front hind),
      do:
        Limb.new("#{part}_#{side}", ["#{part}_upper_#{side}", "#{part}_lower_#{side}"],
          role: :leg,
          pole: if(part == "front", do: {0.0, -1.0, 0.0}, else: {0.0, 1.0, 0.0})
        )
    ) ++
      for(bones = [_ | _] <- [tail], do: Limb.new("tail", bones, role: :tail, solver: :chain)) ++
      [Limb.new("head", ~w(neck_01 head), role: :neck, solver: :chain)]
  end

  def joints(by) do
    legs =
      for side <- @sides do
        [
          Joint.new("elbow_#{side}", :hinge, role: :elbow, bone: "front_lower_#{side}", limits: {-60, 90}),
          Joint.new("wrist_#{side}", :hinge, role: :wrist, bone: "front_foot_#{side}", limits: {-40, 90}),
          Joint.new("knee_#{side}", :hinge, role: :knee, bone: "hind_lower_#{side}", limits: {-90, 60}),
          Joint.new("hock_#{side}", :hinge, role: :ankle, bone: "hind_foot_#{side}", limits: {-60, 90}),
          Joint.new("shoulder_#{side}", :ball,
            role: :shoulder,
            bone: "front_upper_#{side}",
            limits: %{flex: {-60, 90}, spread: {-20, 30}, twist: {-20, 20}}
          ),
          Joint.new("hip_#{side}", :ball,
            role: :hip,
            bone: "hind_upper_#{side}",
            limits: %{flex: {-60, 90}, spread: {-20, 40}, twist: {-20, 20}}
          )
        ]
      end

    List.flatten(legs) ++
      [
        Joint.new("neck", :ball,
          role: :neck,
          bone: "neck_01",
          limits: %{flex: {-40, 60}, spread: {-45, 45}, twist: {-60, 60}}
        ),
        Joint.new("spine", :ball,
          role: :spine,
          bone: "spine_01",
          limits: %{flex: {-20, 30}, spread: {-20, 20}, twist: {-15, 15}}
        )
      ] ++
      for _ <- List.wrap(by["tail_01"]) do
        Joint.new("tail", :ball,
          role: :tail,
          bone: "tail_01",
          limits: %{flex: {-60, 40}, spread: {-60, 60}, twist: {-30, 30}}
        )
      end
  end

  def ports(by) do
    {neck, spine, head} = {by["neck_01"], by["spine_01"], by["head"]}
    along = Vec.norm(Vec.sub(neck.tail, neck.head))

    [
      {"ground", nil, Part.port("ground", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})},
      {"collar", "neck_01",
       Part.port("collar", Vec.lerp(neck.head, neck.tail, 0.5), along, {0.0, -elem(along, 2), elem(along, 1)})},
      {"back", "spine_01", Part.port("back", Vec.lerp(spine.head, spine.tail, 0.5), {0, 0, 1}, {0, 1, 0})},
      {"mouth", "head", Part.port("mouth", head.tail, {1, 0, 0}, {0, 0, 1})}
    ]
  end

  @doc "An animation of the body plan, for an animal of height `h` (m) and the numbers of the gait of its species."
  def animation("wag", skeleton, _h, gait) do
    period = Map.get(gait, "wag", 0.4)
    tail = Enum.filter(~w(tail_01 tail_02 tail_03), &Map.has_key?(skeleton.rest, &1))

    Rig.clip("wag", skeleton, 2 * period, 16, fn t ->
      wave = :math.sin(2 * :math.pi() * t / period)
      tail |> Enum.zip([25, 20, 15]) |> Map.new(fn {bone, a} -> {bone, [spread: a * wave]} end)
    end)
  end
end
