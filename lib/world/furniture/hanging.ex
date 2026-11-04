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
  - `vong_xep/1`: the võng xếp, a net on two short bars on the frame of
    steel of Duy Lợi; `vong_xep_frame/1`, the frame alone as it folds;
  - `iron_stand/1`: a stand of iron tube in arches, with the same net;
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
  alias World.{Assembly, Contact, Frame, Mesh, Part, Shape, Vec}
  alias World.Furniture.Hanging.{Bed, Rig}

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})
  @tan30 :math.tan(:math.pi() / 6)
  # The top of the cushion of an egg chair, over the bottom of its basket.
  @cushion 0.1

  # The branch of a swing: 8 in at 10 ft (HGTV, how to make a tree swing).
  @branch 10 * 12 * 0.0254
  @branch_r 4 * 0.0254

  # The half length of the body of a person on the bed (by eye: the
  # weight on about 1.4 m of the bed, from the shoulders to the heels).
  @body_load 0.7

  # The sit height of a camping hammock (ENO: 18 in or less).
  @eno_sit 18 * 0.0254
  @ultimate "The Ultimate Hang, the hammock hang calculator: the suspension at 30 degrees, the ridgeline at 83% of the length."

  @doc "The models of the hammock shop, as `{name, fun}`."
  def models,
    do: [
      {"vong_luoi_cafe", fn -> cafe() end},
      {"vong_du_cafe", fn -> cafe(bed: :cloth, name: "vong_du_cafe") end},
      {"vong_xep", fn -> vong_xep() end},
      {"vong_xep_frame", fn -> vong_xep_frame() end},
      {"hammock_stand_iron", fn -> iron_stand() end},
      {"hammock_camping", fn -> camping() end},
      {"hammock_camping_shelter", fn -> camping(shelter: true, name: "hammock_camping_shelter") end},
      {"hammock_camping_packed", fn -> camping_packed() end},
      {"hammock_camping_person", fn -> camping(person: true, name: "hammock_camping_person") end},
      {"hammock_spreader_canvas", fn -> spreader() end},
      {"hammock_spreader_rope", fn -> spreader(bed: :net, name: "hammock_spreader_rope") end},
      {"swing_plank", fn -> plank_swing() end},
      {"swing_tire", fn -> tire_swing() end},
      {"swing_porch", fn -> porch_swing() end},
      {"egg_chair", fn -> egg_chair() end},
      {"vong_luoi_cafe_person", fn -> cafe(person: true, name: "vong_luoi_cafe_person") end},
      {"swing_plank_person", fn -> plank_swing(person: true, name: "swing_plank_person") end},
      {"swing_porch_person", fn -> porch_swing(person: true, name: "swing_porch_person") end},
      {"egg_chair_person", fn -> egg_chair(person: true, name: "egg_chair_person") end},
      {"swing_tire_person", fn -> tire_swing(person: true, name: "swing_tire_person") end},
      {"hammock_spreader_canvas_person", fn -> spreader(person: true, name: "hammock_spreader_canvas_person") end}
    ]

  @doc """
  The hang of a bed with gathered ends between two anchors `d` apart: the
  span of the bed (83% of its length), the drop of the suspension at 30
  degrees, the sag of the bed, and the height of the anchors for a lowest
  point at `sit`. With a `load` (the half length of a body on the bed,
  `World.Furniture.Hanging.Bed.loaded/4`), the sag with a person in it:
  the sit height is the height with a person in it. A map `%{span, drop,
  sag, anchor}` (m).

      iex> h = World.Furniture.Hanging.hang(4.5, 2.9, 0.46)
      iex> {Float.round(h.span, 3), Float.round(h.anchor, 2)}
      {2.407, 1.78}
  """
  def hang(d, length, sit, span \\ nil, load \\ nil) do
    span = span || 0.83 * length
    drop = @tan30 * (d - span) / 2
    sag = Bed.sag(span, length, load)
    %{span: span, drop: drop, sag: sag, anchor: sit + sag + drop}
  end

  @doc """
  The võng of a café between two posts (photos: Cà Phê Võng, Vietnam
  Coracle): its ends gathered, a rope from each end to a post. Options:
  `bed` (`:net`, a net of nylon cord, or `:cloth`, parachute nylon),
  `color`, `name`, `person` (true: a person lies along it, `lie/4`).
  """
  def cafe(opts \\ []) do
    bed = Keyword.get(opts, :bed, :net)
    name = Keyword.get(opts, :name, "vong_luoi_cafe")
    # The posts: round poles of 12 cm (the poles of melaleuca, cừ tràm: 6
    # to 12 cm at the foot, Yellow Pages Việt Nam), 2.8 m
    # apart (Yellow Leaf Hammocks, the hanging sizes: 9 to 12 ft apart). The net of a võng:
    # 180 by 142 cm (the net of a võng of Meta.vn); the cloth: 220 by 120
    # cm, by eye.
    {d, post} = {2.8, 0.12}
    {length, width} = if bed == :net, do: {1.8, 1.42}, else: {2.2, 1.2}
    load = if Keyword.get(opts, :person, false), do: @body_load
    h = hang(d - post, length, 0.45, nil, load)
    {a1, a2} = {{-(d - post) / 2, 0.0, h.anchor}, {(d - post) / 2, 0.0, h.anchor}}
    {e1, e2} = {{-h.span / 2, 0.0, h.anchor - h.drop}, {h.span / 2, 0.0, h.anchor - h.drop}}
    surface = Bed.surface(e1, e2, length: length, width: width, ends: :gathered, load: load)
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
          "Two round poles of melaleuca of 12 cm (cừ tràm: 6 to 12 cm at the foot, Yellow Pages Việt Nam), 2.8 m apart (Yellow Leaf Hammocks: 9 to 12 ft): the site."
        ]
      )

    new(
      name,
      site,
      "A võng of a café of the South between two posts: #{if(bed == :net, do: "a net of cord (võng lưới)", else: "a cloth of parachute nylon (võng dù)")}.",
      materials: %{fabric: color, dark: Enum.map(color, &round(&1 * 0.6))}
    )
    |> swing2("bed_#{name}", swinging, a1, a2)
    # A person lies along the võng (the way of the cafés).
    |> then(fn a -> if load, do: lie(a, "bed_#{name}", surface), else: a end)
  end

  @doc """
  The võng xếp of Duy Lợi (the large frame of steel: 260 by 75 by 71 cm,
  6.3 kg, for 150 kg; demxanh.com) with a net of 180 by 142 cm on a bar of
  wood of 50 cm at each end (the net of Bản Mai, gỗ 50 cm, Meta.vn), on
  two cords to the hook at each end. The frame (`vong_xep_frame/1`) is
  locked open while the net is on it. Options: `color`, `name`.
  """
  def vong_xep(opts \\ []) do
    name = Keyword.get(opts, :name, "vong_xep")
    {asm, a1, a2} = duy_loi(name, false)

    asm
    |> Map.update!(:materials, &Map.put(&1, :fabric, color(Keyword.get(opts, :color, [40, 150, 80]))))
    |> swing2("net_#{name}", bar_net(name, a1, a2, 1.7), a1, a2)
  end

  @doc """
  The frame of the võng xếp alone, as it folds (Duy Lợi, the steps to
  fold it: the net off, the two ends of the frame in to the middle, then
  the frame into its bag): the four struts turn down onto the side
  tubes, then the two arms turn in onto the base, the right one over the
  left one. The clip `fold` folds it and opens it again. Options: `name`.
  """
  def vong_xep_frame(opts \\ []) do
    name = Keyword.get(opts, :name, "vong_xep_frame")
    {asm, _, _} = duy_loi(name, true)
    asm
  end

  # The frame of steel of a võng xếp of Duy Lợi (the large one: 260 by 75
  # by 71 cm): a base of two side tubes on four rubber feet, 1.1 m long
  # (the length of a folded võng xếp: 1 to 1.13 m), with a crossbar in the
  # notches on the tubes at each end and the fan brace in the middle (it
  # sets the width); at each end an arm, a V of two legs that lean out
  # from the ends of the base to the hook at its tip; four struts with two
  # bends from the base to the legs. The tube of 32 by 0.8 mm (the frame
  # of Bản Mai, D32 x 0.8 mm, Meta.vn). The left side is the root; the
  # right side (its tube, its feet, its legs and its struts) is a part of
  # its own. With `fold`, each piece turns or slides on its pin (the role
  # `:fold`), and the clip `fold`; else all of it is fixed. Gives the
  # assembly and the two hooks.
  defp duy_loi(name, fold) do
    {len, wid, hgt, lb, r, foot} = {2.6, 0.75, 0.71, 1.1, 0.016, 0.012}
    tube = fn pts -> Shape.sweep(pts, r, :steel, sides: 10) |> Mesh.skin(0.0008, :steel) end
    {yb, zb} = {wid / 2 - r, foot + r}
    base_end = fn sx, sy -> {sx * lb / 2, sy * yb, zb} end
    tip = fn sx -> {sx * (len / 2 - 0.03), 0.0, hgt - 0.02} end
    along = fn a, b, t -> Vec.add(a, Vec.scale(Vec.sub(b, a), t)) end
    sides = [{-1, "left"}, {1, "right"}]
    by_eye = "by eye"

    feet = fn sy ->
      for sx <- [-1, 1] do
        Shape.cylinder(0.022, foot, :rubber, sides: 10, frame: World.Frame.move({sx * (lb / 2 - 0.02), sy * yb, 0.0}))
        |> Mesh.matter(:rubber)
      end
    end

    side = fn sy, s ->
      Part.new("side_#{s}_#{name}", :stand, [tube.([base_end.(-1, sy), base_end.(1, sy)]) | feet.(sy)], [@o],
        sources: [
          "A side tube of the base of the frame of Duy Lợi (the large one: 260 by 75 by 71 cm, 6.3 kg; demxanh.com), 1.1 m long (a folded võng xếp: 1 to 1.13 m), the tube of 32 by 0.8 mm (Bản Mai, Meta.vn), and its rubber feet; #{by_eye}."
        ]
      )
    end

    # The fan brace: a hub in the middle and four blades to the side tubes.
    hub =
      Part.new(
        "fan_hub_#{name}",
        :stand,
        [
          Shape.cylinder(0.04, 0.02, :steel, sides: 12, frame: World.Frame.move({0.0, 0.0, zb - 0.01}))
          |> Mesh.matter(:steel)
        ],
        [@o],
        sources: [
          "The hub of the fan brace (thanh giằng cánh quạt, Duy Lợi: it sets the width with its teeth and a knob); #{by_eye}."
        ]
      )

    blades =
      for {sx, sxn} <- sides, {sy, s} <- sides do
        {Part.new("fan_blade_#{sxn}_#{s}_#{name}", :stand, [tube.([{0.0, 0.0, zb}, {sx * 0.14, sy * yb, zb}])], [@o],
           sources: ["A blade of the fan brace; #{by_eye}."]
         ), sx, sy}
      end

    # A crossbar in the notches on top of the side tubes at each end.
    crossbars =
      for {sx, s} <- sides do
        x = sx * (lb / 2 - 0.06)

        {Part.new("crossbar_#{s}_#{name}", :stand, [tube.([{x, -yb, zb + 2 * r}, {x, yb, zb + 2 * r}])], [@o],
           sources: ["A crossbar in the notches of the side tubes (thanh ngang, Duy Lợi); #{by_eye}."]
         ), x, sx}
      end

    # A leg of an arm: from the end of its side tube to the tip, with its
    # half of the V brace; the hook on the left leg.
    legs =
      for {sx, s} <- sides, {sy, t} <- [{-1, "left"}, {1, "right"}] do
        {tx, _, tz} = tip.(sx)
        {bx, _, bz} = b = along.(base_end.(sx, sy), tip.(sx), 0.65)
        brace = tube.([b, {bx, 0.0, bz}])
        cap = if sy == -1, do: [Rig.ring({tx, 0.0, tz - 0.018}, {1, 0, 0}, 0.012, 0.004)], else: []

        {Part.new("leg_#{s}_#{t}_#{name}", :stand, [tube.([base_end.(sx, sy), tip.(sx)]), brace | cap], [@o],
           sources: [
             "A leg of an arm of the frame: the V of two legs to the hook at its tip (the hook on a bearing, Duy Lợi), and half of the V brace; #{by_eye}."
           ]
         ), sx, sy}
      end

    # A strut from the base at 20 cm from the middle, with two bends, to
    # the middle of a leg.
    struts =
      for {sx, s} <- sides, {sy, t} <- [{-1, "back"}, {1, "front"}] do
        s0 = {sx * 0.2, sy * yb, zb}

        {Part.new(
           "strut_#{s}_#{t}_#{name}",
           :stand,
           [tube.([s0, Vec.add(s0, {sx * 0.08, 0.0, 0.12}), along.(base_end.(sx, sy), tip.(sx), 0.5)])],
           [@o],
           sources: ["A strut with two bends and its notches (Duy Lợi); #{by_eye}."]
         ), s0, sx, sy}
      end

    hooks = {Vec.add(tip.(-1), {0.0, 0.0, -0.03}), Vec.add(tip.(1), {0.0, 0.0, -0.03})}
    about = "The frame of steel of a võng xếp (Duy Lợi)#{if fold, do: ", as it folds", else: ""}."
    {left, right} = {side.(-1, "left"), side.(1, "right")}
    asm = new(name, left, about, site: false)

    asm =
      if fold do
        folded_frame(asm, name, %{
          right: right,
          hub: hub,
          blades: blades,
          crossbars: crossbars,
          legs: legs,
          struts: struts,
          geometry: %{yb: yb, zb: zb, r: r, base_end: base_end, tip: tip, along: along}
        })
      else
        parts = [right, hub] ++ Enum.map(blades ++ crossbars ++ legs, &elem(&1, 0)) ++ Enum.map(struts, &elem(&1, 0))
        fixed(asm, parts)
      end

    {asm, elem(hooks, 0), elem(hooks, 1)}
  end

  # The joints of the frame as it folds, in the steps of Duy Lợi: (1) the
  # struts turn down onto the side tubes; (2) the arms turn in onto the
  # base (the legs on pins at the ends of the side tubes); (3) the
  # crossbars come out of their notches and lie along the left tube; (4)
  # the fan brace closes: the right side slides to the left side, the hub
  # goes half as far, the blades turn, and the two legs of each V turn in
  # their plane until they lie side by side. Folded, the frame is about
  # 1.13 by 0.19 by 0.13 m (a folded võng xếp, chotot.com).
  defp folded_frame(asm, name, p) do
    %{yb: yb, zb: zb, r: r, base_end: base_end, tip: tip, along: along} = p.geometry
    deg = 180 / :math.pi()
    # The two side tubes 19 cm apart over their outsides when folded.
    gap = 0.19 - 2 * r
    width = 2 * yb - gap
    lift = fn {x0, _, z0}, {x1, _, z1} -> :math.atan2(z1 - z0, abs(x1 - x0)) * deg end
    root = "side_left_#{name}"
    right = "side_right_#{name}"

    asm =
      asm
      |> joint(p.right, root, Part.port("pin", {0.0, yb, zb}, {0, -1, 0}, {0, 0, 1}), :slide, [0, width])
      |> joint(p.hub, root, Part.port("pin", {0.0, 0.0, zb}, {0, -1, 0}, {0, 0, 1}), :slide, [0, width / 2])

    # The blades: on the hub, about z; their ends stay on their tubes.
    blade = Vec.len({0.14, yb, 0.0})

    blade_turn = fn sx, sy ->
      a0 = :math.atan2(sy * yb, sx * 0.14)
      a1 = :math.atan2(sy * gap / 2, sx * :math.sqrt(blade * blade - gap * gap / 4))
      (a1 - a0) * deg
    end

    asm =
      Enum.reduce(p.blades, asm, fn {part, sx, sy}, a ->
        joint(
          a,
          part,
          "fan_hub_#{name}",
          Part.port("pin", {0.0, 0.0, zb}, {0, 0, 1}, {0, 1, 0}),
          :hinge,
          Enum.sort([0, blade_turn.(sx, sy)])
        )
      end)

    # The crossbars: about z at the left end, along the left tube.
    asm =
      Enum.reduce(p.crossbars, asm, fn {part, x, sx}, a ->
        joint(
          a,
          part,
          root,
          Part.port("pin", {x, -yb, zb + 2 * r}, {0, 0, 1}, {0, 1, 0}),
          :hinge,
          Enum.sort([0, 90 * sx])
        )
      end)

    # The struts: about y at the foot, down onto the tube to the middle.
    asm =
      Enum.reduce(p.struts, asm, fn {part, s0, sx, sy}, a ->
        angle = 180 - lift.(s0, along.(base_end.(sx, sy), tip.(sx), 0.5)) - 8

        joint(
          a,
          part,
          if(sy == 1, do: right, else: root),
          Part.port("pin", s0, {0, 1, 0}, {0, 0, 1}),
          :hinge,
          Enum.sort([0, sx * -angle])
        )
      end)

    # The legs: a pin about y at the end of the side tube (the arm turns in,
    # the right arm over the left one), then a pin across the plane of
    # the V (the V closes).
    leg = Vec.len(Vec.sub(tip.(1), base_end.(1, 1)))
    close = (:math.acos(gap / 2 / leg) - :math.acos(yb / leg)) * deg

    asm =
      Enum.reduce(p.legs, asm, fn {part, sx, sy}, a ->
        b = base_end.(sx, sy)
        other = base_end.(sx, -sy)
        n = Vec.norm(Vec.cross(Vec.sub(tip.(sx), b), Vec.sub(other, b)))
        arm = 180 - lift.(b, tip.(sx)) - if(sx == 1, do: 6, else: 3)
        mark = Part.new(part.name <> "_arm", :mark, [], [@o])

        a
        |> joint(
          mark,
          if(sy == 1, do: right, else: root),
          Part.port("pin", b, {0, 1, 0}, {0, 0, 1}),
          :hinge,
          Enum.sort([0, sx * -arm])
        )
        |> joint(
          part,
          mark.name,
          Part.port("pin", b, n, Vec.norm(Vec.sub(tip.(sx), b))),
          :hinge,
          Enum.sort([0, -close])
        )
      end)

    folded =
      Map.new(for {n, _, c} <- asm.nodes, c && c.kind != :fixed, do: {n, Enum.max_by(c.limits, &abs/1)})

    step = fn keep -> Map.new(folded, fn {n, v} -> {n, if(keep.(n), do: v, else: 0.0)} end) end
    struts = step.(&(&1 =~ "strut_"))
    arms = step.(&(&1 =~ "strut_" or &1 =~ "_arm"))
    bars = step.(&(&1 =~ "strut_" or &1 =~ "_arm" or &1 =~ "crossbar_"))
    zeros = step.(fn _ -> false end)

    %{
      asm
      | clips: [
          %{
            name: "fold",
            length: 12.0,
            keys: [
              {0.0, zeros},
              {1.5, struts},
              {3.0, arms},
              {4.5, bars},
              {6.0, folded},
              {7.5, bars},
              {9.0, arms},
              {10.5, struts},
              {12.0, zeros}
            ]
          }
        ]
    }
  end

  # A part on a joint of the role `:fold` at the port `at` (its z the axis
  # of a hinge, or the way of a slide), on the node `to`.
  defp joint(asm, part, to, at, kind, limits) do
    Assembly.add(asm, part.name, %{part | ports: Map.put(part.ports, "pin", at)},
      to: to,
      at: %{at | name: part.name <> "_pin"},
      port: "pin",
      kind: kind,
      role: :fold,
      limits: limits
    )
  end

  # The net of a võng xếp or of a stand: 180 by 142 cm on a bar of wood of
  # 50 cm at each end, `span` between its bars, a fan of two cords from
  # each bar to its hook (`a1`, `a2`).
  defp bar_net(name, a1, a2, span) do
    {length, bar} = {1.8, 0.5}
    {{x1, _, z}, {x2, _, _}} = {a1, a2}
    drop = @tan30 * (x2 - x1 - span) / 2
    {e1, e2} = {{-span / 2, 0.0, z - drop}, {span / 2, 0.0, z - drop}}
    surface = Bed.surface(e1, e2, length: length, width: 1.42, ends: {:bar, bar})

    bars =
      for {{x, _, zz}, a} <- [{e1, a1}, {e2, a2}] do
        ends = [{x, -bar / 2, zz}, {x, bar / 2, zz}]

        [
          Shape.box({x - 0.012, -bar / 2 - 0.02, zz - 0.012}, {x + 0.012, bar / 2 + 0.02, zz + 0.012}, :wood)
          |> Mesh.matter(:wood)
          | Rig.fan(a, ends, d: 0.005)
        ]
      end

    Part.new("net_#{name}", :bed, Bed.net(surface, strands: 40, knots: 44) ++ List.flatten(bars), [@o],
      sources: [
        "A net of nylon cord, 180 by 142 cm, on a bar of wood of 50 cm at each end (Bản Mai, gỗ 50 cm, Meta.vn); two cords of 5 mm to each hook."
      ]
    )
  end

  @doc """
  A hammock stand of iron tube in arches (photo: Sturdy Iron Frame
  Hammock, Alibaba): a stand of steel tube of 27 mm (phi 27, Duy Phương,
  Meta.vn), 2.5 by 1.0 by 0.9 m, its posts bent into an arch at each end,
  with the net of a võng xếp. Options: `color`, `name`.
  """
  def iron_stand(opts \\ []) do
    name = Keyword.get(opts, :name, "hammock_stand_iron")
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
          "A stand of steel tube of 27 mm (phi 27, Duy Phương, Meta.vn), a wall of 1.5 mm (by eye), 2.5 by 1.0 by 0.9 m (FPTShop)."
        ]
      )

    {a1, a2} = {{-xh, 0.0, hgt - 0.03}, {xh, 0.0, hgt - 0.03}}
    hooks = for {a, s} <- [{a1, "left"}, {a2, "right"}], do: Rig.hook("hook_#{s}_#{name}", a)

    new(name, stand, "A hammock stand of iron tube in arches, with the net of a võng xếp.",
      site: false,
      materials: %{fabric: Keyword.get(opts, :color, [40, 150, 80])}
    )
    |> fixed(hooks)
    |> swing2("net_#{name}", bar_net(name, a1, a2, 1.6), a1, a2)
  end

  @doc """
  A camping hammock between two trees (ENO DoubleNest: 2.9 by 1.92 m,
  538 g, nylon of 70 denier, carabiners of 7075 aluminum): its ends
  gathered, a ridgeline of 83% of its length, a tree strap round each
  trunk to a carabiner, the trees 4.5 m apart (the FAQ of ENO: 3 to 4.5
  m between the trees; the straps at least 1.5 m from the ground), its
  sit height of 18 in (ENO: 18 in or less). Its stuff sack is sewn to
  the middle of one edge (ENO: an integrated stuff sack), and hangs there
  as a pocket. Options: `color`, `name`, `shelter` (true: a tarp and a bug
  net over it, `shelter/4`), `person` (true: a person lies in it, `lie/3`;
  the bed hangs under the weight, and the anchors go up so that the
  person is at the sit height).
  """
  def camping(opts \\ []) do
    name = Keyword.get(opts, :name, "hammock_camping")
    {d, trunk, length} = {4.5, 0.3, 2.9}
    reach = d - trunk
    person? = Keyword.get(opts, :person, false)
    load = if person?, do: @body_load
    h = hang(reach, length, @eno_sit, nil, load)
    {a1, a2} = {{-reach / 2, 0.0, h.anchor}, {reach / 2, 0.0, h.anchor}}
    {e1, e2} = {{-h.span / 2, 0.0, h.anchor - h.drop}, {h.span / 2, 0.0, h.anchor - h.drop}}
    surface = Bed.surface(e1, e2, length: length, width: 1.92, ends: :gathered, load: load)
    # The carabiner at each gathered end, on the end of its strap.
    clips = for {e, s} <- [{e1, -1}, {e2, 1}], do: Vec.add(e, {s * 0.05, 0.0, 0.0})

    bed =
      Part.new(
        "bed_#{name}",
        :bed,
        Bed.cloth(surface, cols: 24, bands: [{1, :cloth}, {3, :fabric}, {1, :cloth}]) ++
          whippings(e1, e2, a1, a2) ++ [Rig.rope(e1, e2, 0.003), pouch(surface.({0.5, 1.0}))],
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
    shelter? = Keyword.get(opts, :shelter, false)
    cover = if shelter?, do: shelter(name, d, h.anchor, elem(surface.({0.5, 0.0}), 2)), else: []

    new(
      name,
      site,
      "A camping hammock between two trees, on tree straps and carabiners#{if shelter?, do: ", under a tarp and a bug net"}.",
      materials:
        Map.merge(
          %{fabric: Keyword.get(opts, :color, [200, 120, 40]), cloth: [70, 74, 80]},
          if(shelter?, do: %{dark: [86, 94, 62], screen: %{"color" => [24, 24, 24], "alpha" => 0.35}}, else: %{})
        )
    )
    |> fixed([other | loops] ++ cover)
    # In the bug net, the hammock swings only a little (by eye).
    |> swing2("bed_#{name}", bed, a1, a2, straps ++ carabiners, limits: if(shelter?, do: [-8, 8], else: [-30, 30]))
    # The diagonal lay: 15 degrees across the bed (The Ultimate Hang).
    |> then(fn a -> if person?, do: lie(a, "bed_#{name}", surface, 15), else: a end)
  end

  @doc """
  A person who lies in a hammock: on the node `bed` (the person swings
  with the bed), the back on the middle line of the bed (`surface`), the
  hips 8 cm to the side of the head from the lowest point, the head to
  -x, the body in the middle of the bed. The torso and the thighs follow the line of the bed under them (the
  hips bend by the two angles), the knees and the neck bend a little,
  the arms lie along the sides (by eye). The person of `World.People.man/0`.
  """
  def lie(asm, bed, surface, angle \\ 0) do
    {x1, _, _} = surface.({0.0, 0.0})
    {x2, _, _} = surface.({1.0, 0.0})
    # The height of the bed at a point {x, y}: u from x, v from y over the
    # half width of the bed at u.
    height = fn x, y ->
      u = min(max((x - x1) / (x2 - x1), 0.0), 1.0)
      {_, half, _} = surface.({u, 1.0})
      elem(surface.({u, min(max(y / max(half, 0.01), -1.0), 1.0)}), 2)
    end

    line = for i <- 0..200, do: surface.({i / 200, 0.0})
    {x_low, _, _} = Enum.min_by(line, &elem(&1, 2))
    # The head to -x, turned by `angle` (the diagonal lay): the line of
    # the body through the lowest point.
    a = angle * :math.pi() / 180
    head = {-:math.cos(a), -:math.sin(a), 0.0}
    {hx, hy, _} = Vec.add({x_low, 0.0, 0.0}, Vec.scale(head, 0.08))
    z = fn s -> height.(hx + s * elem(head, 0), hy + s * elem(head, 1)) end
    slope = fn s -> :math.atan2(z.(s) - z.(0.0), abs(s)) end
    # The torso along the bed to the shoulders, the legs along the bed to
    # the heels.
    {torso, thigh} = {slope.(0.5), slope.(-0.85)}
    deg = 180 / :math.pi()
    # The hips 10 cm over the bed, across the line of the torso.
    hips = Vec.add({hx, hy, z.(0.0) + 0.1 * :math.cos(torso)}, Vec.scale(head, -0.1 * :math.sin(torso)))
    # The hips port of the person (z up, y to its front) onto this port:
    # its up to the head, its front to the sky.
    up = Vec.add(Vec.scale(head, :math.cos(torso)), {0.0, 0.0, :math.sin(torso)})
    front = Vec.add(Vec.scale(head, -:math.sin(torso)), {0.0, 0.0, :math.cos(torso)})
    x = {1.0, 0.0, 0.0}

    pose = %{
      "thigh_l" => [{x, (torso + thigh) * deg}],
      "thigh_r" => [{x, (torso + thigh) * deg}],
      "calf_l" => [{x, -6}],
      "calf_r" => [{x, -6}],
      "neck_01" => [{x, -15}],
      "upperarm_l" => [{{0.0, 1.0, 0.0}, -38}],
      "upperarm_r" => [{{0.0, 1.0, 0.0}, 38}],
      "lowerarm_l" => [{x, 15}],
      "lowerarm_r" => [{x, 15}]
    }

    Assembly.add(asm, "person", person(pose), to: bed, at: Part.port("lie", hips, up, front), port: "hips")
  end

  # The person of the hammock shop (`World.People.man/0`), in a pose.
  @person [age: 35, height: 0.55, muscle: 0.55]
  defp person(pose), do: World.People.Human.person("person", Keyword.put(@person, :pose, pose))

  @doc """
  A person who sits on the node `node` (a seat, a bench, a basket), the
  hips at `hips`, the front to `front` (a vector on the level, `+y` by
  default), the body back by `recline` degrees (0): the pose `"sit"` of
  `World.People.Pose`, with the changes of `pose`, and the hands to the points of `grips` (`{side, point}`, in the
  axes of the model; the hand closes on a rope) or of `rest` (the hand lies there: on the lap). The person swings with
  the node. The person leans as far as the joint values of `lean` (such
  as `%{"spine.flex" => -30}`: the back 30 degrees to the back) and stops
  where the body touches one of the `obstacles`, in the axes of the
  model (`World.Contact`).
  """
  def sit(asm, node, hips, opts \\ []) do
    front = Keyword.get(opts, :front, {0.0, 1.0, 0.0})
    # The point of a hand in the axes of the person (its hips at the head
    # of its pelvis, `World.People.Human.skeleton/1`).
    h0 = Enum.find(World.People.Human.skeleton(@person).bones, &(&1.name == "pelvis")).head
    side = Vec.cross(front, {0.0, 0.0, 1.0})

    local = fn p ->
      d = Vec.sub(p, hips)
      Vec.add(h0, {Vec.dot(d, side), Vec.dot(d, front), elem(d, 2)})
    end

    # The hands that hold (a rope: the shape "grip") and the hands that lie
    # on a thing (the lap: "relaxed").
    held = for {s, p} <- Keyword.get(opts, :grips, []), do: {s, p, "grip"}
    laid = for {s, p} <- Keyword.get(opts, :rest, []), do: {s, p, "relaxed"}
    grips = for {s, p, _} <- held ++ laid, into: %{}, do: {{:limb, "arm_#{s}"}, %{at: local.(p)}}
    hands = for {s, _, shape} <- held ++ laid, into: %{}, do: {{:hand, String.to_existing_atom(s)}, shape}

    pose =
      World.People.Pose.resolve("sit")
      |> Map.merge(Keyword.get(opts, :pose, %{}))
      |> Map.merge(grips)
      |> Map.merge(hands)

    r = Keyword.get(opts, :recline, 0) * :math.pi() / 180
    up = Vec.add(Vec.scale({0.0, 0.0, 1.0}, :math.cos(r)), Vec.scale(front, -:math.sin(r)))
    ahead = Vec.add(Vec.scale(front, :math.cos(r)), Vec.scale({0.0, 0.0, 1.0}, :math.sin(r)))
    port = Part.port("sit", hips, up, ahead)
    figure = person(pose)
    # The lean that the person wants, to the first touch of an obstacle.
    place = Frame.compose(World.Port.frame(port), Frame.invert(World.Figure.port_frame(figure, "hips")))
    {figure, _} = Contact.lean(figure, Keyword.get(opts, :lean, %{}), Keyword.get(opts, :obstacles, []), place)
    Assembly.add(asm, "person", figure, to: node, at: port, port: "hips")
  end

  @doc """
  A camping hammock packed in its stuff sack (ENO DoubleNest: packed 5 by
  6 by 5 in, 538 g; the hammock that a hiker carries): the sack on its
  side on the ground, the loop of its drawstring out of one end, and the
  two carabiners of the hammock clipped on the loop. Options: `color`,
  `name`.
  """
  def camping_packed(opts \\ []) do
    name = Keyword.get(opts, :name, "hammock_camping_packed")
    {r, len} = {2.5 * 0.0254, 6 * 0.0254}

    # Round at the bottom, drawn in at the top by its drawstring.
    sack =
      [
        {0.0, 0.0},
        {0.55 * r, 0.006},
        {0.85 * r, 0.018},
        {r, 0.04},
        {r, len - 0.045},
        {0.8 * r, len - 0.02},
        {0.35 * r, len - 0.006},
        {0.0, len}
      ]
      |> Shape.lathe(:fabric, sides: 20)
      |> Mesh.transform(World.Frame.new({-len / 2, 0.0, r}, {1, 0, 0}, {0, 0, 1}))

    # The loop of the drawstring, flat on the ground, and a carabiner on it
    # at each side (75 by 45 mm, flat).
    loop = Rig.ring({len / 2 + 0.02, 0.0, 0.0015}, {0, 0, 1}, 0.02, 0.0015, material: :black, sides: 10)
    clips = for sy <- [-1, 1], do: Rig.carabiner("c", {len / 2 + 0.07, sy * 0.022, 0.0045}, {1, 0, 0}, {0, 0, 1})

    hammock =
      Part.new("sack_#{name}", :bed, [sack, loop] ++ Enum.flat_map(clips, & &1.shapes), [@o],
        params: %{"mass" => 0.538},
        sources: [
          "ENO DoubleNest in its integrated stuff sack: 5 by 6 by 5 in, 538 g (ENO); the carabiners clipped on the loop of the drawstring."
        ]
      )

    new(name, hammock, "A camping hammock packed in its stuff sack, with its carabiners.",
      site: false,
      materials: %{fabric: Keyword.get(opts, :color, [200, 120, 40])}
    )
  end

  # The stuff sack of a camping hammock, sewn to its edge at `at`: a sack
  # of nylon 5 in across and 6 in long (ENO DoubleNest: packed 5 by 6 by 5
  # in), empty and flat, outside the edge.
  defp pouch({x, y, z}) do
    [{0.0, 0.0}, {0.05, 0.01}, {0.0635, 0.04}, {0.0635, 0.12}, {0.03, 0.15}, {0.0, 0.152}]
    |> Shape.lathe(:cloth, sides: 12)
    |> Mesh.transform(World.Frame.new({x, y + 0.07, z - 0.152}, {0, 0, 1}, {1, 0, 0}))
    |> then(&%{&1 | points: for({px, py, pz} <- &1.points, do: {px, y + 0.07 + (py - y - 0.07) * 0.35, pz})})
  end

  @doc """
  The tarp and the bug net over a camping hammock between two trees `d`
  apart, the anchors of the straps at `anchor`, the lowest point of the
  hammock at `low`: parts on the site (each hangs
  on its own cord from tree to tree, and stays when the hammock swings).

  - The bug net (ENO Guardian: 9 ft 4 in long, 454 g): a net that hangs
    from its cord 25 cm over the anchors (by eye), down on each side to 5
    cm under the hammock, its ends drawn in round the suspension.
  - The tarp (ENO ProFly: 10 ft 6 in by 6 ft 4 in, 640 g, six guy
    points): a ridge on its cord 35 cm over the cord of the net (by eye),
    a side at 50 degrees down to two corners on each side (the hexagon of
    the tarp: its bottom edge 2.2 m long, by eye), a guy line from each
    corner to a stake.
  """
  def shelter(name, d, anchor, low) do
    {zn, zt} = {anchor + 0.25, anchor + 0.6}
    net_half = 9 * 12 * 0.0254 / 2 + 2 * 0.0254
    cord = fn z -> Rig.rope({-d / 2, 0.0, z}, {d / 2, 0.0, z}, 0.003) end

    # The bug net: at u along it, its top on the cord, its sides 0.8 m
    # out at the middle (out of the edges of the hammock), down to 5 cm
    # under the hammock; at its ends, drawn in to the suspension.
    net =
      fn {u, v} ->
        x = -net_half + 2 * net_half * u
        p = :math.pow(:math.sin(:math.pi() * u), 0.6)
        {hw, bottom} = {0.03 + 0.77 * p, zn - 0.1 - (zn - 0.1 - (low - 0.05)) * p}
        a = min(abs(v) / 0.35, 1.0)
        side = max(abs(v) - 0.35, 0.0) / 0.65

        {x, sign(v) * hw * :math.sin(a * :math.pi() / 2),
         zn - 0.25 * p * (1 - :math.cos(a * :math.pi() / 2)) - side * (zn - 0.25 * p - bottom)}
      end

    # The tarp: two sides from the ridge (3.2 m) to the bottom edges (2.2 m).
    {half_ridge, half_edge, side} = {10.5 * 12 * 0.0254 / 2, 1.1, 6 * 12 * 0.0254 / 2 + 2 * 0.0254}
    {cy, cz} = {side * :math.cos(50 * :math.pi() / 180), zt - side * :math.sin(50 * :math.pi() / 180)}

    sides =
      for sy <- [-1, 1] do
        fn {u, v} ->
          t = (v + 1) / 2

          {(-half_ridge + 2 * half_ridge * u) * (1 - t) + (-half_edge + 2 * half_edge * u) * t, sy * cy * t,
           zt + (cz - zt) * t}
        end
      end

    guys =
      for sx <- [-1, 1],
          sy <- [-1, 1],
          do: Rig.rope({sx * half_edge, sy * cy, cz}, {sx * (half_edge + 0.3), sy * (cy + 0.6), 0.0}, 0.003)

    [
      Part.new(
        "bug_net_#{name}",
        :cover,
        Enum.map(Bed.cloth(net, rows: 24, cols: 16, t: 0.0005, material: :screen), &Mesh.skin(&1, 0.0005, :nylon)) ++
          [cord.(zn)],
        [@o],
        params: %{"mass" => 0.454},
        sources: ["ENO Guardian Bug Net: 9 ft 4 in long, 454 g (the shops); its shape by eye."]
      ),
      Part.new(
        "tarp_#{name}",
        :cover,
        Enum.flat_map(sides, &Bed.cloth(&1, rows: 8, cols: 4, t: 0.001, material: :dark))
        |> Enum.map(&Mesh.skin(&1, 0.001, :nylon)),
        [@o],
        params: %{"mass" => 0.64},
        sources: ["ENO ProFly Rain Tarp: 10 ft 6 in by 6 ft 4 in, 640 g, six guy points (the shops); its pitch by eye."]
      ),
      Part.new("guy_lines_#{name}", :rope, [cord.(zt) | guys], [@o],
        sources: ["The cord of the ridge of the tarp and four guy lines of 3 mm (by eye)."]
      )
    ]
  end

  defp sign(v) when v < 0, do: -1.0
  defp sign(_), do: 1.0

  @doc """
  A hammock with spreader bars between two trees (photos: the Wikipedia
  page Võng; Wayfair): a bed of 74 by 55 in, 124.5 in long with the cords
  of its ends (Sunnydaze, Double Wide 2-Person Spreader Bar Rope
  Hammock), on a bar of wood at each end, the cords from the bar to a
  ring, and a chain from the ring to a tree strap, the trees 15 ft apart
  (Sunnydaze, the rope hammock with spreader bars: the anchors about 15
  ft apart). Options: `bed` (`:cloth`, a canvas; `:net`, a bed of rope),
  `name`, `person` (true: a person lies along it).
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
    load = if Keyword.get(opts, :person, false), do: @body_load
    sag = Bed.sag(span, length, load)
    # The cords of the ends go from the bar to the ring along the bed; the
    # chain from the ring to the strap at 30 degrees.
    drop = @tan30 * (reach / 2 - span / 2 - fan)
    anchor = 0.5 + sag + drop
    {a1, a2} = {{-reach / 2, 0.0, anchor}, {reach / 2, 0.0, anchor}}
    z = anchor - drop
    {e1, e2} = {{-span / 2, 0.0, z}, {span / 2, 0.0, z}}
    {r1, r2} = {{-span / 2 - fan, 0.0, z}, {span / 2 + fan, 0.0, z}}
    surface = Bed.surface(e1, e2, length: length, width: width, ends: :spread, load: load)

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
    |> then(fn a -> if load, do: lie(a, "bed_#{name}", surface), else: a end)
  end

  @doc """
  A swing of a board on two ropes from the branch of a tree: a branch of
  8 in at 10 ft (HGTV, how to make a tree swing: a branch of 8 in or more,
  10 to 15 ft up), a board of an adult of 60 by 25 cm (Corderie Mansas:
  25 by 60 cm for an adult), 3 cm thick, at 60 cm (Corderie Mansas: 60
  cm for an adult), on two ropes of 18 mm (the polypropylene rope of the
  tall tree swing of Masters of Games) 5 cm in from its ends. It swings
  about the line through the two knots on the branch. Options: `name`, `person` (true: a person
  sits on it, `sit/4`).
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
    # A person on the board, the hands on the ropes at the height of the
    # chest, the feet off the ground (the seat of an adult at 60 cm).
    |> then(fn a ->
      if Keyword.get(opts, :person, false),
        do:
          sit(a, "seat_#{name}", {0.0, -0.03, seat + 0.09},
            grips: [{"l", {-gap / 2, 0.0, seat + 0.45}}, {"r", {gap / 2, 0.0, seat + 0.45}}],
            pose: %{"calf_l" => [{{1.0, 0.0, 0.0}, -60}], "calf_r" => [{{1.0, 0.0, 0.0}, -60}]}
          ),
        else: a
    end)
  end

  @doc """
  A tire swing on a branch (the guides of a tire swing: three chains to a
  swivel, the tire about 30 in over the ground): a tire 225/60R16 on its
  side, three chains to the swivel at 2 m (over the head of an adult who
  sits on the tire, by eye), one rope of 18 mm from the swivel to a
  branch of 8 in at 10 ft (HGTV). It swings about the knot on the branch (two
  hinges) and spins on its swivel. Options: `name`, `person` (true: a
  person sits on it).
  """
  def tire_swing(opts \\ []) do
    name = Keyword.get(opts, :name, "swing_tire")
    branch = @branch
    knot = {0.0, 0.0, branch - @branch_r}
    tire = World.Vehicles.Wheels.tire("225/60R16")
    {low, height} = {30 * 0.0254, 0.225}
    swivel_at = {0.0, 0.0, 2.0}
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
    # A person on the tread of the tire between two chains, the face out,
    # the hands on the two chains at the height of the chest.
    |> then(fn a ->
      if Keyword.get(opts, :person, false) do
        top_z = low + height
        hips = {-0.26, 0.0, top_z + 0.09}

        on_chain = fn k, z ->
          ang = 2 * :math.pi() * k / 3
          t = (sz - 0.045 - z) / (sz - 0.045 - top_z)
          {rim * :math.cos(ang) * t, rim * :math.sin(ang) * t, z}
        end

        sit(a, "spin_#{name}", hips,
          front: {-1.0, 0.0, 0.0},
          grips: [{"l", on_chain.(2, top_z + 0.45)}, {"r", on_chain.(1, top_z + 0.45)}],
          pose: %{"calf_l" => [{{1.0, 0.0, 0.0}, -75}], "calf_r" => [{{1.0, 0.0, 0.0}, -75}]}
        )
      else
        a
      end
    end)
  end

  @doc """
  A porch swing (the guides of a porch swing: 5 ft wide, the seat at 17
  to 19 in, for a ceiling of 8 ft): a bench of slats of wood, 152 by 50
  cm, the seat at 18 in, on a chain at each side from an eye hook in the
  joist of the ceiling, the chain parted into two over the bench (a Y), to
  the front and the back of its side. It swings about the line through
  the two hooks. Options: `name`, `person` (true: a person
  sits on it).
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
    # A person on the bench, who leans back to the slats of the back.
    |> then(fn a ->
      if Keyword.get(opts, :person, false),
        do:
          sit(a, "bench_#{name}", {0.0, -depth / 2 + 0.14, seat + 0.09},
            lean: %{"spine.flex" => -30},
            obstacles: Enum.map(backs, &Contact.solid/1)
          ),
        else: a
    end)
  end

  @doc """
  A hanging egg chair on its stand (Outsunny, the egg chair with a stand:
  98 by 95 by 198 cm, the basket 90 by 60 by 105 cm, 52 cm from the
  floor): a basket of wicker over a frame (ribs and rings of 8 mm, by
  eye), open at its front, with a cushion; a spring, a chain and a swivel
  from the hook at the top of a C stand of steel tube. It swings about
  the hook (two hinges), bounces on its spring (a slide down, to the
  stretch of the spring at its rated load of 317.5 kg) and spins on its
  swivel. Options: `color`, `name`, `person`
  (true: a person sits in it).
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
    spring = Rig.spring("spring_#{name}", hook_at, "bounce_#{name}")
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
    |> swing1("swing_#{name}", hook_at, [spring], limits: [-20, 20])
    |> bounce(
      "bounce_#{name}",
      {0.0, 0.0, elem(hook_at, 2) - Rig.spring_length() / 2},
      [chain, top_half],
      to: "swing_#{name}_y",
      limits: [0, Rig.stretch(317.5)]
    )
    |> spin("spin_#{name}", swivel_at, [bottom_half, basket], to: "bounce_#{name}")
    # A person on the cushion, inside the basket, the hands on the lap,
    # the legs out of its front. The back leans back and to the left side
    # as far as the person wants, and stops at the wicker.
    |> then(fn a ->
      if Keyword.get(opts, :person, false),
        do:
          sit(a, "spin_#{name}", {0.0, 0.03, low + @cushion * bh + 0.09},
            recline: 4,
            lean: %{"spine.flex" => -40, "spine.spread" => -20},
            obstacles: [wicker(bw, bd, bh, low)],
            rest: [{"l", {-0.12, 0.28, low + @cushion * bh + 0.2}}, {"r", {0.12, 0.28, low + @cushion * bh + 0.2}}],
            pose: %{
              "thigh_l" => [{{1.0, 0.0, 0.0}, 85}],
              "thigh_r" => [{{1.0, 0.0, 0.0}, 85}],
              "calf_l" => [{{1.0, 0.0, 0.0}, -70}],
              "calf_r" => [{{1.0, 0.0, 0.0}, -70}]
            }
          ),
        else: a
    end)
  end

  @doc """
  The shape of the basket of an egg chair at `t` (0 at its bottom, 1 at
  its top): its half width and its half depth there, over their most (a
  teardrop, wide from the seat to high up).
  """
  def egg(t), do: :math.pow(:math.sin(:math.pi() * t), 0.45) * (1 - 0.15 * t)

  # The wicker of an egg chair as an obstacle (`World.Contact`): a point
  # out of the inner face of its wall (the ribs are 8 mm), but not
  # through its opening (to the front, up to 82% of its height), or a
  # point over its top. The wicker between the ribs is closed.
  defp wicker(bw, bd, bh, low) do
    fn {x, y, z} ->
      t = (z - low) / bh
      over = t >= 1 and abs(x) < bw / 2 and abs(y) < bd / 2
      over or (t > 0 and t < 1 and out_of_wicker?(x, y, t, bw, bd))
    end
  end

  defp out_of_wicker?(x, y, t, bw, bd) do
    e = egg(t)
    {u, v} = {x / (bw / 2 * e - 0.008), y / (bd / 2 * e - 0.008)}
    rho = :math.sqrt(u * u + v * v)
    rho > 1 and not (t < 0.82 and v > 0.2 * rho)
  end

  # The basket of an egg chair: ribs of wicker over an egg, from the seat
  # to the top, rings round it, its front open from the seat to the top
  # of the opening, a cushion on the seat, and a short chain to the
  # swivel.
  defp basket(name, bw, bd, bh, low, to) do
    r = 0.008
    # A teardrop: wide from the seat to high up, narrow only near its hook.
    profile = &egg/1
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

    # The cushion in the bowl: an oval of the shape of the basket at its
    # top, 8 cm thick.
    {cx, cy} = {bw / 2 * egg(@cushion) * 0.92, bd / 2 * egg(@cushion) * 0.92}

    cushion =
      Shape.cylinder(1.0, 0.08, :fabric, sides: 20, frame: World.Frame.move({0.0, 0.0, low + (@cushion * bh - 0.08)}))
      |> then(&%{&1 | points: for({x, y, z} <- &1.points, do: {x * cx, y * cy, z})})
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

  # A material of a role: a color (with the roughness and the metalness of
  # cloth), or a map of its own.
  defp color(%{} = spec), do: Map.merge(%{"roughness" => 0.85, "metalness" => 0.0}, spec)
  defp color(rgb), do: %{"color" => rgb, "roughness" => 0.85, "metalness" => 0.0}

  # The assembly of a thing that hangs: the site (or the stand) as its
  # root. A site holds it: no check of its stand (`"site"` in its extras).
  defp new(name, root, about, opts \\ []) do
    site = Keyword.get(opts, :site, true)

    Assembly.new(name, root,
      root: root.name,
      kind: :hanging,
      materials: Map.new(Keyword.get(opts, :materials, %{}), fn {role, c} -> {role, color(c)} end),
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
