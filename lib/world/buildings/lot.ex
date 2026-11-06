defmodule World.Buildings.Lot do
  @moduledoc """
  A whole house on a lot of a town of Việt Nam, as the houses of Vũng
  Tàu were in 2019 (the requests W17 and W23 of Vũng Tàu): one order
  makes one house, cheap enough for a town of thousands of houses.

  The kind of this step is the tube house (nhà ống): a narrow front of 3
  to 6 m on the street, a deep lot of 8 to 25 m, 1 to 8 floors on a
  frame of concrete, walls of hollow brick (gạch ống) under plaster. The
  ground floor opens to the street with a roll-up shutter (cửa cuốn), a
  folding iron gate (cửa xếp), a door with an iron gate, or an open
  shop; a step and a small ramp for the scooters lead up to its floor,
  20 cm over the street. Each floor over it has a balcony with a rail (or
  a sunshade over its windows), and some balconies have an iron cage.
  The roof is a flat terrace with a parapet, corrugated metal, or clay
  tiles. The options: `width`, `depth`, `floors`, `style` (`:old`: wood
  shutters, rails of bars, a cửa xếp, rebar on the terrace; `:new`:
  glass in aluminum frames, rails of tubes), `roof`, `ground`, `finish`
  (the front of the ground floor plain, of polished granite, or the
  whole front of patterned tiles), `left` and `right` (each side wall,
  as seen from the street: `:shared` with a neighbor, `:free` with
  windows, or `:bare` brick from the ground to the roof), `extension` (a
  room of one floor at the back), `terrace_room` (a room on a flat
  terrace), `paint_age` (0 to 1) and `seed`. The seed picks the details
  (the balconies, the cages, the places of the doors and the windows);
  the paint age changes no shape: it goes into the extras for the
  plaster shader of the app. The same options give the same house.

  The parts have the roles of W23: `plaster`, `brick_ong`,
  `tile_granite`, `tile_pattern`, `metal_shutter`, `iron`,
  `roof_corrugated`, `roof_clay`, `concrete` and `glass`, and `wood` and
  `aluminum` for the shutters, the doors and the frames. The UVs are in
  meters, and the height and the distance to a corner are in the data
  of each point (`World.Surface`). Each level (near, mid, far) has its
  own shapes: the bars, the slats, the ribs of the metal and the courses
  of the tiles only at near; panels at mid; at far, a box with its roof.

  The axes: x across the front (+x is at the left as seen from the
  street), y to the street (the front of the lot is at y = depth / 2),
  z up from the street. The origin is at the center of the lot, on the
  street: the balconies and the ramp go out of the lot, over the
  sidewalk, as on the real street.
  """
  alias World.{Assembly, Detail, Mesh, Part, Shape, Vec}

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  # The floor of the ground floor over the street (W20).
  @plinth 0.2
  # The height of the ground floor, floor to floor: at least 3.6 m clear
  # (TCVN 9411:2012), and a slab.
  @ground 3.8
  # The height of a floor over it, floor to floor (by eye: 3.3 to 3.6 m).
  @storey 3.4
  # A rail and a parapet: 1.1 m (the common height of a rail; 0.9 m at
  # the least).
  @rail 1.1
  # The piers at the sides of the ground floor, and the top of its
  # opening over the street.
  @pier 0.25
  @opening 3.2
  # The walls: a front of 2 wythes of gạch ống (8 by 8 by 18 cm) under
  # plaster, a side wall of 1 wythe (by eye).
  @front_wall 0.2
  @side_wall 0.11
  # A balcony goes 0.6 to 1.2 m out (Vũng Tàu, plan 0004, R7; the rules of
  # a street front: 0.9 to 1.4 m by the width of the street).
  @reach {0.6, 1.2}
  # The slope of a metal roof and of a roof of clay tiles (by eye).
  @pitch %{corrugated: 12.0, clay: 30.0}

  @kinds [:tube]
  @styles [:old, :new]
  @roofs [:flat, :corrugated, :clay]
  @grounds [:cua_cuon, :cua_xep, :door_gate, :open_shop]
  @finishes [:plain, :granite, :pattern]
  @sides [:shared, :free, :bare]

  @doc "The values of each choice of a house: `kind`, `style`, `roof`, `ground`, `finish` and the sides."
  def choices,
    do: %{kind: @kinds, style: @styles, roof: @roofs, ground: @grounds, finish: @finishes, side: @sides}

  @doc """
  The houses of the catalog: a new tube house of 4 by 16 m, an old one
  of 4 by 18 m with a bare wall and a free wall, and a house of 5 by 20 m
  with two floors and a roof of clay tiles.
  """
  def models do
    [
      {"nha_ong_4x16", fn -> house(name: "nha_ong_4x16") end},
      {"nha_ong_cu_4x18",
       fn ->
         house(
           name: "nha_ong_cu_4x18",
           depth: 18.0,
           floors: 4,
           style: :old,
           roof: :corrugated,
           ground: :cua_xep,
           finish: :pattern,
           left: :bare,
           right: :free,
           extension: true,
           paint_age: 0.8,
           seed: 7
         )
       end},
      {"nha_ong_5x20",
       fn ->
         house(
           name: "nha_ong_5x20",
           width: 5.0,
           depth: 20.0,
           floors: 2,
           roof: :clay,
           ground: :door_gate,
           finish: :plain,
           right: :free,
           seed: 4
         )
       end}
    ]
  end

  @doc """
  A house from its options (see the module). Its name is `name`
  (`"nha_ong"` by default).
  """
  def house(opts \\ []) do
    o = options(opts)
    plan = plan(o)
    level = Detail.level()

    parts =
      [
        part("walls", walls(o, plan, level)),
        part("front_ground", front_ground(o, plan, level)),
        part("slabs", slabs(o, plan, level)),
        part("windows", windows(o, plan, level)),
        part("iron", iron(o, plan, level)),
        part("roof", roof(o, plan, level)),
        part("inside", inside(o, plan, level)),
        part("extension", extension(o, plan, level)),
        part("terrace_room", terrace_room(o, plan, level))
      ]
      |> Enum.reject(&(&1.shapes == []))
      |> Enum.map(&%{&1 | name: "#{&1.name}_#{o.name}"})

    [root | rest] = parts

    asm =
      Assembly.new(o.name, root,
        root: root.name,
        kind: :house,
        sources: sources(o),
        extras: extras(o, plan)
      )

    asm = Enum.reduce(rest, asm, fn p, a -> Assembly.add(a, p.name, p, at: "o", port: "o") end)
    shutter(asm, o, plan, level)
  end

  # --- The options and the plan ---------------------------------------------

  defp options(opts) do
    get = fn key, default -> Keyword.get(opts, key, default) end

    o = %{
      name: get.(:name, "nha_ong"),
      kind: get.(:kind, :tube),
      width: get.(:width, 4.0) / 1,
      depth: get.(:depth, 16.0) / 1,
      floors: get.(:floors, 3),
      style: get.(:style, :new),
      roof: get.(:roof, :flat),
      ground: get.(:ground, :cua_cuon),
      finish: get.(:finish, :granite),
      left: get.(:left, :shared),
      right: get.(:right, :shared),
      extension: get.(:extension, false),
      terrace_room: get.(:terrace_room, false),
      paint_age: get.(:paint_age, 0.3) / 1,
      seed: get.(:seed, 1)
    }

    for {k, v} <- [
          kind: o.kind,
          style: o.style,
          roof: o.roof,
          ground: o.ground,
          finish: o.finish,
          left: o.left,
          right: o.right
        ],
        not Enum.member?(Map.fetch!(choices(), if(k in [:left, :right], do: :side, else: k)), v),
        do: raise(ArgumentError, "a house has no #{k} #{inspect(v)}")

    unless o.width >= 3.0 and o.width <= 6.0, do: raise(ArgumentError, "the width of a house is 3 to 6 m")
    unless o.depth >= 8.0 and o.depth <= 25.0, do: raise(ArgumentError, "the depth of a house is 8 to 25 m")
    unless o.floors in 1..8, do: raise(ArgumentError, "a house has 1 to 8 floors")
    o
  end

  # The heights of the floors, the back of the main block, and the
  # details that the seed picks.
  defp plan(o) do
    s = :rand.seed_s(:exsss, {o.seed + 1, 7_919, 104_729})
    {r, s} = draws(s, 8)
    [r_reach, r_side, r_cage, r_ext, r_balcony, r_sunshade, r_bars, r_window] = r
    floors = for i <- 0..o.floors, do: floor_z(i)
    top = List.last(floors)
    ext = if o.extension, do: Float.round(min(3.0 + 2.0 * r_ext, o.depth * 0.3), 2), else: 0.0
    {lo, hi} = @reach
    # Each floor over the ground: a balcony or a sunshade over its windows.
    {flags, _} = draws(s, o.floors)

    balconies =
      for {f, i} <- Enum.with_index(flags), i > 0 do
        if f < 0.25 + 0.5 * r_balcony, do: :balcony, else: :sunshade
      end

    %{
      floors: floors,
      top: top,
      back: -o.depth / 2 + ext,
      ext: ext,
      reach: Float.round(lo + (hi - lo) * r_reach, 2),
      door_left: r_side < 0.5,
      cage: r_cage < if(o.style == :old, do: 0.6, else: 0.3),
      balconies: balconies,
      sunshade: r_sunshade < 0.7,
      bars: o.style == :old or r_bars < 0.3,
      window: o.width >= 4.0 and r_window < 0.8
    }
  end

  defp draws(s, n), do: Enum.map_reduce(1..n//1, s, fn _, s -> :rand.uniform_s(s) end)

  # The height of the floor `i` over the street (0 is the ground floor).
  defp floor_z(0), do: @plinth
  defp floor_z(i), do: @plinth + @ground + @storey * (i - 1)

  # The extras of the house: the lot, the corners for the surface data,
  # the paint age and the seed for the shader of the app.
  defp extras(o, plan) do
    hw = o.width / 2
    corners = [[-hw, o.depth / 2], [hw, o.depth / 2], [-hw, plan.back], [hw, plan.back]]
    corners = if plan.ext > 0, do: corners ++ [[-hw, -o.depth / 2], [hw, -o.depth / 2]], else: corners

    %{
      "surface" => %{
        "corners" => corners,
        "uv" => "meters",
        "uv2" => "height and distance to a corner, m",
        "color_0" =>
          "red: height / #{World.Surface.height_scale()} m; green: distance to a corner / #{World.Surface.reach_scale()} m"
      },
      "lot" => %{"width" => o.width, "depth" => o.depth},
      "house" => %{
        "kind" => Atom.to_string(o.kind),
        "style" => Atom.to_string(o.style),
        "roof" => Atom.to_string(o.roof),
        "ground" => Atom.to_string(o.ground),
        "finish" => Atom.to_string(o.finish),
        "floors" => o.floors,
        "left" => Atom.to_string(o.left),
        "right" => Atom.to_string(o.right),
        "height" => Float.round(plan.top + if(o.roof == :flat, do: @rail, else: 0.0), 3)
      },
      "paint_age" => o.paint_age,
      "seed" => o.seed
    }
  end

  defp sources(o) do
    [
      "A #{o.kind} house of Vũng Tàu, 2019: #{o.floors} floors on a lot of #{o.width} by #{o.depth} m (World.Buildings.Lot).",
      "The ground floor: 3.6 m clear at the least (TCVN 9411:2012, nhà ở liên kế); its floor 0.2 m over the street (Vũng Tàu, W20).",
      "A balcony: 0.6 to 1.2 m out (Vũng Tàu, plan 0004, R7). A rail and a parapet: 1.1 m.",
      "The heights of the floors over the ground floor, the walls, the slopes of the roofs and the details: by eye, from the photos of the streets of Vũng Tàu of the owner."
    ]
  end

  defp part(name, meshes), do: Part.new(name, :building, meshes, [@o], sources: [])

  # --- The walls ------------------------------------------------------------

  # The side walls, the back wall, the front wall of the floors over the
  # ground floor, and the parapet or the gables.
  defp walls(o, plan, level) do
    hw = o.width / 2
    len = side_length(o, plan)
    top = wall_top(o, plan, level)

    # The side walls go between the front wall and the back wall.
    sides =
      for {side, u, at} <- [
            {o.left, {0.0, 1.0, 0.0}, {hw, plan.back + @front_wall, 0.0}},
            {o.right, {0.0, -1.0, 0.0}, {-hw, o.depth / 2 - @front_wall, 0.0}}
          ] do
        # The holes of the windows only at near; at mid the glass is on the
        # wall (`wall_panes/3`).
        holes = if side == :free and level == :near, do: side_windows(o, plan, len), else: []
        role = if side == :bare, do: :brick_ong, else: :plaster
        sheet(at, u, {0.0, 0.0, 1.0}, len, top, holes, role, ends: @front_wall, skin: {@side_wall, :brick})
      end

    back_holes = if level == :near, do: back_windows(o, plan), else: []

    back =
      sheet({-hw, plan.back, 0.0}, {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, o.width, top, back_holes, :plaster,
        skin: {@front_wall, :brick}
      )

    front_role = if o.finish == :pattern, do: :tile_pattern, else: :plaster

    # At far, the front is one sheet (`front_ground/3`).
    fronts =
      for i <- 1..(o.floors - 1)//1, level != :far do
        {z0, z1} = {Enum.at(plan.floors, i), Enum.at(plan.floors, i + 1)}

        sheet(
          {hw, o.depth / 2, z0},
          {-1.0, 0.0, 0.0},
          {0.0, 0.0, 1.0},
          o.width,
          z1 - z0,
          front_holes(o, plan, i),
          front_role,
          skin: {@front_wall, :brick}
        )
      end

    [back | sides ++ fronts] ++ top_of_walls(o, plan, level)
  end

  # The length of a side wall, and the top of the walls: at far the
  # walls of a flat terrace go up to the top of the parapet.
  defp side_length(o, plan), do: o.depth / 2 - plan.back - 2 * @front_wall
  defp wall_top(%{roof: :flat}, plan, :far), do: plan.top + @rail
  defp wall_top(_o, plan, _level), do: plan.top

  # A window on each floor over the ground floor in the back wall.
  defp back_windows(o, plan) do
    for {z, i} <- Enum.with_index(plan.floors), i > 0 and i < o.floors do
      {o.width / 2 - 0.4, z + 1.0, o.width / 2 + 0.4, z + 2.0, 0.15}
    end
  end

  # The windows of a free side wall: one on each floor over the ground
  # floor, in the front half and the back half of a deep house.
  defp side_windows(o, plan, len) do
    ys = if len > 10, do: [len * 0.3, len * 0.7], else: [len / 2]

    for {z, i} <- Enum.with_index(plan.floors), i > 0 and i < o.floors, y <- ys do
      {y - 0.4, z + 1.0, y + 0.4, z + 2.0, 0.05}
    end
  end

  # The holes of the front of the floor `i`: a door to the balcony (or a
  # window) and a window, in the axes of the sheet (u from the left as
  # seen from the street).
  defp front_holes(o, plan, i) do
    w = o.width
    dw = if w < 4.0, do: 1.2, else: 1.4
    {d0, wx} = if plan.door_left, do: {0.4, 0.4 + dw + 0.4}, else: {w - 0.4 - dw, 0.4}
    balcony? = Enum.at(plan.balconies, i - 1) == :balcony
    door = if balcony?, do: {d0, 0.0, d0 + dw, 2.4, 0.15}, else: {d0, 0.9, d0 + dw, 2.3, 0.2}
    window = if plan.window and wx + 1.2 <= w - 0.3, do: [{wx, 0.9, wx + 1.2, 2.3, 0.2}], else: []
    [door | window]
  end

  # The top of the walls: a parapet round a flat terrace (boxes, its
  # inside also shows from the hills), or a gable at the front and the
  # back of a roof of two slopes.
  defp top_of_walls(o, plan, level) do
    hw = o.width / 2
    {top, front, back} = {plan.top, o.depth / 2, plan.back}

    case o.roof do
      :flat when level == :far ->
        []

      :flat ->
        t = @side_wall
        h = @rail

        [
          Shape.box({-hw, front - t, top}, {hw, front, top + h}, :plaster),
          Shape.box({-hw, back, top}, {hw, back + t, top + h}, :plaster),
          Shape.box({hw - t, back + t, top}, {hw, front - t, top + h}, :plaster),
          Shape.box({-hw, back + t, top}, {-hw + t, front - t, top + h}, :plaster)
        ]
        |> Enum.map(&Mesh.matter(&1, :brick))

      pitched ->
        rise = hw * :math.tan(@pitch[pitched] * :math.pi() / 180)

        for y <- [front - @front_wall, back], do: gable([{-hw, 0.0}, {hw, 0.0}, {0.0, rise}], y, top, @front_wall)
    end
  end

  # A gable: a triangle of the wall (x and the height over the top of the
  # walls), `t` thick from y.
  defp gable(loop, y, top, t) do
    loop
    |> Shape.prism(t, :plaster, frame: World.Frame.new({0.0, y, top}, {0, 1, 0}, {0, 0, 1}))
    |> Mesh.matter(:brick)
  end

  # --- The ground floor -----------------------------------------------------

  # The front of the ground floor: the piers and the beam over the
  # opening (or a wall with a door and a window), of the front finish.
  defp front_ground(o, plan, :far) do
    # All the front in one sheet, of the role of the most of it.
    role = if o.floors > 1 and o.finish != :pattern, do: :plaster, else: ground_role(o)
    hw = o.width / 2

    [
      sheet({hw, o.depth / 2, 0.0}, {-1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, o.width, wall_top(o, plan, :far), [], role,
        skin: {@front_wall, :brick}
      )
    ]
  end

  defp front_ground(o, plan, _level) do
    hw = o.width / 2
    z1 = Enum.at(plan.floors, 1, plan.top)
    role = ground_role(o)

    holes =
      if o.ground == :door_gate,
        do: door_gate_holes(o),
        else: [{@pier, @plinth, o.width - @pier, @opening, 0.12}]

    [
      sheet({hw, o.depth / 2, 0.0}, {-1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, o.width, z1, holes, role,
        vs: [@plinth],
        skin: {@front_wall, :brick}
      )
    ]
  end

  defp ground_role(o), do: %{plain: :plaster, granite: :tile_granite, pattern: :tile_pattern}[o.finish]

  # A door of 1.6 m (two leaves) and a window, in a wall of the front.
  defp door_gate_holes(o) do
    w = o.width
    d0 = if w < 4.0, do: (w - 1.6) / 2, else: 0.5
    window = if w >= 4.0, do: [{w - 0.5 - 1.2, 1.1, w - 0.5, 2.5, 0.15}], else: []
    [{d0, @plinth, d0 + 1.6, 2.6, 0.15} | window]
  end

  # The cửa cuốn: a panel of slats in the opening, on a slide up into
  # its box (the role `:open`, 0 closed to 3 m open). Not for the other
  # fronts, and not at far: there the front is one sheet.
  defp shutter(asm, %{ground: :cua_cuon} = o, _plan, level) when level != :far do
    hw = o.width / 2 - @pier
    y = o.depth / 2 - 0.1
    h = @opening - @plinth

    panel =
      if level == :near,
        do:
          sheet({hw, y, 0.0}, {-1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, 2 * hw, h, [], :metal_shutter,
            vs: ribs(h, 0.08),
            relief: fn _u, v -> if rem(round(v / 0.04), 2) == 0, do: 0.0, else: 0.012 end,
            skin: {0.0008, :steel}
          ),
        else: Shape.box({-hw, y - 0.01, 0.0}, {hw, y, h}, :metal_shutter) |> Mesh.matter(:steel)

    port = Part.port("slide", {0.0, y, @plinth}, {0, 0, 1}, {0, 1, 0})
    part = Part.new("shutter_#{o.name}", :building, [panel], [%{port | name: "slide"}], sources: [])

    Assembly.add(asm, part.name, part,
      at: %{port | name: "shutter_axis"},
      port: "slide",
      kind: :slide,
      role: :open,
      limits: [0.0, h]
    )
  end

  defp shutter(asm, _o, _plan, _level), do: asm

  # The knots of a ribbed sheet: a rib each `step`, with an edge at its
  # half.
  defp ribs(len, step), do: for(k <- 0..round(len / (step / 2)), do: Float.round(min(k * step / 2, len), 4))

  # --- The slabs: balconies, sunshades, the step, the ramp ------------------

  defp slabs(o, plan, level) do
    hw = o.width / 2
    front = o.depth / 2
    step_role = if o.finish == :granite, do: :tile_granite, else: :concrete

    # The step over the width of the opening, and the ramp at its middle.
    ramp_w = min(1.0, o.width - 2 * @pier - 0.6)

    step =
      if level == :far,
        do: [],
        else: [
          Shape.box({-hw + @pier, front, 0.0}, {-ramp_w / 2, front + 0.3, @plinth}, step_role),
          Shape.box({ramp_w / 2, front, 0.0}, {hw - @pier, front + 0.3, @plinth}, step_role),
          ramp(ramp_w, front)
        ]

    upper =
      for {kind, i} <- Enum.with_index(plan.balconies, 1), level != :far do
        z = Enum.at(plan.floors, i)

        case kind do
          :balcony -> Shape.box({-hw, front, z - 0.12}, {hw, front + plan.reach, z}, :concrete)
          :sunshade -> Shape.box({-hw, front, z + 2.45}, {hw, front + 0.5, z + 2.53}, :concrete)
        end
      end

    # A sunshade over the opening of the ground floor.
    over =
      if plan.sunshade and level != :far,
        do: [Shape.box({-hw, front, @opening + 0.2}, {hw, front + 0.6, @opening + 0.28}, :concrete)],
        else: []

    terrace =
      if o.roof == :flat,
        do: [
          Shape.box(
            {-hw + @side_wall, plan.back + @front_wall, plan.top - 0.05},
            {hw - @side_wall, front - @front_wall, plan.top},
            :concrete
          )
        ],
        else: []

    Enum.map(step ++ upper ++ over ++ terrace, &Mesh.matter(&1, :concrete))
  end

  # The ramp for the scooters: a wedge from the street to the floor, 0.8 m
  # long (by eye).
  defp ramp(w, front) do
    [{front, 0.0}, {front + 0.8, 0.0}, {front, @plinth}]
    |> Shape.prism(w, :concrete, frame: World.Frame.new({-w / 2, 0.0, 0.0}, {1, 0, 0}, {0, 0, 1}))
  end

  # --- Windows and doors ----------------------------------------------------

  defp windows(o, plan, level) do
    if level == :far do
      []
    else
      hw = o.width / 2

      for i <- 1..(o.floors - 1)//1, {u0, v0, u1, v1, depth} <- front_holes(o, plan, i) do
        z = Enum.at(plan.floors, i)
        # The sheet goes from the left (+x) to the right: u is -x.
        {x0, x1} = {hw - u1, hw - u0}
        y = o.depth / 2 - depth
        pane(o.style, {x0, y, z + v0}, {x1, y, z + v1}, level, v0 == 0.0)
      end
      |> List.flatten()
      |> Kernel.++(ground_doors(o, plan, level))
      |> Kernel.++(wall_panes(o, plan, level))
    end
  end

  # The glass of the windows of the side walls and of the back wall: in
  # the hole at near, on the face of the wall at mid.
  defp wall_panes(o, plan, level) do
    hw = o.width / 2
    at = fn d -> if level == :near, do: d, else: -0.006 end
    len = side_length(o, plan)
    y0 = plan.back + @front_wall
    y1 = o.depth / 2 - @front_wall

    left =
      if o.left == :free,
        do:
          for(
            {a, b, c, e, d} <- side_windows(o, plan, len),
            d = at.(d),
            do: {{hw - d - 0.006, y0 + a, b}, {hw - d, y0 + c, e}}
          ),
        else: []

    right =
      if o.right == :free,
        do:
          for(
            {a, b, c, e, d} <- side_windows(o, plan, len),
            d = at.(d),
            do: {{-hw + d, y1 - c, b}, {-hw + d + 0.006, y1 - a, e}}
          ),
        else: []

    back =
      for {a, b, c, e, d} <- back_windows(o, plan),
          d = at.(d),
          do: {{-hw + a, plan.back + d, b}, {-hw + c, plan.back + d + 0.006, e}}

    for {lo, hi} <- left ++ right ++ back, do: Shape.box(lo, hi, :glass) |> Mesh.matter(:glass)
  end

  # A window or a door in its hole, at the back of the reveal: glass in
  # an aluminum frame (new), or wood shutters (old).
  defp pane(style, {x0, y, z0}, {x1, _, z1}, level, door?) do
    glass = Shape.box({x0, y - 0.03, z0}, {x1, y - 0.024, z1}, :glass) |> Mesh.matter(:glass)

    cond do
      level == :mid ->
        [glass]

      style == :new ->
        f = 0.05
        mid = (x0 + x1) / 2

        [
          glass,
          Shape.box({x0, y - 0.05, z0}, {x0 + f, y, z1}, :aluminum),
          Shape.box({x1 - f, y - 0.05, z0}, {x1, y, z1}, :aluminum),
          Shape.box({x0, y - 0.05, z0}, {x1, y, z0 + f}, :aluminum),
          Shape.box({x0, y - 0.05, z1 - f}, {x1, y, z1}, :aluminum),
          Shape.box({mid - f / 2, y - 0.05, z0}, {mid + f / 2, y, z1}, :aluminum)
        ]
        |> Enum.map(&Mesh.matter(&1, :aluminum))
        |> then(fn [g | rest] -> [Mesh.matter(g, :glass) | rest] end)

      true ->
        # Two leaves of wood with louvers (a door has panels at the
        # bottom).
        mid = (x0 + x1) / 2

        leaves =
          for {a, b} <- [{x0, mid}, {mid, x1}],
              do: Shape.box({a + 0.005, y - 0.04, z0}, {b - 0.005, y - 0.01, z1}, :wood)

        start = if door?, do: z0 + 0.9, else: z0 + 0.1

        louvers =
          for {a, b} <- [{x0, mid}, {mid, x1}], k <- 0..max(round((z1 - 0.1 - start) / 0.07) - 1, 0) do
            z = start + k * 0.07
            Shape.box({a + 0.06, y - 0.005, z}, {b - 0.06, y, z + 0.035}, :wood)
          end

        Enum.map(leaves ++ louvers, &Mesh.matter(&1, :wood))
    end
  end

  # The door of a front with a door and a gate: two leaves.
  defp ground_doors(%{ground: :door_gate} = o, _plan, level) do
    hw = o.width / 2

    for {u0, v0, u1, v1, depth} <- door_gate_holes(o) do
      pane(o.style, {hw - u1, o.depth / 2 - depth, v0}, {hw - u0, o.depth / 2 - depth, v1}, level, v0 == @plinth)
    end
    |> List.flatten()
  end

  defp ground_doors(_o, _plan, _level), do: []

  # --- Iron: rails, cages, bars, the gate, rebar ----------------------------

  defp iron(o, plan, level) do
    if level == :far do
      []
    else
      hw = o.width / 2
      front = o.depth / 2

      balcony =
        for {:balcony, i} <- Enum.with_index(plan.balconies, 1) do
          z = Enum.at(plan.floors, i)
          z_next = Enum.at(plan.floors, i + 1)
          y = front + plan.reach

          rail(o.style, {-hw, y, z + 0.002}, {hw, y, z + @rail}, level) ++
            if(plan.cage, do: cage({-hw, front, z + 0.002}, {hw, y, z_next - 0.122}, level), else: [])
        end

      bars =
        if plan.bars and level == :near do
          for i <- 1..(o.floors - 1)//1, {u0, v0, u1, v1, _} <- front_holes(o, plan, i), v0 > 0 do
            z = Enum.at(plan.floors, i)
            bars({hw - u1, front - 0.02, z + v0}, {hw - u0, front - 0.02, z + v1})
          end
        else
          []
        end

      gate = gate(o, level)
      rebar = if o.style == :old and o.roof == :flat and level == :near, do: rebar(o, plan), else: []
      Enum.map(List.flatten(balcony ++ bars ++ gate ++ rebar), &Mesh.matter(&1, :steel))
    end
  end

  # A rail of a balcony along x at y: bars (old) or tubes (new), or one
  # panel at mid.
  defp rail(_style, {x0, y, z0}, {x1, _, z1}, :mid) do
    # A post at each end, a top rail and a bottom rail.
    posts = [{x0, x0 + 0.04}, {x1 - 0.04, x1}]

    for({a, b} <- posts, do: Shape.box({a, y - 0.04, z0}, {b, y, z1}, :iron)) ++
      for z <- [z0 + 0.1, z1 - 0.05], do: Shape.box({x0, y - 0.035, z}, {x1, y - 0.005, z + 0.05}, :iron)
  end

  defp rail(:old, {x0, y, z0}, {x1, _, z1}, _level) do
    n = round((x1 - x0) / 0.12)

    tops = [
      Shape.box({x0, y - 0.04, z1 - 0.04}, {x1, y, z1}, :iron),
      Shape.box({x0, y - 0.03, z0 + 0.08}, {x1, y, z0 + 0.11}, :iron)
    ]

    tops ++
      for(
        k <- 1..(n - 1)//1,
        x = x0 + k * (x1 - x0) / n,
        do: Shape.box({x - 0.008, y - 0.024, z0 + 0.08}, {x + 0.008, y - 0.008, z1 - 0.04}, :iron)
      )
  end

  defp rail(:new, {x0, y, z0}, {x1, _, z1}, _level) do
    posts =
      for k <- 0..round((x1 - x0) / 1.0),
          x = min(x0 + k * 1.0, x1 - 0.04),
          do: Shape.box({x, y - 0.04, z0}, {x + 0.04, y, z1}, :iron)

    tubes =
      for k <- 0..3,
          z = z0 + 0.2 + k * (z1 - z0 - 0.24) / 3,
          do: Shape.box({x0, y - 0.035, z}, {x1, y - 0.005, z + 0.03}, :iron)

    posts ++ tubes
  end

  # An iron cage round a balcony (chuồng cọp): bars at its front and its
  # sides from its floor to the slab over it, and flats across.
  defp cage({x0, _y0, z0}, {x1, y1, z1}, :mid), do: [Shape.box({x0, y1, z0}, {x1, y1 + 0.02, z1}, :iron)]

  defp cage({x0, y0, z0}, {x1, y1, z1}, _level) do
    n = round((x1 - x0) / 0.15)
    m = round((y1 - y0) / 0.15)

    front =
      for k <- 0..n,
          x = x0 + k * (x1 - x0) / n,
          do: Shape.box({x - 0.006, y1 + 0.01, z0}, {x + 0.006, y1 + 0.022, z1}, :iron)

    sides =
      for k <- 1..m//1,
          x <- [x0 + 0.01, x1 - 0.022],
          y = y0 + k * (y1 - y0) / m,
          do: Shape.box({x, y - 0.006, z0}, {x + 0.012, y + 0.006, z1}, :iron)

    flats = for z <- [z0 + 1.2, z1 - 0.1], do: Shape.box({x0, y1 + 0.022, z}, {x1, y1 + 0.03, z + 0.03}, :iron)
    front ++ sides ++ flats
  end

  # Security bars in front of a window.
  defp bars({x0, y, z0}, {x1, _, z1}) do
    n = max(round((x1 - x0) / 0.12), 2)

    for k <- 1..(n - 1),
        x = x0 + k * (x1 - x0) / n,
        do: Shape.box({x - 0.007, y, z0}, {x + 0.007, y + 0.014, z1}, :iron)
  end

  # The gate of the ground floor: a cửa xếp (vertical channels and
  # crossed bars) in the opening, or a gate of bars in front of the door.
  defp gate(%{ground: :cua_xep} = o, level) do
    {x0, x1} = {-o.width / 2 + @pier, o.width / 2 - @pier}
    y = o.depth / 2 - 0.06
    {z0, z1} = {@plinth, @opening}

    if level == :mid do
      [Shape.box({x0, y - 0.02, z0}, {x1, y, z1}, :iron)]
    else
      n = round((x1 - x0) / 0.11)

      channels =
        for k <- 0..n, x = x0 + k * (x1 - x0) / n, do: Shape.box({x - 0.01, y - 0.02, z0}, {x + 0.01, y, z1}, :iron)

      rows =
        for z <- [z0 + 0.4, (z0 + z1) / 2, z1 - 0.4],
            do: Shape.box({x0, y - 0.03, z - 0.01}, {x1, y - 0.02, z + 0.01}, :iron)

      channels ++ rows
    end
  end

  defp gate(%{ground: :door_gate} = o, level) do
    hw = o.width / 2
    [{u0, v0, u1, v1, _} | _] = door_gate_holes(o)
    y = o.depth / 2 + 0.02

    if level == :mid,
      do: [Shape.box({hw - u1, y, v0}, {hw - u0, y + 0.02, v1}, :iron)],
      else:
        bars({hw - u1, y, v0}, {hw - u0, y, v1}) ++ [Shape.box({hw - u1, y, v1 - 0.03}, {hw - u0, y + 0.02, v1}, :iron)]
  end

  defp gate(_o, _level), do: []

  # Rebar out of the corners of the parapet, for a floor of the future.
  defp rebar(o, plan) do
    hw = o.width / 2

    for x <- [-hw + 0.05, hw - 0.1], y <- [o.depth / 2 - 0.1, plan.back + 0.05], dx <- [0.0, 0.05] do
      Shape.box({x + dx, y, plan.top + @rail}, {x + dx + 0.012, y + 0.012, plan.top + @rail + 0.8}, :iron)
    end
  end

  # --- The roof -------------------------------------------------------------

  defp roof(%{roof: :flat}, _plan, _level), do: []

  defp roof(o, plan, level) do
    hw = o.width / 2
    a = @pitch[o.roof] * :math.pi() / 180
    slope = hw / :math.cos(a)
    over = 0.15
    {y0, y1} = {plan.back - over, o.depth / 2 + over}
    role = if o.roof == :clay, do: :roof_clay, else: :roof_corrugated
    {skin, matter} = if o.roof == :clay, do: {0.015, :terracotta}, else: {0.0004, :steel}

    relief =
      cond do
        level != :near -> nil
        o.roof == :clay -> fn _u, v -> 0.03 * (1 - frac(v / 0.25)) end
        true -> fn u, _v -> if rem(round(u / 0.125), 2) == 0, do: 0.0, else: 0.025 end
      end

    knots = if level == :near and o.roof == :corrugated, do: [us: ribs(y1 - y0, 0.25)], else: []

    vknots =
      if level == :near and o.roof == :clay,
        do: [vs: Enum.flat_map(1..floor(slope / 0.25)//1, &[&1 * 0.25 - 0.004, &1 * 0.25])],
        else: []

    for {at, u, v} <- [
          {{hw, y0, plan.top}, {0.0, 1.0, 0.0}, {-:math.cos(a), 0.0, :math.sin(a)}},
          {{-hw, y1, plan.top}, {0.0, -1.0, 0.0}, {:math.cos(a), 0.0, :math.sin(a)}}
        ] do
      sheet(at, u, v, y1 - y0, slope, [], role, knots ++ vknots ++ [relief: relief, skin: {skin, matter}])
    end
  end

  defp frac(x), do: x - Float.floor(x)

  # --- The inside of an open ground floor -----------------------------------

  # The room behind a cửa xếp or an open shop: a floor of tiles, a back
  # wall 5 m in, the side walls and a ceiling, so that the street sees a
  # room and not the sky.
  defp inside(%{ground: ground} = o, plan, level) when ground in [:cua_xep, :open_shop] and level != :far do
    # A coat of plaster of 2 cm on the walls of the house, and a floor of
    # light ceramic tiles (by eye).
    hw = o.width / 2 - @side_wall - 0.02
    front = o.depth / 2 - @front_wall
    back = max(front - 5.0, plan.back + 0.5)
    z1 = Enum.at(plan.floors, 1, plan.top) - 0.15
    h = z1 - @plinth

    [
      Shape.box({-hw, back, 0.0}, {hw, front, @plinth}, :tile_granite) |> Mesh.matter(:concrete),
      sheet({-hw, back, @plinth}, {1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, 2 * hw, h, [], :plaster,
        inward: true,
        skin: {0.02, :brick}
      ),
      sheet({hw, back, @plinth}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}, front - back, h, [], :plaster,
        inward: true,
        skin: {0.02, :brick}
      ),
      sheet({-hw, front, @plinth}, {0.0, -1.0, 0.0}, {0.0, 0.0, 1.0}, front - back, h, [], :plaster,
        inward: true,
        skin: {0.02, :brick}
      ),
      sheet({-hw, back, z1}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, 2 * hw, front - back, [], :plaster,
        inward: true,
        skin: {0.1, :concrete}
      )
    ]
  end

  defp inside(_o, _plan, _level), do: []

  # --- The extension and the room on the terrace ----------------------------

  # A room of one floor at the back, with a roof of corrugated metal down
  # to the back.
  defp extension(%{extension: false}, _plan, _level), do: []

  defp extension(o, plan, level) do
    hw = o.width / 2
    {y0, y1} = {-o.depth / 2, plan.back}
    h = @plinth + @storey
    role = fn side -> if side == :bare, do: :brick_ong, else: :plaster end
    a = 8.0 * :math.pi() / 180
    len = (y1 - y0 + 0.3) / :math.cos(a)

    [
      sheet(
        {-hw, y0, 0.0},
        {1.0, 0.0, 0.0},
        {0.0, 0.0, 1.0},
        o.width,
        h,
        if(level == :far, do: [], else: [{o.width / 2 - 0.45, 1.0, o.width / 2 + 0.45, 3.1, 0.12}]),
        :plaster,
        skin: {@side_wall, :brick}
      ),
      sheet({hw, y0 + @side_wall, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}, y1 - y0 - @side_wall, h, [], role.(o.left),
        skin: {@side_wall, :brick}
      ),
      sheet({-hw, y1, 0.0}, {0.0, -1.0, 0.0}, {0.0, 0.0, 1.0}, y1 - y0 - @side_wall, h, [], role.(o.right),
        skin: {@side_wall, :brick}
      ),
      sheet(
        {-hw - 0.1, y0 - 0.3, h},
        {1.0, 0.0, 0.0},
        {0.0, :math.cos(a), :math.sin(a)},
        o.width + 0.2,
        len,
        [],
        :roof_corrugated,
        us: if(level == :near, do: ribs(o.width + 0.2, 0.25), else: []),
        relief: if(level == :near, do: fn u, _v -> if rem(round(u / 0.125), 2) == 0, do: 0.0, else: 0.025 end),
        skin: {0.0004, :steel}
      )
    ]
  end

  # A room at the back of a flat terrace (the room of the stairs), with a
  # door to the terrace and a flat roof.
  defp terrace_room(%{terrace_room: true, roof: :flat} = o, plan, level) do
    hw = o.width / 2 - @side_wall
    {y0, y1} = {plan.back + @side_wall, min(plan.back + 3.0, o.depth / 2 - 1.0)}
    {z0, h} = {plan.top, 2.6}
    door = if level == :far, do: [], else: [{0.3, 0.0, 1.1, 2.1, 0.1}]

    [
      sheet({hw, y1, z0}, {-1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, 2 * hw, h, door, :plaster, skin: {@side_wall, :brick}),
      Shape.box({-hw, y0, z0 + h}, {hw, y1 + 0.3, z0 + h + 0.1}, :concrete) |> Mesh.matter(:concrete)
    ]
  end

  defp terrace_room(_o, _plan, _level), do: []

  # --- A sheet of a wall ----------------------------------------------------

  # A sheet: a closed slab on the rectangle from `at` along `u` (its
  # length) and `v` (its height); its outside face is to u × v
  # (`inward: true` turns it to the other side), and its back is the
  # thickness of `skin` (`{thickness, matter}`) in. The holes are `{u0,
  # v0, u1, v1, depth}` through the slab (the depth is the place of the
  # window or the door in it). The points are at each edge of a hole, at
  # the knots `us` and `vs`, and at the corners, 4 m from them and at the
  # middle of the length (`World.Surface`; `ends`: the corner of the
  # building is this far past each end). `relief` moves each point of
  # the outside face out by a function of u and v (the ribs of metal,
  # the courses of tiles).
  defp sheet(at, u, v, len, ht, holes, role, opts) do
    inward = Keyword.get(opts, :inward, false)
    {t, matter} = Keyword.fetch!(opts, :skin)
    n = Vec.norm(Vec.cross(u, v))
    n = if inward, do: Vec.scale(n, -1.0), else: n
    # `ends`: the corner of the building is this far past each end.
    corner = min(World.Surface.reach_scale() - Keyword.get(opts, :ends, 0.0), len / 2)

    us =
      knots(
        [0.0, len, corner, len / 2, len - corner] ++
          Keyword.get(opts, :us, []) ++ Enum.flat_map(holes, fn {a, _, b, _, _} -> [a, b] end),
        len
      )

    vs = knots([0.0, ht] ++ Keyword.get(opts, :vs, []) ++ Enum.flat_map(holes, fn {_, a, _, b, _} -> [a, b] end), ht)
    {tu, tv} = {List.to_tuple(us), List.to_tuple(vs)}
    {nu, nv} = {tuple_size(tu), tuple_size(tv)}
    relief = Keyword.get(opts, :relief) || fn _, _ -> 0.0 end

    point = fn {side, i, j} ->
      {a, b} = {elem(tu, i), elem(tv, j)}
      base = at |> Vec.add(Vec.scale(u, a)) |> Vec.add(Vec.scale(v, b))
      if side == :f, do: Vec.add(base, Vec.scale(n, relief.(a, b))), else: Vec.add(base, Vec.scale(n, -t))
    end

    hole_at = fn x, y -> Enum.any?(holes, fn {a, b, c, d, _} -> x > a and x < c and y > b and y < d end) end

    solid = fn i, j ->
      i >= 0 and j >= 0 and i < nu - 1 and j < nv - 1 and
        not hole_at.((elem(tu, i) + elem(tu, i + 1)) / 2, (elem(tv, j) + elem(tv, j + 1)) / 2)
    end

    cells = for i <- 0..(nu - 2), j <- 0..(nv - 2), solid.(i, j), do: {i, j}

    # Each cell: its face out, its face at the back, and a face on each
    # edge that has no cell next to it (the rim, and the reveal of a hole).
    faces =
      Enum.flat_map(cells, fn {i, j} ->
        [
          [{:f, i, j}, {:f, i + 1, j}, {:f, i + 1, j + 1}, {:f, i, j + 1}],
          [{:k, i, j + 1}, {:k, i + 1, j + 1}, {:k, i + 1, j}, {:k, i, j}]
        ] ++
          if(solid.(i, j - 1), do: [], else: [[{:f, i + 1, j}, {:f, i, j}, {:k, i, j}, {:k, i + 1, j}]]) ++
          if(solid.(i + 1, j), do: [], else: [[{:f, i + 1, j + 1}, {:f, i + 1, j}, {:k, i + 1, j}, {:k, i + 1, j + 1}]]) ++
          if(solid.(i, j + 1), do: [], else: [[{:f, i, j + 1}, {:f, i + 1, j + 1}, {:k, i + 1, j + 1}, {:k, i, j + 1}]]) ++
          if(solid.(i - 1, j), do: [], else: [[{:f, i, j}, {:f, i, j + 1}, {:k, i, j + 1}, {:k, i, j}]])
      end)

    faces = if inward, do: Enum.map(faces, &Enum.reverse/1), else: faces
    keys = faces |> List.flatten() |> Enum.uniq()
    index = keys |> Enum.with_index() |> Map.new()
    points = Enum.map(keys, point)
    faces = Enum.map(faces, fn f -> Enum.map(f, &index[&1]) end)
    Mesh.new(points, Mesh.outside(points, faces), role) |> Mesh.matter(matter)
  end

  defp knots(list, max) do
    list
    |> Enum.map(&Float.round(min(max(&1 / 1, 0.0), max / 1), 5))
    |> Enum.sort()
    |> Enum.dedup()
  end
end
