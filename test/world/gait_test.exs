defmodule World.People.GaitTest do
  # The walks and the clip to stand of a person (plan 0021, D1 to D5, D7, D8).
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Frame, GLB, Vec}
  alias World.People.{Gait, Human, Motion, Pose, Skeleton}

  @people [
    man: [age: 35, gender: 1.0, height: 0.55],
    woman: [age: 30, gender: 0.0],
    old: [age: 75, gender: 1.0],
    child: [age: 8, gender: 0.0]
  ]

  setup_all do
    {:ok, skeletons: Map.new(@people, fn {who, opts} -> {who, Human.skeleton(opts)} end)}
  end

  test "each walk of each kind of person: the feet on the ground, no slide, a loop, in the limits of D1 and of its look",
       %{skeletons: skeletons} do
    for {who, opts} <- @people, kind <- Gait.kinds(), seed <- 1..6 do
      s = skeletons[who]
      clip = Pose.animation(kind, s.bones, age: opts[:age], seed: seed)
      # (The limits of D1 are for a walk at a normal speed; a walk under 1 m/s is a slow walk.)
      limits = if clip.extras["speed"] >= 1.0, do: :walk, else: :slow
      faults = Motion.faults(s, clip, speed: clip.extras["speed"], limits: limits)
      assert faults == [], "#{who} #{kind} #{seed}: #{inspect(faults)}"
    end
  end

  test "the clip to stand: a loop of 6 s, the feet stay, the weight goes from one foot to the other",
       %{skeletons: skeletons} do
    for {who, _} <- @people do
      s = skeletons[who]
      clip = Pose.animation("idle", s.bones)
      assert clip.name == "idle"
      # (The heels 12 cm to 20 cm apart, the feet a little out, the trunk upright, the hands relaxed.)
      assert Motion.faults(s, clip, limits: :stand) == [], "#{who}"
      keys = Motion.measure(s, clip)
      assert_in_delta List.last(keys).t, 6.0, 1.0e-9
      sides = Enum.map(keys, &elem(&1.hips, 0))
      assert Enum.max(sides) - Enum.min(sides) >= 0.04
      # (The head turns a little; the chest moves with the breath.)
      heads = Enum.map(keys, & &1.world["head"].x)
      assert Enum.max(for a <- heads, b <- heads, do: Vec.len(Vec.sub(a, b))) > 0.1
    end
  end

  # The measures of each walk of a person (the seed 1): the step width (m), the most angle of the line from the
  # shoulder to the hand to the front and to the back, and the lean of the trunk, at each key.
  defp look(s, kind, opts) do
    clip = Pose.animation(kind, s.bones, Keyword.put(opts, :seed, 1))
    keys = Motion.measure(s, clip, speed: (clip[:extras] || %{})["speed"] || 0.0)
    heel = fn side -> for k <- keys, elem(k.feet[side].heel, 2) <= 0.01, do: elem(k.feet[side].heel, 0) end
    mean = fn list -> Enum.sum(list) / length(list) end
    arms = for k <- keys, side <- [:l, :r], do: k.arm[side]

    %{
      width: abs(mean.(heel.(:l)) - mean.(heel.(:r))),
      front: Enum.max(arms),
      back: -Enum.min(arms),
      lean: Enum.map(keys, & &1.lean),
      keys: keys
    }
  end

  test "the look of a walk: a narrow step, the arms to the front and to the back, the trunk upright",
       %{skeletons: skeletons} do
    looks =
      for {who, opts} <- @people,
          kind <- ~w(walk stroll idle),
          into: %{},
          do: {{who, kind}, look(skeletons[who], kind, opts)}

    for {who, opts} <- @people do
      {walk, stroll, idle} = {looks[{who, "walk"}], looks[{who, "stroll"}], looks[{who, "idle"}]}
      # (The step width: 6 cm to 13 cm, and less at a higher speed; the feet of the clip to stand 12 cm to 20 cm
      # apart.)
      assert walk.width >= 0.06 and walk.width < stroll.width and stroll.width <= 0.13, "#{who}"
      assert idle.width >= 0.12 and idle.width <= 0.2, "#{who}"
      # (The arms of the walk of a person under 60: 15° to 25° to the front, 8° to 20° to the back; less in the
      # stroll.)
      if opts[:age] < 60,
        do: assert(walk.front >= 15 and walk.front <= 25 and walk.back >= 8 and walk.back <= 20, "#{who}")

      assert stroll.front < walk.front and stroll.back < walk.back, "#{who}"
      # (The trunk: at most 4° to the front in the walk, 3° in the stroll.)
      assert Enum.max(walk.lean) <= 4 and Enum.max(stroll.lean) <= 3 and Enum.min(stroll.lean) >= 0, "#{who}"
    end

    # (An old man swings his arms less than a man of 35; his back bends as a bend of the spine, not as a lean of
    # the trunk.)
    {old, man} = {looks[{:old, "walk"}], looks[{:man, "walk"}]}
    assert old.front + old.back < man.front + man.back
    curve = fn %{keys: [k | _]} -> bend(k.world) end
    assert curve.(old) >= curve.(man) + 4
  end

  # The bend of the spine: the angle (degrees, in the plane from the back to the front) from the line of the lower
  # back (the pelvis to spine_02) to the line of the upper back (spine_03 to the neck), to the front for more than 0.
  defp bend(w) do
    angle = fn a, b ->
      {_, y, z} = Vec.sub(w[b].at, w[a].at)
      :math.atan2(y, z) * 180 / :math.pi()
    end

    angle.("spine_03", "neck_01") - angle.("pelvis", "spine_02")
  end

  test "the clip to stand has 12 keys each second, and it is as smooth as a clip of 48 keys each second (R7)",
       %{skeletons: skeletons} do
    s = skeletons.man
    {few, many} = {Pose.animation("idle", s.bones), Gait.idle(s.bones, fps: 48)}
    assert length(hd(few.channels).times) == 6 * 12 + 1
    # (Each point of each bone, at each key of the clip of 48 keys: the clip of 12 keys with straight lines between
    # its keys, as a project plays it, is within 1 mm.)
    for {{t, fine}, {_, coarse}} <- Enum.zip(Motion.frames(s, many), Motion.frames(s, sampled(few, many))) do
      for {name, f} <- fine do
        for p <- [f.at, Skeleton.tip(s, fine, name)],
            q = if(p == f.at, do: coarse[name].at, else: Skeleton.tip(s, coarse, name)) do
          assert Vec.len(Vec.sub(p, q)) < 0.001, "#{name} at #{t} s"
        end
      end
    end
  end

  # A clip at the times of another clip: each value between its two keys, on a straight line (a turn on the
  # shortest arc).
  defp sampled(clip, at) do
    times = hd(at.channels).times

    channels =
      for c <- clip.channels do
        keys = Enum.zip(c.times, c.values)

        values =
          for t <- times do
            [{t0, a}, {t1, b}] =
              keys |> Enum.chunk_every(2, 1, :discard) |> Enum.find(fn [{t0, _}, {t1, _}] -> t >= t0 and t <= t1 end)

            u = (t - t0) / (t1 - t0)
            if c.path == :rotation, do: Frame.blend(a, b, u), else: Vec.add(a, Vec.scale(Vec.sub(b, a), u))
          end

        %{c | times: times, values: values}
      end

    %{clip | channels: channels}
  end

  test "the numbers of a walk (D3 to D5): the speed, the step from the legs, the cadence, the age and the seed",
       %{skeletons: skeletons} do
    man = skeletons.man
    walk = Gait.numbers(man, "walk", age: 35)
    stroll = Gait.numbers(man, "stroll", age: 35)
    # (The walk of a man of the rules is about 1.2 m/s, his stroll about 0.8 m/s.)
    assert_in_delta walk.speed, 1.2, 0.06
    assert_in_delta stroll.speed, 0.8, 0.06
    assert_in_delta walk.speed, walk.stride * walk.cadence / 120, 1.0e-9

    for {who, opts} <- @people, kind <- Gait.kinds(), seed <- 1..20 do
      n = Gait.numbers(skeletons[who], kind, age: opts[:age], seed: seed)
      assert n.cadence >= 80 and n.cadence <= 110, "#{who} #{kind} #{seed}"
    end

    # (The step comes from the legs: a child takes shorter steps. An old man takes shorter steps than his legs
    # give a man of 35, and more slowly.)
    {_, _, hip} = man.rest["thigh_l"].at
    old = skeletons.old
    {_, _, old_hip} = old.rest["thigh_l"].at
    assert Gait.numbers(skeletons.child, "walk").step < 0.7 * walk.step
    young = Gait.numbers(old, "walk", age: 35)
    aged = Gait.numbers(old, "walk", age: 75)
    assert aged.step < 0.9 * young.step and aged.cadence < young.cadence
    assert_in_delta young.step / old_hip, walk.step / hip, 0.1 * walk.step / hip

    # (Two seeds: other numbers, in small limits.)
    other = Gait.numbers(man, "walk", age: 35, seed: 2)
    assert other != walk
    assert abs(other.step / walk.step - 1) < 0.1 and abs(other.cadence / walk.cadence - 1) < 0.08
  end

  test "the keys (D7) and the extras of a walk (D4); the names of the clips (R5)", %{skeletons: skeletons} do
    s = skeletons.man
    clip = Pose.animation("walk", s.bones, age: 35)
    assert clip.name == "walk"
    n = Gait.numbers(s, "walk", age: 35)
    [c | _] = clip.channels
    # (24 keys each second, the last at the time of a cycle.)
    assert_in_delta List.last(c.times), n.period, 1.0e-9
    assert_in_delta (length(c.times) - 1) / n.period, 24, 1.0
    assert %{"speed" => speed, "stride" => stride, "cadence" => cadence, "contacts" => contacts} = clip.extras
    assert_in_delta speed, n.speed, 1.0e-3
    assert_in_delta stride, n.stride, 1.0e-3
    assert_in_delta cadence, n.cadence, 1.0e-3
    # (The contact of the heel and the toe-off of each foot, in s: the right foot half a cycle after the left.)
    t = n.period
    assert_in_delta contacts["l"]["heel"], 0.0, 1.0e-3
    assert_in_delta contacts["l"]["toe_off"], 0.6 * t, 1.0e-3
    assert_in_delta contacts["r"]["heel"], 0.5 * t, 1.0e-3
    assert_in_delta contacts["r"]["toe_off"], 0.1 * t, 1.0e-3

    assert Pose.walks() == ~w(idle stroll walk)
    # (The clips of Gait with no option: a person of 30 years and the seed 1.)
    assert Gait.walk(s.bones, "stroll") == Pose.animation("stroll", s.bones, age: 30, seed: 1)
    assert Gait.idle(s.bones) == Pose.animation("idle", s.bones)
  end

  test "a person who walks: the extras of the clip in the GLB and in parts.json" do
    traveler = Detail.with(:far, &World.People.traveler/0)
    scene = Build.scene(traveler, level: :far)
    [walk, %{name: "blink"}] = scene.animations
    assert walk.extras["speed"] > 1.0
    json = World.GLBHelper.json(GLB.encode(scene))
    [glb_walk, glb_blink] = json["animations"]
    assert glb_walk["extras"] == walk.extras and not Map.has_key?(glb_blink, "extras")
    parts = Build.parts_file("traveler", traveler)
    assert parts["animations"] == [Map.put(walk.extras, "name", "walk")]
    # (A model with no clip that has extras has no key animations.)
    refute Map.has_key?(Build.parts_file("man", Detail.with(:far, &World.People.man/0)), "animations")
    refute Map.has_key?(Build.parts_file("rider", Detail.with(:far, &World.People.rider/0)), "animations")
    # (A group: the beats of its routine, one time.)
    group = Detail.with(:far, fn -> World.People.exercise("aerobics", count: 1) end)

    assert [%{"name" => "aerobics", "bpm" => 120, "beats" => [+0.0 | _]}] =
             Build.parts_file("group", group)["animations"]
  end
end
