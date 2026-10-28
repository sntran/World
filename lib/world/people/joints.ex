defmodule World.People.Joints do
  @moduledoc """
  The joints of a person as `World.Joint`s: the names that an order gives
  in `"joints"` to pose a person.

  - The hinges: `elbow`, `wrist`, `knee`, `ankle`, and one curl for each
    finger (`thumb`, `index`, `middle`, `ring`, `pinky`). The value of the
    elbow, the wrist, the knee and a finger is the angle from straight (0
    is a straight joint); the value of the ankle adds to the rest (more
    points the toes down). The value replaces the flex of the pose. A
    curl bends the three joints of a finger together (the two last joints
    of the thumb).
  - The balls: `shoulder`, `hip`, `neck`, `spine`, each with `flex` (to
    the front), `spread` (out to the side of the limb; for the neck and
    the spine, to the right side) and `twist` (around the limb; for the
    neck and the spine, to the left side). The values turn the joint in
    the axes of the body, before the turns of the pose.

  Each joint of a limb has a side: `elbow_l`, `shoulder_r.spread`. The
  two sides are mirrors: a value has the same meaning on the two sides.
  The limits are the normal ranges of motion of the AAOS tables (American
  Academy of Orthopaedic Surgeons, "Joint Motion: Method of Measuring and
  Recording", 1965), from the rest pose of the skeleton (the A pose).
  """
  alias World.Joint

  @fingers ~w(thumb index middle ring pinky)

  # The bones of a finger and the part of the curl of each.
  @curl %{
    "thumb" => [{"thumb_02", 0.6}, {"thumb_03", 0.8}],
    "finger" => [{"01", 1.0}, {"02", 1.1}, {"03", 0.8}]
  }

  @doc "The joints of a person."
  def all do
    limbs =
      for side <- ~w(l r) do
        [
          Joint.new("elbow_#{side}", :hinge, role: :elbow, bone: "lowerarm_#{side}", limits: {0, 150}),
          Joint.new("wrist_#{side}", :hinge, role: :wrist, bone: "hand_#{side}", limits: {-70, 80}),
          Joint.new("knee_#{side}", :hinge, role: :knee, bone: "calf_#{side}", limits: {0, 150}),
          Joint.new("ankle_#{side}", :hinge, role: :ankle, bone: "foot_#{side}", limits: {-20, 50}),
          Joint.new("shoulder_#{side}", :ball,
            role: :shoulder,
            bone: "upperarm_#{side}",
            limits: %{flex: {-60, 180}, spread: {-45, 135}, twist: {-90, 90}}
          ),
          Joint.new("hip_#{side}", :ball,
            role: :hip,
            bone: "thigh_#{side}",
            limits: %{flex: {-30, 120}, spread: {-20, 45}, twist: {-45, 45}}
          )
        ] ++
          for f <- @fingers do
            Joint.new("#{f}_#{side}", :hinge, role: :finger, bone: first(f, side), limits: {0, 90})
          end
      end

    List.flatten(limbs) ++
      [
        Joint.new("neck", :ball,
          role: :neck,
          bone: "neck_01",
          limits: %{flex: {-50, 60}, spread: {-45, 45}, twist: {-70, 70}}
        ),
        Joint.new("spine", :ball,
          role: :spine,
          bone: "spine_01",
          limits: %{flex: {-30, 80}, spread: {-35, 35}, twist: {-40, 40}}
        )
      ]
  end

  defp first("thumb", side), do: "thumb_02_#{side}"
  defp first(f, side), do: "#{f}_01_#{side}"

  @doc """
  The names of the values of the joints of a person, for an order
  (`World.Joint.values/1`).
  """
  def values, do: Enum.flat_map(all(), &Joint.values/1)

  @doc """
  A pose of `World.People.Skeleton` with the values of the joints: a map
  of a value name (`values/0`) to a number. A value out of the limits
  stops at the nearest limit. The names that are not joints of a person
  stay out.
  """
  def pose(pose, values) do
    Enum.reduce(all(), pose, fn j, pose ->
      Enum.reduce(j.axes, pose, fn axis, pose ->
        name = if axis, do: "#{j.name}.#{axis}", else: j.name

        case Map.fetch(values, name) do
          {:ok, v} -> set(pose, j, axis, Joint.clamp(j, axis, v / 1))
          :error -> pose
        end
      end)
    end)
  end

  defp set(pose, %Joint{role: :finger, name: name}, nil, v) do
    [finger, side] = String.split(name, "_")
    bones = if finger == "thumb", do: @curl["thumb"], else: for({n, k} <- @curl["finger"], do: {"#{finger}_#{n}", k})
    Enum.reduce(bones, pose, fn {bone, k}, pose -> flex(pose, "#{bone}_#{side}", v * k) end)
  end

  defp set(pose, %Joint{kind: :hinge, bone: bone}, nil, v), do: flex(pose, bone, v)

  # The spine bends as the `:spine` of the pose: a third on each bone.
  defp set(pose, %Joint{role: :spine}, axis, v), do: Map.update(pose, :spine, [{axis, v}], &[{axis, v} | &1])

  defp set(pose, %Joint{bone: bone} = j, axis, v),
    do: Map.update(pose, bone, [turn(j, axis, v)], &[turn(j, axis, v) | &1])

  # The neck turns in the axes of the body; a limb flexes to the front,
  # spreads out to its side, and twists around itself.
  defp turn(%Joint{role: :neck}, :flex, v), do: {{-1.0, 0.0, 0.0}, v}
  defp turn(%Joint{role: :neck}, :spread, v), do: {{0.0, 1.0, 0.0}, v}
  defp turn(%Joint{role: :neck}, :twist, v), do: {{0.0, 0.0, 1.0}, v}
  defp turn(_j, :flex, v), do: {{1.0, 0.0, 0.0}, v}
  defp turn(%Joint{bone: bone}, :spread, v), do: {{0.0, if(String.ends_with?(bone, "_r"), do: -1.0, else: 1.0), 0.0}, v}
  defp turn(_j, :twist, v), do: {:twist, v}

  # The flex of a hinge replaces the flex of the pose, in its place.
  defp flex(pose, bone, v) do
    Map.update(pose, bone, [{:flex, v}], fn turns ->
      if Enum.any?(turns, &match?({:flex, _}, &1)),
        do: Enum.map(turns, &if(match?({:flex, _}, &1), do: {:flex, v}, else: &1)),
        else: [{:flex, v} | turns]
    end)
  end
end
