defmodule World.SDFTest do
  # Fields of distances and the edits of a sculpture (plan 0008, D1, D2;
  # R1).
  use ExUnit.Case, async: true

  alias World.{Frame, SDF, Vec}

  # Random points in a box, the same at each run.
  defp points(n, size, seed) do
    :rand.seed(:exsss, {seed, seed, seed})
    for _ <- 1..n, do: {(:rand.uniform() - 0.5) * size, (:rand.uniform() - 0.5) * size, (:rand.uniform() - 0.5) * size}
  end

  # Points on the surface of a shape that each ray from its center
  # crosses once: by bisection of the field along rays.
  defp surface(edit, n) do
    :rand.seed(:exsss, {7, 7, 7})

    for _ <- 1..n do
      dir = Vec.norm({:rand.normal(), :rand.normal(), :rand.normal()})
      bisect(edit, dir, 0.0, 10.0, 60)
    end
  end

  defp bisect(_edit, dir, lo, hi, 0), do: Vec.scale(dir, (lo + hi) / 2)

  defp bisect(edit, dir, lo, hi, k) do
    mid = (lo + hi) / 2

    if SDF.distance(edit, Vec.scale(dir, mid)) < 0,
      do: bisect(edit, dir, mid, hi, k - 1),
      else: bisect(edit, dir, lo, mid, k - 1)
  end

  defp nearest(samples, p), do: samples |> Enum.map(&Vec.len(Vec.sub(&1, p))) |> Enum.min()

  @exact [
    {:ball, {0.6}},
    {:box, {0.5, 0.3, 0.2}},
    {:round_box, {0.5, 0.4, 0.3, 0.1}},
    {:capsule, {0.4, 0.2}},
    {:cylinder, {0.3, 0.5}},
    {:cone, {0.5, 0.2, 0.4}}
  ]

  test "each exact shape: less than 0 inside, 0 on its surface, and the distance to its surface outside" do
    for {shape, size} <- @exact do
      e = SDF.edit(shape, size)
      samples = surface(e, 6_000)
      assert SDF.distance(e, {0.0, 0.0, 0.0}) < 0, inspect(shape)
      for s <- Enum.take(samples, 50), do: assert(abs(SDF.distance(e, s)) < 1.0e-9, inspect({shape, s}))

      for p <- points(200, 3.0, 1), (d = SDF.distance(e, p)) > 0.05 do
        # The samples are some cm apart: the true distance is within it.
        assert_in_delta d, nearest(samples, p), 0.03, inspect({shape, p})
      end
    end
  end

  test "the ring and the tube: exact, from the points of their surfaces" do
    ring = SDF.edit(:ring, {0.5, 0.15})

    samples =
      for u <- 0..199,
          v <- 0..39,
          a = u * 2 * :math.pi() / 200,
          b = v * 2 * :math.pi() / 40,
          do:
            {(0.5 + 0.15 * :math.cos(b)) * :math.cos(a), (0.5 + 0.15 * :math.cos(b)) * :math.sin(a),
             0.15 * :math.sin(b)}

    assert SDF.distance(ring, {0.65, 0.0, 0.0}) |> abs() < 1.0e-12
    assert SDF.distance(ring, {0.5, 0.0, 0.0}) == -0.15
    for p <- points(100, 2.0, 2), d = SDF.distance(ring, p), d > 0.05, do: assert_in_delta(d, nearest(samples, p), 0.02)

    # A tube of one radius is the union of its capsules; of one point, a ball.
    tube = SDF.edit(:tube, {[{0, 0, 0}, {0, 0, 1}, {1, 0, 1}], [0.2, 0.2, 0.2]})
    a = SDF.edit(:capsule, {0.5, 0.2}, frame: Frame.move({0, 0, 0.5}))

    # A turn of 90° round y puts the axis of the capsule along x; a move puts it at x = 0.5, z = 1.
    b = SDF.edit(:capsule, {0.5, 0.2}, frame: Frame.compose(Frame.move({0.5, 0, 1}), Frame.turn({0, 1, 0}, 90)))

    for p <- points(200, 3.0, 3) do
      assert_in_delta SDF.distance(tube, p), min(SDF.distance(a, p), SDF.distance(b, p)), 1.0e-9
    end

    ball = SDF.edit(:tube, {[{1, 2, 3}], [0.5]})
    assert_in_delta SDF.distance(ball, {1, 2, 4}), 0.5, 1.0e-12
    # A cone with round ends: its ends are balls of their radii.
    cone = SDF.edit(:tube, {[{0, 0, 0}, {0, 0, 1}], [0.4, 0.1]})
    assert_in_delta SDF.distance(cone, {0, 0, -0.4}), 0.0, 1.0e-9
    assert_in_delta SDF.distance(cone, {0, 0, 1.1}), 0.0, 1.0e-9
  end

  test "the ellipsoid and the superellipsoid: a bound, never more than the distance, and near it at the surface" do
    for {shape, size} <- [
          {:ellipsoid, {0.6, 0.3, 0.2}},
          {:superellipsoid, {0.5, 0.4, 0.3, 4.0}},
          {:superellipsoid, {0.4, 0.4, 0.4, 2.0}}
        ] do
      e = SDF.edit(shape, size)
      samples = surface(e, 8_000)
      assert SDF.distance(e, {0.0, 0.0, 0.0}) < 0
      for s <- Enum.take(samples, 50), do: assert(abs(SDF.distance(e, s)) < 1.0e-9)

      for p <- points(300, 3.0, 4), (d = SDF.distance(e, p)) > 0 do
        truth = nearest(samples, p)
        assert d <= truth + 0.01, inspect({shape, p, d, truth})
      end
    end

    # The superellipsoid of the power 2 is the ball.
    s = SDF.edit(:superellipsoid, {0.4, 0.4, 0.4, 2.0})
    for p <- points(50, 2.0, 5), do: assert_in_delta(SDF.distance(s, p), Vec.len(p) - 0.4, 1.0e-12)
    # At the center of the ellipsoid: its least radius inside.
    assert SDF.distance(SDF.edit(:ellipsoid, {0.6, 0.3, 0.2}), {0, 0, 0}) == -0.2
  end

  test "an ellipsoid: the true distance outside, and a slope of at most 1 at each place (the ranges of the cells need it)" do
    # A ball, and a point on an axis: the distance as it is.
    assert_in_delta SDF.distance(SDF.edit(:ellipsoid, {0.3, 0.3, 0.3}), {0.5, 0.4, 0.1}), :math.sqrt(0.42) - 0.3, 1.0e-9
    thin = SDF.edit(:ellipsoid, {0.0035, 0.09, 0.026})
    assert_in_delta SDF.distance(thin, {0.0, 0.2, 0.0}), 0.11, 1.0e-9
    assert_in_delta SDF.distance(thin, {0.01, 0.0, 0.0}), 0.0065, 1.0e-9
    # Next to the long axis the distance is the same (the short formula gave a small part of it).
    assert_in_delta SDF.distance(thin, {1.0e-5, 0.2, 0.0}), 0.11, 1.0e-6

    # A point off the axes: the least distance to many points of the surface.
    wide = SDF.edit(:ellipsoid, {0.4, 0.1, 0.2})
    p = {0.3, 0.25, -0.2}

    near =
      for i <- 0..400, j <- 0..400, a = :math.pi() * i / 400, b = 2 * :math.pi() * j / 400, reduce: 1.0e9 do
        best ->
          q = {0.4 * :math.sin(a) * :math.cos(b), 0.1 * :math.sin(a) * :math.sin(b), 0.2 * :math.cos(a)}
          min(best, Vec.len(Vec.sub(p, q)))
      end

    assert_in_delta SDF.distance(wide, p), near, 1.0e-4

    # The slope between two points, inside, outside and across the surface, near the middle planes too.
    :rand.seed(:exsss, {7, 7, 7})
    u = fn lo, hi -> lo + (hi - lo) * :rand.uniform() end

    for _ <- 1..2_000 do
      {rx, ry, rz} = {:math.exp(u.(-5.8, -1.2)), :math.exp(u.(-5.8, -1.2)), :math.exp(u.(-5.8, -1.2))}
      e = SDF.edit(:ellipsoid, {rx, ry, rz})
      flat = if :rand.uniform() < 0.3, do: 1.0e-4, else: 1.0
      p = {u.(-3, 3) * rx * flat, u.(-3, 3) * ry, u.(-3, 3) * rz}
      far = Enum.min([rx, ry, rz]) * :math.pow(10, u.(-3, 0.5))
      q = Vec.add(p, {u.(-1, 1) * far, u.(-1, 1) * far, u.(-1, 1) * far})
      assert abs(SDF.distance(e, p) - SDF.distance(e, q)) <= Vec.len(Vec.sub(p, q)) * (1 + 1.0e-6) + 1.0e-12
    end
  end

  test "the blend: the minimum when the values are the blend apart, and at most a quarter of the blend less" do
    assert SDF.smin(0.3, 0.7, 0.0) == 0.3 and SDF.smin(0.3, 0.7, 0.4) == 0.3
    assert SDF.smax(0.3, 0.7, 0.4) == 0.7

    for {a, b} <- [{0.0, 0.0}, {0.1, 0.2}, {-0.3, -0.25}, {1.0, 1.1}], r <- [0.1, 0.5] do
      s = SDF.smin(a, b, r)
      assert s <= min(a, b) and min(a, b) - s <= r / 4 + 1.0e-15 and s == SDF.smin(b, a, r)
    end

    assert_in_delta SDF.smin(0.0, 0.0, 0.4), -0.1, 1.0e-15
  end

  defp sculpture do
    turn = Frame.turn({1, 1, 0}, 35, {0.2, 0.1, 0.0})

    [
      SDF.edit(:box, {0.5, 0.4, 0.3}, material: :stone),
      SDF.edit(:ball, {0.35}, frame: Frame.move({0.5, 0.0, 0.3}), blend: 0.2, material: :clay),
      SDF.edit(:cylinder, {0.15, 0.6}, frame: turn, mode: :subtract, blend: 0.05),
      SDF.edit(:ellipsoid, {0.4, 0.2, 0.1}, frame: Frame.move({-0.5, 0.3, 0.3}), blend: 0.1),
      SDF.edit(:ring, {0.3, 0.05}, frame: Frame.move({0.0, 0.0, 0.35}), blend: 0.03),
      SDF.edit(:ball, {0.2}, frame: Frame.move({0.5, 0.0, 0.3}), mode: :paint, material: :gold)
    ]
  end

  test "the field of a sculpture changes by at most the distance between two points, so it is a bound" do
    edits = sculpture()
    ps = points(400, 2.5, 6)
    qs = points(400, 2.5, 7)

    for {p, q} <- Enum.zip(ps, qs) do
      assert abs(SDF.value(edits, p) - SDF.value(edits, q)) <= Vec.len(Vec.sub(p, q)) * (1 + 1.0e-9)
    end

    # Near points too, where the blends bend the field.
    for p <- ps, d <- [{1.0e-3, 0, 0}, {0, 1.0e-3, 0}, {0, 0, 1.0e-3}] do
      assert abs(SDF.value(edits, p) - SDF.value(edits, Vec.add(p, d))) <= 1.0e-3 * (1 + 1.0e-6)
    end
  end

  test "a cell keeps the edits that can change the field in it, and the field of those is the field of all at each point of it" do
    edits = sculpture()
    :rand.seed(:exsss, {9, 9, 9})

    counts =
      for _ <- 1..400 do
        c = {(:rand.uniform() - 0.5) * 2.5, (:rand.uniform() - 0.5) * 2.5, (:rand.uniform() - 0.5) * 2.5}
        half = 0.01 + :rand.uniform() * 0.4
        kept = SDF.prune(edits, c, half)

        for _ <- 1..20 do
          dir = Vec.norm({:rand.normal(), :rand.normal(), :rand.normal()})
          p = Vec.add(c, Vec.scale(dir, :rand.uniform() * half))
          assert SDF.field(kept, p) == SDF.field(edits, p)
        end

        length(kept)
      end

    # The small cells far from the edits keep few of them.
    assert Enum.sum(counts) / length(counts) < 0.6 * length(edits)
    assert SDF.prune(edits, {5.0, 5.0, 5.0}, 0.1) |> Enum.all?(&(&1.mode == :add))
    # A cut or a paint of nothing goes.
    assert SDF.prune([SDF.edit(:ball, {1}, mode: :subtract), SDF.edit(:ball, {1}, mode: :paint)], {0, 0, 0}, 0.1) == [
             SDF.edit(:ball, {1}, mode: :paint)
           ]
  end

  test "the hot loop of the value gives the same values as the fold, to the bit, for each shape, frame and mode (plan 0010, R13)" do
    :rand.seed(:exsss, {5, 6, 7})
    u = fn lo, hi -> lo + (hi - lo) * :rand.uniform() end

    frame = fn turn? ->
      at = {u.(-0.6, 0.6), u.(-0.6, 0.6), u.(-0.6, 0.6)}

      if turn?,
        do: Frame.new(at, Vec.norm({u.(-1, 1), u.(-1, 1), u.(0.2, 1)}), Vec.norm({u.(-1, 1), u.(0.2, 1), 0.0})),
        else: Frame.move(at)
    end

    size = fn
      :ball -> {u.(0.05, 0.3)}
      :box -> {u.(0.05, 0.3), u.(0.05, 0.3), u.(0.05, 0.3)}
      :round_box -> {u.(0.1, 0.3), u.(0.1, 0.3), u.(0.1, 0.3), u.(0.01, 0.08)}
      :capsule -> {u.(0.05, 0.3), u.(0.03, 0.15)}
      :cylinder -> {u.(0.05, 0.2), u.(0.05, 0.3)}
      :ellipsoid -> {u.(0.05, 0.3), u.(0.05, 0.3), u.(0.05, 0.3)}
      :cone -> {u.(0.05, 0.2), u.(0.0, 0.1), u.(0.05, 0.3)}
      :ring -> {u.(0.1, 0.3), u.(0.02, 0.08)}
      :superellipsoid -> {u.(0.05, 0.3), u.(0.05, 0.3), u.(0.05, 0.3), 4.0}
      :tube -> {[{0.0, 0.0, 0.0}, {0.2, 0.1, 0.0}, {0.3, 0.3, 0.1}], [0.05, 0.03, 0.02]}
    end

    edits =
      for shape <- SDF.shapes(), turn? <- [false, true], mode <- SDF.modes(), blend <- [0.0, u.(0.02, 0.1)] do
        raise = if mode == :paint, do: [raise: u.(-0.03, 0.03)], else: []
        SDF.edit(shape, size.(shape), [frame: frame.(turn?), mode: mode, blend: blend] ++ raise)
      end

    # A paint with no raise is not in the list of the value.
    plain = SDF.edit(:ball, {0.2}, mode: :paint, color: {1, 2, 3})
    assert {:fast, list} = SDF.fast(edits ++ [plain])
    assert length(list) == length(edits) and length(edits) == 10 * 2 * 3 * 2
    points = for _ <- 1..2_000, do: {u.(-1, 1), u.(-1, 1), u.(-1, 1)}

    # All the edits in their order, and each edit after one ball (each clause of the loop, on the two sides of 0).
    ball = SDF.edit(:ball, {0.4})
    lists = [edits ++ [plain] | for(e <- edits, do: [ball, e])]

    for list <- lists,
        fast = SDF.fast(list),
        limit <- [1.0e30, 0.2],
        p <- Enum.take(points, if(length(list) > 2, do: 2_000, else: 60)) do
      assert SDF.value(fast, p, limit) == SDF.value(list, p, limit)
    end

    # A point with whole numbers, and no edit.
    assert SDF.value(SDF.fast([ball]), {1, 0, 0}, 5) == SDF.value([ball], {1, 0, 0}, 5)
    assert SDF.value(SDF.fast([]), {0.0, 0.0, 0.0}, 0.3) == 0.3
  end

  test "the parts of the hot loop are the steps of the functions of the field" do
    require World.SDF.Inline, as: Inline
    :rand.seed(:exsss, {8, 8, 8})

    for _ <- 1..500 do
      [d, de, k, limit, h] = for _ <- 1..5, do: :rand.uniform() - 0.3
      k = if k < 0.1, do: 0.0, else: k
      limit = abs(limit) + 0.05
      clamp = fn v -> min(max(v, -limit), limit) end
      assert Inline.blend(:add, d, de, k, limit) == clamp.(SDF.smin(d, de, k))
      assert Inline.blend(:subtract, d, de, k, limit) == clamp.(SDF.smax(d, -de, k))
      assert Inline.clamp(d * 3, limit) == clamp.(d * 3)
      assert Inline.positive(d) == max(d, 0.0)
      least = min(d, de)
      assert Inline.soft(least, d, de, k) == SDF.smin(d, de, k)
      # A paint with a raise: the field of a ball with the paint of a box at a point.
      paint = SDF.edit(:box, {0.2, 0.2, 0.2}, mode: :paint, blend: k, raise: h)
      p = {de, d, 0.1}
      value = SDF.value([SDF.edit(:ball, {0.3}), paint], p, limit)
      assert Inline.lift(SDF.value([SDF.edit(:ball, {0.3})], p, limit), SDF.distance(paint, p), k, h, limit) == value
    end

    # The root of the nearest point of an ellipsoid: no step, and the steps of the distance.
    assert Inline.root(0.25, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0) == 0.25
    {rx, ry, rz} = {0.3, 0.1, 0.2}
    {x, y, z} = {0.5, 0.4, -0.3}
    {ux, uy, uz, sx, sy, sz} = {rx * x, ry * y, rz * abs(z), rx * rx, ry * ry, rz * rz}
    t = Inline.root(Enum.max([ux - sx, uy - sy, uz - sz, 0.0]), ux, uy, uz, sx, sy, sz, 8)
    {dx, dy, dz} = {x * t / (sx + t), y * t / (sy + t), z * t / (sz + t)}
    assert :math.sqrt(dx * dx + dy * dy + dz * dz) == SDF.distance(SDF.edit(:ellipsoid, {rx, ry, rz}), {x, y, z})
  end

  test "the shares of the edits in the surface at a point: one edit away from a joint, two across a smooth joint" do
    a = SDF.edit(:ball, {0.5})
    b = SDF.edit(:ball, {0.3}, frame: Frame.move({0.6, 0.0, 0.0}), blend: 0.1)
    cut = SDF.edit(:cylinder, {0.1, 1.0}, mode: :subtract)
    paint = SDF.edit(:ball, {0.2}, frame: Frame.move({-0.5, 0.0, 0.0}), mode: :paint, color: {1, 2, 3})
    edits = [a, b, cut, paint]
    # On the first ball, far from the second one (a paint and a cut have no share).
    assert SDF.shares(edits, {-0.5, 0.0, 0.0}) == [{a, 1.0}]
    assert SDF.shares(edits, {0.9, 0.0, 0.0}) == [{b, 1.0}]
    # In the joint of the two balls: a share of each, and the shares add to 1.
    assert [{^b, sb}, {^a, sa}] = SDF.shares(edits, {0.42, 0.0, 0.27})
    assert sa > 0.05 and sb > 0.05
    assert_in_delta sa + sb, 1.0, 1.0e-12
    assert SDF.shares([cut, paint], {0.0, 0.0, 0.0}) == []
  end

  test "a paint with a raise moves the surface in its shape, out or in, with a slope across its border" do
    ball = SDF.edit(:ball, {0.5})
    bump = SDF.edit(:ball, {0.1}, frame: Frame.move({0.0, 0.0, 0.5}), mode: :paint, blend: 0.04, raise: 0.02)

    dent =
      SDF.edit(:ball, {0.1},
        frame: Frame.move({0.5, 0.0, 0.0}),
        mode: :paint,
        blend: 0.04,
        raise: -0.02,
        color: {9, 9, 9}
      )

    edits = [ball, bump, dent]
    # In the shape of the paint the surface is 2 cm out (or in); away from it, where it was.
    assert_in_delta SDF.value(edits, {0.0, 0.0, 0.52}), 0.0, 1.0e-12
    assert_in_delta SDF.value(edits, {0.48, 0.0, 0.0}), 0.0, 1.0e-12
    assert_in_delta SDF.value(edits, {0.0, 0.5, 0.0}), 0.0, 1.0e-12
    # Across the border of the paint (4 cm wide): between the two.
    edge = Vec.scale(Vec.norm({0.0, 0.1, 0.49}), 0.51)
    assert SDF.value(edits, edge) > -0.01 and SDF.value(edits, edge) < 0.01 and SDF.value(edits, edge) != 0.01
    # The three folds agree.
    for p <- points(200, 0.7, 11) do
      assert {d, _} = SDF.field(edits, p)
      assert_in_delta d, SDF.value(edits, p), 1.0e-12
      assert_in_delta elem(SDF.sample(edits, p), 0), d, 1.0e-12
    end

    assert SDF.color(edits, {0.48, 0.0, 0.0}) == {9, 9, 9}
    assert_in_delta SDF.relief(edits), 0.04, 1.0e-12
    assert SDF.relief([ball]) == 0.0
    # The bounds hold the surface that a raise moves out.
    assert {_, {_, _, top}} = SDF.bounds(edits)
    assert top >= 0.52
    assert_raise ArgumentError, fn -> SDF.edit(:ball, {0.1}, raise: 0.01) end

    # For a mesh with maps: a raise of less than half a cell is not in the mesh (a new edit, with its own id).
    assert SDF.coarse(edits, 0.03) == edits
    assert [^ball, flat, flat_dent] = SDF.coarse(edits, 0.05)
    assert flat.raise == 0.0 and flat.id != bump.id and flat_dent.color == dent.color
    assert flat == SDF.edit(:ball, {0.1}, frame: Frame.move({0.0, 0.0, 0.5}), mode: :paint, blend: 0.04)

    # A cell keeps the paints with a raise that reach it, and the field of those is the field of all.
    :rand.seed(:exsss, {4, 4, 4})

    for _ <- 1..300 do
      c = {(:rand.uniform() - 0.5) * 1.4, (:rand.uniform() - 0.5) * 1.4, (:rand.uniform() - 0.5) * 1.4}
      half = 0.01 + :rand.uniform() * 0.2
      {kept, {lo, hi}} = SDF.cell(edits, c, half)

      for _ <- 1..20 do
        dir = Vec.norm({:rand.normal(), :rand.normal(), :rand.normal()})
        p = Vec.add(c, Vec.scale(dir, :rand.uniform() * half))
        assert SDF.field(kept, p) == SDF.field(edits, p)
        # The range of the cell holds the value at each of its points.
        assert SDF.value(edits, p) >= lo - 1.0e-12 and SDF.value(edits, p) <= hi + 1.0e-12
      end
    end
  end

  test "the bounds of a sculpture hold its inside: the boxes of its shapes that add, grown by a quarter of its blends" do
    edits = sculpture()
    bounds = SDF.bounds(edits)
    for p <- points(4_000, 3.0, 8), SDF.value(edits, p) < 0, do: assert(inside?(bounds, p))
    assert SDF.bounds([]) == nil and SDF.bounds([SDF.edit(:ball, {1}, mode: :subtract)]) == nil
    assert SDF.bounds([SDF.edit(:ball, {1}, blend: 0.4)]) == {{-1.1, -1.1, -1.1}, {1.1, 1.1, 1.1}}
  end

  defp inside?({{a, b, c}, {d, e, f}}, {x, y, z}), do: x >= a and x <= d and y >= b and y <= e and z >= c and z <= f

  test "the modes: a cut takes away, paint changes the material only; the material of the nearer edit" do
    box = SDF.edit(:box, {0.5, 0.5, 0.5}, material: :stone)
    hole = SDF.edit(:cylinder, {0.2, 1.0}, mode: :subtract, material: :rust)
    assert SDF.value([box], {0, 0, 0}) < 0
    assert SDF.value([box, hole], {0, 0, 0}) > 0
    # The wall of the hole has the material of the cut; the rest of the box, stone.
    assert {_, :rust} = SDF.field([box, hole], {0.2, 0, 0})
    assert {_, :stone} = SDF.field([box, hole], {0.5, 0.4, 0})
    assert {_, :stone} = SDF.field([box, SDF.edit(:cylinder, {0.2, 1.0}, mode: :subtract)], {0.2, 0, 0})
    # Paint: the same field, the material in its shape.
    paint = SDF.edit(:ball, {0.3}, frame: Frame.move({0.5, 0, 0}), mode: :paint, material: :gold)
    assert SDF.value([box, paint], {0.5, 0, 0}) == SDF.value([box], {0.5, 0, 0})
    assert {_, :gold} = SDF.field([box, paint], {0.5, 0, 0})
    assert {_, :stone} = SDF.field([box, paint], {-0.5, 0, 0})
    # No edit: far outside; a cut of nothing is nothing.
    assert SDF.field([], {0, 0, 0}) == {1.0e30, nil}
    assert SDF.value([hole], {0, 0, 0}) >= 1.0e30
    assert SDF.shapes() |> length() == 10 and SDF.modes() == [:add, :subtract, :paint]
    assert_raise ArgumentError, ~r/the mode of an edit/, fn -> SDF.edit(:ball, {1}, mode: :melt) end
  end
end
