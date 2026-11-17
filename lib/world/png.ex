defmodule World.PNG do
  @moduledoc """
  A PNG file that World makes (the textures with no file: the coat of
  an animal, the pores of the skin): 8 bits for each channel, the rows
  with no filter, so each build gives the same bytes. And a PNG file of
  16-bit gray values that World reads (the height tiles of a terrain,
  `World.Terrain`), and a PNG file of 8 bits for each channel that World
  reads (the swatch of the texture of an item of clothes, `World.People`).
  """

  @doc """
  The bytes of a PNG file of `rows` (a list of binaries, one for each row
  of texels), each texel `channels` bytes: 3 (red, green, blue) or 4
  (with the alpha).
  """
  def encode([first | _] = rows, channels) when channels in [3, 4] do
    width = div(byte_size(first), channels)
    type = if channels == 3, do: 2, else: 6
    data = for row <- rows, into: <<>>, do: <<0>> <> row

    <<137, 80, 78, 71, 13, 10, 26, 10>> <>
      chunk("IHDR", <<width::32, length(rows)::32, 8, type, 0, 0, 0>>) <>
      chunk("IDAT", :zlib.compress(data)) <> chunk("IEND", <<>>)
  end

  @doc """
  The values of a PNG file of 16-bit gray (no interlace): `{width,
  height, values}`, the values a tuple of integers from 0 to 65535, row
  by row from the top row of the image.
  """
  def decode_gray16(<<137, 80, 78, 71, 13, 10, 26, 10, rest::binary>>) do
    chunks = chunks(rest, [])
    <<w::32, h::32, 16, 0, _, _, 0>> = chunks |> List.keyfind("IHDR", 0) |> elem(1)
    data = :zlib.uncompress(for({"IDAT", d} <- chunks, into: <<>>, do: d))
    rows = unfilter(data, w * 2, 2, <<0::size(w * 2 * 8)>>, [])
    {w, h, rows |> Enum.flat_map(fn row -> for <<v::16 <- row>>, do: v end) |> List.to_tuple()}
  end

  @doc """
  The texels of a PNG file of 8 bits for each channel (no palette, no
  interlace): `{width, height, channels, rows}`, the rows a tuple of
  binaries from the top row of the image, each texel `channels` bytes (1
  gray, 2 gray and alpha, 3 red, green and blue, 4 with the alpha).

      iex> png = World.PNG.encode([<<1, 2, 3, 4, 5, 6>>, <<7, 8, 9, 10, 11, 12>>], 3)
      iex> World.PNG.decode(png)
      {2, 2, 3, {<<1, 2, 3, 4, 5, 6>>, <<7, 8, 9, 10, 11, 12>>}}
  """
  def decode(<<137, 80, 78, 71, 13, 10, 26, 10, rest::binary>>) do
    chunks = chunks(rest, [])
    <<w::32, h::32, 8, type, _, _, 0>> = chunks |> List.keyfind("IHDR", 0) |> elem(1)
    channels = Map.fetch!(%{0 => 1, 4 => 2, 2 => 3, 6 => 4}, type)
    data = :zlib.uncompress(for({"IDAT", d} <- chunks, into: <<>>, do: d))
    {w, h, channels, data |> unfilter(w * channels, channels, <<0::size(w * channels * 8)>>, []) |> List.to_tuple()}
  end

  defp chunks(<<len::32, type::binary-4, data::binary-size(len), _crc::32, rest::binary>>, acc),
    do: if(type == "IEND", do: Enum.reverse(acc), else: chunks(rest, [{type, data} | acc]))

  # The rows of the image with their filters undone (PNG, section 9): each
  # row `n` bytes, `bpp` bytes for each texel.
  defp unfilter(<<>>, _n, _bpp, _prev, acc), do: Enum.reverse(acc)

  defp unfilter(data, n, bpp, prev, acc) do
    <<filter, row::binary-size(^n), rest::binary>> = data
    row = undo(filter, row, bpp, prev)
    unfilter(rest, n, bpp, row, [row | acc])
  end

  defp undo(0, row, _bpp, _prev), do: row
  defp undo(2, row, _bpp, prev), do: add(row, prev)

  # The filters Sub, Average and Paeth: each byte with the byte of the
  # texel to its left (`bpp` bytes before it), the byte over it, and the
  # byte over that.
  defp undo(f, row, bpp, prev) when f in [1, 3, 4] do
    {out, _} =
      for {x, i} <- Enum.with_index(:binary.bin_to_list(row)), reduce: {[], []} do
        {acc, done} ->
          {a, b, c} =
            {if(i >= bpp, do: Enum.at(done, bpp - 1), else: 0), :binary.at(prev, i),
             if(i >= bpp, do: :binary.at(prev, i - bpp), else: 0)}

          v =
            case f do
              1 -> x + a
              3 -> x + div(a + b, 2)
              4 -> x + paeth(a, b, c)
            end
            |> band()

          {[v | acc], Enum.take([v | done], bpp)}
      end

    out |> Enum.reverse() |> :binary.list_to_bin()
  end

  # The filter Up: each byte plus the byte over it.
  defp add(row, prev),
    do: for({x, y} <- Enum.zip(:binary.bin_to_list(row), :binary.bin_to_list(prev)), into: <<>>, do: <<band(x + y)>>)

  defp band(v), do: Bitwise.band(v, 255)

  defp paeth(a, b, c) do
    p = a + b - c
    {pa, pb, pc} = {abs(p - a), abs(p - b), abs(p - c)}

    cond do
      pa <= pb and pa <= pc -> a
      pb <= pc -> b
      true -> c
    end
  end

  defp chunk(type, data), do: <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>
end
