defmodule World.Furniture.Hanging do
  @moduledoc """
  The hammock shop of the world (the family `:hanging`): the things that
  hang and swing, each from the same parts:

  - a bed (`World.Furniture.Hanging.Bed`): cloth or a net of cords, its
    ends gathered, on short bars or on spreader bars, its middle line a
    catenary between its ends;
  - the suspension and the anchors (`World.Furniture.Hanging.Rig`):
    ropes, chains, the cords of the ends, rings, hooks, carabiners,
    swivels, tree straps; the trees, the posts and the ceiling of the
    site, or a stand;
  - a seat in place of a bed: a board, a tire, a bench, a basket.

  The joints are as in real life (`docs/format.md`, "A joint as in real
  life"): a thing on two anchors swings about the line through them (one
  hinge on that axis); a thing on one point swings about it in any way
  (two hinges at the point, about x and about y) and spins on its swivel,
  whose two halves are on the two nodes. The anchors and the hooks stay on
  the site or the stand.

  The hang of a hammock between two anchors: its suspension goes at 30
  degrees under the level, and a hammock with gathered ends hangs with
  83% of its length between its ends (The Ultimate Hang, the hammock hang
  calculator: a hang angle of 30 degrees, a ridgeline of 83% of the
  length for a gathered-end hammock); its lowest point is at its sit
  height. The height of the anchors comes from these.

  The models:

  - `cafe/1`: the võng of the cafés of the South between two posts: a net
    of cords (`bed: :net`) or a cloth of parachute nylon (võng dù, `bed:
    :cloth`);
  - `vong_xep/1`: the võng xếp, a net on two short bars on a stand of
    steel tube;
  - `camping/1`: a camping hammock between two trees: tree straps,
    carabiners and a ridgeline;
  - `spreader/1`: a hammock with spreader bars between two trees: a
    cloth of canvas (`bed: :cloth`) or a bed of rope (`bed: :net`);
  - `plank_swing/1`: a board on two ropes from a branch;
  - `tire_swing/1`: a tire on three chains to a swivel, on one rope from
    a branch;
  - `porch_swing/1`: a bench on chains from two hooks in the ceiling of
    a porch;
  - `egg_chair/1`: a basket of wicker on a chain and a swivel from the
    hook of its stand.

  The axes: x along the bed or the bench, y across, z up.
  """
  alias World.{Assembly, Mesh, Part, Shape, Vec}
  alias World.Furniture.Hanging.{Bed, Rig}

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})
  @tan30 :math.tan(:math.pi() / 6)
  # The branch of a swing: 8 in at 10 ft (HGTV, how to make a tree swing).
  @branch 10 * 12 * 0.0254
  @branch_r 4 * 0.0254

  # The sit height of a camping hammock (ENO: 18 in or less).
  @eno_sit 18 * 0.0254
  @ultimate "The Ultimate Hang, the hammock hang calculator: the suspension at 30 degrees, the ridgeline at 83% of the length."

  @doc "The models of the hammock shop, as `{name, fun}`."
  def models,
    do: [
      {"vong_luoi_cafe", fn -> cafe() end},
      {"vong_du_cafe", fn -> cafe(bed: :cloth, name: "vong_du_cafe") end},
      {"vong_xep", fn -> vong_xep() end},
      {"hammock_camping", fn -> camping() end},
      {"hammock_spreader_canvas", fn -> spreader() end},
      {"hammock_spreader_rope", fn -> spreader(bed: :net, name: "hammock_spreader_rope") end},
      {"swing_plank", fn -> plank_swing() end},
      {"swing_tire", fn -> tire_swing() end},
      {"swing_porch", fn -> porch_swing() end},
      {"egg_chair", fn -> egg_chair() end}
    ]

  @doc """
  The hang of a bed with gathered ends between two anchors `d` apart: the
  span of the bed (83% of its length), the drop of the suspension at 30
  degrees, the sag of the bed, and the height of the anchors for a lowest
  point at `sit`. A map `%{span, drop, sag, anchor}` (m).

      iex> h = World.Furniture.Hanging.hang(4.5, 2.9, 0.46)
      iex> {Float.round(h.span, 3), Float.round(h.anchor, 2)}
      {2.407, 1.78}
  """
  def hang(d, length, sit, span \\ nil) do
    span = span || 0.83 * length
    drop = @tan30 * (d - span) / 2
    sag = Bed.sag(span, length)
    %{span: span, drop: drop, sag: sag, anchor: sit + sag + drop}
  end

  @doc """
  The võng of a café between two posts (photos: Cà Phê Võng, Vietnam
  Coracle): its ends gathered, a rope from each end to a post. Options:
  `bed` (`:net`, a net of nylon cord, or `:cloth`, parachute nylon),
  `color`, `name`.
  """
  def cafe(opts \\ []) do
    bed = Keyword.get(opts, :bed, :net)
    name = Keyword.get(opts, :name, "vong_luoi_cafe")
    # The posts: round poles of 12 cm (by eye from the photos), 2.8 m
    # apart (Yellow Leaf Hammocks, the hanging sizes: 9 to 12 ft apart). The net of a võng:
    # 180 by 142 cm (the net of a võng of Meta.vn); the cloth: 220 by 120
    # cm, by eye.
    {d, post} = {2.8, 0.12}
    {length, width} = if bed == :net, do: {1.8, 1.42}, else: {2.2, 1.2}
    h = hang(d - post, length, 0.45)
    {a1, a2} = {{-(d - post) / 2, 0.0, h.anchor}, {(d - post) / 2, 0.0, h.anchor}}
    {e1, e2} = {{-h.span / 2, 0.0, h.anchor - h.drop}, {h.span / 2, 0.0, h.anchor - h.drop}}
    surface = Bed.surface(e1, e2, length: length, width: width, ends: :gathered)
    color = Keyword.get(opts, :color, if(bed == :net, do: [24, 92, 150], else: [20, 120, 130]))

    # The net: a mesh of about 3.5 cm (by eye). The cloth: a hem of 2 cm
    # at each edge, of a darker color (by eye).
    beds =
      if bed == :net,
        do: Bed.net(surface, strands: 40, knots: 48),
        else: cloth_mass(Bed.cloth(surface, cols: 24, bands: [{2, :dark}, {116, :fabric}, {2, :dark}]), surface, 0.087)

    swinging =
      Part.new(
        "bed_#{name}",
        :bed,
        beds ++ whippings(e1, e2, a1, a2) ++ [Rig.rope(a1, e1, 0.01), Rig.rope(e2, a2, 0.01)],
        [@o],
        sources: [
          if(bed == :net,
            do: "A net of nylon cord of 2.4 mm, 180 by 142 cm (the net of a võng, Meta.vn), its ends gathered.",
            else:
              "A cloth of parachute nylon, 220 by 120 cm (by eye), of 87 g/m2 (the cloth of a camping hammock: ENO DoubleNest, 538 g for 2.9 by 1.92 m)."
          ),
          @ultimate
        ]
      )

    site =
      Part.new(
        "posts_#{name}",
        :site,
        for(sx <- [-1, 1], p <- Rig.post("p", {sx * d / 2, 0.0}, post).shapes, do: p),
        [@o],
        sources: [
          "Two round poles of wood of 12 cm (by eye), 2.8 m apart (Yellow Leaf Hammocks: 9 to 12 ft): the site."
        ]
      )

    new(
      name,
      site,
      "A võng of a café of the South between two posts: #{if(bed == :net, do: "a net of cord (võng lưới)", else: "a cloth of parachute nylon (võng dù)")}.",
      materials: %{fabric: color, dark: Enum.map(color, &round(&1 * 0.6))}
    )
    |> swing2("bed_#{name}", swinging, a1, a2)
  end

  @doc """
  The võng xếp (photo: Sturdy Iron Frame Hammock, Alibaba): a stand of
  steel tube of 27 mm (the frame of a võng xếp of Duy Phương: phi 27,
  Meta.vn), 2.5 by 1.0 by 0.9 m (the large võng xếp of Duy Lợi, FPTShop),
  and a net of 180 by 142 cm on a bar of wood of 50 cm at each end (the
  net of Bản Mai, gỗ 50 cm, Meta.vn), on two cords to the hook at each
  end. Options: `color`, `name`.
  """
  def vong_xep(opts \\ []) do
    name = Keyword.get(opts, :name, "vong_xep")
    {len, wid, hgt, tube} = {2.5, 1.0, 0.9, 0.027}
    r = tube / 2
    # The stand: two rails on the ground, three cross rails, and at each
    # end two posts that lean out to the hook at the top.
    {xb, xh} = {len / 2 - 0.2, len / 2 - 0.05}
    tub = fn a, b -> Shape.sweep([a, b], r, :steel, sides: 10) |> Mesh.skin(0.0015, :steel) end
    rails = for sy <- [-1, 1], do: tub.({-xb, sy * (wid / 2 - r), r}, {xb, sy * (wid / 2 - r), r})
    cross = for x <- [-xb, 0.0, xb], do: tub.({x, -(wid / 2 - r), r}, {x, wid / 2 - r, r})
    # Each post bends in to the hook: the two posts of an end make an arch
    # (the photo of the stand).
    posts =
      for sx <- [-1, 1], sy <- [-1, 1] do
        arch =
          for k <- 0..8,
              t = k / 8,
              do:
                {sx * (xb + (xh - xb) * t), sy * (wid / 2 - r) * (1 - t * t),
                 r + (hgt - 0.03 - r) * :math.sin(:math.pi() / 2 * t)}

        Shape.sweep(arch, r, :steel, sides: 10) |> Mesh.skin(0.0015, :steel)
      end

    stand =
      Part.new("stand_#{name}", :stand, rails ++ cross ++ posts, [@o],
        sources: [
          "A stand of steel tube of 27 mm (phi 27, Duy Phương, Meta.vn), a wall of 1.5 mm (by eye), 2.5 by 1.0 by 0.9 m (Duy Lợi, FPTShop)."
        ]
      )

    {a1, a2} = {{-xh, 0.0, hgt - 0.03}, {xh, 0.0, hgt - 0.03}}

    # The net: 1.8 m long, 1.6 m between its bars, so that the cords to the
    # hooks go at about 30 degrees.
    {length, span, bar} = {1.8, 1.6, 0.5}
    drop = @tan30 * (2 * xh - span) / 2
    {e1, e2} = {{-span / 2, 0.0, hgt - 0.03 - drop}, {span / 2, 0.0, hgt - 0.03 - drop}}
    surface = Bed.surface(e1, e2, length: length, width: 1.42, ends: {:bar, bar})

    bars =
      for {{x, _, z}, a} <- [{e1, a1}, {e2, a2}] do
        ends = [{x, -bar / 2, z}, {x, bar / 2, z}]

        [
          Shape.box({x - 0.012, -bar / 2 - 0.02, z - 0.012}, {x + 0.012, bar / 2 + 0.02, z + 0.012}, :wood)
          |> Mesh.matter(:wood)
          | Rig.fan(a, ends, d: 0.005)
        ]
      end

    net =
      Part.new("net_#{name}", :bed, Bed.net(surface, strands: 40, knots: 44) ++ List.flatten(bars), [@o],
        sources: [
          "A net of nylon cord, 180 by 142 cm, on a bar of wood of 50 cm at each end (Bản Mai, gỗ 50 cm, Meta.vn); two cords of 5 mm to each hook."
        ]
      )

    hooks = for {a, s} <- [{a1, "left"}, {a2, "right"}], do: Rig.hook("hook_#{s}_#{name}", a)

    new(name, stand, "A võng xếp: a net of cord on a stand of steel tube.",
      site: false,
      materials: %{fabric: Keyword.get(opts, :color, [40, 150, 80])}
    )
    |> fixed(hooks)
    |> swing2("net_#{name}", net, a1, a2)
  end

  @doc """
  A camping hammock between two trees (ENO DoubleNest: 2.9 by 1.92 m,
  538 g, nylon of 70 denier, carabiners of 7075 aluminum): its ends
  gathered, a ridgeline of 83% of its length, a tree strap round each
  trunk to a carabiner, the trees 4.5 m apart (the FAQ of ENO: 3 to 4.5
  m between the trees; the straps at least 1.5 m from the ground), its
  sit height of 18 in (ENO: 18 in or less). Options: `color`, `name`.
  """
  def camping(opts \\ []) do
    name = Keyword.get(opts, :name, "hammock_camping")
    {d, trunk, length} = {4.5, 0.3, 2.9}
    reach = d - trunk
    h = hang(reach, length, @eno_sit)
    {a1, a2} = {{-reach / 2, 0.0, h.anchor}, {reach / 2, 0.0, h.anchor}}
    {e1, e2} = {{-h.span / 2, 0.0, h.anchor - h.drop}, {h.span / 2, 0.0, h.anchor - h.drop}}
    surface = Bed.surface(e1, e2, length: length, width: 1.92, ends: :gathered)
    # The carabiner at each gathered end, on the end of its strap.
    clips = for {e, s} <- [{e1, -1}, {e2, 1}], do: Vec.add(e, {s * 0.05, 0.0, 0.0})

    bed =
      Part.new(
        "bed_#{name}",
        :bed,
        Bed.cloth(surface, cols: 24, bands: [{1, :cloth}, {3, :fabric}, {1, :cloth}]) ++
          whippings(e1, e2, a1, a2) ++ [Rig.rope(e1, e2, 0.003)],
        [@o],
        params: %{"mass" => 0.538},
        sources: [
          "ENO DoubleNest: 2.9 by 1.92 m, 538 g, nylon of 70 denier; a ridgeline of 83% of its length (#{@ultimate})"
        ]
      )

    {loops, straps} =
      for {{a, c}, {s, sx}} <-
            Enum.zip([{a1, Enum.at(clips, 0)}, {a2, Enum.at(clips, 1)}], [{"left", -1}, {"right", 1}]) do
        strap = Rig.tree_strap("strap_loop_#{s}_#{name}", {sx * d / 2, 0.0}, trunk / 2, elem(a, 2), a)
        free = World.Materials.Webbing.strap("strap_#{s}_#{name}", [a, c], 0.025, thickness: 0.0015, material: :black)
        {strap, free}
      end
      |> Enum.unzip()

    carabiners = for {c, s} <- Enum.zip(clips, ["left", "right"]), do: Rig.carabiner("carabiner_#{s}_#{name}", c)
    [site, other] = trees(name, d, trunk)

    new(name, site, "A camping hammock between two trees, on tree straps and carabiners.",
      materials: %{fabric: Keyword.get(opts, :color, [200, 120, 40]), cloth: [70, 74, 80]}
    )
    |> fixed([other | loops])
    |> swing2("bed_#{name}", bed, a1, a2, straps ++ carabiners)
  end

  @doc """
  A hammock with spreader bars between two trees (photos: the Wikipedia
  page Võng; Wayfair): a bed of 74 by 55 in, 124.5 in long with the cords
  of its ends (Sunnydaze, Double Wide 2-Person Spreader Bar Rope
  Hammock), on a bar of wood at each end, the cords from the bar to a
  ring, and a chain from the ring to a tree strap, the trees 15 ft apart
  (Sunnydaze, the rope hammock with spreader bars: the anchors about 15
  ft apart). Options: `bed` (`:cloth`, a canvas; `:net`, a bed of rope),
  `name`.
  """
  def spreader(opts \\ []) do
    bed = Keyword.get(opts, :bed, :cloth)
    name = Keyword.get(opts, :name, "hammock_spreader_canvas")
    {d, trunk} = {15 * 12 * 0.0254, 0.32}
    {length, width} = {74 * 0.0254, 55 * 0.0254}
    fan = (124.5 - 74) / 2 * 0.0254
    # The bars at 90% of the length of the bed apart (by eye): a bed on
    # bars hangs flatter than a gathered one.
    span = 0.9 * length
    reach = d - trunk
    sag = Bed.sag(span, length)
    # The cords of the ends go from the bar to the ring along the bed; the
    # chain from the ring to the strap at 30 degrees.
    drop = @tan30 * (reach / 2 - span / 2 - fan)
    anchor = 0.5 + sag + drop
    {a1, a2} = {{-reach / 2, 0.0, anchor}, {reach / 2, 0.0, anchor}}
    z = anchor - drop
    {e1, e2} = {{-span / 2, 0.0, z}, {span / 2, 0.0, z}}
    {r1, r2} = {{-span / 2 - fan, 0.0, z}, {span / 2 + fan, 0.0, z}}
    surface = Bed.surface(e1, e2, length: length, width: width, ends: :spread)

    beds =
      case bed do
        :cloth -> cloth_mass(Bed.cloth(surface, t: 0.003, cols: 22, bands: stripes()), surface, 0.407)
        :net -> Bed.net(surface, strands: 22, knots: 26, d: 0.006, material: :rope)
      end

    holes = fn {x, _, zz} -> for k <- 0..9, do: {x, -width / 2 + width * (k + 0.5) / 10, zz} end

    ends =
      for {e, rr} <- [{e1, r1}, {e2, r2}] do
        {x, _, zz} = e

        [
          Shape.box({x - 0.019, -width / 2 - 0.05, zz - 0.01}, {x + 0.019, width / 2 + 0.05, zz + 0.01}, :wood)
          |> Mesh.matter(:wood),
          Rig.ring(rr, {0, 1, 0}, 0.025, 0.005) | Rig.fan(rr, holes.(e), d: 0.004)
        ]
      end

    chains = Rig.chain(a1, r1) ++ Rig.chain(r2, a2)

    hammock =
      Part.new("bed_#{name}", :bed, beds ++ List.flatten(ends) ++ chains, [@o],
        sources: [
          "A bed of 74 by 55 in, 124.5 in long with its cords (Sunnydaze, Double Wide 2-Person Spreader Bar Rope Hammock); #{if(bed == :cloth, do: "a canvas of cotton of 12 oz/yd2 (407 g/m2)", else: "a bed of rope of 4.8 mm")}.",
          "Spreader bars of hardwood of 38 by 20 mm, ten cords to a ring of steel, a chain to the strap (by eye)."
        ]
      )

    loops =
      for {a, s, sx} <- [{a1, "left", -1}, {a2, "right", 1}],
          do: Rig.tree_strap("strap_#{s}_#{name}", {sx * d / 2, 0.0}, trunk / 2, elem(a, 2), a)

    colors =
      if bed == :cloth,
        do: %{red: [178, 36, 40], blue: [34, 62, 120], orange: [226, 170, 52], white: [232, 222, 196]},
        else: %{rope: [222, 205, 170]}

    [site, other] = trees(name, d, trunk)

    new(name, site, "A hammock with spreader bars between two trees.", materials: colors)
    |> fixed([other | loops])
    |> swing2("bed_#{name}", hammock, a1, a2)
  end

  @doc """
  A swing of a board on two ropes from the branch of a tree: a branch of
  8 in at 10 ft (HGTV, how to make a tree swing: a branch of 8 in or more,
  10 to 15 ft up), a board of an adult of 60 by 25 cm (Corderie Mansas:
  25 by 60 cm for an adult), 3 cm thick, at 60 cm (Corderie Mansas: 60
  cm for an adult), on two ropes of 18 mm (the polypropylene rope of the
  tall tree swing of Masters of Games) 5 cm in from its ends. It swings
  about the line through the two knots on the branch. Options: `name`.
  """
  def plank_swing(opts \\ []) do
    name = Keyword.get(opts, :name, "swing_plank")
    {branch, seat, gap} = {@branch, 0.6, 0.5}
    {k1, k2} = {{-gap / 2, 0.0, branch - @branch_r}, {gap / 2, 0.0, branch - @branch_r}}
    board = Shape.box({-0.3, -0.125, seat - 0.03}, {0.3, 0.125, seat}, :wood) |> Mesh.matter(:wood)
    ropes = for {x, _, z} <- [k1, k2], do: Rig.rope({x, 0.0, z}, {x, 0.0, seat}, 0.018)

    swing =
      Part.new("seat_#{name}", :seat, [board | ropes], [@o],
        sources: [
          "A board of 60 by 25 cm at 60 cm (Corderie Mansas: the seat of an adult), 3 cm thick; two ropes of 18 mm (Masters of Games)."
        ]
      )

    knots =
      Part.new(
        "knots_#{name}",
        :hardware,
        for(
          {x, _, _} <- [k1, k2],
          do: Rig.ring({x, 0.0, branch}, {1, 0, 0}, @branch_r + 0.009, 0.009, material: :rope) |> Mesh.matter(:nylon)
        ),
        [@o],
        sources: ["A knot of the rope round the branch."]
      )

    new(name, tree_with_branch(name, branch), "A swing of a board on two ropes from a branch.")
    |> fixed([knots])
    |> swing2("seat_#{name}", swing, {-gap / 2, 0.0, branch}, {gap / 2, 0.0, branch}, [],
      role: :swing,
      limits: [-60, 60]
    )
  end

  @doc """
  A tire swing on a branch (the guides of a tire swing: three chains to a
  swivel, the tire about 30 in over the ground): a tire 225/60R16 on its
  side, three chains to the swivel, one rope of 18 mm from the swivel to
  a branch of 8 in at 10 ft (HGTV). It swings about the knot on the branch (two
  hinges) and spins on its swivel. Options: `name`.
  """
  def tire_swing(opts \\ []) do
    name = Keyword.get(opts, :name, "swing_tire")
    branch = @branch
    knot = {0.0, 0.0, branch - @branch_r}
    tire = World.Vehicles.Wheels.tire("225/60R16")
    {low, height} = {30 * 0.0254, 0.225}
    swivel_at = {0.0, 0.0, 1.45}
    {top, bottom} = Rig.swivel("swivel_#{name}", swivel_at)
    {sx, sy, sz} = swivel_at

    rope =
      Part.new("rope_#{name}", :rope, [Rig.rope(knot, {sx, sy, sz + 0.045}, 0.018)], [@o],
        sources: ["A rope of 18 mm from the branch to the swivel (Masters of Games)."]
      )

    # The tire on its side (its axis is z): its bottom at 30 in.
    flat = %{tire | shapes: Enum.map(tire.shapes, &Mesh.transform(&1, World.Frame.move({0.0, 0.0, low + height / 2})))}
    rim = tire.params["diameter"] / 2 - 0.02

    chains =
      for k <- 0..2, a = 2 * :math.pi() * k / 3 do
        Rig.chain({sx, sy, sz - 0.045}, {rim * :math.cos(a), rim * :math.sin(a), low + height})
      end
      |> List.flatten()

    hanging =
      Part.new("chains_#{name}", :chain, chains, [@o],
        sources: ["Three chains from the swivel to the tire (the guides of a tire swing)."]
      )

    new(
      name,
      tree_with_branch(name, branch),
      "A tire swing: a tire on three chains and a swivel, on one rope from a branch."
    )
    |> fixed([
      Part.new(
        "knot_#{name}",
        :hardware,
        [Rig.ring({0.0, 0.0, branch}, {1, 0, 0}, @branch_r + 0.009, 0.009, material: :rope) |> Mesh.matter(:nylon)],
        [@o],
        sources: ["A knot of the rope round the branch."]
      )
    ])
    |> swing1("swing_#{name}", knot, [rope, top], limits: [-45, 45])
    |> spin("spin_#{name}", swivel_at, [bottom, hanging, %{flat | name: "tire_#{name}"}], to: "swing_#{name}_y")
  end

  @doc """
  A porch swing (the guides of a porch swing: 5 ft wide, the seat at 17
  to 19 in, for a ceiling of 8 ft): a bench of slats of wood, 152 by 50
  cm, the seat at 18 in, on a chain at each side from an eye hook in the
  joist of the ceiling, the chain parted into two over the bench (a Y), to
  the front and the back of its side. It swings about the line through
  the two hooks. Options: `name`.
  """
  def porch_swing(opts \\ []) do
    name = Keyword.get(opts, :name, "swing_porch")
    {ceiling, width, depth, seat} = {8 * 12 * 0.0254, 1.52, 0.5, 18 * 0.0254}
    xh = width / 2 + 0.05
    {h1, h2} = {{-xh, 0.0, ceiling}, {xh, 0.0, ceiling}}
    slat = fn x0, x1, y0, y1, z0, z1 -> Shape.box({x0, y0, z0}, {x1, y1, z1}, :wood) |> Mesh.matter(:wood) end

    seats =
      for k <- 0..5,
          y = -depth / 2 + k * depth / 6,
          do: slat.(-width / 2, width / 2, y + 0.005, y + depth / 6 - 0.005, seat - 0.02, seat)

    backs =
      for k <- 0..3,
          z = seat + 0.08 + k * 0.1,
          do: slat.(-width / 2, width / 2, -depth / 2 - 0.02, -depth / 2, z, z + 0.08)

    arms =
      for sx <- [-1, 1],
          do: slat.(sx * width / 2 - 0.03, sx * width / 2 + 0.03, -depth / 2, depth / 2, seat + 0.2, seat + 0.23)

    sides =
      for sx <- [-1, 1],
          y <- [-depth / 2, depth / 2 - 0.04],
          do: slat.(sx * width / 2 - 0.02, sx * width / 2 + 0.02, y, y + 0.04, seat - 0.06, seat + 0.2)

    # The Y of each side: the chain from the hook to a ring 0.5 m over the
    # arm, then to the front and the back of the side.
    yz = seat + 0.75

    chains =
      for sx <- [-1, 1] do
        ring = {sx * xh, 0.0, yz}

        Rig.chain({sx * xh, 0.0, ceiling - 0.02}, ring) ++
          Rig.chain(ring, {sx * (width / 2 + 0.02), -depth / 2 + 0.02, seat + 0.2}) ++
          Rig.chain(ring, {sx * (width / 2 + 0.02), depth / 2 - 0.02, seat + 0.2}) ++
          [Rig.ring(ring, {0, 1, 0}, 0.02, 0.005)]
      end
      |> List.flatten()

    bench =
      Part.new("bench_#{name}", :seat, seats ++ backs ++ arms ++ sides ++ chains, [@o],
        sources: [
          "A bench of slats of wood, 152 by 50 cm, the seat at 18 in (the guides: 5 ft wide, 17 to 19 in); chains of 4 mm (by eye)."
        ]
      )

    hooks = for {h, s} <- [{h1, "left"}, {h2, "right"}], do: Rig.hook("hook_#{s}_#{name}", h)

    new(
      name,
      Rig.beam("ceiling_#{name}", {-xh - 0.2, 0.0, ceiling}, {xh + 0.2, 0.0, ceiling}),
      "A porch swing: a bench on chains from two hooks in the joist of the ceiling."
    )
    |> fixed(hooks)
    |> swing2("bench_#{name}", bench, h1, h2, [], role: :swing, limits: [-25, 25])
  end

  @doc """
  A hanging egg chair on its stand (Outsunny, the egg chair with a stand:
  98 by 95 by 198 cm, the basket 90 by 60 by 105 cm, 52 cm from the
  floor): a basket of wicker over a frame (ribs and rings of 8 mm, by
  eye), open at its front, with a cushion; a spring, a chain and a swivel
  from the hook at the top of a C stand of steel tube. It swings about
  the hook (two hinges), bounces on its spring (a slide down, to the
  stretch of the spring at its rated load of 317.5 kg) and spins on its
  swivel. Options: `color`, `name`.
  """
  def egg_chair(opts \\ []) do
    name = Keyword.get(opts, :name, "egg_chair")
    {bw, bd, bh, low, top} = {0.9, 0.6, 1.05, 0.52, 1.98}
    hook_at = {0.0, 0.0, top - 0.1}
    # The C stand: a base of two feet, a post at the back, and an arc over
    # the basket to the hook.
    r = 0.019
    tub = fn pts -> Shape.sweep(pts, r, :steel, sides: 10) |> Mesh.skin(0.0015, :steel) end
    back = -bd / 2 - 0.25
    # The arc: a quarter of an ellipse from the top of the post to over
    # the middle of the basket.
    arc = for k <- 0..10, a = :math.pi() / 2 * k / 10, do: {0.0, back * :math.cos(a), top - 0.25 + 0.25 * :math.sin(a)}

    stand =
      Part.new(
        "stand_#{name}",
        :stand,
        [
          tub.([{-0.48, back, r}, {0.48, back, r}]),
          tub.([{0.0, back, r}, {0.0, 0.45, r}]),
          tub.([{0.0, back, r}, {0.0, back, top - 0.25}]),
          tub.(arc)
        ],
        [@o],
        sources: ["A C stand of steel tube of 38 mm, a wall of 1.5 mm (by eye), 198 cm high (Outsunny)."]
      )

    hook = Rig.hook("hook_#{name}", hook_at)
    {spring_top, spring_bottom} = Rig.spring("spring_#{name}", hook_at)
    spring_end = elem(hook_at, 2) - Rig.spring_length()
    swivel_at = {0.0, 0.0, low + bh + 0.12}
    {top_half, bottom_half} = Rig.swivel("swivel_#{name}", swivel_at)
    {sx, sy, sz} = swivel_at

    chain =
      Part.new("chain_#{name}", :chain, Rig.chain({0.0, 0.0, spring_end}, {sx, sy, sz + 0.045}), [@o],
        sources: ["A chain from the spring to the swivel (by eye)."]
      )

    basket = basket(name, bw, bd, bh, low, {sx, sy, sz - 0.045})

    new(name, stand, "A hanging egg chair of wicker on its stand.",
      site: false,
      materials: %{fabric: Keyword.get(opts, :color, [200, 196, 186])}
    )
    |> fixed([hook])
    |> swing1("swing_#{name}", hook_at, [spring_top], limits: [-20, 20])
    |> bounce(
      "bounce_#{name}",
      {0.0, 0.0, elem(hook_at, 2) - Rig.spring_length() / 2},
      [spring_bottom, chain, top_half],
      to: "swing_#{name}_y",
      limits: [0, Rig.stretch(317.5)]
    )
    |> spin("spin_#{name}", swivel_at, [bottom_half, basket], to: "bounce_#{name}")
  end

  # The basket of an egg chair: ribs of wicker over an egg, from the seat
  # to the top, rings round it, its front open from the seat to the top
  # of the opening, a cushion on the seat, and a short chain to the
  # swivel.
  defp basket(name, bw, bd, bh, low, to) do
    r = 0.008
    profile = fn t -> :math.pow(:math.sin(:math.pi() * t), 0.8) * (1 - 0.15 * t) end
    point = fn t, a -> {bw / 2 * profile.(t) * :math.cos(a), bd / 2 * profile.(t) * :math.sin(a), low + bh * t} end
    # The opening faces +y, from 12% to 82% of the height: there the ribs
    # and the rings go only round the back.
    open? = fn a -> :math.sin(a) > 0.2 end
    {a0, a1} = {:math.pi() - :math.asin(0.2), 2 * :math.pi() + :math.asin(0.2)}

    # Fewer strands far away: 16 ribs and 9 rings at near, 8 and 5 at far.
    {nr, step} = if World.Detail.level() == :far, do: {8, 4}, else: {16, 2}

    ribs =
      for k <- 0..(nr - 1),
          a = 2 * :math.pi() * k / nr,
          steps <- if(open?.(a), do: [0..2, 17..20], else: [0..20]),
          do: for(i <- steps, do: point.(i / 20, a))

    rings =
      for j <- 2..18//step, t = j / 20 do
        if t > 0.12 and t < 0.82,
          do: for(k <- 0..30, do: point.(t, a0 + (a1 - a0) * k / 30)),
          else: for(k <- 0..48, do: point.(t, 2 * :math.pi() * k / 48))
      end

    strands = for line <- ribs ++ rings, do: Shape.sweep(line, r, :black, sides: 5) |> Mesh.matter(:plastic)

    cushion =
      Shape.cylinder(0.36, 0.08, :fabric, sides: 20, frame: World.Frame.move({0.0, 0.03, low + 0.12 * bh}))
      |> Mesh.matter(:seat_foam)

    {tx, ty, tz} = to
    hanger = Rig.chain({tx, ty, low + bh}, {tx, ty, tz})

    Part.new("basket_#{name}", :seat, [cushion | strands] ++ hanger, [@o],
      sources: [
        "A basket of 90 by 60 by 105 cm, 52 cm from the floor (Outsunny); wicker of PE of 16 mm over a frame (by eye), a cushion."
      ]
    )
  end

  # The trees of a site: two trunks `d` apart, each a part of its own;
  # the first is the root, the second goes on it (`fixed/2`).
  defp trees(name, d, trunk) do
    for {s, sx} <- [{"left", -1}, {"right", 1}], do: Rig.trunk("tree_#{s}_#{name}", {sx * d / 2, 0.0}, trunk)
  end

  # A tree with a branch out over the swing: a trunk of 40 cm (by eye),
  # and a branch of 8 in along x at the height `z` (HGTV: a branch of 8 in
  # or more, roughly parallel to the ground).
  defp tree_with_branch(name, z) do
    trunk =
      Shape.cylinder(0.2, z + 0.8, :bark, sides: 16, frame: World.Frame.move({-1.4, 0.0, 0.0})) |> Mesh.matter(:wood)

    branch =
      Shape.sweep([{-1.4, 0.0, z - 0.2}, {-0.6, 0.0, z}, {0.8, 0.0, z}], @branch_r, :bark, sides: 12)
      |> Mesh.matter(:wood)

    Part.new("tree_#{name}", :site, [trunk, branch], [@o],
      sources: [
        "A tree with a branch of 8 in at 10 ft (HGTV, how to make a tree swing): the site; the trunk of 40 cm by eye."
      ]
    )
  end

  # The mass of a cloth: its area by its mass of a square meter (kg/m2).
  # A skin of nylon of the thickness that gives that mass: the mesh is the
  # two faces of the cloth.
  defp cloth_mass(meshes, surface, kg) do
    t = kg * Bed.area(surface) / (1140 * (meshes |> Enum.map(&elem(World.Mass.area(&1), 0)) |> Enum.sum()))
    for m <- meshes, do: Mesh.skin(m, t, :nylon)
  end

  # The stripes of a canvas along the bed (the canvas of the photos of
  # Wayfair: stripes of red, blue, yellow and cream, by eye).
  defp stripes do
    for(_ <- 1..3, b <- [{3, :red}, {1, :white}, {2, :blue}, {1, :orange}, {1, :white}], do: b) ++ [{3, :red}]
  end

  # The whipping of each gathered end: on the bed, toward its rope.
  defp whippings(e1, e2, a1, a2), do: [Bed.whipping(e1, Vec.sub(a1, e1)), Bed.whipping(e2, Vec.sub(a2, e2))]

  # The assembly of a thing that hangs: the site (or the stand) as its
  # root. A site holds it: no check of its stand (`"site"` in its extras).
  defp new(name, root, about, opts \\ []) do
    site = Keyword.get(opts, :site, true)

    Assembly.new(name, root,
      root: root.name,
      kind: :hanging,
      materials:
        Map.new(Keyword.get(opts, :materials, %{}), fn {role, rgb} ->
          {role, %{"color" => rgb, "roughness" => 0.85, "metalness" => 0.0}}
        end),
      sources: [about, "The parts of the hammock shop (World.Furniture.Hanging)."],
      extras: if(site, do: %{"site" => true}, else: %{})
    )
  end

  # Parts fixed to the root: the hooks, the knots, the loops of the
  # straps.
  defp fixed(asm, parts),
    do: Enum.reduce(parts, asm, fn p, a -> Assembly.add(a, p.name, with_o(p), at: "o", port: "o") end)

  # A part from another shop (a strap of webbing) has no port "o": it is
  # in the axes of the model, so its "o" is the origin.
  defp with_o(%Part{ports: %{"o" => _}} = p), do: p
  defp with_o(%Part{} = p), do: %{p | ports: Map.put(p.ports, "o", @o)}

  # A thing on two anchors: a hinge about the line from `a1` to `a2`; the
  # parts in `more` go on its node too.
  defp swing2(asm, name, part, a1, a2, more \\ [], opts \\ []) do
    axis = Vec.norm(Vec.sub(a2, a1))
    port = Part.port("hinge", a1, axis, {0, 0, 1})
    part = %{part | ports: Map.put(part.ports, "hinge", port)}

    asm
    |> Assembly.add(name, part,
      at: %{port | name: name <> "_axis"},
      port: "hinge",
      kind: :hinge,
      role: Keyword.get(opts, :role, :swing),
      limits: Keyword.get(opts, :limits, [-30, 30])
    )
    |> then(fn a ->
      Enum.reduce(more, a, fn p, a -> Assembly.add(a, p.name, with_o(p), to: name, at: "o", port: "o") end)
    end)
  end

  # A thing on one point: two hinges at the point (about x, then about y)
  # and the parts on the second one.
  defp swing1(asm, name, at, parts, opts) do
    limits = Keyword.get(opts, :limits, [-30, 30])
    mark = fn n, axis -> Part.new(n, :mark, [], [@o, Part.port("hinge", at, axis, perpendicular(axis))]) end
    px = Part.port(name <> "_x", at, {1, 0, 0}, {0, 0, 1})
    py = Part.port(name <> "_y", at, {0, 1, 0}, {0, 0, 1})

    asm
    |> Assembly.add(name <> "_x", mark.(name <> "_x", {1, 0, 0}),
      at: px,
      port: "hinge",
      kind: :hinge,
      role: :swing,
      limits: limits
    )
    |> Assembly.add(name <> "_y", mark.(name <> "_y", {0, 1, 0}),
      to: name <> "_x",
      at: py,
      port: "hinge",
      kind: :hinge,
      role: :swing,
      limits: limits
    )
    |> then(fn a ->
      Enum.reduce(parts, a, fn p, a -> Assembly.add(a, p.name, with_o(p), to: name <> "_y", at: "o", port: "o") end)
    end)
  end

  # The node that bounces on a spring: a slide down at the middle of the
  # spring, on the node `to`; its parts go on it.
  defp bounce(asm, name, at, [first | rest], to: to, limits: limits) do
    port = Part.port("bounce", at, {0, 0, -1}, {0, 1, 0})
    first = %{first | ports: Map.put(first.ports, "bounce", port)}

    asm
    |> Assembly.add(name, first,
      to: to,
      at: %{port | name: name <> "_axis"},
      port: "bounce",
      kind: :slide,
      role: :bounce,
      limits: limits
    )
    |> then(fn a ->
      Enum.reduce(rest, a, fn p, a -> Assembly.add(a, p.name, with_o(p), to: name, at: "o", port: "o") end)
    end)
  end

  # The node that spins on a swivel: a hinge about z at the swivel, on
  # the node `to`, with no limits; its parts go on it.
  defp spin(asm, name, at, [first | rest], to: to) do
    port = Part.port("spin", at, {0, 0, 1}, {0, 1, 0})
    first = %{first | ports: Map.put(first.ports, "spin", port)}

    asm
    |> Assembly.add(name, first, to: to, at: %{port | name: name <> "_axis"}, port: "spin", kind: :hinge, role: :spin)
    |> then(fn a ->
      Enum.reduce(rest, a, fn p, a -> Assembly.add(a, p.name, with_o(p), to: name, at: "o", port: "o") end)
    end)
  end

  defp perpendicular({1, 0, 0}), do: {0, 0, 1}
  defp perpendicular({0, 1, 0}), do: {0, 0, 1}
end
