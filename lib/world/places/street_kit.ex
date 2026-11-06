defmodule World.Places.StreetKit do
  @moduledoc """
  The street kit of a town of Việt Nam (Vũng Tàu, W21): pieces that the
  game puts side by side along the streets and the hẻm, and the things
  on the sidewalk. Each piece is a model of the kind `:street`, with three
  levels, the data of `World.Surface` and its ports in its list of the
  parts (`World.Build.parts_file/2`): `join` where the next piece starts,
  and `wire` where a cable comes.

  - The strips of 2 m along x (the street side at y = 0): the sidewalk
    (`sidewalk/1`: a curb of concrete and tiles of terrazzo of 40 by 40
    cm on a slab), the gutter (`gutter/1`: a channel of concrete under
    covers, one of them a grate of iron), and the concrete paving of a
    hẻm (`hem/1`: with cracks and patches by its seed). Each is
    `:straight`, a `:corner` (the strip turns: a square of its width with
    an edge on two sides) or a `:junction` (a T: a square with an edge on
    one side). The ramp cut (`ramp_cut/0`): the curb low and the
    sidewalk a slope, where the scooters go up to a house.
  - The concrete power pole (`pole/0`: a centrifugal pole of 12 m, 10 m
    over the ground, two crossarms with insulators, a coil of the
    bundles of cables), the transformer on its pole (`transformer/0`),
    the meter boxes (`meter_box/0`), the street lamp (`lamp/0`) and the
    bin of 240 L (`bin/0`, its lid on a hinge).

  The sizes are by eye from the streets of Vũng Tàu and the sizes of
  common products of 2019 (each in its sources), unless a source says
  other.
  """
  alias World.{Assembly, Detail, Mesh, Part, Shape, Vec}

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})
  @len 2.0
  # The top of the sidewalk over the street, the curb, a tile.
  @walk 0.15
  @curb 0.18
  @tile 0.4

  @doc "The models of the kit, by their names."
  def models do
    for shape <- [:straight, :corner, :junction],
        {name, fun} <- [{"via_he", &sidewalk/1}, {"muong", &gutter/1}, {"hem", &hem/1}] do
      {"#{name}_#{shape}", fn -> fun.(shape) end}
    end ++
      [
        {"via_he_ram", &ramp_cut/0},
        {"cot_dien_12m", &pole/0},
        {"may_bien_ap", &transformer/0},
        {"hop_cong_to", &meter_box/0},
        {"den_duong", &lamp/0},
        {"thung_rac_240l", &bin/0}
      ]
  end

  # --- The strips ---------------------------------------------------------------

  # The plan of a piece: its size along x and y, and which of its four
  # sides (:y0 the street side, :x0, :x1, :y1) has an edge.
  defp plan(:straight, w), do: {{@len, w}, [:y0]}
  defp plan(:corner, w), do: {{w, w}, [:y0, :x0]}
  defp plan(:junction, w), do: {{w, w}, [:y0]}

  @doc """
  A piece of the sidewalk: 3 m wide (the sidewalks of the streets of the
  center of Vũng Tàu: 3 to 5 m), its top #{@walk} m over the street, a
  curb of #{@curb} m on each edge, tiles of terrazzo of #{@tile} m.
  """
  def sidewalk(shape, opts \\ []) do
    w = Keyword.get(opts, :width, 3.0)
    {{lx, ly}, edges} = plan(shape, w)
    level = Detail.level()
    {x0, y0} = {if(:x0 in edges, do: @curb, else: 0.0), if(:y0 in edges, do: @curb, else: 0.0)}

    curbs =
      for e <- edges do
        case e do
          :y0 -> Shape.box({0.0, 0.0, 0.0}, {lx, @curb, @walk}, :concrete)
          :x0 -> Shape.box({0.0, 0.0, 0.0}, {@curb, ly, @walk}, :concrete)
        end
      end

    base = Shape.box({x0, y0, 0.0}, {lx, ly, @walk - 0.03}, :concrete)
    tiles = tiles({x0, y0}, {lx, ly}, @walk - 0.03, @walk, level)

    piece("via_he_#{shape}", shape, Enum.map(curbs ++ [base], &Mesh.matter(&1, :concrete)) ++ tiles, {lx, ly}, [
      "The sidewalk: tiles of terrazzo of 40 by 40 cm and a curb (bó vỉa) of concrete: by eye, from the streets of Vũng Tàu."
    ])
  end

  # The tiles of a sidewalk: one tile each #{@tile} m with a joint of 4 mm
  # at near, one slab at mid and far.
  defp tiles({x0, y0}, {x1, y1}, z0, z1, :near) do
    for x <- steps(x0, x1, @tile), y <- steps(y0, y1, @tile) do
      Shape.box({x + 0.002, y + 0.002, z0}, {min(x + @tile, x1) - 0.002, min(y + @tile, y1) - 0.002, z1}, :tile_pattern)
      |> Mesh.matter(:concrete)
    end
  end

  defp tiles({x0, y0}, {x1, y1}, z0, z1, _level),
    do: [Shape.box({x0, y0, z0}, {x1, y1, z1}, :tile_pattern) |> Mesh.matter(:concrete)]

  defp steps(a, b, step), do: for(k <- 0..(ceil((b - a) / step - 1.0e-9) - 1)//1, do: a + k * step)

  @doc """
  A piece of the gutter beside the curb: a channel of 0.3 m inside and
  0.4 m deep with walls of 0.1 m, under covers of concrete of 0.5 m, and
  one grate of iron (bars) in each piece.
  """
  def gutter(shape) do
    w = 0.5
    {{lx, ly}, edges} = plan(shape, w)
    level = Detail.level()
    {d, t} = {0.4, 0.1}

    walls =
      [Shape.box({0.0, 0.0, -d}, {lx, ly, -d + 0.08}, :concrete)] ++
        for e <- edges ++ open_walls(shape) do
          case e do
            :y0 -> Shape.box({0.0, 0.0, -d + 0.08}, {lx, t, -0.05}, :concrete)
            :y1 -> Shape.box({0.0, ly - t, -d + 0.08}, {lx, ly, -0.05}, :concrete)
            :x0 -> Shape.box({0.0, t, -d + 0.08}, {t, ly - t, -0.05}, :concrete)
          end
        end

    n = max(round(lx / 0.5), 1)

    covers =
      for k <- 0..(n - 1) do
        {a, b} = {k * lx / n + 0.005, (k + 1) * lx / n - 0.005}

        if k == 0 and level == :near,
          do: grate({a, 0.0}, {b, ly}),
          else: [Shape.box({a, 0.0, -0.05}, {b, ly, 0.0}, :concrete)]
      end

    parts = Enum.map(walls, &Mesh.matter(&1, :concrete)) ++ List.flatten(covers)

    piece("muong_#{shape}", shape, parts, {lx, ly}, [
      "The gutter (mương): a channel of 0.3 by 0.4 m under covers of concrete and grates of iron: by eye, from the streets of Vũng Tàu."
    ])
  end

  # The wall at the back of a gutter that does not turn.
  defp open_walls(:straight), do: [:y1]
  defp open_walls(_shape), do: []

  defp grate({x0, y0}, {x1, y1}) do
    frame = Shape.box({x0, y0, -0.05}, {x1, y0 + 0.03, 0.0}, :iron)
    back = Shape.box({x0, y1 - 0.03, -0.05}, {x1, y1, 0.0}, :iron)

    bars =
      for x <- steps(x0 + 0.03, x1 - 0.03, 0.05),
          do: Shape.box({x, y0 + 0.03, -0.05}, {x + 0.012, y1 - 0.03, 0.0}, :iron)

    Enum.map([frame, back | bars], &Mesh.matter(&1, :steel))
  end

  @doc """
  A piece of the concrete paving of a hẻm, 3 m wide (`width`, 2 to 4 m),
  0.12 m thick, its top at the street: cracks (thin dark lines) and
  patches of asphalt and of new concrete by its seed, at near and mid.
  """
  def hem(shape, opts \\ []) do
    w = Keyword.get(opts, :width, 3.0)
    seed = Keyword.get(opts, :seed, 1)
    {{lx, ly}, _edges} = plan(shape, w)
    level = Detail.level()
    s = :rand.seed_s(:exsss, {seed + 11, 3, 5})
    {r, _} = Enum.map_reduce(1..8, s, fn _, s -> :rand.uniform_s(s) end)
    [c1, c2, c3, p1, p2, p3, p4, k] = r

    slab = Shape.box({0.0, 0.0, -0.12}, {lx, ly, 0.0}, :concrete) |> Mesh.matter(:concrete)

    marks =
      if level == :far do
        []
      else
        # Two cracks across, and a patch.
        cracks =
          for {a, b} <- [{c1, c2}, {c2, c3}] do
            {xa, xb} = {a * lx, b * lx}
            crack({xa, 0.05}, {xb, ly - 0.05})
          end

        {px, py} = {p1 * (lx - 0.8), p2 * (ly - 0.6)}
        role = if k < 0.5, do: :asphalt, else: :concrete
        patch = Shape.box({px, py, 0.0}, {px + 0.4 + p3 * 0.4, py + 0.3 + p4 * 0.3, 0.006}, role)
        cracks ++ [Mesh.matter(patch, :concrete)]
      end

    piece("hem_#{shape}", shape, [slab | marks], {lx, ly}, [
      "The concrete paving of a hẻm: a slab of 0.12 m with cracks and patches, by eye from the hẻm of Vũng Tàu."
    ])
  end

  # A crack: a thin line of the role `asphalt` over the slab.
  defp crack({x0, y0}, {x1, y1}) do
    {dx, dy} = {x1 - x0, y1 - y0}
    len = :math.sqrt(dx * dx + dy * dy)
    {nx, ny} = {-dy / len * 0.006, dx / len * 0.006}

    [{x0 + nx, y0 + ny}, {x1 + nx, y1 + ny}, {x1 - nx, y1 - ny}, {x0 - nx, y0 - ny}]
    |> Shape.prism(0.003, :asphalt)
    |> Mesh.matter(:concrete)
  end

  @doc """
  The ramp cut of a sidewalk: the curb 3 cm over the street and the
  sidewalk a slope up to its top in 0.8 m, where the scooters go up to a
  house, 2 m long.
  """
  def ramp_cut do
    w = 3.0
    level = Detail.level()
    low = 0.03
    curb = Shape.box({0.0, 0.0, 0.0}, {@len, @curb, low}, :concrete)
    base = Shape.box({0.0, @curb + 0.8, 0.0}, {@len, w, @walk - 0.03}, :concrete)

    slope =
      [{@curb, 0.0}, {@curb + 0.8, 0.0}, {@curb + 0.8, @walk}, {@curb, low}]
      |> Shape.prism(@len, :concrete, frame: World.Frame.new({0.0, 0.0, 0.0}, {1, 0, 0}, {0, 0, 1}))

    tiles = tiles({0.0, @curb + 0.8}, {@len, w}, @walk - 0.03, @walk, level)

    piece("via_he_ram", :straight, Enum.map([curb, base, slope], &Mesh.matter(&1, :concrete)) ++ tiles, {@len, w}, [
      "The ramp cut (dốc dắt xe): the curb low and a slope of concrete in front of a house, by eye from the streets of Vũng Tàu."
    ])
  end

  # A piece: one part, its ports `join` at each side that the next piece
  # meets, and its surface data.
  defp piece(name, shape, meshes, {lx, ly}, sources) do
    joins =
      case shape do
        :straight ->
          [{{0.0, 0.0, 0.0}, {-1.0, 0.0, 0.0}}, {{lx, 0.0, 0.0}, {1.0, 0.0, 0.0}}]

        :corner ->
          [{{lx, 0.0, 0.0}, {1.0, 0.0, 0.0}}, {{0.0, ly, 0.0}, {0.0, 1.0, 0.0}}]

        :junction ->
          [{{0.0, 0.0, 0.0}, {-1.0, 0.0, 0.0}}, {{lx, 0.0, 0.0}, {1.0, 0.0, 0.0}}, {{0.0, ly, 0.0}, {0.0, 1.0, 0.0}}]
      end

    ports = for {at, n} <- joins, do: port("join", at, n, [0.0, 0.0, 0.0])
    corners = [[0.0, 0.0], [lx, 0.0], [0.0, ly], [lx, ly]]
    assembly(name, [Part.new(name, :street, meshes, [@o], sources: [])], sources, ports, corners)
  end

  defp port(kind, at, normal, size, extra \\ %{}),
    do: Map.merge(%{"kind" => kind, "at" => Vec.float(at), "normal" => Vec.float(normal), "size" => size}, extra)

  defp assembly(name, [root | rest], sources, ports, corners) do
    extras = %{"ports" => ports, "surface" => %{"corners" => corners}}
    asm = Assembly.new(name, root, root: root.name, kind: :street, sources: sources, extras: extras)
    Enum.reduce(rest, asm, fn p, a -> Assembly.add(a, p.name, p, at: "o", port: "o") end)
  end

  # --- The things on the sidewalk ---------------------------------------------

  @doc """
  The concrete power pole: a centrifugal pole (cột bê tông ly tâm) of
  12 m, 10 m over the ground (2 m in it), 0.33 m wide at the ground and
  0.19 m at the top; two crossarms of steel across the line at 9.6 and
  8.9 m with insulators, a clamp of the cables at 7.5 m with a coil of
  the bundles of cables (near and mid), and the ports: `wire` at each
  insulator and at the clamp (along the street, both ways), `meter` and
  `transformer` on the pole, `lamp` for the arm of a lamp.
  """
  def pole do
    level = Detail.level()
    h = 10.0
    body = Shape.lathe([{0.0, 0.0}, {0.165, 0.0}, {0.095, h}, {0.0, h}], :concrete) |> Mesh.matter(:concrete)

    arms =
      for z <- [9.6, 8.9] do
        Shape.box({-0.04, -1.0, z}, {0.04, 1.0, z + 0.075}, :iron) |> Mesh.matter(:steel)
      end

    insulators =
      if level == :far,
        do: [],
        else:
          for(
            z <- [9.6, 8.9],
            y <- [-0.8, -0.3, 0.3, 0.8],
            do:
              Shape.cylinder(0.05, 0.15, :porcelain, frame: World.Frame.move({0.0, y, z + 0.075}))
              |> Mesh.matter(:porcelain)
          )

    coil = if level == :far, do: [], else: coil(7.2, level)
    part = Part.new("cot_dien_12m", :street, [body | arms ++ insulators ++ coil], [@o], sources: [])

    wires =
      for z <- [9.6, 8.9], y <- [-0.8, -0.3, 0.3, 0.8], n <- [{1.0, 0.0, 0.0}, {-1.0, 0.0, 0.0}] do
        port("wire", {0.0, y, z + 0.225}, n, [0.02, 0.02, 0.02], %{"line" => "high"})
      end

    low =
      for n <- [{1.0, 0.0, 0.0}, {-1.0, 0.0, 0.0}],
          do: port("wire", {0.0, 0.0, 7.5}, n, [0.06, 0.06, 0.06], %{"line" => "low"})

    others = [
      port("meter", {0.0, 0.14, 2.6}, {0.0, 1.0, 0.0}, [0.5, 0.7, 0.22]),
      port("transformer", {0.0, -0.13, 6.0}, {0.0, -1.0, 0.0}, [1.0, 1.4, 0.8]),
      port("lamp", {0.0, 0.11, 8.0}, {0.0, 1.0, 0.0}, [0.1, 0.1, 1.5])
    ]

    assembly(
      "cot_dien_12m",
      [part],
      [
        "A centrifugal concrete pole of 12 m (cột bê tông ly tâm), 2 m in the ground; its diameters, the crossarms and the insulators by eye, from the streets of Vũng Tàu.",
        "The coil of the bundles of cables on the pole: by eye, from photos of the streets of Việt Nam."
      ],
      wires ++ low ++ others,
      []
    )
  end

  # A coil of cables round the pole: loops of black cable at near, fewer
  # at mid.
  defp coil(z, level) do
    n = if level == :near, do: 6, else: 2

    for k <- 0..(n - 1) do
      r = 0.22 + 0.03 * rem(k, 3)
      dz = z + 0.06 * k
      tilt = 0.08 * (rem(k, 2) * 2 - 1)

      line =
        for j <- 0..12 do
          a = 2 * :math.pi() * j / 12
          {r * :math.cos(a), r * :math.sin(a), dz + tilt * :math.sin(a)}
        end

      Shape.sweep(line, 0.012, :rubber, sides: 6) |> Mesh.matter(:rubber)
    end
  end

  @doc """
  A transformer on its pole (by eye: a tank of 0.7 by 0.5 by 1.0 m, the
  fins of its radiator at near, three bushings), on a bracket with the
  port `pole` (to the port `transformer` of the pole), and `wire` ports
  at its bushings.
  """
  def transformer do
    level = Detail.level()
    tank = Shape.box({-0.35, -0.75, 0.0}, {0.35, -0.25, 1.0}, :metal) |> Mesh.skin(0.006, :steel)
    bracket = Shape.box({-0.4, -0.25, 0.05}, {0.4, 0.0, 0.15}, :iron) |> Mesh.matter(:steel)

    fins =
      if level == :near,
        do:
          for(
            x <- steps(-0.3, 0.3, 0.06),
            do: Shape.box({x, -0.85, 0.1}, {x + 0.02, -0.75, 0.9}, :metal) |> Mesh.matter(:steel)
          ),
        else: []

    bushings =
      if level == :far,
        do: [],
        else:
          for(
            x <- [-0.2, 0.0, 0.2],
            do:
              Shape.cylinder(0.04, 0.25, :porcelain, frame: World.Frame.move({x, -0.5, 1.0})) |> Mesh.matter(:porcelain)
          )

    # A transformer of 50 kVA with its oil: about 400 kg (by eye, from
    # the data of common transformers on a pole).
    part =
      Part.new("may_bien_ap", :street, [tank, bracket | fins ++ bushings], [@o],
        params: %{"mass" => 400.0},
        sources: ["A transformer of 50 kVA on a pole, with its oil: about 400 kg (by eye)."]
      )

    ports =
      [port("pole", {0.0, 0.0, 0.1}, {0.0, 1.0, 0.0}, [0.8, 0.1, 0.25])] ++
        for x <- [-0.2, 0.0, 0.2], do: port("wire", {x, -0.5, 1.25}, {0.0, 0.0, 1.0}, [0.02, 0.02, 0.02])

    assembly(
      "may_bien_ap",
      [part],
      ["A transformer on a pole: its tank and fins by eye, from the streets of Vũng Tàu."],
      ports,
      []
    )
    |> site()
  end

  # A thing that hangs on a pole or a wall: its site holds it.
  defp site(asm), do: %{asm | extras: Map.put(asm.extras, "site", true)}

  @doc """
  The meter boxes on a pole (hộp công tơ): a box of composite of 0.5 by
  0.22 by 0.7 m with a window for four meters, the port `pole`, a `wire`
  port in at its top and four out at its bottom (to the houses).
  """
  def meter_box do
    level = Detail.level()
    box = Shape.box({-0.25, 0.0, 0.0}, {0.25, 0.22, 0.7}, :plastic) |> Mesh.skin(0.004, :plastic)

    window =
      if level == :far, do: [], else: [Shape.box({-0.2, 0.22, 0.25}, {0.2, 0.225, 0.6}, :glass) |> Mesh.matter(:glass)]

    part = Part.new("hop_cong_to", :street, [box | window], [@o], sources: [])

    ports =
      [
        port("pole", {0.0, 0.0, 0.35}, {0.0, -1.0, 0.0}, [0.5, 0.7, 0.22]),
        port("wire", {0.0, 0.11, 0.7}, {0.0, 0.0, 1.0}, [0.03, 0.03, 0.03])
      ] ++
        for x <- [-0.18, -0.06, 0.06, 0.18],
            do: port("wire", {x, 0.11, 0.0}, {0.0, 0.0, -1.0}, [0.02, 0.02, 0.02], %{"line" => "house"})

    assembly(
      "hop_cong_to",
      [part],
      ["The meter boxes of a pole for four houses: by eye, from the streets of Vũng Tàu."],
      ports,
      []
    )
    |> site()
  end

  @doc """
  A street lamp: a tapered pole of steel of 8 m on a base plate and a
  plinth of concrete, an arm
  of 1.5 m out over the street and an LED head (by eye), and the port
  `base`.
  """
  def lamp do
    h = 8.0
    # The pole on a plinth of concrete of 0.6 m and a base plate (by eye).
    plinth = Shape.box({-0.3, -0.3, 0.0}, {0.3, 0.3, 0.2}, :concrete) |> Mesh.matter(:concrete)
    plate = Shape.box({-0.2, -0.2, 0.2}, {0.2, 0.2, 0.22}, :metal) |> Mesh.matter(:steel)
    # Tubes and sheets of steel and aluminum of 3 to 4 mm (by eye).
    pole = Shape.lathe([{0.0, 0.22}, {0.09, 0.22}, {0.04, h}, {0.0, h}], :metal) |> Mesh.skin(0.004, :steel)
    line = [{0.0, 0.0, h - 0.3}, {0.0, -0.6, h + 0.05}, {0.0, -1.5, h + 0.15}]
    arm = line |> Shape.sweep(0.03, :metal) |> Mesh.skin(0.003, :steel)
    head = Shape.box({-0.13, -1.85, h + 0.05}, {0.13, -1.3, h + 0.17}, :aluminum) |> Mesh.skin(0.003, :aluminum)
    lens = Shape.box({-0.11, -1.82, h + 0.04}, {0.11, -1.33, h + 0.05}, :glass) |> Mesh.matter(:glass)
    part = Part.new("den_duong", :street, [plinth, plate, pole, arm, head, lens], [@o], sources: [])

    ports = [
      port("base", {0.0, 0.0, 0.0}, {0.0, 0.0, -1.0}, [0.6, 0.2, 0.6]),
      port("light", {0.0, -1.57, h + 0.04}, {0.0, 0.0, -1.0}, [0.22, 0.01, 0.5])
    ]

    assembly(
      "den_duong",
      [part],
      ["A street lamp of 8 m with an LED head: by eye, from the streets of Vũng Tàu."],
      ports,
      []
    )
  end

  @doc """
  A bin of 240 L on two wheels (the common green bin of the cities of
  Việt Nam): 0.58 by 0.73 by 1.07 m (EN 840-1 bins of 240 L), the body,
  two wheels of 0.2 m, and the lid on a hinge at the back (the role
  `:open`, 0 to 180 degrees).
  """
  def bin do
    level = Detail.level()
    {w, d, h} = {0.58, 0.73, 1.0}

    body =
      [
        {{-0.25, -0.3, 0.0}, {0.25, 0.3, 0.0}},
        {{-w / 2, -d / 2 + 0.06, h}, {w / 2, d / 2 - 0.06, h}}
      ]
      |> then(fn [{a0, a1}, {b0, b1}] -> taper(a0, a1, b0, b1) end)
      |> Mesh.skin(0.005, :plastic)

    axle = Shape.cylinder(0.012, w, :steel, frame: World.Frame.new({-w / 2, -d / 2 + 0.08, 0.1}, {1, 0, 0}, {0, 0, 1}))

    wheels =
      for x <- [-w / 2 - 0.05, w / 2] do
        Shape.cylinder(0.1, 0.05, :rubber,
          sides: if(level == :far, do: 8, else: 16),
          frame: World.Frame.new({x, -d / 2 + 0.08, 0.1}, {1, 0, 0}, {0, 0, 1})
        )
        |> Mesh.matter(:rubber)
      end

    handle =
      Shape.box({-w / 2 + 0.04, -d / 2 - 0.02, h - 0.12}, {w / 2 - 0.04, -d / 2 + 0.03, h - 0.08}, :plastic)
      |> Mesh.matter(:plastic)

    body_part =
      Part.new("thung_rac_240l", :street, [body, Mesh.matter(axle, :steel), handle | wheels], [@o], sources: [])

    lid =
      Part.new(
        "nap_thung_rac",
        :street,
        [Shape.box({-w / 2, 0.0, 0.0}, {w / 2, d, 0.07}, :plastic) |> Mesh.skin(0.005, :plastic)],
        [%{Part.port("hinge", {0.0, 0.0, 0.0}, {1, 0, 0}, {0, 0, 1}) | name: "hinge"}],
        sources: []
      )

    asm =
      Assembly.new("thung_rac_240l", body_part,
        root: body_part.name,
        kind: :street,
        sources: ["A bin of 240 L on two wheels: 580 by 730 by 1075 mm (the size of the bins of 240 L of EN 840-1)."],
        materials: %{plastic: %{"color" => [34, 120, 64], "roughness" => 0.6, "metalness" => 0.0}},
        extras: %{"ports" => [port("base", {0.0, 0.0, 0.0}, {0.0, 0.0, -1.0}, [w, 0.0, d])]}
      )

    Assembly.add(asm, "nap_thung_rac", lid,
      at: %{Part.port("lid", {0.0, -d / 2, h}, {1, 0, 0}, {0, 0, 1}) | name: "lid"},
      port: "hinge",
      kind: :hinge,
      role: :open,
      limits: [0.0, 180.0]
    )
  end

  # A closed body between two rectangles (the bottom and the top), each
  # `{{x0, y0, z}, {x1, y1, z}}`.
  defp taper({ax0, ay0, az}, {ax1, ay1, _}, {bx0, by0, bz}, {bx1, by1, _}) do
    points = [
      {ax0, ay0, az},
      {ax1, ay0, az},
      {ax1, ay1, az},
      {ax0, ay1, az},
      {bx0, by0, bz},
      {bx1, by0, bz},
      {bx1, by1, bz},
      {bx0, by1, bz}
    ]

    faces = [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
    Mesh.new(points, Mesh.outside(points, faces), :plastic)
  end
end
