defmodule World.KTX2Test do
  use ExUnit.Case, async: true
  import Bitwise

  alias World.{KTX2, PNG, UASTC}

  @fixtures Path.expand("../js/fixtures/ktx2", __DIR__)

  # The values of the header of a file of KTX2, its level index, and its data format descriptor.
  defp header(file) do
    <<0xAB, "KTX 20", 0xBB, "\r\n", 0x1A, "\n", vk::little-32, type_size::little-32, w::little-32, h::little-32,
      depth::little-32, layers::little-32, faces::little-32, levels::little-32, scheme::little-32, dfd_at::little-32,
      dfd_len::little-32, _::binary>> = file

    index = for i <- 0..(levels - 1), do: binary_part(file, 80 + 24 * i, 24)
    index = for <<at::little-64, len::little-64, raw::little-64>> <- index, do: {at, len, raw}
    <<_::binary-size(^dfd_at), dfd::binary-size(^dfd_len), _::binary>> = file

    %{
      vk: vk,
      type_size: type_size,
      w: w,
      h: h,
      depth: depth,
      layers: layers,
      faces: faces,
      levels: levels,
      scheme: scheme,
      index: index,
      dfd: dfd
    }
  end

  test "the fixtures of the test of the transcoder (test/js/ktx2.test.js) are the files that World writes" do
    for name <- ~w(glow alpha) do
      png = File.read!(Path.join(@fixtures, "#{name}.png"))
      assert KTX2.from_png(png) == File.read!(Path.join(@fixtures, "#{name}.ktx2"))
    end
  end

  test "a file of KTX2: the header, each level of the mipmaps with Zstandard, and the data format descriptor of UASTC" do
    png = File.read!(Path.join(@fixtures, "glow.png"))
    file = KTX2.from_png(png)
    h = header(file)
    assert {h.vk, h.type_size, h.w, h.h, h.depth, h.layers, h.faces, h.levels} == {0, 1, 128, 128, 0, 0, 1, 8}
    assert h.scheme == if(Code.ensure_loaded?(:zstd), do: 2, else: 0)

    # Each level: its blocks of 16 bytes (the image to 1 by 1), at a multiple of 16, the smallest first in the file.
    raws = for {_, _, raw} <- h.index, do: raw
    assert raws == for(s <- [128, 64, 32, 16, 8, 4, 2, 1], do: max(div(s, 4), 1) ** 2 * 16)
    ats = for {at, _, _} <- h.index, do: at
    assert Enum.all?(ats, &(rem(&1, 16) == 0)) and ats == Enum.sort(ats, :desc)

    # The descriptor: the model UASTC (166), the primaries of BT.709, sRGB, blocks of 4 by 4, 16 bytes, RGB.
    <<_::little-32, 0::little-32, 2::little-16, 40::little-16, 166, 1, 2, 0, 3, 3, 0, 0, 16, _::binary-9, 127, 0,
      _::binary>> = h.dfd

    # A normal or a finish image is linear (the transfer 1).
    <<_::binary-14, 1, _::binary>> = header(KTX2.from_png(png, srgb: false)).dfd
  end

  test "an image with an alpha, an RGBA image with no alpha, and an image whose sides are not multiples of 4" do
    alpha = File.read!(Path.join(@fixtures, "alpha.png"))
    <<_::binary-31, 3, _::binary>> = header(KTX2.from_png(alpha)).dfd

    opaque = PNG.encode(List.duplicate(:binary.copy(<<1, 2, 3, 255>>, 8), 8), 4)
    <<_::binary-31, 0, _::binary>> = header(KTX2.from_png(opaque)).dfd

    # 6 by 10: 2 by 3 blocks (the last row and column repeat), then 3 by 5, 1 by 2 and 1 by 1.
    rows = for y <- 0..9, do: for(x <- 0..5, into: <<>>, do: <<x * 40, y * 25, 7>>)
    h = header(KTX2.encode(List.to_tuple(rows), 6, 10, 3))
    assert {h.w, h.h, h.levels} == {6, 10, 4}
    assert for({_, _, raw} <- h.index, do: div(raw, 16)) == [6, 2, 1, 1]
  end

  # The bits of a block from its low bit: `{value, bits}` at `at`.
  defp bits(<<block::little-128>>, at, n), do: block >>> at &&& (1 <<< n) - 1

  test "the blocks of UASTC: one color (mode 8), RGB (mode 5), RGBA (mode 14), and the anchor of the weights" do
    solid = UASTC.block(List.duplicate({10, 20, 30, 255}, 16), false)
    assert bits(solid, 0, 5) == 0x17
    assert {bits(solid, 5, 8), bits(solid, 13, 8), bits(solid, 21, 8), bits(solid, 29, 8)} == {10, 20, 30, 255}

    ramp = for i <- 0..15, do: {i * 16, 255 - i * 16, 100, 255}
    rgb = UASTC.block(ramp, false)
    assert bits(rgb, 0, 5) == 0xB
    # (The hints are 15 bits, then the end colors R0 R1 G0 G1 B0 B1: the first texel is at the low end.)
    assert {bits(rgb, 20, 8), bits(rgb, 28, 8), bits(rgb, 36, 8), bits(rgb, 44, 8)} == {0, 240, 255, 15}
    # The first weight has 2 bits, the others 3: 0 for the first texel, 7 for the last.
    assert bits(rgb, 68, 2) == 0 and bits(rgb, 68 + 2 + 14 * 3, 3) == 7

    # With the first texel at the high end, the end colors change places and each weight turns round.
    turned = UASTC.block(Enum.reverse(ramp), false)
    assert {bits(turned, 20, 8), bits(turned, 28, 8)} == {240, 0} and bits(turned, 68, 2) == 0

    clear = for i <- 0..15, do: {200, 100, 50, i * 17}
    rgba = UASTC.block(clear, true)
    assert bits(rgba, 0, 5) == 0xD
    # (The hints of RGB and of the alpha are 23 bits; then R0 R1 G0 G1 B0 B1 A0 A1.)
    assert {bits(rgba, 28 + 48, 8), bits(rgba, 28 + 56, 8)} == {0, 255}

    # A part between two end colors, as the decoder of ASTC makes it.
    assert {UASTC.interpolate(0, 255, 0), UASTC.interpolate(0, 255, 64), UASTC.interpolate(0, 255, 32)} == {0, 255, 128}
  end
end
