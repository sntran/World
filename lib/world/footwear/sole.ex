defmodule World.Footwear.Sole do
  @moduledoc """
  The soles of a shoe: a stack of layers on the outline of its last
  (`World.Footwear.Last`), each a molded or cut part: an outsole of
  rubber, a midsole of EVA, a sole of tire rubber, a sole of wood, a grip
  pad. A layer is on the one under it.

  A layer: `name`, `heel` and `ball` (its thickness at the heel and from
  65% of the last to the toes), `role` (its color), `matter` (its mass),
  `side` (its margin out from the foot, 6 mm by default), `outline`
  (`:foot`, the outline of the foot, or `:board`, a board with round ends
  as wide as the foot is at its widest), `rim` (the radius of a rim round
  its top edge, or nil), `source`. The options of the stack: `rise` (the
  tip of the sole turned up: its height at the toes, 0 by default) and
  `base` (the height of the bottom of the stack: the teeth of a geta
  under it, `teeth/4`).
  """
  alias World.{Part, Shape}
  alias World.Footwear.Last

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @doc """
  The parts of a stack of layers on a last, from the ground up, and the
  height of its top at y: `%{parts: [part], top: fun}`. The first part is
  the bottom layer; each other part is on the one under it.
  """
  def stack(%Last{} = last, layers, opts \\ []) do
    rise = Keyword.get(opts, :rise, 0.0)
    base = Keyword.get(opts, :base, 0.0)
    lift = fn y -> base + rise * max(0.0, (y - 0.8 * last.length) / (0.2 * last.length)) ** 2 end

    {parts, top} =
      Enum.map_reduce(layers, fn y -> lift.(y) end, fn layer, below ->
        h = fn y -> thickness(layer, last, y) end
        {layer(last, layer, below, h), fn y -> below.(y) + h.(y) end}
      end)

    %{parts: parts, top: top}
  end

  @doc """
  The thickness of a layer at y: from the heel to 65% of the last, then
  the same to the toes.
  """
  def thickness(layer, %Last{length: l}, y) do
    {heel, ball} = {Keyword.fetch!(layer, :heel), Keyword.get(layer, :ball, Keyword.fetch!(layer, :heel))}
    heel + (ball - heel) * min(max(y, 0.0) / (0.65 * l), 1.0)
  end

  # A layer: sections along y, each the width of the foot and `side` at
  # each side, from the back of the last to its tip.
  defp layer(%Last{} = last, layer, below, h) do
    side = Keyword.get(layer, :side, 0.006)
    stations = if Keyword.get(layer, :outline, :foot) == :board, do: board(last, side), else: stations(last, side)

    mesh =
      stations
      |> Enum.map(fn {y, cx, w} ->
        {{cx, y, below.(y) + h.(y) / 2}, {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, w / 2, h.(y) / 2, 6}
      end)
      |> Shape.loft(Keyword.fetch!(layer, :role), sides: 24)
      |> World.Mesh.matter(Keyword.fetch!(layer, :matter))

    rim =
      case Keyword.get(layer, :rim) do
        nil ->
          []

        r ->
          edge = fn sign -> for {y, cx, w} <- stations, do: {cx + sign * (w / 2 - r), y, below.(y) + h.(y) - 0.001} end
          line = edge.(1) ++ Enum.reverse(edge.(-1))

          [
            (line ++ [hd(line)])
            |> Shape.sweep(r, Keyword.fetch!(layer, :role), sides: 8)
            |> World.Mesh.matter(Keyword.fetch!(layer, :matter))
          ]
      end

    Part.new(Keyword.fetch!(layer, :name), :sole, [mesh | rim], [@o],
      params: %{
        "heel" => Keyword.fetch!(layer, :heel),
        "ball" => Keyword.get(layer, :ball, Keyword.fetch!(layer, :heel)),
        "length" => Float.round(last.length, 4)
      },
      sources: List.wrap(Keyword.get(layer, :source, []))
    )
  end

  @doc """
  The teeth of a geta under a board on the last: a block across the board
  at each part of the length of the last, `height` high and `thick` along
  the last, as wide as the board. The options `role`, `matter`,
  `source`.
  """
  def teeth(name, %Last{} = last, {height, thick, parts}, opts) do
    {_, cx, w} = last |> board(Keyword.get(opts, :side, 0.006)) |> Enum.max_by(&elem(&1, 2))

    blocks =
      for part <- parts do
        y = part * last.length

        Shape.box({cx - w / 2, y - thick / 2, 0.0}, {cx + w / 2, y + thick / 2, height}, Keyword.fetch!(opts, :role))
        |> World.Mesh.matter(Keyword.fetch!(opts, :matter))
      end

    Part.new(name, :sole, blocks, [@o],
      params: %{"height" => height, "thick" => thick, "count" => length(parts)},
      sources: List.wrap(Keyword.get(opts, :source, []))
    )
  end

  # The outline of a board: as wide as the foot at its widest and `side`
  # at each side, its ends half round.
  defp board(%Last{rows: rows, length: l}, side) do
    {a, b} = {rows |> Enum.map(&elem(&1, 1)) |> Enum.min(), rows |> Enum.map(&elem(&1, 2)) |> Enum.max()}
    {cx, w} = {(a + b) / 2, b - a + 2 * side}
    r = w / 2

    for i <- 0..16 do
      y = l * i / 16
      d = min(y, l - y)
      half = if d < r, do: :math.sqrt(max(r * r - (r - d) ** 2, (0.15 * r) ** 2)), else: r
      {y, cx, 2 * half}
    end
  end

  @doc """
  The sections of the outline of a sole: `{y, middle, width}`, from the
  back of the last (y = 0) to its tip, `side` out from the foot.
  """
  def stations(%Last{rows: rows, length: l}, side) do
    ys = Enum.take_every(rows, 2)
    {_, a0, b0, _} = hd(ys)
    {_, a1, b1, _} = List.last(ys)

    [{0.0, (a0 + b0) / 2, (b0 - a0) * 0.6}] ++
      for({y, a, b, _} <- ys, do: {y, (a + b) / 2, b - a + 2 * side}) ++
      [{l, (a1 + b1) / 2, (b1 - a1) * 0.6}]
  end
end
