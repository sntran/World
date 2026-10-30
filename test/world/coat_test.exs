defmodule World.Animals.CoatTest do
  use ExUnit.Case, async: true

  alias World.Animals.Coat

  # The chunks of a PNG file: `{type, data}`, each with a good CRC.
  defp chunks(<<>>), do: []

  defp chunks(<<size::32, type::binary-4, data::binary-size(size), crc::32, rest::binary>>) do
    assert crc == :erlang.crc32(type <> data)
    [{type, data} | chunks(rest)]
  end

  test "the texture of the coat: a gray PNG of 128 by 128 texels, the same each time" do
    {"image/png", png} = Coat.texture()
    assert Coat.texture() == {"image/png", png}
    <<137, 80, 78, 71, 13, 10, 26, 10, rest::binary>> = png
    [{"IHDR", ihdr}, {"IDAT", idat}, {"IEND", ""}] = chunks(rest)
    assert ihdr == <<128::32, 128::32, 8, 2, 0, 0, 0>>

    rows = :zlib.uncompress(idat)
    assert byte_size(rows) == 128 * (1 + 3 * 128)

    texels =
      for <<0, row::binary-size(3 * 128) <- rows>>, <<r, g, b <- row>> do
        assert r == g and g == b
        r
      end

    # From a dark strand (0.72) to white, and the mean of the texels.
    assert Enum.min(texels) >= round(0.72 * 255) and Enum.max(texels) <= 255
    assert Enum.max(texels) - Enum.min(texels) > 40
    assert_in_delta Coat.mean(), Enum.sum(texels) / (255 * length(texels)), 1.0e-12
    assert Coat.tile() == 0.04
  end
end
