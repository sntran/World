defmodule World.Vehicles.Bicycle do
  @moduledoc """
  A bicycle with a diamond frame from its geometry sheet (plan 0002,
  D5): the numbers that a maker gives for each size of a frame. The
  skills `bicycle_frame`, `bicycle_fork` and `crankset` take them, and
  `World.Vehicles.TouringBicycle` is one sheet (`touring/0`).

  The sheet (meters and degrees): `tire` (its code: the axle height is
  its radius less the `sag` of the tire under the rider), `wheelbase`,
  `chainstay`, `bb_drop`, `stack`, `reach`, `head_angle`, `seat_angle`,
  `seat_tube`, `head_tube`, `seatpost`, `rear_spacing`, the outside
  diameter of each tube (`top_tube_d`, `down_tube_d`, `head_tube_d`,
  `chainstay_d`, `seatstay_d`), `bar_width`, `arm` (the crank) and
  `teeth` (the chainring). The parts are made with the back of the bike
  at y = 0, the front to +y.
  """
  alias World.{Assembly, Frame, Part, Shape, Vec}
  alias World.Vehicles.Wheels

  @touring %{
    "tire" => "37-622",
    "sag" => 0.003,
    "wheelbase" => 1.03,
    "chainstay" => 0.43,
    "bb_drop" => 0.07,
    "stack" => 0.58,
    "reach" => 0.38,
    "head_angle" => 72.0,
    "seat_angle" => 73.5,
    "seat_tube" => 0.54,
    "head_tube" => 0.15,
    "seatpost" => 0.2,
    "rear_spacing" => 0.13,
    "top_tube_d" => 0.0286,
    "down_tube_d" => 0.035,
    "head_tube_d" => 0.036,
    "chainstay_d" => 0.018,
    "seatstay_d" => 0.016,
    "bar_width" => 0.42,
    "rake" => 0.045,
    "arm" => 0.17,
    "teeth" => 44
  }

  @doc "The sheet of a touring frame of 54 cm (`World.Vehicles.TouringBicycle`)."
  def touring, do: @touring

  @doc """
  The points of a sheet: `r` (the axle height), `rear` and `front` (the
  axles), `bb` (the bottom bracket), `axis` (the steering axis, up),
  `head_top`, `head_bottom` and `seat_top`, and `seat_dir` (along the
  seat tube, up).
  """
  def points(s) do
    r = Wheels.tire_radius(s["tire"]) - s["sag"]
    bb_y = r + :math.sqrt(s["chainstay"] ** 2 - s["bb_drop"] ** 2)
    bb = {0.0, bb_y, r - s["bb_drop"]}
    axis = dir(s["head_angle"])
    seat_dir = dir(s["seat_angle"])
    head_top = Vec.add(bb, {0.0, s["reach"], s["stack"]})

    %{
      r: r,
      rear: {0.0, r, r},
      front: {0.0, r + s["wheelbase"], r},
      bb: bb,
      axis: axis,
      seat_dir: seat_dir,
      head_top: head_top,
      head_bottom: Vec.sub(head_top, Vec.scale(axis, s["head_tube"])),
      seat_top: Vec.add(bb, Vec.scale(seat_dir, s["seat_tube"]))
    }
  end

  # A direction up and back at an angle from the ground (a tube of the frame).
  defp dir(angle) do
    a = angle * :math.pi() / 180
    {0.0, -:math.cos(a), :math.sin(a)}
  end

  defp port(name, at, axis, up), do: Part.port(name, at, axis, up)

  @doc "The port `steer` of the frame and of the fork: on the steering axis at the bottom of the head tube."
  def steer_port(s) do
    %{head_bottom: hb, axis: axis} = points(s)
    {_, ay, az} = axis
    port("steer", hb, axis, Vec.norm({0.0, az, -ay}))
  end

  @doc """
  The frame: the tubes, the bottom bracket shell, the seat post, the
  saddle and a bottle cage, with the ports `origin`, `steer`,
  `rear_axle`, `bb`, `stand` (for a kickstand) and `rack` (at the rear
  axle, for a rack).
  """
  def frame(s, name) do
    %{rear: {_, ry, rz} = rear, bb: bb, head_top: ht, head_bottom: hb, seat_top: st, seat_dir: sd} = points(s)
    tube = fn line, d -> Shape.sweep(line, d / 2, :paint, sides: 10) end
    half = s["rear_spacing"] / 2

    tubes = [
      tube.([bb, st], s["top_tube_d"]),
      tube.([st, ht], s["top_tube_d"]),
      tube.([bb, hb], s["down_tube_d"]),
      tube.([hb, ht], s["head_tube_d"])
      | for(
          x <- [-half, half],
          do: [
            tube.([Vec.add(bb, {x * 0.5, 0.0, 0.0}), {x, ry, rz}], s["chainstay_d"]),
            tube.([Vec.add(st, {x * 0.3, 0.0, -0.02}), {x, ry, rz}], s["seatstay_d"])
          ]
        )
    ]

    shell =
      Shape.cylinder(0.021, 0.068, :paint,
        sides: 16,
        frame: Frame.new(Vec.add(bb, {-0.034, 0.0, 0.0}), {1, 0, 0}, {0, 0, 1})
      )

    saddle_at = Vec.add(st, Vec.scale(sd, s["seatpost"]))
    post = Shape.sweep([Vec.sub(st, {0.0, -0.01, 0.05}), saddle_at], 0.0136, :aluminum, sides: 10)
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
        [Vec.lerp(bb, hb, 0.3) |> Vec.add({0.0, 0.0, 0.025}), Vec.lerp(bb, hb, 0.6) |> Vec.add({0.0, 0.0, 0.025})],
        0.036,
        :black,
        sides: 12
      )

    Part.new(
      name,
      :frame,
      List.flatten(tubes) ++ [shell, post, saddle, cage],
      [
        port("origin", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}),
        steer_port(s),
        port("rear_axle", rear, {1, 0, 0}, {0, 0, 1}),
        port("rack", rear, {0, 0, 1}, {0, 1, 0}),
        port("bb", bb, {1, 0, 0}, {0, 0, 1}),
        port("stand", Vec.add(bb, {-0.05, -0.08, 0.0}), {1, 0, 0}, {0, 0, 1})
      ],
      sources: [
        "A diamond frame of steel tubes: top and seat tube #{mm(s["top_tube_d"])} mm, down tube #{mm(s["down_tube_d"])} mm; chainstay #{mm(s["chainstay"])} mm, stack #{mm(s["stack"])} mm, reach #{mm(s["reach"])} mm, head angle #{s["head_angle"]} degrees, seat angle #{s["seat_angle"]} degrees."
      ]
    )
  end

  defp mm(m), do: round(m * 1000)

  @doc """
  The fork, the stem and a drop bar of `bar_width`, with its fender: the
  ports `steer` and `axle` (the front wheel goes on it).
  """
  def fork(s, name) do
    %{front: {_, fy, fz}, head_top: ht, head_bottom: crown, axis: axis} = points(s)
    # The blades go down the steering axis, then bend forward to the axle.
    down = Vec.neg(axis)

    blades =
      for x <- [-0.05, 0.05] do
        line = [
          Vec.add(crown, {x * 0.6, 0.0, 0.0}),
          Vec.add(Vec.add(crown, Vec.scale(down, 0.18)), {x, 0.0, 0.0}),
          Vec.add(Vec.add(crown, Vec.scale(down, 0.31)), {x, s["rake"] / 2, 0.0}),
          {x, fy, fz}
        ]

        Shape.sweep(line, 0.011, :paint, sides: 8)
      end

    steerer = Shape.sweep([crown, Vec.add(ht, Vec.scale(axis, 0.04))], 0.0143, :black, sides: 10)
    bar_c = Vec.add(ht, Vec.add(Vec.scale(axis, 0.04), {0.0, 0.09, 0.0}))
    stem = Shape.sweep([Vec.add(ht, Vec.scale(axis, 0.035)), bar_c], 0.016, :black, sides: 8)
    w = s["bar_width"] / 2

    drops =
      for x <- [-w, w],
          do: [
            Vec.add(bar_c, {x, 0.0, 0.0}),
            Vec.add(bar_c, {x, 0.08, -0.03}),
            Vec.add(bar_c, {x, 0.06, -0.13}),
            Vec.add(bar_c, {x, -0.03, -0.14})
          ]

    bar = Shape.sweep(Enum.reverse(hd(drops)) ++ List.last(drops), 0.0119, :black, sides: 8)
    fender = Shape.loft(Shape.arc({fy, fz}, 0.37, -15, -105, 6, 0.03, 0.004), :black, smooth: 1, sides: 8)

    Part.new(
      name,
      :fork,
      blades ++ [steerer, stem, bar, fender],
      [steer_port(s), port("axle", {0.0, fy, fz}, {1, 0, 0}, {0, 0, 1})],
      sources: ["A steel fork with #{mm(s["rake"])} mm of rake; a drop bar of #{round(s["bar_width"] * 100)} cm."]
    )
  end

  @doc """
  The crankset: the chainring of `teeth` teeth (on a pitch of 12.7 mm),
  two arms of `arm`, and a pedal on each arm that turns on its own axle
  (the hinges `pedal_right` and `pedal_left`). Its port `axle` goes on
  the port `bb` of the frame.
  """
  def crankset(s, name) do
    arm = s["arm"]
    out = s["teeth"] * 0.0127 / (2 * :math.pi()) + 0.0022
    {o, i} = {Float.round(out, 3), Float.round(out - 0.017, 3)}
    ring = Shape.lathe([{i, -0.002}, {o, -0.002}, {o, 0.002}, {i, 0.002}], :steel, kind: :ring, sides: s["teeth"])

    spider =
      Shape.lathe([{0.012, -0.004}, {0.075, -0.004}, {0.075, 0.004}, {0.012, 0.004}], :aluminum, kind: :ring, sides: 10)

    spindle = Shape.cylinder(0.012, 0.15, :steel, sides: 12, frame: Frame.move({0.0, 0.0, -0.075}))

    arms =
      for x <- [-1, 1], do: Shape.sweep([{0.0, 0.0, x * 0.075}, {x * arm, 0.0, x * 0.08}], 0.011, :aluminum, sides: 8)

    # The crank is made around its own z axis (the axle, to the right).
    crank =
      Part.new(
        name,
        :crankset,
        [ring, spider, spindle | arms],
        [
          port("axle", {0, 0, 0}, {0, 0, 1}, {1, 0, 0}),
          port("pedal_right", {arm, 0.0, 0.085}, {0, 0, 1}, {1, 0, 0}),
          port("pedal_left", {-arm, 0.0, -0.085}, {0, 0, -1}, {1, 0, 0})
        ],
        params: %{"crank" => arm, "teeth" => s["teeth"]},
        sources: ["Crank arms of #{mm(arm)} mm; a chainring of #{s["teeth"]} teeth."]
      )

    pedal =
      Part.new(
        "pedal_flat",
        :pedal,
        [Shape.box({-0.05, -0.012, 0.015}, {0.05, 0.012, 0.085}, :black, round: 0.2, smooth: 1)],
        [port("axle", {0, 0, 0}, {0, 0, 1}, {1, 0, 0})]
      )

    Assembly.new(name, crank, root: "crank")
    |> Assembly.add("pedal_right", pedal, at: "pedal_right", port: "axle", kind: :hinge, role: :pedal)
    |> Assembly.add("pedal_left", pedal, at: "pedal_left", port: "axle", kind: :hinge, role: :pedal)
  end
end
