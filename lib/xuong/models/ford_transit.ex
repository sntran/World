defmodule Xuong.Models.FordTransit do
  @moduledoc """
  A Ford Transit 148 in high roof van, made a camper van: the "camper" of
  Phượt, and the base van of DIY. It has a sliding door at the right
  side, two rear doors, a roof fan with a lid, and solar panels.

  The hood opens on the engine bay: the 3.5 L V6 with its belt and
  pulleys, the radiator and its fan, the air box, the reservoirs, the
  fuse box, and the two items of DIY for the engine bay: a second
  alternator and a DC-DC charger (the REDARC BCDC1250D). The parts in
  the bay are `inside`: they are only in the near level.

  The parts are made with the back of the van at y = 0; the `place` of
  the assembly moves the van to its center.
  """
  alias Xuong.{Assembly, Frame, Part, Shape}
  alias Xuong.Models.{Body, VanGear, Vehicle}
  alias Xuong.Parts.{Fasteners, Wheels}

  @length 5.98
  @front_y 5.98 - 1.016
  @rear_y 5.98 - 1.016 - 3.749
  @axle_z 0.356
  @hw 1.028
  # The top line of the nose: {y, z}. The hood is on it.
  @nose [{5.10, 1.74}, {5.55, 1.30}, {5.86, 1.06}, {@length, 0.92}]
  @hood_y 5.13

  @sources [
    "Ford Transit 148 in high roof: length 235.5 in, width 81 in with no mirrors, height 109 in, wheelbase 147.6 in (Ford and Autopadre, 2025).",
    "The front axle 40 in from the front: a guess, as in DIY. Tires 235/65R16C; tracks about 1.74 m.",
    "Roof fan: 14 by 14 in, as the common fans of camper vans. Solar panels: 1.72 by 1.13 m, as 400 W panels.",
    "The shape of the body: by eye, from photos of the van."
  ]

  @doc "The camper van."
  def model do
    wheel = Wheels.car_wheel("235/65R16", spokes: 6, pcd: 0.18, lugs: 5, rim_material: :steel)
    hx = 0.87

    Assembly.new("ford_transit_148_camper", body(),
      root: "body",
      kind: :vehicle,
      sources: @sources,
      place: Frame.move({0.0, -@length / 2, 0.0})
    )
    |> Assembly.add("lights", lights(), at: "origin", port: "origin")
    |> Assembly.add("sliding_door", sliding_door(),
      at: "slide",
      port: "slide",
      kind: :slides,
      role: :door,
      limits: [0, 1.1]
    )
    |> Assembly.add("rear_door_right", rear_door(1),
      at: "hinge_right",
      port: "hinge",
      kind: :turns,
      role: :door,
      limits: [0, 180]
    )
    |> Assembly.add("rear_door_left", rear_door(-1),
      at: "hinge_left",
      port: "hinge",
      kind: :turns,
      role: :door,
      limits: [0, 180]
    )
    |> Assembly.add("roof_fan", roof_fan(), at: "fan", port: "base")
    |> Assembly.add("fan_lid", fan_lid(),
      to: "roof_fan",
      at: "lid",
      port: "hinge",
      kind: :turns,
      role: :lid,
      limits: [0, 60]
    )
    |> add_solar()
    |> Assembly.add("hood", hood(),
      at: "hood",
      port: "hinge",
      kind: :turns,
      role: :lid,
      limits: [0, 60]
    )
    |> engine_bay()
    |> Vehicle.corner("front_right", wheel, {hx, @front_y, @axle_z}, steer: true, limits: [-38, 38], disc: 0.30)
    |> Vehicle.corner("front_left", wheel, {-hx, @front_y, @axle_z}, steer: true, limits: [-38, 38], disc: 0.30)
    |> Vehicle.corner("rear_right", wheel, {hx, @rear_y, @axle_z}, disc: 0.30)
    |> Vehicle.corner("rear_left", wheel, {-hx, @rear_y, @axle_z}, disc: 0.30)
  end

  defp port(name, at, axis, up), do: Part.port(name, at, axis, up)
  defp origin, do: port("origin", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  defp body do
    arches = [{@rear_y, @axle_z, 0.42}, {@front_y, @axle_z, 0.42}]

    shell =
      Body.loft(
        [
          {0.0, 0.50, 2.70, 0.98, 5.0},
          {0.06, 0.42, 2.77, 1.02, 8.0},
          {4.45, 0.42, 2.77, @hw, 8.0},
          {4.70, 0.42, 2.42, 1.02, 7.0},
          {5.10, 0.44, 1.74, 1.0, 6.0}
        ],
        arches,
        :white,
        sides: 24
      )

    # The nose: a fender at each side, the front under the grille, and the
    # tray under the engine. The hood closes the top.
    fenders =
      for x <- [-1, 1] do
        Body.loft(
          [
            {5.10, 0.44, 1.71, 0.17, 6.0},
            {5.55, 0.46, 1.275, 0.15, 6.0},
            {5.86, 0.50, 1.035, 0.11, 5.0},
            {5.96, 0.56, 0.94, 0.08, 4.0}
          ],
          arches,
          :white,
          x0: x * 0.82,
          sides: 16
        )
      end

    front =
      Shape.loft(Shape.rows_y([{5.84, 0.46, 1.02, 0.84, 5.0}, {@length, 0.58, 0.90, 0.80, 3.0}]), :white,
        smooth: 1,
        sides: 20
      )

    tray = Shape.box({-0.68, 5.10, 0.40}, {0.68, 5.86, 0.44}, :black)

    windshield =
      Shape.loft(
        Shape.rows_z([{1.76, 5.08, 5.12, 0.86, 7}, {2.10, 4.90, 4.95, 0.86, 7}, {2.40, 4.72, 4.77, 0.82, 7}]),
        :glass_dark,
        sides: 16
      )

    cab_windows =
      for x <- [-1, 1],
          do: Shape.box({x * (@hw + 0.004) - 0.006, 4.25, 1.40}, {x * (@hw + 0.004) + 0.006, 4.85, 1.85}, :glass_dark)

    side_windows =
      for x <- [-1, 1],
          do: Shape.box({x * (@hw + 0.004) - 0.006, 1.80, 1.62}, {x * (@hw + 0.004) + 0.006, 2.80, 2.10}, :glass_dark)

    bumper_f = Shape.box({-1.0, 5.80, 0.42}, {1.0, @length + 0.02, 0.66}, :trim, round: 0.2, smooth: 1)
    bumper_r = Shape.box({-1.0, -0.06, 0.42}, {1.0, 0.10, 0.58}, :trim)
    grille = Shape.box({-0.62, @length - 0.03, 0.68}, {0.62, @length + 0.012, 0.95}, :black, round: 0.2, smooth: 1)
    step = Shape.box({0.85, 3.10, 0.36}, {1.05, 4.20, 0.42}, :black)

    mirrors =
      for x <- [-1, 1],
          do: Shape.box({x * 1.13 - 0.07, 4.78, 1.55}, {x * 1.13 + 0.07, 4.90, 1.85}, :black)

    arms = for x <- [-1, 1], do: Shape.sweep([{x * 1.0, 4.85, 1.62}, {x * 1.07, 4.85, 1.62}], 0.014, :black, sides: 6)
    plate = Shape.box({-0.26, -0.07, 0.62}, {0.26, -0.06, 0.73}, :white)

    Part.new(
      "body_transit_148_high",
      :body,
      [shell, front, tray, windshield, bumper_f, bumper_r, grille, step, plate] ++
        fenders ++ cab_windows ++ side_windows ++ mirrors ++ arms,
      [
        origin(),
        port("hood", {0.0, @hood_y, top(@hood_y) - 0.01}, {1, 0, 0}, {0, 0, 1}),
        port("slide", {0.0, 0.0, 0.0}, {0, -1, 0}, {0, 0, 1}),
        port("hinge_right", {0.995, -0.01, 1.55}, {0, 0, 1}, {0, 1, 0}),
        port("hinge_left", {-0.995, -0.01, 1.55}, {0, 0, -1}, {0, 1, 0}),
        port("fan", {0.0, 4.1, 2.77}, {0, 0, 1}, {0, 1, 0}),
        port("solar_a", {0.0, 1.05, 2.77}, {0, 0, 1}, {0, 1, 0}),
        port("solar_b", {0.0, 2.88, 2.77}, {0, 0, 1}, {0, 1, 0})
        | for(
            {name, x, y} <- [
              {"front_right", 1, @front_y},
              {"front_left", -1, @front_y},
              {"rear_right", 1, @rear_y},
              {"rear_left", -1, @rear_y}
            ],
            do: Vehicle.corner_port("corner_#{name}", {x * 0.87, y, @axle_z})
          )
      ],
      sources: ["By eye, from photos of the van."]
    )
  end

  # The sliding door on the right side: it moves back along -y.
  defp sliding_door do
    panel = Shape.box({@hw + 0.002, 3.12, 0.46}, {@hw + 0.022, 4.22, 2.42}, :white, round: 0.03, smooth: 1)
    glass = Shape.box({@hw + 0.022, 3.30, 1.62}, {@hw + 0.026, 4.05, 2.10}, :glass_dark)
    handle = Shape.box({@hw + 0.022, 4.02, 1.18}, {@hw + 0.04, 4.15, 1.22}, :black)

    Part.new("sliding_door_transit", :door, [panel, glass, handle], [
      port("slide", {0.0, 0.0, 0.0}, {0, -1, 0}, {0, 0, 1})
    ])
  end

  # A rear door: half the width of the back, on a hinge at the side.
  defp rear_door(side) do
    x0 = side * 0.995

    panel =
      Shape.box({min(x0, 0.0) + 0.004 * side, -0.05, 0.50}, {max(x0, 0.0) - 0.004 * side, -0.02, 2.62}, :white,
        round: 0.03,
        smooth: 1
      )

    glass = Shape.box({side * 0.15, -0.055, 1.62}, {side * 0.85, -0.05, 2.25}, :glass_dark)
    Part.new("rear_door_transit", :door, [panel, glass], [port("hinge", {x0, -0.01, 1.55}, {0, 0, side}, {0, 1, 0})])
  end

  defp roof_fan do
    base = Shape.box({-0.2, -0.2, 0.0}, {0.2, 0.2, 0.06}, :white, round: 0.2, smooth: 1)
    port_lid = port("lid", {0.0, -0.2, 0.06}, {-1, 0, 0}, {0, 0, 1})

    Part.new("roof_fan_14in", :fan, base, [port("base", {0.0, 0.0, 0.0}, {0, 0, 1}, {0, 1, 0}), port_lid],
      sources: ["A roof fan for a hole of 14 by 14 in."]
    )
  end

  # The lid of the fan: a hinge at its back, it opens up at its front.
  defp fan_lid do
    lid = Shape.box({-0.21, 0.0, 0.0}, {0.21, 0.42, 0.04}, :plastic, round: 0.3, smooth: 1)
    Part.new("roof_fan_lid", :lid, lid, [port("hinge", {0.0, 0.0, 0.0}, {-1, 0, 0}, {0, 0, 1})])
  end

  defp add_solar(asm) do
    Enum.reduce(["solar_a", "solar_b"], asm, fn name, a ->
      Assembly.add(a, name, solar_panel(), at: name, port: "base")
    end)
  end

  # A solar panel of 1.72 by 1.13 m on four feet, fixed with M8 bolts.
  defp solar_panel do
    frame = Shape.box({-0.565, -0.86, 0.05}, {0.565, 0.86, 0.085}, :aluminum)
    cells = Shape.box({-0.55, -0.845, 0.085}, {0.55, 0.845, 0.088}, :glass_dark)

    feet =
      for x <- [-0.5, 0.5],
          y <- [-0.75, 0.75],
          do: Shape.box({x - 0.02, y - 0.04, 0.0}, {x + 0.02, y + 0.04, 0.05}, :aluminum)

    panel =
      Part.new(
        "solar_panel_400w",
        :solar_panel,
        [frame, cells | feet],
        [
          port("base", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})
          | for(
              {x, y} <- [{-0.5, -0.75}, {0.5, -0.75}, {-0.5, 0.75}, {0.5, 0.75}],
              do: port("foot_#{x}_#{y}", {x, y, 0.05}, {0, 0, -1}, {0, 1, 0})
            )
        ],
        sources: ["A 400 W panel: 1722 x 1134 x 35 mm, as common panels of the trade."]
      )

    Enum.reduce(
      [{-0.5, -0.75}, {0.5, -0.75}, {-0.5, 0.75}, {0.5, 0.75}],
      Assembly.new("solar_panel_on_feet", panel, root: "panel"),
      fn {x, y}, a ->
        Assembly.add(a, "bolt_#{x}_#{y}", Fasteners.bolt("M8", 0.03, inside: true), at: "foot_#{x}_#{y}", port: "head")
      end
    )
  end

  # The top of the nose at y, in a straight line between the keys.
  defp top(y) do
    [{ya, za}, {yb, zb}] =
      @nose |> Enum.chunk_every(2, 1, :discard) |> Enum.find(fn [{ya, _}, {yb, _}] -> y >= ya and y <= yb end)

    za + (zb - za) * (y - ya) / (yb - ya)
  end

  # The hood: a thin shell on the top line of the nose, with its hinge at
  # the back. It turns up at the front.
  defp hood do
    rows =
      for {y, hw} <- [{@hood_y, 0.97}, {5.3, 0.965}, {5.55, 0.95}, {5.7, 0.93}, {5.86, 0.91}, {5.93, 0.86}],
          do: {y, top(y) - 0.025, top(y) + 0.006, hw, 8.0}

    Part.new(
      "hood_transit",
      :lid,
      [Shape.loft(Shape.rows_y(rows), :white, smooth: 1, sides: 20)],
      [port("hinge", {0.0, @hood_y, top(@hood_y) - 0.01}, {1, 0, 0}, {0, 0, 1})]
    )
  end

  # --- The engine bay -------------------------------------------------------------------

  # The bay is from the cowl (y = 5.10) to the front (y = 5.84), from x =
  # -0.67 to 0.67 (the fenders), over the tray (z = 0.44). The 3.5 L V6
  # is along y, its belt at the front.
  defp engine_bay(asm) do
    hidden = fn part -> %{part | inside: true} end

    asm
    |> Assembly.add("engine", hidden.(engine()), at: "origin", port: "origin")
    |> Assembly.add("radiator", hidden.(radiator()), at: "origin", port: "origin")
    |> Assembly.add("radiator_fan", hidden.(radiator_fan()),
      at: port("fan", {0.0, 5.66, 0.80}, {0, 1, 0}, {0, 0, 1}),
      port: "axle",
      kind: :turns,
      role: :spin
    )
    |> Assembly.add("bay_parts", hidden.(bay_parts()), at: "origin", port: "origin")
    |> Assembly.add("second_alternator", inside(VanGear.second_alternator()),
      at: port("second_alternator", {-0.42, 5.50, 0.84}, {0, 0, 1}, {0, 1, 0}),
      port: "o"
    )
    |> Assembly.add("dc_charger", inside(VanGear.redarc_bcdc1250d()),
      at: port("dc_charger", {0.668, 5.535, 0.95}, {-1, 0, 0}, {0, 0, -1}),
      port: "o"
    )
  end

  defp inside(%Assembly{nodes: nodes} = a),
    do: %{a | nodes: for({name, item, c} <- nodes, do: {name, inside(item), c})}

  defp inside(%Part{} = p), do: %{p | inside: true}

  # The pulleys of the belt at the front of the engine, in order around
  # the belt: {x, z, radius}.
  @pulleys [{0.0, 0.62, 0.085}, {0.30, 0.92, 0.032}, {0.05, 1.0, 0.06}, {-0.14, 0.96, 0.035}, {-0.28, 0.66, 0.06}]
  @belt_y 5.575

  defp engine do
    block = [
      Shape.box({-0.18, 5.18, 0.45}, {0.18, 5.50, 0.52}, :dark),
      Shape.box({-0.20, 5.16, 0.52}, {0.20, 5.54, 0.90}, :dark),
      Shape.box({-0.32, 5.17, 0.86}, {-0.12, 5.53, 1.0}, :aluminum, round: 0.15, smooth: 1),
      Shape.box({0.12, 5.17, 0.86}, {0.32, 5.53, 1.0}, :aluminum, round: 0.15, smooth: 1),
      Shape.box({-0.26, 5.18, 1.0}, {0.26, 5.50, 1.08}, :black, round: 0.2, smooth: 1),
      Shape.box({-0.12, 5.20, 1.08}, {0.12, 5.46, 1.14}, :black, round: 0.2, smooth: 1),
      Shape.box({-0.22, 5.54, 0.55}, {0.22, 5.565, 1.0}, :aluminum)
    ]

    pulleys =
      for {x, z, r} <- @pulleys,
          do:
            Shape.cylinder(r, 0.025, :steel,
              sides: 16,
              frame: Frame.new({x, @belt_y - 0.0125, z}, {0, 1, 0}, {0, 0, 1})
            )

    # The stock alternator (behind its pulley) and the compressor of the AC.
    accessories = [
      Shape.cylinder(0.07, 0.15, :aluminum, sides: 16, frame: Frame.new({0.30, 5.41, 0.92}, {0, 1, 0}, {0, 0, 1})),
      Shape.cylinder(0.06, 0.15, :aluminum, sides: 16, frame: Frame.new({-0.28, 5.41, 0.66}, {0, 1, 0}, {0, 0, 1}))
    ]

    belt = Shape.sweep(belt_line(@pulleys, @belt_y), 0.005, :rubber, sides: 4)

    Part.new("engine_ford_3_5_v6", :engine, block ++ pulleys ++ accessories ++ [belt], [origin()],
      sources: ["The 3.5 L V6 of the Transit, along the van: its size and its belt by eye, from photos."]
    )
  end

  # The line of a belt around pulleys (in order, counterclockwise in x
  # and z): on each pulley an arc from the side of the last pulley to the
  # side of the next.
  defp belt_line(pulleys, y) do
    n = length(pulleys)

    normal = fn {ax, az, _}, {bx, bz, _} ->
      {dx, dz} = {bx - ax, bz - az}
      :math.atan2(-dx, dz)
    end

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

  defp radiator do
    core = Shape.box({-0.55, 5.72, 0.52}, {0.55, 5.78, 1.04}, :dark)
    tanks = for x <- [-1, 1], do: Shape.box({x * 0.55 - 0.03, 5.715, 0.52}, {x * 0.55 + 0.03, 5.785, 1.06}, :black)

    shroud = [
      Shape.box({-0.26, 5.68, 0.56}, {0.26, 5.72, 0.59}, :black),
      Shape.box({-0.26, 5.68, 1.01}, {0.26, 5.72, 1.04}, :black),
      Shape.box({-0.26, 5.68, 0.59}, {-0.23, 5.72, 1.01}, :black),
      Shape.box({0.23, 5.68, 0.59}, {0.26, 5.72, 1.01}, :black)
    ]

    Part.new("radiator_transit", :radiator, [core | tanks ++ shroud], [origin()],
      sources: ["A radiator of about 1.1 by 0.5 m with its fan shroud: by eye."]
    )
  end

  defp radiator_fan do
    blades =
      for k <- 0..6 do
        a = 2 * :math.pi() * k / 7

        Shape.box({0.04, -0.03, -0.004}, {0.2, 0.03, 0.004}, :black,
          frame:
            Frame.compose(
              Frame.new({0.0, 5.66, 0.80}, {0, 1, 0}, {-:math.sin(a), 0.0, :math.cos(a)}),
              Frame.turn({1, 0, 0}, 25)
            )
        )
      end

    hub = Shape.cylinder(0.045, 0.04, :black, sides: 12, frame: Frame.new({0.0, 5.64, 0.80}, {0, 1, 0}, {0, 0, 1}))

    Part.new("radiator_fan_transit", :fan, [hub | blades], [port("axle", {0.0, 5.66, 0.80}, {0, 1, 0}, {0, 0, 1})])
  end

  # The air box, the reservoirs and the fuse box.
  defp bay_parts do
    shapes = [
      Shape.box({0.40, 5.20, 0.90}, {0.62, 5.44, 1.10}, :black, round: 0.2, smooth: 1),
      Shape.sweep([{0.40, 5.30, 1.02}, {0.25, 5.36, 1.10}, {0.10, 5.38, 1.12}], 0.04, :black, sides: 8),
      Shape.box({0.42, 5.62, 0.95}, {0.58, 5.70, 1.08}, :white, round: 0.2, smooth: 1),
      Shape.box({-0.62, 5.16, 0.92}, {-0.44, 5.34, 1.08}, :black),
      Shape.box({-0.40, 5.11, 1.05}, {-0.30, 5.155, 1.14}, :white)
    ]

    Part.new("engine_bay_transit", :bay, shapes, [origin()],
      sources: ["The air box, the coolant reservoir, the fuse box and the brake reservoir: by eye."]
    )
  end

  defp lights do
    head = fn x ->
      Shape.loft(
        Shape.rows_y([{5.78, 1.0, 1.16, 0.14, 3}, {5.86, 0.99, 1.14, 0.12, 3}, {5.93, 0.98, 1.1, 0.08, 3}], x),
        :light_front,
        smooth: 1,
        sides: 12
      )
    end

    tail = fn x -> Shape.box({x - 0.04, -0.02, 0.85}, {x + 0.04, 0.02, 1.45}, :light_back, round: 0.3, smooth: 1) end

    Part.new("lights_transit", :light, [head.(0.72), head.(-0.72), tail.(0.96), tail.(-0.96)], [origin()],
      detail: :always
    )
  end
end
