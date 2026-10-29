defmodule World.AnimalsTest do
  use ExUnit.Case, async: true

  alias World.{Animals, Build, Figure, Frame, Joint, Limb, Part, Rig, Scene, Vec}
  alias World.People.Skeleton

  # A figure in a module attribute is a literal in the code of the test:
  # slow to compile. The dog is made once for the tests.
  setup_all do
    {:ok, dog: Animals.animal("street_dog", animations: ["walk", "wag"])}
  end

  defp world(scene, name) do
    frames = Scene.world_frames(scene)
    frames[Enum.find_index(scene.nodes, &(&1.name == name))]
  end

  test "a street dog: its size, its skin and its materials", %{dog: dog} do
    scene = Build.scene(dog)
    [w, l, h] = scene.extras["size"]
    assert_in_delta w, 0.23, 0.05
    assert_in_delta l, 0.84, 0.1
    assert_in_delta h, 0.67, 0.05
    {{_, _, ground}, _} = Scene.bounds(scene)
    assert_in_delta ground, 0.0, 0.01
    assert scene.extras["kind"] == "animal"
    # The materials of the mesh of the template (a Shiba Inu).
    assert Map.keys(scene.materials) |> Enum.sort() == [:dark, :eye, :fur, :iris, :marking, :white]

    for p <- Enum.flat_map(scene.nodes, & &1.primitives), w <- p.weights do
      assert_in_delta Enum.sum(Tuple.to_list(w)), 1.0, 1.0e-9
    end

    big = Build.scene(Animals.animal("street_dog", size: 1.2))
    assert_in_delta Enum.at(big.extras["size"], 2), 1.2 * h, 0.01
    # A coat with no markings is the color of the material of the fur.
    brown = Animals.animal("street_dog", coat: [10, 20, 30])
    assert brown.materials.fur["color"] == [10, 20, 30] and brown.params["coat"] == [10, 20, 30]
    [fur] = for n <- brown.nodes, p <- n.primitives, p.material == :fur, do: p
    assert fur.colors == nil
  end

  test "the joints, the limbs and the ports of the dog", %{dog: dog} do
    assert "tail.spread" in Figure.values(dog) and "hock_r" in Figure.values(dog)
    assert Figure.limbs(dog) == ~w(front_l front_r head hind_l hind_r tail)

    rest = Build.scene(dog)
    wag = Build.scene(dog, pose: %{"tail.spread" => 40})
    assert elem(world(wag, "tail_03").at, 0) > elem(world(rest, "tail_03").at, 0) + 0.05
    up = Build.scene(dog, pose: %{"tail.flex" => 30})
    assert elem(world(up, "tail_03").at, 2) > elem(world(rest, "tail_03").at, 2)

    # A paw to a point: the front leg reaches to the front.
    to = Vec.add(dog.skeleton.rest["front_foot_l"].at, {0.0, 0.06, 0.08})
    reach = Build.scene(dog, targets: %{"front_l" => to})
    assert Vec.len(Vec.sub(world(reach, "front_foot_l").at, to)) < 1.0e-3

    {_, y, z} = Figure.port_frame(dog, "collar").at
    assert y > 0.15 and z > 0.4
    assert Figure.port!(dog, "mouth").bone == "head"
    assert Figure.port!(dog, "ground").bone == nil
  end

  # The frames of the bones in the axes of the animal at each time of a
  # clip.
  defp frames(%{skeleton: s}, clip) do
    for k <- 0..(length(hd(clip.channels).times) - 1) do
      s.bones
      |> Enum.with_index(1)
      |> Map.new(fn {b, i} ->
        f =
          for c <- clip.channels, c.node == i, reduce: s.local[b.name] do
            f when c.path == :rotation -> %{Enum.at(c.values, k) | at: f.at}
            f -> %{f | at: Enum.at(c.values, k)}
          end

        {b.name, f}
      end)
      |> then(&Skeleton.world(s, &1))
    end
  end

  # The height of each foot over its height at rest (a part of the height
  # of the pelvis) at each time of a clip: the lowest point of its skin
  # (the points that the foot moves most).
  defp feet(%{skeleton: s} = animal, clip) do
    index = s.bones |> Enum.with_index() |> Map.new(fn {b, i} -> {b.name, i} end)
    skin = for n <- Build.scene(animal).nodes, p <- n.primitives, p.joints, do: p
    h = elem(s.rest["pelvis"].at, 2)

    Map.new(World.Animals.Quadruped.feet(), fn f ->
      points =
        for p <- skin,
            {at, {j, _, _, _}, {w, _, _, _}} <- Enum.zip([p.positions, p.joints, p.weights]),
            j == index[f] and w > 0.5,
            do: Frame.point(Frame.invert(s.rest[f]), at)

      low = fn world -> points |> Enum.map(&elem(Frame.point(world[f], &1), 2)) |> Enum.min() end
      {f, for(world <- frames(animal, clip), do: (low.(world) - low.(s.rest)) / h)}
    end)
  end

  # No foot goes into the ground; in a walk and a run, each foot comes
  # down to the ground.
  defp on_ground(animal, clip) do
    for {f, ups} <- feet(animal, clip) do
      assert Enum.min(ups) > -0.005, "#{clip.name} #{f}"
      if clip.name in ~w(walk run), do: assert(Enum.min(ups) < 0.005, "#{clip.name} #{f}")
    end
  end

  test "the clips of the template on the bones, and the wag", %{dog: dog} do
    [walk, wag] = dog.animations
    assert walk.name == "walk" and wag.name == "wag"
    s = dog.skeleton
    index = fn bone -> 1 + Enum.find_index(s.bones, &(&1.name == bone)) end
    nodes = MapSet.new(walk.channels, & &1.node)
    assert index.("front_lower_l") in nodes and index.("hind_foot_r") in nodes and index.("tail_01") in nodes
    assert %{path: :translation} = Enum.find(walk.channels, &(&1.node == index.("pelvis") and &1.path == :translation))
    assert MapSet.new(wag.channels, & &1.node) == MapSet.new(~w(tail_01 tail_02 tail_03), index)

    all = Animals.animal("street_dog", animations: ~w(walk run idle eat))
    assert Enum.map(all.animations, & &1.name) == ~w(walk run idle eat)

    for clip <- all.animations do
      # Each bone keeps its length: its head is on its parent where it is
      # at rest.
      for world <- frames(all, clip), b <- s.bones, b.parent do
        at = Frame.point(world[b.parent], s.local[b.name].at)
        assert Vec.len(Vec.sub(world[b.name].at, at)) < 1.0e-9
      end

      on_ground(all, clip)
    end

    # A walk and a run loop: the last time is the first. The head goes
    # down to eat.
    [walk, run, _, eat] = Enum.map(all.animations, &frames(all, &1))

    for clip <- [walk, run],
        do: assert(Vec.len(Vec.sub(List.last(clip)["head"].at, hd(clip)["head"].at)) < 1.0e-3)

    assert eat |> Enum.map(&elem(&1["head"].at, 2)) |> Enum.min() < elem(s.rest["head"].at, 2) - 0.15

    # The speeds of the clips that move the animal: a run is faster.
    %{"walk_speed" => slow, "run_speed" => fast} = all.params
    assert slow > 0.2 and fast > 2 * slow

    assert Animals.species() == ~w(cat cow deer donkey fox goat horse macaque pig street_dog water_buffalo wolf)
    assert Animals.animal("street_dog", []).name == "dog"
    assert_raise ArgumentError, ~r/unknown species "lion"/, fn -> Animals.animal("lion", []) end

    assert_raise ArgumentError, ~r/unknown animation of a street_dog "fly"/, fn ->
      Animals.animal("street_dog", animations: ["fly"])
    end

    refute Animals.__mix_recompile__?()
  end

  test "a rig: bones with no body, a root with a body, a port on no bone" do
    bones = [
      %{name: "root", head: {0, 0, 0}, tail: {0, 0, 0.5}, radius: {{0.1, 0.1}, {0.05, 0.05}}, material: :paint},
      %{name: "arm", parent: "root", head: {0, 0, 0.5}, tail: {0, 0.4, 0.5}, x: {0, 0, 1}, radius: nil}
    ]

    f =
      Rig.figure("post",
        bones: bones,
        limbs: [Limb.new("all", ~w(root arm), solver: :chain)],
        joints: [Joint.new("arm", :hinge, bone: "arm", role: :arm)],
        ports: [
          {"top", nil, Part.port("top", {0, 0, 1}, {0, 0, 1})},
          {"hand", "arm", Part.port("hand", {0, 0.4, 0.5}, {0, 1, 0})}
        ],
        spheres: [{{0, 0.4, 0.5}, 0.02, "arm", :paint}],
        kind: :prop
      )

    assert f.kind == :prop and length(f.nodes) == 4
    [mesh] = for n <- f.nodes, n.primitives != [], do: n
    # The tube of the root, and the sphere on the arm.
    assert [%{material: :paint, joints: tube}, %{material: :paint, joints: ball}] = mesh.primitives
    assert Enum.uniq(tube) == [{0, 0, 0, 0}] and Enum.uniq(ball) == [{1, 0, 0, 0}]
    # The x of the arm is up: the bone turns around z of World.
    assert Vec.len(Vec.sub(f.skeleton.rest["arm"].x, {0.0, 0.0, 1.0})) < 1.0e-9
    assert Figure.port_frame(f, "hand").at == Frame.point(Figure.bone_frame(f, "arm"), Figure.port!(f, "hand").at)
    assert Figure.port!(f, "top").bone == nil
    assert Build.scene(f, pose: %{"arm" => 30}).nodes |> Enum.at(3) |> Map.get(:frame) != Enum.at(f.nodes, 2).frame
  end

  # The highest point of the spine (the withers), at far (no smooth
  # steps: the points of the template).
  defp withers(animal) do
    scene = World.Detail.with(:far, fn -> Build.scene(animal) end)
    # The joints of a point are indices of the bones of the skin.
    spine = Enum.find_index(animal.skeleton.bones, &(&1.name == "spine_01"))

    for n <- scene.nodes,
        p <- n.primitives,
        p.material == :fur,
        {pos, j, w} <- Enum.zip([p.positions, p.joints, p.weights]),
        elem(j, 0) == spine and elem(w, 0) >= 0.5,
        reduce: 0.0,
        do: (top -> max(top, elem(pos, 2)))
  end

  test "the presets of the template: the height at the withers, the colors and the parts of each" do
    heights = [
      {"cat", 0.25},
      {"wolf", 0.8},
      {"fox", 0.4},
      {"goat", 0.55},
      {"pig", 0.6},
      {"deer", 0.9},
      {"horse", 1.35},
      {"donkey", 1.1},
      {"cow", 1.1},
      {"water_buffalo", 1.3}
    ]

    for {name, h} <- heights do
      animal = Animals.animal(name, animations: ~w(walk))
      assert_in_delta withers(animal), h, 0.05 * h, name
      assert Figure.limbs(animal) == ~w(front_l front_r head hind_l hind_r tail)
      # The walk of its template, with the feet on the ground.
      on_ground(animal, hd(animal.animations))
    end

    # The cat on the fox: gray, with a white chest and white paws (the
    # lighter parts and the dark legs of the fox).
    cat = Animals.animal("cat", [])
    assert cat.materials.fur["color"] == [78, 78, 84]
    assert cat.materials.marking["color"] == [236, 233, 226] and cat.materials.dark["color"] == [236, 233, 226]

    # A pig on the cow, with no horns of the cow; its black head and back
    # are in the colors of the points, of the fur and of the lighter parts.
    pig = Build.scene(Animals.animal("pig", []))
    refute :horn in Map.keys(pig.materials)
    [fur] = for n <- pig.nodes, p <- n.primitives, p.material == :fur, do: p
    assert Enum.any?(fur.colors, &(elem(&1, 0) < 60)) and Enum.any?(fur.colors, &(elem(&1, 0) > 200))
    [marking] = for n <- pig.nodes, p <- n.primitives, p.material == :marking, do: p
    assert marking.colors != nil and pig.materials.marking["color"] == [255, 255, 255]

    # The new horns of a water buffalo are wide; it has none of the bull.
    buffalo = Build.scene(Animals.animal("water_buffalo", []))
    [horns] = for n <- buffalo.nodes, p <- n.primitives, p.material == :horn, do: p
    {{x0, _, _}, {x1, _, _}} = World.Vec.bounds(horns.positions)
    assert x1 - x0 > 0.6

    goat = Build.scene(Animals.animal("goat", []))
    assert :horn in Map.keys(goat.materials)
    [horns] = for n <- goat.nodes, p <- n.primitives, p.material == :horn, do: p
    {{_, _, low}, _} = World.Vec.bounds(horns.positions)
    {_, {_, _, top}} = Scene.bounds(goat)
    assert low > 0.5 * top

    # A shape and markings of an order over the preset.
    long =
      Animals.animal("goat", shape: %{"horns" => 1.2, "leg_length" => 1.3}, markings: %{"socks" => [255, 255, 255]})

    # The same height at the withers: longer legs give a shorter body.
    length = fn a -> a |> Build.scene() |> Map.get(:extras) |> Map.get("size") |> Enum.at(1) end
    assert length.(long) < length.(Animals.animal("goat", []))
    [fur] = for n <- Build.scene(long).nodes, p <- n.primitives, p.material == :fur, do: p
    # White socks above the dark hooves.
    assert Enum.any?(fur.colors, &(elem(&1, 0) > 200 and elem(&1, 2) > 200))
  end

  test "a long-tailed macaque: the template of primates, on four limbs" do
    m = Animals.animal("macaque", animations: Animals.animations("macaque"))
    assert Animals.animations("macaque") == ~w(walk sit)
    scene = Build.scene(m)
    assert Map.keys(scene.materials) |> Enum.sort() == [:eye, :fur]
    assert Figure.limbs(m) == ~w(arm_l arm_r head leg_l leg_r tail)
    assert "elbow_l" in Figure.values(m) and "ankle_r" in Figure.values(m) and "tail.flex" in Figure.values(m)
    assert Figure.port!(m, "grip_r").bone == "hand_r" and Figure.port!(m, "back").bone == "spine_02"
    assert m.params["walk_speed"] == 0.58

    # The UVs and the fur: the fur from the species (no fur on the face,
    # 2.5 cm on the coat), on the fur only (not on the eyes); one unit of
    # UV is about 1.3 m of skin.
    [eye] = for n <- scene.nodes, p <- n.primitives, p.material == :eye, do: p
    [fur] = for n <- scene.nodes, p <- n.primitives, p.material == :fur, do: p
    assert eye.fur == nil and length(eye.uvs) == length(eye.positions)
    assert length(fur.fur) == length(fur.positions) and length(fur.uvs) == length(fur.positions)
    assert Enum.min(fur.fur) == 0.0
    assert_in_delta Enum.max(fur.fur), 0.025, 1.0e-9
    assert m.params["uv_size"] > 1.0 and m.params["uv_size"] < 1.6
    big = Animals.animal("macaque", size: 2.0)

    assert_in_delta Enum.max(hd(for n <- Build.scene(big).nodes, p <- n.primitives, p.material == :fur, do: p).fur),
                    0.05,
                    1.0e-9

    s = m.skeleton
    rest = s.rest

    # The left side is at -x; eight bones of the tail; the arms are about
    # 0.9 of the legs.
    assert elem(rest["hand_l"].at, 0) < 0 and elem(rest["hand_r"].at, 0) > 0
    assert Enum.count(Map.keys(rest), &String.starts_with?(&1, "tail_")) == 8
    span = fn a, b -> Vec.len(Vec.sub(rest[b].at, rest[a].at)) end

    index =
      (span.("upperarm_l", "lowerarm_l") + span.("lowerarm_l", "hand_l")) /
        (span.("thigh_l", "calf_l") + span.("calf_l", "foot_l"))

    assert_in_delta index, 0.9, 0.03

    # The pose: the wrists and the ankles on the ground, the hands flat
    # with the fingers to the front, the feet flat, the back near level.
    w = Skeleton.world(s, Skeleton.locals(s, m.pose))
    ground = elem(rest["foot_l"].at, 2)

    for side <- ~w(l r) do
      assert_in_delta elem(w["hand_#{side}"].at, 2), ground, 1.0e-3
      assert_in_delta elem(w["foot_#{side}"].at, 2), ground, 1.0e-3
      assert Vec.len(Vec.sub(w["hand_#{side}"].y, {0.0, 1.0, 0.0})) < 1.0e-9
      assert Vec.len(Vec.sub(w["foot_#{side}"].y, rest["foot_#{side}"].y)) < 1.0e-9
    end

    # A flat foot with no `lay` keeps its turn of the rest.
    lifted = Skeleton.world(s, Skeleton.locals(s, %{{:limb, "leg_l"} => %{by: {0.0, 0.03, 0.02}, flat: true}}))
    assert Vec.len(Vec.sub(lifted["foot_l"].y, rest["foot_l"].y)) < 1.0e-9

    assert Vec.dot(w["hand_l"].x, {0.0, 0.0, -1.0}) > 0.999 and Vec.dot(w["hand_r"].x, {0.0, 0.0, 1.0}) > 0.999
    trunk = Vec.norm(Vec.sub(w["neck_01"].at, w["pelvis"].at))
    assert abs(elem(trunk, 2)) < 0.5 and elem(trunk, 1) > 0.8

    # The walk: the diagonal order of a primate (hind left, front right,
    # hind right, front left), each limb a quarter of the step after the
    # last; each hand or foot is on the ground for about 0.6 of the step.
    [walk, sit] = m.animations
    frames = frames(m, walk)
    n = length(frames) - 1

    tops =
      for limb <- ~w(foot_l hand_r foot_r hand_l) do
        zs = frames |> Enum.take(n) |> Enum.map(&elem(&1[limb].at, 2))
        on = Enum.count(zs, &(&1 < ground + 1.0e-3)) / n
        assert_in_delta on, 0.6, 0.08, limb
        Enum.find_index(zs, &(&1 == Enum.max(zs)))
      end

    for [a, b] <- Enum.chunk_every(tops, 2, 1, :discard), do: assert(rem(b - a + n, n) in 3..5)

    # The sit: the hips low, the tail on the ground and not under it, the
    # head turns to look around.
    [first | _] = sits = frames(m, sit)
    assert elem(first["pelvis"].at, 2) < 0.5 * elem(w["pelvis"].at, 2)
    for f <- sits, b <- s.bones, String.starts_with?(b.name, "tail_"), do: assert(elem(f[b.name].at, 2) > -0.01)
    turned = for f <- sits, do: elem(f["head"].z, 0)
    assert Enum.max(turned) - Enum.min(turned) > 0.5
  end
end
