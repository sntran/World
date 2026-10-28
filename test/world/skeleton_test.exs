defmodule World.SkeletonTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.{Frame, Vec}
  alias World.People.{Human, Pose, Skeleton}

  @skeleton Human.skeleton()

  # The points of the joints in a pose, in the axes of the person.
  defp at(pose), do: at(@skeleton, pose)

  defp at(skeleton, pose) do
    w = Skeleton.world(skeleton, Skeleton.locals(skeleton, Pose.expand(pose)))
    fn bone -> w[bone].at end
  end

  defp dir(pos, a, b), do: Vec.norm(Vec.sub(pos.(b), pos.(a)))

  defp deg(u, v), do: :math.acos(max(-1.0, min(1.0, Vec.dot(Vec.norm(u), Vec.norm(v))))) * 180 / :math.pi()

  defp mirror({x, y, z}), do: {-x, y, z}

  # The flex of a hinge in a pose: the angle from the parent bone to the
  # bone, in the plane of the hinge (a straight elbow keeps its small
  # angle out of that plane, as a real arm).
  defp flex(pose, bone),
    do: Skeleton.flex(@skeleton, Skeleton.world(@skeleton, Skeleton.locals(@skeleton, Pose.expand(pose))), bone)

  test "the turns around the axes of World give the frames of before" do
    for name <- Pose.names() do
      pose = Pose.resolve(name)
      locals = Skeleton.locals(@skeleton, pose)

      for b <- @skeleton.bones do
        # The old way: the frame at rest, then the turns around its head.
        to_bone = Frame.invert(%{b.frame | at: {0.0, 0.0, 0.0}})

        old =
          Enum.reduce(Map.get(pose, b.name, []), @skeleton.local[b.name], fn {axis, d}, f ->
            Frame.compose(f, Frame.turn(Frame.dir(to_bone, axis), d))
          end)

        assert Vec.len(Vec.sub(old.y, locals[b.name].y)) < 1.0e-9
        assert Vec.len(Vec.sub(old.z, locals[b.name].z)) < 1.0e-9
      end
    end
  end

  test "the hinges: the rest flex, and the limits" do
    assert Skeleton.hinge?("lowerarm_l") and Skeleton.hinge?("ring_03_r") and Skeleton.hinge?("thumb_02_l")
    refute Skeleton.hinge?("upperarm_l") or Skeleton.hinge?("thumb_01_l") or Skeleton.hinge?("head")
    assert Skeleton.limits("lowerarm_r") == {0, 150}
    assert Skeleton.limits("pinky_01_l") == {-15, 90}
    # The arms of MakeHuman rest with the elbows bent.
    assert_in_delta Skeleton.rest_flex(@skeleton, "lowerarm_l"), 46, 2
    assert_in_delta Skeleton.rest_flex(@skeleton, "lowerarm_l"), Skeleton.rest_flex(@skeleton, "lowerarm_r"), 1.0e-6
    assert_in_delta Skeleton.rest_flex(@skeleton, "thumb_02_l"), Skeleton.rest_flex(@skeleton, "thumb_02_r"), 1.0e-6
  end

  test "a flex of 0 makes a straight joint, and a flex of 90 a right angle" do
    for b <- ~w(lowerarm_l calf_r middle_02_l thumb_03_r hand_l) do
      assert_in_delta flex(%{b => [flex: 0]}, b), 0, 1.0e-6
      {_, hi} = Skeleton.limits(b)
      assert_in_delta flex(%{b => [flex: 50]}, b), min(50, hi), 1.0e-6
      assert_in_delta flex(%{}, b), Skeleton.rest_flex(@skeleton, b), 1.0e-6
    end
  end

  property "the flex of a hinge stays in its limits" do
    check all(flex <- integer(-400..400), max_runs: 25) do
      for b <- ~w(lowerarm_r index_01_l) do
        {lo, hi} = Skeleton.limits(b)
        assert_in_delta flex(%{b => [flex: flex]}, b), flex |> max(lo) |> min(hi), 1.0e-6
      end
    end
  end

  property "the right side is the mirror of the left side" do
    turn = tuple({member_of([:flex, :spread, :twist]), integer(-60..60)})

    check all(
            bone <- member_of(~w(upperarm lowerarm hand index_01 thumb_01 thumb_02 thigh calf)),
            turns <- list_of(turn, min_length: 1, max_length: 3),
            axis <- member_of([{1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}]),
            d <- integer(-40..40),
            max_runs: 25
          ) do
      left = %{"#{bone}_l" => turns ++ [{axis, d}], "clavicle_l" => [{axis, d}]}
      l = at(left)
      r = at(Pose.mirror(left))

      for p <- ~w(hand index_03 thumb_03 foot) do
        assert Vec.len(Vec.sub(mirror(l.("#{p}_l")), r.("#{p}_r"))) < 0.003
      end
    end
  end

  property "the aim puts the wrist in the direction, and the elbow to the pole" do
    check all(
            x <- float(min: -1.0, max: -0.2),
            y <- float(min: -0.5, max: 1.0),
            z <- float(min: -0.8, max: 0.8),
            flex <- integer(20..120),
            max_runs: 20
          ) do
      to = Vec.norm({x, y, z})
      pose = %{{:aim, :l} => %{to: to, pole: {0.0, -0.3, -1.0}}, "lowerarm_l" => [flex: flex]}
      pos = at(pose)
      assert deg(Vec.sub(pos.("hand_l"), pos.("upperarm_l")), to) < 0.5

      # The elbow is on the side of the pole.
      elbow = Vec.sub(pos.("lowerarm_l"), pos.("upperarm_l"))
      across = fn v -> Vec.sub(v, Vec.scale(to, Vec.dot(v, to))) end
      assert Vec.dot(across.(elbow), across.({0.0, -0.3, -1.0})) > 0

      # The mirror aims the right arm.
      r = at(Pose.mirror(pose))
      assert deg(Vec.sub(r.("hand_r"), r.("upperarm_r")), mirror(to)) < 0.5
    end
  end

  test "the aim of the elbow, the collarbone, and an aim at the pole" do
    pos = at(%{{:aim, :r} => %{to: {1.0, 0.0, 0.0}, end: :elbow, pole: {0.0, 0.0, 1.0}}, "lowerarm_r" => [flex: 90]})
    assert deg(dir(pos, "upperarm_r", "lowerarm_r"), {1.0, 0.0, 0.0}) < 0.5
    # The forearm goes up, to the pole.
    assert deg(dir(pos, "lowerarm_r", "hand_r"), {0.0, 0.0, 1.0}) < 2

    # The collarbone lifts with an arm over the horizon.
    rest = at(%{})
    up = at(%{{:aim, :l} => %{to: {-0.5, 0.0, 0.87}}})
    {_, _, z0} = rest.("upperarm_l")
    {_, _, z1} = up.("upperarm_l")
    assert z1 > z0 + 0.005

    # A straight arm, or a pole on the line: only the aim.
    straight = at(%{{:aim, :l} => %{to: {-1.0, 0.0, 0.0}, pole: {-1.0, 0.0, 0.0}}, "lowerarm_l" => [flex: 0]})
    assert deg(Vec.sub(straight.("hand_l"), straight.("upperarm_l")), {-1.0, 0.0, 0.0}) < 0.5
  end

  property "the face looks in the direction" do
    check all(
            x <- float(min: -0.8, max: 0.8),
            z <- float(min: -0.4, max: 0.4),
            max_runs: 15
          ) do
      to = Vec.norm({x, 1.0, z})
      w = Skeleton.world(@skeleton, Skeleton.locals(@skeleton, %{look: to}))
      face = Frame.dir(Frame.invert(%{@skeleton.rest["head"] | at: {0.0, 0.0, 0.0}}), {0.0, 1.0, 0.0})
      assert deg(Frame.dir(w["head"], face), to) < 0.5
    end

    # To the front: no turn.
    w = Skeleton.world(@skeleton, Skeleton.locals(@skeleton, %{look: {0.0, 1.0, 0.0}}))
    assert Vec.len(Vec.sub(w["head"].y, @skeleton.rest["head"].y)) < 1.0e-9
  end

  test "the shapes of a hand" do
    assert Pose.hands() == ["fist", "open", "point", "relaxed", "thumbs_up"]
    near = fn pos, tip -> Vec.len(Vec.sub(pos.(tip), pos.("hand_r"))) end

    open = at(%{{:hand, :r} => "open"})
    fist = at(%{{:hand, :r} => "fist"})
    point = at(%{{:hand, :r} => "point"})

    # In the fist, the tips of the fingers come back to the palm.
    for f <- ~w(index middle ring pinky), do: assert(near.(fist, "#{f}_03_r") < near.(open, "#{f}_03_r") - 0.03)

    # The point: the index finger is straight on the line of the hand, the
    # other fingers in the fist.
    for b <- ~w(index_01_r index_02_r index_03_r), do: assert_in_delta(flex(%{{:hand, :r} => "point"}, b), 0, 1.0e-6)
    assert_in_delta near.(point, "middle_03_r"), near.(fist, "middle_03_r"), 1.0e-9
    # The thumbs up: the thumb straight out.
    up = at(%{{:hand, :r} => "thumbs_up"})
    away = fn pos -> Vec.len(Vec.sub(pos.("thumb_03_r"), pos.("index_02_r"))) end
    assert away.(up) > away.(fist) + 0.01

    # A turn of the bone comes after the shape.
    assert Pose.expand(%{{:hand, :l} => "open", "index_02_l" => [twist: 5]})["index_02_l"] == [flex: 0, twist: 5]
    assert_raise ArgumentError, ~r/unknown hand/, fn -> Pose.hand(:l, "wave") end
  end

  test "the mirror of a pose" do
    pose = %{
      "spine_02" => [{{0.0, 1.0, 0.0}, 7}],
      "upperarm_l" => [{{1.0, 0.5, 0.2}, 10}, flex: 5],
      {:aim, :l} => %{to: {-1.0, 0.2, 0.3}, end: :elbow},
      {:hand, :r} => "point",
      look: {-0.5, 1.0, 0.0}
    }

    assert Pose.mirror(pose) == %{
             "spine_02" => [{{0.0, -1.0, -0.0}, 7}],
             "upperarm_r" => [{{1.0, -0.5, -0.2}, 10}, flex: 5],
             {:aim, :r} => %{to: {1.0, 0.2, 0.3}, end: :elbow},
             {:hand, :l} => "point",
             look: {0.5, 1.0, 0.0}
           }

    assert Pose.mirror(Pose.mirror(pose)) == pose
  end

  property "a blend of two frames goes on the shortest arc" do
    check all(
            a <- integer(-80..80),
            b <- integer(-80..80),
            k <- float(min: 0.0, max: 1.0),
            max_runs: 50
          ) do
      axis = {0.0, 0.6, 0.8}
      fa = Frame.turn(axis, a, {1.0, 2.0, 3.0})
      fb = Frame.turn(axis, b, {1.0, 2.0, 3.0})
      f = Frame.blend(fa, fb, k)
      want = Frame.turn(axis, a + (b - a) * k, {1.0, 2.0, 3.0})
      assert Vec.len(Vec.sub(f.x, want.x)) < 1.0e-6 and Vec.len(Vec.sub(f.z, want.z)) < 1.0e-6
      assert Vec.len(Vec.sub(f.at, Vec.lerp(fa.at, fb.at, k))) < 1.0e-9
    end

    # The two signs of one turn: the near one.
    f = Frame.turn({0.0, 0.0, 1.0}, 170.0)
    g = Frame.turn({0.0, 0.0, 1.0}, -170.0)
    mid = Frame.blend(f, g, 0.5)
    assert Vec.len(Vec.sub(mid.x, {-1.0, 0.0, 0.0})) < 1.0e-6
  end
end
