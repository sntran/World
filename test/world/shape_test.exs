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

  property "each number in its range: the bones stay joined, the lengths scale, the paws are on the ground", c do
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

      assert_in_delta length(bones, "front_lower_l"), n["leg_length"] * length(c.bones, "front_lower_l"), 1.0e-9
      assert_in_delta length(bones, "spine_01"), n["body_length"] * length(c.bones, "spine_01"), 1.0e-9
      assert_in_delta length(bones, "tail_02"), n["tail_length"] * length(c.bones, "tail_02"), 1.0e-9
      assert_in_delta length(bones, "ear_l"), n["ear_size"] * length(c.bones, "ear_l"), 1.0e-9

      feet =
        for {b, m} <- c.weights, String.contains?(b, "_foot_"), {i, w} <- m, w >= 0.5, do: elem(Enum.at(points, i), 2)

      assert_in_delta Enum.min(feet), 0.0, 1.0e-9
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
    regions = Shape.regions(c.bones, c.points, c.weights)
    assert Map.keys(regions) |> Enum.sort() == Enum.sort(Shape.regions())

    for {r, list} <- regions do
      assert length(list) == length(c.points)
      assert Enum.all?(list, &(&1 >= 0 and &1 <= 1.0 + 1.0e-9)), r
      assert Enum.any?(list, &(&1 >= 0.5)), r
    end

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
    %{bones: b, points: p, weights: w, template: t} = Animals.template("primate")
    {long, _} = Shape.apply(b, p, w, %{"arm_length" => 1.5}, t)
    assert_in_delta length(long, "upperarm_l"), 1.5 * length(b, "upperarm_l"), 1.0e-9
    assert_in_delta length(long, "thigh_l"), length(b, "thigh_l"), 1.0e-9

    head = for {i, k} <- w["head"], k > 0.5, do: i
    top = fn points -> head |> Enum.map(&elem(Enum.at(points, &1), 2)) |> Enum.max() end
    front = fn points -> head |> Enum.map(&elem(Enum.at(points, &1), 1)) |> Enum.max() end
    {_, rest} = Shape.apply(b, p, w, %{}, t)
    {_, low} = Shape.apply(b, p, w, %{"cranium" => 0.6}, t)
    {_, snout} = Shape.apply(b, p, w, %{"muzzle_length" => 1.8}, t)
    # The skull goes down; the muzzle goes to the front, and the top of
    # the head stays.
    assert top.(low) < top.(rest) - 0.03
    assert front.(snout) > front.(rest) + 0.03
    assert_in_delta top.(snout), top.(rest), 1.0e-9

    # The face is the front of the head; the hands and the feet are the
    # socks.
    regions = Shape.regions(b, p, w)
    face = for {m, i} <- Enum.with_index(regions["face"]), m > 0.5, do: elem(Enum.at(p, i), 1)
    assert face != [] and Enum.min(face) > elem(bone(b, "head").head, 1)
    hand = for {i, k} <- w["hand_l"], k > 0.9, do: Enum.at(regions["socks"], i)
    assert hand != [] and Enum.all?(hand, &(&1 > 0.9))
  end
end
