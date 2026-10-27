defmodule Xuong.Models.PowerStations do
  @moduledoc """
  The power stations of DIY (`DIY.Catalog`, the station models), at the
  sizes of their makers. The look of each station follows the photos of
  its maker, as the drawings of DIY do (`DIYWeb.Icon.StationShapes`):

  - Pecron F5000LFP: a dark box on a trolley with two wheels and a handle
    that slides up.
  - Pecron E3800LFP: a dark box with an orange cap on each corner; the
    ports in orange frames on the top half of its front, ribs on the
    bottom half.
  - EcoFlow DELTA Pro and DELTA Pro 3: the front is the short end. Two
    wheels at the back, a handle that slides out of the bottom of the
    front. The DELTA Pro is black with a gray cap; the DELTA Pro 3 is
    silver with a dark hood at each end.
  - EcoFlow DELTA Pro Ultra: the inverter on its battery, two wide slabs.
  - Anker SOLIX F3800 (and Plus): a tall box of warm gray on wheels, the
    handle at the top of its front, the AC outlets on its right side.
  """
  alias Xuong.{Assembly, Frame, Part, Shape}
  alias Xuong.Models.Kit
  import Kit, only: [inch: 1, mm: 1, same: 4, rbox: 4]

  @o {0, 0, 0}
  defp origin, do: same("o", @o, {0, 0, 1}, {0, 1, 0})

  @doc "Each station as `{name, fun}`."
  def all do
    [
      {"power_station_pecron_f5000lfp", &__MODULE__.pecron_f5000/0},
      {"power_station_pecron_e3800lfp", &__MODULE__.pecron_e3800/0},
      {"power_station_ecoflow_delta_pro", &__MODULE__.delta_pro/0},
      {"power_station_ecoflow_delta_pro_3", &__MODULE__.delta_pro_3/0},
      {"power_station_ecoflow_delta_pro_ultra", &__MODULE__.delta_pro_ultra/0},
      {"power_station_anker_solix_f3800", &__MODULE__.solix_f3800/0},
      {"power_station_anker_solix_f3800_plus", &__MODULE__.solix_f3800_plus/0}
    ]
  end

  # --- The faces of the ports ---------------------------------------------------

  # An AC outlet (NEMA 5-20) on a face that looks to `n` (a unit axis), at
  # `{x, y, z}` (the center of the face of the outlet).
  defp outlet(at, n) do
    f = Frame.new(at, n, if(elem(n, 2) == 0, do: {0, 0, 1}, else: {0, 1, 0}))

    [
      Shape.box({-0.018, -0.022, 0.0}, {0.018, 0.022, 0.004}, :plastic, frame: f),
      Shape.box({-0.008, 0.002, 0.004}, {-0.006, 0.011, 0.005}, :black, frame: f),
      Shape.box({0.006, 0.002, 0.004}, {0.008, 0.011, 0.005}, :black, frame: f),
      Shape.box({-0.002, -0.014, 0.004}, {0.002, -0.008, 0.005}, :black, frame: f)
    ]
  end

  # A row of `n` small ports (USB) on a face that looks to y, from `{x, y, z}`.
  defp usb_row({x, y, z}, n),
    do:
      for(i <- 0..(n - 1), do: Shape.box({x + i * 0.022, y, z}, {x + i * 0.022 + 0.012, y + 0.003, z + 0.006}, :black))

  defp screen({x, y, z}, {w, h}), do: Shape.box({x, y, z}, {x + w, y + 0.003, z + h}, :screen)

  # A wheel of a station: a hub and a tire, its axle along x.
  defp station_wheel(name, r, w) do
    shapes = [
      Shape.lathe([{r * 0.45, -w / 2}, {r, -w / 2 + 0.004}, {r, w / 2 - 0.004}, {r * 0.45, w / 2}], :rubber,
        kind: :ring,
        sides: 24
      ),
      Shape.lathe(
        [{0.0, -w / 2 + 0.003}, {r * 0.47, -w / 2 + 0.003}, {r * 0.47, w / 2 - 0.003}, {0.0, w / 2 - 0.003}],
        :dark, sides: 16)
    ]

    Part.new(name, :wheel, shapes, [same("hub", @o, {0, 0, 1}, {0, 1, 0})], params: %{"diameter" => 2 * r})
  end

  defp add_wheels(asm, x_out, y, r, w) do
    for {side, sx} <- [{"left", -1}, {"right", 1}], reduce: asm do
      asm ->
        at = Part.port("axle_#{side}", {sx * (x_out - w / 2), y, r}, {sx, 0, 0}, {0, 0, 1})

        Assembly.add(asm, "wheel_#{side}", station_wheel("station_wheel_#{round(2000 * r)}", r, w),
          at: at,
          port: "hub",
          kind: :turns,
          role: :wheel
        )
    end
  end

  # --- Pecron ---------------------------------------------------------------------

  @doc "The Pecron F5000LFP on its trolley: 21.7 by 15 by 13.1 in, near 17 in high on the trolley."
  def pecron_f5000 do
    {w, d, hb} = {inch(21.7), inch(15), inch(13.1)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -d / 2, d / 2}
    z0 = inch(17) - hb

    body =
      [
        rbox({x0, y0, z0}, {x1, y1, z0 + hb}, :dark, 0.04),
        rbox({x0 + 0.02, y1 - 0.004, z0 + hb * 0.45}, {x1 - 0.02, y1 + 0.006, z0 + hb - 0.02}, :black, 0.05),
        screen({-0.06, y1 + 0.006, z0 + hb - 0.09}, {0.12, 0.06})
      ] ++
        usb_row({x0 + 0.05, y1 + 0.006, z0 + hb - 0.08}, 4) ++
        Enum.flat_map([-0.18, -0.12, 0.12, 0.18], &outlet({&1, y1 + 0.006, z0 + hb * 0.62}, {0, 1, 0})) ++
        for(
          x <- [x0 + 0.03, x1 - 0.13],
          do: rbox({x, y0 - 0.01, z0 + hb - 0.05}, {x + 0.1, y0 + 0.01, z0 + hb - 0.02}, :black, 0.2)
        )

    # The trolley: a frame of steel tubes under the station, the axle at the back.
    r = 0.075

    trolley =
      [
        Shape.box({x0 + 0.02, y0, z0 - 0.03}, {x1 - 0.02, y1, z0}, :black),
        Kit.rod({x0 - 0.01, y0 + 0.05, r}, {1, 0, 0}, 0.008, w + 0.02, :steel),
        Kit.rod({x0 + 0.05, y1 - 0.06, 0.0}, {0, 0, 1}, 0.012, z0 - 0.03, :black),
        Kit.rod({x1 - 0.05, y1 - 0.06, 0.0}, {0, 0, 1}, 0.012, z0 - 0.03, :black)
      ] ++
        for(
          x <- [x0 + 0.03, x1 - 0.03],
          do: Shape.box({x - 0.015, y0, r - 0.02}, {x + 0.015, y0 + 0.08, z0 - 0.03}, :black)
        )

    handle =
      Part.new(
        "trolley_handle",
        :handle,
        [
          Shape.sweep(
            [
              {x0 + 0.05, y0 - 0.02, z0},
              {x0 + 0.05, y0 - 0.02, z0 + hb + 0.05},
              {x1 - 0.05, y0 - 0.02, z0 + hb + 0.05},
              {x1 - 0.05, y0 - 0.02, z0}
            ],
            0.01,
            :black, sides: 8)
        ],
        [same("slide", {0.0, y0 - 0.02, z0}, {0, 0, 1}, {0, 1, 0})]
      )

    Assembly.new(
      "power_station_pecron_f5000lfp",
      Part.new("pecron_f5000lfp", :station, body ++ trolley, [origin()], params: %{"kwh" => 5.12, "output_w" => 7200}),
      root: "station",
      kind: :power,
      sources: [
        "Pecron, the page of the F5000LFP: 21.7 by 15 by 13.1 in. On its trolley it is near 17 in high (an estimate from the photos of Pecron, as in DIY)."
      ]
    )
    |> add_wheels(w / 2 + 0.04, y0 + 0.05, r, 0.04)
    |> Assembly.add("handle", handle,
      at: Kit.same("slide", {0.0, y0 - 0.02, z0}, {0, 0, 1}, {0, 1, 0}),
      port: "slide",
      kind: :slides,
      role: :handle,
      limits: [0, 0.4]
    )
  end

  @doc "The Pecron E3800LFP: 17.5 by 12.1 by 14.7 in, an orange cap on each corner."
  def pecron_e3800 do
    {w, d, h} = {inch(17.5), inch(12.1), inch(14.7)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -d / 2, d / 2}
    c = 0.045

    caps =
      for x <- [x0, x1 - c], y <- [y0, y1 - c], z <- [0.0, h - c] do
        rbox(
          {x - 0.003, y - 0.003, z - if(z == 0.0, do: 0.0, else: 0.003)},
          {x + c + 0.003, y + c + 0.003, z + c + if(z == 0.0, do: 0.0, else: 0.003)},
          :orange,
          0.25
        )
      end

    frames =
      for {x, wf} <- [{x0 + 0.04, 0.12}, {x0 + 0.17, 0.11}, {x0 + 0.29, 0.13}] do
        [
          Shape.box({x, y1, h * 0.55}, {x + wf, y1 + 0.004, h - 0.05}, :orange),
          Shape.box({x + 0.006, y1 + 0.004, h * 0.55 + 0.006}, {x + wf - 0.006, y1 + 0.006, h - 0.056}, :black)
        ]
      end

    ports =
      outlet({x0 + 0.1, y1 + 0.006, h * 0.72}, {0, 1, 0}) ++
        outlet({x0 + 0.33, y1 + 0.006, h * 0.72}, {0, 1, 0}) ++
        usb_row({x0 + 0.18, y1 + 0.006, h * 0.66}, 3) ++ [screen({x0 + 0.18, y1 + 0.006, h * 0.76}, {0.08, 0.05})]

    ribs =
      for i <- 0..9,
          do: Shape.box({x0 + 0.06 + i * 0.033, y1, 0.07}, {x0 + 0.072 + i * 0.033, y1 + 0.006, h * 0.45}, :black)

    handles =
      for x <- [x0 + 0.06, x1 - 0.06],
          do:
            Shape.sweep(
              [{x, y0 + 0.08, h}, {x, y0 + 0.08, h + 0.03}, {x, y1 - 0.08, h + 0.03}, {x, y1 - 0.08, h}],
              0.012,
              :black
            )

    body = [rbox({x0, y0, 0.0}, {x1, y1, h}, :dark, 0.04)] ++ caps ++ List.flatten(frames) ++ ports ++ ribs ++ handles

    Assembly.new(
      "power_station_pecron_e3800lfp",
      Part.new("pecron_e3800lfp", :station, body, [origin()], params: %{"kwh" => 3.84, "output_w" => 4200}),
      root: "station",
      kind: :power,
      sources: ["Pecron, the page of the E3800LFP: 17.5 by 12.1 by 14.7 in. The front is 17.5 in wide."]
    )
  end

  # --- EcoFlow ----------------------------------------------------------------------

  @doc "The EcoFlow DELTA Pro: 11.2 in wide at the front, 25 in deep, 16.4 in high."
  def delta_pro, do: delta(:pro)

  @doc "The EcoFlow DELTA Pro 3: 410.4 by 341 by 693 mm (13.4 in wide at the front, 27.3 in deep, 16.2 in high)."
  def delta_pro_3, do: delta(:pro_3)

  defp delta(kind) do
    {w, d, h} = if kind == :pro, do: {inch(11.2), inch(25), inch(16.4)}, else: {mm(341), mm(693), mm(410.4)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -d / 2, d / 2}
    r = 0.055
    zb = 0.035
    {shell, cap} = if kind == :pro, do: {:black, :gray}, else: {:aluminum, :dark}

    body =
      if kind == :pro do
        [
          rbox({x0, y0, zb}, {x1, y1, h - 0.06}, shell, 0.05),
          rbox({x0 + 0.005, y0 + 0.005, h - 0.07}, {x1 - 0.005, y1 - 0.005, h}, cap, 0.08)
        ]
      else
        [
          rbox({x0, y0 + 0.08, zb}, {x1, y1 - 0.08, h}, shell, 0.05),
          rbox({x0 - 0.005, y1 - 0.1, zb}, {x1 + 0.005, y1, h + 0.005}, cap, 0.1),
          rbox({x0 - 0.005, y0, zb}, {x1 + 0.005, y0 + 0.1, h + 0.005}, cap, 0.1)
        ]
      end

    front =
      [screen({-0.05, y1, h - 0.17}, {0.1, 0.07})] ++
        usb_row({-0.05, y1, h - 0.22}, 5) ++
        outlet({-0.05, y1 + 0.003, 0.17}, {0, 1, 0}) ++ outlet({0.05, y1 + 0.003, 0.17}, {0, 1, 0})

    sides = Enum.flat_map(0..3, &outlet({x1 + 0.002, y0 + 0.25 + &1 * 0.06, h * 0.42}, {1, 0, 0}))

    vents =
      for i <- 0..5, do: Shape.box({x0 - 0.002, y0 + 0.15 + i * 0.04, 0.1}, {x0, y0 + 0.17 + i * 0.04, h - 0.12}, :dark)

    top_handles =
      for y <- [y0 + 0.08, y1 - 0.08],
          do:
            Shape.sweep(
              [{x0 + 0.04, y, h}, {x0 + 0.04, y, h + 0.02}, {x1 - 0.04, y, h + 0.02}, {x1 - 0.04, y, h}],
              0.01,
              :black
            )

    stand = [Shape.box({x0 + 0.03, y1 - 0.08, 0.0}, {x1 - 0.03, y1 - 0.04, zb}, :rubber)]

    handle =
      Part.new(
        "delta_handle_#{kind}",
        :handle,
        [
          Shape.sweep(
            [
              {x0 + 0.04, y1 - 0.3, zb + 0.01},
              {x0 + 0.04, y1 + 0.01, zb + 0.01},
              {x1 - 0.04, y1 + 0.01, zb + 0.01},
              {x1 - 0.04, y1 - 0.3, zb + 0.01}
            ],
            0.009,
            :dark, sides: 8)
        ],
        [same("slide", {0.0, y1, zb}, {0, 1, 0}, {0, 0, 1})]
      )

    {name, source, params} =
      if kind == :pro,
        do:
          {"power_station_ecoflow_delta_pro",
           "EcoFlow, the page of the DELTA Pro: 25 by 11.2 by 16.4 in. The front is the short end.",
           %{"kwh" => 3.6, "output_w" => 3600}},
        else:
          {"power_station_ecoflow_delta_pro_3",
           "EcoFlow, the page of the DELTA Pro 3: 410.4 by 341 by 693 mm. The front is the short end.",
           %{"kwh" => 4.096, "output_w" => 4000}}

    Assembly.new(
      name,
      Part.new(
        String.replace(name, "power_station_", ""),
        :station,
        body ++ front ++ sides ++ vents ++ top_handles ++ stand,
        [origin()], params: params),
      root: "station",
      kind: :power,
      sources: [source]
    )
    |> add_wheels(w / 2 + 0.03, y0 + r + 0.02, r, 0.035)
    |> Assembly.add("handle", handle,
      at: Kit.same("slide", {0.0, y1, zb}, {0, 1, 0}, {0, 0, 1}),
      port: "slide",
      kind: :slides,
      role: :handle,
      limits: [0, 0.3]
    )
  end

  @doc """
  The EcoFlow DELTA Pro Ultra: the inverter (690 by 481 by 214 mm) on one
  battery (660 by 455 by 204 mm).
  """
  def delta_pro_ultra do
    {wb, db, hb} = {mm(660), mm(455), mm(204)}
    {wi, di, hi} = {mm(690), mm(481), mm(214)}

    battery = [
      rbox({-wb / 2, -db / 2, 0.01}, {wb / 2, db / 2, hb}, :dark, 0.06),
      Shape.box({-wb / 2 + 0.02, db / 2 - 0.005, 0.03}, {wb / 2 - 0.02, db / 2 + 0.002, hb - 0.02}, :aluminum),
      Shape.box({-wb / 2 + 0.02, -db / 2 - 0.002, 0.03}, {wb / 2 - 0.02, -db / 2 + 0.005, hb - 0.02}, :aluminum)
    ]

    feet =
      Kit.feet(
        [
          {-wb / 2 + 0.05, -db / 2 + 0.05},
          {wb / 2 - 0.05, -db / 2 + 0.05},
          {-wb / 2 + 0.05, db / 2 - 0.05},
          {wb / 2 - 0.05, db / 2 - 0.05}
        ],
        0.02,
        0.012
      )

    z = hb + 0.004

    inverter =
      [
        rbox({-wi / 2, -di / 2, z}, {wi / 2, di / 2, z + hi}, :dark, 0.06),
        Shape.box({-wi / 2 + 0.03, di / 2, z + 0.03}, {wi / 2 - 0.03, di / 2 + 0.003, z + hi - 0.03}, :black),
        screen({-0.1, di / 2 + 0.003, z + hi - 0.09}, {0.2, 0.06})
      ] ++
        Enum.flat_map([-0.24, -0.18, 0.18, 0.24], &outlet({&1, di / 2 + 0.005, z + 0.07}, {0, 1, 0})) ++
        usb_row({-0.06, di / 2 + 0.005, z + 0.06}, 6) ++
        for(
          x <- [-wi / 2 + 0.06, wi / 2 - 0.06],
          do:
            Shape.sweep(
              [
                {x, -di / 2 + 0.06, z + hi},
                {x, -di / 2 + 0.06, z + hi + 0.025},
                {x, di / 2 - 0.06, z + hi + 0.025},
                {x, di / 2 - 0.06, z + hi}
              ],
              0.01,
              :black
            )
        )

    Assembly.new(
      "power_station_ecoflow_delta_pro_ultra",
      Part.new("delta_pro_ultra_battery", :battery, battery ++ feet, [origin()], params: %{"kwh" => 6.144}),
      root: "battery",
      kind: :power,
      sources: [
        "EcoFlow, the page of the DELTA Pro Ultra: the inverter is 690 by 481 by 214 mm, the battery 660 by 455 by 204 mm."
      ]
    )
    |> Assembly.add(
      "inverter",
      Part.new("delta_pro_ultra_inverter", :inverter, inverter, [same("bottom", {0.0, 0.0, z}, {0, 0, 1}, {0, 1, 0})],
        params: %{"output_w" => 7200}
      ), at: Kit.same("top", {0.0, 0.0, z}, {0, 0, 1}, {0, 1, 0}), port: "bottom")
  end

  # --- Anker ------------------------------------------------------------------------

  @doc "The Anker SOLIX F3800: it stands up, 15.3 in wide at the front, 15.6 in deep, 27.6 in high with its wheels."
  def solix_f3800, do: solix(false)

  @doc "The Anker SOLIX F3800 Plus: the size of the F3800, with more solar input."
  def solix_f3800_plus, do: solix(true)

  defp solix(plus) do
    {w, d, h} = {inch(15.3), inch(15.6), inch(27.6)}
    {x0, x1, y0, y1} = {-w / 2, w / 2, -d / 2, d / 2}
    r = 0.06
    zb = 0.05

    body =
      [
        rbox({x0, y0, zb}, {x1, y1, h - 0.02}, :gray, 0.05),
        rbox({x0 + 0.01, y1 - 0.004, h * 0.55}, {x1 - 0.01, y1 + 0.006, h - 0.1}, :dark, 0.06),
        screen({-0.06, y1 + 0.006, h - 0.2}, {0.12, 0.05})
      ] ++
        usb_row({x0 + 0.06, y1 + 0.006, h - 0.27}, 6) ++
        Enum.flat_map(
          0..5,
          &outlet({x1 + 0.002, y0 + 0.08 + rem(&1, 3) * 0.07, h * 0.45 + div(&1, 3) * 0.07}, {1, 0, 0})
        ) ++
        [Shape.box({x0 - 0.004, y0 + 0.06, h * 0.4}, {x0, y1 - 0.06, h * 0.6}, :dark)] ++
        Kit.feet([{x0 + 0.05, y1 - 0.05}, {x1 - 0.05, y1 - 0.05}], 0.02, zb)

    handle =
      Part.new(
        "solix_handle",
        :handle,
        [
          Shape.sweep(
            [
              {x0 + 0.05, y1 - 0.05, h - 0.12},
              {x0 + 0.05, y1 - 0.05, h},
              {x1 - 0.05, y1 - 0.05, h},
              {x1 - 0.05, y1 - 0.05, h - 0.12}
            ],
            0.012,
            :dark, sides: 8)
        ],
        [same("slide", {0.0, y1 - 0.05, h}, {0, 0, 1}, {0, 1, 0})]
      )

    name = if plus, do: "power_station_anker_solix_f3800_plus", else: "power_station_anker_solix_f3800"

    Assembly.new(
      name,
      Part.new(String.replace(name, "power_station_", ""), :station, body, [origin()],
        params: %{"kwh" => 3.84, "output_w" => 6000, "solar_w" => if(plus, do: 3200, else: 2400)}
      ),
      root: "station",
      kind: :power,
      sources: [
        "Anker, the page of the SOLIX F3800#{if plus, do: " Plus", else: ""}: 27.6 by 15.3 by 15.6 in with its wheels. Its user guide shows that it stands up."
      ]
    )
    |> add_wheels(w / 2 + 0.02, y0 + r, r, 0.04)
    |> Assembly.add("handle", handle,
      at: Kit.same("slide", {0.0, y1 - 0.05, h}, {0, 0, 1}, {0, 1, 0}),
      port: "slide",
      kind: :slides,
      role: :handle,
      limits: [0, 0.35]
    )
  end
end
