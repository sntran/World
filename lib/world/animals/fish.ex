defmodule World.Animals.Fish do
  @moduledoc """
  The body plan of a fish: a chain of bones from the snout to the tail
  fin, and fins.

  The bones of World, from the front to the back: `head`, `spine_01`,
  `pelvis` (the root, the middle of the body), `tail_01` to `tail_03`
  (the back of the body and the stalk of the tail) and `tail_04` (the
  tail fin).

  The joints (the values add to the rest): the balls `spine` and `tail`.
  The limbs: `body` (a chain from the pelvis to the head) and `tail` (a
  chain from `tail_01` to the tail fin). The ports: `ground` (under the
  belly), `mouth`.

  The size of a fish (its `height` in its species file) is its length,
  from the snout to the end of the tail fin.

  The animations: `swim` (a wave goes along the body to the tail, larger
  at the back, as a carp swims) and `idle` (slow and small waves of the
  tail, in place). The numbers of the gait of a species (`gait`):
  `period` (the time of one wave, s) and `stride` (the distance of one
  wave, in lengths of the fish).
  """
  alias World.{Joint, Limb, Part, Rig, Vec}

  @chain ~w(head spine_01 pelvis tail_01 tail_02 tail_03 tail_04)
  # The wave of the swim at each bone: degrees of the turn to the side.
  @wave %{"head" => 3, "spine_01" => 2, "pelvis" => 3, "tail_01" => 6, "tail_02" => 9, "tail_03" => 12, "tail_04" => 14}

  @doc false
  def figure_name(species), do: species |> String.split("_") |> List.last()

  @doc "The bones of the body plan, parents first."
  def bones, do: ~w(pelvis spine_01 head tail_01 tail_02 tail_03 tail_04)

  @doc "The bone whose head is the tail of a bone (nil: the end of the bone of the mesh)."
  def next("pelvis"), do: "spine_01"
  def next("spine_01"), do: "head"
  def next("tail_0" <> i), do: if(i == "4", do: nil, else: "tail_0#{String.to_integer(i) + 1}")
  def next(_), do: nil

  @doc "The hinge of a bone: across the body, so a flex turns it up or down."
  def hinge(_name, _dir), do: {1.0, 0.0, 0.0}

  @doc "The size of the mesh: its length, from the snout to the end of the tail fin."
  def height(points, _weights) do
    {lo, hi} = points |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
    hi - lo
  end

  @doc "The pose of the fish: its rest."
  def stance(_skeleton, _gait), do: %{}

  @doc "The speed of the swim (`swim_speed`, m/s), for a fish of length `h`."
  def speeds(h, gait), do: %{"swim_speed" => Float.round(stride(h, gait) / period(gait), 2)}

  @doc "The names of the animations."
  def animations, do: ~w(swim idle)

  @doc "The animations that are clips of the template: none."
  def clips, do: []

  def limbs(_by) do
    [
      Limb.new("body", ~w(pelvis spine_01 head), role: :neck, solver: :chain),
      Limb.new("tail", ~w(tail_01 tail_02 tail_03 tail_04), role: :tail, solver: :chain)
    ]
  end

  def joints(_by) do
    [
      Joint.new("spine", :ball,
        role: :spine,
        bone: "spine_01",
        limits: %{flex: {-15, 15}, spread: {-30, 30}, twist: {-10, 10}}
      ),
      Joint.new("tail", :ball,
        role: :tail,
        bone: "tail_01",
        limits: %{flex: {-20, 20}, spread: {-45, 45}, twist: {-10, 10}}
      )
    ]
  end

  def ports(by) do
    head = by["head"]

    [
      {"ground", nil, Part.port("ground", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})},
      {"mouth", "head", Part.port("mouth", head.tail, Vec.norm(Vec.sub(head.tail, head.head)), {0, 0, 1})}
    ]
  end

  @doc "An animation of the body plan, for a fish of length `h` (m) and the numbers of the gait of its species."
  def animation("swim", skeleton, _h, gait), do: wave("swim", skeleton, period(gait), 1.0)
  def animation("idle", skeleton, _h, gait), do: wave("idle", skeleton, 3 * period(gait), 0.3)

  # A wave along the chain: each bone turns to the side, a part of a
  # period after the bone in front of it, so the wave goes to the tail.
  defp wave(name, skeleton, period, size) do
    bones = Enum.filter(@chain, &Map.has_key?(skeleton.rest, &1))

    Rig.clip(name, skeleton, period, 16, fn t ->
      for {bone, i} <- Enum.with_index(bones), into: %{} do
        # The bones in front of the pelvis point to the front: a turn of
        # the same sign moves them to the other side.
        sign = if i < 2, do: -1, else: 1
        {bone, [spread: sign * size * @wave[bone] * :math.sin(2 * :math.pi() * (t / period - i / 8))]}
      end
    end)
  end

  defp period(gait), do: Map.get(gait, "period", 0.6)
  defp stride(h, gait), do: Map.get(gait, "stride", 0.5) * h
end
