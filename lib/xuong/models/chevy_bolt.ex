defmodule Xuong.Models.ChevyBolt do
  @moduledoc """
  A Chevrolet Bolt EV (2022): the "car" of Phượt, and the car of the
  owner.

  The parts are made with the back of the car at y = 0; the `place` of the
  assembly moves the car to its center. The body is a loft with the
  arches of the wheels (`Xuong.Models.Body`); its shape follows photos of
  the car, by eye.
  """
  alias Xuong.{Assembly, Frame, Part, Shape}
  alias Xuong.Models.{Body, Vehicle}
  alias Xuong.Parts.Wheels

  @length 4.145
  @rear_y 0.78
  @front_y 0.78 + 2.601
  @axle_z 0.3234
  @track 1.50

  @sources [
    "Chevrolet Bolt EV (2022): length 4145 mm, width 1765 mm (with no mirrors), height 1611 mm, wheelbase 2601 mm.",
    "Tracks 1500 mm (front) and 1490 mm (rear); tires 215/50R17; wheels 5 x 105 mm.",
    "The shape of the body: by eye, from photos of the car."
  ]

  @doc "The car."
  def model do
    wheel = Wheels.car_wheel("215/50R17", pcd: 0.105, rim_material: :aluminum)
    hx = @track / 2

    Assembly.new("chevy_bolt_ev", body(),
      root: "body",
      kind: :vehicle,
      sources: @sources,
      place: Frame.move({0.0, -@length / 2, 0.0})
    )
    |> Assembly.add("lights", lights(), at: "origin", port: "origin")
    |> Vehicle.corner("front_right", wheel, {hx, @front_y, @axle_z}, steer: true, disc: 0.276)
    |> Vehicle.corner("front_left", wheel, {-hx, @front_y, @axle_z}, steer: true, disc: 0.276)
    |> Vehicle.corner("rear_right", wheel, {hx, @rear_y, @axle_z}, disc: 0.264)
    |> Vehicle.corner("rear_left", wheel, {-hx, @rear_y, @axle_z}, disc: 0.264)
  end

  defp origin, do: Part.port("origin", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  defp body do
    arches = [{@rear_y, @axle_z, 0.375}, {@front_y, @axle_z, 0.375}]

    lower =
      Body.loft(
        [
          {0.0, 0.42, 0.92, 0.78, 3.0},
          {0.08, 0.30, 1.00, 0.86, 5.0},
          {0.40, 0.27, 1.04, 0.88, 6.0},
          {1.50, 0.24, 1.04, 0.882, 6.0},
          {2.80, 0.26, 1.02, 0.88, 6.0},
          {3.30, 0.28, 0.96, 0.87, 6.0},
          {3.80, 0.30, 0.87, 0.85, 5.0},
          {4.05, 0.34, 0.79, 0.80, 4.0},
          {@length, 0.42, 0.70, 0.70, 3.0}
        ],
        arches,
        :paint
      )

    glass =
      Body.loft(
        [
          {0.10, 0.97, 1.06, 0.70, 3.0},
          {0.30, 0.99, 1.50, 0.75, 4.0},
          {0.60, 1.0, 1.59, 0.76, 4.0},
          {1.60, 1.01, 1.611, 0.77, 4.0},
          {2.20, 1.0, 1.56, 0.76, 4.0},
          {2.75, 0.99, 1.16, 0.73, 3.5},
          {2.95, 0.98, 1.02, 0.70, 3.0}
        ],
        [],
        :glass_dark,
        sides: 16
      )

    roof = Body.loft([{0.5, 1.585, 1.605, 0.64, 4.0}, {2.0, 1.59, 1.616, 0.66, 4.0}], [], :black, sides: 16, step: 0.4)
    bumper_f = Shape.box({-0.80, 4.0, 0.30}, {0.80, @length + 0.01, 0.52}, :trim, round: 0.25, smooth: 2)
    bumper_r = Shape.box({-0.80, -0.01, 0.32}, {0.80, 0.12, 0.55}, :trim, round: 0.25, smooth: 2)
    grille = Shape.box({-0.42, @length - 0.02, 0.56}, {0.42, @length + 0.012, 0.66}, :black, round: 0.3, smooth: 2)
    plate_f = Shape.box({-0.26, @length + 0.01, 0.36}, {0.26, @length + 0.02, 0.47}, :white)
    plate_r = Shape.box({-0.26, -0.025, 0.62}, {0.26, -0.015, 0.73}, :white)

    mirrors =
      for x <- [-1, 1] do
        [
          Shape.box({x * 0.93 - 0.06, 2.80, 1.02}, {x * 0.93 + 0.06, 2.90, 1.11}, :black, round: 0.3, smooth: 2),
          Shape.sweep([{x * 0.80, 2.86, 1.03}, {x * 0.88, 2.86, 1.05}], 0.012, :black, sides: 6)
        ]
      end

    Part.new(
      "body_bolt_ev",
      :body,
      [lower, glass, roof, bumper_f, bumper_r, grille, plate_f, plate_r] ++ List.flatten(mirrors),
      [origin() | corner_ports()],
      sources: ["By eye, from photos of the car."]
    )
  end

  defp corner_ports do
    for {name, x, y} <- [
          {"front_right", 1, @front_y},
          {"front_left", -1, @front_y},
          {"rear_right", 1, @rear_y},
          {"rear_left", -1, @rear_y}
        ],
        do: Vehicle.corner_port("corner_#{name}", {x * @track / 2, y, @axle_z})
  end

  defp lights do
    head = fn x ->
      Shape.loft(
        Shape.rows_y([{3.88, 0.80, 0.86, 0.15, 3}, {3.99, 0.78, 0.84, 0.13, 3}, {4.07, 0.76, 0.81, 0.09, 3}], x),
        :light_front, smooth: 1, sides: 12)
    end

    tail = fn x ->
      Shape.loft(
        Shape.rows_z([{0.90, 0.0, 0.14, 0.07, 3}, {1.04, 0.02, 0.14, 0.08, 3}, {1.14, 0.06, 0.14, 0.06, 3}], x),
        :light_back, smooth: 1, sides: 12)
    end

    Part.new("lights_bolt_ev", :light, [head.(0.6), head.(-0.6), tail.(0.74), tail.(-0.74)], [origin()],
      detail: :always
    )
  end
end
