defmodule Xuong.Models.FordTransit do
  @moduledoc """
  A Ford Transit 148 in high roof van, made a camper van: the "camper" of
  Phượt, and the base van of DIY. It has a sliding door at the right
  side, two rear doors, a roof fan with a lid, and solar panels.

  The parts are made with the back of the van at y = 0; the `place` of
  the assembly moves the van to its center.
  """
  alias Xuong.{Assembly, Frame, Part, Shape}
  alias Xuong.Models.{Body, Vehicle}
  alias Xuong.Parts.{Fasteners, Wheels}

  @length 5.98
  @front_y 5.98 - 1.016
  @rear_y 5.98 - 1.016 - 3.749
  @axle_z 0.356
  @hw 1.028

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
          {5.10, 0.44, 1.74, 1.0, 6.0},
          {5.55, 0.46, 1.30, 0.96, 5.0},
          {5.86, 0.50, 1.06, 0.90, 4.0},
          {@length, 0.58, 0.92, 0.80, 3.0}
        ],
        arches,
        :white,
        sides: 24
      )

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

    bumper_f = Shape.box({-1.0, 5.80, 0.42}, {1.0, @length + 0.02, 0.66}, :trim, round: 0.2, smooth: 2)
    bumper_r = Shape.box({-1.0, -0.06, 0.42}, {1.0, 0.10, 0.58}, :trim, round: 0.2, smooth: 2)
    grille = Shape.box({-0.62, @length - 0.03, 0.68}, {0.62, @length + 0.012, 0.95}, :black, round: 0.2, smooth: 2)
    step = Shape.box({0.85, 3.10, 0.36}, {1.05, 4.20, 0.42}, :black)

    mirrors =
      for x <- [-1, 1],
          do: Shape.box({x * 1.13 - 0.07, 4.78, 1.55}, {x * 1.13 + 0.07, 4.90, 1.85}, :black, round: 0.3, smooth: 2)

    arms = for x <- [-1, 1], do: Shape.sweep([{x * 1.0, 4.85, 1.62}, {x * 1.07, 4.85, 1.62}], 0.014, :black, sides: 6)
    plate = Shape.box({-0.26, -0.07, 0.62}, {0.26, -0.06, 0.73}, :white)

    Part.new(
      "body_transit_148_high",
      :body,
      [shell, windshield, bumper_f, bumper_r, grille, step, plate] ++ cab_windows ++ side_windows ++ mirrors ++ arms,
      [
        origin(),
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
    lid = Shape.box({-0.21, 0.0, 0.0}, {0.21, 0.42, 0.04}, :plastic, round: 0.3, smooth: 2)
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
