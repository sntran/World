defmodule Xuong.Models.VanGear do
  @moduledoc """
  The gear of a camper van for DIY: the electrical parts (a LiFePO4
  battery, the Victron MultiPlus-II, SmartShunt, Lynx Distributor and
  Orion XS, a battery switch), a 12 V fridge, a roof fan, a diesel heater,
  a water tank, and a solar panel. The terminals have their real bolts,
  so the list of the parts gives them.

  Each part stands on z = 0, centered, its front to +y. The roof fan and
  the heater go through a surface (the roof, the floor): their z = 0 is
  that surface.
  """
  alias Xuong.{Assembly, Frame, Part, Shape}
  alias Xuong.Models.Kit
  alias Xuong.Parts.Fasteners
  import Kit, only: [inch: 1, mm: 1, same: 4, rbox: 4]

  @o {0, 0, 0}
  defp origin, do: same("o", @o, {0, 0, 1}, {0, 1, 0})

  @doc "Each model as `{name, fun}`."
  def all do
    [
      {"battery_battle_born_bb10012", &__MODULE__.battery/0},
      {"victron_multiplus_ii_12_3000", &__MODULE__.multiplus/0},
      {"victron_smartshunt_500a", &__MODULE__.smartshunt/0},
      {"victron_lynx_distributor", &__MODULE__.lynx/0},
      {"victron_orion_xs_12_12_50", &__MODULE__.orion_xs/0},
      {"battery_switch_blue_sea_6006", &__MODULE__.battery_switch/0},
      {"fridge_dometic_cfx3_45", &__MODULE__.cfx3/0},
      {"roof_fan_maxxair_7500k", &__MODULE__.maxxfan/0},
      {"heater_webasto_air_top_2000_stc", &__MODULE__.air_top/0},
      {"water_tank_20gal", &__MODULE__.water_tank/0},
      {"solar_panel_rich_solar_mega_400", &__MODULE__.solar_panel/0}
    ]
  end

  # Bolts on the terminals: a bolt with its head up at each point.
  defp add_bolts(asm, prefix, points, thread, length) do
    points
    |> Enum.with_index(1)
    |> Enum.reduce(asm, fn {p, i}, asm ->
      Assembly.add(asm, "#{prefix}_#{i}", Fasteners.bolt(thread, length),
        at: Part.port("#{prefix}_#{i}", p, {0, 0, -1}, {0, 1, 0}),
        port: "head"
      )
    end)
  end

  # --- The battery ----------------------------------------------------------------

  @doc "A LiFePO4 battery of 12 V and 100 Ah: the Battle Born BB10012, 12.75 by 6.87 by 9 in."
  def battery do
    {w, d, h} = {inch(12.75), inch(6.87), inch(9)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -d / 2, d / 2}
    zt = h - 0.012

    case_ = [
      rbox({x0, y0, 0.0}, {x1, y1, zt}, :black, 0.03),
      rbox({x0 - 0.003, y0 - 0.003, zt - 0.02}, {x1 + 0.003, y1 + 0.003, h}, :dark, 0.08),
      Shape.box({x0 + 0.06, y1, 0.06}, {x1 - 0.06, y1 + 0.002, 0.16}, :white)
    ]

    terminals =
      for {x, mat} <- [{x0 + 0.045, :red}, {x1 - 0.045, :black}] do
        [
          Kit.rod({x, 0.0, h}, {0, 0, 1}, 0.012, 0.012, :copper),
          Shape.lathe([{0.0, h - 0.002}, {0.022, h - 0.002}, {0.022, h + 0.004}, {0.0, h + 0.004}], mat,
            sides: 16,
            frame: Frame.move({x, 0.0, 0.0})
          )
        ]
      end

    straps =
      for x <- [x0 - 0.004, x1 + 0.004],
          do:
            Shape.sweep(
              [{x, -0.04, zt - 0.03}, {x, -0.04, zt + 0.03}, {x, 0.04, zt + 0.03}, {x, 0.04, zt - 0.03}],
              0.005,
              :black, sides: 6)

    Assembly.new(
      "battery_battle_born_bb10012",
      Part.new("battery_bb10012", :battery, case_ ++ List.flatten(terminals) ++ straps, [origin()],
        params: %{"volts" => 12, "amp_hours" => 100, "chemistry" => "LiFePO4"}
      ),
      root: "battery",
      kind: :electrical,
      sources: [
        "Battle Born BB10012: 12.75 by 6.87 by 9 in, 31 lb (Battle Born cut sheet). Studs of 5/16-18 in (an M8 here)."
      ]
    )
    |> add_bolts("terminal_bolt", [{x0 + 0.045, 0.0, h + 0.016}, {x1 - 0.045, 0.0, h + 0.016}], "M8", 0.025)
  end

  # --- Victron -----------------------------------------------------------------------

  @doc """
  The Victron MultiPlus-II 12/3000/120-32, an inverter and charger on a
  wall: 546 by 275 by 147 mm (h by w by d), 19 kg.
  """
  def multiplus do
    {h, w, d} = {mm(546), mm(275), mm(147)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -d / 2, d / 2}
    zc = 0.13

    body =
      [
        rbox({x0, y0, zc}, {x1, y1, h}, :blue, 0.04),
        Shape.box({x0 + 0.03, y1, h - 0.16}, {x1 - 0.03, y1 + 0.003, h - 0.07}, :white),
        Shape.box({x0 + 0.08, y1 + 0.003, h - 0.14}, {x0 + 0.12, y1 + 0.005, h - 0.12}, :screen),
        Shape.box({x0 - 0.01, y0, 0.0}, {x1 + 0.01, y0 + 0.012, h + 0.02}, :dark)
      ] ++
        Kit.bars(
          {x0 - 0.001, y0 + 0.03, zc + 0.08},
          {x0 - 0.001, y1 - 0.03, zc + 0.08},
          {0.0, 0.0, 0.025},
          10,
          0.003,
          :dark
        ) ++
        Kit.bars(
          {x1 + 0.001, y0 + 0.03, zc + 0.08},
          {x1 + 0.001, y1 - 0.03, zc + 0.08},
          {0.0, 0.0, 0.025},
          10,
          0.003,
          :dark
        )

    glands =
      for x <- [x0 + 0.04, x0 + 0.09, x1 - 0.09, x1 - 0.04], do: Kit.rod({x, 0.0, 0.0}, {0, 0, 1}, 0.012, 0.02, :black)

    cover =
      Part.new(
        "multiplus_cover",
        :cover,
        [rbox({x0, y0 + 0.012, 0.02}, {x1, y1, zc}, :dark, 0.06)],
        [same("o", @o, {0, 0, 1}, {0, 1, 0})], sources: ["The cover of the connections, with 4 screws."])

    asm =
      Assembly.new(
        "victron_multiplus_ii_12_3000",
        Part.new("multiplus_ii_12_3000_120_32", :inverter, body ++ glands, [origin()],
          params: %{"volts" => 12, "va" => 3000, "charge_a" => 120}
        ),
        root: "inverter",
        kind: :electrical,
        sources: [
          "Victron MultiPlus-II 12/3000/120-32: 546 by 275 by 147 mm, 19 kg (Schrack and Manel Service listings; the depth is 141 or 147 mm)."
        ]
      )
      |> Assembly.add("cover", cover, at: Kit.same("o", @o, {0, 0, 1}, {0, 1, 0}), port: "o")

    Enum.reduce(
      Enum.with_index([{x0 + 0.02, zc - 0.02}, {x1 - 0.02, zc - 0.02}, {x0 + 0.02, 0.04}, {x1 - 0.02, 0.04}], 1),
      asm,
      fn {{x, z}, i}, asm ->
        Assembly.add(asm, "cover_screw_#{i}", Fasteners.cap_screw("M4", 0.012),
          at: Part.port("screw_#{i}", {x, y1, z}, {0, -1, 0}, {0, 0, 1}),
          port: "head"
        )
      end
    )
  end

  @doc "The Victron SmartShunt 500 A: 120 by 54 by 46 mm, a battery monitor on the negative cable."
  def smartshunt do
    {w, d, h} = {mm(120), mm(54), mm(46)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -d / 2, d / 2}

    # The copper bar on a base of plastic of 12 mm: the bolts go into it.
    shapes = [
      Shape.box({x0, y0 + 0.006, 0.0}, {x1, y1 - 0.006, 0.012}, :black),
      Shape.box({x0, y0 + 0.012, 0.012}, {x1, y1 - 0.012, 0.02}, :copper),
      rbox({x0 + 0.025, y0, 0.0}, {x1 - 0.025, y1, h}, :blue, 0.1),
      Shape.box({x0 + 0.03, y1, h - 0.03}, {x0 + 0.045, y1 + 0.002, h - 0.02}, :screen)
    ]

    Assembly.new(
      "victron_smartshunt_500a",
      Part.new("smartshunt_500a", :shunt, shapes, [origin()], params: %{"amps" => 500}),
      root: "shunt",
      kind: :electrical,
      sources: [
        "Victron SmartShunt 500A/50mV: 46 by 120 by 54 mm (h by w by d; Victron and retailer listings). Studs of M10."
      ]
    )
    |> add_bolts("shunt_bolt", [{x0 + 0.012, 0.0, 0.02}, {x1 - 0.012, 0.0, 0.02}], "M10", 0.02)
  end

  @doc "The Victron Lynx Distributor: a DC busbar with 4 fuses, 290 by 170 by 80 mm (h by l by w)."
  def lynx do
    {w, h, d} = {mm(170), mm(290), mm(80)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -d / 2, d / 2}

    base = [
      rbox({x0, y0, 0.0}, {x1, y0 + 0.03, h}, :black, 0.05),
      Shape.box({x0 + 0.02, y0 + 0.03, 0.04}, {x1 - 0.02, y0 + 0.04, h - 0.04}, :copper)
    ]

    fuses =
      for i <- 0..3,
          do: Shape.box({x0 + 0.03, y0 + 0.04, 0.05 + i * 0.05}, {x1 - 0.03, y0 + 0.06, 0.08 + i * 0.05}, :plastic)

    cover =
      Part.new(
        "lynx_cover",
        :cover,
        [
          rbox({x0, y0 + 0.03, 0.0}, {x1, y1, h}, :blue, 0.06),
          Shape.box({x0 + 0.04, y1, h - 0.06}, {x1 - 0.04, y1 + 0.002, h - 0.03}, :white)
        ],
        [same("hinge", {0.0, y0 + 0.03, h}, {1, 0, 0}, {0, 1, 0})]
      )

    Assembly.new(
      "victron_lynx_distributor",
      Part.new("lynx_distributor_m10", :busbar, base ++ fuses, [origin()], params: %{"fuses" => 4}),
      root: "busbar",
      kind: :electrical,
      sources: [
        "Victron, the technical specifications of the Lynx Distributor: 290 by 170 by 80 mm (h by l by w), 2.2 kg."
      ]
    )
    |> Assembly.add("cover", cover,
      at: Kit.same("hinge", {0.0, y0 + 0.03, h}, {1, 0, 0}, {0, 1, 0}),
      port: "hinge",
      kind: :turns,
      role: :lid,
      limits: [0, 100]
    )
  end

  @doc "The Victron Orion XS 12/12-50A, a DC-DC charger: 137.3 by 123.1 by 40 mm (h by w by d)."
  def orion_xs do
    {h, w, d} = {mm(137.3), mm(123.1), mm(40)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -d / 2, d / 2}

    shapes =
      [
        rbox({x0, y0, 0.006}, {x1, y1, h}, :blue, 0.08),
        Shape.box({x0 + 0.015, y1, h - 0.035}, {x0 + 0.05, y1 + 0.002, h - 0.02}, :white)
      ] ++
        for(
          i <- 0..5,
          do: Shape.box({x0 + 0.01 + i * 0.02, y0 - 0.004, 0.026}, {x0 + 0.018 + i * 0.02, y0, h - 0.02}, :dark)
        ) ++
        for(
          i <- 0..3,
          do: Shape.box({x0 + 0.02 + i * 0.025, y0 + 0.008, 0.0}, {x0 + 0.035 + i * 0.025, y1 - 0.008, 0.006}, :black)
        )

    Assembly.new(
      "victron_orion_xs_12_12_50",
      Part.new("orion_xs_12_12_50", :charger, shapes, [origin()], params: %{"amps" => 50}),
      root: "charger",
      kind: :electrical,
      sources: ["Victron Orion XS 12/12-50A: 137.3 by 123.1 by 40 mm, 0.33 kg (retailer listings)."]
    )
  end

  @doc "A battery switch: the Blue Sea Systems 6006 m-Series, on and off, with studs of 3/8-16 in (M10)."
  def battery_switch do
    s = mm(70)
    a = s / 2

    base = [rbox({-a, -a, 0.0}, {a, a, 0.035}, :red, 0.15), Kit.rod({0.0, 0.0, 0.035}, {0, 0, 1}, 0.018, 0.01, :black)]

    knob =
      Part.new(
        "switch_knob",
        :knob,
        [
          Shape.box({-0.008, -0.025, 0.045}, {0.008, 0.025, 0.065}, :red),
          Kit.rod({0.0, 0.0, 0.035}, {0, 0, 1}, 0.02, 0.012, :red)
        ],
        [same("knob", {0.0, 0.0, 0.035}, {0, 0, 1}, {0, 1, 0})]
      )

    Assembly.new(
      "battery_switch_blue_sea_6006",
      Part.new("blue_sea_6006", :switch, base, [origin()], params: %{"amps" => 300}),
      root: "switch",
      kind: :electrical,
      sources: [
        "Blue Sea Systems 6006 m-Series: studs of 3/8-16 in, 7/8 in long, 300 A (Waytek). The size of the base (70 by 70 mm) is an estimate from the photos."
      ]
    )
    |> Assembly.add("knob", knob,
      at: Kit.same("knob", {0.0, 0.0, 0.035}, {0, 0, 1}, {0, 1, 0}),
      port: "knob",
      kind: :turns,
      role: :knob,
      limits: [0, 90]
    )
    |> add_bolts("switch_stud", [{-a + 0.012, 0.0, 0.035}, {a - 0.012, 0.0, 0.035}], "M10", 0.022)
  end

  # --- The fridge, the fan, the heater, the tank --------------------------------------

  @doc "A 12 V fridge: the Dometic CFX3 45, 694 by 398 by 476 mm, its lid on a hinge at the back."
  def cfx3 do
    {l, w, h} = {mm(694), mm(398), mm(476)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -l / 2, l / 2}
    zl = h - 0.07

    body =
      Kit.cavity({x0, y0 + 0.17, 0.0}, {x1, y1, zl}, 0.04, :dark, :top) ++
        [
          rbox({x0, y0, 0.0}, {x1, y0 + 0.17, zl - 0.12}, :dark, 0.06),
          Shape.box({x0 + 0.04, y0 + 0.17, 0.0}, {x1 - 0.04, y0 + 0.21, zl - 0.12}, :dark),
          Shape.box({x0 + 0.03, y0 - 0.002, 0.05}, {x1 - 0.03, y0, zl - 0.17}, :black),
          Shape.box({-0.05, y0 + 0.08, zl - 0.12}, {0.05, y0 + 0.12, zl - 0.118}, :screen)
        ] ++
        for y <- [y0 + 0.07, y1 - 0.07],
            do:
              Shape.sweep(
                [{x0 - 0.002, y, zl - 0.15}, {x0 - 0.03, y, zl - 0.12}, {x0 - 0.03, y, 0.08}, {x0 - 0.002, y, 0.05}],
                0.008,
                :gray, sides: 6)

    lid =
      Part.new(
        "cfx3_45_lid",
        :lid,
        [
          rbox({x0, y0 + 0.17, zl}, {x1, y1, h}, :gray, 0.08),
          Shape.box({-0.08, y1, h - 0.05}, {0.08, y1 + 0.02, h - 0.02}, :dark)
        ],
        [same("hinge", {0.0, y0 + 0.17, zl}, {1, 0, 0}, {0, 1, 0})]
      )

    Assembly.new(
      "fridge_dometic_cfx3_45",
      Part.new("cfx3_45", :fridge, body, [origin()], params: %{"liters" => 46, "volts" => 12}),
      root: "fridge",
      kind: :appliance,
      sources: ["Dometic CFX3 45: 694 by 398 by 476 mm (BCF and Jacksons Leisure listings)."]
    )
    |> Assembly.add("lid", lid,
      at: Kit.same("hinge", {0.0, y0 + 0.17, zl}, {1, 0, 0}, {0, 1, 0}),
      port: "hinge",
      kind: :turns,
      role: :lid,
      limits: [0, 95]
    )
  end

  @doc """
  A roof fan: the MaxxAir MaxxFan Deluxe 7500K, 22 1/2 by 16 1/2 by 5 in,
  for a cutout of 14 by 14 in. The lid opens; the fan turns.
  """
  def maxxfan do
    {l, w, h} = {inch(22.5), inch(16.5), inch(5)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -l / 2, l / 2}
    c = inch(14) / 2

    # The flange on the roof, and the walls of the opening (no bottom).
    walls = Kit.cavity({-c, -c, -0.06}, {c, c, 0.03}, 0.012, :white, :top) |> List.delete_at(3)
    flange = [Shape.box({-c - 0.03, -c - 0.03, 0.0}, {c + 0.03, c + 0.03, 0.012}, :white) | walls]

    grille =
      for k <- 1..4,
          do:
            Shape.sweep(
              for(
                i <- 0..16,
                do: {0.045 * k * :math.cos(:math.pi() * i / 8), 0.045 * k * :math.sin(:math.pi() * i / 8), 0.03}
              ),
              0.002,
              :white, sides: 4)

    blades =
      for k <- 0..9 do
        a = 2 * :math.pi() * k / 10

        Shape.box({0.03, -0.025, -0.003}, {0.15, 0.025, 0.003}, :white,
          frame:
            Frame.compose(
              Frame.new({0.0, 0.0, 0.0}, {0, 0, 1}, {-:math.sin(a), :math.cos(a), 0.0}),
              Frame.turn({1, 0, 0}, 25)
            )
        )
      end

    fan =
      Part.new(
        "maxxfan_rotor",
        :fan,
        [Kit.rod({0.0, 0.0, -0.01}, {0, 0, 1}, 0.03, 0.02, :white) | blades],
        [same("axle", @o, {0, 0, 1}, {0, 1, 0})], inside: true)

    lid =
      Part.new(
        "maxxfan_lid",
        :lid,
        [rbox({x0, y0, 0.03}, {x1, y1, h}, :glass_dark, 0.08)],
        [same("hinge", {0.0, y0, 0.03}, {1, 0, 0}, {0, 1, 0})]
      )

    Assembly.new(
      "roof_fan_maxxair_7500k",
      Part.new("maxxfan_7500k_base", :base, flange ++ grille, [origin()], params: %{"cutout_in" => 14}),
      root: "base",
      kind: :appliance,
      sources: ["MaxxAir MaxxFan Deluxe 7500K: 22 1/2 by 16 1/2 by 5 in, a cutout of 14 by 14 in (retailer listing)."]
    )
    |> Assembly.add("fan", fan,
      at: Kit.same("axle", {0.0, 0.0, -0.02}, {0, 0, 1}, {0, 1, 0}),
      port: "axle",
      kind: :turns,
      role: :spin
    )
    |> Assembly.add("lid", lid,
      at: Kit.same("hinge", {0.0, y0, 0.03}, {1, 0, 0}, {0, 1, 0}),
      port: "hinge",
      kind: :turns,
      role: :lid,
      limits: [0, 50]
    )
  end

  @doc "A diesel air heater: the Webasto Air Top 2000 STC, 310 by 120 by 118 mm, 2.6 kg."
  def air_top do
    {l, w, h} = {mm(310), mm(120), mm(118)}
    {x0, x1} = {-l / 2, l / 2}

    shapes = [
      Shape.loft(
        for(
          {x, k} <- [{x0, 0.8}, {x0 + 0.03, 1.0}, {x1 - 0.03, 1.0}, {x1, 0.85}],
          do: {{x, 0.0, h / 2}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}, w / 2 * k, h / 2 * k, 5}
        ),
        :black, sides: 20),
      Shape.box({x0 + 0.04, -w / 2 - 0.002, h * 0.35}, {x0 + 0.12, -w / 2, h * 0.65}, :dark),
      Kit.rod({x0, 0.0, h / 2}, {-1, 0, 0}, mm(45), 0.02, :black, 16),
      Kit.rod({x1, 0.0, h / 2}, {1, 0, 0}, mm(45), 0.02, :black, 16),
      Kit.rod({x0 + 0.06, 0.0, 0.0}, {0, 0, -1}, mm(12), 0.05, :steel),
      Kit.rod({x0 + 0.12, 0.0, 0.0}, {0, 0, -1}, mm(12), 0.05, :steel),
      Kit.rod({x1 - 0.06, 0.0, 0.0}, {0, 0, -1}, mm(12), 0.05, :steel)
    ]

    Assembly.new(
      "heater_webasto_air_top_2000_stc",
      Part.new("air_top_2000_stc", :heater, shapes, [origin()], params: %{"watts" => 2000, "fuel" => "diesel"}),
      root: "heater",
      kind: :appliance,
      sources: [
        "Webasto, the Air Top 2000 STC: 310 by 120 by 118 mm (l by w by h), 2.6 kg. The pipes under it go through the floor."
      ]
    )
  end

  @doc "A fresh water tank of 20 gallons (76 L): 24 by 14 by 14 in, with a fill, a vent and an outlet."
  def water_tank do
    {w, d, h} = {inch(24), inch(14), inch(14)}

    shapes = [
      rbox({-w / 2, -d / 2, 0.0}, {w / 2, d / 2, h}, :white, 0.08),
      Kit.rod({-w / 2 + 0.06, 0.0, h}, {0, 0, 1}, mm(20), 0.03, :black),
      Kit.rod({w / 2 - 0.06, 0.0, h}, {0, 0, 1}, mm(8), 0.025, :black),
      Kit.rod({w / 2, 0.0, 0.03}, {1, 0, 0}, mm(10), 0.03, :black)
    ]

    Assembly.new("water_tank_20gal", Part.new("water_tank_20gal", :tank, shapes, [origin()], params: %{"liters" => 76}),
      root: "tank",
      kind: :plumbing,
      sources: [
        "No source: a common size of a tank of 20 gallons. The item sheet of DIY asks for the size of the real tank."
      ]
    )
  end

  # --- The solar panel ------------------------------------------------------------------

  @doc """
  A solar panel of 400 W: the Rich Solar MEGA 400, 67.8 by 44.7 by 1.2 in,
  108 half cells (6 by 18). It lies flat: the long side along y.
  """
  def solar_panel do
    {w, l, t} = {inch(44.7), inch(67.8), inch(1.2)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -l / 2, l / 2}
    f = 0.03

    frame = [
      Shape.box({x0, y0, 0.0}, {x0 + f, y1, t}, :aluminum),
      Shape.box({x1 - f, y0, 0.0}, {x1, y1, t}, :aluminum),
      Shape.box({x0 + f, y0, 0.0}, {x1 - f, y0 + f, t}, :aluminum),
      Shape.box({x0 + f, y1 - f, 0.0}, {x1 - f, y1, t}, :aluminum),
      Shape.box({x0 + f, y0 + f, t - 0.008}, {x1 - f, y1 - f, t - 0.004}, :white)
    ]

    {cw, cl} = {(w - 2 * f - 0.03) / 6, (l - 2 * f - 0.05) / 18}

    cells =
      for i <- 0..5, j <- 0..17 do
        {cx, cy} = {x0 + f + 0.015 + i * cw, y0 + f + 0.025 + j * cl}
        Shape.box({cx + 0.002, cy + 0.002, t - 0.004}, {cx + cw - 0.002, cy + cl - 0.002, t - 0.003}, :solar_cell)
      end

    glass = Shape.box({x0 + f, y0 + f, t - 0.003}, {x1 - f, y1 - f, t - 0.0005}, :glass)
    box = Shape.box({-0.06, y1 - 0.25, 0.005}, {0.06, y1 - 0.15, 0.025}, :black)

    Assembly.new(
      "solar_panel_rich_solar_mega_400",
      Part.new("rich_solar_mega_400", :panel, frame ++ cells ++ [glass, box], [origin()],
        params: %{"watts" => 400, "cells" => 108}
      ),
      root: "panel",
      kind: :electrical,
      sources: ["Rich Solar, the page of the MEGA 400: 67.8 by 44.7 by 1.2 in, 108 half cells (6 by 9 by 2)."]
    )
  end
end
