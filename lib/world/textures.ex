defmodule World.Textures do
  @moduledoc """
  The textures that World makes for a role of a drawing (plan 0004, D7:
  `"materials": {"stone_wash": {"texture": "washed_stone"}}`), with no
  file: each build gives the same bytes (`World.PNG`).

  - `washed_stone`: a render of washed stone (đá rửa), small pebbles of
    3 to 6 mm in a cement of their color, as on the statue on Núi Nhỏ:
    the colors of the pebbles (a base color texture, white on the mean, so
    the color of the role stays the color of the surface) and their round
    tops (a normal texture). A tile is 0.3 m, on the UVs in metres of a
    surface (`World.Surface`).

  - A photo of `priv/textures/` (plan 0005): `NAME.jpg` (the detail, grey)
    and `NAME_normal.jpg` (its normal texture), made from a photo by
    `scripts/measure/panel.py`: a panel in relief on the base of a statue.
    Its role puts the image once on a panel (`panel` of a material of a
    drawing, `World.Build`); the licenses of the photos are in
    `CREDITS.md`.

  A texture is only at near (`World.Detail`): at mid and far a pebble is
  smaller than a texel of the screen, and the file stays small.

  - The surfaces of made things (plan 0020, D8), with the patterns of the
    surfaces of the edits (`World.Sculpt.Texture.look/4`), for a role of a
    rule in code. Each is a tile of one pitch (64 by 64 texels: a color
    texture, white on the mean, and a normal texture), at each level:
    the texture is small, and the mipmaps of an app give its mean far away.

    | Texture | For the role | The tile |
    |---|---|---|
    | `corrugated` | `roof_corrugated`: a roof of metal sheets | Square ribs of 32 mm on a pitch of 0.25 m, along v (across u). |
    | `shutter` | `metal_shutter`: a rolling shutter | Round ribs of 12 mm on a pitch of 0.08 m, along u (across v). |
    | `panes` | `glass`: the glass of a window | Panes of 0.5 by 0.6 m in frames of 5 cm (darker), each pane 2 cm in. |

    A sheet with a relief of its own (the roof of `World.Skills.Roof` at
    near and mid) has its ribs in its shape: the texture is for a flat
    sheet.
  """

  alias World.{PNG, Vec}

  @size 256
  @cell 8
  @tile 0.3

  @dir Path.join(:code.priv_dir(:world), "textures")
  @photos for(
            f <- File.ls!(Path.join(__DIR__, "../../priv/textures")),
            String.ends_with?(f, ".jpg") and not String.ends_with?(f, "_normal.jpg"),
            do: Path.rootname(f)
          )
          |> Enum.sort()
  for f <- File.ls!(Path.join(__DIR__, "../../priv/textures")),
      do: @external_resource(Path.join(__DIR__, "../../priv/textures/" <> f))

  # The textures of made things: a surface of `World.Sculpt.Texture`, the
  # size of its tile (m, along u and along v), and the side of the surface
  # that the tile is (`:up`: x along u, y along v; `:side`: x along u, z
  # along v; `:across`: the ribs along u).
  @made %{
    "corrugated" => {{"corrugated", %{}}, {0.25, 0.25}, :up},
    "shutter" => {{"corrugated", %{"profile" => "round", "pitch" => 0.08, "depth" => 0.012}}, {0.08, 0.08}, :across},
    "panes" => {{"windows", %{"pane" => [0.5, 0.6], "frame" => 0.05}}, {0.55, 0.65}, :side}
  }
  # The texels on each side of the tile of a made thing.
  @texels 64

  @doc "The names of the textures."
  def names, do: ["washed_stone" | Enum.sort(Map.keys(@made))] ++ @photos

  @doc """
  The keys of the material of a role for a texture at a level (`nil` for
  no texture): the base color image, the normal image and how many times
  each repeats in one unit of the UVs (a metre).
  """
  def spec(name, level)

  def spec("washed_stone", :near) do
    {color, normal} = washed_stone()
    repeat = Float.round(1 / @tile, 4)

    %{
      "image" => {"image/png", color},
      "image_scale" => repeat,
      "normal_image" => {"image/png", normal},
      "normal_image_scale" => repeat,
      "normal_scale" => 0.8
    }
  end

  def spec(name, :near) when name in @photos do
    %{
      "image" => {"image/jpeg", File.read!(Path.join(@dir, name <> ".jpg"))},
      "normal_image" => {"image/jpeg", File.read!(Path.join(@dir, name <> "_normal.jpg"))},
      "normal_scale" => 0.7
    }
  end

  def spec(name, _level) when is_map_key(@made, name) do
    {_, {u, v}, _} = @made[name]
    {color, normal} = made(name)
    scale = %{"scale" => [Float.round(1 / u, 4), Float.round(1 / v, 4)]}

    %{
      "image" => {"image/png", color},
      "image_transform" => scale,
      "normal_image" => {"image/png", normal},
      "normal_scale" => 1.0
    }
  end

  def spec(_name, _level), do: nil

  @doc """
  The two PNG files of a texture of a made thing (`corrugated`,
  `shutter` or `panes`): `{color, normal}`.
  """
  def made(name) do
    case :persistent_term.get({__MODULE__, name}, nil) do
      nil ->
        pngs = make(@made[name])
        :persistent_term.put({__MODULE__, name}, pngs)
        pngs

      pngs ->
        pngs
    end
  end

  defp make({{kind, data}, {u, v}, facing}) do
    look = World.Sculpt.Texture.made(kind, data)
    {du, dv} = {u / @texels, v / @texels}

    # The place of a texel in the axes of the surface, and the side that it faces.
    {place, n} =
      case facing do
        :up -> {fn i, j -> {i * du, j * dv, 0.0} end, {0.0, 0.0, 1.0}}
        :side -> {fn i, j -> {i * du, 0.0, j * dv} end, {0.0, 1.0, 0.0}}
        # (Ribs along u: the profile goes along v.)
        :across -> {fn i, j -> {j * dv, i * du, 0.0} end, {0.0, 0.0, 1.0}}
      end

    texels =
      for j <- 0..(@texels - 1), i <- 0..(@texels - 1), into: %{} do
        {height, tone, to, _light} = World.Sculpt.Texture.look(look, place.(i + 0.5, j + 0.5), n, min(du, dv))
        part = if to, do: elem(to, 2), else: 1.0
        # (The frames of the panes are darker; the panes take the color of the role.)
        shade = if kind == "windows", do: tone * (0.6 + 0.4 * part), else: tone
        {{i, j}, {height, shade}}
      end

    h = fn i, j -> elem(texels[{rem(i + @texels, @texels), rem(j + @texels, @texels)}], 0) end

    colors =
      for j <- 0..(@texels - 1) do
        for i <- 0..(@texels - 1), into: <<>>, do: <<byte(elem(texels[{i, j}], 1))::8>> |> :binary.copy(3)
      end

    normals =
      for j <- 0..(@texels - 1) do
        for i <- 0..(@texels - 1), into: <<>> do
          {nx, ny, nz} =
            Vec.norm({-(h.(i + 1, j) - h.(i - 1, j)) / (2 * du), -(h.(i, j + 1) - h.(i, j - 1)) / (2 * dv), 1.0})

          <<byte((nx + 1) / 2)::8, byte((ny + 1) / 2)::8, byte((nz + 1) / 2)::8>>
        end
      end

    {PNG.encode(colors, 3), PNG.encode(normals, 3)}
  end

  @doc "The two PNG files of washed stone: `{color, normal}`."
  def washed_stone do
    case :persistent_term.get({__MODULE__, :washed_stone}, nil) do
      nil ->
        pngs = make_washed_stone()
        :persistent_term.put({__MODULE__, :washed_stone}, pngs)
        pngs

      pngs ->
        pngs
    end
  end

  # The colors of the pebbles (as a part of white): light grey, beige,
  # white, a darker grey and a warm brown, as in the photos of the render.
  @pebbles [{0.97, 0.96, 0.93}, {0.93, 0.89, 0.80}, {1.0, 1.0, 0.98}, {0.78, 0.77, 0.75}, {0.86, 0.79, 0.70}]
  @cement {0.80, 0.78, 0.73}

  defp make_washed_stone do
    cells = div(@size, @cell)

    stones =
      for cx <- 0..(cells - 1), cy <- 0..(cells - 1), into: %{} do
        {{cx, cy},
         {(cx + 0.25 + 0.5 * hash(cx, cy, 1)) * @cell, (cy + 0.25 + 0.5 * hash(cx, cy, 2)) * @cell,
          2.6 + 2.2 * hash(cx, cy, 3), Enum.at(@pebbles, trunc(hash(cx, cy, 4) * length(@pebbles)))}}
      end

    # The height and the color of each texel: the top of the highest
    # pebble over it, or the cement.
    texels =
      for y <- 0..(@size - 1), x <- 0..(@size - 1), into: %{} do
        {cx, cy} = {div(x, @cell), div(y, @cell)}

        best =
          for dx <- -1..1, dy <- -1..1, reduce: {0.0, @cement} do
            {h, _} = acc ->
              {px, py, r, color} = stones[{rem(cx + dx + cells, cells), rem(cy + dy + cells, cells)}]
              ddx = wrap(x - px)
              ddy = wrap(y - py)
              d2 = (ddx * ddx + ddy * ddy) / (r * r)
              top = if d2 < 1.0, do: r * :math.sqrt(1.0 - d2), else: 0.0
              if top > h, do: {top, color}, else: acc
          end

        {{x, y}, best}
      end

    h = fn x, y -> elem(texels[{rem(x + @size, @size), rem(y + @size, @size)}], 0) end

    color_rows =
      for y <- 0..(@size - 1) do
        for x <- 0..(@size - 1), into: <<>> do
          {top, {r, g, b}} = texels[{x, y}]
          # The cement between the pebbles is in a little shadow.
          shade = if top == 0.0, do: 0.92, else: 1.0
          <<byte(r * shade)::8, byte(g * shade)::8, byte(b * shade)::8>>
        end
      end

    normal_rows =
      for y <- 0..(@size - 1) do
        for x <- 0..(@size - 1), into: <<>> do
          {nx, ny, nz} = Vec.norm({-(h.(x + 1, y) - h.(x - 1, y)) / 2, (h.(x, y + 1) - h.(x, y - 1)) / 2, 1.0})
          <<byte((nx + 1) / 2)::8, byte((ny + 1) / 2)::8, byte((nz + 1) / 2)::8>>
        end
      end

    {PNG.encode(color_rows, 3), PNG.encode(normal_rows, 3)}
  end

  # The shortest offset on a tile that repeats.
  defp wrap(d) when d > @size / 2, do: d - @size
  defp wrap(d) when d < -@size / 2, do: d + @size
  defp wrap(d), do: d

  defp byte(v), do: v |> Kernel.*(255) |> round() |> max(0) |> min(255)

  # A number from 0 to 1 for a cell and a key: each build gives the same.
  defp hash(x, y, k), do: :erlang.phash2({x, y, k}, 1_000_000) / 1_000_000
end
