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
    # (In the stand the angles of the hips and the arms are 0.)
    assert_in_delta k0.thigh.l, 0.0, 1.0e-6
    assert_in_delta k0.arm.r, 0.0, 1.0e-6

    # (A foot that moves forward with the person slides; the hips, the legs and the arms of a walk do not move.)
    faults = Motion.faults(s, look, speed: 1.2, walk: :walk)
    assert {:slide, "a foot on the ground moves 240.0 cm"} in faults
    assert {:hips, "the hips go up and down 0.0 cm"} in faults
    assert {:knee, "the knee bends 0.0° in the swing"} in faults
    assert {:arm, "the arm swings 0.0° to the front"} in faults
    assert {:hips, "the hips go up and down 0.0 cm"} in Motion.faults(s, look, walk: :slow)
  end
end
