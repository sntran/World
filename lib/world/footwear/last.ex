defmodule World.Footwear.Last do
  @moduledoc """
  The last of a shoe: the form of the foot that a shoemaker makes the shoe
  on. Here it is the footprint of a bare foot of a person
  (`World.People.Human.footprint/2`), in the axes of the shoe: x across
  (to the outside of a right foot), y from the heel to the toes, z up.

  The sole of a shoe has the length of the last: the foot and 2 Paris
  points (a Paris point is 2/3 cm; the EU size is 3/2 of the length of
  the last in cm: Wikipedia, Shoe size, the European system). The heel
  of the foot is @heel from the back of the sole.

  Each part of a shoe (`World.Footwear.Sole`, `World.Footwear.Upper`)
  takes its places from the last: a row of the foot at a part of its
  length (`at/2`), the sole under it (`World.Footwear.Sole.top/2`).
  """
  alias World.People.Human

  defstruct foot: 0.0, length: 0.0, rows: []

  # A Paris point (m), and the sole behind the heel of the foot (by eye).
  @paris 2 / 300
  @heel 0.004

  @doc "The length of a Paris point (m)."
  def paris, do: @paris

  @doc """
  The last of the right foot of a person (the options of
  `World.People.Human.person/2`). The base mesh of the foot is sparse:
  each side of a row is the widest of the row and the rows next to it,
  then the mean of 5 rows.
  """
  def new(person \\ []) do
    fp = Human.footprint(person, "r")
    %__MODULE__{foot: fp.length, length: fp.length + 2 * @paris, rows: rows(fp)}
  end

  @doc """
  The EU size of a shoe for a foot of a length (m).

      iex> World.Footwear.Last.eu_size(0.24)
      38
      iex> World.Footwear.Last.eu_size(0.26)
      41
  """
  def eu_size(foot), do: round(1.5 * (foot + 2 * @paris) * 100)

  @doc "The place y (m) of a part of the length of the foot from its heel."
  def y(%__MODULE__{foot: foot}, part), do: @heel + part * foot

  @doc """
  The row of the foot at a part of its length from its heel: `{y, x0, x1,
  top}`, the inside and the outside of the foot, and the height of its top.
  """
  def at(%__MODULE__{rows: rows} = l, part) do
    y = y(l, part)
    {_, x0, x1, top} = Enum.min_by(rows, fn {ry, _, _, _} -> abs(ry - y) end)
    {y, x0, x1, top}
  end

  @doc """
  The rows of the foot from the heel to a part of its length.
  """
  def back(%__MODULE__{rows: rows} = l, part), do: Enum.filter(rows, fn {y, _, _, _} -> y <= y(l, part) end)

  @doc """
  The gap between the first and the second toe, where the post of a thong
  goes: at 88% of the length of the foot, a third of the width of the
  foot from its inside (by eye: the base mesh has no toes).
  """
  def toe_gap(%__MODULE__{} = l) do
    {y, x0, x1, _} = at(l, 0.88)
    {x0 + (x1 - x0) / 3, y}
  end

  # The rows of the footprint in the axes of the shoe: the heel of the
  # foot at y = @heel, the middle of the foot at x = 0.
  defp rows(%{rows: rows}) do
    [{y0, _, _, _} | _] = rows
    cx = rows |> Enum.map(fn {_, a, b, _} -> (a + b) / 2 end) |> then(&(Enum.sum(&1) / length(&1)))
    wide = near(rows, 1, fn group, {y, _, _, top} -> {y, min_of(group, 1), max_of(group, 2), top} end)

    near(wide, 2, fn group, {y, _, _, top} ->
      {y - y0 + @heel, mean_of(group, 1) - cx, mean_of(group, 2) - cx, top}
    end)
  end

  # Each row with the rows within k of it.
  defp near(rows, k, fun) do
    t = List.to_tuple(rows)
    n = tuple_size(t)
    for i <- 0..(n - 1), do: fun.(for(j <- max(i - k, 0)..min(i + k, n - 1), do: elem(t, j)), elem(t, i))
  end

  defp min_of(group, i), do: group |> Enum.map(&elem(&1, i)) |> Enum.min()
  defp max_of(group, i), do: group |> Enum.map(&elem(&1, i)) |> Enum.max()
  defp mean_of(group, i), do: (group |> Enum.map(&elem(&1, i)) |> Enum.sum()) / length(group)
end
