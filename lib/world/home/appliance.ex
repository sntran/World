defmodule World.Home.Appliance do
  @moduledoc """
  An appliance or a part of the power system of a home, from its kind
  and its size (`docs/plans/0019-world-serves-the-projects.md`, step 5;
  for DIY): a body of the right size with the details of the real
  thing, so that a person knows it: the doors and the handles of a
  fridge, the knobs and the window of a range, the round door of a
  washer, the terminals of a battery, a stud for each port of a busbar.

  `drawing/1` gives a model of one part from edits
  (`World.Skills.Sculpt`). The middle of the thing is at x = 0 and
  y = 0, it stands on z = 0, and its front is to +y.

  The size of a kind with no size in the request is a common size of
  the kind, as a guess: a project gives the size of the real product.
  """

  alias World.Town.Wall

  @steel "#c9ccd0"
  @white "#eceeed"
  @black "#1e2022"
  @glass "#27323a"
  @metal %{"roughness" => 0.35, "metal" => 0.8}
  @paint %{"roughness" => 0.5}
  @dark %{"roughness" => 0.4}

  # Each kind: its common size [wide, deep, high] (m) and the color of its body.
  @kinds %{
    "fridge" => {[0.91, 0.84, 1.78], @steel},
    "freezer" => {[1.12, 0.6, 0.85], @white},
    "range" => {[0.76, 0.66, 0.92], @steel},
    "microwave" => {[0.55, 0.42, 0.31], @steel},
    "dishwasher" => {[0.6, 0.6, 0.86], @steel},
    "washer" => {[0.69, 0.76, 0.99], @white},
    "dryer" => {[0.69, 0.76, 0.99], @white},
    "water_heater" => {[0.56, 0.56, 1.5], @white},
    "tv" => {[1.12, 0.06, 0.65], @black},
    "battery" => {[0.33, 0.17, 0.22], "#2d4f8a"},
    "power_station" => {[0.56, 0.38, 0.43], "#3a3d40"},
    "inverter" => {[0.38, 0.22, 0.12], "#2f5f9e"},
    "solar_panel" => {[1.13, 1.72, 0.035], "#1c2b4a"},
    "busbar" => {[0.2, 0.05, 0.04], "#b23a2e"},
    "water_tank" => {[0.64, 0.36, 0.39], "#e9e6da"},
    "box" => {[0.5, 0.4, 0.4], @white}
  }

  @doc "The kinds of an appliance."
  def kinds, do: @kinds |> Map.keys() |> Enum.sort()

  @doc """
  The request with each choice made. A key that has a value keeps it; a
  value that is not possible raises an `ArgumentError`.

    * `kind`: one of `kinds/0` (`box`: a plain body).
    * `name` (small letters, digits and `_`) and `sources` (lines of
      text).
    * `size`: `[wide, deep, high]` (m), each from 0.01 to 5. Without it,
      the common size of the kind.
    * `color`: the color of the body.
    * `doors` of a fridge: `french` (two doors over a drawer), `top` (a
      small door over a large one) or `single`.
    * `ports`: the studs of a busbar, 1 to 24 (4).
  """
  def request(opts \\ %{}) do
    need(is_map(opts), "the request of an appliance is a map")

    case Map.keys(opts) -- ~w(kind name sources size color doors ports) do
      [] ->
        :ok

      [key | _] ->
        raise(
          ArgumentError,
          "an appliance has no key #{inspect(key)}: its keys are kind, name, sources, size, color, doors, ports"
        )
    end

    kind = Map.get(opts, "kind", "box")
    need(is_map_key(@kinds, kind), "the kind of an appliance is one of #{Enum.join(kinds(), ", ")}")
    {size, color} = @kinds[kind]
    name = Map.get(opts, "name", kind)
    need(is_binary(name) and name =~ ~r/^[a-z][a-z0-9_]*$/, "the name of an appliance has small letters, digits and _")
    sources = Map.get(opts, "sources", [])
    need(is_list(sources) and Enum.all?(sources, &is_binary/1), "the sources of an appliance are lines of text")
    size = Map.get(opts, "size", size)

    need(
      match?([_, _, _], size) and Enum.all?(size, &(is_number(&1) and &1 >= 0.01 and &1 <= 5)),
      "the size of an appliance is [wide, deep, high], each from 0.01 m to 5 m"
    )

    color = Map.get(opts, "color", color)
    need(is_binary(color) and color =~ ~r/^#[0-9a-f]{6}$/, "the color of an appliance is as #a1b2c3 (small letters)")
    doors = Map.get(opts, "doors", "french")
    need(doors in ~w(french top single), "the doors of a fridge are french, top or single")
    ports = Map.get(opts, "ports", 4)
    need(is_integer(ports) and ports in 1..24, "a busbar has from 1 to 24 ports")

    %{
      "kind" => kind,
      "name" => name,
      "sources" => sources,
      "size" => Enum.map(size, &(&1 * 1.0)),
      "color" => color,
      "doors" => doors,
      "ports" => ports
    }
  end

  defp need(true, _text), do: :ok
  defp need(false, text), do: raise(ArgumentError, text)

  @doc """
  The drawing of the appliance of a request (`request/1`): one part from
  edits, with its cells from its size. The extras have the request
  (`appliance`) and `tags`: the place of the label of the real thing
  (`[x, y, z]`, on its right side or its back), for a project that
  shows a number there.
  """
  def drawing(request \\ %{}) do
    r = request(request)
    [w, d, h] = r["size"]
    # (Cells for the thin details of a small thing, and not too many cells for a large one.)
    cell = min(max(Enum.min([w, d, h]) / 12, 0.004), 0.02)
    levels = fn list -> Map.new(Enum.zip(~w(near mid far), list)) end
    budget = [8_000, 2_000, 400]

    data = %{
      "edits" => Enum.map(edits(r), &Map.put(&1, "material", "part_01")),
      "cells" => levels.([r4(cell), r4(cell * 2), r4(cell * 4)]),
      "budget" => levels.(budget),
      "bake" => levels.(Enum.zip_with(budget, [1024, 512, 128], &image/2)),
      "dirt" => 0.1,
      "wear" => 0.05
    }

    %{
      "name" => r["name"],
      "kind" => "prop",
      "sources" => r["sources"],
      "materials" => %{"part_01" => %{"color" => "#ffffff", "roughness" => 0.6, "metalness" => 0.0}},
      "extras" => %{"appliance" => r, "tags" => %{"label" => [r4(w / 2), r4(-d / 4), r4(h * 0.75)]}},
      "nodes" => [%{"name" => "#{r["name"]}_than", "skill" => %{"sculpt" => data}}]
    }
  end

  defp image(budget, side),
    do: Enum.find([64, 128, 256, 512, 1024, 2048, 4096], &(&1 >= max(side, World.Sculpt.Bake.least(budget))))

  # --- The edits of each kind ---------------------------------------------------------

  defp edits(%{"kind" => kind, "size" => [w, d, h], "color" => color} = r) do
    # The front of the thing as a wall: the way along it from the left to the right, and the height.
    front = Wall.new([w / 2, d / 2], [-w / 2, d / 2])
    kind(kind, r, {w, d, h}, color, front)
  end

  # The body: a box with round edges, from `z0` up to `z1`.
  defp body({w, d, _h}, z0, z1, color, look \\ @paint) do
    round = min(0.012, Enum.min([w, d, z1 - z0]) / 8)
    Wall.edit("round_box", [r4(w / 2), r4(d / 2), r4((z1 - z0) / 2), r4(round)], [0, 0, r4((z0 + z1) / 2)], color, look)
  end

  # The thin dark line round a door or a drawer on the front.
  defp seam(front, s0, s1, z0, z1) do
    line = %{"raise" => -0.003, "blend" => 0.003, "roughness" => 0.6}

    for {s, z, wide, high} <- [
          {(s0 + s1) / 2, z0, s1 - s0, 0.006},
          {(s0 + s1) / 2, z1, s1 - s0, 0.006},
          {s0, (z0 + z1) / 2, 0.006, z1 - z0},
          {s1, (z0 + z1) / 2, 0.006, z1 - z0}
        ] do
      Wall.paint(front, s, z, {wide, high}, "#4a4d50", line)
    end
  end

  # A handle: a bar that stands 4 cm out of the front, upright or level.
  defp handle(front, s, z, long, upright?) do
    size = if upright?, do: {0.022, long, 0.022}, else: {long, 0.022, 0.022}

    ends =
      if upright?,
        do: [{s, z - long / 2 + 0.03}, {s, z + long / 2 - 0.03}],
        else: [{s - long / 2 + 0.03, z}, {s + long / 2 - 0.03, z}]

    [Wall.box(front, s, z, size, "#b8bbbe", Map.put(@metal, "out", 0.045))] ++
      for({ps, pz} <- ends, do: Wall.box(front, ps, pz, {0.022, 0.022, 0.04}, "#b8bbbe", Map.put(@metal, "out", 0.02)))
  end

  # A knob that stands out of the front.
  defp knob(front, s, z, radius) do
    Wall.edit(
      "cylinder",
      [r4(radius), 0.012],
      Wall.at(front, s, z, 0.012),
      "#2c2e30",
      Map.merge(@dark, %{"axis" => Wall.axis(front)})
    )
  end

  # A flat dark part of the front: a window, a screen, a panel of keys.
  defp panel(front, s, z, {wide, high}, color \\ @glass),
    do: Wall.paint(front, s, z, {wide, high}, color, %{"raise" => -0.002, "roughness" => 0.15, "metal" => 0.3})

  # Four low feet under a thing.
  defp feet({w, d, _h}, high) do
    for sx <- [-1, 1], sy <- [-1, 1] do
      Wall.edit(
        "cylinder",
        [0.02, r4(high / 2)],
        [r4(sx * (w / 2 - 0.05)), r4(sy * (d / 2 - 0.05)), r4(high / 2)],
        @black,
        @dark
      )
    end
  end

  defp kind("fridge", r, {w, _d, h} = size, color, front) do
    base = [body(size, 0.04, h, color, @metal) | feet(size, 0.04)]
    {lo, hi, a, b} = {0.06, h - 0.02, 0.012, w - 0.012}

    doors =
      case r["doors"] do
        "french" ->
          # Two doors side by side over a wide drawer, each door with its handle at the middle.
          cut = h * 0.42

          seam(front, a, w / 2 - 0.003, cut + 0.006, hi) ++
            seam(front, w / 2 + 0.003, b, cut + 0.006, hi) ++
            seam(front, a, b, lo, cut - 0.006) ++
            handle(front, w / 2 - 0.05, (cut + hi) / 2, (hi - cut) * 0.55, true) ++
            handle(front, w / 2 + 0.05, (cut + hi) / 2, (hi - cut) * 0.55, true) ++
            handle(front, w / 2, cut - 0.1, w * 0.7, false)

        "top" ->
          cut = h * 0.7

          seam(front, a, b, cut + 0.006, hi) ++
            seam(front, a, b, lo, cut - 0.006) ++
            handle(front, 0.07, cut + 0.16, 0.22, true) ++ handle(front, 0.07, cut - 0.3, 0.4, true)

        "single" ->
          seam(front, a, b, lo, hi) ++ handle(front, 0.07, h * 0.6, h * 0.35, true)
      end

    base ++ doors
  end

  # A chest freezer: a lid on its top, with a handle at its front edge.
  defp kind("freezer", _r, {w, d, h} = size, color, front) do
    [
      body(size, 0.03, h - 0.07, color),
      Wall.edit(
        "round_box",
        [r4(w / 2 + 0.008), r4(d / 2 + 0.008), 0.03, 0.01],
        [0, 0, r4(h - 0.03)],
        shade(color, 0.96),
        @paint
      )
      | feet(size, 0.03) ++ handle(front, w / 2, h - 0.04, w * 0.3, false)
    ]
  end

  # A range: burners on its top, a back panel with knobs, an oven door with a window and a handle.
  defp kind("range", _r, {w, d, h} = size, color, front) do
    top = h - 0.09

    burners =
      for sx <- [-1, 1], sy <- [-1, 1] do
        Wall.edit(
          "cylinder",
          [r4(w * 0.11), 0.006],
          [r4(sx * w * 0.22), r4(sy * d * 0.2 - 0.02), r4(top + 0.004)],
          @black,
          @dark
        )
      end

    [
      body(size, 0.0, top, color, @metal),
      Wall.edit("box", [r4(w / 2), 0.025, 0.045], [0, r4(-d / 2 + 0.025), r4(h - 0.045)], color, @metal)
    ] ++
      burners ++
      for(i <- 0..4, do: knob(front, w * (0.14 + 0.18 * i), top - 0.05, 0.02)) ++
      seam(front, 0.02, w - 0.02, 0.16, top - 0.11) ++
      [panel(front, w / 2, (0.16 + top - 0.11) / 2 - 0.02, {w * 0.62, (top - 0.27) * 0.5})] ++
      handle(front, w / 2, top - 0.15, w * 0.8, false) ++ seam(front, 0.02, w - 0.02, 0.02, 0.14)
  end

  # A microwave: a door with a window, and a panel of keys at its right.
  defp kind("microwave", _r, {w, _d, h} = size, color, front) do
    cut = w * 0.72

    [body(size, 0.01, h, color, @metal) | feet(size, 0.01)] ++
      seam(front, 0.01, cut, 0.02, h - 0.02) ++
      [
        panel(front, cut / 2, h / 2, {cut * 0.78, h * 0.6}),
        panel(front, (cut + w) / 2, h * 0.72, {(w - cut) * 0.7, h * 0.14}, "#0d1f14")
      ] ++
      for(
        i <- 0..2,
        j <- 0..3,
        do:
          Wall.paint(
            front,
            cut + (w - cut) * (0.27 + 0.23 * i),
            h * (0.5 - 0.1 * j),
            {(w - cut) * 0.16, h * 0.06},
            "#3a3d40"
          )
      ) ++
      handle(front, cut - 0.03, h / 2, h * 0.6, true)
  end

  # A dishwasher: one door with a handle, and a strip of controls at its top.
  defp kind("dishwasher", _r, {w, _d, h} = size, color, front) do
    [
      body(size, 0.1, h, color, @metal),
      Wall.edit("box", [r4(w / 2 - 0.02), 0.2, 0.05], [0, -0.05, 0.05], @black, @dark)
    ] ++
      seam(front, 0.01, w - 0.01, 0.11, h - 0.12) ++
      [panel(front, w / 2, h - 0.06, {w * 0.9, 0.07}, @black)] ++ handle(front, w / 2, h - 0.17, w * 0.75, false)
  end

  # A washer and a dryer: a round door of glass, and a panel of controls at the top.
  defp kind(kind, _r, {w, _d, h} = size, color, front) when kind in ["washer", "dryer"] do
    radius = min(w, h) * 0.3
    at = Wall.at(front, w / 2, h * 0.45, 0.0)
    out = %{"axis" => Wall.axis(front)}

    [body(size, 0.03, h, color) | feet(size, 0.03)] ++
      [
        Wall.edit("cylinder", [r4(radius), 0.03], at, "#b8bbbe", Map.merge(@metal, out)),
        Wall.edit(
          "cylinder",
          [r4(radius * 0.74), 0.034],
          at,
          if(kind == "washer", do: @glass, else: "#3a3d40"),
          Map.merge(out, %{"roughness" => 0.1, "metal" => 0.3})
        ),
        panel(front, w / 2, h - 0.08, {w * 0.9, 0.1}, "#d4d6d8"),
        panel(front, w * 0.72, h - 0.08, {w * 0.2, 0.06}, "#0d1f14"),
        knob(front, w * 0.3, h - 0.08, 0.03)
      ]
  end

  # A water heater: a tank that stands, with two pipes and a valve on its top.
  defp kind("water_heater", _r, {w, d, h}, color, front) do
    radius = min(w, d) / 2

    [
      Wall.edit("cylinder", [r4(radius), r4(h * 0.46)], [0, 0, r4(h * 0.46 + 0.02)], color, @paint),
      Wall.edit("ellipsoid", [r4(radius), r4(radius), r4(h * 0.06)], [0, 0, r4(h * 0.94)], color, @paint),
      Wall.edit("cylinder", [r4(radius * 0.9), 0.02], [0, 0, 0.02], @black, @dark),
      Wall.edit("cylinder", [0.014, r4(h * 0.03)], [r4(-radius * 0.45), 0, r4(h * 0.985)], "#b06a3c", @metal),
      Wall.edit("cylinder", [0.014, r4(h * 0.03)], [r4(radius * 0.45), 0, r4(h * 0.985)], "#b06a3c", @metal),
      Wall.box(front, w / 2, h * 0.22, {0.14, 0.2, 0.05}, "#d4d6d8", Map.put(@paint, "out", radius - d / 2 + 0.02)),
      knob(Wall.out(front, radius - d / 2 + 0.045), w / 2, h * 0.22, 0.03)
    ]
  end

  # A television: a thin panel with a dark screen, on a stand.
  defp kind("tv", _r, {w, d, h}, color, front) do
    [
      Wall.edit(
        "round_box",
        [r4(w / 2), r4(max(d, 0.03) / 2), r4(h * 0.46), 0.006],
        [0, 0, r4(h * 0.54)],
        color,
        @dark
      ),
      panel(Wall.out(front, max(d, 0.03) / 2 - d / 2), w / 2, h * 0.55, {w - 0.03, h * 0.86}, "#0b0f14"),
      Wall.edit("box", [0.03, 0.02, r4(h * 0.05)], [0, 0, r4(h * 0.05)], @black, @dark),
      Wall.edit("round_box", [r4(w * 0.22), r4(max(d * 2, 0.11)), 0.008, 0.004], [0, 0, 0.008], @black, @dark)
    ]
  end

  # A battery: a box with a lid, a handle, a label, and two terminals on its top (red and black).
  defp kind("battery", _r, {w, d, h} = size, color, front) do
    [
      body(size, 0.0, h * 0.86, color),
      Wall.edit(
        "round_box",
        [r4(w / 2), r4(d / 2), r4(h * 0.07), 0.004],
        [0, 0, r4(h * 0.93)],
        shade(color, 0.75),
        @paint
      ),
      Wall.paint(front, w / 2, h * 0.45, {w * 0.7, h * 0.4}, "#f2f2ee", %{"roughness" => 0.6}),
      Wall.edit("cylinder", [r4(d * 0.09), r4(h * 0.05)], [r4(-w * 0.36), 0, r4(h * 1.0)], "#b3261e", @metal),
      Wall.edit("cylinder", [r4(d * 0.09), r4(h * 0.05)], [r4(w * 0.36), 0, r4(h * 1.0)], @black, @metal),
      Wall.tube(
        [
          [r4(-w * 0.18), 0, r4(h)],
          [r4(-w * 0.1), 0, r4(h * 1.12)],
          [r4(w * 0.1), 0, r4(h * 1.12)],
          [r4(w * 0.18), 0, r4(h)]
        ],
        List.duplicate(r4(d * 0.045), 4),
        @black,
        @dark
      )
    ]
  end

  # A power station: a box with a handle at each end of its top, and a front with a screen and outlets.
  defp kind("power_station", _r, {w, d, h} = size, color, front) do
    handles =
      for sx <- [-1, 1] do
        x = sx * (w / 2 - 0.035)

        Wall.tube(
          [
            [r4(x), r4(-d * 0.3), r4(h * 0.9)],
            [r4(x), r4(-d * 0.3), r4(h)],
            [r4(x), r4(d * 0.3), r4(h)],
            [r4(x), r4(d * 0.3), r4(h * 0.9)]
          ],
          List.duplicate(0.014, 4),
          @black,
          @dark
        )
      end

    outlets = for i <- 0..3, do: panel(front, w * (0.2 + 0.2 * i), h * 0.3, {w * 0.12, h * 0.16}, "#101214")

    [body(size, 0.01, h * 0.92, color) | feet(size, 0.01)] ++
      handles ++
      [
        panel(front, w / 2, h * 0.62, {w * 0.5, h * 0.2}, "#0d1f14"),
        Wall.paint(front, w / 2, h * 0.8, {w * 0.8, 0.012}, "#e0a020")
      ] ++ outlets
  end

  # An inverter: a low box with cooling fins on its top, and two terminals at one end.
  defp kind("inverter", _r, {w, d, h} = size, color, _front) do
    fins =
      for i <- -4..4,
          do:
            Wall.edit(
              "box",
              [r4(w * 0.42), 0.003, r4(h * 0.1)],
              [0, r4(i * d * 0.09), r4(h * 0.9)],
              shade(color, 0.8),
              @metal
            )

    [
      body(size, 0.0, h * 0.8, color, @metal),
      Wall.edit(
        "cylinder",
        [0.008, 0.012],
        [r4(w / 2 + 0.01), r4(-d * 0.2), r4(h * 0.4)],
        "#b3261e",
        Map.put(@metal, "axis", [1, 0, 0])
      ),
      Wall.edit(
        "cylinder",
        [0.008, 0.012],
        [r4(w / 2 + 0.01), r4(d * 0.2), r4(h * 0.4)],
        @black,
        Map.put(@metal, "axis", [1, 0, 0])
      )
      | fins
    ]
  end

  # A solar panel: a thin flat panel in a frame, with the lines of its cells.
  defp kind("solar_panel", _r, {w, d, h}, color, _front) do
    line = %{"mode" => "paint", "raise" => -0.001, "blend" => 0.002}
    {columns, rows} = {max(2, round(w / 0.19)), max(2, round(d / 0.19))}

    [
      Wall.edit("box", [r4(w / 2), r4(d / 2), r4(h / 2)], [0, 0, r4(h / 2)], "#c9ccd0", @metal),
      Wall.edit("box", [r4(w / 2 - 0.02), r4(d / 2 - 0.02), 0.004], [0, 0, r4(h)], color, %{
        "roughness" => 0.15,
        "metal" => 0.4
      })
    ] ++
      for(
        i <- 1..(columns - 1),
        do: Wall.edit("box", [0.002, r4(d / 2 - 0.02), 0.01], [r4(-w / 2 + w * i / columns), 0, r4(h)], "#9aa7b5", line)
      ) ++
      for(
        j <- 1..(rows - 1),
        do: Wall.edit("box", [r4(w / 2 - 0.02), 0.002, 0.01], [0, r4(-d / 2 + d * j / rows), r4(h)], "#9aa7b5", line)
      )
  end

  # A busbar: a base with a bar of copper, a stud with a nut for each port, and a hood at each end.
  defp kind("busbar", r, {w, d, h}, color, _front) do
    ports = r["ports"]

    studs =
      for i <- 0..(ports - 1), x = -w / 2 + w * (i + 0.5) / ports do
        [
          Wall.edit(
            "cylinder",
            [r4(min(d * 0.12, w / ports * 0.2)), r4(h * 0.3)],
            [r4(x), 0, r4(h * 0.75)],
            "#c9ccd0",
            @metal
          ),
          Wall.edit(
            "prism",
            [r4(min(d * 0.22, w / ports * 0.36)), r4(h * 0.08), 6],
            [r4(x), 0, r4(h * 0.62)],
            "#b8bbbe",
            @metal
          )
        ]
      end

    [
      Wall.edit("box", [r4(w / 2 + 0.012), r4(d / 2), r4(h * 0.15)], [0, 0, r4(h * 0.15)], @black, @dark),
      Wall.edit("box", [r4(w / 2), r4(d * 0.3), r4(h * 0.12)], [0, 0, r4(h * 0.42)], "#b87333", @metal),
      Wall.edit("box", [0.006, r4(d / 2), r4(h * 0.5)], [r4(-w / 2 - 0.006), 0, r4(h * 0.5)], color, @paint),
      Wall.edit("box", [0.006, r4(d / 2), r4(h * 0.5)], [r4(w / 2 + 0.006), 0, r4(h * 0.5)], color, @paint)
      | List.flatten(studs)
    ]
  end

  # A water tank: a body with round edges, a cap on its top and an outlet low at its front.
  defp kind("water_tank", _r, {w, d, h} = size, color, front) do
    [
      Wall.edit(
        "round_box",
        [r4(w / 2), r4(d / 2), r4(h / 2), r4(Enum.min([w, d, h]) * 0.12)],
        [0, 0, r4(h / 2)],
        color,
        %{"roughness" => 0.4}
      ),
      Wall.edit("cylinder", [r4(Enum.min([w, d]) * 0.12), 0.015], [r4(-w * 0.25), 0, r4(h + 0.01)], "#2d4f8a", @paint),
      Wall.edit(
        "cylinder",
        [0.012, 0.02],
        Wall.at(front, w * 0.8, h * 0.1, 0.015),
        @black,
        Map.put(@dark, "axis", Wall.axis(front))
      )
      | for(
          z <- [0.35, 0.65],
          do:
            Wall.paint(front, w / 2, h * z, {w * 0.9, 0.01}, shade(color, 0.85), %{"raise" => -0.003, "blend" => 0.004})
        )
    ] ++ [body(size, 0.0, 0.01, shade(color, 0.9))]
  end

  defp kind("box", _r, {_w, _d, h} = size, color, _front), do: [body(size, 0.0, h, color)]

  defp r4(v), do: Wall.r4(v)

  # A color, darker by a part.
  defp shade("#" <> hex, part) do
    <<r::8, g::8, b::8>> = Base.decode16!(hex, case: :mixed)
    "#" <> Base.encode16(<<round(r * part), round(g * part), round(b * part)>>, case: :lower)
  end
end
