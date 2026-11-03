defmodule World.Vehicles.Van.Chassis do
  @moduledoc """
  The fifth station of the line of a van (`World.Vehicles.Van`): the
  marriage of the body and the drive. The engine bay under the hood (the
  3.5 L V6 with its belt, the radiator and its fan, the air box, the
  reservoirs and the fuse box), the items of DIY in the bay (a second
  alternator, a DC-DC charger), the drive under the body (the
  transmission, the propeller shaft, the rear axle on its leaf springs,
  the front suspension, the fuel tank, the battery, the exhaust and the
  spare wheel), and the four wheels, the front two on their knuckles
  that steer.

  The engine, the transmission, the axle and the other bought parts have
  the mass of their data sheets (`World.Mass`), with the fluids of a van
  ready to drive: the curb weight of Ford is with a full tank of fuel.
  The parts under the body are boxes and tubes of their sizes (most
  sizes are estimates).
  """
  alias World.{Assembly, Frame, Part, Shape}
  alias World.Gear.Camper
  alias World.Vehicles.{Corners, Wheels}
  alias World.Vehicles.Van.Kit

  @station "chassis"

  @doc "The van with its engine bay (and the `items` of DIY in it) and its wheels."
  def marry(asm, van, items) do
    %{m: m, l: l, f: f} = van
    wb = m["wheelbase"] / 1
    [tf, tr] = m["track"]

    wheel =
      Kit.station(
        Wheels.car_wheel(m["tire"], face: :disc, holes: 10, pcd: 0.18, lugs: 5, rim_material: :steel, sides: 40),
        @station
      )

    rz = Wheels.tire_radius(m["tire"])

    asm
    |> engine_bay(van, items)
    |> drive(van)
    |> Corners.corner("front_right", wheel, {tf / 2, l - f, rz},
      steer: true,
      limits: [-38, 38],
      disc: 0.30,
      station: @station
    )
    |> Corners.corner("front_left", wheel, {-tf / 2, l - f, rz},
      steer: true,
      limits: [-38, 38],
      disc: 0.30,
      station: @station
    )
    |> Corners.corner("rear_right", wheel, {tr / 2, l - f - wb, rz}, disc: 0.30, station: @station)
    |> Corners.corner("rear_left", wheel, {-tr / 2, l - f - wb, rz}, disc: 0.30, station: @station)
  end

  # The parts in the bay are `inside`: they are only in the near level.
  defp engine_bay(asm, %{h: h}, items) do
    l = h.length
    hidden = fn part -> %{part | inside: true} end

    asm =
      asm
      |> Assembly.add("engine", hidden.(engine(l)), at: "origin", port: "origin")
      |> Assembly.add("radiator", hidden.(radiator(l)), at: "origin", port: "origin")
      |> Assembly.add("radiator_fan", hidden.(radiator_fan(l)),
        at: Kit.port("fan", {0.0, l - 0.32, 0.8}, {0, 1, 0}, {0, 0, 1}),
        port: "axle",
        kind: :hinge,
        role: :spin
      )
      |> Assembly.add("bay_parts", hidden.(bay_parts(l)), at: "origin", port: "origin")

    Enum.reduce(items, asm, fn
      # Low at the left of the front of the engine, beside the compressor
      # of the air conditioner and under the air box.
      :second_alternator, asm ->
        Assembly.add(asm, "second_alternator", inside(Kit.station(Camper.second_alternator(), "upfit")),
          at: Kit.port("second_alternator", {-0.42, l - 0.48, 0.62}, {0, 0, 1}, {0, 1, 0}),
          port: "o"
        )

      :dc_charger, asm ->
        Assembly.add(asm, "dc_charger", inside(Kit.station(Camper.redarc_bcdc1250d(), "upfit")),
          at: Kit.port("dc_charger", {0.598, l - 0.45, 0.95}, {-1, 0, 0}, {0, 0, -1}),
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

    Kit.part(@station, "engine_ford_3_5_v6", :engine, block ++ pulleys ++ accessories ++ [belt], [Kit.origin()],
      params: %{"mass" => 194.0},
      sources: [
        "The 3.5 L V6 of the Transit, along the van: its size and its belt by eye, from photos of the bay.",
        "The mass: 189 kg dry, with no accessory drive (Ford Performance, the 3.5 L EcoBoost crate engine; the 3.5 L PFDi of the van is near it: an estimate), and 5 kg of oil (5.7 L)."
      ]
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

    Kit.part(@station, "radiator_transit", :radiator, [core | tanks ++ shroud], [Kit.origin()],
      params: %{"mass" => 10.0},
      sources: ["A radiator of about 1.1 by 0.5 m with its fan shroud: by eye; 10 kg with its coolant (an estimate)."]
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

    Kit.part(
      @station,
      "radiator_fan_transit",
      :fan,
      [hub | blades],
      [Kit.port("axle", {0.0, y, 0.8}, {0, 1, 0}, {0, 0, 1})],
      matter: %{black: {:plastic, 0.0025}}
    )
  end

  # --- The drive under the body ------------------------------------------------------------

  # The parts of the drive, in the axes of the van (`d` back from the
  # front, as `l - d` on y), each a box or a tube of its size: the
  # transmission behind the engine, the propeller shaft to the rear axle,
  # the axle on two leaf springs, the front crossmember with the
  # suspension and the steering, the fuel tank, the battery under the
  # floor of the driver, the exhaust at the right side, the spare wheel
  # under the back. They are only in the near level, as the bay.
  defp drive(asm, %{l: l, f: f, m: m}) do
    wb = m["wheelbase"] / 1
    rz = Wheels.tire_radius(m["tire"])
    [_, tr] = m["track"]
    {ya, yr} = {l - f, l - f - wb}
    hidden = fn part -> %{part | inside: true} end
    box = fn a, b, role -> Shape.box(a, b, role) end

    transmission =
      bought(
        "transmission_10r80",
        :transmission,
        [box.({-0.2, ya - 0.66, 0.42}, {0.2, ya + 0.19, 0.8}, :aluminum)],
        116.0,
        "The 10R80, the automatic transmission of 10 speeds: 106.17 kg (Ford, workshop manual of the 2019 Ranger), and 10 kg of its fluid (11.8 L of MERCON ULV): 116 kg. Its box of 0.85 by 0.4 by 0.38 m: an estimate."
      )

    shaft =
      bought(
        "propeller_shaft",
        :shaft,
        [Shape.sweep([{0.0, ya - 0.66, 0.5}, {0.0, yr + 0.2, 0.42}], 0.04, :steel, sides: 10)],
        25.0,
        "The propeller shaft of two pieces of steel: 25 kg (its package is 27.6 kg: an estimate)."
      )

    axle =
      bought(
        "rear_axle_9_75",
        :axle,
        [
          Shape.sweep([{0.12 - tr / 2, yr, rz}, {tr / 2 - 0.12, yr, rz}], 0.06, :steel, sides: 12),
          Shape.cylinder(0.15, 0.2, :steel, sides: 12, frame: Frame.new({-0.1, yr, rz}, {1, 0, 0}, {0, 0, 1}))
        ],
        150.0,
        "The rear axle with a ring gear of 9.75 in, its shafts and its brakes: 150 kg (the housing of the 9.75 in axle of the F-150 ships at 127 kg with no shafts and no brakes, Ford Performance: an estimate)."
      )

    springs =
      bought(
        "leaf_springs",
        :spring,
        for(s <- [1, -1], do: box.({s * 0.55, yr - 0.75, rz - 0.08}, {s * 0.62, yr + 0.75, rz - 0.02}, :steel)),
        40.0,
        "The two leaf springs of the rear axle: 40 kg (an estimate)."
      )

    front =
      bought(
        "front_suspension",
        :suspension,
        [box.({-0.7, ya - 0.1, 0.25}, {0.7, ya + 0.1, 0.4}, :steel)],
        130.0,
        "The front crossmember, the struts, the arms and the steering gear: 130 kg (an estimate)."
      )

    tank =
      bought(
        "fuel_tank",
        :tank,
        [box.({-0.75, l / 2 - 0.5, 0.3}, {-0.1, l / 2 + 0.5, 0.55}, :black)],
        82.0,
        "The fuel tank of 25 gal (Ford, 2025 Transit Technical Specifications): 11.7 kg empty (the tank CK4Z-9002-E, a retailer of Ford parts), and 70 kg of gasoline (94.6 L at 0.74 kg/L: an estimate). The curb weight of Ford is with a full tank."
      )

    battery =
      bought(
        "battery_h6",
        :battery,
        [box.({-0.55, ya - 1.0, 0.35}, {-0.3, ya - 0.72, 0.55}, :black)],
        20.4,
        "The battery H6, 70 Ah, 610 CCA (Ford, 2022 Transit Body and Equipment Mounting Manual, page 87), under the floor of the driver: 20.4 kg (an AGM battery of that size, a retailer)."
      )

    exhaust =
      bought(
        "exhaust",
        :exhaust,
        [
          Shape.sweep(
            [{0.25, ya, 0.45}, {0.35, ya - 0.8, 0.35}, {0.4, yr + 0.6, 0.33}, {0.45, 0.3, 0.33}],
            0.035,
            :steel,
            sides: 10
          ),
          box.({0.25, l / 2 - 0.3, 0.25}, {0.55, l / 2 + 0.3, 0.45}, :steel)
        ],
        25.0,
        "The exhaust with its converters and its muffler: 25 kg (an estimate)."
      )

    # The spare wheel under the back, flat: one cylinder of its size (it
    # is not in sight), with the mass of a tire and a wheel.
    %{diameter: dw, width: ww} = Wheels.tire_size(m["tire"])

    spare =
      bought(
        "spare_wheel",
        :wheel,
        [Shape.cylinder(dw / 2, ww, :tire, sides: 16, frame: Frame.move({0.0, 0.55, 0.33 - ww / 2}))],
        28.1,
        "The spare wheel: a tire of 15.9 kg (Michelin, Agilis CrossClimate data book, 235/65R16C) on a steel wheel of 16 by 6.5 in of 12.2 kg (a retailer)."
      )

    asm
    |> Assembly.add("transmission", hidden.(transmission), to: "engine", at: "origin", port: "origin")
    |> Assembly.add("propeller_shaft", hidden.(shaft), to: "transmission", at: "origin", port: "origin")
    |> Assembly.add("rear_axle", hidden.(axle), to: "propeller_shaft", at: "origin", port: "origin")
    |> Assembly.add("leaf_springs", hidden.(springs), to: "rear_axle", at: "origin", port: "origin")
    |> Assembly.add("front_suspension", hidden.(front), to: "engine", at: "origin", port: "origin")
    |> Assembly.add("fuel_tank", hidden.(tank), at: "origin", port: "origin")
    |> Assembly.add("battery", hidden.(battery), at: "origin", port: "origin")
    |> Assembly.add("exhaust", hidden.(exhaust), at: "origin", port: "origin")
    |> Assembly.add("spare_wheel", hidden.(spare), at: "origin", port: "origin")
  end

  # A part that the line buys, with the mass of its data sheet.
  defp bought(name, kind, shapes, kg, source),
    do: Kit.part(@station, name, kind, shapes, [Kit.origin()], params: %{"mass" => kg}, sources: [source])

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

    Kit.part(@station, "engine_bay_transit", :bay, shapes, [Kit.origin()],
      matter: %{black: {:plastic, 0.0025}, plastic: {:plastic, 0.0025}},
      sources: [
        "The air box, the coolant reservoir, the fuse box and the brake reservoir: from the photos of the bay of a 2022 Transit."
      ]
    )
  end
end
