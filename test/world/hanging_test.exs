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

      # A person (World.People) has its own triangles: 44 000 at near.
      person? = Enum.any?(item.nodes, &match?({_, %World.Figure{}, _}, &1))

      for level <- [:near, :mid, :far] do
        tris = Scene.triangles(Build.scene(Detail.with(level, fun), level: level))

        limit =
          %{near: 40_000, mid: 15_000, far: 8_000}[level] +
            if(person?, do: %{near: 45_000, mid: 8_000, far: 2_000}[level], else: 0)

        assert tris < limit, "#{name} at #{level}: #{tris}"
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
    # A packed hammock has no joint: its carabiners lie on the ground.
    assert [] == for({_, _, %{kind: :hinge}} <- Hanging.camping_packed().nodes, do: :hinge)

    for {name, fun} <- Hanging.models(), name != "hammock_camping_packed" do
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

  test "a person in a hammock: the bed hangs deeper under the weight, and the person lies on the bed" do
    # The same bed with a person in it sags more: its middle is a parabola
    # under the body, straight out of it.
    assert Bed.sag(2.4, 2.9, 0.7) > Bed.sag(2.4, 2.9)
    [{_, z0}, {_, z1}, {_, z2}] = Bed.loaded(2.4, 2.9, 0.7, 2)
    assert z0 == 0.0 and z2 == 0.0 and z1 < 0
    assert Hanging.hang(4.2, 2.9, 0.46, nil, 0.7).anchor > Hanging.hang(4.2, 2.9, 0.46).anchor

    item = Detail.with(:far, fn -> Hanging.camping(person: true, name: "p") end)
    {_, person, c} = List.keyfind(item.nodes, "person", 0)
    assert %World.Figure{kind: :person} = person
    assert c.to == "bed_p"
    # The head and the feet are over the hips: the person lies in the
    # curve of the bed.
    place = Frame.compose(World.Port.frame(c.at), Frame.invert(World.Figure.port_frame(person, "hips")))
    z = fn n -> elem(Frame.point(place, World.Figure.port_frame(person, n).at), 2) end
    assert z.("crown") > z.("hips") and z.("sole_l") > z.("hips")
  end

  test "the frame of the võng xếp folds in the steps of Duy Lợi, to a bundle of about 1.1 by 0.2 by 0.2 m" do
    item = Hanging.vong_xep_frame()
    [%{name: "fold", keys: keys}] = item.clips
    # Open at the start and at the end; the folded pose in the middle.
    assert {+0.0, open} = hd(keys)
    assert Enum.all?(open, fn {_, v} -> v == 0.0 end)
    {_, folded} = Enum.at(keys, 4)
    assert World.Check.model(item, folded) == :ok
    {open_lo, open_hi} = Scene.bounds(Build.scene(item, level: :far))
    {lo, hi} = Scene.bounds(Build.scene(item, pose: folded, level: :far))
    {ox, oy, _} = Vec.sub(open_hi, open_lo)
    {x, y, z} = Vec.sub(hi, lo)
    assert ox > 2.5 and oy > 0.7
    assert x < 1.2 and y < 0.25 and z < 0.25
    # The right side slides to the left one; the struts turn first.
    assert folded["side_right_vong_xep_frame"] > 0.5
    {_, struts} = Enum.at(keys, 1)
    assert struts["strut_left_back_vong_xep_frame"] != 0 and struts["side_right_vong_xep_frame"] == 0.0
  end

  test "a part that stretches: the spring is a skin between the node that swings and the slide" do
    item = Hanging.egg_chair()
    scene = Build.scene(item, pose: %{"bounce_egg_chair" => 0.02})
    i = Enum.find_index(scene.nodes, &(&1.name == "spring_egg_chair"))
    node = Enum.at(scene.nodes, i)
    %{joints: [a, b]} = Enum.at(scene.skins, node.skin)
    assert Enum.at(scene.nodes, a).name == "swing_egg_chair_y" and Enum.at(scene.nodes, b).name == "bounce_egg_chair"
    # The top eye stays, the bottom eye goes down with the slide, the coils between.
    weights =
      for p <- node.primitives,
          {{j, _, _, _}, {w0, w1, _, _}} <- Enum.zip(p.joints, p.weights),
          do: if(j == 1, do: 1.0, else: w1 * 1.0 + 0 * w0)

    assert Enum.min(weights) == 0.0 and Enum.max(weights) == 1.0
    assert Enum.any?(weights, &(&1 > 0.3 and &1 < 0.7))
    # The bottom of the spring goes down with the slide; its top stays.
    only = fn sc ->
      %{sc | nodes: Enum.map(sc.nodes, &if(&1.name == "spring_egg_chair", do: &1, else: %{&1 | primitives: []}))}
    end

    {{_, _, lo}, {_, _, hi}} = Scene.bounds(only.(scene))
    {{_, _, lo0}, {_, _, hi0}} = Scene.bounds(only.(Build.scene(item)))
    assert_in_delta lo, lo0 - 0.02, 1.0e-6
    assert_in_delta hi, hi0, 1.0e-6
    # A part that stretches to a node that is not there is an error.
    bad =
      put_in(
        Hanging.egg_chair().nodes,
        Enum.map(item.nodes, fn
          {"bounce_egg_chair" = n, part, c} ->
            {n, %{part | name: n}, c}

          {n, %{params: %{"stretch" => st}} = part, c} ->
            {n, %{part | params: %{"stretch" => %{st | "to" => "none"}}}, c}

          other ->
            other
        end)
      )

    assert_raise ArgumentError, ~r/no node none/, fn -> Build.scene(bad) end
  end

  test "people on the swings and in the beds: the diagonal lay, the hands on the ropes, the back in the basket" do
    place = fn item ->
      {_, person, c} = List.keyfind(item.nodes, "person", 0)
      f = Frame.compose(World.Port.frame(c.at), Frame.invert(World.Figure.port_frame(person, "hips")))
      {person, c, fn n -> Frame.point(f, World.Figure.port_frame(person, n).at) end}
    end

    # The camping hammock: the head 15 degrees off the middle line.
    {_, _, at} = place.(Detail.with(:far, fn -> Hanging.camping(person: true, name: "p") end))
    {hx, hy, _} = Vec.sub(at.("crown"), at.("hips"))
    assert_in_delta :math.atan2(-hy, -hx) * 180 / :math.pi(), 15, 3

    # The plank swing: the hands close on the ropes, the person on the seat.
    {person, c, at} = place.(Detail.with(:far, fn -> Hanging.plank_swing(person: true) end))
    assert c.to == "seat_swing_plank"
    # The hand closes: its fingers turn (the shape "grip").
    assert Map.has_key?(person.pose, "index_01_l")
    {gx, _, gz} = at.("grip_l")
    assert_in_delta gx, -0.25, 0.08
    assert_in_delta gz, 1.05, 0.1

    # The egg chair: the person sits nearly upright in the basket, on the
    # node that spins, the hands on the lap.
    {person, c, at} = place.(Detail.with(:far, fn -> Hanging.egg_chair(person: true) end))
    assert c.to == "spin_egg_chair"
    assert abs(elem(at.("crown"), 1) - elem(at.("hips"), 1)) < 0.1
    assert elem(at.("crown"), 2) > elem(at.("hips"), 2) + 0.6
    assert Map.has_key?(person.pose, "index_01_l")
    {_, c, _} = place.(Detail.with(:far, fn -> Hanging.porch_swing(person: true) end))
    assert c.to == "bench_swing_porch"
  end

  test "the person in the egg chair is inside its basket: no point through the wicker, the head under its top" do
    item = Detail.with(:mid, fn -> Hanging.egg_chair(person: true) end)
    scene = Build.scene(item, level: :mid)
    frames = Scene.world_frames(scene)
    {bw, bd, bh, low} = {0.9, 0.6, 1.05, 0.52}
    person = Enum.find(scene.nodes, &(&1.skin != nil and &1.name != "spring_egg_chair"))
    skin = Enum.at(scene.skins, person.skin)

    bones =
      skin.joints
      |> Enum.zip(skin.inverse_bind)
      |> Enum.map(fn {j, ib} -> Frame.compose(frames[j], ib) end)
      |> List.to_tuple()

    points =
      for p <- person.primitives, {pt, js, ws} <- Enum.zip([p.positions, p.joints, p.weights]) do
        Enum.zip(Tuple.to_list(js), Tuple.to_list(ws))
        |> Enum.map(fn {j, w} -> Vec.scale(Frame.point(elem(bones, j), pt), w) end)
        |> Enum.reduce(&Vec.add/2)
      end

    # Out of the oval of the basket at its height, and not out of the front
    # (the legs go out of the opening).
    through =
      for {x, y, z} <- points,
          z > low and z < low + bh,
          e = Hanging.egg((z - low) / bh),
          e > 0,
          (x / (bw / 2 * e)) ** 2 + (y / (bd / 2 * e)) ** 2 > 1.0,
          y < 0.25 * bd / 2 * e,
          do: {x, y, z}

    assert through == []
    assert points |> Enum.map(&elem(&1, 2)) |> Enum.max() < low + bh
  end

  test "the shelter of a camping hammock: a tarp and a bug net on the site, over the hammock" do
    item = Hanging.camping(shelter: true, name: "s")
    names = for {_, p, _} <- item.nodes, do: p.name
    assert "tarp_s" in names and "bug_net_s" in names
    # The tarp and the net stay on the site: on the root, not on the bed.
    for n <- ["tarp_s", "bug_net_s"],
        do: assert({_, _, %{kind: :fixed, to: "tree_left_s"}} = List.keyfind(item.nodes, n, 0))

    {_, _, %{limits: [-8, 8]}} = List.keyfind(item.nodes, "bed_s", 0)
    # The bug net goes under the hammock, and the tarp over the net.
    z = fn n ->
      {_, p, _} = List.keyfind(item.nodes, n, 0)
      p.shapes |> Enum.flat_map(& &1.points) |> Enum.map(&elem(&1, 2))
    end

    assert Enum.min(z.("bug_net_s")) < Enum.min(z.("bed_s"))
    assert Enum.max(z.("tarp_s")) > Enum.max(z.("bug_net_s"))
    assert item.materials[:screen]["alpha"] == 0.35
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
    assert rest["spring_egg_chair"] == down["spring_egg_chair"]
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
