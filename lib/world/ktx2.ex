defmodule World.KTX2 do
  @moduledoc """
  An image as a file of KTX2 with Basis Universal (plan 0020, D14): the
  texels in blocks of UASTC (`World.UASTC`), each level of the mipmaps
  supercompressed with Zstandard, for `KHR_texture_basisu` in a GLB. An
  app transcodes the blocks to the format of its GPU (BC7 on a desktop,
  ASTC or ETC on a phone), so the image stays packed in the memory of the
  GPU: 1 byte for each texel, where an image of PNG takes 4.

  The file has each level of the mipmaps, from the image to 1 by 1 (each
  level the mean of 2 by 2 texels of the level before it), as a GPU
  needs them: it cannot make the mipmaps of a packed image. The data
  format descriptor gives the model of UASTC, the sRGB or the linear
  transfer (`srgb`: an image of color or of glow has sRGB; a normal or a
  finish image is linear), and the channels (RGB, or RGBA when a texel
  has an alpha). With no Zstandard in the runtime (`:zstd` of Erlang
  29), the levels are not supercompressed.
  """
  import Bitwise

  @identifier <<0xAB, "KTX 20", 0xBB, "\r\n", 0x1A, "\n">>
  # The model of UASTC in a data format descriptor, and its channels.
  @uastc 166
  @rgb 0
  @rgba 3

  @doc """
  The file of KTX2 of an image of PNG of RGB or RGBA (`World.PNG`):
  `srgb` (true by default) for the transfer of its colors.
  """
  def from_png(png, opts \\ []) do
    {w, h, channels, rows} = World.PNG.decode(png)
    encode(rows, w, h, channels, opts)
  end

  @doc """
  The file of KTX2 of the rows of an image (`World.PNG.decode/1`), `w` by
  `h` texels, with 3 or 4 `channels`.
  """
  def encode(rows, w, h, channels, opts \\ []) when channels in [3, 4] do
    srgb = Keyword.get(opts, :srgb, true)
    alpha? = channels == 4 and Enum.any?(Tuple.to_list(rows), &alpha?/1)
    levels = levels(rows, w, h, channels)
    zstd? = Code.ensure_loaded?(:zstd)

    # The data of each level: its blocks, supercompressed.
    datas =
      for {rows, lw, lh} <- levels do
        blocks = World.UASTC.encode(rows, lw, lh, channels)
        {if(zstd?, do: IO.iodata_to_binary(:zstd.compress(blocks)), else: blocks), byte_size(blocks)}
      end

    dfd = dfd(srgb, if(alpha?, do: @rgba, else: @rgb))
    kvd = kvd([{"KTXwriter", "World"}])
    count = length(levels)

    # (The identifier, the header of 9 numbers of 4 bytes, the index of 4 numbers of 4 bytes and 2 of 8, and the level index.)
    head = 12 + 36 + 32 + 24 * count
    {dfd_at, kvd_at} = {head, head + byte_size(dfd)}
    start = align(kvd_at + byte_size(kvd), 16)

    # The levels are in the file from the smallest to the largest; the index has them from level 0.
    {placed, _} =
      datas
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.map_reduce(start, fn {{data, raw}, i}, at ->
        at = align(at, 16)
        {{i, at, data, raw}, at + byte_size(data)}
      end)

    index =
      for {_, at, data, raw} <- Enum.sort(placed),
          into: <<>>,
          do: <<at::little-64, byte_size(data)::little-64, raw::little-64>>

    header =
      <<0::little-32, 1::little-32, w::little-32, h::little-32, 0::little-32, 0::little-32, 1::little-32,
        count::little-32, if(zstd?, do: 2, else: 0)::little-32>>

    indices =
      <<dfd_at::little-32, byte_size(dfd)::little-32, kvd_at::little-32, byte_size(kvd)::little-32, 0::little-64,
        0::little-64>>

    top = @identifier <> header <> indices <> index <> dfd <> kvd

    Enum.reduce(Enum.reverse(Enum.sort(placed)), top, fn {_, at, data, _}, bin ->
      bin <> :binary.copy(<<0>>, at - byte_size(bin)) <> data
    end)
  end

  defp alpha?(row), do: Enum.any?(for(<<_, _, _, a <- row>>, do: a), &(&1 != 255))

  defp align(n, k), do: div(n + k - 1, k) * k

  # The levels of the mipmaps: `{rows, w, h}`, from the image to 1 by 1.
  defp levels(rows, w, h, channels), do: chain(rows, w, h, channels, [])

  defp chain(rows, 1, 1, _channels, acc), do: Enum.reverse([{rows, 1, 1} | acc])

  defp chain(rows, w, h, channels, acc),
    do: chain(half(rows, w, h, channels), max(div(w, 2), 1), max(div(h, 2), 1), channels, [{rows, w, h} | acc])

  # The next level: each texel the mean of 2 by 2 texels (a side of 1 stays).
  defp half(rows, w, h, channels) do
    {nw, nh} = {max(div(w, 2), 1), max(div(h, 2), 1)}

    for y <- 0..(nh - 1) do
      {r0, r1} = {elem(rows, min(2 * y, h - 1)), elem(rows, min(2 * y + 1, h - 1))}

      for x <- 0..(nw - 1), c <- 0..(channels - 1), into: <<>> do
        {x0, x1} = {min(2 * x, w - 1), min(2 * x + 1, w - 1)}

        s =
          :binary.at(r0, x0 * channels + c) + :binary.at(r0, x1 * channels + c) + :binary.at(r1, x0 * channels + c) +
            :binary.at(r1, x1 * channels + c)

        <<(s + 2) >>> 2>>
      end
    end
    |> List.to_tuple()
  end

  # The data format descriptor: one basic block, with one sample of 128 bits.
  defp dfd(srgb, channel) do
    block =
      <<0::little-32, 2::little-16, 40::little-16, @uastc, 1, if(srgb, do: 2, else: 1), 0, 3, 3, 0, 0, 16, 0, 0, 0, 0,
        0, 0, 0, 0::little-16, 127, channel, 0, 0, 0, 0, 0::little-32, 0xFFFFFFFF::little-32>>

    <<byte_size(block) + 4::little-32>> <> block
  end

  # The key and value data: each pair with its length, a null at the end of the key and the value, and padding to 4 bytes.
  defp kvd(pairs) do
    for {k, v} <- pairs, into: <<>> do
      pair = k <> <<0>> <> v <> <<0>>
      <<byte_size(pair)::little-32>> <> pair <> :binary.copy(<<0>>, rem(4 - rem(byte_size(pair), 4), 4))
    end
  end
end
