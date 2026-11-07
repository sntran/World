defmodule World.Skills.Robe do
  @moduledoc """
  The skill `robe` of a sculptor: the robe of a statue on its figure (the
  data of a node `figure`, `World.Skills.Figure`), as shapes for the cast:
  a long column from the neck to the feet, its sleeves along the bones of
  the arms, the two long panels at its sides (by eye from the photos of
  the statue on Núi Nhỏ), and a mitt round each hand of `arms_out`. Its
  data: `meshes` (none with `robe` false).
  """
  @behaviour World.Skill
  alias World.{Shape, Vec}
  alias World.Skills.Statue

  @names ~w(robe)

  @impl true
  def name, do: "robe"

  @impl true
  def trade, do: :sculptor

  @impl true
  def check(data, path), do: Statue.check(data, path, @names)

  @impl true
  def estimate(_data, _level), do: 0

  @impl true
  def make(data, %{"figure" => %{"figure" => fig}}, _context) do
    o = Statue.o(data, @names)
    {nil, %{"meshes" => if(o.robe, do: robe(fig), else: [])}, %{}}
  end

  # In units of the person.
  defp robe(%{scale: s, marks: m, hands: hands}) do
    sh = elem(m["upperarm_l"], 2) / s
    neck = elem(m["head"], 2) / s
    yc = 0.01 * s

    column =
      [
        {0.0, 0.215, 0.135},
        {0.06, 0.215, 0.135},
        {0.07, 0.205, 0.13},
        {0.5, 0.19, 0.12},
        {0.95, 0.185, 0.125},
        {sh - 0.12, 0.2, 0.14},
        {sh, 0.215, 0.13},
        {sh + 0.05, 0.17, 0.1},
        {neck, 0.07, 0.07}
      ]
      |> Enum.map(fn {z, hx, hy} -> {{0.0, yc, z * s}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, hx * s, hy * s, 3.5} end)
      |> Shape.loft(:concrete, sides: 24)

    panels =
      for side <- [-1.0, 1.0] do
        Shape.loft(
          [
            {{side * 0.235 * s, yc, (sh - 0.02) * s}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, 0.035 * s, 0.12 * s, 4.0},
            {{side * 0.23 * s, yc, 0.42 * s}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, 0.035 * s, 0.11 * s, 4.0}
          ],
          :concrete,
          sides: 16
        )
      end

    sleeves = for side <- ~w(l r), do: sleeve(m["upperarm_" <> side], m["lowerarm_" <> side], m["hand_" <> side], s)
    [column | panels ++ sleeves ++ Enum.map(hands, &mitt/1)]
  end

  # A mitt round the points of a hand out to the side: from the wrist to
  # the tip, a little narrower at the tip.
  defp mitt({{x0, y0, z0}, {x1, y1, z1}}) do
    {c, hy, hz} = {fn x -> {x, (y0 + y1) / 2, (z0 + z1) / 2} end, (y1 - y0) / 2 + 0.02, (z1 - z0) / 2 + 0.02}
    {inner, outer} = if abs(x0) < abs(x1), do: {x0, x1}, else: {x1, x0}
    mid = inner + 0.7 * (outer - inner)

    [{inner, 1.0}, {mid, 1.0}, {outer, 0.75}]
    |> Enum.map(fn {x, k} -> {c.(x), {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}, hy * k, hz * k, 4.0} end)
    |> Shape.loft(:concrete, sides: 16)
  end

  # A sleeve: wide at the shoulder (and lower, as it hangs), narrow at the
  # wrist.
  defp sleeve(shoulder, elbow, wrist, s) do
    d1 = Vec.norm(Vec.sub(elbow, shoulder))
    d2 = Vec.norm(Vec.sub(wrist, elbow))

    [
      {Vec.sub(shoulder, Vec.scale(d1, 0.04 * s)), d1, 0.1, 0.14, -0.08},
      {shoulder, d1, 0.1, 0.14, -0.08},
      {elbow, Vec.norm(Vec.add(d1, d2)), 0.075, 0.095, -0.035},
      {Vec.sub(wrist, Vec.scale(d2, 0.01 * s)), d2, 0.06, 0.055, 0.0}
    ]
    |> Enum.map(fn {at, d, hu, hv, down} ->
      v = across(d)
      u = Vec.cross(v, d)
      {Vec.add(at, Vec.scale(v, down * s)), u, v, hu * s, hv * s, 4.0}
    end)
    |> Shape.loft(:concrete, sides: 16)
  end

  # The direction across a bone toward the top (or the front, for a bone
  # that goes up or down).
  defp across(d) do
    hint = if abs(Vec.dot(d, {0.0, 0.0, 1.0})) > 0.9, do: {0.0, 1.0, 0.0}, else: {0.0, 0.0, 1.0}
    Vec.norm(Vec.sub(hint, Vec.scale(d, Vec.dot(hint, d))))
  end
end
