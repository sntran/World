defmodule Xuong.Models.Appliances do
  @moduledoc """
  The appliances of a house for DIY (Small Steps Home), at the sizes of
  the models that DIY uses (`DIY.Catalog`, the typical size of each
  kind). The doors, the lids and the drawers open; the drums, the fans
  and the turntables turn; the knobs turn.

  Each appliance has a body with a real opening (a cavity), so an open
  door shows the inside: the shelves, the racks, the drum.
  """
  alias Xuong.{Assembly, Frame, Part, Shape}
  alias Xuong.Models.Kit
  import Kit, only: [inch: 1, same: 4, rbox: 4]

  # --- The fridge -----------------------------------------------------------

  @doc """
  A fridge with French doors and a freezer drawer: the LG LRFXS2503S,
  32 3/4 by 33 (with the handles) by 69 7/8 in.
  """
  def fridge do
    {w, d, h} = {inch(32.75), inch(33), inch(69.875)}
    {x0, x1} = {-w / 2, w / 2}
    y0 = -d / 2
    # The front of the body, of the doors, and of the handles.
    {yb, yd} = {y0 + 0.70, y0 + 0.775}
    {zb, zm, zt} = {0.02, 0.80, h}
    t = 0.035

    body =
      Kit.cavity({x0, y0, zb}, {x1, yb, zt}, t, :stainless) ++
        [
          # The wall between the freezer and the fresh food, and the base.
          Shape.box({x0 + t, y0 + t, zm}, {x1 - t, yb, zm + 0.04}, :stainless),
          Shape.box({x0 + 0.02, yb - 0.06, 0.0}, {x1 - 0.02, yb - 0.01, zb}, :black)
        ] ++
        Kit.feet(
          [{x0 + 0.05, y0 + 0.05}, {x1 - 0.05, y0 + 0.05}, {x0 + 0.05, yb - 0.1}, {x1 - 0.05, yb - 0.1}],
          0.015,
          zb
        )

    inside =
      Kit.cavity({x0 + t, y0 + t, zm + 0.04}, {x1 - t, yb - 0.005, zt - t}, 0.006, :white) ++
        for z <- [1.06, 1.29, 1.52],
            do: Shape.box({x0 + t + 0.01, y0 + t + 0.01, z}, {x1 - t - 0.01, yb - 0.09, z + 0.006}, :glass)

    crispers =
      for {a, b} <- [{x0 + t + 0.01, -0.005}, {0.005, x1 - t - 0.01}] do
        Kit.cavity({a, y0 + 0.08, zm + 0.05}, {b, yb - 0.09, zm + 0.22}, 0.004, :plastic, :top)
      end

    cabinet =
      Part.new("fridge_lg_lrfxs2503s_body", :body, body, [
        same("door_left", {x0, yb, zm + 0.045}, {0, 0, 1}, {0, 1, 0}),
        same("door_right", {x1, yb, zm + 0.045}, {0, 0, -1}, {0, 1, 0}),
        same("drawer", {0.0, yb, zb}, {0, 1, 0}, {0, 0, 1})
      ])

    Assembly.new("fridge_lg_lrfxs2503s", cabinet,
      root: "body",
      kind: :appliance,
      sources: ["LG LRFXS2503S: 32 3/4 by 33 (with the handles) by 69 7/8 in (retailer listings, the size of DIY)."]
    )
    |> Assembly.add(
      "shelves",
      Part.new("fridge_shelves", :shelf, inside ++ List.flatten(crispers), [same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})],
        inside: true
      ), at: Kit.same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}), port: "o")
    |> Assembly.add("door_left", fridge_door(:left, x0, 0.0, yb, yd, zm + 0.045, zt, d),
      at: "door_left",
      port: "hinge",
      kind: :turns,
      role: :door,
      limits: [0, 120]
    )
    |> Assembly.add("door_right", fridge_door(:right, 0.0, x1, yb, yd, zm + 0.045, zt, d),
      at: "door_right",
      port: "hinge",
      kind: :turns,
      role: :door,
      limits: [0, 120]
    )
    |> Assembly.add("freezer_drawer", freezer_drawer(x0, x1, y0, yb, yd, zb, zm, d),
      at: "drawer",
      port: "slide",
      kind: :slides,
      role: :drawer,
      limits: [0, 0.45]
    )
  end

  defp fridge_door(side, xa, xb, yb, yd, z0, z1, d) do
    gap = 0.003
    {xa, xb} = {xa + if(side == :right, do: gap, else: 0.0), xb - if(side == :left, do: gap, else: 0.0)}
    inner = if side == :left, do: xb - 0.03, else: xa + 0.03
    yh = -d / 2 + d

    slab = rbox({xa, yb, z0}, {xb, yd, z1}, :stainless, 0.04)
    liner = Shape.box({xa + 0.03, yb - 0.012, z0 + 0.04}, {xb - 0.03, yb, z1 - 0.04}, :white)

    bins =
      for z <- [z0 + 0.18, z0 + 0.48, z0 + 0.74],
          do: Kit.cavity({xa + 0.05, yb - 0.075, z}, {xb - 0.05, yb - 0.012, z + 0.1}, 0.004, :plastic, :top)

    grip = Kit.handle({inner, yd, z0 + 0.2}, {inner, yd, z1 - 0.15}, {0, 1, 0}, yh - yd - 0.012, 0.012, :stainless)

    screen =
      if side == :left,
        do: [Shape.box({xa + 0.10, yd, z0 + 0.62}, {xa + 0.22, yd + 0.002, z0 + 0.72}, :screen)],
        else: []

    hinge =
      if side == :left,
        do: same("hinge", {xa, yb, z0}, {0, 0, 1}, {0, 1, 0}),
        else: same("hinge", {xb, yb, z0}, {0, 0, -1}, {0, 1, 0})

    Part.new("fridge_door_#{side}", :door, [slab, liner, grip | screen] ++ List.flatten(bins), [hinge])
  end

  defp freezer_drawer(x0, x1, y0, yb, yd, zb, zm, d) do
    front = rbox({x0, yb, zb + 0.005}, {x1, yd, zm - 0.005}, :stainless, 0.04)
    basket = Kit.cavity({x0 + 0.06, y0 + 0.12, zb + 0.05}, {x1 - 0.06, yb, zm - 0.18}, 0.004, :plastic, :top)

    grip =
      Kit.handle(
        {x0 + 0.12, yd, zm - 0.07},
        {x1 - 0.12, yd, zm - 0.07},
        {0, 1, 0},
        d / 2 - yd - 0.012,
        0.012,
        :stainless
      )

    Part.new("fridge_freezer_drawer", :drawer, [front, grip | basket], [
      same("slide", {0.0, yb, zb}, {0, 1, 0}, {0, 0, 1})
    ])
  end

  # --- The washer and the dryer ---------------------------------------------

  @doc "A washer with its door in the front: the LG WM4000HWA, 27 by 30 1/4 by 39 in."
  def washer, do: front_loader(:washer)

  @doc "A dryer of the same line as the washer: 27 by 30 1/4 by 39 in."
  def dryer, do: front_loader(:dryer)

  defp front_loader(kind) do
    {w, d, h} = {inch(27), inch(30.25), inch(39)}
    {x0, x1, y0} = {-w / 2, w / 2, -d / 2}
    # The front of the body: the door is in front of it.
    yf = y0 + d - 0.07
    {cz, half, ring} = if kind == :washer, do: {0.43, 0.2, 0.235}, else: {0.47, 0.2, 0.235}
    zp = h - 0.12

    body =
      [
        Shape.box({x0, y0, 0.02}, {x1, yf - 0.02, 0.06}, :white),
        Shape.box({x0, y0, 0.06}, {x0 + 0.02, yf - 0.02, h}, :white),
        Shape.box({x1 - 0.02, y0, 0.06}, {x1, yf - 0.02, h}, :white),
        Shape.box({x0 + 0.02, y0, 0.06}, {x1 - 0.02, y0 + 0.02, h}, :white),
        rbox({x0, y0, h - 0.02}, {x1, yf, h}, :white, 0.03),
        # The control panel.
        rbox({x0, yf - 0.02, zp}, {x1, yf + 0.01, h - 0.02}, :white, 0.1),
        Shape.box({x0 + 0.22, yf + 0.01, zp + 0.03}, {x0 + 0.42, yf + 0.012, zp + 0.08}, :screen)
      ] ++
        Kit.holed_panel({x0, x1}, {0.02, zp}, {yf - 0.02, yf}, {0.0, cz}, half, :white) ++
        [
          # The ring around the door and the gasket.
          Shape.lathe([{0.19, 0.0}, {half * 1.5, 0.0}, {half * 1.5, 0.004}, {0.19, 0.004}], :plastic,
            kind: :ring,
            sides: 32,
            frame: Frame.new({0.0, yf, cz}, {0, 1, 0}, {0, 0, 1})
          ),
          Shape.lathe([{0.17, -0.12}, {0.19, -0.12}, {0.21, -0.01}, {0.19, 0.0}], :rubber,
            kind: :ring,
            sides: 32,
            frame: Frame.new({0.0, yf, cz}, {0, 1, 0}, {0, 0, 1})
          )
        ] ++
        Kit.feet(
          [{x0 + 0.05, y0 + 0.06}, {x1 - 0.05, y0 + 0.06}, {x0 + 0.05, yf - 0.08}, {x1 - 0.05, yf - 0.08}],
          0.02,
          0.02
        )

    # The drum: stainless, with three lifters, on the axis of the door.
    drum_shapes =
      [
        Shape.lathe([{0.0, -0.5}, {0.25, -0.5}, {0.25, -0.12}, {0.2, -0.1}], :stainless,
          sides: 32,
          frame: Frame.new({0.0, yf, cz}, {0, 1, 0}, {0, 0, 1})
        )
      ] ++
        for k <- 0..2 do
          a = 2 * :math.pi() * k / 3
          {sx, sz} = {:math.sin(a), :math.cos(a)}

          Shape.box({-0.015, -0.48, 0.21}, {0.015, -0.14, 0.25}, :plastic,
            frame: Frame.new({0.0, yf, cz}, {sx, 0.0, sz}, {0, 1, 0})
          )
        end

    drum =
      Part.new("drum_#{kind}", :drum, drum_shapes, [same("axle", {0.0, yf, cz}, {0, 1, 0}, {0, 0, 1})], inside: true)

    {knob_at, dial} =
      {{x1 - 0.16, yf + 0.01, zp + 0.055},
       Kit.knob("dial_#{kind}", {x1 - 0.16, yf + 0.01, zp + 0.055}, {0, 1, 0}, {0, 0, 1}, 0.035, 0.025)}

    door = front_door(kind, {0.0, yf, cz}, ring)

    base = Part.new("#{kind}_body", :body, body, [same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})])

    asm =
      Assembly.new(if(kind == :washer, do: "washer_lg_wm4000hwa", else: "dryer_lg"), base,
        root: "body",
        kind: :appliance,
        sources: [
          if(kind == :washer,
            do: "LG WM4000HWA: 27 by 30 1/4 by 39 in (LG spec sheet, the size of DIY).",
            else:
              "A dryer of the line of the LG WM4000HWA: 27 by 30 1/4 by 39 in (the size of DIY, no source of its own)."
          )
        ]
      )
      |> Assembly.add("drum", drum,
        at: Kit.same("axle", {0.0, yf, cz}, {0, 1, 0}, {0, 0, 1}),
        port: "axle",
        kind: :turns,
        role: :spin
      )
      |> Assembly.add("door", door,
        at: Kit.same("hinge", {-ring - 0.03, yf, cz}, {0, 0, 1}, {0, 1, 0}),
        port: "hinge",
        kind: :turns,
        role: :door,
        limits: [0, 170]
      )
      |> Assembly.add("dial", dial,
        at: Kit.same("dial_#{kind}", knob_at, {0, 1, 0}, {0, 0, 1}),
        port: "dial_#{kind}",
        kind: :turns,
        role: :knob,
        limits: [0, 330]
      )

    if kind == :washer do
      tray =
        Part.new(
          "detergent_drawer",
          :drawer,
          [
            Shape.box({x0 + 0.02, yf - 0.35, zp + 0.005}, {x0 + 0.2, yf + 0.012, zp + 0.1}, :white),
            Shape.box({x0 + 0.05, yf + 0.012, zp + 0.06}, {x0 + 0.17, yf + 0.02, zp + 0.075}, :plastic)
          ],
          [same("slide", {x0, yf, zp}, {0, 1, 0}, {0, 0, 1})],
          detail: :near
        )

      Assembly.add(asm, "detergent_drawer", tray,
        at: Kit.same("slide", {x0, yf, zp}, {0, 1, 0}, {0, 0, 1}),
        port: "slide",
        kind: :slides,
        role: :drawer,
        limits: [0, 0.25]
      )
    else
      vent = Kit.rod({0.0, y0, 0.25}, {0, -1, 0}, inch(2), 0.06, :aluminum, 16)

      Assembly.add(asm, "vent", Part.new("dryer_vent_4in", :pipe, vent, [same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})]),
        at: Kit.same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}),
        port: "o"
      )
    end
  end

  # A round door with a glass bowl: it turns around a hinge at its left.
  defp front_door(kind, {cx, yf, cz}, ring) do
    f = Frame.new({cx, yf, cz}, {0, 1, 0}, {0, 0, 1})
    frame_color = if kind == :washer, do: :chrome, else: :dark

    shapes = [
      Shape.lathe(
        [{ring - 0.065, 0.012}, {ring, 0.012}, {ring + 0.005, 0.045}, {ring - 0.02, 0.065}, {ring - 0.065, 0.06}],
        frame_color, kind: :ring, sides: 40, frame: f),
      Shape.lathe([{0.0, -0.05}, {0.12, -0.04}, {ring - 0.06, 0.02}, {ring - 0.06, 0.05}, {0.0, 0.05}], :glass_dark,
        sides: 32,
        frame: f
      ),
      Shape.box({cx + ring - 0.03, yf + 0.03, cz - 0.07}, {cx + ring + 0.005, yf + 0.06, cz + 0.07}, :dark),
      Shape.box({cx - ring - 0.03, yf + 0.005, cz - 0.09}, {cx - ring + 0.01, yf + 0.025, cz + 0.09}, :metal)
    ]

    Part.new("door_round_#{kind}", :door, shapes, [same("hinge", {cx - ring - 0.03, yf, cz}, {0, 0, 1}, {0, 1, 0})])
  end

  # --- The dishwasher --------------------------------------------------------

  @doc """
  A dishwasher under a counter: 24 by 24 by 34 in (the opening of a
  counter). The door turns down at its bottom; two racks slide out.
  """
  def dishwasher do
    {w, d, h} = {inch(24), inch(24), inch(34)}
    {x0, x1, y0} = {-w / 2 + 0.005, w / 2 - 0.005, -d / 2}
    yf = d / 2 - 0.05
    zh = 0.11

    tub = Kit.cavity({x0, y0, zh}, {x1, yf, h - 0.01}, 0.02, :stainless)

    base =
      [
        Shape.box({x0, y0, 0.02}, {x1, yf, zh}, :dark),
        Shape.box({x0 + 0.01, yf, 0.02}, {x1 - 0.01, yf + 0.02, zh - 0.005}, :stainless)
      ] ++
        Kit.feet(
          [{x0 + 0.04, y0 + 0.05}, {x1 - 0.04, y0 + 0.05}, {x0 + 0.04, yf - 0.05}, {x1 - 0.04, yf - 0.05}],
          0.012,
          0.02,
          :metal
        )

    arm =
      Shape.box({-0.2, -0.02, 0.0}, {0.2, 0.02, 0.012}, :plastic, frame: Frame.move({0.0, (y0 + yf) / 2, zh + 0.04}))

    body = Part.new("dishwasher_tub", :body, tub ++ base, [same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})])

    spray =
      Part.new("spray_arm", :arm, arm, [same("arm", {0.0, (y0 + yf) / 2, zh + 0.04}, {0, 0, 1}, {0, 1, 0})],
        inside: true
      )

    door =
      Part.new(
        "dishwasher_door",
        :door,
        [
          rbox({x0, yf, zh}, {x1, yf + 0.045, h}, :stainless, 0.03),
          Shape.box({x0 + 0.02, yf - 0.01, zh + 0.02}, {x1 - 0.02, yf, h - 0.02}, :stainless),
          Shape.box({x0 + 0.1, yf + 0.045, h - 0.05}, {x0 + 0.24, yf + 0.047, h - 0.025}, :screen),
          Kit.handle(
            {x0 + 0.08, yf + 0.045, h - 0.1},
            {x1 - 0.08, yf + 0.045, h - 0.1},
            {0, 1, 0},
            0.035,
            0.01,
            :stainless
          )
        ],
        [same("hinge", {0.0, yf, zh}, {-1, 0, 0}, {0, 1, 0})]
      )

    Assembly.new("dishwasher_24in", body,
      root: "tub",
      kind: :appliance,
      sources: [
        "A dishwasher under a counter: an opening of 24 in (the size of DIY). The depth and the height are typical, no source."
      ]
    )
    |> Assembly.add("spray_arm", spray,
      at: Kit.same("arm", {0.0, (y0 + yf) / 2, zh + 0.04}, {0, 0, 1}, {0, 1, 0}),
      port: "arm",
      kind: :turns,
      role: :spin
    )
    |> Assembly.add("door", door,
      at: Kit.same("hinge", {0.0, yf, zh}, {-1, 0, 0}, {0, 1, 0}),
      port: "hinge",
      kind: :turns,
      role: :door,
      limits: [0, 90]
    )
    |> Assembly.add("rack_lower", rack("rack_lower", x0, x1, y0, yf, zh + 0.07, 0.17),
      at: Kit.same("slide_rack_lower", {0.0, yf, zh + 0.07}, {0, 1, 0}, {0, 0, 1}),
      port: "slide_rack_lower",
      kind: :slides,
      role: :drawer,
      limits: [0, 0.45]
    )
    |> Assembly.add("rack_upper", rack("rack_upper", x0, x1, y0, yf, zh + 0.38, 0.15),
      at: Kit.same("slide_rack_upper", {0.0, yf, zh + 0.38}, {0, 1, 0}, {0, 0, 1}),
      port: "slide_rack_upper",
      kind: :slides,
      role: :drawer,
      limits: [0, 0.4]
    )
  end

  # A wire rack: a frame of rods and tines.
  defp rack(name, x0, x1, y0, yf, z, h) do
    {a, b, c, e} = {x0 + 0.04, x1 - 0.04, y0 + 0.04, yf - 0.02}
    r = 0.003

    rim =
      for zz <- [z, z + h],
          do: Shape.sweep([{a, c, zz}, {b, c, zz}, {b, e, zz}, {a, e, zz}, {a, c, zz}], r, :plastic, sides: 6)

    floor = Kit.bars({a, c, z}, {a, e, z}, {(b - a) / 9, 0.0, 0.0}, 10, r, :plastic)

    tines =
      Kit.bars(
        {a + 0.05, c + 0.03, z},
        {a + 0.05, c + 0.03, z + h * 0.7},
        {0.0, (e - c - 0.06) / 7, 0.0},
        8,
        r,
        :plastic
      )

    Part.new(name, :rack, rim ++ floor ++ tines, [same("slide_" <> name, {0.0, yf, z}, {0, 1, 0}, {0, 0, 1})],
      inside: true
    )
  end

  # --- The range and the microwave -------------------------------------------

  @doc """
  A gas range: 30 in wide (the cutout of most counters), 28 in deep and 47
  in high at its back guard. The oven door turns down, the drawer slides,
  the five knobs turn.
  """
  def range do
    {w, d, h} = {inch(30), inch(28), inch(47)}
    {x0, x1, y0} = {-w / 2, w / 2, -d / 2}
    yf = d / 2 - 0.06
    {zo0, zo1, zc} = {0.17, 0.78, 0.915}

    body =
      [
        Shape.box({x0, y0, 0.0}, {x0 + 0.02, yf, zc}, :stainless),
        Shape.box({x1 - 0.02, y0, 0.0}, {x1, yf, zc}, :stainless),
        Shape.box({x0 + 0.02, y0, 0.0}, {x1 - 0.02, y0 + 0.02, zc}, :dark),
        # The front panel of the knobs, the top and the back guard.
        Shape.box({x0, yf - 0.02, zo1 + 0.04}, {x1, yf + 0.03, zc}, :stainless),
        Shape.box({x0, y0, zc}, {x1, yf + 0.03, zc + 0.012}, :black),
        rbox({x0, y0, zc}, {x1, y0 + 0.07, h}, :stainless, 0.1)
      ] ++
        Kit.cavity({x0 + 0.02, y0 + 0.02, zo0}, {x1 - 0.02, yf, zo1 + 0.04}, 0.012, :dark) ++
        [Shape.box({x0 + 0.02, y0 + 0.02, 0.0}, {x1 - 0.02, yf, 0.03}, :dark)]

    burners =
      for {x, y, r} <- [{-0.19, 0.12, 0.05}, {0.19, 0.12, 0.045}, {-0.19, -0.13, 0.04}, {0.19, -0.13, 0.055}] do
        Shape.lathe([{0.0, 0.0}, {r, 0.0}, {r, 0.018}, {r * 0.7, 0.026}, {0.0, 0.026}], :black,
          sides: 20,
          frame: Frame.move({x, y, zc + 0.012})
        )
      end

    grates =
      for xs <- [{x0 + 0.02, -0.01}, {0.01, x1 - 0.02}] do
        {a, b} = xs
        {c, e} = {y0 + 0.09, yf - 0.01}
        z = zc + 0.05
        frame = Shape.sweep([{a, c, z}, {b, c, z}, {b, e, z}, {a, e, z}, {a, c, z}], 0.005, :black, sides: 6)
        [frame | Kit.bars({a + (b - a) / 4, c, z}, {a + (b - a) / 4, e, z}, {(b - a) / 4, 0.0, 0.0}, 3, 0.005, :black)]
      end

    racks =
      for z <- [0.33, 0.52],
          do:
            Shape.sweep(
              [
                {x0 + 0.05, y0 + 0.05, z},
                {x1 - 0.05, y0 + 0.05, z},
                {x1 - 0.05, yf - 0.03, z},
                {x0 + 0.05, yf - 0.03, z},
                {x0 + 0.05, y0 + 0.05, z}
              ],
              0.003,
              :chrome, sides: 6)

    door =
      Part.new(
        "oven_door",
        :door,
        [
          Kit.holed_panel({x0 + 0.003, x1 - 0.003}, {zo0, zo1 + 0.035}, {yf, yf + 0.05}, {0.0, 0.5}, 0.17, :stainless),
          [Shape.box({-0.2, yf + 0.01, 0.33}, {0.2, yf + 0.04, 0.67}, :glass_dark)],
          [Kit.handle({x0 + 0.06, yf + 0.05, zo1}, {x1 - 0.06, yf + 0.05, zo1}, {0, 1, 0}, 0.05, 0.012, :stainless)]
        ]
        |> List.flatten(),
        [same("hinge", {0.0, yf, zo0}, {-1, 0, 0}, {0, 1, 0})]
      )

    drawer =
      Part.new(
        "range_drawer",
        :drawer,
        [rbox({x0 + 0.003, yf, 0.035}, {x1 - 0.003, yf + 0.05, zo0 - 0.005}, :stainless, 0.05)] ++
          Kit.cavity({x0 + 0.04, y0 + 0.1, 0.04}, {x1 - 0.04, yf, zo0 - 0.02}, 0.004, :dark, :top),
        [same("slide", {0.0, yf, 0.035}, {0, 1, 0}, {0, 0, 1})]
      )

    cooktop =
      Part.new("range_body", :body, body ++ burners ++ List.flatten(grates), [
        same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})
      ])

    asm =
      Assembly.new("range_30in", cooktop,
        root: "body",
        kind: :appliance,
        sources: [
          "A range of 30 in: the cutout of most counters (the size of DIY). The depth and the height at the back guard are typical, no source."
        ]
      )
      |> Assembly.add(
        "racks",
        Part.new("oven_racks", :rack, racks, [same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})], inside: true),
        at: Kit.same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}),
        port: "o"
      )
      |> Assembly.add("oven_door", door,
        at: Kit.same("hinge", {0.0, yf, zo0}, {-1, 0, 0}, {0, 1, 0}),
        port: "hinge",
        kind: :turns,
        role: :door,
        limits: [0, 90]
      )
      |> Assembly.add("drawer", drawer,
        at: Kit.same("slide", {0.0, yf, 0.035}, {0, 1, 0}, {0, 0, 1}),
        port: "slide",
        kind: :slides,
        role: :drawer,
        limits: [0, 0.4]
      )

    Enum.reduce(Enum.with_index([-0.26, -0.13, 0.0, 0.13, 0.26], 1), asm, fn {x, i}, asm ->
      at = {x, yf + 0.03, zo1 + 0.085}
      name = "knob_#{i}"

      Assembly.add(asm, name, Kit.knob(name, at, {0, 1, 0}, {0, 0, 1}, 0.022, 0.03),
        at: Kit.same(name, at, {0, 1, 0}, {0, 0, 1}),
        port: name,
        kind: :turns,
        role: :knob,
        limits: [0, 270]
      )
    end)
  end

  @doc "A microwave on a counter: the Panasonic NN-SN966S, 23 7/8 by 19 7/16 by 14 in."
  def microwave do
    {w, d, h} = {inch(23.875), inch(19.4375), inch(14)}
    {x0, x1, y0} = {-w / 2, w / 2, -d / 2}
    yf = d / 2 - 0.035
    xs = x1 - 0.14

    body =
      [
        rbox({x0, y0, 0.012}, {x1, yf, 0.03}, :stainless, 0.05),
        rbox({x0, y0, h - 0.018}, {x1, yf, h}, :stainless, 0.05),
        Shape.box({x0, y0, 0.03}, {x0 + 0.012, yf, h - 0.018}, :stainless),
        Shape.box({x1 - 0.012, y0, 0.03}, {x1, yf, h - 0.018}, :stainless),
        Shape.box({x0, y0, 0.03}, {x1, y0 + 0.012, h - 0.018}, :stainless),
        Shape.box({xs, y0 + 0.012, 0.03}, {x1 - 0.012, yf, h - 0.018}, :stainless),
        # The panel of the buttons.
        Shape.box({xs, yf, 0.03}, {x1, yf + 0.035, h - 0.018}, :black),
        Shape.box({xs + 0.02, yf + 0.035, h - 0.08}, {x1 - 0.02, yf + 0.036, h - 0.04}, :screen)
      ] ++
        Kit.cavity({x0 + 0.012, y0 + 0.012, 0.03}, {xs, yf, h - 0.018}, 0.004, :white) ++
        Kit.feet(
          [{x0 + 0.04, y0 + 0.04}, {x1 - 0.04, y0 + 0.04}, {x0 + 0.04, yf - 0.04}, {x1 - 0.04, yf - 0.04}],
          0.01,
          0.012
        )

    buttons =
      for i <- 0..3,
          j <- 0..2,
          do:
            Shape.box(
              {xs + 0.025 + j * 0.032, yf + 0.035, 0.08 + i * 0.03},
              {xs + 0.05 + j * 0.032, yf + 0.039, 0.1 + i * 0.03},
              :plastic
            )

    cx = (x0 + xs) / 2

    plate =
      Part.new(
        "turntable",
        :plate,
        [Shape.lathe([{0.0, 0.0}, {0.16, 0.0}, {0.165, 0.012}, {0.0, 0.006}], :glass, sides: 32)],
        [same("axle", {0.0, 0.0, 0.0}, {0, 0, 1}, {0, 1, 0})], inside: true)

    door =
      Part.new(
        "microwave_door",
        :door,
        Kit.holed_panel(
          {x0 + 0.002, xs - 0.002},
          {0.032, h - 0.02},
          {yf, yf + 0.035},
          {cx - 0.02, h / 2},
          0.1,
          :stainless
        ) ++
          [
            Shape.box({x0 + 0.06, yf + 0.005, h / 2 - 0.1}, {xs - 0.1, yf + 0.03, h / 2 + 0.1}, :glass_dark),
            Kit.handle(
              {xs - 0.04, yf + 0.035, 0.08},
              {xs - 0.04, yf + 0.035, h - 0.08},
              {0, 1, 0},
              0.025,
              0.008,
              :stainless
            )
          ],
        [same("hinge", {x0, yf, 0.03}, {0, 0, 1}, {0, 1, 0})]
      )

    Assembly.new(
      "microwave_panasonic_nn_sn966s",
      Part.new("microwave_body", :body, body ++ buttons, [same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})]),
      root: "body",
      kind: :appliance,
      sources: ["Panasonic NN-SN966S: 23 7/8 by 19 7/16 by 14 in (Panasonic spec table, the size of DIY)."]
    )
    |> Assembly.add("turntable", plate,
      at: Kit.same("t", {cx, (y0 + yf) / 2, 0.036}, {0, 0, 1}, {0, 1, 0}),
      port: "axle",
      kind: :turns,
      role: :spin
    )
    |> Assembly.add("door", door,
      at: Kit.same("hinge", {x0, yf, 0.03}, {0, 0, 1}, {0, 1, 0}),
      port: "hinge",
      kind: :turns,
      role: :door,
      limits: [0, 110]
    )
  end

  # --- The chest freezer ---------------------------------------------------

  @doc "A chest freezer: the Frigidaire FFCL1542AW, 14.8 cu ft, 55 3/4 by 29 9/16 by 32 1/2 in."
  def freezer do
    {w, d, h} = {inch(55.75), inch(29.5625), inch(32.5)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -d / 2, d / 2}
    zl = h - 0.07
    t = 0.06

    box = [
      rbox({x0, y0, 0.02}, {x0 + t, y1, zl}, :white, 0.04),
      rbox({x1 - t, y0, 0.02}, {x1, y1, zl}, :white, 0.04),
      rbox({x0 + t, y0, 0.02}, {x1 - t, y0 + t, zl}, :white, 0.04),
      rbox({x0 + t, y1 - t, 0.02}, {x1 - t, y1, zl}, :white, 0.04),
      Shape.box({x0 + t, y0 + t, 0.02}, {x1 - t, y1 - t, 0.12}, :white),
      # The step of the compressor, at the right of the inside.
      Shape.box({x1 - t - 0.3, y0 + t, 0.12}, {x1 - t, y1 - t, 0.3}, :white),
      Shape.box({x0 + 0.1, y1, 0.08}, {x0 + 0.2, y1 + 0.004, 0.11}, :plastic)
    ]

    feet =
      Kit.feet(
        [{x0 + 0.06, y0 + 0.06}, {x1 - 0.06, y0 + 0.06}, {x0 + 0.06, y1 - 0.06}, {x1 - 0.06, y1 - 0.06}],
        0.02,
        0.02
      )

    basket =
      Kit.cavity(
        {x0 + t + 0.02, y0 + t + 0.02, zl - 0.25},
        {x0 + t + 0.42, y1 - t - 0.02, zl - 0.03},
        0.004,
        :plastic,
        :top
      )

    lid =
      Part.new(
        "freezer_lid",
        :lid,
        [
          rbox({x0, y0, zl}, {x1, y1 + 0.01, h}, :white, 0.06),
          Shape.box({-0.12, y1 + 0.01, zl + 0.01}, {0.12, y1 + 0.03, zl + 0.03}, :plastic)
        ],
        [same("hinge", {0.0, y0, zl}, {1, 0, 0}, {0, 1, 0})]
      )

    Assembly.new(
      "freezer_frigidaire_ffcl1542aw",
      Part.new("freezer_box", :body, box ++ feet, [same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})]),
      root: "box",
      kind: :appliance,
      sources: ["Frigidaire FFCL1542AW, 14.8 cu ft: 55 3/4 by 29 9/16 by 32 1/2 in (Best Buy, the size of DIY)."]
    )
    |> Assembly.add(
      "basket",
      Part.new("freezer_basket", :basket, basket, [same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})], inside: true),
      at: Kit.same("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0}),
      port: "o"
    )
    |> Assembly.add("lid", lid,
      at: Kit.same("hinge", {0.0, y0, zl}, {1, 0, 0}, {0, 1, 0}),
      port: "hinge",
      kind: :turns,
      role: :lid,
      limits: [0, 80]
    )
  end
end
