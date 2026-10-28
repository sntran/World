defmodule Xuong.Models.Van.BodyShop do
  @moduledoc """
  The first station of the line of a van (`Xuong.Models.Van`): the body
  in white.

  At the near level the body is of sheets on the hull: the nose, the
  fenders and the floor of the engine bay, the firewall, and from there
  to the back the sheets of the sides, the roof and the floor, 3 cm
  thick, with the openings (`Xuong.Models.Van.Openings`) cut: the
  windshield, the front doors, the sliding door, the rear doors, the
  windows of the body, and the arches of the wheels. Inside are the
  floors, the wells of the wheels and the pillar behind the front door
  at the right side. At the mid and far levels the body is closed.
  """
  alias Xuong.Detail
  alias Xuong.Models.{Hull, Vehicle}
  alias Xuong.Models.Van.{Kit, Openings}
  alias Xuong.Parts.Wheels

  @station "body_shop"

  # The engine bay: from the back of the grille (d = 0.2) to the firewall
  # (d = 0.62), between the fenders (x from -0.6 to 0.6), over its floor
  # (z = 0.5).
  @bay {0.2, 0.62, 0.6, 0.5}

  # The cab floor (z) from the firewall to the back of the front doors:
  # by eye from the photos of the cab with the doors open.
  @cab_floor 0.6

  @doc "The body of a van, with its ports: `hood`, and a corner at each wheel."
  def body(van) do
    %{h: h, m: m} = van
    {d0, d1} = Hull.span(h)
    {b0, b1, bx, bz} = @bay
    side = fn x -> fn _ -> [x] end end

    nose = [
      Hull.skin(h, d0, b0, :paint),
      Hull.skin(h, b0, b1, :paint, clip: side.({:x_min, bx})),
      Hull.skin(h, b0, b1, :paint, clip: side.({:x_max, -bx})),
      Hull.skin(h, b0, b1, :paint, clip: side.({:z_max, bz}))
    ]

    cab_and_cargo =
      if Detail.level() == :near do
        firewall = Hull.skin(h, b1, b1 + 0.02, :paint)

        sheets =
          for s <- [1, -1],
              do:
                Hull.shell(h, b1, d1, :paint,
                  side: s,
                  step: 0.5,
                  holes: Openings.body_holes(van, s),
                  edges: Openings.edges(van)
                )

        [firewall | List.flatten(sheets)]
      else
        [Hull.skin(h, b1, d1, :paint)]
      end

    {f, wb, [tf, tr]} = {m["front"], m["wheelbase"], m["track"]}
    rz = Wheels.tire_radius(m["tire"])

    corners =
      for {name, x, d} <- [
            {"front_right", tf / 2, f},
            {"front_left", -tf / 2, f},
            {"rear_right", tr / 2, f + wb},
            {"rear_left", -tr / 2, f + wb}
          ],
          do: Vehicle.corner_port("corner_#{name}", {x, h.length - d, rz})

    Kit.part(@station, "body_" <> m["make"], :body, nose ++ cab_and_cargo, [Kit.origin() | corners],
      sources: van.make["openings"]["sources"]
    )
  end

  @doc """
  The parts inside the body, only at the near level: the floor of the
  cab and of the cargo area, the wells of the wheels, and the pillar
  behind the front door at the right side.
  """
  def inside(van) do
    %{h: h, m: m, l: l} = van
    {_, f1} = Openings.front_door_span(van)
    {s0, _} = Openings.sliding_door_span(van)
    hw = Hull.half_width(h, (f1 + s0) / 2)
    floor = m["floor"]

    floors = [
      Hull.skin(h, 0.62, f1 + 0.05, :dark,
        clip: fn _ -> [{:z_min, @cab_floor - 0.02}, {:z_max, @cab_floor}] end,
        sides: 8
      ),
      Hull.skin(h, f1, l - 0.01, :plywood,
        sides: 8,
        clip: fn d ->
          # Between the wells of the wheels, the floor is narrower.
          side =
            if Hull.arch(h, d),
              do: [{:x_max, Hull.half_width(h, d) - 0.3}, {:x_min, 0.3 - Hull.half_width(h, d)}],
              else: []

          [{:z_min, floor - 0.02}, {:z_max, floor} | side]
        end
      )
    ]

    wells =
      for {ad, az, r} <- h.arches, s <- [1, -1] do
        x0 = Hull.half_width(h, ad) - 0.3
        x1 = Hull.half_width(h, ad) - 0.03

        arc = fn radius ->
          for i <- 0..12, a = :math.pi() * i / 12, do: {l - ad + radius * :math.cos(a), az + radius * :math.sin(a)}
        end

        ring = fn x -> for {y, z} <- arc.(r + 0.03) ++ Enum.reverse(arc.(r)), do: {s * x, y, z} end
        Xuong.Shape.rings([ring.(x0), ring.(x1)], :black)
      end

    pillar =
      Xuong.Shape.box({hw - 0.14, l - (s0 + 0.06), 0.42}, {hw - 0.06, l - (f1 - 0.04), 2.36}, :paint)

    Kit.part(@station, "inside_" <> m["make"], :body, [pillar | floors ++ wells], [Kit.origin()],
      detail: :near,
      sources: [
        "The floor of the cargo area at #{floor} m (the model); the floor of the cab, the wells of the wheels and the pillar behind the front door: by eye from the photos of the van with the doors open."
      ]
    )
  end
end
