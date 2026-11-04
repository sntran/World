defmodule World.HangingTest do
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Frame, Mass, Scene, Vec}
  alias World.Furniture.Hanging
  alias World.Furniture.Hanging.{Bed, Rig}

  doctest Hanging
  doctest Bed

  test "the catenary of a bed: its length, its sag, and a longer bed sags more" do
    pts = Bed.catenary(2.0, 2.4, 64)
    {_, z0} = hd(pts)
    assert z0 == 0.0 and Enum.all?(pts, fn {_, z} -> z <= 1.0e-12 end)
    assert Bed.sag(2.0, 2.4) > Bed.sag(2.0, 2.2)
    # A bed with gathered ends hangs with 83% of its length between them.
    h = Hanging.hang(4.5, 2.9, 0.46)
    assert_in_delta h.span / 2.9, 0.83, 1.0e-9
    assert_in_delta h.drop, :math.tan(:math.pi() / 6) * (4.5 - h.span) / 2, 1.0e-9
    assert_in_delta Hanging.hang(4.0, 3.0, 0.5, 2.5).span, 2.5, 1.0e-9
  end

  test "the shapes of a bed: gathered, on bars, spread; as cloth or as a net" do
    e = {{-1.0, 0.0, 1.0}, {1.0, 0.0, 1.0}}

    width = fn ends ->
      s = Bed.surface(elem(e, 0), elem(e, 1), length: 2.3, width: 1.4, ends: ends)
      Vec.len(Vec.sub(s.({0.0, 1.0}), s.({0.0, -1.0})))
    end

    assert width.(:gathered) < 0.03
    assert_in_delta width.({:bar, 0.5}), 0.5, 0.01
    assert_in_delta width.(:spread), 1.4, 0.01
    s = Bed.surface(elem(e, 0), elem(e, 1), length: 2.3, width: 1.4, ends: :gathered)
    # Each thread along the bed has the length of the bed: the edges hang
    # almost taut, the middle deep.
    len = fn v -> polyline(for i <- 0..200, do: s.({i / 200, v})) end
    for v <- [0.0, 0.5, 1.0], do: assert_in_delta(len.(v), 2.3, 0.01)
    assert elem(s.({0.5, 1.0}), 2) > elem(s.({0.5, 0.0}), 2) + 0.2
    # Across the middle, the cloth is as wide as it is flat.
    assert_in_delta polyline(for j <- 0..100, do: s.({0.5, -1 + j / 50})), 1.4, 0.02
    # A bed with short ends cannot spread: its edges are taut, no longer
    # than the bed.
    short = Bed.surface(elem(e, 0), elem(e, 1), length: 2.05, width: 1.4, ends: :gathered)
    assert polyline(for i <- 0..200, do: short.({i / 200, 1.0})) <= 2.06
    # A net: a cord for each strand and an edge cord at each side, half at
    # mid, sheets at far.
    assert length(Bed.net(s, strands: 10, knots: 12)) == 12
    assert length(Detail.with(:mid, fn -> Bed.net(s, strands: 10, knots: 12) end)) == 7
    assert [%World.Mesh{}] = Detail.with(:far, fn -> Bed.net(s) end)
    # A cloth in bands across: one mesh for each band.
    assert [_, _, _] = Bed.cloth(s, bands: [{1, :dark}, {4, :fabric}, {1, :dark}])
    assert %World.Mesh{} = Bed.whipping({0, 0, 0}, {1, 0, 0})
    assert Bed.area(s) > 2.0
  end

  test "the rig: ropes, rings, chains, cords, hooks, carabiners, swivels in two halves, straps, anchors" do
    assert %World.Mesh{matter: :nylon} = Rig.rope({0, 0, 0}, {0, 0, 1}, 0.01)
    assert length(Rig.chain({0, 0, 0}, {0, 0, 0.5})) > 20
    assert [_] = Detail.with(:mid, fn -> Rig.chain({0, 0, 0}, {0, 0, 0.5}) end)
    assert length(Rig.fan({0, 0, 0}, [{1, 0, 0}, {1, 1, 0}])) == 2
    assert %{ports: %{"hook" => _}} = Rig.hook("h", {0, 0, 2})
    assert %{kind: :hardware} = Rig.carabiner("c", {0, 0, 1})
    {top, bottom} = Rig.swivel("s", {0, 0, 1})
    assert top.name == "s_top" and bottom.name == "s_bottom"
    assert %{kind: :strap} = Rig.tree_strap("t", {0.0, 0.0}, 0.15, 1.7, {1.0, 0.0, 1.5})
    assert %{kind: :site} = Rig.post("p", {0.0, 0.0}, 0.12)
    assert %{kind: :site} = Rig.beam("b", {-1.0, 0.0, 2.4}, {1.0, 0.0, 2.4})
  end

  test "the models: true models of the hammock shop, a mass for each part, in their limits" do
    for {name, fun} <- Hanging.models() do
      item = fun.()
      assert World.Check.model(item) == :ok, name
      assert %{unknown: []} = Mass.of(item)
      assert World.Places.family_of(item) == :hanging

      for level <- [:near, :mid, :far] do
        tris = Scene.triangles(Build.scene(Detail.with(level, fun), level: level))
        assert tris < %{near: 40_000, mid: 15_000, far: 8_000}[level], "#{name} at #{level}: #{tris}"
      end
    end
  end

  test "the hang: the lowest point of a camping hammock at its sit height, its straps at 30 degrees" do
    item = Hanging.camping()
    {_, bed, _} = List.keyfind(item.nodes, "bed_hammock_camping", 0)
    low = bed.shapes |> Enum.flat_map(& &1.points) |> Enum.map(&elem(&1, 2)) |> Enum.min()
    assert_in_delta low, 0.46, 0.03
    # The camping hammock has the mass of its data sheet.
    assert bed.params["mass"] == 0.538
  end

  test "the joints as in real life: the site and its hooks stay, the thing swings about the real axis" do
    for {name, fun} <- Hanging.models() do
      item = fun.()
      hinges = for {n, _, %{kind: :hinge, limits: limits}} <- item.nodes, do: {n, limits}
      assert hinges != [], name
      pose = Map.new(hinges, fn {n, l} -> {n, if(l, do: List.last(l), else: 90)} end)
      frames = fn p -> Map.new(Build.placed(item, p), fn {f, part} -> {part.name, f} end) end
      {rest, swung} = {frames.(%{}), frames.(pose)}

      # The parts on the root (the site, the stand, the hooks, the knots,
      # the loops of the straps) stay; the others move.
      fixed =
        for {_, part, c} <- item.nodes,
            c == nil or (c.kind == :fixed and c.to == elem(hd(item.nodes), 0)),
            do: part.name

      assert Enum.all?(fixed, &(rest[&1] == swung[&1])), name
      assert Enum.any?(Map.keys(rest) -- fixed, &(rest[&1] != swung[&1])), name

      # The point of the axis of each joint stays where it is: the part
      # turns about the real axis.
      # Each joint alone: the joints over it at 0.
      for {n, l} <- hinges, {^n, part, c} <- [List.keyfind(item.nodes, n, 0)], Map.has_key?(rest, part.name) do
        alone = frames.(%{n => if(l, do: List.last(l), else: 90)})
        at = c.at.at
        moved = Frame.point(alone[part.name], Frame.point(Frame.invert(rest[part.name]), at))
        assert Vec.len(Vec.sub(moved, at)) < 1.0e-6, "#{name}: #{n}"
      end
    end
  end

  test "the spring of the egg chair: its rate, its stretch, and the chair that bounces on it" do
    assert_in_delta Rig.spring_length() + 0.007, 0.108, 1.0e-9
    assert_in_delta Rig.stretch(317.5), 0.0287, 0.001
    item = Hanging.egg_chair()
    {_, _, slide} = List.keyfind(item.nodes, "bounce_egg_chair", 0)
    assert %{kind: :slide, role: :bounce, limits: [0, max]} = slide
    assert_in_delta max, Rig.stretch(317.5), 1.0e-9
    # Down by the stretch: the basket goes down, the top of the spring stays.
    frames = fn p -> Map.new(Build.placed(item, p), fn {f, part} -> {part.name, f} end) end
    {rest, down} = {frames.(%{}), frames.(%{"bounce_egg_chair" => max})}
    assert rest["spring_egg_chair_top"] == down["spring_egg_chair_top"]
    assert_in_delta elem(Frame.point(down["basket_egg_chair"], {0, 0, 0}), 2), -max, 1.0e-9
  end

  test "a thing on one point: two hinges at the point and a spin on its swivel, the halves of the swivel on two nodes" do
    for item <- [Hanging.tire_swing(), Hanging.egg_chair()] do
      roles = for {n, _, %{kind: :hinge, role: r}} <- item.nodes, do: {n, r}

      assert Enum.count(roles, fn {_, r} -> r == :swing end) == 2 and
               Enum.count(roles, fn {_, r} -> r == :spin end) == 1

      # The top half of the swivel is on the node over the spin (the one
      # that swings, or the spring of the egg chair); the bottom half is
      # the first part of the node that spins.
      {_, _, top} = Enum.find(item.nodes, &(elem(&1, 0) =~ "swivel_" and elem(&1, 0) =~ "_top"))
      {_, _, spin} = Enum.find(item.nodes, fn {_, _, c} -> c && c.role == :spin end)
      assert top.to == spin.to
      assert Enum.any?(item.nodes, fn {_, p, c} -> c != nil and c.role == :spin and p.name =~ "swivel_" end)
    end
  end

  defp polyline(points),
    do: points |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> Vec.len(Vec.sub(b, a)) end) |> Enum.sum()
end
