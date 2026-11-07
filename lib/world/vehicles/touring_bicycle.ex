defmodule World.Vehicles.TouringBicycle do
  @moduledoc """
  A touring bicycle (a frame of 54 cm, wheels of 700 x 35c): the
  "bicycle" of Phượt. The frame, the fork and the crankset come from the
  geometry sheet of a common touring frame (`World.Vehicles.Bicycle`);
  the parts have the sizes of their standards.

  The parts are made with the back of the bike at y = 0; the `place` of
  the assembly moves the bike to its center.
  """
  alias World.{Assembly, Frame, Part, Shape}
  alias World.Vehicles.{Bicycle, Wheels}

  @sources [
    "A touring frame of 54 cm: wheelbase 1030 mm, chainstay 430 mm, bottom bracket drop 70 mm, stack 580 mm, reach 380 mm, head angle 72 degrees, seat angle 73.5 degrees.",
    "Tires 37-622 (700 x 35c, ETRTO); a crank of 170 mm; a chainring of 44 teeth (182 mm).",
    "The shapes of the saddle and the bags: by eye."
  ]

  @doc "The bicycle."
  def model do
    s = Bicycle.touring()
    %{front: {_, fy, _}, r: r} = Bicycle.points(s)
    wheel = Wheels.spoked_wheel(s["tire"], spokes: 36)

    fork =
      Assembly.new("fork_touring", Bicycle.fork(s, "fork_touring"), root: "fork")
      |> Assembly.add("front_wheel", wheel, at: "axle", port: "hub", kind: :hinge, role: :wheel)

    Assembly.new("touring_bicycle", Bicycle.frame(s, "frame_touring_54"),
      root: "frame",
      kind: :vehicle,
      sources: @sources,
      place: Frame.move({0.0, -(fy + r) / 2, 0.0})
    )
    |> Assembly.add("rear_wheel", wheel, at: "rear_axle", port: "hub", kind: :hinge, role: :wheel)
    |> Assembly.add("steer", fork, at: "steer", port: "steer", kind: :hinge, role: :steer, limits: [-60, 60])
    |> Assembly.add("crank", Bicycle.crankset(s, "crankset_170"), at: "bb", port: "axle", kind: :hinge, role: :crank)
    |> Assembly.add("rack", rack(), at: "rack", port: "o")
    |> Assembly.add("kickstand", kickstand(), at: "stand", port: "pivot", kind: :hinge, role: :stand, limits: [0, 75])
  end

  defp o(name), do: Part.port(name, {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @doc "The shapes of the rear rack with two bags, from the rear axle (the port `rack` of the frame)."
  def rack_shapes do
    rails =
      for x <- [-0.07, 0.07],
          do:
            Shape.sweep([{x, -0.02, 0.02}, {x, 0.0, 0.06}, {x, 0.32, 0.06}, {x * 0.5, 0.38, 0.11}], 0.005, :black,
              sides: 6
            )

    bags =
      for x <- [-0.15, 0.15],
          do: Shape.box({x - 0.06, -0.08, -0.05}, {x + 0.06, 0.25, 0.05}, :fabric, round: 0.2, smooth: 2)

    rails ++ bags
  end

  defp rack, do: Part.new("rack_and_bags_touring", :rack, rack_shapes(), [o("o")])

  defp kickstand do
    leg = Shape.sweep([{0.0, 0.0, 0.0}, {-0.01, -0.27, 0.02}], 0.008, :aluminum, sides: 6)
    Part.new("kickstand", :stand, leg, [Part.port("pivot", {0, 0, 0}, {1, 0, 0}, {0, 0, 1})])
  end
end
