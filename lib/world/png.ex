defmodule World.PNG do
  @moduledoc """
  A PNG file that World makes (the textures with no file: the coat of
  an animal, the pores of the skin): 8 bits for each channel, the rows
  with no filter, so each build gives the same bytes.
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

  defp chunk(type, data), do: <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>
end
