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

  test "a long tube and a long outline in a ball: only their parts near the ball, and the same field (focus)" do
    # A tube of 60 cones along a wave, an outline of 48 sides (a star), and a profile of 40 sides (a vase).
    wave = for i <- 0..60, do: {i * 0.1 - 3.0, 0.4 * :math.sin(i * 0.3), 0.3 * :math.cos(i * 0.2)}
    tube = SDF.edit(:tube, {wave, for(i <- 0..60, do: 0.15 + 0.1 * :math.sin(i * 0.5))}, mode: :subtract)

    star =
      for i <- 0..47,
          a = i * :math.pi() / 24,
          r = if(rem(i, 2) == 0, do: 1.0, else: 0.7),
          do: {r * :math.cos(a), r * :math.sin(a)}

    extrude = SDF.edit(:extrude, {star, 0.3, 0.02}, frame: Frame.turn({1, 0, 0}, 30))

    vase =
      for(i <- 0..19, do: {0.3 + 0.15 * :math.sin(i * 0.6), i * 0.1 - 1.0}) ++
        for(i <- 19..0//-1, do: {0.2 + 0.15 * :math.sin(i * 0.6), i * 0.1 - 1.0})

    revolve = SDF.edit(:revolve, {vase})
    # (A profile with a side on the axis: that side is not a side of the shape.)
    solid = SDF.edit(:revolve, {[{0, -1}, {0.4, -1}, {0.6, 0}, {0.4, 1}, {0, 1}]}, mode: :crop)
    edits = [extrude, revolve, tube, solid]

    count = fn %{parts: parts} ->
      if is_list(parts), do: length(parts), else: length(elem(parts, 1)) + length(elem(parts, 2))
    end

    :rand.seed(:exsss, {4, 5, 6})

    kept =
      for _ <- 1..300 do
        c = {(:rand.uniform() - 0.5) * 3.0, (:rand.uniform() - 0.5) * 3.0, (:rand.uniform() - 0.5) * 3.0}
        half = 0.02 + :rand.uniform() * 0.3
        near = SDF.focus(edits, c, half)
        # The edits are the same edits, with fewer parts.
        assert SDF.ids(near) == SDF.ids(edits)

        for _ <- 1..20 do
          dir = Vec.norm({:rand.normal(), :rand.normal(), :rand.normal()})
          p = Vec.add(c, Vec.scale(dir, :rand.uniform() * half))
          for {e, n} <- Enum.zip(edits, near), do: assert(SDF.distance(n, p) == SDF.distance(e, p))
          assert SDF.field(near, p) == SDF.field(edits, p)
          # The short list of a cell has the edits with their parts near the cell, and the hot loop reads them.
          short = SDF.prune(edits, c, half)
          assert SDF.value(short, p) == SDF.value(edits, p)
          assert SDF.value(SDF.fast(short), p) == SDF.value(edits, p)
        end

        Enum.map(near, count)
      end

    # A ball keeps a part of the parts in the mean, and a small ball at the shape keeps few of them.
    for {e, i} <- Enum.with_index(edits) do
      mean = Enum.sum(Enum.map(kept, &Enum.at(&1, i))) / length(kept)
      assert mean < 0.3 * count.(e) or e == solid
    end

    assert [%{parts: cones}] = SDF.focus([tube], {0.0, 0.2, 0.3}, 0.02)
    assert length(cones) <= 4
    assert [%{parts: {_, sides, cross}}] = SDF.focus([extrude], {1.0, 0.0, 0.0}, 0.02)
    assert length(sides) <= 4 and length(cross) <= 4

    # A ball at the left of a side that goes from under it to over it: that side is crossed from each point.
    assert [%{parts: {true, [_ | _], []}}] = SDF.focus([extrude], Frame.point(extrude.frame, {0.0, 0.045, 0.0}), 0.02)

    # A point of a flat side of an outline is at 0 to the last bit: each point of a face on a plane of the grid is on one side.
    can = SDF.edit(:revolve, {[{0, -3}, {3.9, -3}, {3.9, 0}, {0, 0}]})

    for i <- -70..70, j <- [0, 7, 33], x = i * 0.05, y = j * 0.05, x * x + y * y < 3.8 * 3.8, z <- [-3.0, 0.0] do
      assert SDF.distance(can, {x, y, z}) == 0.0
    end

    # (Past the end of a side: the distance to its end.)
    assert_in_delta SDF.distance(can, {4.2, 0.0, 0.4}), 0.5, 1.0e-12
    assert_in_delta SDF.distance(can, {4.2, 0.0, -3.4}), 0.5, 1.0e-12

    # Two points of a tube at one place: a cone between them has no length.
    assert_raise ArgumentError, fn -> SDF.edit(:tube, {[{0, 0, 0}, {0.0, 0, 0}, {1, 0, 0}], [0.1, 0.1, 0.1]}) end
    # A profile with all its sides on the axis has no shape.
    none = SDF.edit(:revolve, {[{0, 0}, {0, 1}, {0, 2}]})
    assert SDF.focus([none], {0.0, 0.0, 0.0}, 0.1) == [none] and SDF.distance(none, {0.1, 0, 0}) > 1.0e10
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

  test "the hot loops of the value and of the color give the same results as the folds, to the bit, for each shape, frame and mode (plan 0010, R13; plan 0015)" do
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
      :wedge -> {u.(0.05, 0.3), u.(0.05, 0.3), u.(0.05, 0.3)}
      :prism -> {u.(0.05, 0.3), u.(0.05, 0.3), 6}
      :pyramid -> {u.(0.05, 0.3), u.(0.05, 0.3), u.(0.05, 0.3)}
      :extrude -> {[{-0.2, -0.1}, {0.2, -0.1}, {0.25, 0.1}, {0.0, 0.05}, {-0.2, 0.15}], u.(0.05, 0.2), 0.02}
      :revolve -> {[{0.0, -0.2}, {0.2, -0.15}, {0.1, 0.0}, {0.25, 0.2}, {0.0, 0.2}]}
    end

    edits =
      for shape <- SDF.shapes(),
          turn? <- [false, true],
          mode <- SDF.modes(),
          blend <- [0.0, u.(0.02, 0.1)],
          hard <- [false, true] do
        raise = if mode == :paint, do: [raise: u.(-0.03, 0.03)], else: []
        SDF.edit(shape, size.(shape), [frame: frame.(turn?), mode: mode, blend: blend, hard: hard] ++ raise)
      end

    # A paint with no raise is not in the list of the value.
    plain = SDF.edit(:ball, {0.2}, mode: :paint, color: {1, 2, 3})
    assert {:fast, list} = SDF.fast(edits ++ [plain])
    assert length(list) == length(edits) and length(edits) == 15 * 2 * 4 * 2 * 2
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

    # The hot loop of the color and the finish (`looks/2`): the same edits, each with a color, and
    # some with a finish, a surface, a material or a paint that is not all there. The same result to the bit.
    defaults = %{skin: {0.3, 0.9}}

    seen =
      for {e, i} <- Enum.with_index(edits) do
        e = %{e | color: if(rem(i, 5) == 0 and e.mode != :add, do: nil, else: {u.(0, 1), u.(0, 1), u.(0, 1)})}
        e = if rem(i, 3) == 0, do: %{e | roughness: u.(0.1, 0.9), metal: u.(0, 1), glow: u.(0, 1)}, else: e
        e = if rem(i, 4) == 0, do: %{e | surface: {:stone, 0.05}}, else: e
        e = if rem(i, 7) == 0, do: %{e | material: :skin}, else: e
        if e.mode == :paint, do: %{e | opacity: u.(0.2, 1.0)}, else: e
      end

    for list <- [seen | for(e <- seen, do: [ball, e])],
        looks = SDF.looks(list, defaults),
        limit <- [1.0e30, 0.2],
        p <- Enum.take(points, if(length(list) > 2, do: 2_000, else: 60)) do
      assert SDF.seen(looks, p, limit, defaults) == SDF.seen(list, p, limit, defaults)
      assert SDF.sample(looks, p, limit, defaults) == SDF.sample(list, p, limit, defaults)
    end

    assert SDF.seen(SDF.looks([ball], %{}), {1, 0, 0}, 5, %{}) == SDF.seen([ball], {1, 0, 0}, 5, %{})
  end

  test "the parts of the hot loop are the steps of the functions of the field" do
    require World.SDF.Inline, as: Inline
    :rand.seed(:exsss, {8, 8, 8})

    for _ <- 1..500 do
      [d, de, k, limit, h] = for _ <- 1..5, do: :rand.uniform() - 0.3
      k = if k < 0.1, do: 0.0, else: k
      limit = abs(limit) + 0.05
      clamp = fn v -> min(max(v, -limit), limit) end
      assert Inline.blend(:add, d, de, k, 0.0, limit) == clamp.(SDF.smin(d, de, k))
      assert Inline.blend(:subtract, d, de, k, 0.0, limit) == clamp.(SDF.smax(d, -de, k))
      assert Inline.blend(:crop, d, de, k, 0.0, limit) == clamp.(SDF.smax(d, de, k))
      # A hard blend: the flat slope.
      assert Inline.blend(:add, d, de, k, 1.0, limit) == clamp.(SDF.chamfer(d, de, k))
      assert Inline.blend(:crop, d, de, k, 1.0, limit) == clamp.(-SDF.chamfer(-d, -de, k))
      assert Inline.clamp(d * 3, limit) == clamp.(d * 3)
      assert Inline.positive(d) == max(d, 0.0)
      assert Inline.sign(d) == if(d > 0.0, do: 1.0, else: -1.0) and Inline.sign(d - d) == 0.0
      least = min(d, de)
      assert Inline.soft(least, d, de, k, 0.0) == SDF.smin(d, de, k)
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

  test "a crop keeps what is inside its shape; a hard blend makes a flat slope; a paint has an opacity (plan 0010, R11)" do
    ball = SDF.edit(:ball, {0.5}, material: :stone, color: {200, 200, 200})
    crop = SDF.edit(:box, {0.3, 1.0, 1.0}, mode: :crop, material: :rust, color: {10, 20, 30})
    edits = [ball, crop]

    # In the box the ball stays; out of it nothing; the cut face is at x = 0.3, with the material and the color of the crop.
    assert SDF.value(edits, {0.2, 0.0, 0.0}) < 0 and SDF.value(edits, {0.4, 0.0, 0.0}) > 0
    assert_in_delta SDF.value(edits, {0.3, 0.1, 0.1}), 0.0, 1.0e-12
    assert {_, :rust} = SDF.field(edits, {0.3, 0.1, 0.1})
    assert {_, :stone} = SDF.field(edits, {0.0, 0.0, 0.5})
    assert SDF.color(edits, {0.3, 0.1, 0.1}) == {10, 20, 30}
    assert SDF.color(edits, {0.0, 0.0, 0.5}) == {200, 200, 200}
    # A crop has no share of the surface for the bones, and gives its finish to its face.
    assert SDF.shares(edits, {0.3, 0.1, 0.1}) == [{ball, 1.0}]
    assert SDF.finish([ball, %{crop | metal: 1.0}], {0.3, 0.1, 0.1}) == {0.6, 1.0, 0.0}
    # A crop that holds the whole cell, deep in it, goes from the list of the cell.
    assert SDF.prune([ball, SDF.edit(:ball, {5.0}, mode: :crop)], {0.0, 0.0, 0.5}, 0.1) == [ball]
    assert SDF.prune(edits, {0.3, 0.0, 0.0}, 0.1) == edits
    assert_raise ArgumentError, fn -> SDF.edit(:ball, {1}, mode: :keep) end

    # The hard blend: the minimum with a flat slope. Two flat faces at a right angle (a floor and a wall)
    # get a flat face from 0.1 m on the floor to 0.1 m on the wall; a smooth blend gives a round one.
    assert SDF.chamfer(0.3, 0.7, 0.0) == 0.3 and SDF.chamfer(0.3, 0.8, 0.4) == 0.3
    assert_in_delta SDF.chamfer(0.2, 0.2, 0.4), 0.0, 1.0e-12
    floor = SDF.edit(:box, {5.0, 5.0, 5.0}, frame: Frame.move({0.0, 0.0, -5.0}))
    wall = fn opts -> SDF.edit(:box, {5.0, 5.0, 5.0}, [frame: Frame.move({-5.0, 0.0, 0.0}), blend: 0.1] ++ opts) end
    hard = [floor, wall.(hard: true)]
    for t <- [0.02, 0.05, 0.08], do: assert_in_delta(SDF.value(hard, {t, 0.0, 0.1 - t}), 0.0, 1.0e-12)
    assert SDF.value([floor, wall.([])], {0.05, 0.0, 0.05}) > 0.02
    # It reaches only its blend past its shape, and the field keeps a slope of at most 1.
    assert_in_delta SDF.value(hard, {0.2, 0.0, 0.05}), 0.05, 1.0e-12
    :rand.seed(:exsss, {3, 3, 3})
    mixed = [ball, SDF.edit(:box, {0.3, 0.3, 0.3}, frame: Frame.move({0.5, 0.0, 0.0}), blend: 0.2, hard: true), crop]

    for _ <- 1..500 do
      [p, q] = for _ <- 1..2, do: {:rand.uniform() - 0.3, :rand.uniform() - 0.5, :rand.uniform() - 0.5}
      assert abs(SDF.value(mixed, p) - SDF.value(mixed, q)) <= Vec.len(Vec.sub(p, q)) * (1 + 1.0e-9)
      # A cell keeps the edits that can change the field in it, with a crop and a hard blend too.
      half = 0.02 + :rand.uniform() * 0.2
      {kept, {lo, hi}} = SDF.cell(mixed, p, half)
      near = Vec.add(p, Vec.scale(Vec.norm(Vec.sub(q, p)), half * :rand.uniform()))
      assert SDF.field(kept, near) == SDF.field(mixed, near)
      assert SDF.value(mixed, near) >= lo - 1.0e-12 and SDF.value(mixed, near) <= hi + 1.0e-12
    end

    # The bounds hold the inside, which a hard blend moves out by half of its blend at the most.
    assert SDF.bounds([SDF.edit(:ball, {1}, blend: 0.4, hard: true)]) == {{-1.2, -1.2, -1.2}, {1.2, 1.2, 1.2}}

    # A paint with an opacity of a half: the mean of the light of the two colors.
    white = SDF.edit(:ball, {0.5}, color: {255, 255, 255})

    black = fn opacity ->
      SDF.edit(:ball, {0.2}, frame: Frame.move({0.5, 0.0, 0.0}), mode: :paint, color: {0, 0, 0}, opacity: opacity)
    end

    assert SDF.color([white, black.(1.0)], {0.5, 0.0, 0.0}) == {0, 0, 0}
    assert SDF.color([white, black.(0.5)], {0.5, 0.0, 0.0}) == {188, 188, 188}
    assert SDF.color([white, black.(0.0)], {0.5, 0.0, 0.0}) == {255, 255, 255}
    assert SDF.finish([white, %{black.(0.5) | metal: 1.0}], {0.5, 0.0, 0.0}) == {0.6, 0.5, 0.0}
  end

  test "the wedge, the prism and the pyramid: their faces, their inside, a slope of at most 1, and their bounds" do
    wedge = SDF.edit(:wedge, {0.3, 0.4, 0.2})
    # The slope goes from the top edge at the back to the bottom edge at the front, through the center.
    assert_in_delta SDF.distance(wedge, {0.0, 0.0, 0.0}), 0.0, 1.0e-12
    assert_in_delta SDF.distance(wedge, {0.0, -0.4, 0.2}), 0.0, 1.0e-12
    assert_in_delta SDF.distance(wedge, {0.0, 0.4, -0.2}), 0.0, 1.0e-12
    assert SDF.distance(wedge, {0.0, -0.2, -0.1}) < 0 and SDF.distance(wedge, {0.0, 0.2, 0.1}) > 0
    assert_in_delta SDF.distance(wedge, {0.5, -0.2, -0.1}), 0.2, 1.0e-12

    prism = SDF.edit(:prism, {0.3, 0.2, 6})
    assert_in_delta SDF.distance(prism, {0.0, 0.0, 0.0}), -0.2, 1.0e-12
    # Each of its six sides is 0.3 from its axis; its corners are farther.
    for i <- 0..5,
        a = i * :math.pi() / 3,
        do: assert_in_delta(SDF.distance(prism, {0.3 * :math.cos(a), 0.3 * :math.sin(a), 0.0}), 0.0, 1.0e-12)

    assert SDF.distance(prism, {0.32 * :math.cos(:math.pi() / 6), 0.32 * :math.sin(:math.pi() / 6), 0.0}) < 0
    assert_in_delta SDF.distance(prism, {0.0, 0.0, 0.5}), 0.3, 1.0e-12

    pyramid = SDF.edit(:pyramid, {0.3, 0.2, 0.4})
    assert_in_delta SDF.distance(pyramid, {0.0, 0.0, 0.4}), 0.0, 1.0e-12
    assert_in_delta SDF.distance(pyramid, {0.3, 0.0, -0.4}), 0.0, 1.0e-12
    assert_in_delta SDF.distance(pyramid, {0.0, 0.2, -0.4}), 0.0, 1.0e-12
    assert_in_delta SDF.distance(pyramid, {0.0, 0.0, -0.6}), 0.2, 1.0e-12
    assert SDF.distance(pyramid, {0.0, 0.0, 0.0}) < 0 and SDF.distance(pyramid, {0.2, 0.0, 0.2}) > 0

    :rand.seed(:exsss, {2, 2, 2})

    for e <- [wedge, prism, pyramid] do
      {lo, hi} = SDF.bounds([e])

      for _ <- 1..500 do
        [p, q] = for _ <- 1..2, do: {:rand.uniform() - 0.5, :rand.uniform() - 0.5, :rand.uniform() - 0.5}
        assert abs(SDF.distance(e, p) - SDF.distance(e, q)) <= Vec.len(Vec.sub(p, q)) * (1 + 1.0e-9)
        if SDF.distance(e, p) < 0, do: assert(inside?({lo, hi}, p))
      end
    end
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

  test "an outline: an extrude of a rectangle is a box, a revolve of a rectangle is a cylinder; a hollow outline; round edges (plan 0012, D4)" do
    :rand.seed(:exsss, {5, 5, 5})
    places = for _ <- 1..600, do: {:rand.uniform() - 0.5, :rand.uniform() - 0.5, :rand.uniform() - 0.5}
    frame = Frame.new({0.03, -0.02, 0.05}, {0.2, 0.3, 0.9}, {1.0, 0.1, 0.0})

    # A rectangle of 0.4 by 0.2, 0.3 deep: the box of the half sizes 0.2, 0.1 and 0.15 (the points in each order).
    rect = [{-0.2, -0.1}, {0.2, -0.1}, {0.2, 0.1}, {-0.2, 0.1}]
    box = SDF.edit(:box, {0.2, 0.1, 0.15}, frame: frame)

    for points <- [rect, Enum.reverse(rect)] do
      solid = SDF.edit(:extrude, {points, 0.15, 0}, frame: frame)
      for p <- places, do: assert_in_delta(SDF.distance(solid, p), SDF.distance(box, p), 1.0e-9)
      assert solid.box == box.box
    end

    # A rectangle from the axis, turned round it: a cylinder.
    can = SDF.edit(:cylinder, {0.2, 0.15}, frame: frame)
    turned = SDF.edit(:revolve, {[{0, -0.15}, {0.2, -0.15}, {0.2, 0.15}, {0, 0.15}]}, frame: frame)
    for p <- places, do: assert_in_delta(SDF.distance(turned, p), SDF.distance(can, p), 1.0e-9)
    assert turned.box == can.box

    # An outline with a notch (an L): a point of the notch is outside, and its distance is to the nearest side.
    ell = SDF.edit(:extrude, {[{0, 0}, {0.3, 0}, {0.3, 0.1}, {0.1, 0.1}, {0.1, 0.3}, {0, 0.3}], 0.05, 0})
    assert_in_delta SDF.distance(ell, {0.2, 0.2, 0.0}), 0.1, 1.0e-12
    assert_in_delta SDF.distance(ell, {0.05, 0.2, 0.0}), -0.05, 1.0e-12
    assert_in_delta SDF.distance(ell, {0.05, 0.2, 0.09}), 0.04, 1.0e-12
    assert_in_delta SDF.distance(ell, {0.4, 0.2, 0.0}), :math.sqrt(0.02), 1.0e-12

    # A profile away from the axis: a ring with a square section, hollow in its middle.
    band = SDF.edit(:revolve, {[{0.2, -0.05}, {0.3, -0.05}, {0.3, 0.05}, {0.2, 0.05}]})
    assert_in_delta SDF.distance(band, {0.0, 0.0, 0.0}), 0.2, 1.0e-12
    assert_in_delta SDF.distance(band, {0.0, -0.25, 0.0}), -0.05, 1.0e-12
    assert_in_delta SDF.distance(band, {0.25, 0.0, 0.1}), 0.05, 1.0e-12

    # Round edges: the flat faces and the outline stay; the edge between them is in by the radius.
    sharp = SDF.edit(:extrude, {rect, 0.15, 0})
    round = SDF.edit(:extrude, {rect, 0.15, 0.03})
    assert_in_delta SDF.distance(round, {0.0, 0.0, 0.15}), 0.0, 1.0e-12
    assert_in_delta SDF.distance(round, {0.2, 0.0, 0.0}), 0.0, 1.0e-12
    assert_in_delta SDF.distance(round, {0.2, 0.0, 0.15}), 0.03 * (:math.sqrt(2) - 1), 1.0e-12
    assert_in_delta SDF.distance(sharp, {0.2, 0.0, 0.15}), 0.0, 1.0e-12
    assert round.box == sharp.box

    # The slope of each is at most 1 (the cells of the tree need it), and the bounds hold the inside.
    for e <- [ell, band, round, turned] do
      {lo, hi} = SDF.bounds([e])

      for [p, q] <- Enum.chunk_every(places, 2) do
        assert abs(SDF.distance(e, p) - SDF.distance(e, q)) <= Vec.len(Vec.sub(p, q)) * (1 + 1.0e-9)
        if SDF.distance(e, p) < 0, do: assert(inside?({lo, hi}, p))
      end
    end
  end

  test "the bounds hold a blend at a sharp edge: a wedge, a prism, a pyramid, a superellipsoid" do
    # The field of these shapes is less than the distance at an edge, so
    # two of them with a blend have their inside far past the edge.
    # Two places of the shape for each case: with the axes of the world, and turned.
    frames = [
      {Frame.move({0.0, 0.0, 0.0}), Frame.turn({0.0, 0.0, 1.0}, 180, {0.03, 0.0, 0.0})},
      {Frame.new({0.02, -0.01, 0.03}, {0.3, 0.5, 0.8}, {1.0, 0.2, 0.0}),
       Frame.new({0.05, -0.01, 0.03}, {-0.3, 0.5, 0.8}, {1.0, -0.2, 0.0})}
    ]

    shapes = [
      wedge: {0.115, 0.078, 0.05},
      wedge: {0.1, 0.03, 0.2},
      pyramid: {0.2, 0.05, 0.1},
      pyramid: {0.05, 0.1, 0.3},
      prism: {0.1, 0.05, 3},
      prism: {0.1, 0.2, 5},
      superellipsoid: {0.25, 0.04, 0.1, 4}
    ]

    :rand.seed(:exsss, {3, 3, 3})

    past =
      for {shape, size} <- shapes, hard <- [true, false], {first, second} <- frames do
        one = SDF.edit(shape, size, frame: first, blend: 0.08, hard: hard)
        edits = [one, SDF.edit(shape, size, frame: second, blend: 0.08, hard: hard)]
        {lo, hi} = bounds = SDF.bounds(edits)
        {{wx, wy, wz}, mid} = {Vec.sub(hi, lo), Vec.lerp(lo, hi, 0.5)}
        # Points in a box 1.5 times as large as the bounds.
        spot = fn -> 1.5 * (:rand.uniform() - 0.5) end

        inside =
          for _ <- 1..3_000,
              p = Vec.add(mid, {spot.() * wx, spot.() * wy, spot.() * wz}),
              SDF.value(edits, p) < 0,
              do: p

        assert inside != []
        for p <- inside, do: assert(inside?(bounds, p), inspect({shape, size, hard, p, bounds}))
        # With no blend, the box of the shape.
        assert SDF.bounds([%{one | blend: 0.0}]) == one.box

        # The points of the inside that are past the boxes of the two shapes, grown by the reach of the blends.
        reach = if hard, do: 0.08, else: 0.04
        {a, b} = Vec.bounds(for e <- edits, corner <- Tuple.to_list(e.box), do: corner)
        plain = {Vec.sub(a, {reach, reach, reach}), Vec.add(b, {reach, reach, reach})}
        Enum.count(inside, &(not inside?(plain, &1)))
      end

    # (So the boxes with the reach only do not hold the inside.)
    assert Enum.sum(past) > 0
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
    assert SDF.shapes() |> length() == 15 and SDF.modes() == [:add, :subtract, :paint, :crop]
    assert_raise ArgumentError, ~r/the mode of an edit/, fn -> SDF.edit(:ball, {1}, mode: :melt) end
  end
end
