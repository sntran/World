defmodule World.People.MotionTest do
  # The measures of a clip of a person, and the checks of D8 (plan 0021).
  use ExUnit.Case, async: true

  alias World.{Frame, Vec}
  alias World.People.{Human, Motion, Pose, Skeleton}

  setup_all do
    {:ok, s: Human.skeleton(age: 35, gender: 1.0, height: 0.55)}
  end

  # A clip of poses (on the pose "stand") at their times.
  defp clip(s, poses, times) do
    stand = Pose.resolve("stand")
    base = Skeleton.locals(s, Pose.expand(stand))
    frames = for p <- poses, do: Skeleton.locals(s, Pose.expand(Map.merge(stand, p)))
    %{name: "test", channels: Pose.channels(s.bones, base, frames, times)}
  end

  test "the three points of each foot are on the ground at rest: the heel 6 cm behind the ankle, the ball, the toes",
       %{s: s} do
    w = Skeleton.world(s, s.local)

    for {side, points} <- Motion.points(s) do
      at = for {name, {bone, p}} <- points, into: %{}, do: {name, Frame.point(w[bone], p)}
      assert Enum.all?(Map.values(at), fn {_, _, z} -> abs(z) < 1.0e-9 end)
      {ax, ay, _} = s.rest["foot_#{side}"].at
      {hx, hy, _} = at.heel
      assert_in_delta Vec.len({hx - ax, hy - ay, 0.0}), 0.06, 1.0e-9
      assert elem(at.heel, 1) < elem(at.ball, 1) and elem(at.ball, 1) < elem(at.toe, 1)
    end
  end

  test "a person who stands and turns the head: no fault; and a clip with no channel is the stand", %{s: s} do
    look = clip(s, [%{look: {0.0, 1.0, 0.0}}, %{look: {0.3, 1.0, 0.0}}, %{look: {0.0, 1.0, 0.0}}], [0.0, 1.0, 2.0])
    assert look.channels != []
    assert Motion.faults(s, look) == []
    assert Motion.faults(s, %{name: "stand", channels: []}) == []
  end

  test "the feet over the ground, under it, and in the air of a jump", %{s: s} do
    free = %{{:foot, :l} => :free, {:foot, :r} => :free}
    hips = fn z -> Map.put(free, :hips, %{at: {0.0, 0.0, z}}) end
    up = clip(s, [hips.(0.0), hips.(0.05), hips.(0.0)], [0.0, 1.0, 2.0])
    assert Motion.faults(s, up) == [{:ground, "the feet are 5.0 cm over the ground"}]
    assert Motion.faults(s, up, air: [{0.5, 1.5}]) == []
    down = clip(s, [hips.(0.0), hips.(-0.03), hips.(0.0)], [0.0, 1.0, 2.0])
    assert Motion.faults(s, down) == [{:ground, "a foot is 3.0 cm under the ground"}]
  end

  test "a foot that slides on the ground, and a loop that does not close", %{s: s} do
    slide =
      clip(s, [%{hips: %{}}, %{:hips => %{}, {:foot, :l} => %{by: {0.0, 0.03, 0.0}}}, %{hips: %{}}], [0.0, 1.0, 2.0])

    assert Motion.faults(s, slide) == [{:slide, "a foot on the ground moves 3.0 cm"}]
    open = clip(s, [%{look: {0.0, 1.0, 0.0}}, %{look: {0.3, 1.0, 0.0}}], [0.0, 1.0])
    assert Motion.faults(s, open) == [{:loop, "the first and the last key are not the same"}]
  end

  test "a clip in place goes forward by its speed; the stand is not a walk", %{s: s} do
    look = clip(s, [%{look: {0.0, 1.0, 0.0}}, %{look: {0.2, 1.0, 0.0}}, %{look: {0.0, 1.0, 0.0}}], [0.0, 1.0, 2.0])
    [k0, k1 | _] = Motion.measure(s, look, speed: 1.2)
    assert_in_delta elem(k1.feet.l.heel, 1) - elem(k0.feet.l.heel, 1), 1.2, 1.0e-9
    # (In the stand the angle of the hips is 0; the line from the shoulder to the hand is the line of the joints.)
    assert_in_delta k0.thigh.l, 0.0, 1.0e-6
    {_, dy, dz} = Vec.sub(k0.world["hand_r"].at, k0.world["upperarm_r"].at)
    assert_in_delta k0.arm.r, :math.atan2(dy, -dz) * 180 / :math.pi(), 1.0e-9

    # (A foot that moves forward with the person slides; the hips, the legs and the arms of a walk do not move.)
    faults = Motion.faults(s, look, speed: 1.2, limits: :walk)
    assert {:slide, "a foot on the ground moves 240.0 cm"} in faults
    assert {:hips, "the hips go up and down 0.0 cm"} in faults
    assert {:knee, "the knee bends 0.0° in the swing"} in faults
    assert Enum.any?(faults, &match?({:arm, "the line from the shoulder to the hand goes -" <> _}, &1))
    assert {:hips, "the hips go up and down 0.0 cm"} in Motion.faults(s, look, limits: :slow)
  end

  test "the look of the pose stand: the feet wide apart and straight, the trunk to the front, the hands open",
       %{s: s} do
    stand = %{name: "stand", channels: []}
    faults = Motion.faults(s, stand, limits: :stand)
    assert {:width, "the heels are 36.2 cm apart"} in faults
    assert Enum.sort(Enum.uniq(Keyword.keys(faults))) == [:feet, :hand, :trunk, :width]
    [k] = Motion.measure(s, stand)
    # (The feet of the rest of MakeHuman turn 2° out; the trunk leans 4°; the fingers are straight and apart.)
    assert k.toe.l > 0 and k.toe.l < 3 and k.toe.r > 0 and k.toe.r < 3
    assert k.lean > 4 and k.lean < 5
    assert k.hand.l.curl < 40 and k.hand.l.gap > 10
  end

  test "the measures of a hand: half bent and together, open, a fist; the palm to the thigh", %{s: s} do
    hand = fn shape, more ->
      pose = Map.merge(Map.merge(Pose.resolve("stand"), %{{:hand, :l} => shape, {:hand, :r} => shape}), more)
      w = Skeleton.world(s, Skeleton.locals(s, Pose.expand(pose)))
      {Motion.hand(s, w, :l), Motion.hand(s, w, :r)}
    end

    {l, r} = hand.("hang", %{})
    for h <- [l, r], do: assert(h.curl >= 60 and h.curl <= 150 and h.gap <= 5 and h.palm <= 40, inspect(h))
    {open, _} = hand.("open", %{})
    assert open.curl < 10 and open.gap > 10
    {fist, _} = hand.("fist", %{})
    assert fist.curl > 150
    # (The forearm turns half round: the palm goes to the front.)
    {l, r} = hand.("hang", %{"lowerarm_l" => [{:twist, 90}], "lowerarm_r" => [{:twist, 90}]})
    assert l.palm > 60 and r.palm > 60
  end
end
