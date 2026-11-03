defmodule World.Boats.Ghe do
  @moduledoc """
  The ghe of Vũng Tàu (`docs/world.md`, step P6): a wooden fishing boat,
  built to the rules of the wooden hull of QCVN 91:2025/BNNMT (Chương
  II.II-B, `priv/standards/qcvn91.json`), with each sawn size rounded up
  to a section of Bảng 1 of TCVN 1075:1971 (`World.Materials.Stock.vn_section/2`):
  the least pair of a thickness and one of its widths that is not less
  than the rules (a keel of 220 by 308 mm is 250 by 320 mm).

  - The main sizes are those of BV-92479-TS, a wooden fishing boat of Long
    Hải (Bà Rịa - Vũng Tàu) built in 2002: a length of 20.70 m (Lmax), a
    breadth of 6.80 m (Bmax) and a depth of 3.60 m (D), from the notice of
    its sale (thads.moj.gov.vn, 2026).
  - The lines (the plan, the sheer, the sections, the stem, the transom)
    and the draft (62% of D) are by eye: no drawing of the boat is open.
  - The rules give each size from the length L at the waterline, the
    breadth B at the waterline, D, and the wood group (TCVN 12619:2019).
    The model takes group III, the largest sizes of groups I to III, so
    any wood of those groups is on the safe side. QCVN 91 is for boats of
    24 m (Lmax) and more, and its tables start at L = 21 m; a shorter
    boat takes the sizes of the first band.
  - The wood for the mass is sao đen (Hopea odorata), a wood of boats.
  - The members: the keel, the stem, the sternpost, a frame (sườn đơn) at
    each frame spacing (L + 20 cm or less) with its floor in the middle
    body, the keelson, the bilge and side stringers, the deck beams on
    each second frame with the clamp and the shelf, the planks of the hull
    (a skin), the transom, the deck, the bulwark, the rudder on its
    hinge, and the wheelhouse. Not yet: the engine and its bed, the
    propeller, the fish holds, the mast and the eyes on the bow.

  The axes: x across (to starboard), y along (from the transom to the
  bow), z up from the bottom of the keel.
  """
  alias World.{Assembly, Mesh, Part, Shape, Standards}
  alias World.Materials.Stock

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  # BV-92479-TS: Lmax, Bmax, D (m).
  @lmax 20.7
  @bmax 6.8
  @depth 3.6
  @group "III"

  # The draft at full load, a part of D (by eye).
  @draft 0.62
  # The stations of the hull along s (0 at the transom, 1 at the stem),
  # and the points of each half section.
  @stations 40
  @k 8

  @doc "The ghe of BV-92479-TS."
  def ghe, do: ghe(@lmax, @bmax, @depth)

  @doc """
  A ghe of a length (Lmax), a breadth (Bmax) and a depth (D), in meters.
  """
  def ghe(lmax, bmax, depth) do
    h = %{lmax: lmax, bmax: bmax, depth: depth}
    {l, b} = {waterline(h), breadth(h)}
    s = sizes(scantlings(l, b, depth, @group), l)

    # The rabbet: the planks meet the keel at 60% of its height.
    h = Map.merge(h, %{zr: s.keel_h * 0.6, s: s})

    Assembly.new("ghe_vung_tau", keel(h),
      root: "keel",
      kind: :boat,
      sources: [
        "A ghe of Vũng Tàu: the sizes of BV-92479-TS (Lmax 20.70 m, Bmax 6.80 m, D 3.60 m, a wooden fishing boat of Long Hải, 2002); its members to QCVN 91:2025/BNNMT (Chương II.II-B, wood group III), sawn to the sizes of TCVN 1075:1971; the lines by eye."
      ],
      extras: %{
        "length" => Float.round(l, 2),
        "breadth" => Float.round(b, 2),
        "scantlings" => Map.new(s.list)
      }
    )
    |> Assembly.add("stem", stem(h), at: @o, port: @o)
    |> Assembly.add("sternpost", sternpost(h), at: @o, port: @o)
    |> Assembly.add("framing", framing(h), at: @o, port: @o)
    |> Assembly.add("keelson", keelson(h), to: "framing", at: @o, port: @o)
    |> Assembly.add("stringers", stringers(h), to: "framing", at: @o, port: @o)
    |> Assembly.add("deck_frame", deck_frame(h), to: "framing", at: @o, port: @o)
    |> Assembly.add("planks", planks(h), at: @o, port: @o)
    |> Assembly.add("deck", deck(h), to: "deck_frame", at: @o, port: @o)
    |> Assembly.add("wheelhouse", wheelhouse(h), to: "deck", at: @o, port: @o)
    |> Assembly.add("rudder", rudder(h),
      at: Part.port("rudder", {0.0, y_post(h) - 0.2, 0.0}, {0, 0, 1}, {0, 1, 0}),
      port: "stock",
      kind: :hinge,
      role: :rudder,
      limits: [-35, 35]
    )
  end

  # --- The lines -----------------------------------------------------------------------------

  # The half breadth at the sheer (to the outside of the planks), at s.
  defp half(%{bmax: bmax}, s) do
    f =
      if s <= 0.45,
        do: 0.6 + 0.4 * :math.sin(:math.pi() / 2 * s / 0.45),
        else: :math.pow(:math.cos(:math.pi() / 2 * (s - 0.45) / 0.55), 1.1)

    max(bmax / 2 * f, 0.04)
  end

  # The height of the deck at the side over the rabbet: lowest at 0.4 of
  # the length, up to the bow and less to the transom.
  defp sheer(%{depth: d}, s) when s >= 0.4, do: d + 1.6 * ((s - 0.4) / 0.6) ** 2
  defp sheer(%{depth: d}, s), do: d + 0.5 * ((0.4 - s) / 0.4) ** 2

  # The height of the bottom of the planks (the rabbet line) over the
  # rabbet of the middle: up to the stem in the fore body, up to the
  # transom in the after body.
  defp bottom(h, s) when s > 0.72, do: (sheer(h, 1.0) - 0.3) * ((s - 0.72) / 0.28) ** 1.8
  defp bottom(%{depth: d}, s) when s < 0.12, do: 0.55 * d * ((0.12 - s) / 0.12) ** 2
  defp bottom(_h, _s), do: 0.0

  # The power of a section: full in the middle, a V at the ends.
  defp power(s), do: 1.3 + 1.7 * :math.sqrt(:math.sin(:math.pi() * s))

  # The length at the waterline (QCVN 91, 3.2.1.2): from the transom (it
  # goes under the water) to the stem at the draft.
  defp waterline(%{lmax: lmax, depth: d} = h),
    do: lmax * (0.72 + 0.28 * (@draft * d / (sheer(h, 1.0) - 0.3)) ** (1 / 1.8))

  # The breadth at the waterline in the middle (QCVN 91, 3.2.6).
  defp breadth(%{depth: d} = h) do
    p = power(0.45)
    r = @draft * d / sheer(h, 0.45)
    2 * half(h, 0.45) * (1 - (1 - r) ** p) ** (1 / p)
  end

  # A half section at s, from the keel (i = 0) to the sheer (i = k - 1),
  # `inset` inside the outside of the planks: points {x, z}.
  defp section(h, s, inset) do
    {hb, zb, zs, p} = {half(h, s), h.zr + bottom(h, s), h.zr + sheer(h, s), power(s)}
    xk = h.s.keel_w / 2

    pts =
      for i <- 0..(@k - 1) do
        t = :math.pi() / 2 * i / (@k - 1)
        {xk + (hb - xk) * :math.sin(t) ** (2 / p), zb + (zs - zb) * (1 - :math.cos(t) ** (2 / p))}
      end

    pts |> Enum.with_index() |> Enum.map(fn {pt, i} -> inside(pt, normal(pts, i), inset) end)
  end

  # The normal to the outside of a half section at a point (the curve goes
  # from the keel to the sheer).
  defp normal(pts, i) do
    {x0, z0} = Enum.at(pts, max(i - 1, 0))
    {x1, z1} = Enum.at(pts, min(i + 1, @k - 1))
    l = :math.sqrt((x1 - x0) ** 2 + (z1 - z0) ** 2)
    {(z1 - z0) / l, -(x1 - x0) / l}
  end

  defp inside({x, z}, {nx, nz}, d), do: {x - nx * d, z - nz * d}

  defp ys(h, s), do: s * h.lmax

  # The stations of the hull.
  defp stations, do: for(j <- 0..@stations, do: min(j / @stations, 0.995))

  # --- The sizes of the members ------------------------------------------------------------------

  @doc """
  The sizes of the members of the rules (cm, cm² for an area), for the
  length L and the breadth B at the waterline, the depth D (m) and a wood
  group: `%{name => size}`.

      iex> s = World.Boats.Ghe.scantlings(18.8, 6.6, 3.6, "III")
      iex> {s.keel, s.frame, s.beam, s.spacing}
      {22, [12, 15.5, 17], 16, 38.8}
  """
  def scantlings(l, b, d, group) do
    pick = fn name, v ->
      t = Standards.table("qcvn91", name)
      Enum.at(t["sizes"][group], band(t["bands"], v))
    end

    planks = Standards.table("qcvn91", "planking")["sizes"]

    %{
      keel: pick.("keel", l),
      keelson: pick.("keelson", l),
      stem: pick.("stem", l),
      frame: pick.("frame", d + b / 2),
      beam: pick.("beam", b),
      clamp: pick.("clamp", l),
      shelf: pick.("shelf", l),
      bilge_stringer: pick.("bilge_stringer", l),
      side_stringer: pick.("side_stringer", l),
      plank: planks["outer"][group],
      ceiling: planks["inner"][group],
      deck: planks["deck"][group],
      sheer_strake: planks["sheer_strake"][group],
      spacing: Float.round(l + 20, 1)
    }
  end

  # The band of a value: the last low edge that is not more than it, or
  # the first band.
  defp band(edges, v), do: max(Enum.count(edges, &(&1 <= v)) - 1, 0)

  # The sawn sizes (m), TCVN 1075, and the list for the extras (mm).
  defp sizes(r, l) do
    t = &Stock.vn(:thickness, &1 / 100)
    # A section of Bảng 1 of TCVN 1075 that is not less than the rules.
    sec = fn a, b -> Stock.vn_section(a / 100, b / 100) end
    square = fn a -> a |> sec.(a) |> elem(0) end
    [f1, f2, f3] = Enum.map(r.frame, square)
    [cw, ct] = r.clamp
    [sw, st] = r.shelf
    # The rules give the short side of the keel; the long side is 1.4
    # times (by eye).
    {keel_w, keel_h} = sec.(r.keel, r.keel * 1.4)

    s = %{
      keel_w: keel_w,
      keel_h: keel_h,
      keelson: square.(r.keelson),
      stem: square.(r.stem),
      frame: {f1, f2, f3},
      # A floor: the thickness of the frame at the bottom, its area 4/3 of
      # the frame (9.7).
      floor_h: elem(sec.(f3 * 100, f3 * 100 * 4 / 3), 1),
      beam: sec.(r.beam, r.beam * 1.25),
      # The clamp of a boat with D of 2.5 m or more: 15% more area (6.1).
      clamp: sec.(ct * 1.15, cw) |> then(fn {a, b} -> {b, a} end),
      shelf: sec.(st, sw) |> then(fn {a, b} -> {b, a} end),
      bilge_stringer: sec.(r.bilge_stringer, 20) |> then(fn {a, b} -> {b, a} end),
      side_stringer: sec.(r.side_stringer / 20, 20) |> then(fn {a, b} -> {b, a} end),
      plank: t.(r.plank),
      ceiling: t.(r.ceiling),
      deck: t.(r.deck),
      # The frame spacing: L + 20 cm or less (9.2), to the cm.
      spacing: Float.floor(l + 20) / 100
    }

    mm = fn v -> round(v * 1000) end

    list =
      for {k, v} <- s do
        {Atom.to_string(k), if(is_tuple(v), do: v |> Tuple.to_list() |> Enum.map(mm), else: mm.(v))}
      end

    Map.put(s, :list, list)
  end

  # --- The members ---------------------------------------------------------------------------

  # The keel: from the sternpost to the fore foot (s = 0.72), under the
  # planks.
  defp keel(h) do
    {w, kh} = {h.s.keel_w, h.s.keel_h}
    box = Shape.box({-w / 2, y_post(h), 0.0}, {w / 2, ys(h, 0.72), kh}, :wood) |> Mesh.matter(:sao)
    part("keel_ghe", :keel, [box], "The keel: #{mm(w)} by #{mm(kh)} mm (QCVN 91, Bảng 2/2-B).")
  end

  defp y_post(h), do: ys(h, 0.12)

  # The stem: up the bow, on the line of the rabbet, from the fore foot.
  defp stem(h) do
    a = h.s.stem

    line =
      for s <- [0.72, 0.78, 0.84, 0.9, 0.95, 1.0],
          do: {0.0, ys(h, s) - a / 2, max(h.zr + bottom(h, s) - h.s.keel_h * 0.3, h.s.keel_h / 2)}

    sweep = line |> Shape.sweep(a / :math.sqrt(2), :wood, sides: 4) |> Mesh.matter(:sao)
    part("stem_ghe", :stem, [sweep], "The stem: #{mm(a)} mm square (QCVN 91, Bảng 8/2-B).")
  end

  # The sternpost: up from the after end of the keel to the deck.
  defp sternpost(h) do
    a = h.s.stem
    y = y_post(h) + a / 2
    sweep = Shape.sweep([{0.0, y, h.s.keel_h / 2}, {0.0, y, h.zr + h.depth}], a / :math.sqrt(2), :wood, sides: 4)
    part("sternpost_ghe", :stem, [Mesh.matter(sweep, :sao)], "The sternpost: #{mm(a)} mm square (QCVN 91, Bảng 8/2-B).")
  end

  # A frame at each spacing, from the transom to the stem, with a floor
  # over the keel in the middle body (s from 0.12 to 0.72).
  defp framing(h) do
    sp = h.s.spacing

    frames =
      for {y, i} <- Enum.with_index(Stream.iterate(sp, &(&1 + sp)) |> Enum.take_while(&(&1 < ys(h, 0.93)))) do
        {"frame_#{i + 1}", frame(h, y / h.lmax, "frame_#{i + 1}"), [at: @o, port: @o]}
      end

    Assembly.new("framing", part("framing_mark", :mark, [], "The frames of the hull."), root: "mark")
    |> Assembly.add_all(frames)
  end

  defp frame(h, s, name) do
    {f1, f2, f3} = h.s.frame
    y = ys(h, s)
    inset = fn f -> h.s.plank + reach(f) end

    # The lower, middle and upper parts of the frame, each of its size.
    sides =
      for {from, to, f} <- [{1, 3, f3}, {3, 5, f2}, {5, @k - 1, f1}], sign <- [1, -1] do
        pts = section(h, s, inset.(f)) |> Enum.slice(from..to)

        pts
        |> Enum.map(fn {x, z} -> {sign * x, y, z} end)
        |> Shape.sweep(f / :math.sqrt(2), :wood, sides: 4)
        |> Mesh.matter(:sao)
      end

    floor =
      if s >= 0.12 and s <= 0.72 do
        {x, _} = section(h, s, inset.(f3)) |> Enum.at(2)
        [Shape.box({-x, y - f3 / 2, h.s.keel_h}, {x, y + f3 / 2, h.s.keel_h + h.s.floor_h}, :wood) |> Mesh.matter(:sao)]
      else
        []
      end

    part(
      name,
      :frame,
      sides ++ floor,
      "A single frame (sườn đơn): #{mm(f3)}, #{mm(f2)} and #{mm(f1)} mm square at the bottom, the bilge and the deck (QCVN 91, Bảng 9/2-B)."
    )
  end

  # The keelson: on the floors, from s = 0.14 to 0.70.
  defp keelson(h) do
    a = h.s.keelson
    z = h.s.keel_h + h.s.floor_h
    box = Shape.box({-a / 2, ys(h, 0.14), z}, {a / 2, ys(h, 0.7), z + a}, :wood) |> Mesh.matter(:sao)
    part("keelson_ghe", :keelson, [box], "The keelson: #{mm(a)} mm square (QCVN 91, Bảng 2/2-B).")
  end

  # Three bilge stringers (at the points 3 to 5 of a section) and a side
  # stringer (at the point 6), on the inside of the frames, from s = 0.1
  # to 0.9.
  defp stringers(h) do
    {f1, f2, _} = h.s.frame
    {bt, st} = {board(h.s.bilge_stringer), board(h.s.side_stringer)}
    ss = for j <- 0..16, do: 0.1 + 0.8 * j / 16

    meshes =
      for {i, f, t} <- [{3, f2, bt}, {4, f2, bt}, {5, f2, bt}, {6, f1, st}], sign <- [1, -1] do
        ss
        |> Enum.map(fn s ->
          {x, z} = section(h, s, h.s.plank + 2 * reach(f) + reach(t)) |> Enum.at(i)
          {sign * x, ys(h, s), z}
        end)
        |> Shape.sweep(t / :math.sqrt(2), :wood, sides: 4)
        |> Mesh.matter(:sao)
      end

    [{bw, bth}, {sw, sth}] = [h.s.bilge_stringer, h.s.side_stringer]

    part(
      "stringers_ghe",
      :stringer,
      meshes,
      "Three bilge stringers (#{mm(bw)} by #{mm(bth)} mm) and a side stringer (#{mm(sw)} by #{mm(sth)} mm) on each side (QCVN 91, Bảng 5/2-B, 6/2-B); each a square of the same area."
    )
  end

  # The deck beams on each second frame, under the deck, with the clamp
  # under their ends and the shelf over them.
  defp deck_frame(h) do
    {bt, bh} = h.s.beam
    sp = 2 * h.s.spacing

    beams =
      for y <- Stream.iterate(sp, &(&1 + sp)) |> Enum.take_while(&(&1 < ys(h, 0.9))) do
        s = y / h.lmax
        {x, z} = section(h, s, h.s.plank + 2 * reach(elem(h.s.frame, 0))) |> List.last()
        Shape.box({-x, y - bt / 2, z - h.s.deck - bh}, {x, y + bt / 2, z - h.s.deck}, :wood) |> Mesh.matter(:sao)
      end

    {cw, ct} = h.s.clamp
    c = board(h.s.clamp)
    ss = for j <- 0..16, do: 0.06 + 0.86 * j / 16

    clamps =
      for sign <- [1, -1] do
        ss
        |> Enum.map(fn s ->
          {x, z} = section(h, s, h.s.plank + 2 * reach(elem(h.s.frame, 0)) + reach(c)) |> List.last()
          {sign * x, ys(h, s), z - h.s.deck - bh - reach(c)}
        end)
        |> Shape.sweep(c / :math.sqrt(2), :wood, sides: 4)
        |> Mesh.matter(:sao)
      end

    part(
      "deck_frame_ghe",
      :beam,
      beams ++ clamps,
      "The deck beams (#{mm(bt)} by #{mm(bh)} mm, QCVN 91, Bảng 10/2-B) on each second frame, and the clamps (#{mm(cw)} by #{mm(ct)} mm, Bảng 7/2-B)."
    )
  end

  # The planks of the hull, a slab of their thickness from the outside of
  # the hull to the inside, and the transom.
  defp planks(h) do
    t = h.s.plank
    ring = fn s, inset -> ring(section(h, s, inset), ys(h, s)) end

    hull =
      slab(for(s <- stations(), do: ring.(s, 0.0)), for(s <- stations(), do: ring.(s, t)), :paint) |> Mesh.matter(:sao)

    # The transom: the section at the stern, closed at the deck, t thick.
    loop = section(h, 0.0, 0.0)
    loop = Enum.reverse(loop) ++ Enum.map(loop, fn {x, z} -> {-x, z} end)

    transom =
      Shape.prism(loop, t, :paint, frame: World.Frame.new({0.0, 0.0, 0.0}, {0, 1, 0}, {0, 0, 1})) |> Mesh.matter(:sao)

    part(
      "planks_ghe",
      :planks,
      [hull, transom],
      "The planks of the hull: #{mm(t)} mm (QCVN 91, Bảng 14/2-B); the lines by eye."
    )
  end

  # A ring of a section: the starboard half from the sheer to the keel,
  # then the port half to the sheer. An inner point keeps to its side.
  defp ring(half, y) do
    half = Enum.map(half, fn {x, z} -> {max(x, 0.005), z} end)
    Enum.map(Enum.reverse(half), fn {x, z} -> {x, y, z} end) ++ Enum.map(half, fn {x, z} -> {-x, y, z} end)
  end

  # The deck (with a camber of B/50), and the bulwark of 0.8 m (by eye).
  defp deck(h) do
    {camber, t} = {h.bmax / 50, h.s.deck}

    grid = fn down ->
      for s <- stations() do
        {x, z} = section(h, s, h.s.plank) |> List.last()
        for u <- [-1.0, -0.5, 0.0, 0.5, 1.0], do: {u * x, ys(h, s), z + camber * (1 - u * u) - down}
      end
    end

    deck = slab(grid.(0.0), grid.(t), :wood) |> Mesh.matter(:sao)

    bulwarks =
      for sign <- [1, -1] do
        grid = fn inset ->
          for s <- Enum.drop(stations(), 1) do
            {x, z} = section(h, s, inset) |> List.last()
            ring = [{sign * x, ys(h, s), z + 0.8}, {sign * x, ys(h, s), z}]
            if sign > 0, do: ring, else: Enum.reverse(ring)
          end
        end

        slab(grid.(0.0), grid.(0.04), :paint) |> Mesh.matter(:sao)
      end

    part(
      "deck_ghe",
      :deck,
      [deck | bulwarks],
      "The deck: #{mm(t)} mm (QCVN 91, Bảng 14/2-B); the bulwark of 40 mm and 0.8 m, by eye."
    )
  end

  # The wheelhouse: on the deck from s = 0.1 to 0.3, of plywood (by eye).
  defp wheelhouse(h) do
    {x, z} = section(h, 0.2, h.s.plank) |> List.last()
    {y0, y1} = {ys(h, 0.1), ys(h, 0.3)}
    z0 = z + h.bmax / 50

    walls = Shape.box({-0.7 * x, y0, z0}, {0.7 * x, y1, z0 + 2.1}, :white) |> Mesh.skin(0.02, :plywood)

    roof =
      Shape.box({-0.8 * x, y0 - 0.3, z0 + 2.1}, {0.8 * x, y1 + 0.3, z0 + 2.16}, :white) |> Mesh.skin(0.02, :plywood)

    part("wheelhouse_ghe", :cabin, [walls, roof], "The wheelhouse: plywood, its size by eye.")
  end

  # The rudder: a blade behind the sternpost, and its stock up to the
  # deck. It turns around the stock (+-35 degrees).
  defp rudder(h) do
    a = h.s.stem
    blade = Shape.box({-0.045, -1.1, 0.15}, {0.045, -0.05, 0.15 + 0.4 * h.depth}, :wood) |> Mesh.matter(:sao)

    stock =
      Shape.sweep([{0.0, 0.0, 0.15}, {0.0, 0.0, h.zr + h.depth}], a / :math.sqrt(2), :wood, sides: 4)
      |> Mesh.matter(:sao)

    Part.new("rudder_ghe", :rudder, [blade, stock], [Part.port("stock", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})],
      sources: ["The rudder: its stock of wood, as the stem (QCVN 91, Bảng 8/2-B, trục bánh lái); the blade by eye."]
    )
  end

  # A member of a square section a is a sweep of 4 sides: its corners
  # reach a/sqrt(2) from its line.
  defp reach(a), do: a / :math.sqrt(2)

  # The side of a square of the area of a board.
  defp board({w, t}), do: :math.sqrt(w * t)

  # --- The meshes ------------------------------------------------------------------------------

  # A slab between two grids of points (rings of the same count): the
  # outer face (its quads look out), the inner face, and the faces of its
  # four edges, so the mesh is closed.
  defp slab(outer, inner, material) do
    {m, n} = {length(outer), length(hd(outer))}
    o = fn j, i -> j * n + i end
    q = fn j, i -> m * n + j * n + i end

    faces =
      for(j <- 0..(m - 2), i <- 0..(n - 2), do: [o.(j, i), o.(j, i + 1), o.(j + 1, i + 1), o.(j + 1, i)]) ++
        for(j <- 0..(m - 2), i <- 0..(n - 2), do: [q.(j, i), q.(j + 1, i), q.(j + 1, i + 1), q.(j, i + 1)]) ++
        for(j <- 0..(m - 2), do: [o.(j, 0), o.(j + 1, 0), q.(j + 1, 0), q.(j, 0)]) ++
        for(j <- 0..(m - 2), do: [o.(j + 1, n - 1), o.(j, n - 1), q.(j, n - 1), q.(j + 1, n - 1)]) ++
        for(i <- 0..(n - 2), do: [o.(0, i + 1), o.(0, i), q.(0, i), q.(0, i + 1)]) ++
        for i <- 0..(n - 2), do: [o.(m - 1, i), o.(m - 1, i + 1), q.(m - 1, i + 1), q.(m - 1, i)]

    points = List.flatten(outer) ++ List.flatten(inner)
    Mesh.new(points, Mesh.outside(Enum.map(points, &World.Vec.float/1), faces), material)
  end

  # A member inside the hull is only at the near level; the keel, the
  # stem, the planks, the deck and the wheelhouse show at each level.
  @outside [:keel, :stem, :planks, :deck, :cabin, :mark]
  defp part(name, kind, shapes, source),
    do: Part.new(name, kind, shapes, [@o], sources: [source], detail: if(kind in @outside, do: nil, else: :near))

  defp mm(v), do: round(v * 1000)
end
