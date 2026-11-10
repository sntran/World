defmodule World.Terrain do
  @moduledoc """
  The ground of a place of the world (plan 0006, D3): the height tiles of
  the Vũng Tàu game in `priv/terrain/NAME/`, a copy with no change, so a
  model that World builds on the ground goes back into the game at the
  same place (`geo/2`).

  The frame of the game: X to the east, Z to the south, the height up, in
  metres, the origin at Bãi Trước. Each tile `X_Z.png` covers 256 m with
  129 x 129 samples of 16-bit gray, one each 2 m; the height of a value
  is `offset + value * step` (`terrain.json`).

  The frame of World on a terrain: x to the east, y to the north, z up,
  from the point of a lot. So a point `{x, y, z}` of a model on the lot
  at the game point `{lx, lz}` and height `h` is at the game point
  `{lx + x, h + z, lz - y}` (for a model with no turn).
  """
  alias World.{Mesh, PNG}

  @dir Path.join(:code.priv_dir(:world), "terrain")
  @names for(d <- File.ls!(Path.join(__DIR__, "../../priv/terrain")), do: d) |> Enum.sort()
  for d <- @names, f <- File.ls!(Path.join(__DIR__, "../../priv/terrain/" <> d)) do
    @external_resource Path.join(__DIR__, "../../priv/terrain/#{d}/#{f}")
  end

  @doc "The names of the terrains."
  def names, do: @names

  @doc "The data of a terrain (`terrain.json`), with its tiles: `%{{x, z} => values}`."
  def load(name) when name in @names do
    case :persistent_term.get({__MODULE__, name}, nil) do
      nil ->
        dir = Path.join(@dir, name)
        meta = dir |> Path.join("terrain.json") |> File.read!() |> JSON.decode!()

        tiles =
          for f <- File.ls!(dir), [_, x, z] <- [Regex.run(~r/^(-?\d+)_(-?\d+)\.png$/, f)], into: %{} do
            {_, _, values} = PNG.decode_gray16(File.read!(Path.join(dir, f)))
            {{String.to_integer(x), String.to_integer(z)}, values}
          end

        t = Map.put(meta, "tiles", tiles)
        :persistent_term.put({__MODULE__, name}, t)
        t

      t ->
        t
    end
  end

  @doc "The height (m) of the ground at the game point `{x, z}`, or nil out of the tiles."
  def height(name, {x, z}) do
    t = load(name)
    g = t["grid_m"]
    {i, j} = {x / g, z / g}
    {i0, j0} = {floor(i), floor(j)}
    {fx, fz} = {i - i0, j - j0}
    s = [sample(t, i0, j0), sample(t, i0 + 1, j0), sample(t, i0, j0 + 1), sample(t, i0 + 1, j0 + 1)]

    if Enum.any?(s, &is_nil/1) do
      nil
    else
      [a, b, c, d] = s
      (a * (1 - fx) + b * fx) * (1 - fz) + (c * (1 - fx) + d * fx) * fz
    end
  end

  # The height of the sample of the grid (i, j): the sample is in the
  # tile of its point (the last row and column of a tile are the first of
  # the next).
  defp sample(t, i, j) do
    n = t["samples"] - 1
    {tx, tz} = {Integer.floor_div(i, n), Integer.floor_div(j, n)}

    case t["tiles"][{tx, tz}] do
      nil ->
        nil

      values ->
        %{"offset" => off, "step" => step} = t["height"]
        off + elem(values, (j - tz * n) * (n + 1) + (i - tx * n)) * step
    end
  end

  @doc """
  The mesh of the ground in the box `{x0, z0, x1, z1}` of the game, one
  point each `step` m, in the frame of World from the game point
  `origin` `{ox, oz}` at the height `oh` (x east, y north, z up). Each pad
  `{x, z, r, h}` makes the ground flat at the height `h` in the radius `r`
  round the game point `{x, z}`, and blends into the ground in the next
  `r / 2` (the ground of a lot, cut and filled). A point with no height
  (out of the tiles) is at the height of the sea floor of the game. A
  cell under the sea (each corner lower than `sea`, in metres) has no
  faces: a plane of the sea covers it.
  """
  def mesh(name, {x0, z0, x1, z1}, step, {ox, oz, oh}, material, pads \\ [], sea \\ -1.0) do
    {nx, nz} = {round((x1 - x0) / step), round((z1 - z0) / step)}
    t = load(name)
    floor_h = t["height"]["offset"] + 16.0

    grid =
      for j <- 0..nz, i <- 0..nx, into: %{} do
        {x, z} = {x0 + i * step, z0 + j * step}
        {{i, j}, {x, z, pad(height(name, {x, z}) || floor_h, {x, z}, pads)}}
      end

    # The cells, each with its four corners: the next is to the east, then
    # to the south.
    cells =
      for j <- 0..(nz - 1),
          i <- 0..(nx - 1),
          c = [{i, j}, {i + 1, j}, {i + 1, j + 1}, {i, j + 1}],
          Enum.any?(c, fn k -> elem(grid[k], 2) >= sea end),
          do: c

    index =
      cells |> Enum.concat() |> Enum.uniq() |> Enum.sort_by(fn {i, j} -> {j, i} end) |> Enum.with_index() |> Map.new()

    points =
      index
      |> Enum.sort_by(&elem(&1, 1))
      |> Enum.map(fn {k, _} ->
        {x, z, h} = grid[k]
        {x - ox, oz - z, h - oh}
      end)

    # Two triangles for each cell, not a quad: an open mesh of triangles
    # needs no pass of Wings (`World.Mesh.triangles/2`). The corners of a
    # face go round to the left, seen from over it, so the face turns up.
    faces = for c <- cells, [a, b, c, d] = Enum.map(c, &index[&1]), f <- [[a, c, b], [a, d, c]], do: f
    Mesh.new(points, faces, material, angle: 89.0)
  end

  defp pad(h, {x, z}, pads) do
    Enum.reduce(pads, h, fn {px, pz, r, ph}, h ->
      d = :math.sqrt((x - px) * (x - px) + (z - pz) * (z - pz))

      cond do
        d <= r -> ph
        d < 1.5 * r -> ph + (h - ph) * smooth((d - r) / (0.5 * r))
        true -> h
      end
    end)
  end

  defp smooth(t), do: t * t * (3 - 2 * t)

  @doc """
  The place of a model in the frame of the game (plan 0006, D5): the game
  point and height of its origin and its turn round the vertical (deg,
  from the north to the east), for the extras of the model (`"geo"`).
  """
  def geo({x, z}, h, turn),
    do: %{"frame" => "vung_tau_game", "at" => [x / 1, h / 1, z / 1], "turn" => turn / 1}
end
