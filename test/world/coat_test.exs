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
    {"image/png", png} = Coat.texture()
    assert Coat.texture() == {"image/png", png}
    <<137, 80, 78, 71, 13, 10, 26, 10, rest::binary>> = png
    [{"IHDR", ihdr}, {"IDAT", idat}, {"IEND", ""}] = chunks(rest)
    assert ihdr == <<128::32, 128::32, 8, 6, 0, 0, 0>>

    rows = :zlib.uncompress(idat)
    assert byte_size(rows) == 128 * (1 + 4 * 128)
    texels = for <<0, row::binary-size(4 * 128) <- rows>>, <<r, g, b, a <- row>>, do: {r, g, b, a}
    assert Enum.all?(texels, fn {r, g, b, _} -> r == g and g == b end)

    # The alpha: from 0.5 to 1, one value along each strand.
    alphas = Enum.map(texels, &elem(&1, 3))
    assert Enum.min(alphas) >= 127 and Enum.max(alphas) > 245 and length(Enum.uniq(alphas)) > 50
    texels = Enum.map(texels, &elem(&1, 0))

    # From a dark strand (0.72) to white, and the mean of the texels.
    assert Enum.min(texels) >= round(0.72 * 255) and Enum.max(texels) <= 255
    assert Enum.max(texels) - Enum.min(texels) > 40
    assert_in_delta Coat.mean(), Enum.sum(texels) / (255 * length(texels)), 1.0e-12
    assert Coat.tile() == 0.04
  end
end
