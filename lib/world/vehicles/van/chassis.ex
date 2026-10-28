defmodule World.Vehicles.Van.Chassis do
  @moduledoc """
  The fifth station of the line of a van (`World.Vehicles.Van`): the
  marriage of the body and the drive. The engine bay under the hood (the
  3.5 L V6 with its belt, the radiator and its fan, the air box, the
  reservoirs and the fuse box), the items of DIY in the bay (a second
  alternator, a DC-DC charger), and the four wheels, the front two on
  their knuckles that steer.
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
    |> Corners.corner("front_right", wheel, {tf / 2, l - f, rz}, steer: true, limits: [-38, 38], disc: 0.30)
    |> Corners.corner("front_left", wheel, {-tf / 2, l - f, rz}, steer: true, limits: [-38, 38], disc: 0.30)
    |> Corners.corner("rear_right", wheel, {tr / 2, l - f - wb, rz}, disc: 0.30)
    |> Corners.corner("rear_left", wheel, {-tr / 2, l - f - wb, rz}, disc: 0.30)
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
        kind: :turns,
        role: :spin
      )
      |> Assembly.add("bay_parts", hidden.(bay_parts(l)), at: "origin", port: "origin")

    Enum.reduce(items, asm, fn
      :second_alternator, asm ->
        Assembly.add(asm, "second_alternator", inside(Kit.station(Camper.second_alternator(), "upfit")),
          at: Kit.port("second_alternator", {-0.42, l - 0.48, 0.84}, {0, 0, 1}, {0, 1, 0}),
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

    Kit.part(@station, "radiator_transit", :radiator, [core | tanks ++ shroud], [Kit.origin()],
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

    Kit.part(@station, "radiator_fan_transit", :fan, [hub | blades], [
      Kit.port("axle", {0.0, y, 0.8}, {0, 1, 0}, {0, 0, 1})
    ])
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

    Kit.part(@station, "engine_bay_transit", :bay, shapes, [Kit.origin()],
      sources: [
        "The air box, the coolant reservoir, the fuse box and the brake reservoir: from the photos of the bay of a 2022 Transit."
      ]
    )
  end
end
