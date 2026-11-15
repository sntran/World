defmodule World.Earth do
  @moduledoc """
  The heights of the real Earth, for a project with a planet
  (`docs/plans/0019-world-serves-the-projects.md`, 7.2): the project
  sends points (a latitude and a longitude in degrees), and World
  answers the height of each (m over the level of the sea; less than 0
  under it).

  The data is ETOPO1 of NOAA (the surface of the ice), one value each
  quarter of a degree: `priv/earth/etopo1_025.i16.gz`, 721 rows from the
  south to the north, 1,441 values in a row from 180 degrees west to
  180 degrees east, each a whole number of 16 bits. A point between
  four values has their mean by its distances (bilinear).
  """

  @rows 721
  @cols 1441
  @most 200_000

  @doc "The height (m) at a latitude (-90 to 90) and a longitude (any number of degrees: it wraps)."
  def height(lat, lon) when is_number(lat) and is_number(lon) and lat >= -90 and lat <= 90 do
    grid = grid()
    # (The place in the grid, in cells: 4 cells for each degree.)
    {y, x} = {(lat + 90) * 4, (wrap(lon) + 180) * 4}
    {r, c} = {min(trunc(y), @rows - 2), min(trunc(x), @cols - 2)}
    {v, u} = {y - r, x - c}

    at(grid, r, c) * (1 - u) * (1 - v) + at(grid, r, c + 1) * u * (1 - v) +
      at(grid, r + 1, c) * (1 - u) * v + at(grid, r + 1, c + 1) * u * v
  end

  @doc """
  The heights of a list of points `[lat, lon]`, each a whole number of
  meters: `{:ok, heights}`, or `{:error, errors}` with the path of each
  wrong point (at most #{@most} points in one call).
  """
  def heights(points) when is_list(points) and length(points) <= @most do
    errors =
      for {p, i} <- Enum.with_index(points),
          not match?([lat, lon] when is_number(lat) and is_number(lon) and lat >= -90 and lat <= 90, p),
          do: %{
            "path" => "points.#{i}",
            "message" => "must be [latitude, longitude] in degrees, the latitude from -90 to 90"
          }

    if errors == [],
      do: {:ok, for([lat, lon] <- points, do: round(height(lat, lon)))},
      else: {:error, Enum.take(errors, 20)}
  end

  def heights(_points), do: {:error, [%{"path" => "points", "message" => "must be a list of at most #{@most} points"}]}

  @doc "The source of the data, for the credits of a project."
  def source,
    do:
      "ETOPO1 1 Arc-Minute Global Relief Model (Amante, C. and B. W. Eakins, NOAA Technical Memorandum NESDIS NGDC-24, 2009), the surface of the ice, one value each quarter of a degree. NOAA: the data may be used and redistributed for free."

  defp wrap(lon), do: lon - 360 * Float.floor((lon + 180) / 360)

  defp at(grid, r, c) do
    <<v::signed-big-16>> = binary_part(grid, (r * @cols + c) * 2, 2)
    v
  end

  # The grid in the memory of the node: 2 MB, read one time.
  defp grid do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        grid = :world |> Application.app_dir("priv/earth/etopo1_025.i16.gz") |> File.read!() |> :zlib.gunzip()
        :persistent_term.put(__MODULE__, grid)
        grid

      grid ->
        grid
    end
  end
end
