defmodule World.People.Props do
  @moduledoc """
  The props of a person: things that a person holds or wears, on a port
  on a bone (`World.Figure.hold/4`). Each prop is a part with the port
  of the person that it goes on (`on/1`): `grip` for a hand (the port
  `grip_l` or `grip_r`), `crown` for the head.

  The port `grip` of a prop is on the line of its handle, its axis to
  the side of the thumb, and its `up` away from the palm, as the port
  `grip_l` and `grip_r` of a person.
  """
  alias World.{Detail, Frame, Part, Shape}

  @hand ~w(bottle fan)
  @head ~w(non_la)
  @props @hand ++ @head

  @doc "The names of the props."
  def names, do: Enum.sort(@props)

  @doc "The names of the props for a hand."
  def hand, do: @hand

  @doc "The names of the props for the head."
  def head, do: @head

  @doc "The port of a person that a prop goes on (without the side for a hand)."
  def on(name) when name in @head, do: "crown"
  def on(name) when name in @hand, do: "grip"

  @doc "A prop by its name."
  def prop("fan") do
    # Open to 160 degrees around the axis of the handle; the pivot is at
    # the bottom of the closed hand, under the grip.
    pivot = {0.0, 0.0, -0.045}
    half = 80
    n = Detail.sides(16)
    arc = fn r -> for k <- 0..n, do: sector_point(r, -half + 2 * half * k / n) end
    leaf = arc.(0.33) ++ Enum.reverse(arc.(0.13))
    face = fn loop, t, material -> Shape.prism(loop, t, material, frame: face_frame(pivot, t)) end

    guards =
      for a <- [-half, half] do
        Shape.box({-0.006, -0.003, 0.0}, {0.006, 0.003, 0.335}, :wood,
          frame: Frame.compose(Frame.move(pivot), Frame.turn({0.0, 1.0, 0.0}, -a))
        )
      end

    Part.new(
      "tai_chi_fan",
      :prop,
      [
        face.(leaf, 0.0015, :red),
        face.([{0.0, 0.0} | Enum.reverse(arc.(0.135))], 0.004, :wood),
        Shape.cylinder(0.006, 0.012, :chrome, frame: Frame.new({0.0, -0.006, -0.045}, {0, 1, 0}, {0, 0, 1}))
        | guards
      ],
      [Part.port("grip", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})],
      sources: [
        "A tai chi fan (kung fu fan): ribs of bamboo of about 33 cm, a leaf of silk; it opens to 160 to 180 degrees. A common size of the fans for tai chi; the sizes are a guess from the photos of sellers."
      ]
    )
  end

  def prop("bottle") do
    # A bottle of water of 500 ml (65 mm by 205 mm). The hand holds its
    # side: the axis of the bottle is 1.5 cm less than its radius away
    # from the grip.
    r = 0.0325
    lift = 0.09

    Part.new(
      "water_bottle_500ml",
      :prop,
      [
        Shape.lathe([{0.0, 0.0}, {r, 0.0}, {r, 0.15}, {0.016, 0.18}, {0.0, 0.18}], :glass,
          frame: Frame.move({0.0, 0.0, -lift})
        ),
        Shape.lathe([{0.0, 0.18}, {0.015, 0.18}, {0.015, 0.205}, {0.0, 0.205}], :blue,
          frame: Frame.move({0.0, 0.0, -lift})
        )
      ],
      [Part.port("grip", {0.0, -(r - 0.015), 0.0}, {0, 0, 1}, {0, 1, 0})],
      sources: ["A bottle of water of 500 ml: about 65 mm across and 205 mm high (common sizes)."]
    )
  end

  def prop("non_la") do
    # A nón lá: a cone of palm leaves on a frame of bamboo rings. The ring
    # inside sits on the head: the top of the head is 11 cm over the rim.
    {r, h, t} = {0.205, 0.19, 0.003}
    loop = [{r, 0.0}, {0.004, h}, {0.004, h - t}, {r - t, 0.0}]

    Part.new(
      "non_la",
      :prop,
      [Shape.lathe(loop, :plywood, kind: :ring, sides: 32, frame: Frame.move({0.0, 0.0, -0.11}))],
      [Part.port("crown", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})],
      sources: [
        "A nón lá of Việt Nam: a cone of palm leaves, about 41 cm across and 19 cm high (a common size of the nón lá of Huế)."
      ]
    )
  end

  def prop(name), do: raise(ArgumentError, "unknown prop #{inspect(name)}: #{Enum.join(@props, ", ")}")

  # A point of the fan at a radius and an angle from the handle, in the
  # plane of the prism (x across, y along the handle).
  defp sector_point(r, deg) do
    a = deg * :math.pi() / 180
    {r * :math.sin(a), r * :math.cos(a)}
  end

  # The face of the fan is in the plane of the handle and the fingers (x
  # and z of the port), thin across y: the prism goes along y.
  defp face_frame({px, py, pz}, t), do: Frame.new({px, py - t / 2, pz}, {0, 1, 0}, {0, 0, 1})
end
