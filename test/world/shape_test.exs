defmodule World.Animals.ShapeTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.Animals
  alias World.Animals.Shape
  alias World.Vec

  # The template of the wolf at rest: it has bones of the ears and six
  # bones of the tail.
  setup_all do
    {:ok, Animals.template("wolf")}
  end

  defp length(bones, name) do
    b = Enum.find(bones, &(&1.name == name))
    Vec.len(Vec.sub(b.tail, b.head))
  end

  defp bone(bones, name), do: Enum.find(bones, &(&1.name == name))

  test "the default numbers keep the template", c do
    {bones, points} = Shape.apply(c.bones, c.points, c.weights, %{}, c.template)
    for {p, q} <- Enum.zip(points, c.points), do: assert(Vec.len(Vec.sub(p, q)) < 1.0e-9)
    for {a, b} <- Enum.zip(bones, c.bones), do: assert(Vec.len(Vec.sub(a.head, b.head)) < 1.0e-9)
  end

  property "each number in its range: the bones stay joined, the lengths scale, the paws move as one and are on the ground",
           c do
    numbers = for {name, {lo, hi, _}} <- Shape.numbers(), do: {name, float(min: lo, max: hi)}

    check all n <- fixed_map(numbers), max_runs: 12 do
      {bones, points} = Shape.apply(c.bones, c.points, c.weights, n, c.template)
      by = Map.new(bones, &{&1.name, &1})

      # The tail of a bone is the head of the next bone of its chain.
      for {a, b} <- [
            {"pelvis", "spine_01"},
            {"spine_01", "neck_01"},
            {"neck_01", "head"},
            {"hind_upper_l", "hind_lower_l"},
            {"tail_01", "tail_02"}
          ],
          do: assert(Vec.len(Vec.sub(by[a].tail, by[b].head)) < 1.0e-9)

      assert_in_delta length(bones, "spine_01"), n["body_length"] * length(c.bones, "spine_01"), 1.0e-9
      assert_in_delta length(bones, "tail_02"), n["tail_length"] * length(c.bones, "tail_02"), 1.0e-9
      assert_in_delta length(bones, "ear_l"), n["ear_size"] * length(c.bones, "ear_l"), 1.0e-9

      # The bones of a leg have one length scale, near `leg_length`; the
      # lowest points of the four feet move by one height, and the lowest
      # is on the ground.
      for part <- ~w(front hind) do
        k = length(bones, "#{part}_upper_l") / length(c.bones, "#{part}_upper_l")
        assert k > 0.5 * n["leg_length"] and k < 1.5 * n["leg_length"]

        for b <- ~w(upper_r lower_l lower_r foot_l foot_r),
            do: assert_in_delta(length(bones, "#{part}_#{b}"), k * length(c.bones, "#{part}_#{b}"), 1.0e-9)
      end

      low = fn points, foot ->
        for({i, w} <- c.weights[foot], w >= 0.5, do: elem(Enum.at(points, i), 2)) |> Enum.min()
      end

      moves = for f <- ~w(front_foot_l front_foot_r hind_foot_l hind_foot_r), do: low.(points, f) - low.(c.points, f)
      assert Enum.max(moves) - Enum.min(moves) < 1.0e-9

      assert_in_delta Enum.min(for f <- ~w(front_foot_l front_foot_r hind_foot_l hind_foot_r), do: low.(points, f)),
                      0.0,
                      1.0e-9

      assert Enum.all?(points, fn {x, y, z} -> is_float(x) and is_float(y) and is_float(z) end)
    end
  end

  test "the ears turn down, the muzzle grows, the tail turns down", c do
    {rest, _} = Shape.apply(c.bones, c.points, c.weights, %{}, c.template)
    {droop, _} = Shape.apply(c.bones, c.points, c.weights, %{"ear_droop" => 80}, c.template)

    for ear <- ~w(ear_l ear_r) do
      assert elem(bone(droop, ear).tail, 2) < elem(bone(rest, ear).tail, 2)
      # The ear turns to its own side.
      assert abs(elem(bone(droop, ear).tail, 0)) > abs(elem(bone(rest, ear).tail, 0))
    end

    {long, _} = Shape.apply(c.bones, c.points, c.weights, %{"muzzle_length" => 1.5}, c.template)
    assert length(long, "head") > length(c.bones, "head")

    {low, _} = Shape.apply(c.bones, c.points, c.weights, %{"tail_down" => 120}, c.template)
    assert elem(bone(low, "tail_06").tail, 2) < elem(bone(rest, "tail_06").tail, 2)
  end

  test "the regions and the colors of the coat", c do
    regions = Shape.regions(c.bones, c.points, c.weights, c.eyes)
    assert Map.keys(regions) |> Enum.sort() == Enum.sort(Shape.regions())

    # The wolf has each region but the parts of the mouth that only a
    # template that marks them has (the primates).
    for {r, list} <- regions do
      assert length(list) == length(c.points)
      assert Enum.all?(list, &(&1 >= 0 and &1 <= 1.0 + 1.0e-9)), r
      assert Enum.any?(list, &(&1 >= 0.5)) == r not in ~w(ears_inner teeth mouth), r
    end

    # The fur lies to the back on the body, down on the legs, to the end
    # of the tail; a unit vector, or none for a point on no bone.
    dirs = Shape.fur_dirs(c.bones, c.points, c.weights)
    assert length(dirs) == length(c.points)
    on = fn bone -> for({d, i} <- Enum.with_index(dirs), Map.get(c.weights[bone], i, 0) == 1.0, do: d) end
    assert Enum.all?(on.("spine_01"), &(elem(&1, 1) < 0)) and Enum.all?(on.("front_lower_l"), &(elem(&1, 2) < 0))
    assert Enum.all?(dirs, &(abs(World.Vec.len(&1) - 1) < 1.0e-9))
    assert Shape.fur_dirs(c.bones, [{0, 0, 0} | c.points], %{}) |> Enum.uniq() == [{0.0, 0.0, 0.0}]

    plain = Shape.colors(regions, [10, 20, 30], %{})
    assert Enum.uniq(plain) == [{10.0, 20.0, 30.0}]
    socks = Shape.colors(regions, [0, 0, 0], %{"socks" => [255, 255, 255]})
    for {col, m} <- Enum.zip(socks, regions["socks"]), do: assert_in_delta(elem(col, 0), 255 * m, 1.0e-6)
  end

  test "the horns: up and to the back, or out to the sides", c do
    head = bone(c.bones, "head")
    top = for {i, w} <- c.weights["head"], w > 0.5, do: Enum.at(c.points, i)

    widths =
      for spread <- [0.0, 1.0] do
        {points, tris} = Shape.horns(head, 1.0, spread, top)
        assert length(points) == 2 * 9 * 8 and length(tris) == 2 * 8 * 8 * 2
        {{x0, _, _}, {x1, _, z1}} = Vec.bounds(Enum.map(points, &elem(&1, 0)))
        assert z1 > top |> Enum.map(&elem(&1, 2)) |> Enum.max()
        x1 - x0
      end

    assert Enum.at(widths, 1) > Enum.at(widths, 0) + 0.5
  end

  test "a primate: the arms, the skull, the muzzle to the front, and the coat" do
    %{bones: b, points: p, weights: w, template: t, eyes: eyes, marks: marks} = Animals.template("primate")
    {long, _} = Shape.apply(b, p, w, %{"arm_length" => 1.5}, t)
    assert_in_delta length(long, "upperarm_l"), 1.5 * length(b, "upperarm_l"), 1.0e-9
    assert_in_delta length(long, "thigh_l"), length(b, "thigh_l"), 1.0e-9

    # Narrow hands: the same length and thickness, the width across the
    # palm (the axis z of the bone) 0.6 of the rest.
    {narrow, thin} = Shape.apply(b, p, w, %{"hand_width" => 0.6}, t)
    assert_in_delta length(narrow, "hand_l"), length(b, "hand_l"), 1.0e-9
    {_, rest} = Shape.apply(b, p, w, %{}, t)
    hand = bone(b, "hand_l")
    along = Vec.norm(Vec.sub(hand.tail, hand.head))
    x = Vec.norm(Vec.sub({1.0, 0.0, 0.0}, Vec.scale(along, elem(along, 0))))
    palm = for {i, k} <- w["hand_l"], k > 0.9, do: i

    span = fn points, axis ->
      {lo, hi} = palm |> Enum.map(&Vec.dot(Enum.at(points, &1), axis)) |> Enum.min_max()
      hi - lo
    end

    # The palm points have a small weight on the fingers, which scale
    # across their own frames: these turn a little from the frame of the
    # hand.
    assert_in_delta span.(thin, x), span.(rest, x), 5.0e-4
    assert_in_delta span.(thin, Vec.cross(x, along)), 0.6 * span.(rest, Vec.cross(x, along)), 5.0e-4

    head = for {i, k} <- w["head"], k > 0.5, do: i
    top = fn points -> head |> Enum.map(&elem(Enum.at(points, &1), 2)) |> Enum.max() end
    front = fn points -> head |> Enum.map(&elem(Enum.at(points, &1), 1)) |> Enum.max() end
    {_, low} = Shape.apply(b, p, w, %{"cranium" => 0.6}, t)
    {_, snout} = Shape.apply(b, p, w, %{"muzzle_length" => 1.8}, t)
    # The skull goes down (by 0.4 of its height over the brow); the
    # muzzle goes to the front, and the top of the head stays.
    bone_head = bone(b, "head")
    len = Vec.len(Vec.sub(bone_head.tail, bone_head.head))
    over = top.(rest) - (elem(bone_head.head, 2) + t["brow"] * len)
    assert_in_delta top.(low), top.(rest) - 0.4 * over, 0.1 * over
    assert front.(snout) > front.(rest) + 0.2 * len
    assert_in_delta top.(snout), top.(rest), 1.0e-9

    # The face is the front of the head; the hands and the feet are the
    # socks.
    regions = Shape.regions(b, p, w)

    # The fur: the length of the coat, and over it the length of each
    # region (no fur on the face).
    fur = Shape.fur(regions, 0.03, %{"face" => 0.0})
    assert length(fur) == length(p) and Enum.max(fur) == 0.03

    for {l, m} <- Enum.zip(fur, regions["face"]), m == 1.0, do: assert(l == 0.0)

    face = for {m, i} <- Enum.with_index(regions["face"]), m > 0.5, do: elem(Enum.at(p, i), 1)
    assert face != [] and Enum.min(face) > elem(bone(b, "head").head, 1)
    hand = for {i, k} <- w["hand_l"], k > 0.9, do: Enum.at(regions["socks"], i)
    assert hand != [] and Enum.all?(hand, &(&1 > 0.9))

    # The hands, the shins and the forearms: on their bones only (the
    # douc has black hands, red shins and white forearms).
    for {region, bone} <- [{"hands", "hand_l"}, {"shins", "calf_r"}, {"forearms", "lowerarm_l"}] do
      on = for {i, k} <- w[bone], k > 0.9, do: Enum.at(regions[region], i)
      assert on != [] and Enum.all?(on, &(&1 > 0.9)), region
    end

    for {region, bone} <- [{"hands", "lowerarm_l"}, {"shins", "thigh_r"}, {"forearms", "upperarm_l"}] do
      assert Enum.all?(for({i, k} <- w[bone], k > 0.9, do: Enum.at(regions[region], i)), &(&1 < 0.1)), region
    end

    # The upper lids: over the eyes and in front of them, on the two
    # sides. With no eyes, no lids.
    assert Enum.all?(regions["lids"], &(&1 == 0.0))
    lids = for {m, i} <- Enum.with_index(Shape.regions(b, p, w, eyes)["lids"]), m > 0.5, do: Enum.at(p, i)
    eye = fn f -> eyes |> Enum.map(&f.(Enum.at(p, &1))) |> Enum.min_max() end
    {_, eye_top} = eye.(&elem(&1, 2))
    {eye_back, _} = eye.(&elem(&1, 1))
    assert Enum.any?(lids, &(elem(&1, 0) > 0)) and Enum.any?(lids, &(elem(&1, 0) < 0))
    assert Enum.all?(lids, &(elem(&1, 2) > eye_top - 0.02 and elem(&1, 1) > eye_back))

    # The cheeks: on the two sides of the head, not on the face.
    cheeks = for {m, i} <- Enum.with_index(regions["cheeks"]), m > 0.5, do: Enum.at(p, i)
    assert Enum.any?(cheeks, &(elem(&1, 0) > 0.03)) and Enum.any?(cheeks, &(elem(&1, 0) < -0.03))
    assert Enum.all?(Enum.zip(regions["cheeks"], regions["face"]), fn {c, f} -> c + f <= 1.0 + 1.0e-9 end)

    # The muzzle: at the front of the face, in front of the eyes. The ears
    # (a primate has no bones of the ears): far out on the two sides of
    # the head.
    muzzle = for {m, i} <- Enum.with_index(regions["muzzle"]), m > 0.5, do: Enum.at(p, i)
    assert muzzle != [] and Enum.all?(muzzle, &(elem(&1, 1) > eye_back))
    ears = for {m, i} <- Enum.with_index(regions["ears"]), m > 0.5, do: Enum.at(p, i)
    assert Enum.any?(ears, &(elem(&1, 0) > 0.8 * len)) and Enum.any?(ears, &(elem(&1, 0) < -0.8 * len))
    assert Enum.all?(ears, &(abs(elem(&1, 0)) > 0.8 * len))

    # The inside of the ears (a mark of the mesh): on the ears, on the two
    # sides; with no marks, none.
    assert Enum.all?(regions["ears_inner"], &(&1 == 0.0))
    inner = Shape.regions(b, p, w, eyes, marks)["ears_inner"]
    on = for {m, i} <- Enum.with_index(inner), m > 0.5, do: i
    assert Enum.any?(on, &(elem(Enum.at(p, &1), 0) > 0)) and Enum.any?(on, &(elem(Enum.at(p, &1), 0) < 0))
    assert Enum.all?(on, &(Enum.at(regions["ears"], &1) > 0.5))
  end
end
