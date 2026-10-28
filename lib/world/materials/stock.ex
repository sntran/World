defmodule World.Materials.Stock do
  @moduledoc """
  Stock: tubes, rods, lumber, sheets, plates, aluminum extrusions and ball
  bearings, at the sizes of their standards or of the trade.

  An end port has its axis out of the part, along its length. A face
  port has its axis into the part. So the end of one part connects to the
  face of another with the same port axis.
  """
  alias World.{Frame, Part, Shape}
  # Lumber (US softwood, ASTM D245 and the American Softwood Lumber
  # Standard PS 20): the nominal size and the dry size in inches.
  @lumber %{
    "1x2" => {0.75, 1.5},
    "1x4" => {0.75, 3.5},
    "1x6" => {0.75, 5.5},
    "2x2" => {1.5, 1.5},
    "2x3" => {1.5, 2.5},
    "2x4" => {1.5, 3.5},
    "2x6" => {1.5, 5.5},
    "2x8" => {1.5, 7.25},
    "4x4" => {3.5, 3.5}
  }

  # Deep groove ball bearings (ISO 15): the bore d, the outer diameter D
  # and the width B, in mm.
  @bearings %{
    "6000" => {10, 26, 8},
    "6001" => {12, 28, 8},
    "6002" => {15, 32, 9},
    "6003" => {17, 35, 10},
    "6004" => {20, 42, 12},
    "6005" => {25, 47, 12},
    "6200" => {10, 30, 9},
    "6201" => {12, 32, 10},
    "6202" => {15, 35, 11},
    "6203" => {17, 40, 12},
    "6204" => {20, 47, 14},
    "6205" => {25, 52, 15},
    "6301" => {12, 37, 12},
    "6302" => {15, 42, 13}
  }

  @doc "The sizes of a table, in meters, for the tests."
  def table(:lumber, nominal), do: @lumber |> Map.fetch!(nominal) |> then(fn {t, w} -> {t * 0.0254, w * 0.0254} end)

  def table(:bearing, code),
    do: @bearings |> Map.fetch!(code) |> then(fn {d, o, b} -> {d / 1000, o / 1000, b / 1000} end)

  @doc "The names in a table."
  def names(:lumber), do: Map.keys(@lumber) |> Enum.sort()
  def names(:bearing), do: Map.keys(@bearings) |> Enum.sort()

  @doc """
  A round tube along z, from 0 to `length`: the outer diameter and the
  wall. Ports: `end_a` (z = 0, axis -z), `end_b` (z = length, axis +z),
  `center` (axis +z).
  """
  def tube(od, wall, length, material, opts \\ []) do
    {ro, ri} = {od / 2, od / 2 - wall}

    shape =
      Shape.lathe([{ri, 0.0}, {ro, 0.0}, {ro, length}, {ri, length}], material,
        kind: :ring,
        sides: Keyword.get(opts, :sides, 16)
      )

    long(
      "tube_#{mm(od)}x#{mm(wall)}x#{mm(length)}",
      :tube,
      shape,
      length,
      %{"od" => od, "wall" => wall, "length" => length},
      opts
    )
  end

  @doc "A round rod along z, as `tube/5` with no hole."
  def rod(d, length, material, opts \\ []) do
    shape = Shape.cylinder(d / 2, length, material, sides: Keyword.get(opts, :sides, 12))
    long("rod_#{mm(d)}x#{mm(length)}", :rod, shape, length, %{"d" => d, "length" => length}, opts)
  end

  defp long(name, kind, shape, length, params, opts) do
    Part.new(
      Keyword.get(opts, :name, name),
      kind,
      shape,
      [
        Part.port("end_a", {0, 0, 0}, {0, 0, -1}, {0, 1, 0}),
        Part.port("end_b", {0, 0, length}, {0, 0, 1}, {0, 1, 0}),
        Part.port("center", {0, 0, length / 2}, {0, 0, 1}, {0, 1, 0})
      ],
      params: params,
      sources: Keyword.get(opts, :sources, []),
      inside: Keyword.get(opts, :inside, false)
    )
  end

  @doc """
  A piece of lumber along x, from 0 to `length`: its wide side in y and
  its thin side in z (`lumber("2x4", 2.4)`). Ports: `end_a`, `end_b` (out
  of the ends), `bottom`, `top` (into the faces, at the middle).
  """
  def lumber(nominal, length, opts \\ []) do
    {t, w} = table(:lumber, nominal)
    shape = Shape.box({0, 0, 0}, {length, w, t}, Keyword.get(opts, :material, :wood))

    Part.new(
      "lumber_#{nominal}x#{mm(length)}",
      :lumber,
      shape,
      [
        Part.port("end_a", {0, w / 2, t / 2}, {-1, 0, 0}, {0, 0, 1}),
        Part.port("end_b", {length, w / 2, t / 2}, {1, 0, 0}, {0, 0, 1}),
        Part.port("bottom", {length / 2, w / 2, 0}, {0, 0, 1}, {1, 0, 0}),
        Part.port("top", {length / 2, w / 2, t}, {0, 0, -1}, {1, 0, 0})
      ],
      params: %{"nominal" => nominal, "length" => length},
      sources: [
        "Softwood lumber, PS 20: a #{nominal} is #{Float.round(t / 0.0254, 3)} in by #{Float.round(w / 0.0254, 3)} in."
      ]
    )
  end

  @doc """
  A sheet (plywood, sheet metal) from x = 0 to `w`, y = 0 to `d`, z = 0
  to `t`. Ports: `bottom` and `top` (into the faces, at the middle).
  """
  def sheet(w, d, t, material, opts \\ []) do
    plate(
      [{0, 0}, {w, 0}, {w, d}, {0, d}],
      t,
      material,
      Keyword.put_new(opts, :name, "sheet_#{mm(w)}x#{mm(d)}x#{mm(t)}")
    )
  end

  @doc "A plate: a loop of points `{x, y}` (counterclockwise) with a thickness, from z = 0."
  def plate(loop, t, material, opts \\ []) do
    {cx, cy} = centroid(loop)

    Part.new(
      Keyword.get(opts, :name, "plate_#{mm(t)}"),
      Keyword.get(opts, :kind, :sheet),
      Shape.prism(loop, t, material),
      [Part.port("bottom", {cx, cy, 0}, {0, 0, 1}, {0, 1, 0}), Part.port("top", {cx, cy, t}, {0, 0, -1}, {0, 1, 0})],
      params: %{"thickness" => t},
      sources: Keyword.get(opts, :sources, [])
    )
  end

  defp centroid(loop) do
    n = length(loop)
    {Enum.sum(Enum.map(loop, &elem(&1, 0))) / n, Enum.sum(Enum.map(loop, &elem(&1, 1))) / n}
  end

  @doc """
  An aluminum extrusion with T-slots (`extrusion("2020", 0.3)`): one of
  `World.Framing.profiles/0`.
  """
  def extrusion(profile, length, opts \\ []), do: World.Framing.extrusion(profile, length, opts)

  @doc """
  A deep groove ball bearing (`bearing("6203")`): the outer ring and the
  inner ring, around z, centered at z = 0. Ports: `center` (axis +z) and
  `face` (z = -B/2, axis +z).
  """
  def bearing(code, opts \\ []) do
    {d, od, b} = table(:bearing, code)
    {ri, ro} = {d / 2, od / 2}
    mid = (ri + ro) / 2

    outer =
      Shape.lathe(
        [{mid + (ro - mid) * 0.35, -b / 2}, {ro, -b / 2}, {ro, b / 2}, {mid + (ro - mid) * 0.35, b / 2}],
        :steel,
        kind: :ring,
        sides: 24
      )

    inner =
      Shape.lathe(
        [{ri, -b / 2}, {mid - (mid - ri) * 0.35, -b / 2}, {mid - (mid - ri) * 0.35, b / 2}, {ri, b / 2}],
        :steel,
        kind: :ring,
        sides: 24
      )

    seal =
      Shape.lathe(
        [
          {mid - (mid - ri) * 0.35, -b / 2 * 0.9},
          {mid + (ro - mid) * 0.35, -b / 2 * 0.9},
          {mid + (ro - mid) * 0.35, b / 2 * 0.9},
          {mid - (mid - ri) * 0.35, b / 2 * 0.9}
        ],
        :black,
        kind: :ring,
        sides: 24
      )

    Part.new(
      "bearing_#{code}",
      :bearing,
      [outer, inner, seal],
      [Part.port("center", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}), Part.port("face", {0, 0, -b / 2}, {0, 0, 1}, {0, 1, 0})],
      params: %{"code" => code},
      sources: ["ISO 15, bearing #{code}: d #{d * 1000} mm, D #{od * 1000} mm, B #{b * 1000} mm."],
      inside: Keyword.get(opts, :inside, true)
    )
  end

  @doc "A helical spring along z from 0 to `length`: the mean diameter, the wire and the turns."
  def spring(diameter, wire, length, turns, material, opts \\ []) do
    steps = turns * 12
    line = for i <- 0..steps, do: helix(diameter / 2, length, i / steps, turns)

    Part.new(
      Keyword.get(opts, :name, "spring_#{mm(diameter)}x#{mm(length)}"),
      :spring,
      Shape.sweep(line, wire / 2, material, sides: 6),
      [Part.port("end_a", {0, 0, 0}, {0, 0, -1}, {0, 1, 0}), Part.port("end_b", {0, 0, length}, {0, 0, 1}, {0, 1, 0})],
      params: %{"diameter" => diameter, "wire" => wire, "length" => length, "turns" => turns}
    )
  end

  defp helix(r, length, t, turns) do
    a = 2 * :math.pi() * turns * t
    {r * :math.cos(a), r * :math.sin(a), length * t}
  end

  @doc "A frame that moves a part along its own axes: for a port at a point of a part."
  def at(x, y, z), do: Frame.move({x, y, z})

  defp mm(v), do: v |> Kernel.*(1000) |> round() |> Integer.to_string()
end
