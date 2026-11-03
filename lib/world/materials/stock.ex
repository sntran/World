defmodule World.Materials.Stock do
  @moduledoc """
  Stock: tubes, rods, lumber, sheets, plates, aluminum extrusions and ball
  bearings, at the sizes of their standards or of the trade.

  An end port has its axis out of the part, along its length. A face
  port has its axis into the part. So the end of one part connects to the
  face of another with the same port axis.
  """
  alias World.{Frame, Part, Shape}
  # The tables of the standards (`priv/standards/stock.json`): lumber (US
  # softwood, ASTM D245 and PS 20: the nominal size, and the dry size in
  # inches), deep groove ball bearings (ISO 15: d, D, B in mm), steel pipe
  # (ASME B36.10M: the outside diameter, the wall of schedule 40 and of
  # schedule 80, in inches).
  @lumber World.Standards.tuples({"stock", "lumber"})
  @bearings World.Standards.tuples({"stock", "bearing"})
  @pipe World.Standards.tuples({"stock", "pipe"})
  # The sawn timber of Việt Nam (TCVN 1075:1971): its thicknesses and its
  # widths, in mm.
  @vn World.Standards.table("stock", "vn_lumber")["sizes"]

  @doc "The sizes of a table, in meters, for the tests."
  def table(:lumber, nominal), do: @lumber |> Map.fetch!(nominal) |> then(fn {t, w} -> {t * 0.0254, w * 0.0254} end)

  def table(:bearing, code),
    do: @bearings |> Map.fetch!(code) |> then(fn {d, o, b} -> {d / 1000, o / 1000, b / 1000} end)

  @doc """
  A size of the sawn timber of Việt Nam (TCVN 1075:1971): the least
  thickness or width of the standard that is not less than `size` (m),
  in m. A width over 320 mm takes a width of 360 to 600 mm, which the
  standard gives by agreement of the mill and the buyer. The rules of a
  wooden boat round each size up to it (QCVN 91, II.II-B 2.3).

      iex> World.Materials.Stock.vn(:thickness, 0.055)
      0.06
      iex> World.Materials.Stock.vn(:width, 0.21)
      0.22
      iex> World.Materials.Stock.vn(:width, 0.33)
      0.36
  """
  def vn(kind, size) when kind in [:thickness, :width] do
    mm = Float.round(size * 1000, 3)

    sizes = if kind == :width, do: @vn["width"] ++ @vn["width_by_agreement"], else: @vn["thickness"]

    case Enum.find(sizes, &(&1 >= mm)) do
      nil -> raise ArgumentError, "no #{kind} of TCVN 1075 is #{mm} mm or more"
      v -> v / 1000
    end
  end

  @doc """
  A section of the sawn timber of Việt Nam (TCVN 1075:1971, Bảng 1): the
  smallest pair of a thickness and one of its widths that is not less than
  `{thickness, width}` (m), as `{thickness, width}` in m. With no pair (a
  width over 320 mm), the next thickness and a width by agreement.

      iex> World.Materials.Stock.vn_section(0.22, 0.308)
      {0.25, 0.32}
      iex> World.Materials.Stock.vn_section(0.092, 0.22)
      {0.14, 0.22}
      iex> World.Materials.Stock.vn_section(0.3, 0.4)
      {0.32, 0.4}
  """
  def vn_section(t, w) do
    {tm, wm} = {Float.round(t * 1000, 3), Float.round(w * 1000, 3)}

    pairs =
      for {th, widths} <- @vn["pairs"], th = String.to_integer(th), th >= tm, wd <- widths, wd >= wm, do: {th, wd}

    case Enum.min_by(pairs, fn {a, b} -> {a * b, a} end, fn -> nil end) do
      nil -> {vn(:thickness, t), vn(:width, w)}
      {a, b} -> {a / 1000, b / 1000}
    end
  end

  @doc "The names in a table."
  def names(:lumber), do: Map.keys(@lumber) |> Enum.sort()
  def names(:bearing), do: Map.keys(@bearings) |> Enum.sort()
  def names(:pipe), do: Map.keys(@pipe) |> Enum.sort()

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

  @doc """
  A steel pipe along z, of a nominal pipe size (ASME B36.10M) and a
  schedule (`:sch40` or `:sch80`), as `tube/5`: `pipe("1", :sch40, 2.0)`.
  """
  def pipe(nps, schedule, length, opts \\ []) do
    {od, sch40, sch80} = Map.fetch!(@pipe, nps)
    wall = if schedule == :sch40, do: sch40, else: sch80
    s = if schedule == :sch40, do: "40", else: "80"

    tube(
      od * 0.0254,
      wall * 0.0254,
      length,
      Keyword.get(opts, :material, :steel),
      Keyword.merge(
        [
          name: "pipe_nps_#{String.replace(nps, ["-", "/"], "_")}_sch#{s}x#{mm(length)}",
          sources: ["Steel pipe, ASME B36.10M: NPS #{nps}, schedule #{s}, #{od} in outside, a wall of #{wall} in."]
        ],
        opts
      )
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
