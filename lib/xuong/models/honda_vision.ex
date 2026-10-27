defmodule Xuong.Models.HondaVision do
  @moduledoc """
  A Honda Vision 110 (2021, the model of Việt Nam): a scooter, the
  "motorbike" of Phượt.

  The parts of the scooter are made with the back of the scooter at
  y = 0 (the `place` of the assembly moves it to its center). The shaped
  parts (the body, the seat, the engine) follow the photos of the
  scooter, by eye; the sizes are from the data page of the model.
  """
  alias Xuong.{Assembly, Frame, Part, Shape}
  alias Xuong.Parts.{Fasteners, Stock, Wheels}

  @length 1.871
  @rear {0.0, 0.30, 0.259}
  @front {0.0, 1.555, 0.250}
  @pivot {0.0, 0.80, 0.30}
  # The steering axis: 26.6 degrees from up, through the fork.
  @steer_axis {0.0, -0.447, 0.894}
  @steer_at {0.0, 1.328, 0.703}

  @sources [
    "Honda Vision 110 (2021, Việt Nam): length 1871 mm, width 686 mm, height 1101 mm, wheelbase 1255 mm, seat 761 mm.",
    "Tires: 80/90-14 at the front, 90/90-14 at the back; a disc brake of 190 mm at the front.",
    "The shapes of the body, the seat and the engine: by eye, from photos of the scooter."
  ]

  @doc "The scooter."
  def model do
    Assembly.new("honda_vision_110", frame(),
      root: "frame",
      kind: :vehicle,
      sources: @sources,
      place: Frame.move({0.0, -@length / 2, 0.0})
    )
    |> Assembly.add("body", body(), at: "body", port: "body")
    |> Assembly.add("seat", seat(), at: "seat", port: "hinge", kind: :turns, role: :lid, limits: [0, 75])
    |> Assembly.add("fork", fork(), at: "steer", port: "steer", kind: :turns, role: :steer, limits: [-38, 38])
    |> Assembly.add("engine", engine(), at: "pivot", port: "pivot", kind: :turns, role: :suspension, limits: [-4, 8])
    |> Assembly.add("stand", stand(), at: "stand", port: "pivot", kind: :turns, role: :stand, limits: [0, 92])
  end

  # The same port on two parts: the child stays where its shapes are.
  defp same(name, at, axis, up), do: Part.port(name, at, axis, up)
  defp origin(name), do: same(name, {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  # The frame: a steel tube from the head to the back, under the body.
  defp frame do
    line = [
      {0.0, 1.33, 0.70},
      {0.0, 1.22, 0.30},
      {0.0, 0.95, 0.24},
      {0.0, 0.75, 0.42},
      {0.0, 0.35, 0.62},
      {0.0, 0.08, 0.66}
    ]

    tube = Shape.sweep(line, 0.024, :black, sides: 10)

    head =
      Shape.lathe([{0.0, -0.08}, {0.032, -0.08}, {0.032, 0.08}, {0.0, 0.08}], :black,
        sides: 12,
        frame: Frame.new(@steer_at, @steer_axis, {0.0, 0.894, 0.447})
      )

    Part.new(
      "frame_vision",
      :frame,
      [tube, head],
      [
        origin("body"),
        same("seat", {0.0, 0.88, 0.79}, {-1, 0, 0}, {0, 0, 1}),
        same("steer", @steer_at, @steer_axis, {0.0, 0.894, 0.447}),
        same("pivot", @pivot, {1, 0, 0}, {0, 0, 1}),
        same("stand", {0.0, 0.70, 0.17}, {1, 0, 0}, {0, 0, 1})
      ], inside: true, sources: ["An underbone frame of steel tube, 48 mm."])
  end

  defp body do
    rear =
      Shape.loft(
        Shape.rows_y([
          {-0.03, 0.73, 0.79, 0.045, 3},
          {0.06, 0.6, 0.82, 0.11, 3.5},
          {0.22, 0.47, 0.82, 0.16, 4},
          {0.45, 0.4, 0.8, 0.175, 4},
          {0.66, 0.34, 0.76, 0.165, 4},
          {0.82, 0.3, 0.66, 0.14, 4}
        ]),
        :paint,
        smooth: 2
      )

    floor =
      Shape.loft(
        Shape.rows_y([
          {0.74, 0.2, 0.33, 0.15, 6},
          {0.9, 0.19, 0.31, 0.17, 6},
          {1.18, 0.19, 0.31, 0.17, 6},
          {1.3, 0.2, 0.34, 0.15, 6}
        ]),
        :trim, smooth: 1)

    shield =
      Shape.loft(
        Shape.rows_z([
          {0.22, 1.25, 1.44, 0.13, 3},
          {0.36, 1.22, 1.47, 0.19, 3.5},
          {0.6, 1.18, 1.41, 0.205, 3.5},
          {0.82, 1.14, 1.34, 0.185, 3.5},
          {0.96, 1.11, 1.29, 0.14, 3}
        ]),
        :paint,
        smooth: 2
      )

    front_light =
      Shape.loft(
        Shape.rows_z([{0.62, 1.395, 1.43, 0.09, 3}, {0.7, 1.37, 1.415, 0.11, 3}, {0.78, 1.345, 1.39, 0.07, 3}]),
        :light_front, smooth: 1, sides: 12)

    rear_light =
      Shape.loft(
        Shape.rows_y([{-0.045, 0.74, 0.785, 0.035, 2.5}, {0.0, 0.73, 0.79, 0.09, 3}, {0.05, 0.725, 0.79, 0.1, 3}]),
        :light_back, smooth: 1, sides: 12)

    plate = Shape.box({-0.08, 0.01, 0.48}, {0.08, 0.025, 0.6}, :white)
    holder = Shape.box({-0.035, 0.03, 0.58}, {0.035, 0.08, 0.72}, :trim)

    rail =
      Shape.sweep([{-0.14, 0.32, 0.86}, {-0.13, 0.05, 0.86}, {0.13, 0.05, 0.86}, {0.14, 0.32, 0.86}], 0.012, :aluminum,
        sides: 8
      )

    panels =
      Part.new("body_vision", :body, [rear, floor, shield, plate, holder, rail], [origin("body")],
        sources: ["By eye, from photos."]
      )

    lights = Part.new("lights_vision", :light, [front_light, rear_light], [origin("body")], detail: :always)

    Assembly.new("body_vision", panels, root: "panels")
    |> Assembly.add("lights", lights, at: "body", port: "body")
  end

  # The seat turns up around a hinge at its front.
  defp seat do
    shape =
      Shape.loft(
        Shape.rows_y([
          {0.1, 0.8, 0.85, 0.08, 3},
          {0.2, 0.795, 0.895, 0.14, 4},
          {0.5, 0.78, 0.875, 0.15, 4},
          {0.76, 0.75, 0.84, 0.135, 4},
          {0.88, 0.72, 0.79, 0.08, 3}
        ]),
        :seat,
        smooth: 2
      )

    Part.new("seat_vision", :seat, shape, [same("hinge", {0.0, 0.88, 0.79}, {-1, 0, 0}, {0, 0, 1})],
      sources: ["Seat height 761 mm (data page)."]
    )
  end

  # The fork, the front fender, the bars with their grips, levers and
  # mirrors, and the front wheel on its axle bolt.
  defp fork do
    {_, fy, fz} = @front
    legs = for x <- [-0.065, 0.065], do: Shape.sweep([{x, fy, fz}, {x, 1.4, 0.56}], 0.022, :aluminum, sides: 12)
    tubes = for x <- [-0.065, 0.065], do: Shape.sweep([{x, 1.43, 0.50}, {x, 1.33, 0.70}], 0.016, :chrome, sides: 12)
    clamp = Shape.box({-0.09, 1.31, 0.70}, {0.09, 1.36, 0.73}, :black)
    fender = Shape.loft(Shape.arc({fy, fz}, 0.305, 60, -45, 6, 0.065, 0.012), :paint, smooth: 2, sides: 8)

    bar =
      Shape.sweep(
        [{-0.34, 1.12, 1.05}, {-0.18, 1.14, 1.04}, {0.0, 1.16, 1.0}, {0.18, 1.14, 1.04}, {0.34, 1.12, 1.05}],
        0.011,
        :chrome, sides: 10)

    stem = Shape.sweep([{0.0, 1.33, 0.70}, {0.0, 1.20, 0.98}, {0.0, 1.16, 1.0}], 0.014, :steel, sides: 10)

    head =
      Shape.loft(
        Shape.rows_y([
          {1.0, 0.975, 1.045, 0.1, 3},
          {1.1, 0.955, 1.09, 0.19, 4},
          {1.24, 0.955, 1.08, 0.165, 4},
          {1.34, 0.97, 1.055, 0.1, 3}
        ]),
        :paint, smooth: 2)

    fork =
      Part.new(
        "fork_vision",
        :fork,
        legs ++ tubes ++ [clamp, fender],
        [
          same("steer", @steer_at, @steer_axis, {0.0, 0.894, 0.447}),
          same("axle_bolt", {-0.095, fy, fz}, {1, 0, 0}, {0, 0, 1}),
          same("axle", {0.0, fy, fz}, {1, 0, 0}, {0, 0, 1}),
          same("axle_nut", {0.088, fy, fz}, {1, 0, 0}, {0, 0, 1}),
          origin("bars")
        ], sources: ["A telescopic fork, 26.6 degrees from up."])

    bars =
      Part.new("handlebar_vision", :handlebar, [bar, stem, head], [origin("bars")],
        sources: ["A steel bar of 22.2 mm."]
      )

    grip = fn x ->
      Shape.cylinder(0.017, 0.12, :rubber,
        sides: 12,
        frame: Frame.new({x, 1.12, 1.05}, {if(x > 0, do: 1.0, else: -1.0), 0.0, 0.0}, {0, 0, 1})
      )
    end

    grips = Part.new("grip_22", :grip, [grip.(0.22), grip.(-0.22)], [origin("bars")])
    lever = fn x -> Shape.sweep([{x, 1.15, 1.06}, {x * 1.5, 1.17, 1.06}], 0.005, :aluminum, sides: 6) end
    levers = Part.new("brake_lever", :lever, [lever.(0.2), lever.(-0.2)], [origin("bars")])

    mirror = fn x ->
      sign = if x > 0, do: 1, else: -1

      arm =
        Shape.sweep([{0.17 * sign, 1.13, 1.06}, {0.21 * sign, 1.11, 1.03}, {0.25 * sign, 1.1, 1.05}], 0.006, :black,
          sides: 6
        )

      glass = Shape.box({x - 0.06, 1.08, 1.04}, {x + 0.06, 1.105, 1.1}, :trim, round: 0.3, smooth: 2)
      [arm, glass]
    end

    mirrors = Part.new("mirror_vision", :mirror, mirror.(0.25) ++ mirror.(-0.25), [origin("bars")])

    Assembly.new("fork_vision", fork, root: "fork")
    |> Assembly.add("bars", bars, at: "bars", port: "bars")
    |> Assembly.add("grips", grips, at: "bars", port: "bars")
    |> Assembly.add("levers", levers, at: "bars", port: "bars")
    |> Assembly.add("mirrors", mirrors, at: "bars", port: "bars")
    |> Assembly.add("front_wheel", Wheels.cast_wheel("80/90-14", disc: true),
      at: "axle",
      port: "hub",
      kind: :turns,
      role: :wheel
    )
    |> Assembly.add("axle_bolt", Fasteners.bolt("M12", 0.2), at: "axle_bolt", port: "head")
    |> Assembly.add("axle_nut", Fasteners.nut("M12"), at: "axle_nut", port: "face")
  end

  # The engine and the swing arm, in one unit that turns at its pivot, with
  # the muffler, the rear shock and the rear wheel.
  defp engine do
    {_, ry, rz} = @rear

    case_ =
      Shape.loft(
        Shape.rows_y(
          [
            {0.2, 0.17, 0.33, 0.04, 3},
            {0.32, 0.14, 0.39, 0.055, 4},
            {0.62, 0.15, 0.42, 0.06, 4},
            {0.84, 0.19, 0.38, 0.05, 3}
          ],
          -0.115
        ),
        :aluminum, smooth: 2)

    cylinder =
      Shape.loft(Shape.rows_y([{0.7, 0.22, 0.34, 0.07, 4}, {0.86, 0.22, 0.36, 0.09, 4}], 0.0), :metal, smooth: 1)

    muffler =
      Shape.lathe([{0.0, -0.2}, {0.05, -0.18}, {0.058, 0.0}, {0.05, 0.14}, {0.03, 0.16}, {0.0, 0.16}], :chrome,
        sides: 16,
        smooth: 1,
        frame: Frame.new({0.13, 0.36, 0.3}, {0.0, -1.0, 0.18}, {0, 0, 1})
      )

    pipe =
      Shape.sweep([{0.0, 0.84, 0.24}, {0.06, 0.7, 0.2}, {0.13, 0.6, 0.24}, {0.13, 0.52, 0.27}], 0.018, :steel, sides: 8)

    unit =
      Part.new(
        "engine_vision",
        :engine,
        [case_, cylinder, muffler, pipe],
        [
          same("pivot", @pivot, {1, 0, 0}, {0, 0, 1}),
          same("axle", {0.0, ry, rz}, {1, 0, 0}, {0, 0, 1}),
          same("axle_nut", {0.07, ry, rz}, {1, 0, 0}, {0, 0, 1}),
          same("shock", {0.12, 0.28, 0.33}, {0.0, 0.25, 0.97}, {0, 1, 0})
        ], sources: ["A 110 cc engine, air cooled, with its belt case at the left."])

    shock = Stock.spring(0.045, 0.006, 0.26, 7, :paint, name: "shock_spring_vision")

    Assembly.new("engine_vision", unit, root: "unit")
    |> Assembly.add("shock", shock, at: "shock", port: "end_a")
    |> Assembly.add("rear_wheel", Wheels.cast_wheel("90/90-14"), at: "axle", port: "hub", kind: :turns, role: :wheel)
    |> Assembly.add("axle_nut", Fasteners.nut("M14"), at: "axle_nut", port: "face")
  end

  # The center stand: at rest its legs go back, under the scooter; at 92
  # degrees they stand on the ground.
  defp stand do
    legs =
      for x <- [-0.1, 0.1],
          do: Shape.sweep([{x, 0.70, 0.17}, {x, 0.6, 0.17}, {x * 1.2, 0.53, 0.16}], 0.011, :black, sides: 8)

    foot = Shape.sweep([{-0.12, 0.53, 0.16}, {0.12, 0.53, 0.16}], 0.011, :black, sides: 8)
    Part.new("center_stand_vision", :stand, legs ++ [foot], [same("pivot", {0.0, 0.70, 0.17}, {1, 0, 0}, {0, 0, 1})])
  end
end
