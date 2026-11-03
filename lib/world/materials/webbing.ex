defmodule World.Materials.Webbing do
  @moduledoc """
  Webbing and its hardware, as standard parts for any thing with a strap
  (a helmet, a bag, a harness, a tie-down).

  - `strap/4`: a flat strap of webbing along a path of points, with a
    port at each end.
  - `buckle/2`: a side-release buckle for a width of webbing, with a
    port for the strap at each end.

  The webbing is nylon (Nylon 6,6, 1.13 to 1.15 g/cm3: The Engineering
  ToolBox, Densities of solids), as a solid band of its thickness; a
  woven band has less mass (`TODO.md`). The buckle is acetal (POM,
  1.4 g/cm3, the same table).
  """
  alias World.{Loft, Mesh, Part, Shape, Vec}

  @doc """
  A strap of webbing of the width `w` along a path (two or more points,
  m). The options: `thickness` (1 mm), `across` (the direction of the
  width at the first point; perpendicular to the path by default),
  `material` (the role of its color, `:black`). Its ports: `a` at the
  first point and `b` at the last, in the axes of the part. Its params:
  the width, the thickness and the length.
  """
  def strap(name, [_, _ | _] = path, w, opts \\ []) do
    t = Keyword.get(opts, :thickness, 0.001)
    material = Keyword.get(opts, :material, :black)
    path = Enum.map(path, &Vec.float/1)
    sections = List.duplicate({w / 2, t / 2, 8}, length(path))
    {_, frames} = Loft.rows(Loft.new(path, sections, up: opts[:across]))
    band = Shape.loft(for({c, _, u, v} <- frames, do: {c, u, v, w / 2, t / 2, 8}), material, sides: 12)

    length = path |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [p, q] -> Vec.len(Vec.sub(q, p)) end) |> Enum.sum()

    Part.new(name, :strap, [Mesh.matter(band, :nylon)], [port("a", hd(path)), port("b", List.last(path))],
      params: %{"width" => w / 1, "thickness" => t / 1, "length" => Float.round(length, 4)},
      sources: ["Webbing of nylon, #{mm(w)} mm wide and #{mm(t)} mm thick."]
    )
  end

  @doc """
  A side-release buckle for webbing of the width `w`: the female body
  and the male tongue, locked. Its length along x (from the port
  `female` at x = 0 to the port `male`), its sizes from the width (by
  eye). The option `material` (`:black`).
  """
  def buckle(name, w, opts \\ []) do
    material = Keyword.get(opts, :material, :black)
    {bw, t} = {w * 1.3, w * 0.4}
    {lf, lm} = {w * 1.5, w * 1.1}

    female = Shape.box({0.0, -bw / 2, -t / 2}, {lf, bw / 2, t / 2}, material)
    male = Shape.box({lf, -bw / 2 * 0.9, -t / 2 * 0.8}, {lf + lm, bw / 2 * 0.9, t / 2 * 0.8}, material)

    Part.new(
      name,
      :buckle,
      Enum.map([female, male], &Mesh.matter(&1, :pom)),
      [port("female", {0.0, 0.0, 0.0}), port("male", {lf + lm, 0.0, 0.0})],
      params: %{"width" => w / 1},
      sources: ["A side-release buckle of acetal for webbing of #{mm(w)} mm; its sizes by eye."]
    )
  end

  defp port(name, at), do: Part.port(name, at, {0, 0, 1}, {0, 1, 0})

  defp mm(m), do: round(m * 1000)
end
