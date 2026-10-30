defmodule World.Animals.Coat do
  @moduledoc """
  The texture of the coat of a mammal: hair, light and dark, along v
  (the direction in which the fur lies, `World.Animals.UV`). It is gray:
  the colors of the regions of the coat (the colors of the points) give
  its color. The texture repeats in u and v, and one tile is `tile/1` of
  skin. World makes it with no file and no random state, so each build
  gives the same bytes. There are four kinds of hair (`kinds/0`):

  - `long` (one tile is 4 cm): straight strands of 1 cm. Each column of
    texels has three layers of strands, each strand 32 texels long, at
    an offset of its own (so the ends of the strands do not line up);
    the value of a strand is a hash of its column, its layer and its
    number, softer at its two ends.
  - `short` (2 cm): the same with strands of 16 texels, so of 2.5 mm.
  - `curly` (4 cm): the strands of `long` that bend from side to side,
    3 texels (1 mm) each way, a wave each 32 texels (1 cm); the strands
    of four columns bend together.
  - `wool` (9 cm): round locks of about 16 texels (1.1 cm), with fine
    crimped fibers in them (strands of 8 texels that bend by one
    texel); the gaps between the locks are dark.

  The 128 by 128 texels of each kind have:

  - a value: from 0.72 (a dark strand) to 1 (white: the color of the
    region).
  - an alpha: from 0.5 to 1, a hash of the column and the strand of the
    first layer (of `wool`: the height of the lock). A layer of the coat
    over the bare skin (alpha mode MASK, a cutoff of 0.5) keeps the
    strands where the alpha of the texel times the alpha of the point is
    0.5 or more: with less hair at the point (an alpha from 1 to 0.5),
    fewer strands.
  """

  @size 128
  @kinds ~w(short long curly wool)

  @doc "The kinds of hair."
  def kinds, do: @kinds

  @doc "The length of skin of one tile of the texture of a kind (m)."
  def tile(kind \\ "long")
  def tile("short"), do: 0.02
  def tile("wool"), do: 0.09
  def tile(kind) when kind in @kinds, do: 0.04

  @doc "The texture of a kind of hair: `{mime, bytes}` of a PNG file."
  def texture(kind \\ "long"), do: elem(made(kind), 0)

  @doc """
  The mean value of the texels of a kind (0 to 1): the bare skin (with
  no texture) has this gray, so that it is as light as the fur next to
  it.
  """
  def mean(kind \\ "long"), do: elem(made(kind), 1)

  defp made(kind) when kind in @kinds do
    case :persistent_term.get({__MODULE__, kind}, nil) do
      nil ->
        texels = for y <- 0..(@size - 1), do: for(x <- 0..(@size - 1), do: texel(kind, x, y))
        values = for row <- texels, do: for({v, _} <- row, do: round(255 * v))
        alphas = for row <- texels, do: for({_, a} <- row, do: round(255 * a))
        made = {{"image/png", png(values, alphas)}, Enum.sum(List.flatten(values)) / (255 * @size * @size)}
        :persistent_term.put({__MODULE__, kind}, made)
        made

      made ->
        made
    end
  end

  # A value from 0 to 1 for two integers, with no state.
  defp hash(a, b), do: :erlang.phash2({a, b}, 1_000_003) / 1_000_003

  # The value and the alpha of a texel.
  defp texel("short", x, y), do: strands(x, y, 16, fn _, _ -> 0 end)
  defp texel("long", x, y), do: strands(x, y, 32, fn _, _ -> 0 end)
  defp texel("curly", x, y), do: strands(x, y, 32, &wave(&1, &2, x, 4, 32))

  defp texel("wool", x, y) do
    lock = lock(x, y)
    {fiber, _} = strands(x, y, 8, &wave(&1, &2, x, 1, 8))
    fiber = (fiber - 0.72) / 0.28
    # The top of a lock is light, the gap between two locks dark.
    top = lock
    {0.72 + 0.28 * (((0.45 * fiber + 0.55 * top - 0.5) * 1.8 + 0.5) |> max(0.0) |> min(1.0)), 0.5 + 0.5 * top}
  end

  defp smooth(a, b, t) do
    t = min(max((t - a) / (b - a), 0.0), 1.0)
    t * t * (3 - 2 * t)
  end

  # The bend of a strand: `amp` texels each way, a wave each `period`
  # texels of v, the same for four columns.
  defp wave(y, l, x, amp, period),
    do: round(amp * :math.sin(2 * :math.pi() * (y / period + hash(div(x, 8), 200 + l))))

  # Three layers of strands of `len` texels along v; `bend` moves the
  # column of each layer at a row.
  defp strands(x, y, len, bend) do
    v =
      Enum.sum(
        for l <- 0..2 do
          c = rem(x + bend.(y, l) + @size, @size)
          off = round(hash(c, 100 + l) * len)
          at = rem(y + off, @size)
          base = hash(c * 31 + l, div(at, len) + 17 * l)
          soft = :math.sin(:math.pi() * rem(at, len) / len)
          0.5 + (base - 0.5) * (0.6 + 0.4 * soft)
        end
      ) / 3

    c = rem(x + bend.(y, 0) + @size, @size)
    at = rem(y + round(hash(c, 100) * len), @size)
    {0.72 + 0.28 * (((v - 0.5) * 2.2 + 0.5) |> max(0.0) |> min(1.0)), 0.5 + 0.5 * hash(c * 37 + 5, div(at, len) + 1000)}
  end

  # The height of the locks of wool (0 to 1): cells of 16 texels, each
  # with a center at a hash of its place, that repeat with the tile. A
  # texel is high near the nearest center (the top of a lock) and low
  # far from it and where two locks touch.
  defp lock(x, y) do
    n = div(@size, 16)

    [d1, d2 | _] =
      Enum.sort(
        for i <- (div(x, 16) - 1)..(div(x, 16) + 1), j <- (div(y, 16) - 1)..(div(y, 16) + 1) do
          cx = 16 * (i + hash(rem(i + n, n), rem(j + n, n) + 5000))
          cy = 16 * (j + hash(rem(i + n, n) + 7000, rem(j + n, n)))
          :math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
        end
      )

    smooth(0.0, 1.0, 1 - d1 / 13) * smooth(0.0, 1.0, (d2 - d1) / 5)
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
