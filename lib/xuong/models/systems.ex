defmodule Xuong.Models.Systems do
  @moduledoc """
  The systems of a house for DIY: the water heater, the AC (the outdoor
  unit and the mini split), the ceiling fan and the TV, at the sizes of
  `DIY.Catalog`. The fans turn (`spin`), the vane of the mini split and
  its front panel turn.
  """
  alias Xuong.{Assembly, Frame, Part, Shape}
  alias Xuong.Models.Kit
  import Kit, only: [inch: 1, same: 4, rbox: 4]

  @o {0, 0, 0}

  defp origin, do: same("o", @o, {0, 0, 1}, {0, 1, 0})

  # --- The water heater -----------------------------------------------------

  @doc """
  A gas water heater of 50 gallons: the Rheem PROG50-40N RH62, 21 1/2 in
  across and 61 1/2 in high. The pipes of the water, the flue, the gas
  valve, the relief valve and the drain valve.
  """
  def water_heater do
    {r, h} = {inch(21.5) / 2, inch(61.5)}
    top = h - 0.14

    jacket =
      Shape.lathe(
        [
          {0.0, 0.005},
          {r - 0.01, 0.005},
          {r, 0.03},
          {r, top - 0.03},
          {r - 0.03, top},
          {0.11, top + 0.01},
          {0.0, top + 0.01}
        ],
        :white, sides: 40)

    hood =
      Shape.lathe(
        [{0.0, top + 0.03}, {0.07, top + 0.03}, {0.07, top + 0.06}, {0.05, top + 0.09}, {0.05, h}, {0.0, h}],
        :steel, sides: 20)

    pan =
      Shape.lathe(
        [{0.0, 0.0}, {r + 0.03, 0.0}, {r + 0.03, 0.04}, {r + 0.02, 0.04}, {r + 0.02, 0.005}, {0.0, 0.005}],
        :plastic, sides: 40)

    pipes =
      for {x, mat} <- [{-0.13, :copper}, {0.13, :copper}] do
        [
          Kit.rod({x, -0.05, top - 0.01}, {0, 0, 1}, 0.011, 0.36, mat),
          Kit.rod({x, -0.05, top - 0.01}, {0, 0, 1}, 0.016, 0.05, :metal)
        ]
      end

    # The gas valve at the front, near the bottom, and its pipe.
    valve = [
      rbox({-0.06, r - 0.01, 0.3}, {0.06, r + 0.07, 0.42}, :black, 0.1),
      Kit.rod({0.06, r + 0.03, 0.36}, {1, 0, 0}, 0.01, 0.2, :metal),
      Kit.rod({0.26, r + 0.03, 0.36}, {0, 0, 1}, 0.01, h - 0.36, :metal),
      Shape.box({-0.08, r - 0.012, 0.08}, {0.08, r + 0.002, 0.22}, :steel)
    ]

    relief = [
      Kit.rod({r - 0.01, 0.0, top - 0.2}, {1, 0, 0}, 0.014, 0.06, :copper),
      Shape.box({r + 0.04, -0.02, top - 0.23}, {r + 0.08, 0.02, top - 0.16}, :copper),
      Shape.sweep([{r + 0.06, 0.0, top - 0.23}, {r + 0.06, 0.0, 0.15}], 0.011, :copper)
    ]

    drain = Kit.rod({0.0, r - 0.01, 0.15}, {0, 1, 0}, 0.012, 0.06, :plastic)
    label = Shape.box({-0.12, r - 0.005, 0.6}, {0.12, r + 0.002, 0.95}, :plastic)

    tank =
      Part.new(
        "water_heater_rheem_prog50",
        :tank,
        [jacket, hood, pan, drain, label | List.flatten(pipes)] ++ valve ++ relief,
        [origin()], params: %{"gallons" => 50, "fuel" => "gas"})

    knob_at = {0.0, r + 0.07, 0.37}

    Assembly.new("water_heater_rheem_prog50", tank,
      root: "tank",
      kind: :appliance,
      sources: [
        "Rheem PROG50-40N RH62, 50 gallons: 21 1/2 in across, 61 1/2 in high (distributor listing, the size of DIY)."
      ]
    )
    |> Assembly.add("gas_knob", Kit.knob("gas_knob", knob_at, {0, 1, 0}, {0, 0, 1}, 0.025, 0.02, :dark),
      at: Kit.same("gas_knob", knob_at, {0, 1, 0}, {0, 0, 1}),
      port: "gas_knob",
      kind: :turns,
      role: :knob,
      limits: [0, 90]
    )
  end

  # --- The outdoor unit of a central AC ---------------------------------------

  @doc """
  The outdoor unit of a central AC of 3 tons: the Goodman GSX140361, 29
  by 29 by 32 1/2 in. A grille on the four sides, the coil behind it, the
  compressor, and the fan at the top.
  """
  def ac do
    {s, h} = {inch(29), inch(32.5)}
    a = s / 2
    zt = h - 0.06

    base = [Shape.box({-a, -a, 0.0}, {a, a, 0.05}, :dark), rbox({-a, -a, zt}, {a, a, h - 0.01}, :dark, 0.04)]

    posts =
      for {x, y} <- [{-a, -a}, {a - 0.04, -a}, {-a, a - 0.04}, {a - 0.04, a - 0.04}],
          do: Shape.box({x, y, 0.05}, {x + 0.04, y + 0.04, zt}, :dark)

    coil = Kit.cavity({-a + 0.03, -a + 0.03, 0.05}, {a - 0.03, a - 0.03, zt}, 0.025, :metal, :top) |> List.delete_at(3)

    grille =
      for {from, to, step} <- [
            {{-a + 0.04, a - 0.005, 0.08}, {-a + 0.04, a - 0.005, zt - 0.02}, {0.025, 0.0, 0.0}},
            {{-a + 0.04, -a + 0.005, 0.08}, {-a + 0.04, -a + 0.005, zt - 0.02}, {0.025, 0.0, 0.0}},
            {{a - 0.005, -a + 0.04, 0.08}, {a - 0.005, -a + 0.04, zt - 0.02}, {0.0, 0.025, 0.0}},
            {{-a + 0.005, -a + 0.04, 0.08}, {-a + 0.005, -a + 0.04, zt - 0.02}, {0.0, 0.025, 0.0}}
          ] do
        Kit.bars(from, to, step, 26, 0.0025, :dark)
      end

    compressor =
      Shape.lathe([{0.0, 0.05}, {0.12, 0.05}, {0.13, 0.15}, {0.13, 0.4}, {0.1, 0.46}, {0.0, 0.46}], :black, sides: 20)

    # The panel of the service valves and the wires, at the right of the front.
    panel = [
      Shape.box({a - 0.04, a - 0.2, 0.15}, {a + 0.005, a - 0.04, 0.55}, :dark),
      Kit.rod({a, a - 0.12, 0.2}, {1, 0, 0}, 0.012, 0.03, :copper),
      Kit.rod({a, a - 0.08, 0.25}, {1, 0, 0}, 0.008, 0.03, :copper)
    ]

    fan_grille =
      [Shape.lathe([{0.0, h - 0.012}, {0.06, h - 0.012}, {0.06, h + 0.01}, {0.0, h + 0.01}], :dark, sides: 16)] ++
        for k <- 1..6 do
          rr = 0.045 * k

          pts =
            for i <- 0..24,
                do: {rr * :math.cos(2 * :math.pi() * i / 24), rr * :math.sin(2 * :math.pi() * i / 24), h - 0.004}

          Shape.sweep(pts, 0.002, :dark, sides: 4)
        end

    blades =
      for k <- 0..2 do
        Shape.box({0.03, -0.04, -0.004}, {0.27, 0.04, 0.004}, :black,
          frame:
            Frame.new(
              {0.0, 0.0, zt - 0.05},
              {0, 0, 1},
              {-:math.sin(2 * :math.pi() * k / 3), :math.cos(2 * :math.pi() * k / 3), 0.0}
            )
            |> Frame.compose(Frame.turn({1, 0, 0}, 20))
        )
      end

    unit =
      Part.new(
        "ac_goodman_gsx140361",
        :unit,
        base ++ posts ++ coil ++ List.flatten(grille) ++ [compressor | panel] ++ fan_grille,
        [origin()], params: %{"tons" => 3})

    fan =
      Part.new(
        "ac_fan",
        :fan,
        [Kit.rod({0.0, 0.0, zt - 0.06}, {0, 0, 1}, 0.04, 0.03, :black) | blades],
        [same("axle", {0.0, 0.0, zt - 0.05}, {0, 0, 1}, {0, 1, 0})], inside: true)

    Assembly.new("ac_goodman_gsx140361", unit,
      root: "unit",
      kind: :appliance,
      sources: ["Goodman GSX140361, 3 tons: 29 by 29 by 32 1/2 in (distributor listing, the size of DIY)."]
    )
    |> Assembly.add("fan", fan,
      at: Kit.same("axle", {0.0, 0.0, zt - 0.05}, {0, 0, 1}, {0, 1, 0}),
      port: "axle",
      kind: :turns,
      role: :spin
    )
  end

  # --- The mini split ---------------------------------------------------------

  @doc """
  The indoor unit of a mini split: the Mitsubishi MSZ-GL12NA, 31 7/16 by
  9 1/8 by 11 5/8 in. The front panel opens up; the vane turns.
  """
  def mini_split do
    {w, d, h} = {inch(31.4375), inch(9.125), inch(11.625)}
    {x0, x1, y0} = {-w / 2, w / 2, -d / 2}
    yf = d / 2

    rows = [{x0, 0.0}, {x0 + 0.01, 1.0}, {x1 - 0.01, 1.0}, {x1, 0.0}]

    body =
      Shape.loft(
        for {x, k} <- rows do
          {{x, (y0 + yf - 0.02) / 2, h / 2}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}, (yf - 0.02 - y0) / 2 * (0.9 + 0.1 * k),
           h / 2 * (0.94 + 0.06 * k), 5}
        end,
        :white,
        sides: 24
      )

    outlet = Shape.box({x0 + 0.04, yf - 0.1, 0.0}, {x1 - 0.04, yf - 0.02, 0.012}, :dark)
    # The pipes go out of the back, into the wall.
    pipes = [
      Kit.rod({x0 + 0.08, y0 + 0.01, 0.04}, {0, -1, 0}, 0.009, 0.04, :copper),
      Kit.rod({x0 + 0.11, y0 + 0.01, 0.04}, {0, -1, 0}, 0.012, 0.04, :copper)
    ]

    leds =
      for i <- 0..2,
          do: Shape.box({x1 - 0.12 + i * 0.02, yf + 0.004, 0.035}, {x1 - 0.11 + i * 0.02, yf + 0.008, 0.04}, :screen)

    panel =
      Part.new(
        "mini_split_panel",
        :lid,
        [rbox({x0 + 0.015, yf - 0.02, 0.05}, {x1 - 0.015, yf + 0.004, h - 0.01}, :white, 0.03)] ++ leds,
        [same("hinge", {0.0, yf - 0.01, h - 0.01}, {1, 0, 0}, {0, 0, -1})], detail: :always)

    vane =
      Part.new(
        "mini_split_vane",
        :vane,
        [
          Shape.box({x0 + 0.05, -0.04, -0.003}, {x1 - 0.05, 0.0, 0.003}, :white,
            frame: Frame.new({0.0, yf - 0.02, 0.025}, {0, 0, 1}, {0, 1, 0})
          )
        ],
        [same("vane", {0.0, yf - 0.02, 0.025}, {1, 0, 0}, {0, 1, 0})], detail: :always)

    Assembly.new(
      "mini_split_mitsubishi_msz_gl12na",
      Part.new("mini_split_body", :unit, [body, outlet | pipes], [origin()]),
      root: "body",
      kind: :appliance,
      sources: ["Mitsubishi MSZ-GL12NA: 31 7/16 by 9 1/8 by 11 5/8 in (Mitsubishi spec sheet, the size of DIY)."]
    )
    |> Assembly.add("panel", panel,
      at: Kit.same("hinge", {0.0, yf - 0.01, h - 0.01}, {1, 0, 0}, {0, 0, -1}),
      port: "hinge",
      kind: :turns,
      role: :lid,
      limits: [0, 60]
    )
    |> Assembly.add("vane", vane,
      at: Kit.same("vane", {0.0, yf - 0.02, 0.025}, {1, 0, 0}, {0, 1, 0}),
      port: "vane",
      kind: :turns,
      role: :vane,
      limits: [0, 80]
    )
  end

  # --- The ceiling fan ---------------------------------------------------------

  @doc """
  A ceiling fan of 52 in (a common size): the canopy at the top (z =
  0.305 m), the down rod, the motor, five blades and a light. The model
  stands with its lowest point on z = 0: an app hangs it from a ceiling.
  """
  def ceiling_fan do
    h = inch(12)
    span = inch(52) / 2
    zb = 0.13

    fixed = [
      Shape.lathe([{0.0, h - 0.06}, {0.04, h - 0.06}, {0.08, h - 0.02}, {0.08, h}, {0.0, h}], :metal, sides: 24),
      Kit.rod({0.0, 0.0, zb + 0.08}, {0, 0, 1}, 0.012, h - zb - 0.12, :metal),
      Shape.lathe([{0.0, 0.03}, {0.06, 0.04}, {0.075, 0.07}, {0.06, 0.1}, {0.0, 0.1}], :metal, sides: 24),
      Shape.sphere(0.07, :glass, sides: 20, rings: 10, frame: Frame.move({0.0, 0.0, 0.07}))
    ]

    motor =
      Shape.lathe(
        [{0.0, zb - 0.02}, {0.1, zb - 0.02}, {0.13, zb + 0.02}, {0.11, zb + 0.07}, {0.04, zb + 0.09}, {0.0, zb + 0.09}],
        :metal, sides: 32)

    blades =
      for k <- 0..4 do
        a = 2 * :math.pi() * k / 5
        f = Frame.new({0.0, 0.0, zb + 0.02}, {0, 0, 1}, {-:math.sin(a), :math.cos(a), 0.0})
        iron = Shape.box({0.09, -0.015, -0.004}, {0.2, 0.015, 0.004}, :metal, frame: f)

        blade =
          Shape.box({0.17, -0.07, -0.006}, {span, 0.07, 0.0}, :wood,
            frame: Frame.compose(f, Frame.turn({1, 0, 0}, 12, {0.0, 0.0, 0.0}))
          )

        [iron, blade]
      end

    rotor =
      Part.new("fan_rotor_52in", :rotor, [motor | List.flatten(blades)], [
        same("axle", {0.0, 0.0, zb}, {0, 0, 1}, {0, 1, 0})
      ])

    Assembly.new("ceiling_fan_52in", Part.new("fan_mount", :mount, fixed, [origin()]),
      root: "mount",
      kind: :appliance,
      sources: ["A ceiling fan of 52 in, a common size (the size of DIY: 52 by 52 by 12 in, no source)."]
    )
    |> Assembly.add("rotor", rotor,
      at: Kit.same("axle", {0.0, 0.0, zb}, {0, 0, 1}, {0, 1, 0}),
      port: "axle",
      kind: :turns,
      role: :spin
    )
  end

  # --- The TV ------------------------------------------------------------------

  @doc "A TV of 50 in on its stand: the Samsung UN50CU7000, 44 by 9.9 by 28.3 in."
  def tv do
    {w, d, h} = {inch(44), inch(9.9), inch(28.3)}
    {x0, x1} = {-w / 2, w / 2}
    z0 = 0.075

    panel = [
      rbox({x0, -0.03, z0}, {x1, 0.0, h}, :black, 0.01),
      Shape.box({x0 + 0.008, 0.0, z0 + 0.012}, {x1 - 0.008, 0.002, h - 0.008}, :screen),
      rbox({x0 + 0.1, -0.06, z0 + 0.05}, {x1 - 0.1, -0.03, h - 0.08}, :black, 0.05)
    ]

    feet =
      for x <- [x0 + 0.12, x1 - 0.12] do
        [
          Shape.sweep([{x, -d / 2, 0.006}, {x, -0.02, z0 + 0.04}, {x, d / 2, 0.006}], 0.008, :black, sides: 8),
          Shape.box({x - 0.02, -0.03, z0 - 0.01}, {x + 0.02, -0.005, z0 + 0.06}, :black)
        ]
      end

    Assembly.new(
      "tv_samsung_un50cu7000",
      Part.new("tv_50in", :tv, panel ++ List.flatten(feet), [origin()], params: %{"inches" => 50}),
      root: "tv",
      kind: :appliance,
      sources: ["Samsung UN50CU7000, 50 in, on its stand: 44 by 9.9 by 28.3 in (P.C. Richard, the size of DIY)."]
    )
  end
end
