defmodule Xuong.Parts.Framing do
  @moduledoc """
  The framing systems of DIY and of camper vans:

  - **T-slot extrusions** of aluminum: the fractional series of 80/20
    (10 series: 1 in, 15 series: 1.5 in) and the metric series (20, 30,
    40 mm), with their T-nuts, corner brackets and button head screws.
  - **Strut channel** of steel (Unistrut P1000, 1 5/8 in): the solid
    channel and the channel with slotted holes, a spring nut, a fitting of
    90 degrees, and threaded rod.
  - **L-track** (airline track) of aluminum, with its pockets every 1 in,
    and its fittings.

  A profile lies along z from 0 to its length, centered on x and y (a
  channel stands on y = 0, its opening up). Ports: `end_a`, `end_b`,
  `center` as a tube, and for an extrusion `slot_N` at each slot, at the
  middle of the length, with the axis into the slot.
  """
  alias Xuong.{Frame, Part, Shape}
  alias Xuong.Parts.Fasteners

  # The T-slot profiles: the size of one cell `a`, the cells across x and
  # y, the opening of the slot `o`, the thickness of its lip `t`, the
  # width of the slot under the lip `w`, the depth of the slot `d`, all in
  # mm; the thread of its T-nut; the source.
  @profiles %{
    "1010" => {25.4, 1, 1, 6.5, 2.2, 14.8, 8.1, "1/4-20", "80/20 1010: 1 by 1 in, a T-slot of 0.256 in."},
    "1020" => {25.4, 2, 1, 6.5, 2.2, 14.8, 8.1, "1/4-20", "80/20 1020: 1 by 2 in, six T-slots of 0.256 in."},
    "1030" => {25.4, 3, 1, 6.5, 2.2, 14.8, 8.1, "1/4-20", "80/20 1030: 1 by 3 in, eight T-slots of 0.256 in."},
    "1515" => {38.1, 1, 1, 8.13, 3.2, 20.6, 12.4, "5/16-18", "80/20 1515: 1.5 by 1.5 in, a T-slot of 0.320 in."},
    "1530" => {38.1, 2, 1, 8.13, 3.2, 20.6, 12.4, "5/16-18", "80/20 1530: 1.5 by 3 in, six T-slots of 0.320 in."},
    "2020" =>
      {20.0, 1, 1, 6.2, 1.8, 11.0, 6.2, "M5", "The 20 mm series of T-slot extrusions: 20 by 20 mm, a slot of 6.2 mm."},
    "2040" => {20.0, 2, 1, 6.2, 1.8, 11.0, 6.2, "M5", "The 20 mm series: 20 by 40 mm, six slots of 6.2 mm."},
    "3030" => {30.0, 1, 1, 8.0, 2.2, 16.5, 9.0, "M6", "The 30 mm series: 30 by 30 mm, a slot of 8 mm."},
    "4040" => {40.0, 1, 1, 8.2, 4.3, 20.0, 12.2, "M8", "The 40 mm series: 40 by 40 mm, a slot of 8.2 mm."}
  }

  @doc "The names of the T-slot profiles."
  def profiles, do: @profiles |> Map.keys() |> Enum.sort()

  @doc "A T-slot profile by its name, in meters: `%{a, nx, ny, o, t, w, d, thread, source}`."
  def profile(name) do
    {a, nx, ny, o, t, w, d, thread, source} = Map.fetch!(@profiles, name)
    %{a: a / 1000, nx: nx, ny: ny, o: o / 1000, t: t / 1000, w: w / 1000, d: d / 1000, thread: thread, source: source}
  end

  # The series of a profile: its T-nuts and brackets fit each profile of it.
  # The fractional series are named by the tenths of an inch (10: 1 in,
  # 15: 1.5 in); the metric series by the millimeters.
  defp series(name) do
    case round(profile(name).a * 10000) do
      254 -> "10"
      381 -> "15"
      a -> "#{div(a, 10)}"
    end
  end

  @doc """
  A T-slot extrusion (`extrusion("1515", 0.6)`). The inside is solid in
  the mesh; the slots are real. The sizes inside the slot (the lip, the
  width and the depth) are near the drawings of the makers.
  """
  def extrusion(name, length, opts \\ []) do
    p = profile(name)
    {wx, wy} = {p.nx * p.a, p.ny * p.a}

    # Each side of the rectangle, counterclockwise: its first corner, its
    # direction, the direction into the profile, and the slots on it.
    sides = [
      {{-wx / 2, -wy / 2}, {1, 0}, {0, 1}, p.nx},
      {{wx / 2, -wy / 2}, {0, 1}, {-1, 0}, p.ny},
      {{wx / 2, wy / 2}, {-1, 0}, {0, -1}, p.nx},
      {{-wx / 2, wy / 2}, {0, -1}, {1, 0}, p.ny}
    ]

    k = (p.w - p.o) / 2 * 0.45

    notch = [
      {-p.o / 2, 0.0},
      {-p.o / 2, p.t},
      {-p.w / 2, p.t},
      {-p.w / 2 + k, p.d},
      {p.w / 2 - k, p.d},
      {p.w / 2, p.t},
      {p.o / 2, p.t},
      {p.o / 2, 0.0}
    ]

    loop =
      Enum.flat_map(sides, fn {{x0, y0}, {dx, dy}, {nx, ny}, n} ->
        [{x0, y0}] ++
          for i <- 0..(n - 1), {u, v} <- notch do
            s = p.a * (i + 0.5) + u
            {x0 + dx * s + nx * v, y0 + dy * s + ny * v}
          end
      end)

    slots =
      sides
      |> Enum.flat_map(fn {{x0, y0}, {dx, dy}, {nx, ny}, n} ->
        for i <- 0..(n - 1), do: {{x0 + dx * p.a * (i + 0.5), y0 + dy * p.a * (i + 0.5)}, {nx, ny}}
      end)
      |> Enum.with_index(1)
      |> Enum.map(fn {{{x, y}, {nx, ny}}, i} -> Part.port("slot_#{i}", {x, y, length / 2}, {nx, ny, 0}, {0, 0, 1}) end)

    Part.new(
      "extrusion_#{name}x#{mm(length)}",
      :extrusion,
      [Shape.prism(loop, length, Keyword.get(opts, :material, :aluminum))],
      ends(length) ++ slots,
      params: %{"profile" => name, "length" => length},
      sources: [p.source]
    )
  end

  defp ends(length) do
    [
      Part.port("end_a", {0, 0, 0}, {0, 0, -1}, {0, 1, 0}),
      Part.port("end_b", {0, 0, length}, {0, 0, 1}, {0, 1, 0}),
      Part.port("center", {0, 0, length / 2}, {0, 0, 1}, {0, 1, 0})
    ]
  end

  @doc """
  A T-nut that drops into the slot of a profile of the series of `name`.
  It lies under the lip: its port `face` is on the inside of the lip, its
  axis into the slot (the axis of the screw).
  """
  def t_nut(name) do
    p = profile(name)
    {w, l, h} = {p.w * 0.85, p.a * 0.6, (p.d - p.t) * 0.7}

    Part.new(
      "t_nut_#{series(name)}_#{Fasteners.thread_name(p.thread)}",
      :t_nut,
      [
        Shape.box({-w / 2, -l / 2, 0.0}, {w / 2, l / 2, h}, :steel),
        Shape.cylinder(Fasteners.diameter(p.thread) / 2, h + 0.001, :dark, sides: 10)
      ],
      [Part.port("face", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})],
      detail: :near,
      params: %{"thread" => p.thread},
      sources: ["A drop-in T-nut for the #{series(name)} series, #{p.thread}."]
    )
  end

  @doc """
  A corner bracket with a gusset for the series of `name`: two legs of one
  cell, at a right angle. Its origin is at the corner, on the faces of the
  two profiles; one leg lies along +x on z = 0, the other along +z on
  x = 0. Ports `hole_x` and `hole_z`: at the holes, the axis into the
  profile.
  """
  def corner_bracket(name) do
    p = profile(name)
    {l, w, t} = {p.a, p.a * 0.8, p.a * 0.15}

    gusset =
      Shape.prism([{t, t}, {l * 0.8, t}, {t, l * 0.8}], t * 0.8, :aluminum,
        frame: Frame.new({0.0, t * 0.4, 0.0}, {0, -1, 0}, {0, 0, 1})
      )

    Part.new(
      "corner_bracket_#{series(name)}",
      :bracket,
      [
        Shape.box({0.0, -w / 2, 0.0}, {l, w / 2, t}, :aluminum),
        Shape.box({0.0, -w / 2, 0.0}, {t, w / 2, l}, :aluminum),
        gusset
      ],
      [
        Part.port("hole_x", {l / 2, 0, t}, {0, 0, -1}, {1, 0, 0}),
        Part.port("hole_z", {t, 0, l / 2}, {-1, 0, 0}, {0, 0, 1})
      ],
      params: %{"series" => series(name)},
      sources: ["A corner bracket with a gusset for the #{series(name)} series (a common shape)."]
    )
  end

  @doc "The screw of a bracket for the series of `name`: a button head screw of the thread of the series."
  def bracket_screw(name) do
    p = profile(name)
    Fasteners.button_screw(p.thread, Float.round(p.a * 0.15 + p.t + 0.004, 4)) |> Map.put(:detail, :near)
  end

  # --- Strut channel ------------------------------------------------------------------

  @doc """
  A strut channel of steel, 1 5/8 by 1 5/8 in, 12 gauge (Unistrut P1000):
  `kind` is `:solid` (P1000) or `:slotted` (P1000T: slots of 9/16 by
  1 1/8 in on 2 in centers in its base). It lies along z, its base on
  y = 0 and its opening to +y. Ports: the ends, the center, and `slot_N`
  at each slot (on the base, the axis into the channel).
  """
  def strut(kind, length) do
    {w, t, o, lip} = {0.04128, 0.00266, 0.02223, 0.0095}
    {hw, hl, pitch} = {0.01429 / 2, 0.02858, 0.0508}

    half = fn x0 ->
      [
        {-w / 2, 0.0},
        {x0, 0.0},
        {x0, t},
        {-w / 2 + t, t},
        {-w / 2 + t, w - t},
        {-o / 2 - t, w - t},
        {-o / 2 - t, w - lip},
        {-o / 2, w - lip},
        {-o / 2, w},
        {-w / 2, w}
      ]
    end

    mirror = fn loop -> loop |> Enum.map(fn {x, y} -> {-x, y} end) |> Enum.reverse() end

    {name, holes} =
      if kind == :slotted,
        do: {"strut_p1000t_#{mm(length)}", trunc((length - pitch / 2) / pitch)},
        else: {"strut_p1000_#{mm(length)}", 0}

    shapes =
      if kind == :slotted do
        # The base is cut along its middle: two halves, and a bridge
        # between each two slots.
        centers = for k <- 0..(holes - 1)//1, do: pitch / 2 + k * pitch
        cuts = Enum.map(centers, &{&1 - hl / 2, &1 + hl / 2})

        bridges =
          Enum.zip([{0.0, 0.0} | cuts], cuts ++ [{length, length}]) |> Enum.map(fn {{_, a}, {b, _}} -> {a, b} end)

        [Shape.prism(half.(-hw), length, :steel), Shape.prism(mirror.(half.(-hw)), length, :steel)] ++
          for({a, b} <- bridges, b - a > 0.001, do: Shape.box({-hw, 0.0, a}, {hw, t, b}, :steel))
      else
        # The whole C: the base, the right side and lip, the left lip and side.
        [
          Shape.prism(
            [
              {-w / 2, 0.0},
              {w / 2, 0.0},
              {w / 2, w},
              {o / 2, w},
              {o / 2, w - lip},
              {o / 2 + t, w - lip},
              {o / 2 + t, w - t},
              {w / 2 - t, w - t}
            ] ++
              [
                {w / 2 - t, t},
                {-w / 2 + t, t},
                {-w / 2 + t, w - t},
                {-o / 2 - t, w - t},
                {-o / 2 - t, w - lip},
                {-o / 2, w - lip},
                {-o / 2, w},
                {-w / 2, w}
              ],
            length,
            :steel
          )
        ]
      end

    slots =
      for k <- 0..(holes - 1)//1, do: Part.port("slot_#{k + 1}", {0, 0, pitch / 2 + k * pitch}, {0, 1, 0}, {0, 0, 1})

    Part.new(name, :strut, shapes, ends(length) ++ slots,
      params: %{"length" => length},
      sources: [
        "Unistrut P1000#{if kind == :slotted, do: "T", else: ""}: 1 5/8 by 1 5/8 in, 12 gauge#{if kind == :slotted, do: ", slots of 9/16 by 1 1/8 in on 2 in centers", else: ""} (retailer listings; the lip is approximate)."
      ]
    )
  end

  @doc """
  A spring nut of 1/2-13 for strut channel: it lies in the channel under
  the lips, its spring on the base. Port `face`: the top of the nut, the
  axis down into the channel.
  """
  def spring_nut do
    {l, w, h} = {0.0254, 0.0349, 0.0127}

    Part.new(
      "spring_nut_1_2_13",
      :nut,
      [
        Shape.box({-w / 2, -l / 2, -h}, {w / 2, l / 2, 0.0}, :steel),
        Shape.lathe([{0.004, -h - 0.016}, {0.006, -h - 0.016}, {0.006, -h}, {0.004, -h}], :steel, kind: :ring, sides: 8)
      ],
      [Part.port("face", {0, 0, 0}, {0, 0, -1}, {0, 1, 0})],
      detail: :near,
      params: %{"thread" => "1/2-13"},
      sources: ["A spring nut of 1/2-13 for strut channel of 1 5/8 in (a common size)."]
    )
  end

  @doc """
  A fitting of 90 degrees for strut channel: a plate of steel of 1/4 in,
  1 5/8 in wide, with two legs of 3 1/2 in and a hole of 9/16 in in each.
  Its origin is at the outside of the corner; one leg along +x, the other
  along +z.
  """
  def strut_angle do
    {l, w, t} = {0.0889, 0.04128, 0.00635}

    Part.new(
      "strut_angle_90",
      :fitting,
      [Shape.box({0.0, -w / 2, 0.0}, {l, w / 2, t}, :steel), Shape.box({0.0, -w / 2, 0.0}, {t, w / 2, l}, :steel)],
      [
        Part.port("hole_x", {l * 0.6, 0, t}, {0, 0, -1}, {1, 0, 0}),
        Part.port("hole_z", {t, 0, l * 0.6}, {-1, 0, 0}, {0, 0, 1})
      ],
      sources: [
        "A fitting of 90 degrees for strut channel: 1/4 in thick, 1 5/8 in wide, legs of 3 1/2 in (a common size)."
      ]
    )
  end

  @doc "A threaded rod (`threaded_rod(\"1/2-13\", 0.3)`), along z from 0 to `length`."
  def threaded_rod(thread, length) do
    d = Fasteners.diameter(thread)

    Part.new(
      "threaded_rod_#{Fasteners.thread_name(thread)}x#{mm(length)}",
      :rod,
      [Shape.cylinder(d / 2, length, :steel, sides: 12)],
      ends(length),
      params: %{"thread" => thread, "length" => length},
      sources: ["A threaded rod of #{thread}."]
    )
  end

  # --- L-track -------------------------------------------------------------------------

  @doc """
  An L-track of aluminum (airline track): 1 1/8 in wide and 1/2 in high,
  a slot along its top with a round pocket every 1 in, and a hole for a
  screw every 5 in. It lies along z from 0 to `length`, its base on y = 0,
  its top to +y. Ports: the ends, the center, `pocket_N` at each pocket
  (the axis down into the track) and `screw_N` at each hole.
  """
  def l_track(length) do
    {w, h, base, top_w, slot, pocket} = {0.0286, 0.0127, 0.003, 0.0216, 0.0105, 0.0185}
    pitch = 0.0254
    lip_t = 0.0032

    # The walls under the top, and the base.
    body = [
      Shape.box({-w / 2, 0.0, 0.0}, {w / 2, base, length}, :aluminum),
      Shape.box({-top_w / 2, base, 0.0}, {-top_w / 2 + 0.003, h - lip_t, length}, :aluminum),
      Shape.box({top_w / 2 - 0.003, base, 0.0}, {top_w / 2, h - lip_t, length}, :aluminum)
    ]

    # The top: lips beside the slot, narrow between the pockets and wide
    # at the bridges. A pocket is square in the mesh.
    n = trunc(length / pitch + 1.0e-9)

    lips =
      for k <- 0..(n - 1),
          {a, b, gap} <- [
            {k * pitch, k * pitch + pitch - pocket, slot},
            {k * pitch + pitch - pocket, (k + 1) * pitch, pocket}
          ],
          side <- [-1, 1] do
        {x0, x1} = if side < 0, do: {-top_w / 2, -gap / 2}, else: {gap / 2, top_w / 2}
        Shape.box({x0, h - lip_t, a}, {x1, h, b}, :aluminum)
      end

    tail =
      if length - n * pitch > 0.001,
        do:
          for(
            side <- [-1, 1],
            do:
              Shape.box(
                {if(side < 0, do: -top_w / 2, else: slot / 2), h - lip_t, n * pitch},
                {if(side < 0, do: -slot / 2, else: top_w / 2), h, length},
                :aluminum
              )
          ),
        else: []

    pockets =
      for k <- 0..(n - 1),
          do: Part.port("pocket_#{k + 1}", {0, h, k * pitch + pitch - pocket / 2}, {0, -1, 0}, {0, 0, 1})

    screws =
      for k <- 0..trunc((length - 0.0635) / 0.127)//1,
          do: Part.port("screw_#{k + 1}", {0, base, 0.0635 + k * 0.127}, {0, -1, 0}, {0, 0, 1})

    Part.new("l_track_#{mm(length)}", :track, body ++ lips ++ tail, ends(length) ++ pockets ++ screws,
      params: %{"length" => length},
      sources: [
        "An L-track of aluminum: 1 1/8 by 1/2 in, holes every 5 in (US Cargo Control); the pockets every 1 in, as on airline track."
      ]
    )
  end

  @doc """
  A fitting for L-track: `:ring` (a single stud with a ring of steel) or
  `:stud` (a double stud with a threaded stud of 1/4-20). It sits in a
  pocket: its port `stud` is at the top of the track, the axis down.
  """
  def l_track_fitting(kind) do
    body = [
      Shape.box({-0.008, -0.004, -0.009}, {0.008, 0.004, 0.0}, :steel),
      Shape.cylinder(0.009, 0.006, :steel, sides: 16)
    ]

    {name, top, source} =
      case kind do
        :ring ->
          {"l_track_fitting_ring",
           [
             Shape.lathe([{0.016, 0.0}, {0.021, 0.0}, {0.021, 0.004}, {0.016, 0.004}], :steel,
               kind: :ring,
               sides: 16,
               frame: Frame.new({0.0, 0.0, 0.03}, {1, 0, 0}, {0, 0, 1})
             )
           ], "A single stud fitting with a ring, for L-track (a common fitting)."}

        :stud ->
          {"l_track_fitting_stud_1_4_20",
           [Shape.cylinder(0.0032, 0.03, :steel, sides: 10, frame: Frame.move({0.0, 0.0, 0.006}))],
           "A double stud fitting with a stud of 1/4-20, for L-track (a common fitting)."}
      end

    # Port `slide`: the axis along the track (its body is long along x), up out of the track.
    Part.new(
      name,
      :fitting,
      body ++ top,
      [Part.port("stud", {0, 0, 0}, {0, 0, -1}, {0, 1, 0}), Part.port("slide", {0, 0, 0}, {1, 0, 0}, {0, 0, 1})],
      sources: [source]
    )
  end

  defp mm(x), do: x |> Kernel.*(1000) |> round()
end
