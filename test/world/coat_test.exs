defmodule World.Animals.CoatTest do
  use ExUnit.Case, async: true

  alias World.Animals.Coat

  # The chunks of a PNG file: `{type, data}`, each with a good CRC.
  defp chunks(<<>>), do: []

  defp chunks(<<size::32, type::binary-4, data::binary-size(size), crc::32, rest::binary>>) do
    assert crc == :erlang.crc32(type <> data)
    [{type, data} | chunks(rest)]
  end

  test "the texture of the coat: a gray PNG of 128 by 128 texels with an alpha, the same each time" do
    for kind <- Coat.kinds() do
      {"image/png", png} = Coat.texture(kind)
      assert Coat.texture(kind) == {"image/png", png}
      <<137, 80, 78, 71, 13, 10, 26, 10, rest::binary>> = png
      [{"IHDR", ihdr}, {"IDAT", idat}, {"IEND", ""}] = chunks(rest)
      assert ihdr == <<128::32, 128::32, 8, 6, 0, 0, 0>>

      rows = :zlib.uncompress(idat)
      assert byte_size(rows) == 128 * (1 + 4 * 128)
      texels = for <<0, row::binary-size(4 * 128) <- rows>>, <<r, g, b, a <- row>>, do: {r, g, b, a}
      assert Enum.all?(texels, fn {r, g, b, _} -> r == g and g == b end)

      # The alpha: from 0.5 to 1, one value along each strand (of wool:
      # the height of the lock).
      alphas = Enum.map(texels, &elem(&1, 3))
      assert Enum.min(alphas) >= 127 and Enum.max(alphas) > 245 and length(Enum.uniq(alphas)) > 50, kind
      texels = Enum.map(texels, &elem(&1, 0))

      # From a dark strand (0.72) to white, and the mean of the texels.
      assert Enum.min(texels) >= round(0.72 * 255) and Enum.max(texels) <= 255
      assert Enum.max(texels) - Enum.min(texels) > 40, kind
      assert_in_delta Coat.mean(kind), Enum.sum(texels) / (255 * length(texels)), 1.0e-12
    end

    # Four kinds, each with its own texture; `long` is the default.
    assert Coat.kinds() == ~w(short long curly wool)
    assert Coat.texture() == Coat.texture("long") and Coat.mean() == Coat.mean("long")
    assert length(Enum.uniq(Enum.map(Coat.kinds(), &Coat.texture/1))) == 4
    assert Enum.map(Coat.kinds(), &Coat.tile/1) == [0.02, 0.04, 0.04, 0.09] and Coat.tile() == 0.04
  end

  # The values of the texels of a kind, as rows.
  defp values(kind) do
    {_, <<_::binary-8, rest::binary>>} = Coat.texture(kind)
    [_, {"IDAT", idat}, _] = chunks(rest)
    for <<0, row::binary-size(4 * 128) <- :zlib.uncompress(idat)>>, do: for(<<g, _, _, _ <- row>>, do: g)
  end

  test "the kinds of hair: straight strands, curls and locks of wool" do
    # Straight strands: a texel is near the texel under it more than the
    # texel next to it; less so for short hair, much less for curls.
    near = fn rows, {dx, dy} ->
      t = List.to_tuple(Enum.map(rows, &List.to_tuple/1))
      at = &elem(elem(t, rem(&2 + 128, 128)), rem(&1 + 128, 128))
      Enum.sum(for x <- 0..127, y <- 0..127, do: abs(at.(x, y) - at.(x + dx, y + dy))) / (128 * 128)
    end

    ratio = fn kind ->
      rows = values(kind)
      near.(rows, {0, 1}) / near.(rows, {1, 0})
    end

    assert ratio.("long") < ratio.("short") and ratio.("short") < 0.6
    assert ratio.("curly") > ratio.("long") + 0.1

    # Wool: the same across and along (locks, not strands).
    assert_in_delta ratio.("wool"), 1.0, 0.3
  end
end
