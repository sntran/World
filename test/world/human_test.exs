defmodule World.HumanTest do
  use ExUnit.Case, async: true

  alias World.Build

  alias World.Detail

  alias World.Figure

  alias World.People.Human

  alias World.Scene
  alias World.People.{Data, Pose}
  @limits %{near: 50_000, mid: 12_000, far: 5_000}

  # The size of each person: {width, depth, height} in meters, and the
  # tolerance.
  @sizes %{
    "traveler" => {{0.50, 0.46, 1.65}, 0.05},
    "man" => {{0.50, 0.48, 1.71}, 0.05},
    "woman" => {{0.44, 0.40, 1.58}, 0.05}
  }

  # The moves of a target of a primitive, one for each point (a target of
  # a person is a map of the points that move).
  defp moves(pr, name) do
    {_, m} = Enum.find(pr.targets, &(elem(&1, 0) == name))
    for i <- 0..(length(pr.positions) - 1), do: Map.get(m, i, {0.0, 0.0, 0.0})
  end

  for {name, fun} <- World.Catalog.models(), Map.has_key?(@sizes, name) do
    @name name
    @fun fun

    test "#{name}: the size, the levels, the skin and the materials" do
      scenes = for level <- [:near, :mid, :far], do: {level, Build.scene(Detail.with(level, @fun), level: level)}

      for {level, scene} <- scenes do
        tris = Scene.triangles(scene)
        assert tris <= @limits[level], "#{@name} has #{tris} triangles at #{level}"
        [skin] = scene.skins
        assert length(skin.joints) == 53

        # Each point has 4 weights with the sum 1, and no weight less than 0.
        for n <- scene.nodes, p <- n.primitives, w <- p.weights do
          ws = Tuple.to_list(w)
          assert Enum.all?(ws, &(&1 >= 0)) and abs(Enum.sum(ws) - 1) < 1.0e-6
        end

        # The skinned mesh is a root node; the root of the figure is not.
        assert [%{parent: nil}] = Enum.filter(scene.nodes, & &1.skin)
        assert Map.has_key?(scene.materials, :skin)
      end

      [{:near, near}, {:mid, mid}, {:far, far}] = scenes
      assert Scene.triangles(near) > Scene.triangles(mid) and Scene.triangles(mid) > Scene.triangles(far)

      {{w, d, h}, tol} = @sizes[@name]
      [sw, sd, sh] = near.extras["size"]
      assert abs(sw - w) <= tol and abs(sd - d) <= tol and abs(sh - h) <= tol, "#{@name}: #{inspect([sw, sd, sh])}"

      # The feet stand on the ground.
      {{_, _, z}, _} = Scene.bounds(near)
      assert abs(z) < 0.01
      assert near.extras["kind"] == "person"
      assert [%{"name" => @name, "count" => 1, "kind" => "person"}] = Build.parts(@fun.())
    end
  end

  test "a traveler walks" do
    scene = Build.scene(Detail.with(:far, &World.People.traveler/0), level: :far)
    [walk, %{name: "blink"}] = scene.animations
    assert walk.name == "walk"
    assert length(walk.channels) == 8

    for c <- walk.channels do
      assert length(c.times) == 13 and length(c.values) == 13
      # The loop ends where it starts.
      {first, last} = {hd(c.values), List.last(c.values)}

      assert World.Vec.len(World.Vec.sub(first.y, last.y)) < 1.0e-9 and
               World.Vec.len(World.Vec.sub(first.z, last.z)) < 1.0e-9
    end

    glb = World.GLB.encode(scene)
    assert %{"animations" => [_, _], "skins" => [_]} = World.GLBHelper.json(glb)
  end

  test "a rider sits on the scooter with the hands on the grips" do
    model = World.People.rider()
    scene = Build.scene(Detail.with(:far, fn -> World.People.rider() end), level: :far)
    assert scene.extras["kind"] == "vehicle"
    # The scooter is 1.10 m high; a rider is higher.
    [w, l, h] = scene.extras["size"]
    assert w < 0.75 and abs(l - 1.871) < 0.03 and h > 1.5
    assert Enum.any?(Build.parts(model), &(&1["name"] == "rider"))
  end

  test "a traveler on each vehicle of Phượt: the person is in the seat, and the glass of a car is clear" do
    assert World.People.vehicles() == ~w(bicycle camper car foot motorbike motorcycle)

    for v <- World.People.vehicles() do
      scene = Build.scene(Detail.with(:far, fn -> World.People.traveler(v) end), level: :far)
      [_, _, h] = scene.extras["size"]

      # The head of the person stays under the roof of the car and the van.
      case v do
        "foot" -> assert scene.extras["kind"] == "person" and h > 1.5
        "car" -> assert h < 1.62 and scene.materials[:glass_dark]["alpha"] == 0.35
        "camper" -> assert h < 2.81 and scene.materials[:paint]["color"] != nil
        _ -> assert scene.extras["kind"] == "vehicle" and h > 1.5
      end
    end
  end

  test "a rider on two wheels has a helmet on the head; a driver and a person on foot have none" do
    for v <- World.People.vehicles() do
      scene = Build.scene(Detail.with(:far, fn -> World.People.traveler(v, helmet: [200, 30, 30]) end), level: :far)
      helmet = for n <- scene.nodes, p <- n.primitives, p.material == :helmet, do: p

      if v in ~w(bicycle motorbike motorcycle) do
        [p] = helmet
        assert scene.materials[:helmet]["color"] == [200, 30, 30]
        # Each point of the helmet follows the bone "head" only.
        [skin] = scene.skins
        head = Enum.find_index(skin.joints, &(Enum.at(scene.nodes, &1).name == "head"))
        assert Enum.uniq(p.joints) == [{head, 0, 0, 0}] and Enum.uniq(p.weights) == [{1.0, 0.0, 0.0, 0.0}]
      else
        assert helmet == [] and not Map.has_key?(scene.materials, :helmet)
      end
    end

    # The color of a helmet when the order gives none.
    scene = Build.scene(Detail.with(:far, fn -> World.People.traveler("bicycle") end), level: :far)
    assert scene.materials[:helmet]["color"] == [236, 232, 222]
    # A person with no hair has a helmet too.
    bald = Build.scene(Detail.with(:far, fn -> World.People.traveler("motorbike", hair: nil) end), level: :far)
    assert Map.has_key?(bald.materials, :helmet)
  end

  test "a bigger head: a scale on the bone head, in the box and in the file" do
    big = Build.scene(Detail.with(:far, fn -> Human.person("p", head: 1.6) end), level: :far)
    normal = Build.scene(Detail.with(:far, fn -> Human.person("p") end), level: :far)
    assert %{scale: 1.6} = Enum.find(big.nodes, &(&1.name == "head"))
    assert Enum.all?(normal.nodes, &(&1.scale == 1.0))
    [_, _, h] = big.extras["size"]
    [_, _, h0] = normal.extras["size"]
    assert h > h0 + 0.05

    json = World.GLBHelper.json(World.GLB.encode(big))
    assert [%{"scale" => [1.6, 1.6, 1.6]}] = Enum.filter(json["nodes"], &Map.has_key?(&1, "scale"))
  end

  test "a traveler parked: the person stands next to the vehicle, and looks to the right" do
    for v <- World.People.vehicles() do
      scene = Build.scene(Detail.with(:far, fn -> World.People.traveler(v, [], "parked") end), level: :far)
      refute Map.has_key?(scene.materials, :helmet)
      frames = Scene.world_frames(scene)
      # The root of the person: the parent of its first bone.
      i = Enum.find(scene.nodes, &(&1.name == "Root")).parent
      # The front of the person (+y in its axes) is +x.
      {x, _, _} = World.Frame.dir(frames[i], {0.0, 1.0, 0.0})
      assert_in_delta x, 1.0, 1.0e-9
      [w, _, h] = scene.extras["size"]
      assert h > 1.5

      # The person stands out of the vehicle, at its right side.
      if v != "foot", do: assert(w > 0.9), else: assert(scene.extras["kind"] == "person")
      assert Enum.map(scene.animations, & &1.name) == ["wave", "point", "blink"]
    end
  end

  test "the camper is a van of the line: the driver sits in its seat, with the head under its roof" do
    # The camper of DIY stays as it was.
    assert {_, {-0.45, y, 1.15}, "drive", {x, -1.0}} = World.People.camper()
    assert_in_delta y, 1.1, 1.0e-9
    assert_in_delta x, 1.55, 1.0e-9

    for van <- ~w(promaster_118 sprinter_170_ext_high transit_148_medium) do
      m = World.Vehicles.Van.model(van)
      {_, {-0.45, y, 1.15}, "drive", {x, -1.0}} = World.People.camper(van)
      # The hips are in the cab: behind the front of the van, and less
      # than 1.5 m behind it.
      assert y < m["length"] / 2 - m["front"] and y > m["length"] / 2 - m["front"] - 1.5
      assert_in_delta x, m["width"] / 2 + 0.517, 1.0e-9

      scene = Build.scene(Detail.with(:far, fn -> World.People.traveler("camper", van: van) end), level: :far)
      [_, l, h] = scene.extras["size"]
      assert h < m["height"] + 0.01 and abs(l - m["length"]) < 0.06
    end

    parked =
      Build.scene(Detail.with(:far, fn -> World.People.traveler("camper", [van: "sprinter_144"], "parked") end),
        level: :far
      )

    assert parked.extras["kind"] == "vehicle"

    # On foot, the van is no part of the traveler.
    for scene <- ["ride", "parked"] do
      foot =
        Build.scene(Detail.with(:far, fn -> World.People.traveler("foot", [van: "sprinter_144"], scene) end),
          level: :far
        )

      assert foot.extras["kind"] == "person"
    end
  end

  test "a parked vehicle keeps its colors: the white of the van, not the red of the palette" do
    ride = Build.scene(Detail.with(:far, fn -> World.People.traveler("camper") end), level: :far)
    parked = Build.scene(Detail.with(:far, fn -> World.People.traveler("camper", [], "parked") end), level: :far)
    assert parked.materials[:paint] == ride.materials[:paint]
    assert parked.materials[:paint]["color"] == [240, 241, 238]
  end

  test "the parked traveler waves to the viewer and points to the front of the vehicle" do
    scene = Build.scene(Detail.with(:far, fn -> World.People.traveler("motorbike", [], "parked") end), level: :far)
    [wave, point, _blink] = scene.animations
    names = fn a -> Enum.map(a.channels, &Enum.at(scene.nodes, &1.node).name) |> Enum.sort() end
    # The wave: the right arm, the open hand and the head; the left side
    # does not move.
    assert ~w(clavicle_r head index_03_r lowerarm_r thumb_03_r upperarm_r) -- names.(wave) == []
    refute Enum.any?(names.(wave), &String.ends_with?(&1, "_l"))
    # The point: the left arm and hand, the body and the head.
    assert ~w(clavicle_l hand_l head lowerarm_l neck_01 pinky_03_l spine_02 upperarm_l) -- names.(point) == []
    refute Enum.any?(names.(point), &String.ends_with?(&1, "_r"))

    # Each clip plays once: it starts and stops in the pose of the scene.
    for a <- [wave, point], c <- a.channels do
      assert length(c.times) == 40 and List.last(c.times) == 2.6
      node = Enum.at(scene.nodes, c.node)

      for f <- [hd(c.values), List.last(c.values)],
          do: assert(World.Vec.len(World.Vec.sub(f.y, node.frame.y)) < 1.0e-9)
    end

    # The world at a time of a clip: its frames in the nodes.
    at = fn a, t ->
      k = Enum.find_index(hd(a.channels).times, &(abs(&1 - t) < 1.0e-9))

      nodes =
        Enum.reduce(a.channels, scene.nodes, fn c, nodes ->
          List.update_at(nodes, c.node, &%{&1 | frame: Enum.at(c.values, k)})
        end)

      frames = Scene.world_frames(%{scene | nodes: nodes})
      fn name -> frames[Enum.find_index(nodes, &(&1.name == name))].at end
    end

    # The left arm points up to the front of the vehicle (+y), a little to
    # the viewer (+x): the index finger is out, on the line of the arm,
    # and the other fingers are in the fist.
    pos = at.(point, 0.4)
    {dx, dy, dz} = World.Vec.sub(pos.("hand_l"), pos.("upperarm_l"))
    assert dy > 0.3 and dx > 0 and dx < dy and dz > 0.05
    {ix, iy, iz} = World.Vec.sub(pos.("index_03_l"), pos.("index_01_l"))
    assert iy > ix and iy > abs(iz)
    near = fn n -> World.Vec.len(World.Vec.sub(pos.(n), pos.("hand_l"))) end
    assert near.("middle_03_l") < near.("index_03_l") - 0.04

    # The right hand is over the shoulder.
    pos = at.(wave, 1.0)
    {_, _, dz} = World.Vec.sub(pos.("hand_r"), pos.("upperarm_r"))
    assert dz > 0.2
  end

  # About 40 s in CI, near the limit of 60 s on a slower computer.
  @tag timeout: 120_000
  test "a group at a morning of exercise: a leader in the mirror, and people in rows who face the leader" do
    # At far: a group at near takes four times as long to make.
    make = fn seed -> Detail.with(:far, fn -> World.People.exercise("tai_chi", count: 4, seed: seed) end) end
    group = make.(7)
    assert group == make.(7)
    refute group == make.(8)
    assert Enum.map(group.nodes, &elem(&1, 0)) == ~w(leader person_1 person_2 person_3 person_4)

    scene = Build.scene(group, level: :far)
    # One animation: the routine of the five people (and their blinks).
    [clip, %{name: "blink"}] = scene.animations
    assert clip.name == "tai_chi"
    roots = for {n, i} <- Enum.with_index(scene.nodes), n.name in ~w(leader person_1 person_2 person_3 person_4), do: i
    owners = clip.channels |> Enum.map(&owner(scene, &1.node, roots)) |> Enum.uniq() |> Enum.sort()
    assert owners == Enum.sort(roots)

    frames = Scene.world_frames(scene)
    face = fn name -> World.Frame.dir(frames[Enum.find_index(scene.nodes, &(&1.name == name))], {0.0, 1.0, 0.0}) end
    assert_in_delta elem(face.("leader"), 1), 1.0, 1.0e-9
    assert_in_delta elem(face.("person_1"), 1), -1.0, 1.0e-9
    # The people stand in front of the leader, in rows of three.
    {_, y1, _} = frames[Enum.find_index(scene.nodes, &(&1.name == "person_1"))].at
    {_, y4, _} = frames[Enum.find_index(scene.nodes, &(&1.name == "person_4"))].at
    assert y1 > 2.0 and y4 > y1 + 1.2

    # The ages of the routine.
    for {_, %{params: %{"age" => age}}, _} <- group.nodes, do: assert(age in 55..75)
    assert_raise ArgumentError, ~r/1 to 12 people/, fn -> World.People.exercise("yoga", count: 13) end
  end

  # The root node of the person of a node.
  defp owner(scene, i, roots) do
    if i in roots, do: i, else: owner(scene, Enum.at(scene.nodes, i).parent, roots)
  end

  test "speech: the teeth, the tongue and the 15 visemes as morph targets" do
    p = Human.person("talker", speech: true, blink: false, hair: nil, clothes: [])
    prims = for n <- p.nodes, pr <- n.primitives, do: pr
    names = World.People.Face.names()
    assert length(names) == 15 and hd(names) == "viseme_sil" and List.last(names) == "viseme_U"

    # The skin, the teeth and the tongue have the targets; the eyes have
    # none (the GLB gives them zeros).
    for role <- [:skin, :teeth, :tongue] do
      for pr <- Enum.filter(prims, &(&1.material == role)), do: assert(Enum.map(pr.targets, &elem(&1, 0)) == names)
    end

    assert Enum.find(prims, &(&1.material == :eyes)).targets == nil
    assert Map.has_key?(p.materials, :teeth) and Map.has_key?(p.materials, :tongue)

    # The silence moves nothing; "aa" opens the mouth: the chin goes down
    # by a centimeter or more, and the lower teeth with it.
    skin = Enum.find(prims, &(&1.material == :skin))
    move = &moves/2
    assert Enum.all?(move.(skin, "viseme_sil"), &(&1 == {0.0, 0.0, 0.0}))
    assert move.(skin, "viseme_aa") |> Enum.map(&elem(&1, 2)) |> Enum.min() < -0.01

    teeth =
      prims
      |> Enum.filter(&(&1.material == :teeth))
      |> Enum.map(&(move.(&1, "viseme_aa") |> Enum.map(fn d -> elem(d, 2) end) |> Enum.min()))

    assert Enum.min(teeth) < -0.005

    # The teeth of MakeHuman (with the gums), fit to the mouth: a shape,
    # not a flat strip (an arch more than 3 cm wide and 2 cm deep), with
    # a texture; the tongue in the arch.
    [tp] = Enum.filter(prims, &(&1.material == :teeth))
    [tongue] = Enum.filter(prims, &(&1.material == :tongue))
    {{x0, y0, z0}, {x1, y1, z1}} = World.Vec.bounds(tp.positions)
    assert x1 - x0 > 0.03 and y1 - y0 > 0.02 and z1 - z0 > 0.01 and length(tp.positions) > 1000
    {{tx0, _, _}, {tx1, _, _}} = World.Vec.bounds(tongue.positions)
    assert tx0 > x0 and tx1 < x1
    assert match?({"image/png", _}, p.materials.teeth["image"])

    # The tongue goes down with the jaw (the units of MakeHuman do not
    # move it), the tip more than the back; the upper teeth go down a
    # little (their tips show under the upper lip), less than the lower.
    down = fn pr -> pr |> move.("viseme_aa") |> Enum.map(&elem(&1, 2)) end
    assert Enum.max(down.(tongue)) < -0.003 and Enum.min(down.(tongue)) < Enum.max(down.(tongue)) - 0.001
    {_, {_, _, top}} = World.Vec.bounds(tp.positions)
    upper = for {{_, _, z}, d} <- Enum.zip(tp.positions, down.(tp)), z > top - 0.004, do: d
    assert Enum.max(upper) < -0.001 and Enum.max(upper) > Enum.min(down.(tp)) / 2

    # The shadow in the mouth: the front teeth are white in the colors of
    # the points, the back teeth dark; the teeth are ivory.
    {{_, back, _}, {_, front, _}} = World.Vec.bounds(tp.positions)
    shade = fn y -> for {{_, py, _}, {c, c, c}} <- Enum.zip(tp.positions, tp.colors), abs(py - y) < 0.002, do: c end
    assert Enum.max(shade.(front)) > 240 and Enum.max(shade.(back)) < 100
    assert p.materials.teeth["color"] == [232, 224, 208]

    json = World.GLBHelper.json(World.GLB.encode(Build.scene(p)))
    [mesh] = for m <- json["meshes"], m["extras"], do: m
    assert mesh["extras"]["targetNames"] == names and length(mesh["weights"]) == 15

    # A person with no speech has no teeth and no targets; two origins
    # mix the units of each.
    plain = Human.person("quiet", blink: false, hair: nil, clothes: [])
    assert Enum.all?(for(n <- plain.nodes, pr <- n.primitives, do: pr), &(&1.targets == nil and &1.material != :teeth))

    mean = fn race -> race |> World.People.Face.visemes() |> Enum.find(&(elem(&1, 0) == "viseme_aa")) |> elem(1) end
    {a, b, both} = {mean.(%{"asian" => 1.0}), mean.(%{"african" => 1.0}), mean.(%{"asian" => 1.0, "african" => 1.0})}
    {i, {x, _, _}} = Enum.find(both, fn {_, {x, _, _}} -> abs(x) > 0.01 end)
    assert_in_delta x, (elem(Map.get(a, i, {0.0, 0.0, 0.0}), 0) + elem(Map.get(b, i, {0.0, 0.0, 0.0}), 0)) / 2, 1.0e-9
  end

  test "the weights of the visemes for cues: the middle of each cue, silence at the ends and in a gap" do
    alias World.People.Face
    assert Face.talk([]) == []

    keys = Face.talk([{"PP", 0.0, 0.1}, {"aa", 0.1, 0.3}, {"sil", 0.3, 0.32}, {"O", 0.6, 0.8}], 0.8)

    assert keys == [
             {0.0, %{}},
             {0.05, %{"viseme_PP" => 0.8}},
             {0.2, %{"viseme_aa" => 0.8}},
             {0.31, %{}},
             {0.37, %{}},
             {0.55, %{}},
             {0.7, %{"viseme_O" => 0.8}},
             {0.9, %{}}
           ]
  end

  test "talk: the animation of the visemes for the cues of a voice" do
    cues = [{"PP", 0.1, 0.2}, {"aa", 0.2, 0.4}, {"sil", 0.4, 0.45}, {"viseme_O", 0.8, 1.0}]
    p = Human.person("talker", speech: true, blink: false, hair: nil, clothes: [], talk: cues)
    [%{name: "talk", channels: [c]}] = p.animations
    assert c.path == :weights and c.times == Enum.map(World.People.Face.talk(cues), &elem(&1, 0))

    # The weights of the targets of the mesh, in their order: "PP" at the
    # middle of its cue, 0 for the others.
    [skin] = for n <- p.nodes, pr <- n.primitives, pr.material == :skin, do: pr
    names = Enum.map(skin.targets, &elem(&1, 0))
    at = fn t -> Enum.zip(names, Enum.at(c.values, Enum.find_index(c.times, &(&1 == t)))) |> Map.new() end
    assert at.(0.15)["viseme_PP"] == 1.0 and at.(0.15)["viseme_aa"] == 0.0

    # With no speech, no animation talk.
    assert Human.person("quiet", blink: false, hair: nil, clothes: [], talk: cues).animations == []
  end

  test "the face at rest (relaxed by default, neutral, or a mix) and the blink" do
    lid = fn p ->
      [skin] = for n <- p.nodes, pr <- n.primitives, pr.material == :skin, do: pr
      skin
    end

    relaxed = Human.person("a", hair: nil, clothes: [])
    neutral = Human.person("b", face: "neutral", hair: nil, clothes: [])
    mix = Human.person("c", face: %{"eyeBlinkLeft" => 0.5}, hair: nil, clothes: [])

    # The relaxed face moves points of the face (the eyelids, the mouth);
    # a mix of the application moves them as it says.
    moved = fn a, b ->
      Enum.count(Enum.zip(lid.(a).positions, lid.(b).positions), fn {p, q} ->
        World.Vec.len(World.Vec.sub(p, q)) > 1.0e-4
      end)
    end

    assert moved.(relaxed, neutral) > 50 and moved.(mix, neutral) > 20

    # The blink: two targets, and each closes the eye of its side all the
    # way from the face at rest (the relaxed eyelids are 0.25 closed, so
    # the target moves 0.75 of the neutral one).
    names = Enum.map(lid.(relaxed).targets, &elem(&1, 0))
    assert names == ~w(eyeBlinkLeft eyeBlinkRight)
    size = fn p -> lid.(p) |> moves("eyeBlinkLeft") |> Enum.map(&World.Vec.len/1) |> Enum.max() end
    assert_in_delta size.(relaxed), 0.75 * size.(neutral), 1.0e-6

    # The animation blink: the weights of the targets of the mesh, closed
    # at 0.07 s to 0.12 s, open again at 0.27 s, a loop of 4 s.
    [%{name: "blink", channels: [c]}] = relaxed.animations
    assert Enum.at(relaxed.nodes, c.node).primitives != [] and c.path == :weights
    assert c.times == [0.0, 0.07, 0.12, 0.27, 4.0] and Enum.at(c.values, 1) == [1.0, 1.0] and hd(c.values) == [0.0, 0.0]

    # With no blink, no targets and no animation.
    still = Human.person("d", blink: false, hair: nil, clothes: [])
    assert lid.(still).targets == nil and still.animations == []
  end

  test "the skin: pores near, a sheen and less reflection at each level, darker and warmer creases" do
    p = Human.person("a", hair: nil, clothes: [])
    [skin] = for n <- p.nodes, pr <- n.primitives, pr.material == :skin, do: pr
    near = p.materials.skin
    assert {"image/png", <<137, 80, 78, 71, _::binary>>} = near["normal_image"]
    assert near["normal_image_scale"] == 60 and near["sheen"] == [170, 104, 97] and near["specular"] == 0.5

    for level <- [:mid, :far] do
      spec =
        Build.scene(Detail.with(level, fn -> Human.person("a", hair: nil, clothes: []) end), level: level).materials.skin

      assert spec["sheen"] == [170, 104, 97] and not Map.has_key?(spec, "normal_image")
    end

    # Each point has a color: white on most of the skin; in a crease
    # less green and blue than red (warm), and never darker than 0.75.
    assert length(skin.colors) == length(skin.positions)
    white = Enum.count(skin.colors, &(&1 == {255, 255, 255}))
    assert white > length(skin.colors) / 2
    dark = Enum.reject(skin.colors, &(&1 == {255, 255, 255}))
    assert dark != [] and Enum.all?(dark, fn {r, g, b} -> r >= b and b >= g and g >= round(255 * 0.75) end)

    # The texture of the pores: 128 pixels, the same bytes each time.
    assert World.People.Skin.pores() == near["normal_image"] |> elem(1)
    assert <<_::binary-size(16), 128::32, 128::32, 8, 2, _::binary>> = World.People.Skin.pores()
  end

  test "speech and expressions at mid and far: the body moves by its fit" do
    names = World.People.Face.names() ++ World.People.Face.shape_names()

    for level <- [:mid, :far] do
      p = Detail.with(level, fn -> Human.person("t", speech: true, expressions: true, clothes: ["shoes01"]) end)
      prims = for n <- p.nodes, pr <- n.primitives, do: pr
      [skin] = Enum.filter(prims, &(&1.material == :skin))
      assert Enum.map(skin.targets, &elem(&1, 0)) == names, "#{level}"
      refute Enum.any?(prims, &(&1.material == :teeth))

      # "aa" opens the mouth (the chin down by 5 mm or more). The colored
      # parts of the body (the shoes) have the targets too; the hair at
      # mid has none.
      aa = moves(skin, "viseme_aa")
      assert aa |> Enum.map(&elem(&1, 2)) |> Enum.min() < -0.005, "#{level}"
      assert Enum.find(prims, &(&1.material == :color_shoes01)).targets != nil

      # The eyes of few faces, with the texture of the eyes (dark brown by
      # default), and the eyebrows at mid.
      assert Enum.any?(prims, &(&1.material == :eyes)) and match?({_, _}, p.materials.eyes["image"])
      assert p.materials.eyes["image"] == {"image/png", File.read!(Data.asset("eye_materials", "darkbrown").texture)}
      assert Enum.any?(prims, &(&1.material == :eyebrows)) == (level == :mid)

      # The hole of the mouth of the low-poly body is closed by a dark
      # fan, which moves with the edge of the hole.
      hole = Enum.find(prims, &(&1.material == :hole))
      assert p.materials.hole["color"] == [40, 22, 24] and Enum.map(hole.targets, &elem(&1, 0)) == names
      open = moves(hole, "viseme_aa")
      assert open |> Enum.map(&elem(&1, 2)) |> Enum.min() < -0.005
      assert Enum.all?(Enum.filter(prims, &(&1.material == :hair)), &(&1.targets == nil)), "#{level}"
    end
  end

  test "expressions: the face shapes of ARKit; a blink closes the eyelashes of its side" do
    p = Human.person("face", expressions: true, clothes: [])
    prims = for n <- p.nodes, pr <- n.primitives, do: pr
    names = World.People.Face.shape_names()
    assert length(names) == 30 and "eyeBlinkLeft" in names and "mouthSmileRight" in names and "jawOpen" in names

    for role <- [:skin, :teeth, :tongue, :eyebrows, :eyelashes] do
      for pr <- Enum.filter(prims, &(&1.material == role)), do: assert(Enum.map(pr.targets, &elem(&1, 0)) == names)
    end

    assert Enum.find(prims, &(&1.material == :eyes)).targets == nil

    # The eyebrows and the eyelashes have soft strands (a blend); the hair
    # is in two passes: with a cut of its alpha, then with a blend.
    for role <- [:eyebrows, :eyelashes], do: assert(p.materials[role]["alpha_mode"] == "BLEND")
    assert p.materials.hair["alpha_mode"] == "MASK" and p.materials.hair_edge["alpha_mode"] == "BLEND"
    [hair] = Enum.filter(prims, &(&1.material == :hair))
    [edge] = Enum.filter(prims, &(&1.material == :hair_edge))
    assert edge.positions == hair.positions and edge.targets == hair.targets
    json = World.GLBHelper.json(World.GLB.encode(Build.scene(p)))
    assert Enum.find(json["materials"], &(&1["name"] == "eyebrows"))["alphaMode"] == "BLEND"

    # The eyes have no cornea (MakeHuman draws it clear; it maps to a black
    # disk in the corner of the texture): the iris shows.
    eyes = Enum.find(prims, &(&1.material == :eyes))
    refute Enum.any?(eyes.uvs, fn {u, v} -> u > 0.85 and v > 0.85 end)

    # The left eye of the person is at -x in World: its blink moves its
    # eyelashes down (2 mm or more), and not the eyelashes of the right eye.
    lashes = Enum.find(prims, &(&1.material == :eyelashes))
    blink = moves(lashes, "eyeBlinkLeft")
    moved = for {{x, _, _}, {_, _, dz}} <- Enum.zip(lashes.positions, blink), do: {x, dz}
    assert Enum.any?(moved, fn {x, dz} -> x < 0 and dz < -0.002 end)
    assert Enum.all?(moved, fn {x, dz} -> x < 0 or dz == 0.0 end)

    # A smile of one side moves the corner of the mouth of that side up.
    skin = Enum.find(prims, &(&1.material == :skin))
    smile = moves(skin, "mouthSmileRight")
    ups = for {{x, _, _}, {_, _, dz}} <- Enum.zip(skin.positions, smile), dz > 0.001, do: x
    assert ups != [] and Enum.all?(ups, &(&1 > -0.005))
  end

  test "a child and a baby: the shapes of MakeHuman for the height of the age, with the mean muscle" do
    o = %{gender: 1.0, age: 10, muscle: 0.9, weight: 0.5, height: 0.5, race: %{"asian" => 1.0}}
    weights = fn opts -> Map.new(Human.target_weights(Map.merge(o, opts))) end

    # A boy of 10 years is 78% of the height of a man (the CDC): mostly the child of MakeHuman (81%), a little of
    # the baby, with the mean muscle only.
    child = weights.(%{})
    assert child["asian-male-child"] > 0.85 and child["asian-male-baby"] < 0.15
    assert child["universal-male-child-averagemuscle-averageweight"] == child["asian-male-child"]
    refute Enum.any?(child, fn {name, _} -> String.contains?(name, ["young", "old", "maxmuscle"]) end)

    # A boy grows fast and then stops: at 16 years he is almost a man, with the muscle of the adult part.
    teen = weights.(%{age: 16})
    assert teen["asian-male-young"] > 0.8 and teen["universal-male-young-maxmuscle-averageweight"] > 0.3
    # Between a baby and a child; an age of 1 year or less is mostly the baby of MakeHuman (its height is of a
    # baby of about 6 months: 37% of the man); from 25 years, the young and the old adult.
    small = weights.(%{age: 4})
    assert small["asian-male-baby"] > 0.3 and small["asian-male-child"] > 0.3
    assert_in_delta small["asian-male-baby"] + small["asian-male-child"], 1.0, 1.0e-9
    assert weights.(%{age: 0}) == weights.(%{age: 1}) and weights.(%{age: 0})["asian-male-baby"] > 0.85
    assert_in_delta weights.(%{age: 25})["asian-male-young"], 1.0, 1.0e-9

    # The bust is a shape of the adult part of a girl: a child has none.
    girl = Human.target_weights(Map.merge(o, %{gender: 0.0, age: 14, bust: 1.0}))
    assert Enum.any?(girl, fn {name, _} -> String.starts_with?(name, "breast/female-young-") end)
    refute Enum.any?(girl, fn {name, _} -> String.starts_with?(name, "breast/female-child") end)

    refute Enum.any?(
             Human.target_weights(Map.merge(o, %{gender: 0.0, age: 8, bust: 1.0})),
             &String.starts_with?(elem(&1, 0), "breast/")
           )

    # Each target of these weights is in the data.
    for age <- [1, 4, 10, 16],
        {name, _} <- Human.target_weights(%{o | age: age}),
        do: assert(World.People.Data.target(name))
  end

  # At mid and far a person has no texture on its clothes. An item of many colors (the work suit: blue
  # overalls over a white shirt) gives each point the color of its swatch at the place of the item over
  # it (scripts/swatches.py), not one mean color. An order with a color of the item tints them,
  # as at near. A garment of World is of one fabric: one color, in its material.
  test "at mid and far each item of clothes keeps its colors: the colors of its texture at the points under it" do
    prims = fn level, opts ->
      figure = Detail.with(level, fn -> Human.person("p", [hair: nil] ++ opts) end)
      {figure.nodes |> List.last() |> Map.fetch!(:primitives), figure.materials}
    end

    luma = fn {r, g, b} -> 0.3 * r + 0.6 * g + 0.1 * b end

    for level <- [:mid, :far] do
      {ps, materials} = prims.(level, clothes: ["male_worksuit01", "world_t_shirt"])
      suit = Enum.find(ps, &(&1.material == :color_male_worksuit01))
      assert length(suit.colors) == length(suit.positions)
      lights = Enum.map(suit.colors, luma)
      # The blue overalls and the white shirt: a spread of the light of the points.
      assert Enum.max(lights) - Enum.min(lights) > 80, "#{level}"
      assert materials[:color_male_worksuit01]["color"] == [255, 255, 255]

      # The garment of World has no colors at its points, and the color of its fabric in its material.
      shirt = Enum.find(ps, &(&1.material == :color_world_t_shirt))
      assert shirt == nil or shirt.colors == nil
    end

    # A color of the order tints the points (red: more red than green and blue at each point).
    {ps, _} = prims.(:mid, clothes: ["male_worksuit01"], clothes_colors: [[192, 48, 32]])
    red = Enum.find(ps, &(&1.material == :color_male_worksuit01))
    assert Enum.all?(red.colors, fn {r, g, b} -> r >= g and r >= b end)
  end

  # A print of an order (`clothes_options`): the colors of the print at the points of the item at near (over
  # the mean color of its texture, with a white material), and at the points of the body under it at mid
  # and far. The color of the item is the ground of the print.
  test "an item with a print of checks or stripes: two colors at each level" do
    prims = fn level, opts ->
      figure = Detail.with(level, fn -> Human.person("p", [hair: nil, clothes_colors: [[40, 40, 40]]] ++ opts) end)
      {figure.nodes |> List.last() |> Map.fetch!(:primitives), figure.materials}
    end

    print = %{print: "stripes", print_size: 0.03, print_color: [230, 230, 230]}

    # (At near over the mean color of the fabric, 230: 40 is 44, and 230 is 255.)
    for {level, role, colors} <- [
          {:near, :clothes_world_swim_trunks, [{44, 44, 44}, {255, 255, 255}]},
          {:mid, :color_world_swim_trunks, [{40, 40, 40}, {230, 230, 230}]},
          {:far, :color_world_swim_trunks, [{40, 40, 40}, {230, 230, 230}]}
        ] do
      {ps, materials} = prims.(level, clothes: ["world_swim_trunks"], clothes_options: [print])
      trunks = Enum.find(ps, &(&1.material == role))
      assert trunks.colors |> Enum.uniq() |> Enum.sort() == colors, "#{level}"
      assert materials[role]["color"] == [255, 255, 255]
    end

    # An item of MakeHuman takes a print too; with no print, the item has its colors as before.
    {ps, _} = prims.(:near, clothes: ["shoes01"], clothes_options: [%{print: "checks", print_size: 0.01}])
    assert Enum.find(ps, &(&1.material == :clothes_shoes01)).colors |> Enum.uniq() |> length() == 2
    {ps, materials} = prims.(:near, clothes: ["world_swim_trunks"], clothes_options: [%{print: "plain"}])
    assert Enum.find(ps, &(&1.material == :clothes_world_swim_trunks)).colors == nil
    assert materials[:clothes_world_swim_trunks]["color"] != [255, 255, 255]
  end

  # A loose part of an item (2.5 cm or more out of the body) is its own mesh at mid and far, so the form of
  # a tunic, of the legs of wide pants and of a hood shows, not only their colors.
  test "the form of a loose garment and of a hood at mid and far" do
    scene = fn opts, level ->
      Build.scene(Detail.with(level, fn -> Human.person("p", [hair: nil, pose: "stand"] ++ opts) end), level: level)
    end

    # The depth (front to back) of the person at the hips and the thighs, under the hands.
    depth = fn opts, level ->
      ys = for n <- scene.(opts, level).nodes, p <- n.primitives, {_, y, z} <- p.positions, z > 0.6 and z < 0.8, do: y
      Enum.max(ys) - Enum.min(ys)
    end

    tunic = [clothes: ["world_ao_canh", "world_quan_ong_rong"], clothes_options: [%{print: "checks", print_size: 0.05}]]
    bare = depth.([clothes: []], :near)
    near = depth.(tunic, :near)

    for level <- [:mid, :far] do
      s = scene.(tunic, level)
      prims = Enum.flat_map(s.nodes, & &1.primitives)
      # The tunic is a color on the body and a mesh of its own; the faces of the body under it go.
      assert [_, part] = Enum.filter(prims, &(&1.material == :color_world_ao_canh))
      # (The loose part has the colors of the print of the order.)
      assert part.colors |> Enum.uniq() |> length() == 2
      assert s.materials[:color_world_ao_canh]["double_sided"]
      # The tunic hangs out of the body as at near (within 2 cm), and the person stays in its budget.
      assert_in_delta depth.(tunic, level), near, 0.02
      assert depth.(tunic, level) > bare + 0.04
      assert Scene.triangles(s) < %{mid: 8_500, far: 2_000}[level]
    end

    # The hood up on the head: at mid and far the person is as high as at near, 3 to 5 cm over the head.
    top = fn opts, level ->
      {_, {_, _, z}} = Scene.bounds(scene.(opts, level))
      z
    end

    up = [clothes: ["world_rain_shell"], clothes_options: [%{hood: "up"}]]
    head = top.([clothes: []], :near)
    assert top.(up, :near) - head > 0.03 and top.(up, :near) - head < 0.05

    for level <- [:mid, :far] do
      assert_in_delta top.(up, level), top.(up, :near), 0.01
      # The hood down: a loose part at the back of the neck (with the hem of the shell at the hips).
      s = scene.([clothes: ["world_rain_shell"]], level)
      [_, loose] = s.nodes |> Enum.flat_map(& &1.primitives) |> Enum.filter(&(&1.material == :color_world_rain_shell))
      assert Enum.count(loose.positions, fn {_, y, z} -> y < -0.05 and z > 0.8 * head end) > 4
    end
  end

  test "a child has a flat chest: the shirt over the nipples is not in front of the shirt over the sternum" do
    nipples =
      for {v, d} <- World.People.Data.target("breast/nipple-point-decr"),
          v < 13_380,
          World.Vec.len(d) > 0.01,
          into: MapSet.new(),
          do: v

    # How far the shirt over the nipples is in front of the shirt over the sternum, at the same height (m).
    over = fn gender, age ->
      [{_, _, items}] = Human.dressed(gender: gender, age: age, clothes: ["world_t_shirt"])
      at_nipples = for {v, {_, y, z}, _} <- items, MapSet.member?(nipples, v), do: {y, z}
      {y, _} = hd(at_nipples)
      sternum = for {_, {x, ys, z}, _} <- items, abs(x) < 0.05, abs(ys - y) < 0.1, z > 0, do: z
      (Enum.max(Enum.map(at_nipples, &elem(&1, 1))) - Enum.max(sternum)) / 10
    end

    # The shapes of a child of MakeHuman have a small bust, 6 to 8 mm in front of the sternum under a shirt.
    for {gender, age} <- [{0.0, 6}, {1.0, 9}, {0.0, 12}], do: assert(over.(gender, age) < 0, "#{gender} #{age}")
    # A man has the muscles of his chest; from 16 years the chest is as MakeHuman makes it.
    assert over.(1.0, 30) > 0.004 and over.(1.0, 16) > 0.004
  end

  test "a child has the height of its age, the head of a real child, the face and the skin of a child" do
    # The height: the median of the CDC for the age, as a part of the height of the adult of World.
    assert_in_delta Human.growth(10, 1.0), 138.6 / 176.8, 1.0e-9
    assert_in_delta Human.growth(6.5, 0.0), (114.7 + 121.5) / 2 / 163.3, 1.0e-9
    assert Human.growth(0, 1.0) == Human.growth(1, 1.0) and Human.growth(40, 0.0) == 1.0

    size = fn opts -> Build.scene(Detail.with(:far, fn -> Human.person("p", opts) end), level: :far) end
    [_, _, man] = size.(age: 30, gender: 1.0).extras["size"]
    [_, _, woman] = size.(age: 30, gender: 0.0).extras["size"]

    for {age, gender, adult} <- [{2, 1.0, man}, {6, 0.0, woman}, {9, 1.0, man}, {12, 0.0, woman}, {16, 1.0, man}] do
      scene = size.(age: age, gender: gender)
      [_, _, h] = scene.extras["size"]
      assert_in_delta h / adult, Human.growth(age, gender), 0.03, "#{age} #{gender}"
      # The head of a child is larger than the head of the shape of its height: the scale of its bone.
      assert Enum.find(scene.nodes, &(&1.name == "head")).scale == Human.child_head(age, gender)
    end

    assert Human.child_head(6, 1.0) > 1.1 and Human.child_head(12, 1.0) > Human.child_head(16, 1.0)
    assert Human.child_head(18.25, 1.0) == 1.0 and Human.child_head(30, 0.0) == 1.0

    # The height of the head, chin to top, of a child of 6 and of a man: 86% in the 1977 study (18.4 cm of 21.4 cm).
    head = fn age ->
      figure = Detail.with(:near, fn -> Human.person("p", age: age, gender: 1.0, hair: nil, clothes: []) end)
      skin = figure.nodes |> List.last() |> Map.fetch!(:primitives) |> Enum.find(&(&1.material == :skin))
      bone = Enum.find_index(figure.skins |> hd() |> Map.fetch!(:joints), &(Enum.at(figure.nodes, &1).name == "head"))

      zs =
        for {{_, _, z}, js, ws} <- Enum.zip([skin.positions, skin.joints, skin.weights]),
            {j, w} <- Enum.zip(Tuple.to_list(js), Tuple.to_list(ws)),
            j == bone and w > 0.9,
            do: z

      (Enum.max(zs) - Enum.min(zs)) * Human.child_head(age, 1.0)
    end

    assert_in_delta head.(6) / head.(30), 0.86, 0.04

    # The face and the body of a child: the younger head of MakeHuman, large eyes, full cheeks, no muscle
    # on the chest; less at 12 years, none for an adult. The option shape comes after them.
    o = %{gender: 1.0, age: 4, muscle: 0.5, weight: 0.5, height: 0.5, race: %{"asian" => 1.0}}
    face = fn opts -> Map.new(Human.target_weights(Map.merge(o, opts))) end
    assert face.(%{})["head/head-age-decr"] == 1.0 and face.(%{})["eyes/l-eye-scale-incr"] == 0.5
    assert_in_delta face.(%{age: 12})["head/head-age-decr"], 0.3, 1.0e-9
    refute Map.has_key?(face.(%{age: 30}), "head/head-age-decr")
    refute Map.has_key?(face.(%{shape: %{"head-age-decr-incr" => 0.0}}), "head/head-age-decr")
    assert Human.youth(5) == 1.0 and Human.youth(15) == 0.0 and Human.youth(10) == 0.5

    # The skin of a boy is the skin of a girl of the same origin (the skin of a man has the shadow of a beard).
    boy = Detail.with(:far, fn -> Human.person("p", age: 8, skin: "young_asian_male") end)
    assert Enum.any?(boy.sources, &(&1 =~ "young_asian_female"))
    man = Detail.with(:far, fn -> Human.person("p", age: 30, skin: "young_asian_male") end)
    assert Enum.any?(man.sources, &(&1 =~ "young_asian_male"))
    assert Detail.with(:far, fn -> Human.person("p", age: 8, skin: "young_asian_female") end).sources
  end

  test "the numbers of a person give the weights of the targets" do
    o = %{gender: 0.25, age: 90, muscle: 0.25, weight: 0.75, height: 0.25, race: %{"asian" => 2.0, "african" => 2.0}}
    weights = Map.new(Human.target_weights(o))
    assert_in_delta weights["asian-female-old"], 0.375, 1.0e-9
    assert_in_delta weights["universal-male-old-minmuscle-maxweight"], 0.25 * 0.5 * 0.5, 1.0e-9
    assert_in_delta weights["height/female-old-averagemuscle-averageweight-minheight"], 0.75 * 0.5 * 0.5 * 0.5, 1.0e-9
    refute Map.has_key?(weights, "asian-female-young")

    tall = Map.new(Human.target_weights(%{o | height: 1.0}))
    assert_in_delta tall["height/male-old-minmuscle-averageweight-maxheight"], 0.25 * 0.5 * 0.5, 1.0e-9

    # The shape: with no options, the shape of MakeHuman.
    refute Enum.any?(weights, fn {name, _} -> String.contains?(name, ["breast/", "-decr", "-incr"]) end)

    shaped =
      Map.new(
        Human.target_weights(
          Map.merge(o, %{
            bust: 1.0,
            firmness: 0.25,
            waist: 0.0,
            arms: 0.75,
            shape: %{"measure-calf-circ-decr-incr" => -0.4}
          })
        )
      )

    # 0.75 a woman, old, half minmuscle, half maxweight, the max cup, half minfirmness.
    assert_in_delta shaped["breast/female-old-minmuscle-maxweight-maxcup-minfirmness"], 0.75 * 0.5 * 0.5 * 0.5, 1.0e-9

    assert_in_delta shaped["breast/female-old-minmuscle-maxweight-maxcup-averagefirmness"],
                    0.75 * 0.5 * 0.5 * 0.5,
                    1.0e-9

    assert shaped["torso/measure-waist-circ-decr"] == 1.0
    assert shaped["arms/l-lowerarm-fat-incr"] == 0.5 and shaped["arms/r-lowerarm-fat-incr"] == 0.5
    assert_in_delta shaped["legs/measure-calf-circ-decr"], 0.4, 1.0e-9

    assert_raise ArgumentError, ~r/no slider/, fn -> Human.target_weights(Map.put(o, :shape, %{"wings" => 1.0})) end
  end

  test "each slider of MakeHuman has its targets in the data" do
    for {name, s} <- Data.sliders(), t <- s.decr ++ s.incr do
      assert Data.target(t) != [], "#{name}: #{t}"
    end

    assert map_size(Data.sliders()) == 234
  end

  test "the options of the shape move the body" do
    skin = fn opts ->
      woman =
        Detail.with(:near, fn -> Human.person("w", [gender: 0.0, hair: nil, clothes: [], pose: "stand"] ++ opts) end)

      woman.nodes
      |> List.last()
      |> Map.fetch!(:primitives)
      |> Enum.find(&(&1.material == :skin))
      |> Map.fetch!(:positions)
    end

    base = skin.([])
    # The front of the torso, with no arms (World: y to the front), the width of the waist and of the hips (x).
    front = fn ps ->
      ps
      |> Enum.filter(fn {x, _, z} -> abs(x) < 0.12 and z > 1.0 and z < 1.45 end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.max()
    end

    # The mean width: the arms do not move.
    width = fn ps, {lo, hi} ->
      xs = for {x, _, z} <- ps, abs(x) < 0.25 and z > lo and z < hi, do: abs(x)
      Enum.sum(xs) / length(xs)
    end

    assert front.(skin.(bust: 1.0)) > front.(base) + 0.01
    assert width.(skin.(waist: 0.0), {1.0, 1.05}) < width.(base, {1.0, 1.05})
    assert width.(skin.(hips: 1.0), {0.85, 0.95}) > width.(base, {0.85, 0.95})

    # Each other short name moves some points more than 5 mm, at 0 and at 1.
    for {name, _} <- Human.shapes(), name not in [:bust, :firmness], v <- [0.0, 1.0] do
      moved = Enum.zip_with(skin.([{name, v}]), base, &World.Vec.len(World.Vec.sub(&1, &2)))
      assert Enum.max(moved) > 0.005, "#{name} #{v}"
    end

    # A slider of the map shape, and the map wins over the short name.
    assert skin.(shape: %{"measure-neck-circ-decr-incr" => 1.0}) == skin.(neck: 1.0)
    assert skin.(neck: 1.0, shape: %{"measure-neck-circ-decr-incr" => 0.0}) == base
  end

  test "the 4 largest weights" do
    assert Human.top4([{3, 0.1}, {1, 0.4}, {2, 0.2}, {5, 0.1}, {4, 0.2}, {6, -0.5}]) ==
             [{1, 0.4 / 0.9}, {2, 0.2 / 0.9}, {4, 0.2 / 0.9}, {3, 0.1 / 0.9}]

    assert Human.top4([{3, -0.2}, {4, 0.0}]) == [{0, 1.0}]
  end

  test "a person with no hair, a woman, a pose and an axis" do
    woman = Detail.with(:mid, fn -> Human.person("w", gender: 0.0, hair: nil, clothes: [], pose: "sit") end)
    assert %Figure{kind: :person} = woman
    assert %Figure{name: "p", params: %{"gender" => 1.0}} = Detail.with(:far, fn -> Human.person("p") end)
    refute Map.has_key?(woman.materials, :hair)
    assert Figure.port!(woman, "hips").name == "hips"
    assert_raise ArgumentError, ~r/no port "seat"/, fn -> Figure.port!(woman, "seat") end
    assert Human.to_world({1.0, 2.0, 3.0}) == {-0.1, 0.30000000000000004, 0.2}
  end

  test "the poses and the animations" do
    assert Pose.names() == ["drive", "rest", "ride", "ride_bicycle", "sit", "stand"]
    assert Pose.resolve(%{"a" => []}) == %{"a" => []}
    assert_raise ArgumentError, ~r/unknown pose/, fn -> Pose.resolve("fly") end
    assert_raise ArgumentError, ~r/unknown animation/, fn -> Pose.animation("fly", []) end
  end

  describe "the data of MakeHuman" do
    test "an OBJ file" do
      obj = Data.parse_obj("# a\nv 0 0 0\nv 1 0 x\nvt 0 1\nusemtl m\ng a\nf 1/1 2/1 1/1\ng b\nf 1 2 1\n\n")
      assert obj.points == {{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}}
      assert obj.uvs == {{0.0, 1.0}}
      assert obj.groups == %{"a" => [[{0, 0}, {1, 0}, {0, 0}]], "b" => [[{0, nil}, {1, nil}, {0, nil}]]}
    end

    test "a fit file" do
      text = """
      # a comment
      name a
      x_scale 1 2 0.5
      verts 0
      material a.mhmat
      1 2 3 0.5 0.25 0.25 0.1 0.2 0.3
      7

      delete_verts
      10 - 12 20
      30
      """

      fit = Data.parse_fit(text)
      assert fit.scales == %{"x_scale" => {1, 2, 0.5}}
      assert fit.refs == {{[1, 2, 3], [0.5, 0.25, 0.25], {0.1, 0.2, 0.3}}, {[7], [1.0], {0.0, 0.0, 0.0}}}
      assert fit.delete == MapSet.new([10, 11, 12, 20, 30])

      # The words after the references end them.
      assert tuple_size(Data.parse_fit("verts 0\n7\nmaterial b\n8\n").refs) == 1
    end

    test "the targets and the assets" do
      # (856 targets of an adult, and 48 of a child and of a baby.)
      assert map_size(Data.targets()) == 904
      [{i, {dx, _, _}} | _] = Data.target("asian-male-young")
      assert is_integer(i) and is_float(dx)
      # The memory keeps the index of the pack, not the targets (21 MB): a person reads only its targets,
      # those of a child too.
      assert :erts_debug.flat_size(Data.targets()) * 8 < 300_000
      assert Data.load_targets(["asian-male-child", "universal-female-baby-averagemuscle-averageweight"]) == :ok
      assert [{_, {_, _, _}} | _] = Data.target("asian-male-child")

      # The pack (scripts/targets.exs): its header, the index of each name (its place and its length), then
      # each target compressed alone.
      table = %{"b" => {<<1, 0>>, <<2, 0>>, <<3, 0>>, <<4, 0>>}, "a" => {<<5, 0>>, <<6, 0>>, <<7, 0>>, <<8, 0>>}}
      pack = Data.pack_targets(table)
      assert <<"XTP1", 2::little-32, 22::little-32, index::binary-size(22), _::binary>> = pack
      <<1::little-16, "a", at::little-32, n::little-32, 1::little-16, "b", _::binary>> = index
      assert :zlib.uncompress(binary_part(pack, at, n)) == <<5, 0, 6, 0, 7, 0, 8, 0>>
      assert Data.asset("eye_materials", "brown").mesh == nil
      assert Data.asset("skins", "young_asian_male").texture =~ ".jpg"
      assert_raise ArgumentError, ~r/no asset/, fn -> Data.asset("hair", "none") end
      assert Data.dir() =~ "priv/makehuman"
    end
  end

  test "each level of a person stands on the ground and is as high: soles under the shoes, and the form of the hair at far" do
    scene = fn opts, level -> Build.scene(Detail.with(level, fn -> Human.person("p", opts) end), level: level) end

    for opts <- [
          [clothes: ["mindfront_shoes_biker_boots_male"]],
          [gender: 0.0, hair: "bob01"],
          [hair: "afro01"],
          [hair: nil, clothes: []],
          [age: 8, gender: 0.0, pose: "stand"]
        ] do
      [{near_lo, near_hi} | low] = for level <- [:near, :mid, :far], do: Scene.bounds(scene.(opts, level))
      height = elem(near_hi, 2) - elem(near_lo, 2)

      # The near level stands on the ground: the shoes, also where a heel of the body is under the sole of a
      # shoe (2 mm for the shoes of the woman). The lowest point of mid and far is the lowest point of near
      # within 2 mm (the shoes are a color on the feet at mid and far: 2.9 cm for these boots; a low-poly
      # foot can go 3 mm under a bare foot), and the heights agree within 0.5 % (the top of the hair at far
      # was 1.7 % lower for afro01).
      assert_in_delta elem(near_lo, 2), 0.0, 0.001, inspect(opts)

      for {lo, hi} <- low do
        assert_in_delta elem(lo, 2), elem(near_lo, 2), 0.002, inspect(opts)
        assert_in_delta (elem(hi, 2) - elem(lo, 2)) / height, 1.0, 0.005, inspect(opts)
      end
    end

    # A person at far is about 1 600 triangles: the eyes in 24, the hair in 80 at the most (and the loose
    # parts of the clothes: 86 for the suit and the shoes of the defaults).
    far = scene.([gender: 0.0, hair: "long01"], :far)
    assert Scene.triangles(far) < 1_700
    prims = Enum.flat_map(far.nodes, & &1.primitives)
    assert [eyes] = Enum.filter(prims, &(&1.material == :eyes))
    assert length(eyes.indices) == 72 and length(eyes.uvs) == length(eyes.positions)
    # Long hair is long: a primitive in the color of the hair goes down from the head to the back, and its
    # material is seen from the two sides.
    assert [_scalp, hair] = Enum.filter(prims, &(&1.material == :color_long01))
    assert div(length(hair.indices), 3) in 40..80
    zs = Enum.map(hair.positions, &elem(&1, 2))
    {_, {_, _, top}} = Scene.bounds(far)
    assert Enum.max(zs) > top - 0.04 and Enum.min(zs) < top - 0.4
    assert far.materials[:color_long01]["double_sided"]
    refute far.materials[:skin]["double_sided"]
  end
end
