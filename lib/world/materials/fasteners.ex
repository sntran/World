defmodule World.Materials.Fasteners do
  @moduledoc """
  Bolts, screws, nuts and washers with metric threads (ISO) and unified
  inch threads (ASME: "1/4-20", "1/2-13"), at the sizes of their
  standards, button head screws, and wood screws. The thread itself is not in the mesh.

  The axis of a fastener is its z axis. A hole of another part has a
  port with its axis into the hole: the bolt goes in along it.

  - A bolt or a screw: the head is from z = 0 up; the shank goes down to
    z = -length. Ports: `head` (under the head) and `tip`, each with the
    axis down the shank (-z).
  - A wood screw (flat head, in gauges of ASME B18.6.1): the head goes
    into the wood, with its top at z = 0. The ports are as for a bolt.
  - A nut or a washer: from z = 0 up. Ports: `face` (z = 0) and `top`,
    with the axis +z. A nut on a bolt has its `face` on the far side of
    the parts, with the same axis as the bolt.
  """
  alias World.{Part, Shape}
  # Hexagon head bolt (ISO 4014, ISO 4017): the width across the flats s,
  # and the height of the head k, in mm.
  @hex_head %{
    "M3" => {5.5, 2.0},
    "M4" => {7.0, 2.8},
    "M5" => {8.0, 3.5},
    "M6" => {10.0, 4.0},
    "M8" => {13.0, 5.3},
    "M10" => {16.0, 6.4},
    "M12" => {18.0, 7.5},
    "M14" => {21.0, 8.8},
    "M16" => {24.0, 10.0},
    "M20" => {30.0, 12.5},
    "M24" => {36.0, 15.0}
  }

  # Hexagon nut (ISO 4032): the height m, in mm (s is as for the bolt).
  @nut_height %{
    "M3" => 2.4,
    "M4" => 3.2,
    "M5" => 4.7,
    "M6" => 5.2,
    "M8" => 6.8,
    "M10" => 8.4,
    "M12" => 10.8,
    "M14" => 12.8,
    "M16" => 14.8,
    "M20" => 18.0,
    "M24" => 21.5
  }

  # Plain washer (ISO 7089): the inner diameter d1, the outer d2 and the
  # thickness h, in mm.
  @washer %{
    "M3" => {3.2, 7.0, 0.5},
    "M4" => {4.3, 9.0, 0.8},
    "M5" => {5.3, 10.0, 1.0},
    "M6" => {6.4, 12.0, 1.6},
    "M8" => {8.4, 16.0, 1.6},
    "M10" => {10.5, 20.0, 2.0},
    "M12" => {13.0, 24.0, 2.5},
    "M14" => {15.0, 28.0, 2.5},
    "M16" => {17.0, 30.0, 3.0},
    "M20" => {21.0, 37.0, 3.0},
    "M24" => {25.0, 44.0, 4.0}
  }

  # Hexagon socket head cap screw (ISO 4762): the head diameter dk and its
  # height k, in mm.
  @cap_head %{
    "M3" => {5.5, 3.0},
    "M4" => {7.0, 4.0},
    "M5" => {8.5, 5.0},
    "M6" => {10.0, 6.0},
    "M8" => {13.0, 8.0},
    "M10" => {16.0, 10.0},
    "M12" => {18.0, 12.0},
    "M16" => {24.0, 16.0},
    "M20" => {30.0, 20.0}
  }

  # Flat head wood screw (ASME B18.6.1), by its gauge: the diameter of the
  # thread D, the diameter of the head A and its height H, in inches.
  @wood_screw %{
    "#6" => {0.138, 0.279, 0.083},
    "#8" => {0.164, 0.332, 0.100},
    "#10" => {0.190, 0.385, 0.116},
    "#12" => {0.216, 0.438, 0.132}
  }

  # The unified inch threads (ASME B18.2.1 and B18.2.2): the width across
  # the flats of a hex head, the height of the head, the height of a hex
  # nut; a SAE flat washer: its inner and outer diameters and its
  # thickness; a socket button head (ASME B18.3): its diameter and its
  # height. All in inches.
  @inch %{
    "1/4-20" => %{hex: {0.4375, 0.156}, nut: 0.219, washer: {0.281, 0.625, 0.065}, button: {0.437, 0.132}},
    "5/16-18" => %{hex: {0.5, 0.203}, nut: 0.266, washer: {0.344, 0.688, 0.065}, button: {0.547, 0.166}},
    "3/8-16" => %{hex: {0.5625, 0.234}, nut: 0.328, washer: {0.406, 0.812, 0.065}, button: {0.656, 0.199}},
    "1/2-13" => %{hex: {0.75, 0.312}, nut: 0.438, washer: {0.531, 1.062, 0.095}, button: {0.875, 0.265}}
  }

  # Socket button head screws with metric threads (ISO 7380): the head
  # diameter dk and its height k, in mm.
  @button_head %{"M4" => {7.6, 2.2}, "M5" => {9.5, 2.75}, "M6" => {10.5, 3.3}, "M8" => {14.0, 4.4}}

  @doc "The metric threads in the tables, from small to large."
  def threads, do: @hex_head |> Map.keys() |> Enum.sort_by(&diameter/1)

  @doc "The unified inch threads in the tables, from small to large."
  def inch_threads, do: @inch |> Map.keys() |> Enum.sort_by(&diameter/1)

  @doc """
  The nominal diameter of a thread, in meters: `"M8"` is 0.008, and
  `"1/2-13"` (1/2 in, 13 threads to the inch) is 0.0127.
  """
  def diameter("M" <> d), do: String.to_integer(d) / 1000

  def diameter(inch) do
    [n, d] = inch |> String.split("-") |> hd() |> String.split("/")
    String.to_integer(n) / String.to_integer(d) * 0.0254
  end

  @doc "The sizes of the tables, in meters, for the tests."
  def table(kind, "M" <> _ = t), do: metric(kind, t)
  def table(kind, t), do: inch(kind, Map.fetch!(@inch, t))

  defp metric(:hex_head, t), do: mm(Map.fetch!(@hex_head, t))
  defp metric(:nut, t), do: Map.fetch!(@nut_height, t) / 1000
  defp metric(:washer, t), do: mm(Map.fetch!(@washer, t))
  defp metric(:cap_head, t), do: mm(Map.fetch!(@cap_head, t))
  defp metric(:button_head, t), do: mm(Map.fetch!(@button_head, t))

  defp inch(:hex_head, %{hex: h}), do: inches(h)
  defp inch(:nut, %{nut: m}), do: m * 0.0254
  defp inch(:washer, %{washer: w}), do: inches(w)
  defp inch(:button_head, %{button: b}), do: inches(b)

  defp inches(t), do: t |> Tuple.to_list() |> Enum.map(&(&1 * 0.0254)) |> List.to_tuple()

  defp mm(t), do: t |> Tuple.to_list() |> Enum.map(&(&1 / 1000)) |> List.to_tuple()

  @doc "A hexagon head bolt (ISO 4017 when it has a full thread): `bolt(\"M8\", 0.060)`."
  def bolt(thread, length, opts \\ []) do
    {s, k} = table(:hex_head, thread)
    d = diameter(thread)
    head = Shape.prism(hexagon(s), k, :steel)
    shank = Shape.cylinder(d / 2, length, :steel, sides: 12, frame: World.Frame.move({0, 0, -length}))

    fastener(
      "bolt_#{thread_name(thread)}x#{mm_name(length)}",
      :bolt,
      [head, shank],
      thread,
      length,
      [
        standard(thread, "ISO 4017", "ASME B18.2.1") <>
          ": s #{Float.round(s * 1000, 2)} mm, k #{Float.round(k * 1000, 2)} mm."
      ],
      opts
    )
  end

  @doc "A hexagon socket head cap screw (ISO 4762)."
  def cap_screw(thread, length, opts \\ []) do
    {dk, k} = table(:cap_head, thread)
    d = diameter(thread)
    head = Shape.lathe([{0.0, k}, {dk / 2 * 0.92, k}, {dk / 2, k * 0.92}, {dk / 2, 0.0}, {0.0, 0.0}], :black, sides: 16)
    shank = Shape.cylinder(d / 2, length, :black, sides: 12, frame: World.Frame.move({0, 0, -length}))

    fastener(
      "cap_screw_#{thread_name(thread)}x#{mm_name(length)}",
      :cap_screw,
      [head, shank],
      thread,
      length,
      ["ISO 4762: dk #{dk * 1000} mm, k #{k * 1000} mm."],
      opts
    )
  end

  @doc """
  A flat head wood screw (ASME B18.6.1): `wood_screw("#8", inch(2.5))`.
  The head goes into the wood: its top is at z = 0 (on the face of the
  wood), and the length (with the head) goes down to z = -length, with a
  point.
  """
  def wood_screw(gauge, length, opts \\ []) do
    {d, a, h} = @wood_screw |> Map.fetch!(gauge) |> Tuple.to_list() |> Enum.map(&(&1 * 0.0254)) |> List.to_tuple()
    tip = min(d * 2, length / 3)

    shape =
      Shape.lathe([{0.0, 0.0}, {a / 2, 0.0}, {d / 2, -h}, {d / 2, -length + tip}, {0.0, -length}], :steel, sides: 10)

    fastener(
      "wood_screw_#{String.trim_leading(gauge, "#")}x#{mm_name(length)}",
      :wood_screw,
      [shape],
      gauge,
      length,
      [
        "ASME B18.6.1: gauge #{gauge}, D #{Float.round(d * 1000, 2)} mm, A #{Float.round(a * 1000, 2)} mm, H #{Float.round(h * 1000, 2)} mm."
      ],
      opts
    )
  end

  @doc """
  A socket button head screw: ISO 7380 for a metric thread, ASME B18.3 for
  an inch thread (`button_screw("1/4-20", 0.0127)`), the screw of the
  brackets of T-slot extrusions.
  """
  def button_screw(thread, length, opts \\ []) do
    {dk, k} = table(:button_head, thread)
    d = diameter(thread)
    head = Shape.lathe([{0.0, k}, {dk / 4, k}, {dk / 2 * 0.85, k * 0.55}, {dk / 2, 0.0}, {0.0, 0.0}], :black, sides: 16)
    shank = Shape.cylinder(d / 2, length, :black, sides: 12, frame: World.Frame.move({0, 0, -length}))

    fastener(
      "button_screw_#{thread_name(thread)}x#{mm_name(length)}",
      :button_screw,
      [head, shank],
      thread,
      length,
      [
        standard(thread, "ISO 7380", "ASME B18.3") <>
          ": head #{Float.round(dk * 1000, 2)} mm, height #{Float.round(k * 1000, 2)} mm."
      ],
      opts
    )
  end

  defp fastener(name, kind, shapes, thread, length, sources, opts) do
    Part.new(
      name,
      kind,
      Enum.map(shapes, &material(&1, opts)),
      [Part.port("head", {0, 0, 0}, {0, 0, -1}, {0, 1, 0}), Part.port("tip", {0, 0, -length}, {0, 0, -1}, {0, 1, 0})],
      params: %{"thread" => thread, "length" => length},
      sources: sources,
      inside: Keyword.get(opts, :inside, false)
    )
  end

  @doc "A hexagon nut (ISO 4032)."
  def nut(thread, opts \\ []) do
    {s, _} = table(:hex_head, thread)
    m = table(:nut, thread)
    d = diameter(thread)
    # A ring: the hexagon (r to its corners) with the hole of the thread.
    r = s / :math.sqrt(3)
    shape = Shape.lathe([{d / 2, 0.0}, {r, 0.0}, {r, m}, {d / 2, m}], :steel, kind: :ring, sides: 6)

    Part.new(
      "nut_#{thread_name(thread)}",
      :nut,
      [material(shape, opts)],
      flat_ports(m),
      params: %{"thread" => thread},
      sources: [
        standard(thread, "ISO 4032", "ASME B18.2.2") <>
          ": s #{Float.round(s * 1000, 2)} mm, m #{Float.round(m * 1000, 2)} mm."
      ],
      inside: Keyword.get(opts, :inside, false)
    )
  end

  @doc "A plain washer (ISO 7089)."
  def washer(thread, opts \\ []) do
    {d1, d2, h} = table(:washer, thread)
    shape = Shape.lathe([{d1 / 2, 0.0}, {d2 / 2, 0.0}, {d2 / 2, h}, {d1 / 2, h}], :steel, kind: :ring, sides: 16)

    Part.new(
      "washer_#{thread_name(thread)}",
      :washer,
      [material(shape, opts)],
      flat_ports(h),
      params: %{"thread" => thread},
      sources: [
        standard(thread, "ISO 7089", "SAE flat washer") <>
          ": d1 #{Float.round(d1 * 1000, 2)} mm, d2 #{Float.round(d2 * 1000, 2)} mm, h #{Float.round(h * 1000, 2)} mm."
      ],
      inside: Keyword.get(opts, :inside, false)
    )
  end

  defp flat_ports(h),
    do: [Part.port("face", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}), Part.port("top", {0, 0, h}, {0, 0, 1}, {0, 1, 0})]

  # A hexagon with the width `s` across its flats.
  defp hexagon(s), do: Shape.polygon(s / :math.sqrt(3), 6, 30.0)

  defp material(mesh, opts), do: %{mesh | material: Keyword.get(opts, :material, mesh.material)}

  @doc """
  The name of a thread in the name of a part: `"M8"` is `"m8"`, `"1/2-13"`
  is `"1_2_13"`.
  """
  def thread_name(thread), do: thread |> String.downcase() |> String.replace(["/", "-"], "_")

  defp standard("M" <> _, metric, _inch), do: metric
  defp standard(_, _metric, inch), do: inch

  defp mm_name(length), do: length |> Kernel.*(1000) |> round() |> Integer.to_string()
end
