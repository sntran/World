defmodule Xuong.Models.Van do
  @moduledoc """
  The vans of DIY and of Phượt, from their data (`priv/data/vans.json`):
  the hull (`Xuong.Models.Hull`) from the traces of the side and the
  numbers of the maker, and the parts on it, from photos of the van.

  The Ford Transit (2020 to 2026, US) has:

  - the body in the role `paint` (white by default), with the hood on a
    hinge at its back, over the engine bay;
  - the black bumpers, the black band and the black edge between the
    wheels, the black flares over the wheels;
  - the grille (a hexagon) with the oval, the headlamps that sweep back
    to an amber tip, two vents on the hood, the black strip at the base
    of the windshield;
  - the windshield and the windows of the front doors, the mirrors;
  - the sliding door at the right side, the two rear doors, the lamps at
    the back and the stop lamp at the top;
  - the wheels (235/65R16 on steel rims), and the axles where the
    numbers of Ford put them.

  A point of the van is at `d` back from its front; the parts are made
  with the back of the van at y = 0, and the assembly moves it to its
  center. The numbers of the parts come from the photos and the drawings
  in the sources of the make (`d` and `z` in meters).
  """
  alias Xuong.{Assembly, Detail, Frame, Part, Shape, Vec}
  alias Xuong.Models.{Hull, Vehicle, VanGear}
  alias Xuong.Parts.Wheels

  @external_resource data_path = Path.join([__DIR__, "..", "..", "..", "priv", "data", "vans.json"])
  @data data_path |> File.read!() |> JSON.decode!()

  # The white of the van (Oxford White): its color by eye from the photos.
  @white %{"color" => [240, 241, 238], "roughness" => 0.32, "metalness" => 0.05}

  @doc "The names of the models of vans."
  def models, do: @data["models"] |> Map.keys() |> Enum.sort()

  @doc "The data of a model, with its make."
  def model(name) do
    m = Map.fetch!(@data["models"], name)
    Map.put(m, "make_data", Map.fetch!(@data["makes"], m["make"]))
  end

  @doc "The hull of a model."
  def hull(name) do
    m = model(name)
    make = m["make_data"]
    t = make["traces"][m["roof"]]
    h = make["hull"]
    {height, top} = {m["height"] / 1, t["top"] / 1}

    # The points over 2 m stretch to the height of the model.
    z = fn
      "top" -> height
      z when z > 2.0 -> 2.0 + (z - 2.0) * (height - 2.0) / (top - 2.0)
      z -> z / 1
    end

    line = fn pts -> for [d, zz] <- pts, do: {d / 1, z.(zz)} end
    {f, wb} = {m["front"] / 1, m["wheelbase"] / 1}
    r = Wheels.tire_radius(m["tire"])
    [af, ar] = h["arches"]

    Hull.new(
      length: m["length"] / 1,
      width: m["width"] / 1,
      top: height,
      front: line.(make["front"] ++ t["roof"]),
      back: line.(t["back"]),
      sill: h["sill"] / 1,
      arches: [{f, r, af / 1}, {f + wb, r, ar / 1}],
      belt: h["belt"] / 1,
      lean: h["lean"] / 1,
      edge: h["edge"] / 1,
      crown: List.to_tuple(Enum.map(h["crown"], &(&1 / 1))),
      nose: List.to_tuple(Enum.map(h["nose"], &(&1 / 1))),
      tail: List.to_tuple(Enum.map(h["tail"], &(&1 / 1)))
    )
  end

  # The half length of each item on the roof, along the van.
  @roof_items %{fan: 0.286, solar: 0.861}

  @doc "The half length of an item on the roof (`:fan`, `:solar`), along the van."
  def roof_item(kind), do: Map.fetch!(@roof_items, kind)

  @doc """
  The flat part of the roof of a model: the first and the last `d` (from
  the front) where an item can be.
  """
  def roof_span(name) do
    h = hull(name)
    {d0, d1} = Hull.span(h)
    flat = Enum.find(Hull.stations(h, d0, d1, 0.01), &(Hull.z_high(h, &1) >= h.top - 1.0e-6))
    {flat, h.length - Hull.back(h, h.top)}
  end

  @doc """
  A van. The options: `name` of the assembly, `windows` (`:cargo`, the
  default: the windows of the cab only; `:crew`: the windows of the
  second row too; `:passenger`: the windows all around), `engine_bay` (the items of DIY in the bay:
  `:dc_charger`, `:second_alternator`), `roof` (the items on the roof:
  `{:fan, d}` and `{:solar, d}`, at `d` from the front).
  """
  def build(model_name, opts \\ []) do
    m = model(model_name)
    h = hull(model_name)
    windows = Keyword.get(opts, :windows, :cargo)
    l = h.length
    {f, wb} = {m["front"] / 1, m["wheelbase"] / 1}
    [tf, tr] = m["track"]
    wheel = Wheels.car_wheel(m["tire"], face: :disc, holes: 10, pcd: 0.18, lugs: 5, rim_material: :steel)
    rz = Wheels.tire_radius(m["tire"])

    Assembly.new(Keyword.get(opts, :name, "van_" <> model_name), body(h, m),
      root: "body",
      kind: :vehicle,
      sources: m["sources"] ++ m["make_data"]["sources"],
      materials: %{paint: @white},
      place: Frame.move({0.0, -l / 2, 0.0})
    )
    |> Assembly.add("trim", trim(h, m), at: "origin", port: "origin")
    |> Assembly.add("glass", glass(h, m, windows), at: "origin", port: "origin")
    |> Assembly.add("lamps", lamps(h), at: "origin", port: "origin")
    |> Assembly.add("grille", grille(h), at: "origin", port: "origin")
    |> Assembly.add("mirrors", mirrors(h, m), at: "origin", port: "origin")
    |> details(h, m)
    |> Assembly.add("hood", hood(h),
      at: "hood",
      port: "hinge",
      kind: :turns,
      role: :lid,
      limits: [0, 60]
    )
    |> add_sliding_door(h, m, windows)
    |> add_rear_doors(h, m, windows)
    |> engine_bay(h, Keyword.get(opts, :engine_bay, []))
    |> roof(h, Keyword.get(opts, :roof, []))
    |> Vehicle.corner("front_right", wheel, {tf / 2, l - f, rz}, steer: true, limits: [-38, 38], disc: 0.30)
    |> Vehicle.corner("front_left", wheel, {-tf / 2, l - f, rz}, steer: true, limits: [-38, 38], disc: 0.30)
    |> Vehicle.corner("rear_right", wheel, {tr / 2, l - f - wb, rz}, disc: 0.30)
    |> Vehicle.corner("rear_left", wheel, {-tr / 2, l - f - wb, rz}, disc: 0.30)
  end

  defp port(name, at, axis, up), do: Part.port(name, at, axis, up)
  defp origin, do: port("origin", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  # The hood: from its front edge (the top of the grille) to the black
  # strip at the base of the windshield.
  @hood {0.132, 0.634}
  # The engine bay: under the hood, between the fenders (x from -0.6 to
  # 0.6), over its floor (z = 0.5).
  @bay {0.2, 0.62, 0.6, 0.5}

  # The body: the nose, the two fenders and the floor of the bay, and the
  # cab and the cargo area from the firewall to the back.
  defp body(h, m) do
    {d0, d1} = Hull.span(h)
    {b0, b1, bx, bz} = @bay
    side = fn x -> fn _ -> [x] end end

    shapes = [
      Hull.skin(h, d0, b0, :paint),
      Hull.skin(h, b0, b1, :paint, clip: side.({:x_min, bx})),
      Hull.skin(h, b0, b1, :paint, clip: side.({:x_max, -bx})),
      Hull.skin(h, b0, b1, :paint, clip: side.({:z_max, bz})),
      Hull.skin(h, b1, d1, :paint)
    ]

    {_, hd1} = @hood
    hz = Hull.z_high(h, hd1)
    {f, wb, [tf, tr]} = {m["front"], m["wheelbase"], m["track"]}
    rz = Wheels.tire_radius(m["tire"])

    corners =
      for {name, x, d} <- [
            {"front_right", tf / 2, f},
            {"front_left", -tf / 2, f},
            {"rear_right", tr / 2, f + wb},
            {"rear_left", -tr / 2, f + wb}
          ],
          do: Vehicle.corner_port("corner_#{name}", {x, h.length - d, rz})

    Part.new("body_" <> m["make"], :body, shapes, [
      origin(),
      port("hood", {0.0, h.length - hd1, hz - 0.006}, {1, 0, 0}, {0, 0, 1}) | corners
    ])
  end

  # A skin on a region of the hull, at the right side (x > 0), the left
  # side, or both.
  defp sides(h, d0, d1, material, planes, opts) do
    for s <- [1, -1] do
      Hull.skin(h, d0, d1, material, [clip: fn d -> mirror(planes.(d), s) end] ++ opts)
    end
  end

  defp mirror(planes, 1), do: planes

  defp mirror(planes, -1) do
    for p <- planes do
      case p do
        {:x_min, v} -> {:x_max, -v}
        {:x_max, v} -> {:x_min, -v}
        other -> other
      end
    end
  end

  # The black plastic: the bumpers, the band and the edge between the
  # wheels, the flares over the wheels, the strip at the base of the
  # windshield.
  defp trim(h, m) do
    {d0, d1} = Hull.span(h)
    l = h.length
    {f, wb} = {m["front"], m["wheelbase"]}
    [{_, az, af}, {_, _, ar}] = h.arches
    {_, hd1} = @hood
    # The sliding door covers the band at the right side.
    {s0, s1} = sliding(m)

    bumper_f =
      Hull.skin(h, d0 - 0.018, 0.56, :trim,
        offset: 0.018,
        sides: 24,
        step: 0.04,
        clip: fn d -> [{:z_max, 0.67 + 0.09 * min(1.0, (d - d0) / 0.25)}] end
      )

    bumper_r =
      Hull.skin(h, l - 0.34, d1 + 0.018, :trim,
        offset: 0.018,
        sides: 32,
        step: 0.04,
        clip: fn _ -> [{:z_max, 0.7}] end
      )

    bands =
      for {z0, z1} <- [{0.5, 0.78}, {0.0, 0.41}], s <- [1, -1] do
        clip = fn d ->
          planes = [{:x_min, Hull.half_width(h, d) - 0.06}, {:z_min, z0}, {:z_max, z1}]
          if s == 1 and d > s0 and d < s1, do: [{:z_min, 9.0}], else: mirror(planes, s)
        end

        Hull.skin(h, f + af - 0.02, f + wb - ar + 0.02, :trim, offset: 0.006, sides: 12, step: 0.1, clip: clip)
      end

    flares =
      for {d, r} <- [{f, af}, {f + wb, ar}], s <- [1, -1] do
        hw = Hull.half_width(h, d)

        n = if Detail.level() == :near, do: 14, else: 6

        line =
          for i <- 0..n do
            a = (-78 + 156 * i / n) * :math.pi() / 180
            {s * (hw - 0.01), l - d + (r + 0.015) * :math.sin(a), az + (r + 0.015) * :math.cos(a)}
          end

        Shape.sweep(line, 0.03, :trim, sides: if(n == 14, do: 6, else: 4))
      end

    cowl =
      Hull.skin(h, hd1, 0.805, :trim,
        offset: 0.004,
        sides: 16,
        step: 0.05,
        clip: fn d -> [{:z_min, Hull.z_high(h, d) - 0.03}] end
      )

    # From far, only the bumpers show; from mid, not the strip at the
    # windshield.
    shapes =
      case Detail.level() do
        :far -> [bumper_f, bumper_r]
        :mid -> [bumper_f, bumper_r | bands ++ flares]
        :near -> [bumper_f, bumper_r, cowl | bands ++ flares]
      end

    Part.new("trim_" <> m["make"], :trim, shapes, [origin()],
      sources: [
        "The black plastic of the Transit, from the photos of dealers: the front bumper from 0.29 to 0.76 m, the back bumper to 0.7 m and the lamps at the back from 0.7 to 1.355 m (the passenger van from the back: https://www.comvoy.com/work-van/starke-fl/new-2026-ford-transit-350-xl-passenger-van-23229223), the band from 0.5 to 0.78 m and the edge under 0.41 m between the wheels."
      ]
    )
  end

  # The windshield and the windows of the front doors.
  defp glass(h, m, windows) do
    ws_top = Enum.find(Hull.stations(h, 0.81, 2.4, 0.01), &(Hull.z_high(h, &1) >= 2.08))

    windshield =
      Hull.skin(h, 0.805, ws_top, :glass_dark,
        offset: %{near: 0.004, mid: 0.01, far: 0.025}[Detail.level()],
        sides: 16,
        step: 0.05,
        clip: fn d ->
          hw = Hull.half_width(h, d)
          [{:z_min, Hull.z_high(h, d) - 0.04}, {:x_max, hw - 0.11}, {:x_min, -(hw - 0.11)}]
        end
      )

    doors =
      sides(
        h,
        1.0,
        2.24,
        :glass_dark,
        fn d ->
          belt = 1.21 + 0.19 * (d - 1.0) / 1.24
          [{:x_min, Hull.half_width(h, d) - 0.04}, {:z_min, belt}, {:z_max, min(1.98, Hull.z_high(h, d) - 0.09)}]
        end,
        offset: 0.004,
        sides: 12,
        step: %{near: 0.05, mid: 0.05, far: 0.2}[Detail.level()]
      )

    Part.new("glass_transit", :glass, [windshield | doors] ++ side_windows(h, m, windows), [origin()],
      sources: if(windows == :cargo, do: [], else: m["make_data"]["windows"]["sources"])
    )
  end

  # The windows behind the cab, from the photos of the passenger van
  # (`windows` of the make). The glass is flush, with a black border: at
  # each side, one black band with a seam between two windows. At the
  # right side, the glass of the sliding door is on the door.
  defp side_windows(_h, _m, :cargo), do: []

  defp side_windows(h, m, windows) do
    w = m["make_data"]["windows"]["side"]
    {f, back} = {m["front"], m["front"] + m["quarter_end"]}
    {front, row2} = {f + w["from"], f + hd(w["seams"])}
    corners = %{bt: w["back_top"], bb: w["back_bottom"]}

    case windows do
      :crew ->
        [side_glass(h, w, front, row2, %{ft: w["front_top"]}, -1)]

      :passenger ->
        seams = if Detail.level() == :near, do: Enum.flat_map(w["seams"], &seam(h, w, f + &1)), else: []

        [
          side_glass(h, w, front, back, Map.put(corners, :ft, w["front_top"]), -1),
          side_glass(h, w, row2, back, corners, 1) | seams
        ]
    end
  end

  # A window in the side of the hull, from d0 to d1, with its round
  # corners: `ft`, `fb` (at the front, the top and the bottom), `bt`,
  # `bb` (at the back).
  defp side_glass(h, w, d0, d1, corners, s, offset \\ 0.006) do
    [z0, z1] = w["z"]

    Hull.skin(h, d0, d1, :glass_dark,
      offset: offset,
      sides: 12,
      step: %{near: 0.03, mid: 0.1, far: 0.3}[Detail.level()],
      clip: fn d ->
        {lo, hi} = edges(d - d0, d1 - d, z0, z1, corners)
        mirror([{:x_min, Hull.half_width(h, d) - 0.15}, {:z_min, lo}, {:z_max, hi}], s)
      end
    )
  end

  defp edges(f, b, z0, z1, c) do
    round = fn r, u -> if u < r, do: r - :math.sqrt(max(r * r - (r - u) * (r - u), 0.0)), else: 0.0 end
    get = &Map.get(c, &1, 0.0)
    {z0 + max(round.(get.(:fb), f), round.(get.(:bb), b)), z1 - max(round.(get.(:ft), f), round.(get.(:bt), b))}
  end

  # A seam between two windows of the band, at both sides.
  defp seam(h, w, d) do
    [z0, z1] = w["z"]

    sides(
      h,
      d - 0.008,
      d + 0.008,
      :dark,
      fn d -> [{:x_min, Hull.half_width(h, d) - 0.15}, {:z_min, z0}, {:z_max, z1}] end,
      offset: 0.009,
      sides: 8,
      step: 0.008
    )
  end

  # The glass of a rear door (`s` = 1 at the right, -1 at the left): from
  # the center to its outer edge, on the back face, with round outer
  # corners.
  defp rear_glass(h, m, s) do
    w = m["make_data"]["windows"]["rear_doors"]
    {xo, [z0, z1], rt, rb} = {w["x"], w["z"], w["outer_top"], w["outer_bottom"]}
    n = %{near: 4, mid: 2, far: 1}[Detail.level()]
    arc = fn i -> i * :math.pi() / (2 * n) end

    bottom = for i <- 0..n, a = arc.(i), do: {z0 + rb - rb * :math.cos(a), xo - rb + rb * :math.sin(a)}
    top = for i <- 0..n, a = arc.(i), do: {z1 - rt + rt * :math.sin(a), xo - rt + rt * :math.cos(a)}
    middle = for z <- [1.364, 1.491, 1.797, 1.924], z > z0 + rb and z < z1 - rt, do: {z, xo}

    for {z, x} <- bottom ++ middle ++ top do
      u = Hull.back(h, z)
      for {xx, y} <- [{0.004, u - 0.02}, {x, u - 0.02}, {x, u - 0.012}, {0.004, u - 0.012}], do: {s * xx, y, z}
    end
    |> Shape.rings(:glass_dark)
  end

  # The headlamps, the lamps at the back, the stop lamp at the top.
  defp lamps(h) do
    {_, d1} = Hull.span(h)
    l = h.length

    # A headlamp: from the top corner of the grille (x = 0.6) back along
    # the fender to its amber tip at d = 0.7, from 0.93 to 1.22 m at the
    # front, and to 1.2 m at the tip.
    lamp = fn d0, d1, material, extra ->
      sides(
        h,
        d0,
        d1,
        material,
        fn d ->
          t = max(d - 0.1, 0.0) / 0.6
          [{:x_min, 0.6}, {:z_min, 0.93 + 0.27 * t}, {:z_max, 1.22 + 0.02 * t}]
        end,
        offset: 0.008 + extra,
        sides: 16,
        step: 0.03
      )
    end

    reflector =
      sides(
        h,
        0.02,
        0.5,
        :chrome,
        fn d ->
          t = max(d - 0.1, 0.0) / 0.6
          [{:x_min, 0.66}, {:z_min, 0.97 + 0.27 * t}, {:z_max, 1.18 + 0.02 * t}]
        end,
        offset: 0.011,
        sides: 16,
        step: 0.03
      )

    # A lamp at the back: on the corner pillar, from x = 0.09 m inside
    # the side, around the corner and 0.06 m along the side.
    hw = Hull.half_width(h, d1 - 0.01)

    # Its parts, from the photos: red at the bottom, the clear lamp of
    # the reverse in the middle, red at the top.
    {parts, ts} =
      if Detail.level() == :far,
        do: {[{[0.7, 0.803, 1.16, 1.355], :light_back}], [0.0, 1.0]},
        else:
          {[
             {[0.7, 0.803, 0.87], :light_back},
             {[0.87, 0.95, 1.05, 1.13], :light_front},
             {[1.13, 1.16, 1.26, 1.355], :light_back}
           ], [0.0, 0.25, 0.5, 0.75, 1.0]}

    back_lamp = fn s, zs, material ->
      for z <- zs do
        u = Hull.back(h, z)

        side =
          for t <- ts,
              do: {Hull.half_width(h, l - u - 0.06 * t) + 0.012, u - 0.015 + 0.075 * t}

        {xi, yi} = List.last(side)
        for {x, y} <- [{hw - 0.09, u - 0.015} | side] ++ [{xi - 0.05, yi}, {hw - 0.09, u + 0.03}], do: {s * x, y, z}
      end
      |> Shape.rings(material)
    end

    back = for s <- [1, -1], {zs, material} <- parts, do: back_lamp.(s, zs, material)

    # The third stop lamp: a black housing on the back edge of the roof,
    # 0.74 m wide, with a red lens of 0.4 m at its top (the photos of the
    # back of the van).
    stop = stop_lamp(h)

    Part.new(
      "lamps_transit",
      :light,
      case Detail.level() do
        :far -> lamp.(0.02, 0.7, :black, 0.0) ++ back ++ stop
        :mid -> lamp.(0.02, 0.7, :black, 0.0) ++ lamp.(0.56, 0.7, :orange, 0.002) ++ back ++ stop
        :near -> lamp.(0.02, 0.7, :black, 0.0) ++ reflector ++ lamp.(0.56, 0.7, :orange, 0.002) ++ back ++ stop
      end,
      [origin()],
      detail: :always
    )
  end

  # The housing and the lens of the third stop lamp. Its profile (y, z)
  # goes from the back face, under the edge of the roof, up over the
  # back of the roof; the two ends are at x = -0.37 and 0.37.
  defp stop_lamp(h) do
    top = h.top
    low = top - 0.09
    {ub, ut} = {Hull.back(h, low), Hull.back(h, top)}
    face = fn t -> {ub - 0.015 + (ut - 0.03 - ub + 0.015) * t, low + (top + 0.02 - low) * t} end
    {y0, z0} = face.(0.0)
    {y1, z1} = face.(1.0)
    housing = [{y0, z0}, {y1, z1}, {ut + 0.25, top + 0.02}, {ut + 0.25, top - 0.01}, {y0 + 0.06, z0}]

    {ya, za} = face.(0.55)
    {yb, zb} = face.(0.95)
    lens = [{ya - 0.005, za}, {yb - 0.005, zb}, {yb + 0.01, zb}, {ya + 0.01, za}]

    for {profile, w, material} <- [{housing, 0.37, :black}, {lens, 0.2, :light_back}] do
      Shape.rings(for(x <- [-w, w], do: for({y, z} <- profile, do: {x, y, z})), material)
    end
  end

  # The grille (a hexagon) with the oval.
  defp grille(h) do
    l = h.length

    grille =
      Hull.skin(h, -0.012, 0.2, :black,
        offset: 0.012,
        sides: 16,
        step: 0.02,
        clip: fn _ ->
          k = 0.125 / 0.49
          [{:z_min, 0.665}, {:z_max, 1.15}, {:le, 1.0, -k, 0.475 - 0.66 * k}, {:le, -1.0, -k, 0.475 - 0.66 * k}]
        end
      )

    oval = fn y, z, w, hh, material, depth ->
      Shape.loft(
        [
          {{0.0, y, z}, {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, w, hh, 2.0},
          {{0.0, y + depth, z}, {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, w, hh, 2.0}
        ],
        material,
        sides: 20
      )
    end

    yf = l - 0.098

    Part.new(
      "grille_transit",
      :trim,
      [grille, oval.(yf, 0.98, 0.165, 0.065, :chrome, 0.03), oval.(yf + 0.006, 0.98, 0.15, 0.055, :blue, 0.03)],
      [origin()],
      detail: :always,
      sources: [
        "The grille: a hexagon 1.2 m wide at its top and 0.95 m at its bottom, from 0.66 to 1.15 m, with the oval in its upper middle (the photos of dealers)."
      ]
    )
  end

  # The mirrors: a tall black head (0.48 m) on two arms, 0.2 m out from
  # the side, with its glass at the back.
  defp mirrors(h, m) do
    l = h.length
    f = m["front"]
    hw_m = Hull.half_width(h, f + 0.17)
    ym = l - f - 0.17
    round_head = if Detail.level() == :far, do: [], else: [round: 0.12, smooth: 1]

    shapes =
      for s <- [1, -1] do
        x0 = s * (hw_m + 0.02)
        x1 = s * (hw_m + 0.204)
        {xa, xb} = {min(x0, x1), max(x0, x1)}

        [
          Shape.box({xa, ym - 0.045, 1.24}, {xb, ym + 0.045, 1.72}, :black, round_head),
          Shape.box({min(xa, xb - 0.17), ym - 0.051, 1.27}, {max(xb, xa + 0.17), ym - 0.045, 1.69}, :glass_dark),
          Shape.box({min(s * hw_m, x0), ym - 0.02, 1.33}, {max(s * hw_m, x0), ym + 0.02, 1.37}, :black),
          Shape.box({min(s * hw_m, x0), ym - 0.02, 1.6}, {max(s * hw_m, x0), ym + 0.02, 1.64}, :black)
        ]
      end

    Part.new("mirrors_transit", :mirror, List.flatten(shapes), [origin()], detail: :always)
  end

  # The small parts, only in the near level: the plates, the pockets of
  # the fog lamps, the vents of the hood, the handles, the seams, the rail
  # of the sliding door, the hinges of the rear doors.
  defp details(asm, h, m) do
    if Detail.level() == :near,
      do: Assembly.add(asm, "details", small_parts(h, m), at: "origin", port: "origin"),
      else: asm
  end

  defp small_parts(h, m) do
    l = h.length
    {d0, d1} = Hull.span(h)

    plates = [
      Shape.box({-0.155, l - d0 - 0.035, 0.45}, {0.155, l - d0 - 0.02, 0.6}, :white),
      Shape.box({-0.155, -0.03, 0.56}, {0.155, -0.022, 0.715}, :white)
    ]

    pockets =
      sides(h, 0.08, 0.32, :black, fn _ -> [{:x_min, 0.56}, {:z_min, 0.4}, {:z_max, 0.5}] end,
        offset: 0.024,
        sides: 8,
        step: 0.04
      )

    vents =
      for s <- [1, -1] do
        Hull.skin(h, 0.52, 0.575, :black,
          offset: 0.009,
          sides: 8,
          step: 0.02,
          clip: fn d -> mirror([{:z_min, Hull.z_high(h, d) - 0.012}, {:x_min, 0.12}, {:x_max, 0.44}], s) end
        )
      end

    handles =
      for s <- [1, -1] do
        hw = Hull.half_width(h, 2.0)

        Shape.box(
          {min(s * hw, s * (hw + 0.025)), l - 2.1, 1.15},
          {max(s * hw, s * (hw + 0.025)), l - 1.94, 1.185},
          :black
        )
      end

    seams =
      sides(h, 2.29, 2.302, :dark, fn _ -> [{:x_min, 0.9}, {:z_min, 0.42}, {:z_max, 2.02}] end,
        offset: 0.002,
        sides: 8,
        step: 0.01
      )

    {_, s1} = sliding(m)

    rail =
      Hull.skin(h, s1 + 0.03, l - 0.36, :dark,
        offset: 0.008,
        sides: 8,
        step: 0.1,
        clip: fn d -> [{:x_min, Hull.half_width(h, d) - 0.04}, {:z_min, 1.43}, {:z_max, 1.47}] end
      )

    hinges =
      for s <- [1, -1], z <- [0.6, 1.99] do
        x = s * (Hull.half_width(h, d1 - 0.02) - 0.05)
        u = Hull.back(h, z)
        Shape.box({x - 0.035, u - 0.016, z}, {x + 0.035, u + 0.03, z + 0.09}, :black)
      end

    Part.new("details_transit", :trim, [rail | plates ++ pockets ++ vents ++ handles ++ seams ++ hinges], [origin()],
      sources: [
        "The vents of the hood, the seam of the front door at 1.27 m behind the front axle, the rail of the sliding door at 1.45 m: from the photos of dealers."
      ]
    )
  end

  # The hood, with its hinge at its back. It turns up at the front.
  defp hood(h) do
    {hd0, hd1} = @hood
    hz = Hull.z_high(h, hd1)

    shell =
      Hull.skin(h, hd0, hd1, :paint,
        offset: 0.004,
        sides: 24,
        step: 0.03,
        clip: fn d -> [{:z_min, Hull.z_high(h, d) - 0.035}] end
      )

    Part.new("hood_transit", :lid, [shell], [port("hinge", {0.0, h.length - hd1, hz - 0.006}, {1, 0, 0}, {0, 0, 1})])
  end

  # The opening of the sliding door: 1300 mm, from 1.3 m behind the front
  # axle (`d` of its two ends).
  defp sliding(m), do: {m["front"] + 1.3, m["front"] + 2.75}

  defp add_sliding_door(asm, h, m, windows) do
    {s0, s1} = sliding(m)
    l = h.length

    panel =
      Hull.skin(h, s0, s1, :paint,
        offset: 0.005,
        sides: 16,
        step: 0.05,
        clip: fn d -> [{:x_min, Hull.half_width(h, d) - 0.05}, {:z_min, 0.42}, {:z_max, 2.36}] end
      )

    band =
      for {z0, z1} <- [{0.5, 0.78}, {0.0, 0.41}] do
        Hull.skin(h, s0, s1, :trim,
          offset: 0.011,
          sides: 12,
          step: 0.1,
          clip: fn d -> [{:x_min, Hull.half_width(h, d) - 0.06}, {:z_min, z0}, {:z_max, z1}] end
        )
      end

    hw = Hull.half_width(h, s0 + 0.15)
    handle = Shape.box({hw + 0.005, l - s0 - 0.25, 1.15}, {hw + 0.03, l - s0 - 0.09, 1.185}, :black)
    axis = Vec.norm({0.03, -1.0, 0.0})
    at = {hw, l - (s0 + s1) / 2, 1.4}

    glass =
      if windows == :cargo do
        []
      else
        w = m["make_data"]["windows"]

        [
          side_glass(
            h,
            w["side"],
            m["front"] + w["slider"]["from"],
            s1 - 0.01,
            %{ft: w["slider"]["front_top"]},
            1,
            0.009
          )
        ]
      end

    door =
      Part.new("sliding_door_transit", :door, [panel, handle | band] ++ glass, [port("slide", at, axis, {0, 0, 1})],
        sources: ["The opening of the sliding door: 1300 by 1601 mm (Ford, Body Builders Layout Book 2022)."]
      )

    Assembly.add(asm, "sliding_door", door,
      at: port("slide", at, axis, {0, 0, 1}),
      port: "slide",
      kind: :slides,
      role: :door,
      limits: [0, 1.25]
    )
  end

  # The two rear doors: each half of the back, on hinges at its outer
  # edge. They open to the sides.
  defp add_rear_doors(asm, h, m, windows) do
    {_, d1} = Hull.span(h)
    top = m["floor"] + m["rear_door"] + 0.05

    Enum.reduce([{"rear_door_right", 1}, {"rear_door_left", -1}], asm, fn {name, s}, asm ->
      hw = Hull.half_width(h, d1 - 0.01)
      xh = s * (hw - 0.095)

      leaf =
        Hull.skin(h, h.length - 0.2, d1 + 0.012, :paint,
          offset: 0.012,
          sides: 16,
          step: 0.02,
          clip: fn _ ->
            mirror([{:x_min, 0.003}, {:x_max, hw - 0.095}, {:z_min, 0.71}, {:z_max, top}], s)
          end
        )

      handle = if s == 1, do: [Shape.box({0.05, -0.03, 1.12}, {0.2, -0.01, 1.16}, :black)], else: []
      hinge = port("hinge", {xh, 0.0, 1.5}, {0, 0, s}, {0, 1, 0})

      glass = if windows == :cargo, do: [], else: [rear_glass(h, m, s)]

      Assembly.add(asm, name, Part.new("rear_door_transit", :door, [leaf | handle] ++ glass, [hinge]),
        at: hinge,
        port: "hinge",
        kind: :turns,
        role: :door,
        limits: [0, 180]
      )
    end)
  end

  # --- The engine bay -------------------------------------------------------------------

  # The parts in the bay are `inside`: they are only in the near level.
  defp engine_bay(asm, h, items) do
    l = h.length
    hidden = fn part -> %{part | inside: true} end

    asm =
      asm
      |> Assembly.add("engine", hidden.(engine(l)), at: "origin", port: "origin")
      |> Assembly.add("radiator", hidden.(radiator(l)), at: "origin", port: "origin")
      |> Assembly.add("radiator_fan", hidden.(radiator_fan(l)),
        at: port("fan", {0.0, l - 0.32, 0.8}, {0, 1, 0}, {0, 0, 1}),
        port: "axle",
        kind: :turns,
        role: :spin
      )
      |> Assembly.add("bay_parts", hidden.(bay_parts(l)), at: "origin", port: "origin")

    Enum.reduce(items, asm, fn
      :second_alternator, asm ->
        Assembly.add(asm, "second_alternator", inside(VanGear.second_alternator()),
          at: port("second_alternator", {-0.42, l - 0.48, 0.84}, {0, 0, 1}, {0, 1, 0}),
          port: "o"
        )

      :dc_charger, asm ->
        Assembly.add(asm, "dc_charger", inside(VanGear.redarc_bcdc1250d()),
          at: port("dc_charger", {0.598, l - 0.45, 0.95}, {-1, 0, 0}, {0, 0, -1}),
          port: "o"
        )
    end)
  end

  defp inside(%Assembly{nodes: nodes} = a), do: %{a | nodes: for({name, item, c} <- nodes, do: {name, inside(item), c})}
  defp inside(%Part{} = p), do: %{p | inside: true}

  # The pulleys of the belt at the front of the engine, in order around
  # the belt: {x, z, radius}.
  @pulleys [{0.0, 0.62, 0.085}, {0.3, 0.92, 0.032}, {0.05, 1.0, 0.06}, {-0.14, 0.96, 0.035}, {-0.28, 0.66, 0.06}]

  # The 3.5 L V6 along the van, its belt at its front (d = 0.405).
  defp engine(l) do
    y = fn d -> l - d end
    by = y.(0.405)

    block = [
      Shape.box({-0.18, y.(0.8), 0.5}, {0.18, y.(0.48), 0.55}, :dark),
      Shape.box({-0.2, y.(0.82), 0.55}, {0.2, y.(0.44), 0.9}, :dark),
      Shape.box({-0.32, y.(0.81), 0.86}, {-0.12, y.(0.45), 1.0}, :aluminum, round: 0.15, smooth: 1),
      Shape.box({0.12, y.(0.81), 0.86}, {0.32, y.(0.45), 1.0}, :aluminum, round: 0.15, smooth: 1),
      Shape.box({-0.26, y.(0.8), 1.0}, {0.26, y.(0.48), 1.08}, :black, round: 0.2, smooth: 1),
      Shape.box({-0.12, y.(0.78), 1.08}, {0.12, y.(0.52), 1.14}, :black, round: 0.2, smooth: 1),
      Shape.box({-0.22, y.(0.44), 0.55}, {0.22, y.(0.415), 1.0}, :aluminum)
    ]

    pulleys =
      for {x, z, r} <- @pulleys,
          do: Shape.cylinder(r, 0.025, :steel, sides: 16, frame: Frame.new({x, by - 0.0125, z}, {0, 1, 0}, {0, 0, 1}))

    accessories = [
      Shape.cylinder(0.07, 0.15, :aluminum, sides: 16, frame: Frame.new({0.3, by - 0.165, 0.92}, {0, 1, 0}, {0, 0, 1})),
      Shape.cylinder(0.06, 0.15, :aluminum,
        sides: 16,
        frame: Frame.new({-0.28, by - 0.165, 0.66}, {0, 1, 0}, {0, 0, 1})
      )
    ]

    belt = Shape.sweep(belt_line(@pulleys, by), 0.005, :rubber, sides: 4)

    Part.new("engine_ford_3_5_v6", :engine, block ++ pulleys ++ accessories ++ [belt], [origin()],
      sources: ["The 3.5 L V6 of the Transit, along the van: its size and its belt by eye, from photos of the bay."]
    )
  end

  # The line of a belt around pulleys (in order, counterclockwise in x
  # and z): on each pulley an arc from the side of the last pulley to the
  # side of the next.
  defp belt_line(pulleys, y) do
    n = length(pulleys)
    normal = fn {ax, az, _}, {bx, bz, _} -> :math.atan2(-(bx - ax), bz - az) end

    points =
      for i <- 0..(n - 1),
          {x, z, r} = Enum.at(pulleys, i),
          a0 = normal.(Enum.at(pulleys, i - 1), Enum.at(pulleys, i)),
          a1 = normal.(Enum.at(pulleys, i), Enum.at(pulleys, rem(i + 1, n))),
          a1 = if(a1 < a0, do: a1 + 2 * :math.pi(), else: a1),
          k <- 0..4,
          a = a0 + (a1 - a0) * k / 4,
          do: {x + r * :math.cos(a), y, z + r * :math.sin(a)}

    points ++ [hd(points)]
  end

  defp radiator(l) do
    y = fn d -> l - d end
    core = Shape.box({-0.55, y.(0.26), 0.52}, {0.55, y.(0.2), 1.04}, :dark)

    tanks =
      for x <- [-1, 1], do: Shape.box({x * 0.55 - 0.03, y.(0.265), 0.52}, {x * 0.55 + 0.03, y.(0.195), 1.06}, :black)

    shroud =
      for {a, b} <- [
            {{-0.26, 0.56}, {0.26, 0.59}},
            {{-0.26, 1.01}, {0.26, 1.04}},
            {{-0.26, 0.59}, {-0.23, 1.01}},
            {{0.23, 0.59}, {0.26, 1.01}}
          ] do
        {{x0, z0}, {x1, z1}} = {a, b}
        Shape.box({x0, y.(0.30), z0}, {x1, y.(0.26), z1}, :black)
      end

    Part.new("radiator_transit", :radiator, [core | tanks ++ shroud], [origin()],
      sources: ["A radiator of about 1.1 by 0.5 m with its fan shroud: by eye."]
    )
  end

  defp radiator_fan(l) do
    y = l - 0.32

    blades =
      for k <- 0..6 do
        a = 2 * :math.pi() * k / 7

        Shape.box({0.04, -0.03, -0.004}, {0.2, 0.03, 0.004}, :black,
          frame:
            Frame.compose(
              Frame.new({0.0, y, 0.8}, {0, 1, 0}, {-:math.sin(a), 0.0, :math.cos(a)}),
              Frame.turn({1, 0, 0}, 25)
            )
        )
      end

    hub = Shape.cylinder(0.045, 0.04, :black, sides: 12, frame: Frame.new({0.0, y - 0.02, 0.8}, {0, 1, 0}, {0, 0, 1}))
    Part.new("radiator_fan_transit", :fan, [hub | blades], [port("axle", {0.0, y, 0.8}, {0, 1, 0}, {0, 0, 1})])
  end

  # The air box and its duct, the coolant reservoir, the fuse box, the
  # brake reservoir: in the places of the photos of the bay.
  defp bay_parts(l) do
    y = fn d -> l - d end

    shapes = [
      Shape.box({-0.58, y.(0.62), 0.9}, {-0.36, y.(0.36), 1.1}, :black, round: 0.2, smooth: 1),
      Shape.sweep([{-0.36, y.(0.5), 1.02}, {-0.22, y.(0.55), 1.1}, {-0.1, y.(0.6), 1.12}], 0.045, :black, sides: 8),
      Shape.box({0.36, y.(0.64), 0.95}, {0.52, y.(0.5), 1.1}, :plastic, round: 0.2, smooth: 1),
      Shape.box({0.3, y.(0.4), 0.92}, {0.5, y.(0.25), 1.06}, :black),
      Shape.box({0.42, y.(0.66), 1.04}, {0.52, y.(0.62), 1.12}, :plastic)
    ]

    Part.new("engine_bay_transit", :bay, shapes, [origin()],
      sources: [
        "The air box, the coolant reservoir, the fuse box and the brake reservoir: from the photos of the bay of a 2022 Transit."
      ]
    )
  end

  # --- The roof -------------------------------------------------------------------------

  defp roof(asm, h, items) do
    Enum.reduce(Enum.with_index(items), asm, fn
      {{:fan, d}, i}, asm ->
        Assembly.add(asm, "roof_fan_#{i}", VanGear.maxxfan(),
          at: port("roof_fan_#{i}", {0.0, h.length - d, h.top}, {0, 0, 1}, {0, 1, 0}),
          port: "o"
        )

      {{:solar, d}, i}, asm ->
        Assembly.add(asm, "solar_#{i}", solar_on_feet(),
          at: port("solar_#{i}", {0.0, h.length - d, h.top}, {0, 0, 1}, {0, 1, 0}),
          port: "o"
        )
    end)
  end

  # The solar panel of DIY on four feet of aluminum, 4 cm over the roof.
  defp solar_on_feet do
    feet =
      for x <- [-0.5, 0.5],
          y <- [-0.7, 0.7],
          do: Shape.box({x - 0.02, y - 0.04, 0.0}, {x + 0.02, y + 0.04, 0.04}, :aluminum)

    Assembly.new("solar_on_feet", Part.new("solar_feet", :bracket, feet, [port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})]),
      root: "feet"
    )
    |> Assembly.add("panel", VanGear.solar_panel(), at: port("top", {0.0, 0.0, 0.04}, {0, 0, 1}, {0, 1, 0}), port: "o")
  end
end
