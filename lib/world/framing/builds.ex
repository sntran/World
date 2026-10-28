defmodule World.Framing.Builds do
  @moduledoc """
  Builds from the framing systems (`World.Framing`), as a person in
  DIY or in a camper van makes them. The list of the parts of each build
  counts each profile by its length, and each bracket, screw, T-nut,
  spring nut and fitting.

  - `shelf_8020_1010`: a shelf of 80/20 1010, 36 by 12 by 18 in, with a
    frame at the top and at the bottom, corner brackets, and a top of
    plywood.
  - `strut_wall_rack`: two uprights of Unistrut P1000T on a wall and two
    crossbars on them; at each joint a bolt of 1/2-13 goes into a spring
    nut.
  - `strut_trapeze`: a trapeze hanger: a channel on two threaded rods,
    with nuts and washers.
  - `l_track_floor`: a floor of plywood with two L-tracks and fittings
    that slide along them.
  """
  alias World.{Assembly, Frame, Framing, Kit, Part, Vec}
  alias World.Materials.{Fasteners, Stock}
  import Kit, only: [inch: 1]

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @doc "The models, as `{name, fun}`."
  def all do
    [
      {"extrusion_1010_24in", &__MODULE__.extrusion_1010/0},
      {"extrusion_1515_24in", &__MODULE__.extrusion_1515/0},
      {"extrusion_2020_500mm", &__MODULE__.extrusion_2020/0},
      {"extrusion_4040_500mm", &__MODULE__.extrusion_4040/0},
      {"strut_p1000t_24in", &__MODULE__.strut_24/0},
      {"l_track_24in", &__MODULE__.l_track_24/0},
      {"shelf_8020_1010", &__MODULE__.shelf/0},
      {"strut_wall_rack", &__MODULE__.strut_wall_rack/0},
      {"strut_trapeze", &__MODULE__.strut_trapeze/0},
      {"l_track_floor", &__MODULE__.l_track_floor/0}
    ]
  end

  # The root of a build: a mark with no shapes.
  defp mark, do: Part.new("origin", :mark, [], [@o])

  # The opts to put an item with its local x along `x` and its local z
  # along `z` (its local y is z x x).
  defp at(name, p, x, z), do: [at: Part.port(name, p, z, Vec.cross(z, x)), port: @o]

  # --- One profile -------------------------------------------------------------------

  @doc "80/20 1010, 24 in long."
  def extrusion_1010, do: lying("extrusion_1010_24in", Framing.extrusion("1010", inch(24)))

  @doc "80/20 1515, 24 in long."
  def extrusion_1515, do: lying("extrusion_1515_24in", Framing.extrusion("1515", inch(24)))

  @doc "An extrusion of the 20 mm series, 500 mm long."
  def extrusion_2020, do: lying("extrusion_2020_500mm", Framing.extrusion("2020", 0.5))

  @doc "An extrusion of the 40 mm series, 500 mm long."
  def extrusion_4040, do: lying("extrusion_4040_500mm", Framing.extrusion("4040", 0.5))

  @doc "Unistrut P1000T, 24 in long."
  def strut_24, do: lying("strut_p1000t_24in", Framing.strut(:slotted, inch(24)))

  @doc "An L-track, 24 in long."
  def l_track_24, do: lying("l_track_24in", Framing.l_track(inch(24)))

  # A profile along its z, laid on the ground along x and centered: its
  # local z along x, its local y up.
  defp lying(name, part) do
    {{_, y0, _}, _} = Part.bounds(part)
    len = part.params["length"]

    Assembly.new(name, mark(), root: "origin", kind: :material, sources: part.sources)
    |> Assembly.add("part", part, at("part", {-len / 2, 0.0, -y0}, {0, 1, 0}, {1, 0, 0}))
  end

  # --- The shelf of 80/20 ----------------------------------------------------------------

  @doc """
  A shelf of 80/20 1010: 36 in long, 12 in deep, 18 in high, four legs, a
  frame of rails at the top and at 4 in, a corner bracket under each end
  of a rail (two button head screws and two T-nuts each), and a top of
  plywood of 3/4 in.
  """
  def shelf do
    {w, d, h} = {inch(36), inch(12), inch(18) - inch(0.75)}
    p = Framing.profile("1010")
    a = p.a
    {xl, yl} = {w / 2 - a / 2, d / 2 - a / 2}

    legs = for {sx, sy} <- [{-1, -1}, {1, -1}, {1, 1}, {-1, 1}], do: {sx * xl, sy * yl}

    asm =
      Assembly.new("shelf_8020_1010", mark(),
        root: "origin",
        kind: :furniture,
        sources: ["A shelf of 80/20 1010 (1 by 1 in) with corner brackets of the 10 series; a common build."]
      )

    asm =
      legs
      |> Enum.with_index(1)
      |> Enum.reduce(asm, fn {{x, y}, i}, asm ->
        Assembly.add(asm, "leg_#{i}", Framing.extrusion("1010", h), at("leg_#{i}", {x, y, 0.0}, {1, 0, 0}, {0, 0, 1}))
      end)

    # The rails at two heights (their centers), each between two legs.
    levels = [{"top", h - a / 2}, {"low", inch(4)}]

    rails =
      for {level, z} <- levels,
          {side, sy} <- [{"front", 1}, {"back", -1}],
          do:
            {"rail_#{level}_#{side}", Framing.extrusion("1010", w - 2 * a), {-w / 2 + a, sy * yl, z}, {0, 1, 0},
             {1, 0, 0}}

    ends =
      for {level, z} <- levels,
          {side, sx} <- [{"right", 1}, {"left", -1}],
          do:
            {"rail_#{level}_#{side}", Framing.extrusion("1010", d - 2 * a), {sx * xl, -d / 2 + a, z}, {1, 0, 0},
             {0, 1, 0}}

    asm =
      Enum.reduce(rails ++ ends, asm, fn {n, part, p0, x, z}, asm -> Assembly.add(asm, n, part, at(n, p0, x, z)) end)

    # A bracket under each end of each rail: its corner on the face of the
    # leg and the bottom of the rail; one leg along the rail, one down the
    # leg.
    corners =
      for {level, z} <- levels,
          {dir, base} <- [
            {{1, 0, 0}, fn sy -> {-w / 2 + a, sy * yl} end},
            {{-1, 0, 0}, fn sy -> {w / 2 - a, sy * yl} end}
          ],
          sy <- [1, -1] do
        {x, y} = base.(sy)
        {"#{level}_#{elem(dir, 0)}_#{sy}", {x, y, z - a / 2}, dir}
      end ++
        for {level, z} <- levels, {dir, yy} <- [{{0, 1, 0}, -d / 2 + a}, {{0, -1, 0}, d / 2 - a}], sx <- [1, -1] do
          {"#{level}_y#{elem(dir, 1)}_#{sx}", {sx * xl, yy, z - a / 2}, dir}
        end

    bracket = Framing.corner_bracket("1010")
    screw = Framing.bracket_screw("1010")
    nut = Framing.t_nut("1010")

    asm =
      corners
      |> Enum.with_index(1)
      |> Enum.reduce(asm, fn {{_, corner, dir}, i}, asm ->
        f = Frame.new(corner, {0, 0, -1}, Vec.cross({0, 0, -1}, dir))

        asm
        |> Assembly.add("bracket_#{i}", bracket, at("bracket_#{i}", corner, dir, {0, 0, -1}))
        |> fasten(i, f, bracket, screw, nut, p.t)
      end)

    top = Stock.sheet(w, d, inch(0.75), :plywood, name: "plywood_36x12x0_75")
    Assembly.add(asm, "top", top, at("top", {-w / 2, -d / 2, h}, {1, 0, 0}, {0, 0, 1}))
  end

  # The two screws of a bracket (in its frame `f`) and their T-nuts in the
  # slots, under the lips of the profiles.
  defp fasten(asm, i, f, bracket, screw, nut, lip) do
    for {hole, k} <- [{"hole_x", "a"}, {"hole_z", "b"}], reduce: asm do
      asm ->
        port = Part.port!(bracket, hole)
        {at, axis} = {Frame.point(f, port.at), Frame.dir(f, port.axis)}
        up = Vec.perpendicular(axis)
        # The face of the profile is at the corner side of the leg of the bracket.
        thick = bracket_thickness(bracket)
        face = Vec.add(at, Vec.scale(axis, thick))

        asm
        |> Assembly.add("screw_#{i}#{k}", screw, at: Part.port("s", at, axis, up), port: "head")
        |> Assembly.add("t_nut_#{i}#{k}", nut,
          at: Part.port("n", Vec.add(face, Vec.scale(axis, lip)), axis, up),
          port: "face"
        )
    end
  end

  defp bracket_thickness(bracket) do
    {lo, hi} = Part.bounds(%{bracket | shapes: [hd(bracket.shapes)]})
    elem(Vec.sub(hi, lo), 2)
  end

  # --- Unistrut ----------------------------------------------------------------------

  @doc """
  A rack of strut channel on a wall: two uprights of P1000T, 36 in, with
  their bases on the wall (y = 0) and their openings to the front, and two
  crossbars of P1000T, 30 in, on their fronts. At each joint a hex bolt of
  1/2-13 by 1 1/4 in and a washer go through a slot of the crossbar into
  a spring nut in the upright.
  """
  def strut_wall_rack do
    {up_len, bar_len} = {inch(36), inch(30)}
    {w, t} = {0.04128, 0.00266}
    pitch = 0.0508
    # The uprights stand at two slots of the crossbar.
    xs = [-bar_len / 2 + pitch * 1.5, -bar_len / 2 + pitch * 13.5]
    zs = [inch(8), inch(28)]
    upright = Framing.strut(:slotted, up_len)
    bar = Framing.strut(:slotted, bar_len)

    asm =
      Assembly.new("strut_wall_rack", mark(),
        root: "origin",
        kind: :furniture,
        sources: ["A rack of Unistrut P1000T on a wall, with spring nuts and bolts of 1/2-13; a common build."]
      )

    asm =
      xs
      |> Enum.with_index(1)
      |> Enum.reduce(asm, fn {x, i}, asm ->
        Assembly.add(asm, "upright_#{i}", upright, at("upright_#{i}", {x, 0.0, 0.0}, {1, 0, 0}, {0, 0, 1}))
      end)

    # A crossbar: its base on the fronts of the uprights (y = w), its
    # opening to the front, along x.
    asm =
      zs
      |> Enum.with_index(1)
      |> Enum.reduce(asm, fn {z, i}, asm ->
        Assembly.add(asm, "crossbar_#{i}", bar, at("crossbar_#{i}", {-bar_len / 2, w, z}, {0, 0, -1}, {1, 0, 0}))
      end)

    bolt = Fasteners.bolt("1/2-13", inch(1.25))
    washer = Fasteners.washer("1/2-13")
    nut = Framing.spring_nut()

    for {x, i} <- Enum.with_index(xs, 1), {z, j} <- Enum.with_index(zs, 1), reduce: asm do
      asm ->
        k = "#{i}_#{j}"
        {_, _, wh} = Fasteners.table(:washer, "1/2-13")
        head = {x, w + t + wh, z}

        asm
        |> Assembly.add("washer_#{k}", washer, at: Part.port("w", {x, w + t, z}, {0, 1, 0}, {0, 0, 1}), port: "face")
        |> Assembly.add("bolt_#{k}", bolt, at: Part.port("b", head, {0, -1, 0}, {0, 0, 1}), port: "head")
        |> Assembly.add("spring_nut_#{k}", nut, at: Part.port("n", {x, w - t, z}, {0, -1, 0}, {0, 0, 1}), port: "face")
    end
  end

  @doc """
  A trapeze hanger: a channel of P1000T, 24 in, its opening up, on two
  threaded rods of 1/2-13 from a ceiling 24 in over it, with a nut and a
  washer under and over the base of the channel at each rod.
  """
  def strut_trapeze do
    {len, drop} = {inch(24), inch(24)}
    t = 0.00266
    pitch = 0.0508
    xs = [-len / 2 + pitch * 1.5, len / 2 - pitch * 1.5]
    rod = Framing.threaded_rod("1/2-13", drop + 0.05)
    nut = Fasteners.nut("1/2-13")
    washer = Fasteners.washer("1/2-13")
    {_, _, wh} = Fasteners.table(:washer, "1/2-13")

    asm =
      Assembly.new("strut_trapeze", mark(),
        root: "origin",
        kind: :furniture,
        sources: ["A trapeze hanger of Unistrut P1000T on threaded rods of 1/2-13; a common build."]
      )
      # The channel along x, its opening up.
      |> Assembly.add("channel", Framing.strut(:slotted, len),
        at: Part.port("channel", {-len / 2, 0.0, wh + 0.012}, {1, 0, 0}, {0, 0, 1}),
        port: @o
      )

    for {x, i} <- Enum.with_index(xs, 1), reduce: asm do
      asm ->
        z0 = wh + 0.012

        asm
        |> Assembly.add("rod_#{i}", rod, at("rod_#{i}", {x, 0.0, 0.0}, {1, 0, 0}, {0, 0, 1}))
        |> Assembly.add("washer_under_#{i}", washer,
          at: Part.port("w", {x, 0.0, z0 - wh}, {0, 0, 1}, {0, 1, 0}),
          port: "face"
        )
        |> Assembly.add("nut_under_#{i}", nut,
          at: Part.port("n", {x, 0.0, z0 - wh}, {0, 0, -1}, {0, 1, 0}),
          port: "face"
        )
        |> Assembly.add("washer_over_#{i}", washer,
          at: Part.port("w", {x, 0.0, z0 + t}, {0, 0, 1}, {0, 1, 0}),
          port: "face"
        )
        |> Assembly.add("nut_over_#{i}", nut,
          at: Part.port("n", {x, 0.0, z0 + t + wh}, {0, 0, 1}, {0, 1, 0}),
          port: "face"
        )
    end
  end

  # --- L-track ---------------------------------------------------------------------------

  @doc """
  A floor of plywood of 3/4 in, 48 by 24 in, with two L-tracks of 48 in
  along x, a wood screw of #12 by 5/8 in in each hole, and three fittings
  (two rings and a stud) that slide along the tracks.
  """
  def l_track_floor do
    {len, d, ply} = {inch(48), inch(24), inch(0.75)}
    ys = [-inch(8), inch(8)]
    track = Framing.l_track(len)

    along = fn prefix ->
      for({_, p} <- track.ports, String.starts_with?(p.name, prefix), do: p.at) |> Enum.sort_by(&elem(&1, 2))
    end

    {pockets, screws} = {along.("pocket_"), along.("screw_")}

    asm =
      Assembly.new("l_track_floor", mark(),
        root: "origin",
        kind: :furniture,
        sources: ["A floor of a van of plywood of 3/4 in with two L-tracks; a common build."]
      )
      |> Assembly.add(
        "floor",
        Stock.sheet(len, d, ply, :plywood, name: "plywood_48x24x0_75"),
        at("floor", {-len / 2, -d / 2, 0.0}, {1, 0, 0}, {0, 0, 1})
      )

    # A track: its local z along x, its local y up; a point {0, y, z} of
    # the track is at {x0 + z, y_track, ply + y}.
    world = fn y_track, {_, ty, tz} -> {-len / 2 + tz, y_track, ply + ty} end

    asm =
      ys
      |> Enum.with_index(1)
      |> Enum.reduce(asm, fn {y, i}, asm ->
        asm = Assembly.add(asm, "track_#{i}", track, at("track_#{i}", {-len / 2, y, ply}, {0, 1, 0}, {1, 0, 0}))

        screws
        |> Enum.with_index(1)
        |> Enum.reduce(asm, fn {p, k}, asm ->
          Assembly.add(asm, "track_screw_#{i}_#{k}", Fasteners.wood_screw("#12", inch(0.625)),
            at: Part.port("s", world.(y, p), {0, 0, -1}, {1, 0, 0}),
            port: "head"
          )
        end)
      end)

    # The fittings: a port at a pocket, its axis along the track.
    fittings = [{"ring_1", :ring, hd(ys), 4}, {"ring_2", :ring, hd(ys), 40}, {"stud_1", :stud, List.last(ys), 20}]

    Enum.reduce(fittings, asm, fn {n, kind, y, k}, asm ->
      p = world.(y, Enum.at(pockets, k))

      Assembly.add(asm, "fitting_#{n}", Framing.l_track_fitting(kind),
        at: Part.port(n, p, {1, 0, 0}, {0, 0, 1}),
        port: "slide",
        kind: :slide,
        role: :slide,
        limits: [-elem(p, 0) - len / 2 + 0.02, len / 2 - elem(p, 0) - 0.02]
      )
    end)
  end
end
