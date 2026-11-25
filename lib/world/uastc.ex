defmodule World.UASTC do
  @moduledoc """
  The blocks of UASTC (the LDR 4x4 format of Basis Universal), for an
  image of KTX2 (`World.KTX2`, plan 0020, D14). A block is 16 bytes for 4
  by 4 texels; an app transcodes it to the format of its GPU (BC7, ASTC,
  ETC). World writes three of the modes of UASTC:

  | Mode | For | The data |
  |---|---|---|
  | 8 | A block of one color | The color, with the hints of ETC1. |
  | 5 | A block of RGB | Two end colors of 8 bits, and a weight of 3 bits for each texel. |
  | 14 | A block of RGBA | Two end colors of 8 bits with their alpha, and a weight of 2 bits for each texel. |

  The bits of a block go from the low bit of its first byte. The two end
  colors are on the line of the most change of the colors of the block,
  and the weight of each texel is the one that gives the nearest color.
  The weight of the first texel has one bit less: when it is too large,
  the end colors change places and each weight turns round. The hints
  for BC1 and ETC1 are simple values that each transcoder takes (the
  transcoder to ETC1 makes its colors from the texels).
  """
  import Bitwise

  # The code of each mode (its value and its bits, from the low bit).
  @codes %{5 => {0xB, 5}, 8 => {0x17, 5}, 14 => {0xD, 5}}
  # The values of the weights of 3 bits and of 2 bits (0 to 64), as ASTC has them.
  @w3 {0, 9, 18, 27, 37, 46, 55, 64}
  @w2 {0, 21, 43, 64}
  # The modifiers of the tables of intensity of ETC1.
  @etc1 [{2, 8}, {5, 17}, {9, 29}, {13, 42}, {18, 60}, {24, 80}, {33, 106}, {47, 183}]

  @doc """
  The blocks of an image: `rows` (`World.PNG.decode/1`: a tuple of rows
  of bytes), `w` by `h` texels, with `channels` (3 or 4). A block at an
  edge of an image that is not a multiple of 4 repeats its last row and
  column. Gives the blocks in order, row by row of blocks.
  """
  def encode(rows, w, h, channels) when channels in [3, 4] do
    {bw, bh} = {div(w + 3, 4), div(h + 3, 4)}

    for by <- 0..(bh - 1), bx <- 0..(bw - 1), into: <<>> do
      texels =
        for y <- 0..3, x <- 0..3 do
          row = elem(rows, min(by * 4 + y, h - 1))
          i = min(bx * 4 + x, w - 1) * channels

          if channels == 3,
            do: {:binary.at(row, i), :binary.at(row, i + 1), :binary.at(row, i + 2), 255},
            else: {:binary.at(row, i), :binary.at(row, i + 1), :binary.at(row, i + 2), :binary.at(row, i + 3)}
        end

      block(texels, channels == 4 and Enum.any?(texels, &(elem(&1, 3) != 255)))
    end
  end

  @doc "The block of 16 texels `{r, g, b, a}` (row by row); `alpha?`: the block has an alpha."
  def block([first | _] = texels, alpha?) do
    cond do
      Enum.all?(texels, &(&1 == first)) -> solid(first)
      alpha? -> rgba(texels)
      true -> rgb(texels)
    end
  end

  # Mode 8: one color, and the hints of ETC1 for it (the base color in 5
  # bits, with no intensity: the transcoder adds the modifier of the
  # selector to the base).
  defp solid({r, g, b, a}) do
    q = fn c -> div(c * 31 + 127, 255) end

    pack([
      @codes[8],
      {r, 8},
      {g, 8},
      {b, 8},
      {a, 8},
      # (ETC1: the differential mode, the intensity 0, the selector 0, and the base color.)
      {1, 1},
      {0, 3},
      {0, 2},
      {q.(r), 5},
      {q.(g), 5},
      {q.(b), 5}
    ])
  end

  # Mode 5: RGB, two end colors and a weight of 3 bits for each texel.
  defp rgb(texels) do
    {lo, hi} = ends(texels, 3)
    weights = for t <- texels, do: nearest(t, lo, hi, @w3, 3)
    {lo, hi, weights} = anchor(lo, hi, weights, 7)
    {{r0, g0, b0, _}, {r1, g1, b1, _}} = {lo, hi}

    pack(
      [@codes[5] | hints(texels, nil)] ++
        [{r0, 8}, {r1, 8}, {g0, 8}, {g1, 8}, {b0, 8}, {b1, 8}] ++ weight_bits(weights, 3)
    )
  end

  # Mode 14: RGBA, two end colors with their alpha and a weight of 2 bits for each texel.
  defp rgba(texels) do
    {lo, hi} = ends(texels, 4)
    weights = for t <- texels, do: nearest(t, lo, hi, @w2, 4)
    {lo, hi, weights} = anchor(lo, hi, weights, 3)
    {{r0, g0, b0, a0}, {r1, g1, b1, a1}} = {lo, hi}

    pack(
      [@codes[14] | hints(texels, alpha_hints(texels))] ++
        [{r0, 8}, {r1, 8}, {g0, 8}, {g1, 8}, {b0, 8}, {b1, 8}, {a0, 8}, {a1, 8}] ++ weight_bits(weights, 2)
    )
  end

  # The weight of the first texel has one bit less: its high bit must be
  # 0. Else the end colors change places and each weight turns round.
  defp anchor(lo, hi, [w0 | _] = weights, top) do
    if w0 > div(top, 2), do: {hi, lo, Enum.map(weights, &(top - &1))}, else: {lo, hi, weights}
  end

  defp weight_bits([w0 | rest], bits), do: [{w0, bits - 1} | Enum.map(rest, &{&1, bits})]

  # The hints: BC1 (none), ETC1 (not flipped; differential when the two
  # halves of the block are near in color; the table of intensity of each
  # half from the spread of its texels; no bias), and the hints of the
  # alpha of ETC2 for a block of RGBA.
  defp hints(texels, alpha) do
    at = List.to_tuple(texels)
    halves = for x0 <- [0, 2], do: for(y <- 0..3, x <- x0..(x0 + 1), do: elem(at, y * 4 + x))
    means = Enum.map(halves, &mean/1)
    [m0, m1] = means
    near? = Enum.all?([0, 1, 2], fn c -> abs(div(elem(m0, c) * 31, 255) - div(elem(m1, c) * 31, 255)) <= 3 end)

    inten =
      for {half, m} <- Enum.zip(halves, means) do
        spread = Enum.max(for t <- half, do: abs(luma(t) - luma(m)))
        Enum.find_index(@etc1, fn {_, big} -> big >= spread end) || 7
      end

    [{0, 1}, {0, 1}, {0, 1}, {if(near?, do: 1, else: 0), 1}, {Enum.at(inten, 0), 3}, {Enum.at(inten, 1), 3}, {0, 5}] ++
      if(alpha, do: [{alpha, 8}], else: [])
  end

  # The hints of the alpha of ETC2 (EAC): a table and a multiplier for the spread of the alpha.
  defp alpha_hints(texels) do
    {lo, hi} = Enum.min_max(for {_, _, _, a} <- texels, do: a)
    multiplier = min(max(div(hi - lo + 15, 16), 1), 15)
    multiplier <<< 4 ||| 13
  end

  defp mean(texels) do
    n = length(texels)
    {r, g, b} = Enum.reduce(texels, {0, 0, 0}, fn {r, g, b, _}, {sr, sg, sb} -> {sr + r, sg + g, sb + b} end)
    {div(r + div(n, 2), n), div(g + div(n, 2), n), div(b + div(n, 2), n)}
  end

  defp luma({r, g, b, _}), do: luma({r, g, b})
  defp luma({r, g, b}), do: div(r * 2 + g * 5 + b, 8)

  # The two end colors: the texels on the line of the most change of the
  # colors of the block (from its mean, by a few steps of power
  # iteration from the texel that is farthest from the mean), at the two
  # ends of their projections on it.
  defp ends(texels, comps) do
    vecs = for t <- texels, do: Enum.take(Tuple.to_list(t), comps)
    n = length(vecs)
    mean = Enum.map(Enum.zip_with(vecs, & &1), &(Enum.sum(&1) / n))
    centered = for v <- vecs, do: Enum.zip_with(v, mean, &(&1 - &2))

    cov =
      for i <- 0..(comps - 1), j <- 0..(comps - 1) do
        Enum.sum(for c <- centered, do: Enum.at(c, i) * Enum.at(c, j))
      end

    # (The start has a part on the line in each block of more than one color: (1, 1, 1) has none when
    # the red goes up as the green goes down.)
    start = Enum.max_by(centered, fn c -> Enum.sum(for x <- c, do: x * x) end)

    axis =
      Enum.reduce(1..8, start, fn _, v ->
        next =
          for i <- 0..(comps - 1),
              do: Enum.sum(for j <- 0..(comps - 1), do: Enum.at(cov, i * comps + j) * Enum.at(v, j))

        len = :math.sqrt(Enum.sum(for x <- next, do: x * x))
        if len < 1.0e-9, do: v, else: Enum.map(next, &(&1 / len))
      end)

    dots = for c <- centered, do: Enum.sum(Enum.zip_with(c, axis, &(&1 * &2)))
    {lo, hi} = Enum.min_max(dots)

    point = fn t ->
      list = Enum.zip_with(mean, axis, &(&1 + &2 * t)) |> Enum.map(&min(max(round(&1), 0), 255))
      List.to_tuple(list ++ List.duplicate(255, 4 - comps))
    end

    {point.(lo), point.(hi)}
  end

  # The weight of a texel: the one whose color (as the decoder makes it)
  # is the nearest.
  defp nearest(t, lo, hi, table, comps) do
    0..(tuple_size(table) - 1)
    |> Enum.min_by(fn i ->
      w = elem(table, i)
      Enum.sum(for c <- 0..(comps - 1), do: (interpolate(elem(lo, c), elem(hi, c), w) - elem(t, c)) ** 2)
    end)
  end

  @doc "A part of a color between two end colors, as the decoder of ASTC makes it (LDR, not sRGB)."
  def interpolate(l, h, w) do
    {l, h} = {l <<< 8 ||| l, h <<< 8 ||| h}
    (l * (64 - w) + h * w + 32) >>> 6 >>> 8
  end

  # The 128 bits of a block from fields `{value, bits}`, from the low bit of the first byte.
  defp pack(fields) do
    {value, bits} =
      Enum.reduce(fields, {0, 0}, fn {v, n}, {acc, at} -> {acc ||| (v &&& (1 <<< n) - 1) <<< at, at + n} end)

    true = bits <= 128
    <<value::little-128>>
  end
end
