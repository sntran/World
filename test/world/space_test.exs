defmodule World.Animals.SpaceTest do
  use ExUnit.Case, async: true

  alias World.Animals
  alias World.Animals.{Shape, Space}
  alias World.Vec

  defp bone(bones, name), do: Enum.find(bones, &(&1.name == name))

  test "the shape space of the wolf: a move for each point, the components, the templates it comes from" do
    sp = Space.get("wolf")
    %{points: points} = Animals.template("wolf")
    assert length(sp["mean"]) == length(points)
    assert length(sp["components"]) == 10
    sigmas = Enum.map(sp["components"], & &1["sigma"])
    assert sigmas == Enum.sort(sigmas, :desc) and Enum.all?(sigmas, &(&1 > 0))
    assert Map.keys(sp["animals"]) |> Enum.sort() == ~w(alpaca bull cow deer donkey fox horse husky shiba_inu stag wolf)

    # No coefficient: the mean; a coefficient: the mean and that many
    # sigmas of its component.
    mean = Space.moves(sp, [])
    assert mean == Enum.map(sp["mean"], &List.to_tuple/1)
    [first | _] = sp["components"]
    [{a, b, c} | _] = Space.moves(sp, [2.0])
    [[x, y, z] | _] = first["vectors"]
    {ma, mb, mc} = hd(mean)
    assert_in_delta a, ma + 2 * first["sigma"] * x, 1.0e-9
    assert_in_delta b, mb + 2 * first["sigma"] * y, 1.0e-9
    assert_in_delta c, mc + 2 * first["sigma"] * z, 1.0e-9

    # Each number of each template is in its range (an order can give it).
    for {_, %{"shape" => shape}} <- sp["animals"], {k, v} <- shape do
      {lo, hi, _} = Shape.numbers()[k]
      assert v >= lo and v <= hi, k
    end

    assert Animals.space("wolf") == sp and Animals.space("cat") == nil
    assert Space.get("cat") == nil
    refute Space.__mix_recompile__?()
  end

  test "a move of the space: in the axes of the bone that moves the point most, scaled as that bone" do
    %{bones: bones, points: points, weights: weights, template: t} = Animals.template("wolf")
    {_, rest} = Shape.apply(bones, points, weights, %{}, t)
    zero = List.duplicate({0.0, 0.0, 0.0}, length(points))
    assert {_, ^rest} = Shape.apply(bones, points, weights, %{}, t, zero)

    # One point of the tail, 1 along its bone: with tail_length 2, 2
    # along the bone (the tail is not turned).
    {i, _} = weights["tail_04"] |> Enum.max_by(&elem(&1, 1))
    one = List.replace_at(zero, i, {0.0, 1.0, 0.0})
    {_, moved} = Shape.apply(bones, points, weights, %{"tail_length" => 2.0}, t, one)
    {_, long} = Shape.apply(bones, points, weights, %{"tail_length" => 2.0}, t)
    {_, _, y, _} = Shape.frame(bone(bones, "tail_04"))
    assert_in_delta Vec.dot(Vec.sub(Enum.at(moved, i), Enum.at(long, i)), y), 2.0, 1.0e-6
    assert Enum.at(moved, i + 1) == Enum.at(long, i + 1) or i + 1 == length(points)
  end

  test "neck_up turns the neck and the head up, head_down turns the head down" do
    %{bones: bones, points: points, weights: weights, template: t} = Animals.template("wolf")
    {b0, _} = Shape.apply(bones, points, weights, %{}, t)
    {up, _} = Shape.apply(bones, points, weights, %{"neck_up" => 40}, t)
    {down, _} = Shape.apply(bones, points, weights, %{"head_down" => 40}, t)
    z = fn bs, name, k -> elem(Map.fetch!(bone(bs, name), k), 2) end
    assert z.(up, "head", :tail) > z.(b0, "head", :tail) + 0.01
    assert z.(down, "head", :tail) < z.(b0, "head", :tail) - 0.01
    # The joint of the neck and the body stays; the head stays on the neck.
    assert_in_delta z.(up, "neck_01", :head), z.(b0, "neck_01", :head), 1.0e-9
    assert Vec.len(Vec.sub(bone(down, "head").head, bone(down, "neck_01").tail)) < 1.0e-9
  end

  test "an animal from the space: the wolf with the numbers and the coefficients of the horse" do
    horse = Animals.space("wolf")["animals"]["horse"]
    a = Animals.animal("wolf", shape: horse["shape"], space: horse["space"])
    b = Animals.animal("wolf", shape: horse["shape"])

    points = fn f ->
      for(n <- World.Build.scene(f).nodes, p <- n.primitives, p.material == :fur, do: p.positions) |> hd()
    end

    assert points.(a) != points.(b)

    assert_raise ArgumentError, ~r/the template primate has no shape space/, fn ->
      Animals.animal("macaque", space: [1.0])
    end
  end
end
