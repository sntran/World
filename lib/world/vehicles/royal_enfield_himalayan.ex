defmodule World.Vehicles.RoyalEnfieldHimalayan do
  @moduledoc """
  A Royal Enfield Himalayan 411 (2021): an adventure motorcycle, the
  "motorcycle" of Phượt, and a common bike for long trips in Việt Nam.

  The parts are made with the back of the bike at y = 0; the `place` of
  the assembly moves the bike to its center. The shapes follow photos of
  the bike, by eye.
  """
  alias World.{Assembly, Frame, Part, Shape, Vec}
  alias World.Materials.{Fasteners, Stock}
  alias World.Vehicles.Wheels
  @length 2.19
  @rear {0.0, 0.33, 0.324}
  @front {0.0, 1.795, 0.348}
  @pivot {0.0, 0.88, 0.44}
  # The steering axis: 26.5 degrees from up.
  @axis {0.0, -0.4462, 0.8949}
  @head {0.0, 1.447, 1.046}

  @sources [
    "Royal Enfield Himalayan 411 (2021): length 2190 mm, width 840 mm, height 1370 mm, wheelbase 1465 mm, seat 800 mm, ground clearance 220 mm.",
    "Tires 90/90-21 at the front and 120/90-17 at the back, on wire spokes; discs of 300 mm (front) and 240 mm (back); rake 26.5 degrees.",
    "The shapes of the tank, the seat and the engine: by eye, from photos of the bike."
  ]

  @doc "The motorcycle."
  def model do
    Assembly.new("royal_enfield_himalayan", frame(),
      root: "frame",
      kind: :vehicle,
      sources: @sources,
      place: Frame.move({0.0, -@length / 2, 0.0})
    )
    |> Assembly.add("engine", engine(), at: "origin", port: "origin")
    |> Assembly.add("tank", tank_and_seat(), at: "origin", port: "origin")
    |> Assembly.add("steer", fork(), at: "steer", port: "steer", kind: :turns, role: :steer, limits: [-35, 35])
    |> Assembly.add("swingarm", swingarm(),
      at: "pivot",
      port: "pivot",
      kind: :turns,
      role: :suspension,
      limits: [-6, 10]
    )
    |> Assembly.add("side_stand", side_stand(), at: "stand", port: "pivot", kind: :turns, role: :stand, limits: [0, 80])
  end

  defp port(name, at, axis, up), do: Part.port(name, at, axis, up)
  defp origin, do: port("origin", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})
  defp steer_port, do: port("steer", @head, @axis, Vec.norm({0.0, 0.8949, 0.4462}))

  # A frame of steel tube: the cradle under the engine, the top tubes, and
  # the subframe of the seat.
  defp frame do
    tube = fn line, r -> Shape.sweep(line, r, :black, sides: 10) end

    tubes =
      for x <- [-0.07, 0.07] do
        [
          tube.(
            [
              {x * 0.4, 1.42, 0.98},
              {x, 1.30, 0.62},
              {x, 1.22, 0.30},
              {x, 0.98, 0.26},
              {x, 0.88, 0.44},
              {x, 0.86, 0.78},
              {x * 1.4, 0.40, 0.86},
              {x * 1.4, 0.18, 0.88}
            ],
            0.016
          ),
          tube.([{x * 0.4, 1.44, 1.03}, {x, 1.10, 0.92}, {x, 0.86, 0.78}], 0.018),
          tube.([{x, 0.88, 0.50}, {x * 1.4, 0.45, 0.84}], 0.012)
        ]
      end

    head =
      Shape.lathe([{0.0, -0.08}, {0.03, -0.08}, {0.03, 0.08}, {0.0, 0.08}], :black,
        sides: 12,
        frame: Frame.new(@head, @axis, {0.0, 0.8949, 0.4462})
      )

    guards =
      for x <- [-1, 1],
          do:
            tube.([{x * 0.06, 1.38, 0.95}, {x * 0.2, 1.3, 0.85}, {x * 0.21, 1.15, 0.78}, {x * 0.08, 1.05, 0.78}], 0.011)

    Part.new(
      "frame_himalayan",
      :frame,
      List.flatten(tubes) ++ [head | guards],
      [
        origin(),
        steer_port(),
        port("pivot", @pivot, {1, 0, 0}, {0, 0, 1}),
        port("stand", {-0.12, 1.0, 0.30}, {1, 0, 0}, {0, 0, 1})
      ],
      sources: ["A half duplex split cradle frame of steel tube."]
    )
  end

  defp engine do
    crankcase =
      Shape.loft(
        Shape.rows_y([
          {0.92, 0.28, 0.52, 0.11, 4},
          {1.05, 0.25, 0.58, 0.14, 4},
          {1.25, 0.28, 0.56, 0.13, 4},
          {1.32, 0.34, 0.5, 0.09, 3}
        ]),
        :black,
        smooth: 2
      )

    cylinder =
      Shape.loft(
        Shape.rows_z([{0.52, 1.1, 1.3, 0.07, 4}, {0.68, 1.13, 1.32, 0.075, 4}, {0.78, 1.15, 1.3, 0.07, 4}]),
        :aluminum,
        smooth: 1
      )

    fins =
      for z <- [0.56, 0.6, 0.64, 0.68, 0.72],
          do: Shape.box({-0.085, 1.11 + (z - 0.52) * 0.15, z}, {0.085, 1.33 + (z - 0.52) * 0.1, z + 0.008}, :aluminum)

    exhaust =
      Shape.sweep(
        [{0.04, 1.32, 0.66}, {0.07, 1.38, 0.5}, {0.09, 1.3, 0.28}, {0.12, 1.0, 0.27}, {0.15, 0.75, 0.38}],
        0.022,
        :chrome,
        sides: 10
      )

    muffler =
      Shape.lathe([{0.0, 0.0}, {0.05, 0.02}, {0.055, 0.32}, {0.045, 0.34}, {0.0, 0.34}], :black,
        sides: 16,
        smooth: 1,
        frame: Frame.new({0.15, 0.76, 0.38}, Vec.norm({0.0, -0.9, 0.35}), {0, 0, 1})
      )

    Part.new("engine_himalayan_411", :engine, [crankcase, cylinder, exhaust, muffler | fins], [origin()],
      sources: ["411 cc, one cylinder, air and oil cooled."]
    )
  end

  defp tank_and_seat do
    tank =
      Shape.loft(
        Shape.rows_y([
          {0.98, 0.84, 0.98, 0.1, 3},
          {1.1, 0.82, 1.1, 0.16, 4},
          {1.3, 0.85, 1.12, 0.17, 4},
          {1.42, 0.92, 1.08, 0.11, 3}
        ]),
        :paint,
        smooth: 2
      )

    seat =
      Shape.loft(
        Shape.rows_y([
          {0.3, 0.86, 0.9, 0.08, 3},
          {0.45, 0.86, 0.94, 0.12, 4},
          {0.75, 0.80, 0.86, 0.13, 4},
          {1.0, 0.82, 0.9, 0.12, 3}
        ]),
        :seat,
        smooth: 2
      )

    fender =
      Shape.loft(
        Shape.rows_y([{0.05, 0.86, 0.88, 0.07, 4}, {0.3, 0.84, 0.87, 0.1, 4}, {0.5, 0.80, 0.84, 0.1, 4}]),
        :black,
        smooth: 1
      )

    rack =
      Shape.sweep([{-0.12, 0.45, 0.92}, {-0.12, 0.12, 0.93}, {0.12, 0.12, 0.93}, {0.12, 0.45, 0.92}], 0.009, :black,
        sides: 6
      )

    plate = Shape.box({-0.09, 0.02, 0.64}, {0.09, 0.03, 0.76}, :white)
    tail = Shape.box({-0.05, 0.06, 0.82}, {0.05, 0.1, 0.86}, :light_back, round: 0.3, smooth: 1)
    lights = Part.new("tail_light_himalayan", :light, tail, [origin()], detail: :always)

    body =
      Part.new("tank_seat_himalayan", :body, [tank, seat, fender, rack, plate], [origin()],
        sources: ["Tank of 15 L; seat at 800 mm."]
      )

    Assembly.new("tank_seat_himalayan", body, root: "body")
    |> Assembly.add("tail_light", lights, at: "origin", port: "origin")
  end

  # The fork, the bars, the light with its screen, and the front wheel.
  defp fork do
    {_, fy, fz} = @front
    up = fn p, t -> Vec.add(p, Vec.scale(@axis, t)) end

    legs =
      for x <- [-0.09, 0.09],
          do: Shape.sweep([up.({x, fy, fz}, 0.0), up.({x, fy, fz}, 0.42)], 0.024, :aluminum, sides: 12)

    tubes =
      for x <- [-0.09, 0.09],
          do: Shape.sweep([up.({x, fy, fz}, 0.42), up.({x, fy, fz}, 0.80)], 0.0205, :chrome, sides: 12)

    clamp =
      for t <- [0.62, 0.78], do: Shape.sweep([up.({-0.12, fy, fz}, t), up.({0.12, fy, fz}, t)], 0.022, :black, sides: 8)

    fender = Shape.loft(Shape.arc({fy, fz}, 0.39, -20, -100, 6, 0.06, 0.008), :black, smooth: 1, sides: 8)
    bar_c = up.({0.0, fy, fz}, 0.86)

    bar =
      Shape.sweep(
        [
          Vec.add(bar_c, {-0.42, -0.12, 0.08}),
          Vec.add(bar_c, {-0.2, -0.05, 0.05}),
          bar_c,
          Vec.add(bar_c, {0.2, -0.05, 0.05}),
          Vec.add(bar_c, {0.42, -0.12, 0.08})
        ],
        0.0127,
        :black,
        sides: 10
      )

    grips =
      for s <- [-1, 1],
          do:
            Shape.cylinder(0.017, 0.13, :rubber,
              sides: 12,
              frame: Frame.new(Vec.add(bar_c, {s * 0.30, -0.10, 0.075}), {s * 1.0, -0.2, 0.0}, {0, 0, 1})
            )

    light =
      Shape.lathe([{0.0, 0.0}, {0.09, 0.0}, {0.095, -0.08}, {0.06, -0.12}, {0.0, -0.12}], :black,
        sides: 20,
        frame: Frame.new(up.({0.0, fy + 0.06, fz}, 0.62), {0.0, 1.0, 0.0}, {0, 0, 1})
      )

    lens =
      Shape.lathe([{0.0, 0.0}, {0.085, 0.0}, {0.07, 0.015}, {0.0, 0.02}], :light_front,
        sides: 20,
        frame: Frame.new(up.({0.0, fy + 0.06, fz}, 0.62), {0.0, 1.0, 0.0}, {0, 0, 1})
      )

    screen = Shape.loft(Shape.rows_z([{1.12, 1.62, 1.64, 0.15, 4}, {1.32, 1.5, 1.52, 0.13, 4}]), :glass, sides: 12)

    mirrors =
      for s <- [-1, 1],
          do: [
            Shape.sweep(
              [Vec.add(bar_c, {s * 0.24, -0.06, 0.06}), Vec.add(bar_c, {s * 0.3, -0.04, 0.26})],
              0.006,
              :black,
              sides: 6
            ),
            Shape.box(
              Vec.add(bar_c, {s * 0.3 - 0.05, -0.05, 0.25}),
              Vec.add(bar_c, {s * 0.3 + 0.05, -0.03, 0.32}),
              :black,
              round: 0.3,
              smooth: 2
            )
          ]

    fork =
      Part.new(
        "fork_himalayan",
        :fork,
        legs ++ tubes ++ clamp ++ [fender],
        [
          steer_port(),
          port("axle", {0.0, fy, fz}, {1, 0, 0}, {0, 0, 1}),
          port("axle_bolt", {-0.12, fy, fz}, {1, 0, 0}, {0, 0, 1}),
          port("axle_nut", {0.115, fy, fz}, {1, 0, 0}, {0, 0, 1}),
          origin()
        ],
        sources: ["A telescopic fork of 41 mm, 200 mm of travel."]
      )

    cockpit = Part.new("cockpit_himalayan", :handlebar, [bar, screen | grips] ++ List.flatten(mirrors), [origin()])
    head_light = Part.new("head_light_himalayan", :light, [light, lens], [origin()], detail: :always)

    Assembly.new("fork_himalayan", fork, root: "fork")
    |> Assembly.add("cockpit", cockpit, at: "origin", port: "origin")
    |> Assembly.add("head_light", head_light, at: "origin", port: "origin")
    |> Assembly.add(
      "front_wheel",
      Wheels.spoked_wheel("90/90-21", spokes: 36, rim_depth: 0.018, hub_width: 0.11, rim_material: :black, disc: 0.3),
      at: "axle",
      port: "hub",
      kind: :turns,
      role: :wheel
    )
    |> Assembly.add("axle_bolt", Fasteners.bolt("M16", 0.26), at: "axle_bolt", port: "head")
    |> Assembly.add("axle_nut", Fasteners.nut("M16"), at: "axle_nut", port: "face")
  end

  defp swingarm do
    {_, ry, rz} = @rear
    arms = for x <- [-0.1, 0.1], do: Shape.sweep([{x, 0.88, 0.44}, {x, ry, rz}], 0.02, :black, sides: 8)
    cross = Shape.sweep([{-0.1, 0.80, 0.42}, {0.1, 0.80, 0.42}], 0.018, :black, sides: 8)

    chain =
      Shape.sweep(
        [
          {0.115, 1.13, 0.40},
          {0.115, ry, rz + 0.11},
          {0.115, ry - 0.11, rz},
          {0.115, ry, rz - 0.11},
          {0.115, 1.13, 0.36}
        ],
        0.006,
        :metal,
        sides: 6
      )

    arm =
      Part.new(
        "swingarm_himalayan",
        :swingarm,
        [arms, cross, chain] |> List.flatten(),
        [
          port("pivot", @pivot, {1, 0, 0}, {0, 0, 1}),
          port("axle", {0.0, ry, rz}, {1, 0, 0}, {0, 0, 1}),
          port("shock", {0.0, 0.78, 0.46}, Vec.norm({0.0, 0.3, 1.0}), {0, 1, 0})
        ],
        sources: ["A box section swing arm with a monoshock (linkage)."]
      )

    Assembly.new("swingarm_himalayan", arm, root: "arm")
    |> Assembly.add(
      "shock",
      Stock.spring(0.06, 0.009, 0.28, 8, :paint, name: "monoshock_spring_himalayan") |> Map.put(:inside, true),
      at: "shock",
      port: "end_a"
    )
    |> Assembly.add(
      "rear_wheel",
      Wheels.spoked_wheel("120/90-17", spokes: 36, rim_depth: 0.018, hub_width: 0.13, rim_material: :black, disc: 0.24),
      at: "axle",
      port: "hub",
      kind: :turns,
      role: :wheel
    )
  end

  # The side stand at the left: at rest along the frame, at 80 degrees down
  # on the ground.
  defp side_stand do
    leg = Shape.sweep([{-0.12, 1.0, 0.30}, {-0.13, 0.72, 0.30}], 0.012, :black, sides: 8)
    foot = Shape.box({-0.15, 0.70, 0.29}, {-0.11, 0.75, 0.31}, :black)
    Part.new("side_stand_himalayan", :stand, [leg, foot], [port("pivot", {-0.12, 1.0, 0.30}, {1, 0, 0}, {0, 0, 1})])
  end
end
