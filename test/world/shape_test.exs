defmodule World.Animals.ShapeTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.Animals.Shape
  alias World.Vec

  # The template: the bones of World on the mesh of the dog, in the units
  # of the mesh.
  setup_all do
    t = Path.join([:code.priv_dir(:world), "animals", "templates", "quadruped.json"]) |> File.read!() |> JSON.decode!()
    data = Path.join([:code.priv_dir(:world), "animals", "meshes", "dog.json"]) |> File.read!() |> JSON.decode!()
    to_world = Map.new(t["bones"], fn {world, file} -> {file, world} end)
    file = Map.new(data["bones"], &{&1["name"], &1})
    next = &World.Animals.Quadruped.next/1

    bones =
      for name <- World.Animals.Quadruped.bones(), f = file[t["bones"][name]], f != nil do
        n = next.(name)
        tail = if n && t["bones"][n], do: file[t["bones"][n]]["head"], else: f["tail"]

        %{
          name: name,
          parent: f["parent"] && to_world[f["parent"]],
          head: List.to_tuple(f["head"]),
          tail: List.to_tuple(tail)
        }
      end

    weights = Map.new(data["weights"], fn {b, l} -> {to_world[b], Map.new(l, &List.to_tuple/1)} end)
    {:ok, t: t, bones: bones, points: Enum.map(data["points"], &List.to_tuple/1), weights: weights}
  end

  defp length(bones, name) do
    b = Enum.find(bones, &(&1.name == name))
    Vec.len(Vec.sub(b.tail, b.head))
  end

  test "the default numbers keep the template", c do
    {bones, points} = Shape.apply(c.bones, c.points, c.weights, %{}, c.t)
    for {p, q} <- Enum.zip(points, c.points), do: assert(Vec.len(Vec.sub(p, q)) < 1.0e-9)
    for {a, b} <- Enum.zip(bones, c.bones), do: assert(Vec.len(Vec.sub(a.head, b.head)) < 1.0e-9)
  end

  property "each number in its range: the bones stay joined, the lengths scale, the paws are on the ground", c do
    numbers = for {name, {lo, hi, _}} <- Shape.numbers(), do: {name, float(min: lo, max: hi)}

    check all n <- fixed_map(numbers), max_runs: 12 do
      {bones, points} = Shape.apply(c.bones, c.points, c.weights, n, c.t)
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

      feet =
        for {b, m} <- c.weights, String.contains?(b, "_foot_"), {i, w} <- m, w >= 0.5, do: elem(Enum.at(points, i), 2)

      assert_in_delta Enum.min(feet), 0.0, 1.0e-9
      assert Enum.all?(points, fn {x, y, z} -> is_float(x) and is_float(y) and is_float(z) end)
    end
  end

  test "the ears turn up, the muzzle grows, the tail turns down", c do
    regions = Shape.regions(c.bones, c.points, c.weights, c.t)
    ears = for {m, i} <- Enum.with_index(regions["ears"]), m > 0.5, do: i
    assert ears != []
    {_, up} = Shape.apply(c.bones, c.points, c.weights, %{"ear_up" => 1.0}, c.t)
    {_, down} = Shape.apply(c.bones, c.points, c.weights, %{}, c.t)
    z = fn points -> ears |> Enum.map(&elem(Enum.at(points, &1), 2)) |> Enum.max() end
    assert z.(up) > z.(down)

    {long, _} = Shape.apply(c.bones, c.points, c.weights, %{"muzzle_length" => 1.5}, c.t)
    assert length(long, "head") > length(c.bones, "head")

    {low, _} = Shape.apply(c.bones, c.points, c.weights, %{"tail_down" => 120}, c.t)
    tip = fn bones -> Enum.find(bones, &(&1.name == "tail_04")).tail |> elem(2) end
    {rest, _} = Shape.apply(c.bones, c.points, c.weights, %{}, c.t)
    assert tip.(low) < tip.(rest)
  end

  test "the regions and the colors of the coat", c do
    regions = Shape.regions(c.bones, c.points, c.weights, c.t)
    assert Map.keys(regions) |> Enum.sort() == Enum.sort(Shape.regions())

    for {r, list} <- regions do
      assert length(list) == length(c.points)
      assert Enum.all?(list, &(&1 >= 0 and &1 <= 1.0 + 1.0e-9)), r
      assert Enum.any?(list, &(&1 > 0.5)), r
    end

    plain = Shape.colors(regions, [10, 20, 30], %{})
    assert Enum.uniq(plain) == [{10.0, 20.0, 30.0}]
    socks = Shape.colors(regions, [0, 0, 0], %{"socks" => [255, 255, 255]})
    for {col, m} <- Enum.zip(socks, regions["socks"]), do: assert_in_delta(elem(col, 0), 255 * m, 1.0e-6)
  end
end
