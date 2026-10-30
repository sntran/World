defmodule World.Animals.Coat do
  @moduledoc """
  The texture of the coat of a mammal: strands of hair, light and dark,
  along v (the direction in which the fur lies, `World.Animals.UV`). It
  is gray: the colors of the regions of the coat (the colors of the
  points) give its color. The texture repeats in u and v, and one tile
  is `tile/0` of skin. World makes it with no file and no random state,
  so each build gives the same bytes.

  - 128 by 128 texels. Each column of texels has three layers of
    strands, each strand 32 texels long, at an offset of its own (so the
    ends of the strands do not line up); the value of a strand is a hash
    of its column, its layer and its number, softer at its two ends.
  - The value of a texel: from 0.72 (a dark strand) to 1 (white: the
    color of the region).
  - The alpha of a texel: from 0.5 to 1, a hash of its column and the
    strand of the first layer. A layer of the coat over the bare skin
    (alpha mode MASK, a cutoff of 0.5) keeps the strands where the alpha
    of the texel times the alpha of the point is 0.5 or more: with less
    hair at the point (an alpha from 1 to 0.5), fewer strands.
  """

  @size 128
  @strand 32

  @doc "The length of skin of one tile of the texture (m)."
  def tile, do: 0.04

  @doc "The texture: `{mime, bytes}` of a PNG file."
  def texture, do: elem(made(), 0)

  @doc """
  The mean value of the texels (0 to 1): the bare skin (with no
  texture) has this gray, so that it is as light as the fur next to it.
  """
  def mean, do: elem(made(), 1)

  defp made do
    case :persistent_term.get({__MODULE__, :made}, nil) do
      nil ->
        values = for y <- 0..(@size - 1), do: for(x <- 0..(@size - 1), do: round(255 * value(x, y)))
        alphas = for y <- 0..(@size - 1), do: for(x <- 0..(@size - 1), do: round(255 * alpha(x, y)))
        made = {{"image/png", png(values, alphas)}, Enum.sum(List.flatten(values)) / (255 * @size * @size)}
        :persistent_term.put({__MODULE__, :made}, made)
        made

      made ->
        made
    end
  end

  # A value from 0 to 1 for two integers, with no state.
  defp hash(a, b), do: :erlang.phash2({a, b}, 1_000_003) / 1_000_003

  defp value(x, y) do
    v =
      Enum.sum(
        for l <- 0..2 do
          off = round(hash(x, 100 + l) * @strand)
          at = rem(y + off, @size)
          base = hash(x * 31 + l, div(at, @strand) + 17 * l)
          soft = :math.sin(:math.pi() * rem(at, @strand) / @strand)
          0.5 + (base - 0.5) * (0.6 + 0.4 * soft)
        end
      ) / 3

    0.72 + 0.28 * (((v - 0.5) * 2.2 + 0.5) |> max(0.0) |> min(1.0))
  end

  defp alpha(x, y) do
    at = rem(y + round(hash(x, 100) * @strand), @size)
    0.5 + 0.5 * hash(x * 37 + 5, div(at, @strand) + 1000)
  end

  # A PNG file: 8 bits of red, green, blue and alpha, rows with no filter.
  defp png(values, alphas) do
    rows =
      for {row, arow} <- Enum.zip(values, alphas),
          into: <<>>,
          do: <<0>> <> for({g, a} <- Enum.zip(row, arow), into: <<>>, do: <<g, g, g, a>>)

    <<137, 80, 78, 71, 13, 10, 26, 10>> <>
      chunk("IHDR", <<@size::32, @size::32, 8, 6, 0, 0, 0>>) <>
      chunk("IDAT", :zlib.compress(rows)) <> chunk("IEND", <<>>)
  end

  defp chunk(type, data), do: <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>
end
