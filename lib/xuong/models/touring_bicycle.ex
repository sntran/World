defmodule Xuong.Models.TouringBicycle do
  @moduledoc """
  A touring bicycle (a frame of 54 cm, wheels of 700 x 35c): the
  "bicycle" of Phượt. The frame follows a common geometry of touring
  bikes; the parts have the sizes of their standards.

  The parts are made with the back of the bike at y = 0; the `place` of
  the assembly moves the bike to its center.
  """
  alias Xuong.{Assembly, Frame, Part, Shape, Vec}
  alias Xuong.Parts.Wheels

  @r 0.622 / 2 + 0.034
  @rear {0.0, @r, @r}
  @front {0.0, @r + 1.03, @r}
  @bb {0.0, @r + 0.424, @r - 0.07}
  # The head tube: 72 degrees from the ground.
  @axis {0.0, -0.309, 0.951}
  @head_top {0.0, @r + 0.424 + 0.38, @r - 0.07 + 0.58}

  @sources [
    "A touring frame of 54 cm: wheelbase 1030 mm, chainstay 430 mm, bottom bracket drop 70 mm, stack 580 mm, reach 380 mm, head angle 72 degrees, seat angle 73.5 degrees.",
    "Tires 37-622 (700 x 35c, ETRTO); a crank of 170 mm; a chainring of 44 teeth (182 mm).",
    "The shapes of the saddle and the bags: by eye."
  ]

  @doc "The bicycle."
  def model do
    {_, ry, rz} = @rear
    wheel = Wheels.spoked_wheel("37-622", spokes: 36)
    length = elem(@front, 1) + @r

    Assembly.new("touring_bicycle", frame(),
      root: "frame",
      kind: :vehicle,
      sources: @sources,
      place: Frame.move({0.0, -length / 2, 0.0})
    )
    |> Assembly.add("rear_wheel", wheel, at: "rear_axle", port: "hub", kind: :turns, role: :wheel)
    |> Assembly.add("steer", fork(wheel), at: "steer", port: "steer", kind: :turns, role: :steer, limits: [-60, 60])
    |> Assembly.add("crank", crank(), at: "bb", port: "axle", kind: :turns, role: :crank)
    |> Assembly.add("rack", rack(ry, rz), at: "origin", port: "origin")
    |> Assembly.add("kickstand", kickstand(), at: "stand", port: "pivot", kind: :turns, role: :stand, limits: [0, 75])
  end

  defp port(name, at, axis, up), do: Part.port(name, at, axis, up)
  defp origin, do: port("origin", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})
  defp head_bottom, do: Vec.sub(@head_top, Vec.scale(@axis, 0.15))
  defp steer_port, do: port("steer", head_bottom(), @axis, Vec.norm({0.0, 0.951, 0.309}))

  defp frame do
    seat_top = Vec.add(@bb, Vec.scale({0.0, -0.284, 0.959}, 0.54))
    {_, ry, rz} = @rear
    tube = fn line, r -> Shape.sweep(line, r, :paint, sides: 10) end

    tubes = [
      tube.([@bb, seat_top], 0.0143),
      tube.([seat_top, @head_top], 0.0143),
      tube.([@bb, head_bottom()], 0.0175),
      tube.([head_bottom(), @head_top], 0.018)
      | for(
          x <- [-0.065, 0.065],
          do: [
            tube.([Vec.add(@bb, {x * 0.5, 0.0, 0.0}), {x, ry, rz}], 0.009),
            tube.([Vec.add(seat_top, {x * 0.3, 0.0, -0.02}), {x, ry, rz}], 0.008)
          ]
        )
    ]

    shell =
      Shape.cylinder(0.021, 0.068, :paint,
        sides: 16,
        frame: Frame.new(Vec.add(@bb, {-0.034, 0.0, 0.0}), {1, 0, 0}, {0, 0, 1})
      )

    post =
      Shape.sweep(
        [Vec.sub(seat_top, {0.0, -0.01, 0.05}), Vec.add(seat_top, Vec.scale({0.0, -0.284, 0.959}, 0.2))],
        0.0136,
        :aluminum,
        sides: 10
      )

    saddle_at = Vec.add(seat_top, Vec.scale({0.0, -0.284, 0.959}, 0.2))
    {_, sy, sz} = saddle_at

    saddle =
      Shape.loft(
        Shape.rows_y([
          {sy - 0.11, sz, sz + 0.05, 0.075, 3},
          {sy - 0.02, sz + 0.005, sz + 0.055, 0.07, 3},
          {sy + 0.1, sz + 0.01, sz + 0.05, 0.025, 3},
          {sy + 0.17, sz + 0.015, sz + 0.045, 0.018, 2.5}
        ]),
        :seat,
        smooth: 2
      )

    cage =
      Shape.sweep(
        [
          Vec.lerp(@bb, head_bottom(), 0.3) |> Vec.add({0.0, 0.0, 0.025}),
          Vec.lerp(@bb, head_bottom(), 0.6) |> Vec.add({0.0, 0.0, 0.025})
        ],
        0.036,
        :black,
        sides: 12
      )

    Part.new(
      "frame_touring_54",
      :frame,
      List.flatten(tubes) ++ [shell, post, saddle, cage],
      [
        origin(),
        steer_port(),
        port("rear_axle", @rear, {1, 0, 0}, {0, 0, 1}),
        port("bb", @bb, {1, 0, 0}, {0, 0, 1}),
        port("stand", Vec.add(@bb, {-0.05, -0.08, 0.0}), {1, 0, 0}, {0, 0, 1})
      ],
      sources: ["Steel tubes: 28.6 mm top and seat tube, 35 mm down tube."]
    )
  end

  defp fork(wheel) do
    {_, fy, fz} = @front
    crown = head_bottom()
    # The blades go down the steering axis, then bend forward to the axle
    # (the rake).
    down = Vec.neg(@axis)

    blades =
      for x <- [-0.05, 0.05] do
        line = [
          Vec.add(crown, {x * 0.6, 0.0, 0.0}),
          Vec.add(Vec.add(crown, Vec.scale(down, 0.18)), {x, 0.0, 0.0}),
          Vec.add(Vec.add(crown, Vec.scale(down, 0.31)), {x, 0.022, 0.0}),
          {x, fy, fz}
        ]

        Shape.sweep(line, 0.011, :paint, sides: 8)
      end

    steerer = Shape.sweep([crown, Vec.add(@head_top, Vec.scale(@axis, 0.04))], 0.0143, :black, sides: 10)
    bar_c = Vec.add(@head_top, Vec.add(Vec.scale(@axis, 0.04), {0.0, 0.09, 0.0}))
    stem = Shape.sweep([Vec.add(@head_top, Vec.scale(@axis, 0.035)), bar_c], 0.016, :black, sides: 8)
    # A drop bar: across, then forward and down at each end.
    drops =
      for s <- [-1, 1],
          do: [
            Vec.add(bar_c, {s * 0.21, 0.0, 0.0}),
            Vec.add(bar_c, {s * 0.21, 0.08, -0.03}),
            Vec.add(bar_c, {s * 0.21, 0.06, -0.13}),
            Vec.add(bar_c, {s * 0.21, -0.03, -0.14})
          ]

    bar = Shape.sweep(Enum.reverse(hd(drops)) ++ List.last(drops), 0.0119, :black, sides: 8)
    fender = Shape.loft(Shape.arc({fy, fz}, 0.37, -15, -105, 6, 0.03, 0.004), :black, smooth: 1, sides: 8)

    fork =
      Part.new(
        "fork_touring",
        :fork,
        blades ++ [steerer, stem, bar, fender],
        [steer_port(), port("axle", {0.0, fy, fz}, {1, 0, 0}, {0, 0, 1})],
        sources: ["A steel fork with 45 mm of rake; a drop bar of 42 cm."]
      )

    Assembly.new("fork_touring", fork, root: "fork")
    |> Assembly.add("front_wheel", wheel, at: "axle", port: "hub", kind: :turns, role: :wheel)
  end

  # The crank: the chainring, two arms of 170 mm, and a pedal on each arm
  # that turns on its own axle.
  defp crank do
    ring =
      Shape.lathe([{0.074, -0.002}, {0.091, -0.002}, {0.091, 0.002}, {0.074, 0.002}], :steel, kind: :ring, sides: 44)

    spider =
      Shape.lathe([{0.012, -0.004}, {0.075, -0.004}, {0.075, 0.004}, {0.012, 0.004}], :aluminum, kind: :ring, sides: 10)

    spindle = Shape.cylinder(0.012, 0.15, :steel, sides: 12, frame: Frame.move({0.0, 0.0, -0.075}))

    arms =
      for s <- [-1, 1], do: Shape.sweep([{0.0, 0.0, s * 0.075}, {s * 0.17, 0.0, s * 0.08}], 0.011, :aluminum, sides: 8)

    # The crank is made around its own z axis (the axle, to the right).
    crank =
      Part.new(
        "crankset_170",
        :crankset,
        [ring, spider, spindle | arms],
        [
          port("axle", {0, 0, 0}, {0, 0, 1}, {1, 0, 0}),
          port("pedal_right", {0.17, 0.0, 0.085}, {0, 0, 1}, {1, 0, 0}),
          port("pedal_left", {-0.17, 0.0, -0.085}, {0, 0, -1}, {1, 0, 0})
        ],
        params: %{"crank" => 0.17, "teeth" => 44},
        sources: ["Crank arms of 170 mm; a chainring of 44 teeth."]
      )

    pedal =
      Part.new(
        "pedal_flat",
        :pedal,
        [Shape.box({-0.05, -0.012, 0.015}, {0.05, 0.012, 0.085}, :black, round: 0.2, smooth: 1)],
        [port("axle", {0, 0, 0}, {0, 0, 1}, {1, 0, 0})]
      )

    Assembly.new("crankset_touring", crank, root: "crank")
    |> Assembly.add("pedal_right", pedal, at: "pedal_right", port: "axle", kind: :turns, role: :pedal)
    |> Assembly.add("pedal_left", pedal, at: "pedal_left", port: "axle", kind: :turns, role: :pedal)
  end

  # The rear rack with two bags.
  defp rack(ry, rz) do
    top = rz + 0.03 + 0.03

    rack =
      for x <- [-0.07, 0.07],
          do:
            Shape.sweep(
              [{x, ry - 0.02, rz + 0.02}, {x, ry, top}, {x, ry + 0.32, top}, {x * 0.5, ry + 0.38, top + 0.05}],
              0.005,
              :black,
              sides: 6
            )

    bags =
      for x <- [-0.15, 0.15],
          do:
            Shape.box({x - 0.06, ry - 0.08, rz - 0.05}, {x + 0.06, ry + 0.25, top - 0.01}, :fabric,
              round: 0.2,
              smooth: 2
            )

    Part.new("rack_and_bags_touring", :rack, rack ++ bags, [origin()])
  end

  defp kickstand do
    {_, by, bz} = Vec.add(@bb, {-0.05, -0.08, 0.0})
    leg = Shape.sweep([{-0.05, by, bz}, {-0.06, by - 0.27, bz + 0.02}], 0.008, :aluminum, sides: 6)
    Part.new("kickstand", :stand, leg, [port("pivot", {-0.05, by, bz}, {1, 0, 0}, {0, 0, 1})])
  end
end
