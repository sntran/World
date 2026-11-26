defmodule World.People.RoutineTest do
  # The routines of a morning of exercise with the feet on the ground (plan 0021, D6, D8).
  use ExUnit.Case, async: true

  alias World.{Frame, Vec}
  alias World.People.{Human, Motion, Pose, Skeleton}

  @people [
    man: [age: 35, gender: 1.0, height: 0.55],
    woman: [age: 30, gender: 0.0],
    old: [age: 75, gender: 1.0],
    child: [age: 8, gender: 0.0]
  ]

  setup_all do
    {:ok, skeletons: Map.new(@people, fn {who, opts} -> {who, Human.skeleton(opts)} end)}
  end

  # The lowest point of the feet at a key.
  defp low(k), do: Enum.min(for {_, ps} <- k.feet, {_, {_, _, z}} <- ps, do: z)

  # The turn round z of the axis x of a frame (degrees: to the left side for more than 0).
  defp yaw(%Frame{x: {x, y, _}}), do: :math.atan2(y, x) * 180 / :math.pi()

  test "each routine of each kind of person: the feet on the ground but in a jump, no slide, a loop",
       %{skeletons: skeletons} do
    # (A person late by a delay, and the leader who faces the group: the routine in a mirror.)
    for {who, _} <- @people, name <- Pose.routines(), {delay, mirror} <- [{0.0, false}, {0.3, false}, {0.0, true}] do
      s = skeletons[who]
      clip = Pose.animation(name, s.bones, delay: delay, mirror: mirror)
      air = for {a, b} <- Pose.air(name), do: {a + delay, b + delay}
      faults = Motion.faults(s, clip, air: air)
      assert faults == [], "#{who} #{name} #{delay} #{mirror}: #{inspect(faults)}"
    end
  end

  test "the jumping jacks: both feet leave the ground and come back, and the hips go up", %{skeletons: skeletons} do
    s = skeletons.man
    keys = Motion.measure(s, Pose.animation("aerobics", s.bones))
    jumps = Pose.air("aerobics")
    assert length(jumps) == 4

    for {a, b} <- jumps do
      mid = Enum.min_by(keys, &abs(&1.t - (a + b) / 2))
      land = Enum.min_by(keys, &abs(&1.t - (b + 0.05)))
      assert low(mid) > 0.02 and low(land) <= 0.01
      assert elem(mid.hips, 2) > elem(land.hips, 2) + 0.03
    end
  end

  test "the low moves: the hips go down as the knees bend, with the feet flat on the ground", %{skeletons: skeletons} do
    s = skeletons.man
    {_, _, top} = s.rest["pelvis"].at

    for {name, at, deep} <- [{"tai_chi", 7.5, 0.12}, {"aerobics", 4.0, 0.09}, {"yoga", 20.5, 0.15}] do
      k = Enum.min_by(Motion.measure(s, Pose.animation(name, s.bones)), &abs(&1.t - at))
      assert elem(k.hips, 2) < top - deep, name
      # (Each foot flat: its heel and its ball on the ground.)
      for side <- [:l, :r], point <- [:heel, :ball], do: assert(elem(k.feet[side][point], 2) <= 0.01, name)
    end
  end

  test "the trunk turns with the arms, and the head follows the move", %{skeletons: skeletons} do
    s = skeletons.man
    keys = Motion.measure(s, Pose.animation("aerobics", s.bones))
    at = fn t -> Enum.min_by(keys, &abs(&1.t - t)) end
    stand = Skeleton.world(s, Skeleton.locals(s, Pose.expand(Pose.resolve("stand"))))
    # (A punch of the left arm at 4.5 s, of the right arm at 5.5 s: the chest turns from the hips to the other side.)
    # (From -180° to 180°.)
    wrap = fn d -> d - 360 * Float.round(d / 360) end
    turn = fn w -> wrap.(yaw(w["spine_03"]) - yaw(w["pelvis"]) - yaw(stand["spine_03"]) + yaw(stand["pelvis"])) end
    assert turn.(at.(4.5).world) < -8 and turn.(at.(5.5).world) > 8
    # (The head looks down at the knee at 6.0 s, and up to the hands at the top of a jack at 2.0 s: the bone of
    # the head leans to the front, and back.)
    lean = fn w -> elem(Vec.norm(w["head"].y), 1) end
    assert lean.(at.(6.0).world) > lean.(stand) + 0.1 and lean.(at.(2.0).world) < lean.(stand) - 0.05
  end

  test "the beats in the extras of a routine", %{skeletons: skeletons} do
    s = skeletons.woman
    aerobics = Pose.animation("aerobics", s.bones)
    assert aerobics.extras["bpm"] == 120
    assert aerobics.extras["beats"] == for(k <- 0..15, do: k * 0.5)
    # (A person late by a delay has the beats of the routine: the group plays on one beat.)
    assert Pose.animation("aerobics", s.bones, delay: 0.3).extras == aerobics.extras
    assert Pose.animation("tai_chi", s.bones).extras["beats"] == [0.0, 2.5, 5.0, 7.5, 10.0, 12.5, 14.5]
    assert length(Pose.animation("yoga", s.bones).extras["beats"]) >= 11
  end
end
