defmodule World.TerrainTest do
  # The ground of a place from the Vũng Tàu game (plan 0006, D3 to D5):
  # the height tiles, the heights at the points of the game, the mesh of
  # the ground, the place of the hill with its lots, and the place of a
  # model in the game.
  use ExUnit.Case, async: true

  alias World.{Places, PNG, Terrain}

  # A PNG file of 16-bit gray with a filter for each row (PNG, section 9),
  # for the reader.
  defp gray16(rows, filters) do
    w = length(hd(rows))
    bytes = for r <- rows, do: for(v <- r, into: <<>>, do: <<v::16>>)

    {data, _} =
      bytes
      |> Enum.zip(filters)
      |> Enum.reduce({<<>>, <<0::size(w * 16)>>}, fn {row, f}, {acc, prev} ->
        {acc <> <<f>> <> filter(f, row, prev), row}
      end)

    chunk = fn type, d -> <<byte_size(d)::32, type::binary, d::binary, :erlang.crc32(type <> d)::32>> end

    <<137, 80, 78, 71, 13, 10, 26, 10>> <>
      chunk.("IHDR", <<w::32, length(rows)::32, 16, 0, 0, 0, 0>>) <>
      chunk.("tEXt", "note") <> chunk.("IDAT", :zlib.compress(data)) <> chunk.("IEND", <<>>)
  end

  defp filter(f, row, prev) do
    {x, p} = {:binary.bin_to_list(row), :binary.bin_to_list(prev)}

    for i <- 0..(length(x) - 1), into: <<>> do
      {a, b, c} =
        {if(i >= 2, do: Enum.at(x, i - 2), else: 0), Enum.at(p, i), if(i >= 2, do: Enum.at(p, i - 2), else: 0)}

      v =
        case f do
          0 -> Enum.at(x, i)
          1 -> Enum.at(x, i) - a
          2 -> Enum.at(x, i) - b
          3 -> Enum.at(x, i) - div(a + b, 2)
          4 -> Enum.at(x, i) - paeth(a, b, c)
        end

      <<Bitwise.band(v, 255)>>
    end
  end

  defp paeth(a, b, c) do
    p = a + b - c

    cond do
      abs(p - a) <= abs(p - b) and abs(p - a) <= abs(p - c) -> a
      abs(p - b) <= abs(p - c) -> b
      true -> c
    end
  end

  test "the reader of a PNG file of 16-bit gray undoes each filter of a row" do
    :rand.seed(:exsss, {1, 2, 3})
    rows = for _ <- 1..10, do: for(_ <- 1..7, do: :rand.uniform(65_536) - 1)
    {7, 10, values} = PNG.decode_gray16(gray16(rows, [0, 1, 2, 3, 4, 4, 3, 1, 2, 4]))
    assert Tuple.to_list(values) == List.flatten(rows)
  end

  test "the tiles of the game: the same values as the PNG files, and the heights at the points of the game" do
    assert Terrain.names() == ["nui_nho"]
    t = Terrain.load("nui_nho")
    assert map_size(t["tiles"]) == 55 and t["grid_m"] == 2 and t["samples"] == 129
    # Values of the tile 4_7 that Pillow reads (row, column).
    v = t["tiles"][{4, 7}]
    assert elem(v, 0) == 12_621 and elem(v, 128 * 129 + 128) == 4436

    assert {elem(v, 50 * 129 + 67), elem(v, 50 * 129 + 68), elem(v, 51 * 129 + 67), elem(v, 51 * 129 + 68)} ==
             {15_840, 15_842, 15_827, 15_828}

    # The last column of a tile is the first of the next.
    assert elem(v, 50 * 129 + 128) == 9965 and elem(t["tiles"][{5, 7}], 50 * 129) == 9965

    # The statue of the game (landmark chua_kito_vua): the bilinear value
    # of its four samples.
    {fx, fz} = {1159.87 / 2 - 579, 1893.39 / 2 - 946}
    top = 15_840 * (1 - fx) + 15_842 * fx
    low = 15_827 * (1 - fx) + 15_828 * fx
    assert_in_delta Terrain.height("nui_nho", {1159.87, 1893.39}), -20 + (top * (1 - fz) + low * fz) * 0.01, 1.0e-9
    assert_in_delta Terrain.height("nui_nho", {1159.87, 1893.39}), 138.33, 0.02
    # A sample point: its value.
    assert_in_delta Terrain.height("nui_nho", {1024.0 + 2 * 67, 1792.0 + 2 * 50}), 138.40, 1.0e-9
    # Out of the tiles.
    assert Terrain.height("nui_nho", {-10.0, 2000.0}) == nil
    assert Terrain.height("nui_nho", {1000.0, 100.0}) == nil
  end

  test "the mesh of the ground: flat on a pad, no faces under the sea, the sea floor out of the tiles" do
    pad = {1159.87, 1893.39, 12.0, 140.0}
    m = Terrain.mesh("nui_nho", {1100.0, 1840.0, 1220.0, 1940.0}, 4.0, {1159.87, 1893.39, 0.0}, :grass, [pad])
    assert m.material == :grass and Enum.all?(m.faces, &(length(&1) == 3))
    # On the pad the ground is at its height; x east, y north.
    for {x, y, z} <- m.points, x * x + y * y <= 144, do: assert(z == 140.0)
    assert Enum.any?(m.points, fn {x, y, _} -> x * x + y * y <= 144 end)
    # Out of the pad and its blend: the ground of the game.
    {x, y, z} = Enum.find(m.points, fn {x, y, _} -> x * x + y * y > 18 * 18 end)
    assert_in_delta z, Terrain.height("nui_nho", {1159.87 + x, 1893.39 - y}), 1.0e-9
    # Each face turns up.
    pts = List.to_tuple(m.points)

    for [a, b, c] <- m.faces do
      {_, _, nz} = World.Vec.cross(World.Vec.sub(elem(pts, b), elem(pts, a)), World.Vec.sub(elem(pts, c), elem(pts, a)))
      assert nz > 0
    end

    # The sea of the cape: a box under the sea has no faces; out of the
    # tiles, the sea floor of the game.
    sea = Terrain.mesh("nui_nho", {1300.0, 2700.0, 1340.0, 2740.0}, 8.0, {0.0, 0.0, 0.0}, :grass)
    assert sea.faces == [] and sea.points == []
    out = Terrain.mesh("nui_nho", {-16.0, 2000.0, 0.0, 2016.0}, 8.0, {0.0, 0.0, 0.0}, :grass, [], -10.0)
    assert Enum.any?(out.points, fn {_, _, z} -> z == -4.0 end)
  end

  test "the hill of Núi Nhỏ: a place of the statues, its lots at the heights of the game, its ground, the place in the game" do
    assert Places.for_kind("statue") == "nui_nho"
    {:ok, p} = Places.fetch("nui_nho")
    assert [top, cape] = Places.lots(p)
    # The point of the place on the yard is the top.
    assert top["name"] == "top" and p["at"] == [700.0, 800.0]
    assert_in_delta hd(top["yard"]), 700.0, 1.0e-9
    assert_in_delta Enum.at(top["yard"], 1), 800.0, 1.0e-9
    assert_in_delta top["height"], 138.32, 0.01
    assert_in_delta cape["height"], 1.34, 0.01
    # The cape is 83.32 m to the west and 668.3 m to the south of the top.
    assert_in_delta hd(cape["yard"]), 700.0 - 83.32, 1.0e-6
    assert_in_delta Enum.at(cape["yard"], 1), 800.0 - 668.3, 1.0e-6
    assert Places.lot(p, "moon") == nil
    {:ok, site} = Places.fetch("site")
    assert Places.lots(site) == []

    assert Places.geo(p, "top") == %{
             "frame" => "vung_tau_game",
             "at" => [1159.87, top["height"], 1893.39],
             "turn" => 180.0
           }

    assert Terrain.geo({1, 2}, 3, 90) == %{"frame" => "vung_tau_game", "at" => [1.0, 3.0, 2.0], "turn" => 90.0}

    # The ground in the frame of World from the top, at the height of the sea.
    [m] = Places.ground(p).shapes
    assert m.material == :grass
    {{x0, y0, z0}, {x1, y1, z1}} = World.Mesh.bounds(m)
    assert x0 >= 760 - 1159.87 - 1.0e-6 and x1 <= 1600 - 1159.87 + 1.0e-6
    assert y0 >= 1893.39 - 2640 - 1.0e-6 and y1 <= 1893.39 - 1440 + 1.0e-6
    assert z0 < 0 and z1 > 138 and z1 < 180
    near = for {x, y, z} <- m.points, x * x + y * y <= 100, do: z
    assert near != [] and Enum.all?(near, &(&1 == top["height"]))

    [view] = for q <- Places.view(), q["terrain"], do: q
    assert view["terrain"]["ground"] == "/places/nui_nho/ground.glb"
    assert [%{"height" => _, "yard" => _}, _] = view["terrain"]["lots"]
  end
end
