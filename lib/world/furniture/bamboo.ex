defmodule World.Furniture.Bamboo do
  @moduledoc """
  The bamboo shop of the world (the family `:bamboo`): furniture of culms
  of bamboo (bàn ghế tre), from the same parts in each variant:

  - the pieces of `World.Furniture.Bamboo.Culm`: a culm with its nodes
    and open or closed ends, a slat split from a culm, a cord;
  - the joint of the shops: a rail goes through a hole in the leg, and its
    end shows out of the other side (`rail/4`);
  - the panels of `World.Furniture.Bamboo.Panel`: slats side by side (a
    seat), thin culms side by side (the uprights or the bars of a back),
    a lattice (a frame in the frame), and the zigzag of white cord that
    holds the slats and the uprights.

  The models:

  - `chair/1`: a chair with a straight back (ghế tre lưng tựa đứng): the
    rear legs go up to the back, a seat of slats across with two rows of
    lashing, a back of uprights with two rows of lashing;
  - `folding/1`: a folding chair (ghế xếp) on two frames in an X: the
    posts of the back go down to the front feet, the rear legs go from
    the front of the seat to the rear feet, with a pin at each side where
    they cross. The rear legs and the seat turn on hinges, and the clip
    `fold` folds the chair flat and opens it again. Option `back`:
    `:uprights` (a back of thin uprights with lashing) or `:bars` (a back
    of culms across, on the front of the posts);
  - `armchair/1`: an armchair of thick culms with arms, a seat of slats
    on two rails at each side, and a back that leans. Options `back`
    (`:slats` or `:lattice`), `width` and `panels`: a bench (ghế băng) is
    a wide armchair with three panels of lattice and a leg at the middle;
  - `table/1`: a low table of the set (bàn tre): a top of slats on a frame,
    and a shelf of slats.

  The sizes are by eye from the photos of the shops that the owner sent
  (search results of Google, November 2026): Ghế tre lưng tựa đứng
  (Shopee Việt Nam), Bàn ghế tre (Tre trúc Sài Gòn), Ghế tre, ghế xếp
  (Siêu Thị Tre Trúc), Ghế tre liền bàn (Tre Trúc Ngọc Dương, Facebook,
  2025), Ghế tre gia đình (Home eGreen). The photos are not in the
  repository. The seat is at 0.42 to 0.45 m: the common height of a
  chair is 0.40 to 0.45 m (Neufert, Architects' Data).

  The axes: x across the front, y from the back to the front, z up.
  """
  alias World.{Assembly, Part, Vec}
  alias World.Furniture.Bamboo.{Culm, Panel}

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  @source "The sizes by eye from photos of the bamboo shops (World.Furniture.Bamboo); the culms of tầm vông (PROSEA)."

  @doc "The models of the bamboo shop, as `{name, fun}`."
  def models,
    do: [
      {"ghe_tre", fn -> chair() end},
      {"ghe_tre_xep", fn -> folding() end},
      {"ghe_tre_xep_nan_ngang", fn -> folding(back: :bars, name: "ghe_tre_xep_nan_ngang") end},
      {"ghe_tre_banh", fn -> armchair() end},
      {"ghe_tre_banh_khung", fn -> armchair(back: :lattice, name: "ghe_tre_banh_khung") end},
      {"ghe_bang_tre", fn -> armchair(back: :lattice, width: 1.5, panels: 3, name: "ghe_bang_tre") end},
      {"ban_tre", fn -> table() end}
    ]

  @doc """
  A rail from `a` to `b` through two legs of radius `leg`: it goes
  `over` (option, 10 mm) out of the far side of each leg, where its end
  shows. Options of `Culm.piece/3`; the ends are open by default.
  """
  def rail(a, b, leg, opts \\ []) do
    dir = Vec.norm(Vec.sub(b, a))
    out = leg + Keyword.get(opts, :over, 0.01)

    Culm.piece(
      Vec.sub(a, Vec.scale(dir, out)),
      Vec.add(b, Vec.scale(dir, out)),
      Keyword.merge([ends: {:open, :open}], opts)
    )
  end

  @doc """
  A chair with a straight back (photo: Ghế tre lưng tựa đứng, Shopee).
  Options: `name`, `height` of the seat (0.45).
  """
  def chair(opts \\ []) do
    name = Keyword.get(opts, :name, "ghe_tre")
    h = Keyword.get(opts, :height, 0.45)
    {x, y, d, rd} = {0.19, 0.18, 0.045, 0.03}
    {lr, rr} = {d / 2, rd / 2}
    leg = fn px, py, top -> Culm.piece({px, py, 0.0}, {px, py, top}, d: d, ends: {:open, :node}, phase: 0.55) end
    side = h - 0.02 - rr

    frame =
      [leg.(-x, y, h + 0.02), leg.(x, y, h + 0.02), leg.(-x, -y, 0.9), leg.(x, -y, 0.9)] ++
        for(py <- [y, -y], do: rail({-x, py, h - 0.005}, {x, py, h - 0.005}, lr, d: rd)) ++
        for(px <- [x, -x], do: rail({px, -y, side}, {px, y, side}, lr, d: rd)) ++
        for(py <- [y, -y], do: rail({-x, py, 0.13}, {x, py, 0.13}, lr, d: 0.025)) ++
        for(px <- [x, -x], do: rail({px, -y, 0.21}, {px, y, 0.21}, lr, d: 0.025)) ++
        for(z <- [0.56, 0.86], do: rail({-x, -y, z}, {x, -y, z}, lr, d: rd))

    seat =
      Panel.slats(
        {{-(x - lr), -(y - rr), side + rr}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}},
        2 * (x - lr),
        2 * (y - rr),
        lash: [0.28, 0.72]
      )

    back =
      Panel.culms(
        {{-(x - lr), -y - 0.008, 0.56 + rr / 2}, {0.0, 0.0, 1.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}},
        0.3 - rr,
        2 * (x - lr),
        d: 0.016,
        lash: [0.4, 0.75]
      )

    build(name, "A chair of bamboo with a straight back (ghế tre lưng tựa đứng): the rear legs go up to the back.", [
      {"frame", frame, "Four legs of 45 mm, rails of 30 mm through the legs, stretchers of 25 mm."},
      {"seat", seat, "A seat of slats across, 16 by 6 mm, with two rows of lashing of white cord."},
      {"back", back, "A back of uprights of 16 mm between two rails, with two rows of lashing."}
    ])
  end

  @doc """
  A folding chair on two frames in an X (photos: Siêu Thị Tre Trúc, Home
  eGreen) that folds flat. Options: `name`, `back` (`:uprights` or
  `:bars`).

  The posts of the back go down to the front feet; the rear legs are
  outside the posts and turn on a pin at each side where the two frames
  cross (the joint `rear_legs_NAME`). The seat is inside the posts and
  turns on its rear rail, which goes through the posts (the joint
  `seat_NAME`); its front rests on the top rail of the rear legs. Folded
  (the clip `fold`), the rear legs and the seat lie along the posts. The
  rails of the rear legs and the low rail of the posts are on a face of
  their legs, at the back of the chair when it is folded, so that no
  rail goes through a leg of the other frame.
  """
  def folding(opts \\ []) do
    name = Keyword.get(opts, :name, "ghe_tre_xep")
    back = Keyword.get(opts, :back, :uprights)
    {xa, xb, d} = {0.2, 0.24, 0.035}
    r = d / 2
    {sr, t, rt} = {0.015, 0.006, 0.0125}
    x = {1.0, 0.0, 0.0}
    # The posts: from the front foot up to the top of the back.
    {foot, top} = grounded({0.0, 0.2, 0.0}, {0.0, -0.12, 0.88}, r)
    post = fn s, px -> Vec.add(Vec.add(foot, Vec.scale(Vec.sub(top, foot), s)), {px, 0.0, 0.0}) end
    up = Vec.norm(Vec.sub(top, foot))
    plen = Vec.len(Vec.sub(top, foot))
    n = Vec.cross(up, x)
    # The seat: its rim at 0.425 m, from the rear rail on the posts to
    # the front rail.
    seat_z = 0.425
    y0 = elem(post.((seat_z - elem(foot, 2)) / (elem(top, 2) - elem(foot, 2)), 0.0), 1)
    y1 = 0.32
    # The rear legs: from the rear foot up to under the front of the seat,
    # with the top rail on their back face, under the front rail.
    rail_top = {0.0, y1, seat_z - sr - rt}
    {b_foot, b_top} = rear_legs({0.0, -0.22, 0.0}, rail_top, r, r + rt)
    b_dir = Vec.norm(Vec.sub(b_top, b_foot))
    behind_b = Vec.scale(Vec.cross(b_dir, x), -1.0)
    pin = cross(foot, top, b_top, b_foot)

    posts =
      for(px <- [-xa, xa], do: Culm.piece(post.(0.0, px), post.(1.0, px), d: d, ends: {:open, :node}, phase: 0.4)) ++
        [
          rail(
            Vec.sub(post.(0.11, -xa), Vec.scale(n, r + 0.011)),
            Vec.sub(post.(0.11, xa), Vec.scale(n, r + 0.011)),
            0.0,
            d: 0.022,
            over: r
          )
        ] ++
        for(
          sx <- [-1, 1],
          do:
            Culm.piece(
              {sx * (xa - r - 0.004), elem(pin, 1), elem(pin, 2)},
              {sx * (xb + r + 0.006), elem(pin, 1), elem(pin, 2)},
              d: 0.012,
              ends: {:node, :node}
            )
        )

    on_b = fn point, k -> Vec.add(point, Vec.scale(behind_b, k)) end
    low = along(b_foot, b_top, 0.25)

    rear =
      for(
        px <- [-xb, xb],
        do: Culm.piece(Vec.add(b_foot, {px, 0.0, 0.0}), Vec.add(b_top, {px, 0.0, 0.0}), d: d, ends: {:open, :node})
      ) ++
        [
          rail(Vec.add(on_b.(low, r + 0.011), {-xb, 0.0, 0.0}), Vec.add(on_b.(low, r + 0.011), {xb, 0.0, 0.0}), 0.0,
            d: 0.022,
            over: r
          ),
          rail(Vec.add(rail_top, {-xb, 0.0, 0.0}), Vec.add(rail_top, {xb, 0.0, 0.0}), 0.0, d: 2 * rt, over: r)
        ]

    # The seat: a rim of four culms inside the posts (the rear rail
    # through the posts, two side rails, the front rail), and slats that
    # fill the rim from rail to rail, their tops level with the top of
    # the rim.
    xs = xa - r - sr - 0.002

    seat =
      [
        rail({-xa, y0, seat_z}, {xa, y0, seat_z}, r, d: 2 * sr, over: 0.004),
        Culm.piece({-xs - sr, y1, seat_z}, {xs + sr, y1, seat_z}, d: 2 * sr, ends: {:open, :open})
      ] ++
        for(
          px <- [-xs, xs],
          do: Culm.piece({px, y0 + sr, seat_z}, {px, y1 - sr, seat_z}, d: 2 * sr, ends: {:node, :node})
        ) ++
        Panel.slats({{-(xs - sr), y0, seat_z + sr - t}, {0.0, 1.0, 0.0}, x, {0.0, 0.0, 1.0}}, y1 - y0, 2 * (xs - sr),
          width: 0.018,
          t: t,
          gap: 0.002
        )

    backrest =
      case back do
        :uprights ->
          [
            rail(post.(0.62, -xa), post.(0.62, xa), r, d: 0.025, over: 0.004),
            rail(post.(0.9, -xa), post.(0.9, xa), r, d: 0.025, over: 0.004),
            rail(post.(0.97, -xa), post.(0.97, xa), r, d: 0.022, over: 0.004)
          ] ++
            Panel.culms({Vec.sub(post.(0.62, -(xa - r)), Vec.scale(n, 0.008)), up, x, n}, 0.28 * plen, 2 * (xa - r),
              d: 0.014,
              lash: [0.45, 0.8]
            )

        :bars ->
          Panel.culms({Vec.add(post.(0.6, -0.22), Vec.scale(n, r)), x, up, n}, 0.44, 0.38 * plen,
            d: 0.024,
            gap: 0.006,
            ends: {:open, :open}
          )
      end

    # The angles of the fold: the rear legs and the seat turn to lie
    # along the posts.
    angle = fn {_, vy, vz} -> :math.atan2(vz, vy) * 180 / :math.pi() end
    legs_fold = Float.round(angle.(up) - angle.(b_dir), 1)
    seat_fold = Float.round(angle.(Vec.scale(up, -1.0)), 1)
    {legs, chair_seat} = {"rear_legs_#{name}", "seat_#{name}"}

    build(
      name,
      "A folding chair of bamboo (ghế xếp) on two frames in an X, with a pin at each side where they cross; it folds flat.",
      [
        {"frame", posts,
         "The posts of the back down to the front feet, 35 mm, a low rail of 22 mm, two pins of 12 mm."},
        {"rear_legs", rear,
         "The rear legs of 35 mm, a low rail of 22 mm and a top rail of 25 mm under the front of the seat.",
         hinge: {pin, [0, legs_fold]}},
        {"seat", seat,
         "A seat of slats from the back to the front, 18 by 6 mm, that fill a rim of four culms of 30 mm, level with its top.",
         hinge: {{0.0, y0, seat_z}, [seat_fold, 0]}},
        {"back", backrest,
         if(back == :uprights,
           do: "A back of uprights of 14 mm between two rails, with two rows of lashing.",
           else: "A back of culms of 24 mm across, on the front of the posts."
         )}
      ],
      [
        %{
          name: "fold",
          length: 3.0,
          keys: [
            {0.0, %{legs => 0.0, chair_seat => 0.0}},
            {1.5, %{legs => legs_fold, chair_seat => seat_fold}},
            {3.0, %{legs => 0.0, chair_seat => 0.0}}
          ]
        }
      ]
    )
  end

  # The rear legs from their foot to a top under the top rail at `rail`,
  # with the axis of the rail `off` from the axis of the legs, on their
  # back face: a few steps, since the face depends on the slope of the
  # legs. The foot stands level (`grounded/3`).
  defp rear_legs(foot0, rail, r, off) do
    Enum.reduce(1..4, {foot0, rail}, fn _, {foot, top} ->
      dir = Vec.norm(Vec.sub(top, foot))
      back = Vec.scale(Vec.cross(dir, {1.0, 0.0, 0.0}), -1.0)
      grounded(foot0, Vec.sub(rail, Vec.scale(back, off)), r)
    end)
  end

  @doc """
  An armchair of thick culms (photos: Tre Trúc Ngọc Dương, Tre trúc Sài
  Gòn). Options: `name`, `back` (`:slats` or `:lattice`), `width` (0.62
  m), `panels` (1).
  """
  def armchair(opts \\ []) do
    name = Keyword.get(opts, :name, "ghe_tre_banh")
    back = Keyword.get(opts, :back, :slats)
    width = Keyword.get(opts, :width, 0.62)
    panels = Keyword.get(opts, :panels, 1)
    {d, rd} = {0.06, 0.04}
    {lr, rr} = {d / 2, rd / 2}
    {x, y} = {width / 2 - lr, 0.25}
    seat_z = 0.42
    side = seat_z - rr
    # The front legs go up to the arms; each rear leg is one culm from the
    # ground to the top of the back, and leans back.
    front = fn px -> Culm.piece({px, y, 0.0}, {px, y, 0.68}, d: d, ends: {:open, :open}, phase: 0.6) end
    {foot, top} = grounded({0.0, -y, 0.0}, {0.0, -y - 0.12, 0.95}, lr)

    rear = fn z, px ->
      Vec.add(along(foot, top, (z - elem(foot, 2)) / (elem(top, 2) - elem(foot, 2))), {px, 0.0, 0.0})
    end

    up = Vec.norm(Vec.sub(top, foot))
    n = Vec.cross(up, {1.0, 0.0, 0.0})
    mids = if width > 1.0, do: [0.0], else: []
    rear_y = elem(rear.(seat_z, 0.0), 1)

    frame =
      for(px <- [-x, x], do: front.(px)) ++
        for(
          px <- [-x, x],
          do:
            Culm.piece(Vec.add(foot, {px, 0.0, 0.0}), Vec.add(top, {px, 0.0, 0.0}),
              d: d,
              ends: {:open, :open},
              phase: 0.6
            )
        ) ++
        for(
          px <- mids,
          py <- [y, rear_y],
          do: Culm.piece({px, py, 0.0}, {px, py, side - rr}, d: d, ends: {:open, :node})
        ) ++
        for(px <- [-x, x], z <- [side, 0.3, 0.62], do: rail(rear.(z, px), {px, y, z}, lr, d: rd, over: 0.02)) ++
        for(z <- [seat_z, 0.12], do: rail({-x, y, z}, {x, y, z}, lr, d: rd, over: 0.02)) ++
        for(z <- [seat_z, 0.12, 0.5, 0.9], do: rail(rear.(z, -x), rear.(z, x), lr, d: rd, over: 0.02)) ++
        for(px <- mids, do: rail({px, rear_y, side - rr}, {px, y, side - rr}, lr, d: rd, over: 0.02))

    seat =
      Panel.slats(
        {{-(x - lr), rear_y + rr, seat_z}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}},
        2 * (x - lr),
        y - rr - rear_y - rr,
        width: 0.02,
        t: 0.007
      )

    # The back between the rear legs, from the rail at 0.5 m to the rail
    # at 0.9 m: one panel, or panels with thin uprights between them.
    {z0, z1} = {0.5 + rr, 0.9 - rr}
    lu = Vec.len(Vec.sub(rear.(z1, 0.0), rear.(z0, 0.0)))
    xs = for i <- 0..panels, do: -(x - lr) + 2 * (x - lr) * i / panels

    dividers =
      for px <- xs -- [hd(xs), List.last(xs)],
          do: Culm.piece(rear.(z0 - rr, px), rear.(z1 + rr, px), d: 0.03, ends: {:node, :node})

    panel =
      for {pa, pb} <- Enum.zip(xs, tl(xs)) do
        inner = if pa == hd(xs), do: 0.0, else: 0.015
        outer = if pb == List.last(xs), do: 0.0, else: 0.015
        corner = rear.(z0, pa + inner)

        case back do
          :slats ->
            Panel.slats({corner, up, {1.0, 0.0, 0.0}, n}, lu, pb - pa - inner - outer,
              width: 0.024,
              t: 0.007,
              gap: 0.01
            )

          :lattice ->
            Panel.lattice({corner, up, {1.0, 0.0, 0.0}, n}, lu, pb - pa - inner - outer, inset: 0.06)
        end
      end
      |> List.flatten()

    back_frame = dividers

    kind = if width > 1.0, do: "A bench of bamboo (ghế băng)", else: "An armchair of bamboo (ghế bành)"

    build(name, "#{kind} of thick culms, with arms and a back that leans.", [
      {"frame", frame,
       "Front legs of 60 mm up to the arms, rear legs of 60 mm up to the top of the back, rails of 40 mm through the legs with their ends out by 20 mm."},
      {"seat", seat, "A seat of slats across, 20 by 7 mm."},
      {"back", back_frame ++ panel,
       if(back == :slats,
         do: "A back of slats between two rails of the rear legs.",
         else: "A back of #{panels} panel(s) of lattice: a frame in the frame, with four links."
       )}
    ])
  end

  @doc "A low table of the set (photo: Tre trúc Sài Gòn). Options: `name`."
  def table(opts \\ []) do
    name = Keyword.get(opts, :name, "ban_tre")
    {x, y, d, rd} = {0.46, 0.24, 0.05, 0.035}
    {lr, rr} = {d / 2, rd / 2}
    top_z = 0.45

    frame =
      for(px <- [-x, x], py <- [y, -y], do: Culm.piece({px, py, 0.0}, {px, py, top_z}, d: d, ends: {:open, :node})) ++
        for(py <- [y, -y], z <- [top_z - 0.03, 0.14], do: rail({-x, py, z}, {x, py, z}, lr, d: rd)) ++
        for(px <- [-x, x], z <- [top_z - 0.03 - rd, 0.14 - rd], do: rail({px, -y, z}, {px, y, z}, lr, d: rd))

    slats = fn z ->
      Panel.slats(
        {{-(x - lr), -(y - rr), z}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}},
        2 * (x - lr),
        2 * (y - rr),
        width: 0.022,
        t: 0.007,
        gap: 0.004
      )
    end

    build(name, "A low table of bamboo (bàn tre) of the set: a top of slats and a shelf of slats.", [
      {"frame", frame, "Four legs of 50 mm, rails of 35 mm through the legs."},
      {"top", slats.(top_z - 0.03 + rr), "A top of slats, 22 by 7 mm."},
      {"shelf", slats.(0.14 + rr), "A shelf of slats, 22 by 7 mm."}
    ])
  end

  # The assembly: the first group is the root, the others are on it.
  # A group with `hinge: {point, limits}` turns about the line along x
  # through the point: the joint of its name, of the role `:fold`.
  defp build(name, about, [{root, shapes, note} | rest], clips \\ []) do
    hinge = fn at -> Part.port("hinge", at, {1, 0, 0}, {0, 0, 1}) end

    part = fn group, meshes, text, ports ->
      Part.new("#{group}_#{name}", group_kind(group), meshes, [@o | ports], sources: [text])
    end

    hinges = for {group, _, _, opts} <- rest, {at, _} <- [opts[:hinge]], do: %{hinge.(at) | name: "#{group}_hinge"}

    asm =
      Assembly.new(name, part.(root, shapes, note, hinges),
        root: "#{root}_#{name}",
        kind: :bamboo,
        sources: [about, @source],
        clips: clips
      )

    Enum.reduce(rest, asm, fn
      {group, meshes, text}, asm ->
        Assembly.add(asm, "#{group}_#{name}", part.(group, meshes, text, []), at: "o", port: "o")

      {group, meshes, text, opts}, asm ->
        {at, limits} = opts[:hinge]

        Assembly.add(asm, "#{group}_#{name}", part.(group, meshes, text, [hinge.(at)]),
          at: "#{group}_hinge",
          port: "hinge",
          kind: :hinge,
          role: :fold,
          limits: limits
        )
    end)
  end

  defp group_kind("frame"), do: :frame
  defp group_kind("seat"), do: :seat
  defp group_kind("back"), do: :back
  defp group_kind(_), do: :panel

  # A leg that leans, from its foot to `top`: the foot goes up until the
  # lowest edge of its end is on the ground, as the end of a leg that
  # stands level.
  defp grounded({fx, fy, _} = foot, top, r) do
    dir = Vec.norm(Vec.sub(top, foot))
    lift = r * :math.sqrt(max(1.0 - elem(dir, 2) ** 2, 0.0))
    {{fx, fy, lift}, top}
  end

  # A point at a part `s` of the way from `a` to `b`.
  defp along(a, b, s), do: Vec.add(a, Vec.scale(Vec.sub(b, a), s))

  # The point where two lines cross in the plane of y and z.
  defp cross({_, ay, az}, {_, by, bz}, {_, cy, cz}, {_, dy, dz}) do
    {d1y, d1z, d2y, d2z} = {by - ay, bz - az, dy - cy, dz - cz}
    den = d1y * d2z - d1z * d2y
    t = ((cy - ay) * d2z - (cz - az) * d2y) / den
    {0.0, ay + t * d1y, az + t * d1z}
  end
end
