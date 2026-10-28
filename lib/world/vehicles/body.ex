defmodule World.Vehicles.Body do
  @moduledoc """
  The lofted body of a car or a van: sections along y (the length) from
  key rows, with the arches of the wheels cut up from the bottom.

  A key row is `{y, z_low, z_high, half_width, power}`. Between two key
  rows, the values change in a straight line. An arch `{y, z, radius}`
  lifts the bottom of the body over a wheel: at a distance `dy` from the
  axle, the bottom is at least `z + sqrt(radius² - dy²)`.
  """
  alias World.Shape

  @doc """
  A loft of the key rows, with arches, in `steps` of y (0.1 m). Option
  `x0`: the center of the rows (0 by default), for a fender at one side.
  """
  def loft(keys, arches, material, opts \\ []) do
    {x0, opts} = Keyword.pop(opts, :x0, 0.0)
    step = World.Detail.step(Keyword.get(opts, :step, 0.1))
    {y0, y1} = {elem(hd(keys), 0), elem(List.last(keys), 0)}
    n = max(round((y1 - y0) / step), 1)
    even = for i <- 0..n, do: y0 + (y1 - y0) * i / n

    at_arches =
      for {ay, _, r} <- arches,
          k <- -6..6//arch_step(),
          y = ay + r * :math.sin(k * :math.pi() / 12),
          y > y0 and y < y1,
          do: y

    ys =
      (even ++ Enum.map(keys, &elem(&1, 0)) ++ at_arches)
      |> Enum.map(&Float.round(&1 / 1, 4))
      |> Enum.uniq()
      |> Enum.sort()

    rows =
      for y <- ys do
        {z0, z1, hw, p} = between(keys, y)
        {y, max(z0, arch_bottom(arches, y)), z1, hw, p}
      end

    Shape.loft(Shape.rows_y(rows, x0), material, Keyword.merge([smooth: 1, sides: 20], opts))
  end

  defp arch_step, do: if(World.Detail.level() == :near, do: 1, else: 2)

  # The values of the key rows at y, in a straight line between two rows.
  defp between(keys, y) do
    [a, b] =
      keys
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.find(List.last(Enum.chunk_every(keys, 2, 1, :discard)), fn [{ya, _, _, _, _}, {yb, _, _, _, _}] ->
        y >= ya and y <= yb
      end)

    {ya, z0a, z1a, hwa, pa} = a
    {yb, z0b, z1b, hwb, pb} = b
    t = if yb == ya, do: 0.0, else: (y - ya) / (yb - ya)
    lerp = fn u, v -> u + (v - u) * t end
    {lerp.(z0a, z0b), lerp.(z1a, z1b), lerp.(hwa, hwb), lerp.(pa, pb)}
  end

  defp arch_bottom(arches, y) do
    Enum.reduce(arches, 0.0, fn {ay, az, r}, acc ->
      dy = abs(y - ay)
      if dy < r, do: max(acc, az + :math.sqrt(r * r - dy * dy)), else: acc
    end)
  end
end
