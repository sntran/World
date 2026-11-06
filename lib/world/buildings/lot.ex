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
  @interiors [:none, :front_room]

  @doc "The values of each choice of a house: `kind`, `style`, `roof`, `ground`, `finish` and the sides."
  def choices,
    do: %{
      kind: @kinds,
      style: @styles,
      roof: @roofs,
      ground: @grounds,
      finish: @finishes,
      side: @sides,
      interior: @interiors
    }

  @doc """
  The houses of the catalog: a new tube house of 4 by 16 m, an old one
  of 4 by 18 m with a bare wall and a free wall, and a house of 5 by 20 m
  with two floors and a roof of clay tiles, and a homestay of 4 by 14 m
  with an open front room.
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
       end},
      {"nha_ong_homestay_4x14",
       fn ->
         house(
           name: "nha_ong_homestay_4x14",
           depth: 14.0,
           floors: 4,
           ground: :open_shop,
           interior: :front_room,
           seed: 5
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
        part("front_room", front_room(o, plan, level)),
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
      interior: get.(:interior, :none),
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
          right: o.right,
          interior: o.interior
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
      "seed" => o.seed,
      "ports" => ports(o, plan),
      "collision" => collision(o, plan)
    }
  end

  # --- The collision boxes (W20) --------------------------------------------

  # The simple boxes that the game uses in place of the mesh: the walls,
  # the front of the ground floor (the piers, the beam, the parts of a
  # wall with a door, the closed shutter or gate), the floor, the step,
  # the ramp, the room at the back, and the front room. The same at each
  # level. `World.Build` makes a node of each.
  defp collision(o, plan) do
    hw = o.width / 2
    {front, back} = {o.depth / 2, plan.back}
    top = wall_top(o, plan, :far)
    z1 = Enum.at(plan.floors, 1, plan.top)
    box = fn name, {x0, y0, z0}, {x1, y1, z1} -> cbox(name, {x0, y0, z0}, {x1, y1, z1}) end

    walls = [
      box.("wall_left", {hw - @side_wall, back, 0.0}, {hw, front, top}),
      box.("wall_right", {-hw, back, 0.0}, {-hw + @side_wall, front, top}),
      box.("wall_back", {-hw + @side_wall, back, 0.0}, {hw - @side_wall, back + @front_wall, top}),
      box.("front_beam", {-hw + @side_wall, front - @front_wall, @opening}, {hw - @side_wall, front, z1}),
      box.("floor", {-hw + @side_wall, back + @front_wall, 0.0}, {hw - @side_wall, front, @plinth})
    ]

    upper =
      if top > z1,
        do: [box.("front_upper", {-hw + @side_wall, front - @front_wall, z1}, {hw - @side_wall, front, top})],
        else: []

    ramp_w = min(1.0, o.width - 2 * @pier - 0.6)

    step = [
      box.("step_left", {ramp_w / 2, front, 0.0}, {hw - @pier, front + 0.3, @plinth}),
      box.("step_right", {-hw + @pier, front, 0.0}, {-ramp_w / 2, front + 0.3, @plinth}),
      ramp_box(ramp_w, front)
    ]

    ext =
      if plan.ext > 0,
        do: [box.("extension", {-hw, -o.depth / 2, 0.0}, {hw, back, @plinth + @storey})],
        else: []

    walls ++ upper ++ ground_boxes(o, plan) ++ step ++ ext ++ room_boxes(o, plan)
  end

  # A box between two corners (in any order).
  defp cbox(name, {a0, b0, c0}, {a1, b1, c1}) do
    r = &Float.round(&1 / 1, 4)
    {x0, x1, y0, y1, z0, z1} = {min(a0, a1), max(a0, a1), min(b0, b1), max(b0, b1), min(c0, c1), max(c0, c1)}

    %{
      "name" => name,
      "at" => {r.((x0 + x1) / 2), r.((y0 + y1) / 2), r.((z0 + z1) / 2)},
      "size" => {r.(x1 - x0), r.(y1 - y0), r.(z1 - z0)}
    }
  end

  # A box turned about x: from the point `{y0, z0}` to `{y1, z1}` (its top
  # face), `w` wide and `t` thick under it.
  defp slope_box(name, w, {y0, z0}, {y1, z1}, t, x \\ 0.0) do
    {dy, dz} = {y1 - y0, z1 - z0}
    len = :math.sqrt(dy * dy + dz * dz)
    up = {0.0, dy / len, dz / len}
    # The normal up from the face, on the side of +z.
    n = if dy >= 0, do: {0.0, -dz / len, dy / len}, else: {0.0, dz / len, -dy / len}
    mid = Vec.sub({x, (y0 + y1) / 2, (z0 + z1) / 2}, Vec.scale(n, t / 2))
    r = &Float.round(&1 / 1, 4)
    {mx, my, mz} = mid

    %{
      "name" => name,
      "at" => {r.(mx), r.(my), r.(mz)},
      "size" => {r.(w), r.(len), r.(t)},
      "axis" => n,
      "up" => up
    }
  end

  defp ramp_box(w, front), do: slope_box("ramp", w, {front, @plinth}, {front + 0.8, 0.0}, 0.05)

  # The front of the ground floor: the piers, and the closed shutter (it
  # moves with its node), the gate, or the wall round a door.
  defp ground_boxes(o, _plan) do
    hw = o.width / 2
    front = o.depth / 2
    {y0, y1} = {front - @front_wall, front}

    piers = [
      cbox("pier_left", {hw - @pier, y0, 0.0}, {hw, y1, @opening}),
      cbox("pier_right", {-hw, y0, 0.0}, {-hw + @pier, y1, @opening})
    ]

    piers ++
      case o.ground do
        :cua_cuon ->
          [
            Map.put(
              cbox("shutter", {-hw + @pier, y1 - 0.12, @plinth}, {hw - @pier, y1 - 0.08, @opening}),
              "node",
              "shutter_#{o.name}"
            )
          ]

        :cua_xep ->
          [cbox("gate", {-hw + @pier, y1 - 0.09, @plinth}, {hw - @pier, y1 - 0.03, @opening})]

        :door_gate ->
          [{d0, _, d1, top, _} | _] = door_gate_holes(o)

          [
            cbox("wall_door_left", {hw - d0, y0, 0.0}, {hw - @pier, y1, @opening}),
            cbox("wall_door_right", {-hw + @pier, y0, 0.0}, {hw - d1, y1, @opening}),
            cbox("wall_door_top", {hw - d1, y0, top}, {hw - d0, y1, @opening}),
            cbox("door", {hw - d1, y0, @plinth}, {hw - d0, y1, top})
          ]

        :open_shop ->
          []
      end
  end

  # The back of the room behind an open front (no front room), and the
  # front room: the wall at its back round its door, its ceiling and the
  # stairs.
  defp room_boxes(%{interior: :front_room} = o, plan) do
    r = room(o, plan)
    {d0, d1} = r.door
    hw = r.hw
    {y0, y1} = {r.back - 0.1, r.back}

    [
      cbox("room_back_left", {d1, y0, @plinth}, {hw, y1, r.ceiling}),
      cbox("room_back_right", {-hw, y0, @plinth}, {d0, y1, r.ceiling}),
      cbox("room_back_top", {d0, y0, @plinth + 2.1}, {d1, y1, r.ceiling}),
      # The ceiling round its hole over the top of the stairs.
      cbox("ceiling_back", {-hw, r.back, r.ceiling}, {hw, r.hole.y0, r.ceiling + 0.1}),
      cbox("ceiling_front", {-hw, r.hole.y1, r.ceiling}, {hw, r.front, r.ceiling + 0.1}),
      cbox("ceiling_side", side_of_hole(r, -hw), side_of_hole(r, hw) |> then(fn {x, y, z} -> {x, y, z + 0.1} end)),
      slope_box(
        "stairs",
        r.stair.x1 - r.stair.x0,
        {r.stair.y0, @plinth},
        {r.stair.y1, r.stair.z1},
        0.2,
        (r.stair.x0 + r.stair.x1) / 2
      )
    ]
  end

  defp room_boxes(%{ground: ground} = o, plan) when ground in [:cua_xep, :open_shop] do
    hw = o.width / 2 - @side_wall
    back = max(o.depth / 2 - @front_wall - 5.0, plan.back + 0.5)
    [cbox("room_back", {-hw, back - 0.02, @plinth}, {hw, back, Enum.at(plan.floors, 1, plan.top)})]
  end

  defp room_boxes(_o, _plan), do: []

  # --- The front room (W20) -------------------------------------------------

  # The room that a player can enter from the street: its floor 20 cm
  # over the street, a ceiling 3 m over the floor, a wall at its back
  # with a door of 0.9 by 2.1 m (to the back of the house), and the
  # stairs along the side wall away from the door, up to the first floor
  # (each riser 18 cm at the most, each tread 26 cm at the most: by eye).
  defp room(o, plan) do
    hw = o.width / 2 - @side_wall - 0.02
    front = o.depth / 2 - @front_wall
    back = front - min(7.0, front - (plan.back + @front_wall) - 0.3)
    z1 = Enum.at(plan.floors, 1, plan.top)
    rise = z1 - @plinth
    n = ceil(rise / 0.18)
    run = min(0.26 * (n - 1), front - back - 1.0)
    # The door at the side of the door of the floors over it, the stairs
    # at the other side.
    s = if plan.door_left, do: -1.0, else: 1.0
    {x0, x1} = if s > 0, do: {hw - 0.9, hw}, else: {-hw, -hw + 0.9}
    d = if s > 0, do: -hw + 0.3, else: hw - 1.2
    y0 = front - 1.0
    y1 = y0 - run

    %{
      hw: hw,
      front: front,
      back: back,
      ceiling: @plinth + 3.0,
      door: {d, d + 0.9},
      stair: %{x0: x0, x1: x1, y0: y0, y1: y1, z1: z1, n: n, tread: run / (n - 1), riser: rise / n},
      # The hole of the ceiling over the top of the stairs: 2.6 m long
      # (2.2 m of head room under the slab over it, by eye).
      hole: %{x0: x0, x1: x1, y0: y1, y1: min(y1 + 2.6, front)}
    }
  end

  # A corner of the box of the ceiling beside its hole: `x` at the side
  # wall away from the hole, else at the edge of the hole.
  defp side_of_hole(r, x) do
    stairs_left = r.hole.x1 >= r.hw
    edge = if stairs_left, do: r.hole.x0, else: r.hole.x1
    if x > 0 == stairs_left, do: {edge, r.hole.y1, r.ceiling}, else: {x, r.hole.y0, r.ceiling}
  end

  defp front_room(%{interior: :front_room} = o, plan, level) when level != :far do
    r = room(o, plan)
    {d0, d1} = r.door
    hw = r.hw
    st = r.stair
    h = r.ceiling - @plinth

    coat = fn at, u, v, len, ht, holes ->
      sheet(at, u, v, len, ht, holes, :plaster, inward: true, skin: {0.02, :brick})
    end

    {open_from, open_to} = {r.hole.y0, r.hole.y1}
    hole_u = {r.hole.x0 + hw, r.hole.x1 + hw}

    [
      Shape.box({-hw, r.back, 0.0}, {hw, r.front, @plinth}, :tile_granite) |> Mesh.matter(:concrete),
      coat.({hw, r.back, @plinth}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}, r.front - r.back, h, []),
      coat.({-hw, r.front, @plinth}, {0.0, -1.0, 0.0}, {0.0, 0.0, 1.0}, r.front - r.back, h, []),
      # The wall at the back of the room, from the room side, with its door.
      sheet(
        {hw, r.back, @plinth},
        {-1.0, 0.0, 0.0},
        {0.0, 0.0, 1.0},
        2 * hw,
        h,
        [{hw - d1, 0.0, hw - d0, 2.1, 0.05}],
        :plaster,
        skin: {0.1, :brick}
      ),
      sheet(
        {-hw, r.back, r.ceiling},
        {1.0, 0.0, 0.0},
        {0.0, 1.0, 0.0},
        2 * hw,
        r.front - r.back,
        [{elem(hole_u, 0), open_from - r.back, elem(hole_u, 1), open_to - r.back, 0.0}],
        :plaster,
        inward: true,
        skin: {0.1, :concrete}
      )
    ] ++ stairs(st, level)
  end

  defp front_room(_o, _plan, _level), do: []

  # The stairs: a box for each step at near, one wedge at mid.
  defp stairs(st, :near) do
    for k <- 0..(st.n - 1) do
      y = st.y0 - k * st.tread

      Shape.box({st.x0, y - st.tread, @plinth}, {st.x1, y, @plinth + (k + 1) * st.riser}, :tile_granite)
      |> Mesh.matter(:concrete)
    end
  end

  defp stairs(st, :mid) do
    # The loop in y and z (the frame has its z along x).
    loop = [{st.y0, @plinth}, {st.y1, st.z1}, {st.y1, @plinth}]
    frame = World.Frame.new({st.x0, 0.0, 0.0}, {1, 0, 0}, {0, 0, 1})
    [loop |> Shape.prism(st.x1 - st.x0, :tile_granite, frame: frame) |> Mesh.matter(:concrete)]
  end

  # --- The ports for the small parts of the game (W18) ----------------------

  # The size of the thing on each kind of port: across the front, up, and
  # out of the wall (or along the lot for a port that looks up). By eye
  # from photos, and the sizes of common products of 2019 (`sources/1`).
  @port_sizes %{
    "ac" => [0.7, 0.55, 0.28],
    "rail" => nil,
    "pot" => [0.35, 0.5, 0.35],
    "sign" => nil,
    "number" => [0.3, 0.2, 0.01],
    "altar" => [0.45, 0.5, 0.35],
    "water_tank" => [1.0, 1.6, 1.0],
    "dish" => [0.6, 0.7, 0.4],
    "antenna" => [0.3, 2.5, 0.3],
    "laundry" => [2.0, 1.6, 0.6],
    "wire" => [0.1, 0.1, 0.05]
  }

  # The most triangles of a whole house at each level, for a town of
  # thousands of houses (Vũng Tàu, W22).
  @limits %{near: 40_000, mid: 3_000, far: 300}

  # The material roles of a house: the 10 roles of W23, and the wood and
  # the aluminum of the shutters, the doors and the frames.
  @roles ~w(plaster brick_ong tile_granite tile_pattern metal_shutter iron roof_corrugated roof_clay concrete glass wood aluminum)a

  @doc "The most triangles of a whole house at each level (W22): `%{near: _, mid: _, far: _}`."
  def limits, do: @limits

  @doc "The material roles that a house can have (W23, and `wood` and `aluminum`)."
  def roles, do: @roles

  @doc "The kinds of the ports of a house (W18)."
  def port_kinds, do: @port_sizes |> Map.keys() |> Enum.sort()

  # The ports of a house, in the axes of the house. A port on a wall is
  # at the middle of the thing on the face of the wall; a port that looks
  # up is at the middle of the base of the thing. The front ports (an
  # AC unit over a window of each floor, the rail and two pots of each
  # balcony, the sign over the opening of the ground floor and the size
  # of its text, the plate of the house number on a pier, the altar of
  # the earth god on the floor inside the door), the roof ports (the
  # water tank, a dish, an antenna, a laundry pole) and the wire ports
  # (where the cables from the power poles come to the front).
  defp ports(o, plan) do
    front_ports(o, plan) ++ roof_ports(o, plan)
  end

  defp port(kind, at, normal, extra \\ %{}) do
    Map.merge(%{"kind" => kind, "at" => at, "normal" => normal, "size" => @port_sizes[kind]}, extra)
  end

  defp front_ports(o, plan) do
    hw = o.width / 2
    front = o.depth / 2
    out = {0.0, 1.0, 0.0}
    up = {0.0, 0.0, 1.0}

    ac =
      for i <- 1..(o.floors - 1)//1 do
        z = Enum.at(plan.floors, i)
        # Over the window, else over the door (u from the left, x = hw - u).
        [{d0, _, d1, _, _} | rest] = front_holes(o, plan, i)
        {u0, u1} = with([{w0, _, w1, _, _}] <- rest, do: {w0, w1}, else: (_ -> {d0, d1}))
        port("ac", {hw - (u0 + u1) / 2, front, z + 2.75}, out, %{"floor" => i})
      end

    balconies =
      for {:balcony, i} <- Enum.with_index(plan.balconies, 1) do
        z = Enum.at(plan.floors, i)
        y = front + plan.reach

        [
          port("rail", {0.0, y, z + @rail / 2}, out, %{"floor" => i, "size" => [o.width, @rail, 0.04]})
          | for(x <- [hw - 0.3, -hw + 0.3], do: port("pot", {x, y - 0.25, z}, up, %{"floor" => i}))
        ]
      end

    # The sign on the band between the opening and the first floor, over
    # the sunshade.
    z1 = Enum.at(plan.floors, 1, plan.top)
    {s0, s1} = {@opening + 0.3, z1 - 0.1}
    sign_w = o.width - 2 * @pier

    sign =
      port("sign", {0.0, front, (s0 + s1) / 2}, out, %{
        "size" => [sign_w, Float.round(s1 - s0, 3), 0.05],
        "text" => [Float.round(sign_w - 0.3, 3), Float.round((s1 - s0) * 0.6, 3)]
      })

    # The plate of the number on the pier away from the door of the floors
    # over it; the altar inside, at that side.
    side = if plan.door_left, do: -1.0, else: 1.0
    number = port("number", {side * (hw - @pier / 2), front, 2.0}, out)
    altar = port("altar", {side * (hw - @side_wall - 0.3), front - @front_wall - 0.25, @plinth}, up, %{"facing" => out})
    wires = for x <- [hw - 0.15, -hw + 0.15], do: port("wire", {x, front, z1 - 0.3}, out)
    ac ++ List.flatten(balconies) ++ [sign, number, altar] ++ wires
  end

  defp roof_ports(%{roof: :flat} = o, plan) do
    hw = o.width / 2
    {front, back, top} = {o.depth / 2, plan.back, plan.top}
    up = {0.0, 0.0, 1.0}

    # On a room on the terrace the tank is on its roof.
    tank =
      if o.terrace_room,
        do: {0.0, plan.back + @side_wall + 1.0, top + 2.7},
        else: {0.0, back + @front_wall + 0.7, top}

    [
      port("water_tank", tank, up),
      port("dish", {hw - 0.5, front - @front_wall - 0.5, top}, up),
      port("antenna", {-hw + 0.06, back + 0.06, top + @rail}, up),
      port("laundry", {0.0, (front + back) / 2, top}, up)
    ]
  end

  # A roof of two slopes: the tank on a stand at the back, the dish on the
  # front gable and the antenna on the back gable, at the ridge.
  defp roof_ports(o, plan) do
    rise = o.width / 2 * :math.tan(@pitch[o.roof] * :math.pi() / 180)
    ridge = Float.round(plan.top + rise, 4)
    up = {0.0, 0.0, 1.0}

    [
      port("water_tank", {0.0, plan.back + 1.0, ridge}, up),
      port("dish", {0.0, o.depth / 2 - 0.3, ridge}, up),
      port("antenna", {0.0, plan.back + 0.1, ridge}, up)
    ]
  end

  defp sources(o) do
    [
      "A #{o.kind} house of Vũng Tàu, 2019: #{o.floors} floors on a lot of #{o.width} by #{o.depth} m (World.Buildings.Lot).",
      "The ground floor: 3.6 m clear at the least (TCVN 9411:2012, nhà ở liên kế); its floor 0.2 m over the street (Vũng Tàu, W20).",
      "A balcony: 0.6 to 1.2 m out (Vũng Tàu, plan 0004, R7). A rail and a parapet: 1.1 m.",
      "The heights of the floors over the ground floor, the walls, the slopes of the roofs and the details: by eye, from the photos of the streets of Vũng Tàu of the owner.",
      "The ports (W18): the boxes of an outdoor unit of an AC of 9,000 BTU/h, a water tank of 1,000 L, a dish of 60 cm, a TV antenna, a plate of a house number, an altar of the earth god and a laundry pole are by eye, from photos and the sizes of common products of 2019."
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
  defp inside(%{ground: ground, interior: :none} = o, plan, level)
       when ground in [:cua_xep, :open_shop] and level != :far do
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
