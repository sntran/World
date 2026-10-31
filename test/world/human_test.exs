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
    move = fn pr, name -> pr.targets |> Enum.find(&(elem(&1, 0) == name)) |> elem(1) end
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
    size = fn p -> lid.(p).targets |> hd() |> elem(1) |> Enum.map(&World.Vec.len/1) |> Enum.max() end
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
      {_, aa} = Enum.find(skin.targets, &(elem(&1, 0) == "viseme_aa"))
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
      {_, open} = Enum.find(hole.targets, &(elem(&1, 0) == "viseme_aa"))
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
    {_, blink} = Enum.find(lashes.targets, &(elem(&1, 0) == "eyeBlinkLeft"))
    moved = for {{x, _, _}, {_, _, dz}} <- Enum.zip(lashes.positions, blink), do: {x, dz}
    assert Enum.any?(moved, fn {x, dz} -> x < 0 and dz < -0.002 end)
    assert Enum.all?(moved, fn {x, dz} -> x < 0 or dz == 0.0 end)

    # A smile of one side moves the corner of the mouth of that side up.
    skin = Enum.find(prims, &(&1.material == :skin))
    {_, smile} = Enum.find(skin.targets, &(elem(&1, 0) == "mouthSmileRight"))
    ups = for {{x, _, _}, {_, _, dz}} <- Enum.zip(skin.positions, smile), dz > 0.001, do: x
    assert ups != [] and Enum.all?(ups, &(&1 > -0.005))
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
      assert map_size(Data.targets()) == 120
      [{i, {dx, _, _}} | _] = Data.target("asian-male-young")
      assert is_integer(i) and is_float(dx)
      assert Data.asset("eye_materials", "brown").mesh == nil
      assert Data.asset("skins", "young_asian_male").texture =~ ".jpg"
      assert_raise ArgumentError, ~r/no asset/, fn -> Data.asset("hair", "none") end
      assert Data.dir() =~ "priv/makehuman"
    end
  end
end
