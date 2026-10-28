defmodule Xuong.Models.VanBuilds do
  @moduledoc """
  Builds of wood for a camper van, as a person makes them: lumber and
  plywood at their real sizes, with each wood screw. The list of the parts
  of a build is its list of the things to buy: the pieces of lumber by
  their lengths, the sheets by their sizes, the screws by their counts.

  - `van_bed_platform`: a bed across a Ford Transit 148 in with a high
    roof, 70 by 60 in, its top at 38 in, with the garage under it.
  - `van_galley`: a galley of 48 in, 20 in deep and 36 in high: a
    carcass of plywood, a counter of butcher block with a sink, drawers
    that slide and a door.
  """
  alias Xuong.{Assembly, Part, Shape, Vec}
  alias Xuong.Models.Kit
  alias Xuong.Parts.{Fasteners, Stock}
  import Kit, only: [inch: 1, same: 4]

  @origin Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  # Put a part with its axes at a point: its x along `x`, its z along `z`.
  defp put(asm, name, part, at, x, z),
    do: Assembly.add(asm, name, part, at: Part.port(name, at, z, Vec.cross(z, x)), port: @origin)

  # A wood screw at a point, into the wood along `dir`.
  defp screw(asm, name, gauge, length, at, dir) do
    up = if abs(elem(dir, 2)) > 0.9, do: {0, 1, 0}, else: {0, 0, 1}
    Assembly.add(asm, name, Fasteners.wood_screw(gauge, length), at: Part.port(name, at, dir, up), port: "head")
  end

  defp screws(asm, prefix, gauge, length, points, dir) do
    points
    |> Enum.with_index(1)
    |> Enum.reduce(asm, fn {p, i}, asm -> screw(asm, "#{prefix}_#{i}", gauge, length, p, dir) end)
  end

  # --- The bed platform ----------------------------------------------------------

  @doc "A bed platform of 2x3 lumber and plywood of 1/2 in: 70 by 60 in, the top at 38 in."
  def bed_platform do
    {w, d, top} = {inch(70), inch(60), inch(38)}
    {t, b} = Stock.table(:lumber, "2x3")
    ply = inch(0.5)
    {x0, x1, y0, y1} = {-w / 2, w / 2, -d / 2, d / 2}
    zr = top - ply - b
    joist_len = d - 2 * t
    joists = [x0, x0 + inch(17.5), -t / 2, x1 - inch(17.5) - t, x1 - t]

    asm =
      Assembly.new("van_bed_platform", Part.new("bed_origin", :mark, [], [@origin]),
        root: "origin",
        kind: :furniture,
        sources: [
          "A bed across a Ford Transit 148 in with a high roof: 70 in wide (the cargo width, DIY), 60 in deep, the top at 38 in. 2x3 lumber (1.5 by 2.5 in, PS 20) and plywood of 1/2 in."
        ]
      )
      |> put("rail_front", Stock.lumber("2x3", w), {x0, y1, zr}, {1, 0, 0}, {0, -1, 0})
      |> put("rail_back", Stock.lumber("2x3", w), {x0, y0 + t, zr}, {1, 0, 0}, {0, -1, 0})

    asm =
      joists
      |> Enum.with_index(1)
      |> Enum.reduce(asm, fn {x, i}, asm ->
        put(asm, "joist_#{i}", Stock.lumber("2x3", joist_len), {x, y0 + t, zr}, {0, 1, 0}, {1, 0, 0})
      end)

    # The legs stand under the rails: the wide side along the rail.
    legs = for x <- [x0, -b / 2, x1 - b], y <- [y0, y1 - t], do: {x, y}

    asm =
      legs
      |> Enum.with_index(1)
      |> Enum.reduce(asm, fn {{x, y}, i}, asm ->
        put(asm, "leg_#{i}", Stock.lumber("2x3", zr), {x, y, 0.0}, {0, 0, 1}, {0, 1, 0})
      end)

    # The plywood: two sheets, each half of the width.
    asm =
      asm
      |> put("top_left", Stock.sheet(w / 2, d, ply, :plywood), {x0, y0, zr + b}, {1, 0, 0}, {0, 0, 1})
      |> put("top_right", Stock.sheet(w / 2, d, ply, :plywood), {0.0, y0, zr + b}, {1, 0, 0}, {0, 0, 1})

    # Two screws through a rail into the end of each joist; two screws
    # down through a rail into each leg; screws through the plywood into
    # the joists, 5 along each joist.
    joist_screws =
      for x <- joists,
          {y, dir} <- [{y1, {0, -1, 0}}, {y0, {0, 1, 0}}],
          z <- [zr + b * 0.3, zr + b * 0.7],
          do: {{x + t / 2, y, z}, dir}

    leg_screws = for {x, y} <- legs, dx <- [0.3, 0.7], do: {x + b * dx, y + t / 2, zr + b}
    ply_screws = for x <- joists, k <- 0..4, do: {x + t / 2, y0 + t + 0.05 + k * (joist_len - 0.1) / 4, zr + b + ply}

    asm =
      Enum.reduce(Enum.with_index(joist_screws, 1), asm, fn {{p, dir}, i}, asm ->
        screw(asm, "joist_screw_#{i}", "#8", inch(2.5), p, dir)
      end)

    asm
    |> screws("leg_screw", "#10", inch(4), leg_screws, {0, 0, -1})
    |> screws("top_screw", "#8", inch(1.25), ply_screws, {0, 0, -1})
  end

  # --- The galley ----------------------------------------------------------------

  @doc """
  A galley of 48 in: a carcass of plywood of 3/4 in on a toe kick of 3 in,
  a counter of butcher block of 1 1/2 in with a sink of 13 by 15 in, three
  drawers at the left, and a door at the right.
  """
  def galley do
    {w, d, h} = {inch(48), inch(20), inch(36)}
    p = inch(0.75)
    {x0, x1, y0, y1} = {-w / 2, w / 2, -d / 2, d / 2}
    {kick, ztop} = {inch(3), h - inch(1.5)}
    xm = x0 + inch(22)
    side_h = ztop

    sheet = fn w, d -> Stock.sheet(w, d, p, :plywood) end

    asm =
      Assembly.new("van_galley", Part.new("galley_origin", :mark, [], [@origin]),
        root: "origin",
        kind: :furniture,
        sources: [
          "A galley of a van: 48 by 20 by 36 in, a common size. Plywood of 3/4 in, a counter of butcher block of 1 1/2 in, a sink of 13 by 15 in."
        ]
      )
      |> put("side_left", sheet.(d, side_h), {x0, y0, 0.0}, {0, 1, 0}, {1, 0, 0})
      |> put("side_right", sheet.(d, side_h), {x1 - p, y0, 0.0}, {0, 1, 0}, {1, 0, 0})
      |> put("divider", sheet.(d - p, side_h - kick - p), {xm, y0 + inch(0.25), kick + p}, {0, 1, 0}, {1, 0, 0})
      |> put("bottom", sheet.(w - 2 * p, d - inch(0.25)), {x0 + p, y0 + inch(0.25), kick}, {1, 0, 0}, {0, 0, 1})
      |> put("toe_kick", sheet.(w - 2 * p, kick), {x0 + p, y1 - inch(3), 0.0}, {1, 0, 0}, {0, -1, 0})
      |> put(
        "back",
        Stock.sheet(w - 2 * p, side_h - kick, inch(0.25), :plywood),
        {x0 + p, y0 + inch(0.25), kick},
        {1, 0, 0},
        {0, -1, 0}
      )

    # The counter, with the hole of the sink.
    {sx, sy, sw, sd} = {x1 - inch(14) - inch(13) / 2, -inch(0.5), inch(13), inch(15)}

    counter =
      Part.new(
        "butcher_block_49x21",
        :counter,
        Kit.holed_slab(
          {x0 - inch(0.5), y0, ztop},
          {x1 + inch(0.5), y1 + inch(1), h},
          {sx - sw / 2, sy - sd / 2},
          {sx + sw / 2, sy + sd / 2},
          :wood
        ),
        [@origin],
        sources: ["A counter of butcher block: 49 by 21 by 1 1/2 in."]
      )

    sink =
      Part.new(
        "sink_13x15",
        :sink,
        Kit.cavity(
          {sx - sw / 2, sy - sd / 2, ztop - inch(6)},
          {sx + sw / 2, sy + sd / 2, h + 0.004},
          0.002,
          :stainless,
          :top
        ) ++
          [
            Shape.box(
              {sx - sw / 2 - 0.012, sy - sd / 2 - 0.012, h},
              {sx + sw / 2 + 0.012, sy + sd / 2 + 0.012, h + 0.003},
              :stainless
            )
          ],
        [@origin],
        sources: ["A sink of stainless steel: 13 by 15 in, 6 in deep."]
      )

    faucet =
      Part.new(
        "faucet",
        :faucet,
        [
          Shape.sweep(
            [{sx, y0 + 0.04, h}, {sx, y0 + 0.04, h + 0.3}, {sx, y0 + 0.2, h + 0.3}, {sx, y0 + 0.2, h + 0.24}],
            0.012,
            :chrome,
            sides: 10
          )
        ],
        [same("swivel", {sx, y0 + 0.04, h}, {0, 0, 1}, {0, 1, 0})],
        detail: :always
      )

    asm =
      asm
      |> Assembly.add("counter", counter, at: @origin, port: @origin)
      |> Assembly.add("sink", sink, at: @origin, port: @origin)
      |> Assembly.add("faucet", faucet,
        at: Kit.same("swivel", {sx, y0 + 0.04, h}, {0, 0, 1}, {0, 1, 0}),
        port: "swivel",
        kind: :turns,
        role: :knob,
        limits: [-90, 90]
      )

    # Three drawers at the left, a door at the right.
    zs = [kick + p, kick + inch(9.5), kick + inch(19.5), ztop - inch(0.25)]

    asm =
      zs
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.with_index(1)
      |> Enum.reduce(asm, fn {[za, zb], i}, asm ->
        Assembly.add(asm, "drawer_#{i}", drawer("drawer_#{i}", x0 + p, xm, y0 + inch(1), y1, za, zb),
          at: Kit.same("slide_drawer_#{i}", {(x0 + p + xm) / 2, y1, za}, {0, 1, 0}, {0, 0, 1}),
          port: "slide_drawer_#{i}",
          kind: :slides,
          role: :drawer,
          limits: [0, inch(16)]
        )
      end)

    door =
      Part.new(
        "galley_door",
        :door,
        [
          Shape.box({xm + p + 0.002, y1, kick + 0.003}, {x1 - p - 0.002, y1 + p, ztop - 0.006}, :plywood),
          Kit.handle(
            {xm + p + 0.04, y1 + p, ztop - 0.25},
            {xm + p + 0.04, y1 + p, ztop - 0.1},
            {0, 1, 0},
            0.025,
            0.005,
            :black
          )
        ],
        [same("hinge", {x1 - p, y1, kick}, {0, 0, -1}, {0, 1, 0})]
      )

    asm =
      Assembly.add(asm, "door", door,
        at: Kit.same("hinge", {x1 - p, y1, kick}, {0, 0, -1}, {0, 1, 0}),
        port: "hinge",
        kind: :turns,
        role: :door,
        limits: [0, 110]
      )

    # Screws: through each side into the bottom, and up through the bottom
    # into the divider, 3 for each joint.
    side_screws =
      for {x, dir} <- [{x0, {1, 0, 0}}, {x1, {-1, 0, 0}}],
          k <- 0..2,
          do: {{x, y0 + 0.05 + k * (d - 0.1) / 2, kick + p / 2}, dir}

    bottom_screws = for k <- 0..2, do: {{xm + p / 2, y0 + 0.05 + k * (d - 0.1) / 2, kick}, {0, 0, 1}}

    Enum.reduce(Enum.with_index(side_screws ++ bottom_screws, 1), asm, fn {{pt, dir}, i}, asm ->
      screw(asm, "carcass_screw_#{i}", "#8", inch(1.5), pt, dir)
    end)
  end

  # A drawer: a box of plywood of 1/2 in and its front of 3/4 in.
  defp drawer(name, xa, xb, ya, yb, za, zb) do
    q = inch(0.5)
    port = same("slide_" <> name, {(xa + xb) / 2, yb, za}, {0, 1, 0}, {0, 0, 1})
    {xa, xb, za, zb} = {xa + 0.012, xb - 0.012, za + 0.004, zb - 0.004}
    box = Kit.cavity({xa + 0.01, ya, za + 0.01}, {xb - 0.01, yb, zb - 0.02}, q, :plywood, :top)

    front = [
      Shape.box({xa - 0.01, yb, za - 0.002}, {xb + 0.01, yb + inch(0.75), zb + 0.002}, :plywood),
      Kit.handle(
        {(xa + xb) / 2 - 0.06, yb + inch(0.75), zb - 0.04},
        {(xa + xb) / 2 + 0.06, yb + inch(0.75), zb - 0.04},
        {0, 1, 0},
        0.025,
        0.005,
        :black
      )
    ]

    Part.new(name, :drawer, box ++ front, [port])
  end
end
