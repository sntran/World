defmodule World.Sculpt.TextureTest do
  # The surfaces of the edits of a sculpture (plan 0012, D3).
  use ExUnit.Case, async: true

  alias World.Sculpt.Texture

  defp spread(values) do
    mean = Enum.sum(values) / length(values)
    :math.sqrt(Enum.sum(for v <- values, do: (v - mean) ** 2) / length(values))
  end

  test "the noise: from 0 to 1, the same for the same place, smooth, with a change for each unit" do
    :rand.seed(:exsss, {1, 2, 3})
    places = for _ <- 1..2_000, do: {:rand.uniform() * 40 - 20, :rand.uniform() * 40 - 20, :rand.uniform() * 40 - 20}
    values = for {x, y, z} <- places, do: Texture.noise(x, y, z)
    assert Enum.all?(values, &(&1 >= 0.0 and &1 <= 1.0))
    assert values == for({x, y, z} <- places, do: Texture.noise(x, y, z))
    assert_in_delta Enum.sum(values) / 2_000, 0.5, 0.03
    assert spread(values) > 0.12
    # A small step is a small change; the values at the points of the grid are the values of the grid.
    for {x, y, z} <- Enum.take(places, 200) do
      assert abs(Texture.noise(x + 0.01, y, z) - Texture.noise(x, y, z)) < 0.03
      assert abs(Texture.noise(x, y, z + 0.01) - Texture.noise(x, y, z)) < 0.03
    end
  end

  test "each kind: a name, a scale, and numbers in their ranges at each place" do
    assert Texture.kinds() ==
             ~w(bark brushed cast concrete fabric hair leather leaves palm plaster rubber rust stone weave wood)

    assert Texture.kind("wood") == {:wood, 0.006} and Texture.kind("glass") == nil
    :rand.seed(:exsss, {4, 5, 6})

    for name <- Texture.kinds(), {kind, scale} = Texture.kind(name) do
      assert scale >= 0.001 and scale < 0.2

      seen =
        for _ <- 1..600 do
          q = {:rand.uniform() * 30 - 15, :rand.uniform() * 30 - 15, :rand.uniform() * 30 - 15}
          n = Enum.random([{1.0, 0.0, 0.0}, {0.0, -1.0, 0.0}, {0.0, 0.0, 1.0}, {0.6, 0.0, 0.8}])
          {height, tone, rough, metal, to} = Texture.at(kind, q, n)
          # The relief is less than half of a mark; the color does not go to black or past two times.
          assert abs(height) <= 0.5 and tone > 0.3 and tone < 1.7 and abs(rough) <= 0.4, inspect({name, q})
          assert metal >= 0.0 and metal <= 1.0
          assert to == nil or (elem(to, 1) >= 0.0 and elem(to, 1) <= 1.0)
          assert Texture.at(kind, q, n) == {height, tone, rough, metal, to}
          {height, tone}
        end

      # The surface is not flat, and its color is not even.
      assert spread(Enum.map(seen, &elem(&1, 0))) > 0.004, name
      assert spread(Enum.map(seen, &elem(&1, 1))) > 0.01, name
    end
  end

  test "hair has strands that go out and down from the z; palm has 40 blades round the z (plan 0017)" do
    # The height of a strand: 0 to 1; it changes little along the strand, and much across it.
    {along, across} =
      for i <- 1..200, reduce: {0.0, 0.0} do
        {along, across} ->
          a = i * 0.37
          {x, y, z} = {60 * :math.cos(a), 60 * :math.sin(a), -i * 0.5}
          here = Texture.strand({x, y, z})
          assert here >= 0.0 and here <= 1.0
          # (Along: out and down by 3 units. Across: round the z by 3 units.)
          down = Texture.strand({x * 1.03, y * 1.03, z - 1.2})
          side = Texture.strand({60 * :math.cos(a + 0.05), 60 * :math.sin(a + 0.05), z})
          {along + abs(down - here), across + abs(side - here)}
      end

    assert across > 4 * along
    # On the z itself, a strand has a height too.
    assert Texture.strand({0.0, 0.0, 3.0}) >= 0.0
    # The relief and the tone of the hair are from the height of the strand.
    {height, tone, _, 1.0, nil} = Texture.at(:hair, {40.0, 20.0, -5.0}, {0.0, 0.0, 1.0})
    assert_in_delta height, 0.5 * (Texture.strand({40.0, 20.0, -5.0}) - 0.5), 1.0e-12
    assert tone > 0.6

    # Palm: a dark line between two blades (each 9 degrees), and blades of different tones.
    at = fn deg ->
      Texture.at(
        :palm,
        {50 * :math.cos(deg * :math.pi() / 180), 50 * :math.sin(deg * :math.pi() / 180), -20.0},
        {0.0, 0.0, 1.0}
      )
    end

    {seam_height, seam_tone, _, _, _} = at.(9.0)
    {_, mid_tone, _, _, _} = at.(13.5)
    assert seam_tone < mid_tone - 0.1 and seam_height < -0.2
    tones = for k <- 0..39, do: at.(k * 9 + 4.5) |> elem(1) |> Float.round(2)
    assert length(Enum.uniq(tones)) > 10
  end

  test "wood has rings across its grain; a weave has strips over and under; rust takes the metal away" do
    # Over two rings, the color of wood changes much less along the grain (z) than across it.
    across = for i <- 0..400, do: elem(Texture.at(:wood, {i * 0.005, 0.3, 2.0}, {0.0, 1.0, 0.0}), 1)
    along = for i <- 0..400, do: elem(Texture.at(:wood, {1.3, 0.3, i * 0.005}, {0.0, 1.0, 0.0}), 1)
    assert spread(across) > 2 * spread(along)

    # A weave: the middle of a strip is high, its edge is low; the next square has the other strip on top.
    {top, _, _, _, _} = Texture.at(:weave, {0.5, 0.5, 9.0}, {0.0, 0.0, 1.0})
    {edge, _, _, _, _} = Texture.at(:weave, {0.5, 0.02, 9.0}, {0.0, 0.0, 1.0})
    {side, _, _, _, _} = Texture.at(:weave, {1.02, 0.5, 9.0}, {0.0, 0.0, 1.0})
    assert top > 0.15 and edge < 0.03 and side < 0.03
    # (The z of a weave does not change it: it is flat across z, pressed to the shape.)
    assert Texture.at(:weave, {0.5, 0.5, 9.0}, {0.0, 0.0, 1.0}) == Texture.at(:weave, {0.5, 0.5, -3.0}, {1.0, 0.0, 0.0})

    # A cloth has its threads on the side that the surface faces: a wall along x has them in y and z.
    assert Texture.at(:fabric, {7.7, 0.5, 0.5}, {1.0, 0.0, 0.0}) ==
             Texture.at(:fabric, {1.1, 0.5, 0.5}, {-1.0, 0.1, 0.0})

    assert Texture.at(:fabric, {0.5, 7.7, 0.5}, {0.0, 1.0, 0.0}) ==
             Texture.at(:fabric, {0.5, 1.1, 0.5}, {0.2, 1.0, 0.0})

    assert Texture.at(:fabric, {0.5, 0.5, 7.7}, {0.0, 0.0, 1.0}) ==
             Texture.at(:fabric, {0.5, 0.5, 1.1}, {0.0, 0.3, -1.0})

    # Rust: where it is, the color goes to brown and the metal goes away.
    :rand.seed(:exsss, {7, 8, 9})

    parts =
      for _ <- 1..500 do
        q = {:rand.uniform() * 30, :rand.uniform() * 30, :rand.uniform() * 30}
        {_, _, rough, metal, {{r, g, b}, part}} = Texture.at(:rust, q, {0.0, 0.0, 1.0})
        assert r > g and g > b
        assert_in_delta metal, 1.0 - part, 1.0e-9
        assert_in_delta rough, 0.35 * part, 1.0e-9
        part
      end

    assert Enum.any?(parts, &(&1 == 0.0)) and Enum.any?(parts, &(&1 == 1.0))
  end
end
