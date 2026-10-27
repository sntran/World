defmodule Xuong.Parts.Fasteners do
  @moduledoc """
  Bolts, screws, nuts and washers with metric threads, at the sizes of
  their ISO standards. The thread itself is not in the mesh.

  The axis of a fastener is its z axis. A hole of another part has a
  port with its axis into the hole: the bolt goes in along it.

  - A bolt or a screw: the head is from z = 0 up; the shank goes down to
    z = -length. Ports: `head` (under the head) and `tip`, each with the
    axis down the shank (-z).
  - A nut or a washer: from z = 0 up. Ports: `face` (z = 0) and `top`,
    with the axis +z. A nut on a bolt has its `face` on the far side of
    the parts, with the same axis as the bolt.
  """
  alias Xuong.{Part, Shape}

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

  @doc "The threads in the tables, from small to large."
  def threads, do: @hex_head |> Map.keys() |> Enum.sort_by(&diameter/1)

  @doc "The nominal diameter of a thread, in meters: `\"M8\"` is 0.008."
  def diameter("M" <> d), do: String.to_integer(d) / 1000

  @doc "The sizes of the tables, in meters, for the tests."
  def table(:hex_head, t), do: mm(Map.fetch!(@hex_head, t))
  def table(:nut, t), do: Map.fetch!(@nut_height, t) / 1000
  def table(:washer, t), do: mm(Map.fetch!(@washer, t))
  def table(:cap_head, t), do: mm(Map.fetch!(@cap_head, t))

  defp mm(t), do: t |> Tuple.to_list() |> Enum.map(&(&1 / 1000)) |> List.to_tuple()

  @doc "A hexagon head bolt (ISO 4017 when it has a full thread): `bolt(\"M8\", 0.060)`."
  def bolt(thread, length, opts \\ []) do
    {s, k} = table(:hex_head, thread)
    d = diameter(thread)
    head = Shape.prism(hexagon(s), k, :steel)
    shank = Shape.cylinder(d / 2, length, :steel, sides: 12, frame: Xuong.Frame.move({0, 0, -length}))

    fastener(
      "bolt_#{String.downcase(thread)}x#{mm_name(length)}",
      :bolt,
      [head, shank],
      thread,
      length,
      ["ISO 4017: s #{s * 1000} mm, k #{k * 1000} mm."],
      opts
    )
  end

  @doc "A hexagon socket head cap screw (ISO 4762)."
  def cap_screw(thread, length, opts \\ []) do
    {dk, k} = table(:cap_head, thread)
    d = diameter(thread)
    head = Shape.lathe([{0.0, k}, {dk / 2 * 0.92, k}, {dk / 2, k * 0.92}, {dk / 2, 0.0}, {0.0, 0.0}], :black, sides: 16)
    shank = Shape.cylinder(d / 2, length, :black, sides: 12, frame: Xuong.Frame.move({0, 0, -length}))

    fastener(
      "cap_screw_#{String.downcase(thread)}x#{mm_name(length)}",
      :cap_screw,
      [head, shank],
      thread,
      length,
      ["ISO 4762: dk #{dk * 1000} mm, k #{k * 1000} mm."],
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
      "nut_#{String.downcase(thread)}",
      :nut,
      [material(shape, opts)],
      flat_ports(m),
      params: %{"thread" => thread},
      sources: ["ISO 4032: s #{s * 1000} mm, m #{m * 1000} mm."],
      inside: Keyword.get(opts, :inside, false)
    )
  end

  @doc "A plain washer (ISO 7089)."
  def washer(thread, opts \\ []) do
    {d1, d2, h} = table(:washer, thread)
    shape = Shape.lathe([{d1 / 2, 0.0}, {d2 / 2, 0.0}, {d2 / 2, h}, {d1 / 2, h}], :steel, kind: :ring, sides: 16)

    Part.new(
      "washer_#{String.downcase(thread)}",
      :washer,
      [material(shape, opts)],
      flat_ports(h),
      params: %{"thread" => thread},
      sources: ["ISO 7089: d1 #{d1 * 1000} mm, d2 #{d2 * 1000} mm, h #{h * 1000} mm."],
      inside: Keyword.get(opts, :inside, false)
    )
  end

  defp flat_ports(h),
    do: [Part.port("face", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}), Part.port("top", {0, 0, h}, {0, 0, 1}, {0, 1, 0})]

  # A hexagon with the width `s` across its flats.
  defp hexagon(s), do: Shape.polygon(s / :math.sqrt(3), 6, 30.0)

  defp material(mesh, opts), do: %{mesh | material: Keyword.get(opts, :material, mesh.material)}

  defp mm_name(length), do: length |> Kernel.*(1000) |> round() |> Integer.to_string()
end
