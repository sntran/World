defmodule World.Vehicles.Corners do
  @moduledoc """
  Helpers for vehicles with four wheels: a corner of the vehicle (the
  knuckle, the brake disc and the wheel on its hub), and the ports that
  the body gives for each corner.

  A body has, for each corner, a port at the center of the hub, with its
  axis up (+z): the axis of the steering. The knuckle turns on it (a
  front corner) or stays fixed (a rear corner). The wheel turns on the
  knuckle, around the axle (+x on the right side, -x on the left side),
  so that the face of the wheel looks out.
  """
  alias World.{Assembly, Part, Shape}
  @doc "The port of a corner on the body: at the center of the hub, with its axis up."
  def corner_port(name, {x, y, z}), do: Part.port(name, {x, y, z}, {0, 0, 1}, {0, 1, 0})

  @doc """
  Add a corner to an assembly: `name` is `"front_left"`, `"rear_right"`,
  ... The options: `steer` (a front corner turns: `true`), `limits` of the
  steering (degrees), `disc` (the diameter of the brake disc, or nil).
  """
  def corner(asm, name, wheel, {x, y, z}, opts) do
    side = if x >= 0, do: 1.0, else: -1.0
    knuckle_name = "#{name}_knuckle"
    knuckle = knuckle(knuckle_name, {x, y, z}, side, Keyword.get(opts, :disc))

    joint =
      if Keyword.get(opts, :steer, false),
        do: [kind: :turns, role: :steer, limits: Keyword.get(opts, :limits, [-35, 35])],
        else: []

    asm
    |> Assembly.add(knuckle_name, knuckle, [at: "corner_#{name}", port: "steer"] ++ joint)
    |> Assembly.add("#{name}_wheel", wheel, to: knuckle_name, at: "axle", port: "hub", kind: :turns, role: :wheel)
  end

  # A knuckle: a small block inside the wheel, with its brake disc, and
  # the axle port that looks out of the vehicle.
  defp knuckle(name, {x, y, z}, side, disc) do
    block =
      Shape.box({x - side * 0.02 - 0.03, y - 0.06, z - 0.08}, {x - side * 0.02 + 0.03, y + 0.06, z + 0.08}, :metal)

    discs =
      if disc,
        do: [
          Shape.lathe(
            [{disc / 2 * 0.62, -0.012}, {disc / 2, -0.012}, {disc / 2, 0.012}, {disc / 2 * 0.62, 0.012}],
            :steel,
            kind: :ring,
            sides: 32,
            frame: World.Frame.new({x - side * 0.04, y, z}, {side, 0.0, 0.0}, {0, 0, 1})
          )
        ],
        else: []

    Part.new(
      name,
      :knuckle,
      [block | discs],
      [
        Part.port("steer", {x, y, z}, {0, 0, 1}, {0, 1, 0}),
        Part.port("axle", {x, y, z}, {side, 0.0, 0.0}, {0, 0, 1})
      ],
      inside: true
    )
  end
end
