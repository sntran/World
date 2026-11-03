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
  # The tables of the standards (`priv/standards/fasteners.json`, read
  # when World.Standards compiles): a metric size in mm, an inch size in
  # inches. A bolt (ISO 4014, 4017): the width across the flats s and the
  # height of the head k. A nut (ISO 4032): its height m. A washer (ISO
  # 7089): d1, d2, h. A cap screw (ISO 4762) and a button head (ISO 7380):
  # dk, k. A wood screw (ASME B18.6.1): D, A, H. The inch threads (ASME
  # B18.2.1, B18.2.2, B18.3, SAE): the hex head, the nut, the washer and
  # the button head.
  @hex_head World.Standards.tuples({"fasteners", "hex_head"})
  @nut_height World.Standards.tuples({"fasteners", "nut"})
  @washer World.Standards.tuples({"fasteners", "washer"})
  @cap_head World.Standards.tuples({"fasteners", "cap_head"})
  @wood_screw World.Standards.tuples({"fasteners", "wood_screw"})
  @button_head World.Standards.tuples({"fasteners", "button_head"})
  @inch (for {thread, t} <- World.Standards.table("fasteners", "inch")["sizes"], into: %{} do
           {thread,
            %{
              hex: List.to_tuple(t["hex"]),
              nut: t["nut"],
              washer: List.to_tuple(t["washer"]),
              button: List.to_tuple(t["button"])
            }}
         end)

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
