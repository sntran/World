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

  A texture is only at near (`World.Detail`): at mid and far a pebble is
  smaller than a texel of the screen, and the file stays small.
  """

  alias World.{PNG, Vec}

  @size 256
  @cell 8
  @tile 0.3

  @doc "The names of the textures."
  def names, do: ~w(washed_stone)

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

  def spec(_name, _level), do: nil

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
