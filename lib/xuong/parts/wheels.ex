defmodule Xuong.Parts.Wheels do
  @moduledoc """
  Tires, rims and wheels. A wheel turns around its z axis, with its
  center at the origin. Each wheel has the port `hub` (the center, the
  axis +z): a vehicle puts it on an axle port with the axis to its right
  side.

  The size of a tire comes from its code:

  - a motorcycle or a car (ETRTO, ISO 4000 and ISO 5751): `"80/90-14"` or
    `"215/50R17"`: the width in mm, the height of the side as a percent of
    the width, and the rim in inches;
  - a bicycle (ETRTO, ISO 5775): `"37-622"`: the width and the bead seat
    diameter, both in mm.
  """
  alias Xuong.{Assembly, Frame, Part, Shape, Vec}

  @doc """
  The sizes of a tire code, in meters: `%{width, height, rim}` (the rim
  is the bead seat diameter) and the outer diameter.
  """
  def tire_size(code) do
    size =
      case Regex.run(~r{^(\d+)/(\d+)\s*[-R ]\s*(\d+(?:\.\d+)?)$}, code) do
        [_, w, ratio, rim] ->
          w = String.to_integer(w) / 1000
          %{width: w, height: w * String.to_integer(ratio) / 100, rim: parse_number(rim) * 0.0254}

        nil ->
          case Regex.run(~r{^(\d+)-(\d+)$}, code) do
            [_, w, bsd] ->
              w = String.to_integer(w) / 1000
              # A bicycle tire is near round: its height is near its width.
              %{width: w, height: w * 0.92, rim: String.to_integer(bsd) / 1000}

            nil ->
              raise ArgumentError, "unknown tire code #{inspect(code)}"
          end
      end

    Map.put(size, :diameter, size.rim + 2 * size.height)
  end

  defp parse_number(s), do: if(String.contains?(s, "."), do: String.to_float(s), else: String.to_integer(s) / 1)

  @doc """
  A tire. The options: `profile` (`:round` for a motorcycle or a bicycle,
  `:flat` for a car), `rim_width` (in meters), `sides`.
  """
  def tire(code, opts \\ []) do
    %{width: w, height: h, rim: d} = size = tire_size(code)
    r0 = d / 2
    wb = Keyword.get(opts, :rim_width, w * 0.62) / 2
    hw = w / 2

    half =
      case Keyword.get(opts, :profile, :round) do
        :flat ->
          [
            {r0, wb},
            {r0 + 0.12 * h, wb + (hw - wb) * 0.7},
            {r0 + 0.38 * h, hw},
            {r0 + 0.72 * h, hw * 0.99},
            {r0 + 0.93 * h, hw * 0.96},
            {r0 + h, hw * 0.86},
            {r0 + h, hw * 0.3}
          ]

        :round ->
          [
            {r0, wb},
            {r0 + 0.14 * h, hw * 0.88},
            {r0 + 0.42 * h, hw},
            {r0 + 0.72 * h, hw * 0.9},
            {r0 + 0.9 * h, hw * 0.62},
            {r0 + 0.98 * h, hw * 0.3}
          ]
      end

    profile = half ++ [{r0 + h, 0.0}] ++ Enum.reverse(for {r, z} <- half, do: {r, -z})

    Part.new(
      "tire_#{String.replace(code, ~r{[^0-9A-Za-z]+}, "_")}",
      :tire,
      Shape.lathe(profile, :tire, kind: :ring, sides: Keyword.get(opts, :sides, 48)),
      [hub_port()],
      params: %{"code" => code, "diameter" => Float.round(size.diameter, 4)},
      sources: [
        "ETRTO #{code}: width #{round(w * 1000)} mm, side #{round(h * 1000)} mm, rim #{Float.round(d * 1000, 1)} mm."
      ]
    )
  end

  @doc """
  A rim: a ring with a well and two flanges, for a bead seat diameter and
  a width (meters). Options: `depth` of the well, `flange`, `material`.
  """
  def rim(diameter, width, opts \\ []) do
    r0 = diameter / 2
    depth = Keyword.get(opts, :depth, 0.02)
    f = Keyword.get(opts, :flange, 0.012)
    t = 0.004
    hw = width / 2
    ri = r0 - depth

    profile = [
      {ri, -hw},
      {ri, hw},
      {r0 + f, hw + t},
      {r0 + f, hw},
      {r0, hw - t},
      {r0, -hw + t},
      {r0 + f, -hw},
      {r0 + f, -hw - t}
    ]

    Part.new(
      "rim_#{round(diameter * 1000)}x#{round(width * 1000)}",
      :rim,
      Shape.lathe(profile, Keyword.get(opts, :material, :rim), kind: :ring, sides: Keyword.get(opts, :sides, 48)),
      [hub_port()],
      params: %{"diameter" => diameter, "width" => width}
    )
  end

  @doc """
  A cast wheel of a motorbike or a scooter: a rim, a hub, `spokes` curved
  spokes (5 by default), the tire, and with `disc: true` a brake disc on
  the left side (+z).
  """
  def cast_wheel(code, opts \\ []) do
    %{width: w, rim: d} = tire_size(code)
    rim_w = Keyword.get(opts, :rim_width, w * 0.7)
    rim = rim(d, rim_w, depth: 0.016, flange: 0.01)
    ri = d / 2 - 0.016
    n = Keyword.get(opts, :spokes, 5)
    hub_r = 0.045

    hub =
      Part.new(
        "hub_cast",
        :hub,
        Shape.lathe([{0.0, -0.06}, {0.03, -0.06}, {hub_r, -0.045}, {hub_r, 0.045}, {0.03, 0.06}, {0.0, 0.06}], :rim,
          sides: 24
        ),
        [hub_port()]
      )

    spokes =
      for k <- 0..(n - 1) do
        a = 360 * k / n
        line = for i <- 0..4, do: spoke_point(hub_r * 0.9, ri + 0.004, a, 14.0, i / 4)
        Part.new("spoke_cast", :spoke, Shape.sweep(line, 0.009, :rim, sides: 8, smooth: 1), [hub_port()])
      end

    asm =
      Assembly.new("wheel_cast_#{String.replace(code, ~r{[^0-9A-Za-z]+}, "_")}", rim, root: "rim", kind: :wheel)
      |> Assembly.add("tire", tire(code, Keyword.merge([rim_width: rim_w], opts)), at: "hub", port: "hub")
      |> Assembly.add("hub", hub, at: "hub", port: "hub")
      |> add_all("spoke", spokes)

    if Keyword.get(opts, :disc, false),
      do:
        Assembly.add(asm, "disc", brake_disc(0.19),
          at: Xuong.Port.new("disc", {0, 0, 0.05}, {0, 0, 1}, {0, 1, 0}),
          port: "hub"
        ),
      else: asm
  end

  # A point on a curved spoke: from the hub to the rim, turning by `bend`
  # degrees on the way.
  defp spoke_point(r0, r1, a, bend, t) do
    r = r0 + (r1 - r0) * t
    ang = (a + bend * :math.sin(t * :math.pi() / 2)) * :math.pi() / 180
    {r * :math.cos(ang), r * :math.sin(ang), 0.0}
  end

  @doc "A brake disc of a diameter (meters), 4 mm thick, with its center ring."
  def brake_disc(diameter, opts \\ []) do
    ro = diameter / 2

    disc =
      Shape.lathe([{ro * 0.72, -0.002}, {ro, -0.002}, {ro, 0.002}, {ro * 0.72, 0.002}], :steel, kind: :ring, sides: 36)

    carrier =
      Shape.lathe(
        [{0.03, -0.002}, {ro * 0.74, -0.002}, {ro * 0.74, 0.002}, {0.03, 0.002}],
        Keyword.get(opts, :material, :rim),
        kind: :ring,
        sides: 24
      )

    Part.new("brake_disc_#{round(diameter * 1000)}", :brake_disc, [disc, carrier], [hub_port()],
      params: %{"diameter" => diameter}
    )
  end

  @doc """
  A wheel with wire spokes (a bicycle, a classic motorcycle): a rim, a hub
  with two flanges, `spokes` spokes (36 by default) laced three-cross,
  the tire, and with `disc: diameter` a brake disc on the +z side.
  """
  def spoked_wheel(code, opts \\ []) do
    %{width: w, rim: d} = tire_size(code)
    rim_w = Keyword.get(opts, :rim_width, max(w * 0.55, 0.018))

    rim =
      rim(d, rim_w,
        depth: Keyword.get(opts, :rim_depth, 0.02),
        flange: 0.004,
        material: Keyword.get(opts, :rim_material, :aluminum)
      )

    ri = d / 2 - Keyword.get(opts, :rim_depth, 0.02)
    n = Keyword.get(opts, :spokes, 36)
    {flange_r, flange_z} = {0.028, Keyword.get(opts, :hub_width, 0.07) / 2}

    hub =
      Part.new(
        "hub_spoked",
        :hub,
        Shape.lathe(
          [
            {0.0, -flange_z - 0.012},
            {0.012, -flange_z - 0.012},
            {0.012, -flange_z - 0.002},
            {flange_r, -flange_z},
            {flange_r, -flange_z + 0.003},
            {0.016, -flange_z + 0.006},
            {0.016, flange_z - 0.006},
            {flange_r, flange_z - 0.003},
            {flange_r, flange_z},
            {0.012, flange_z + 0.002},
            {0.012, flange_z + 0.012},
            {0.0, flange_z + 0.012}
          ],
          :aluminum,
          sides: 20
        ),
        [hub_port()]
      )

    half = div(n, 2)
    cross = 360 / half * Keyword.get(opts, :cross, 3) / 2

    spokes =
      for k <- 0..(n - 1) do
        side = if rem(k, 2) == 0, do: 1, else: -1
        a = 360 * k / n
        dir = if rem(div(k, 2), 2) == 0, do: 1, else: -1
        from = polar(flange_r * 0.92, a + dir * cross, side * (flange_z - 0.0015))
        to = polar(ri, a, 0.0)

        Part.new("spoke_wire", :spoke, Shape.sweep([from, to], 0.001, :steel, sides: 4), [hub_port()],
          params: %{"gauge" => "2.0 mm"}
        )
      end

    asm =
      Assembly.new("wheel_spoked_#{String.replace(code, ~r{[^0-9A-Za-z]+}, "_")}", rim, root: "rim", kind: :wheel)
      |> Assembly.add("tire", tire(code, Keyword.merge([rim_width: rim_w], opts)), at: "hub", port: "hub")
      |> Assembly.add("hub", hub, at: "hub", port: "hub")
      |> add_all("spoke", spokes)

    case Keyword.get(opts, :disc) do
      nil ->
        asm

      d ->
        Assembly.add(asm, "disc", brake_disc(d),
          at: Xuong.Port.new("disc", {0, 0, flange_z + 0.014}, {0, 0, 1}, {0, 1, 0}),
          port: "hub"
        )
    end
  end

  @doc """
  A car wheel: a rim with a face of `spokes` spokes (5), the center cap,
  `lugs` lug nuts (5) on the circle `pcd` (0.1143 m), and the tire
  (`car_wheel("215/50R17")`). The face is on the +z side.
  """
  def car_wheel(code, opts \\ []) do
    %{width: w, rim: d} = tire_size(code)
    rim_w = Keyword.get(opts, :rim_width, w * 0.86)
    rim = rim(d, rim_w, depth: 0.03, flange: 0.016, material: Keyword.get(opts, :rim_material, :aluminum))
    ri = d / 2 - 0.03
    n = Keyword.get(opts, :spokes, 5)
    face_z = rim_w / 2 - 0.012

    center =
      Part.new(
        "wheel_center",
        :hub,
        Shape.lathe(
          [{0.0, face_z - 0.03}, {0.085, face_z - 0.03}, {0.085, face_z}, {0.06, face_z + 0.01}, {0.0, face_z + 0.012}],
          Keyword.get(opts, :rim_material, :aluminum),
          sides: 24
        ),
        [hub_port()]
      )

    spokes =
      for k <- 0..(n - 1) do
        a = 360 * k / n

        sections =
          for {t, hw} <- [{0.0, 0.03}, {0.5, 0.022}, {1.0, 0.03}] do
            r = 0.075 + (ri - 0.075) * t
            {polar(r, a, face_z - 0.012 * t), tangent(a), {0.0, 0.0, 1.0}, hw, 0.014, 4}
          end

        Part.new(
          "spoke_car",
          :spoke,
          Shape.loft(sections, Keyword.get(opts, :rim_material, :aluminum), sides: 12, smooth: 1),
          [hub_port()]
        )
      end

    # The lug nuts on the face, on their circle (PCD).
    pcd = Keyword.get(opts, :pcd, 0.1143)
    lugs = Keyword.get(opts, :lugs, 5)

    asm =
      Assembly.new("wheel_car_#{String.replace(code, ~r{[^0-9A-Za-z]+}, "_")}", rim, root: "rim", kind: :wheel)
      |> Assembly.add("tire", tire(code, Keyword.merge([rim_width: rim_w, profile: :flat], opts)),
        at: "hub",
        port: "hub"
      )
      |> Assembly.add("center", center, at: "hub", port: "hub")
      |> add_all("spoke", spokes)

    Enum.reduce(1..lugs//1, asm, fn k, a ->
      at = polar(pcd / 2, 360 * k / lugs + 36, face_z + 0.002)

      Assembly.add(a, "lug_#{k}", Xuong.Parts.Fasteners.nut("M12", material: :chrome),
        at: Xuong.Port.new("lug_#{k}", at, {0, 0, 1}, {0, 1, 0}),
        port: "face"
      )
    end)
  end

  defp polar(r, deg, z) do
    a = deg * :math.pi() / 180
    {r * :math.cos(a), r * :math.sin(a), z / 1}
  end

  defp tangent(deg) do
    a = deg * :math.pi() / 180
    Vec.norm({-:math.sin(a), :math.cos(a), 0.0})
  end

  defp hub_port, do: Part.port("hub", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  # Add parts with the names `prefix_1`, `prefix_2`, ... at the hub.
  defp add_all(asm, prefix, parts) do
    parts
    |> Enum.with_index(1)
    |> Enum.reduce(asm, fn {p, i}, a -> Assembly.add(a, "#{prefix}_#{i}", p, at: "hub", port: "hub") end)
  end

  @doc "The frame of an axle: a point, with the axis to the right side (+x) of a vehicle."
  def axle(at), do: Frame.new(at, {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0})
end
