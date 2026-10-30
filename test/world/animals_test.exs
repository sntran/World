defmodule World.AnimalsTest do
  use ExUnit.Case, async: true

  alias World.{Animals, Build, Figure, Frame, Joint, Limb, Part, Rig, Scene, Vec}
  alias World.Animals.Coat
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

  # The height of the lowest point of the skin of each of the bones (the
  # points that the bone moves most) at each time of a clip, as a part of
  # the height of the pelvis.
  defp heights(%{skeleton: s} = animal, clip, bones) do
    index = s.bones |> Enum.with_index() |> Map.new(fn {b, i} -> {b.name, i} end)
    skin = for n <- Build.scene(animal).nodes, p <- n.primitives, p.joints, do: p
    h = elem(s.rest["pelvis"].at, 2)
    worlds = [s.rest | frames(animal, clip)]

    for b <- bones,
        points =
          for(
            p <- skin,
            {at, {j, _, _, _}, {w, _, _, _}} <- Enum.zip([p.positions, p.joints, p.weights]),
            j == index[b] and w > 0.5,
            do: Frame.point(Frame.invert(s.rest[b]), at)
          ),
        points != [],
        into: %{} do
      {b, for(world <- worlds, do: (points |> Enum.map(&elem(Frame.point(world[b], &1), 2)) |> Enum.min()) / h)}
    end
  end

  # The paws carry the animal: no foot goes into the ground, and in a
  # walk and a run each foot comes down to the ground. In a death, the
  # lowest point of the skin is on the ground at each time.
  defp on_ground(%{skeleton: s} = animal, %{name: "death"} = clip) do
    # The skin is a little over the ground: it is smooth, and its points
    # move with all their bones (the retarget moves each point with its
    # main bone).
    for time <- animal |> heights(clip, Enum.map(s.bones, & &1.name)) |> Map.values() |> Enum.zip(),
        low = time |> Tuple.to_list() |> Enum.min(),
        do: assert(low > -0.005 and low < 0.015, "death #{low}")
  end

  defp on_ground(animal, clip) do
    for {f, [rest | lows]} <- heights(animal, clip, World.Animals.Quadruped.feet()),
        ups = Enum.map(lows, &(&1 - rest)) do
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

    clips = Animals.animations("street_dog") -- ["wag"]
    # A dog has no kick (the files of the dogs have none); a cow has.
    assert clips == ~w(walk run idle idle_low eat attack jump jump_stop hit_l hit_r death)
    assert "kick" in Animals.animations("cow")

    assert_raise ArgumentError, ~r/unknown animation of a wolf "kick"/, fn ->
      Animals.animal("wolf", animations: ["kick"])
    end

    all = Animals.animal("street_dog", animations: clips)
    assert Enum.map(all.animations, & &1.name) == clips

    for clip <- all.animations do
      # Each bone keeps its length: its head is on its parent where it is
      # at rest.
      for world <- frames(all, clip), b <- s.bones, b.parent do
        at = Frame.point(world[b.parent], s.local[b.name].at)
        assert Vec.len(Vec.sub(world[b.name].at, at)) < 1.0e-9
      end

      on_ground(all, clip)
    end

    # The loops: the last time is the first. The head goes down to eat
    # and in the idle with the head low; the animal lies down at the end
    # of a death.
    [walk, run, _, low, eat, attack, jump, _, hit_l, hit_r, death] = Enum.map(all.animations, &frames(all, &1))

    for clip <- [walk, run, low, attack, jump, hit_l, hit_r],
        do: assert(Vec.len(Vec.sub(List.last(clip)["head"].at, hd(clip)["head"].at)) < 1.0e-3)

    for {clip, down} <- [{eat, 0.15}, {low, 0.05}],
        do: assert(clip |> Enum.map(&elem(&1["head"].at, 2)) |> Enum.min() < elem(s.rest["head"].at, 2) - down)

    assert elem(List.last(death)["pelvis"].at, 2) < 0.6 * elem(s.rest["pelvis"].at, 2)

    # The speeds of the clips that move the animal: a run is faster.
    %{"walk_speed" => slow, "run_speed" => fast, "jump_speed" => jump_speed} = all.params
    assert slow > 0.2 and fast > 2 * slow and jump_speed > slow

    assert Animals.species() ==
             ~w(alpaca carp cat chicken cow deer donkey douc duck fox gibbon goat horse husky hyena macaque pig pig_tailed_macaque red_deer rhesus_macaque sheep street_dog tilapia water_buffalo wolf)

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
      {"water_buffalo", 1.3},
      {"alpaca", 0.9},
      {"husky", 0.55},
      {"red_deer", 1.22},
      {"sheep", 0.74},
      {"hyena", 0.8}
    ]

    for {name, h} <- heights do
      animal = Animals.animal(name, animations: ~w(walk))
      assert_in_delta withers(animal), h, 0.05 * h, name
      # A tail, when the template has the bones of a tail.
      tail = if Map.has_key?(animal.skeleton.rest, "tail_01"), do: ~w(tail), else: []
      assert Figure.limbs(animal) == ~w(front_l front_r head hind_l hind_r) ++ tail
      # The walk of its template, with the feet on the ground.
      on_ground(animal, hd(animal.animations))
    end

    # The cat on the fox: gray, with a white chest and white paws (the
    # lighter parts and the dark legs of the fox).
    cat = Animals.animal("cat", [])
    assert cat.materials.fur["color"] == [78, 78, 84]
    assert cat.materials.marking["color"] == [236, 233, 226] and cat.materials.dark["color"] == [236, 233, 226]

    # The kind of hair of the coat texture: of the species (the wool of
    # the sheep, the curls of the alpaca), else from the length of the
    # coat (the cow: 8 mm, short; the wolf: 5 cm, long). One tile of the
    # texture is `Coat.tile/1` of skin.
    for {name, kind} <- [{"sheep", "wool"}, {"alpaca", "curly"}, {"cow", "short"}, {"wolf", "long"}] do
      a = Animals.animal(name, [])
      assert a.params["hair"] == kind and a.materials.fur["image"] == Coat.texture(kind), name
      assert_in_delta a.materials.fur["image_scale"], a.params["uv_size"] / Coat.tile(kind), 0.05, name
    end

    refute Map.has_key?(Animals.animal("carp", []).params, "hair")

    # A pig on the pig of the farm pack: the clips of the cow (its file
    # has no walk), and no wag (no bones of a tail). Its black head and
    # back are in the colors of the points of the fur.
    assert "kick" in Animals.animations("pig") and "wag" not in Animals.animations("pig")
    assert "wag" in Animals.animations("cow")
    pig = Build.scene(Animals.animal("pig", []))
    [fur] = for n <- pig.nodes, p <- n.primitives, p.material == :fur, do: p
    assert Enum.any?(fur.colors, &(elem(&1, 0) < 60)) and Enum.any?(fur.colors, &(elem(&1, 0) > 200))
    assert pig.materials.fur["color"] == [255, 255, 255]

    # The mane and the tail of a horse (a mesh of hair) have fur: 5 cm on
    # the mane, 8 cm on the tail; the fur lies along the skin.
    horse = Build.scene(Animals.animal("horse", []))
    [mane] = for n <- horse.nodes, p <- n.primitives, p.material == :mane, do: p
    assert_in_delta Enum.max(mane.fur), 0.08, 1.0e-6
    assert Enum.any?(mane.fur, &(abs(&1 - 0.05) < 0.005)) and length(mane.fur_dirs) == length(mane.positions)

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
    assert Animals.animations("macaque") == ~w(walk run sit climb hang jump)
    scene = Build.scene(m)
    assert Map.keys(scene.materials) |> Enum.sort() == [:bare, :eye, :fringe, :fur, :iris]
    assert Figure.limbs(m) == ~w(arm_l arm_r head leg_l leg_r tail)
    assert "elbow_l" in Figure.values(m) and "ankle_r" in Figure.values(m) and "tail.flex" in Figure.values(m)
    assert Figure.port!(m, "grip_r").bone == "hand_r" and Figure.port!(m, "back").bone == "spine_02"
    assert m.params["walk_speed"] == 0.29 and m.params["run_speed"] == 1.14

    # The UVs and the fur: the fur from the species (no fur on the face,
    # 2.5 cm on the coat), on the fur only (not on the eyes); one unit of
    # UV is about 1.3 m of skin.
    [eye] = for n <- scene.nodes, p <- n.primitives, p.material == :eye, do: p
    [fur] = for n <- scene.nodes, p <- n.primitives, p.material == :fur, do: p
    assert eye.fur == nil and length(eye.uvs) == length(eye.positions)
    assert length(fur.fur) == length(fur.positions) and length(fur.uvs) == length(fur.positions)
    # The fur has 3 mm of hair or more; less is the bare skin and its
    # fringe.
    assert Enum.min(fur.fur) > 0.003 - 1.0e-6
    assert_in_delta Enum.max(fur.fur), 0.025, 1.0e-9
    # The tail has short hair.
    tail = for {b, k} <- Enum.with_index(m.skeleton.bones), String.starts_with?(b.name, "tail_"), do: k
    on_tail = for {f, j, w} <- Enum.zip([fur.fur, fur.joints, fur.weights]), elem(j, 0) in tail, elem(w, 0) > 0.9, do: f
    assert on_tail != [] and Enum.max(on_tail) < 0.01
    assert m.params["uv_size"] > 1.0 and m.params["uv_size"] < 1.6

    # The coat has the strands of hair of `World.Animals.Coat`, one tile
    # for each 4 cm of skin. The bare skin (the face, the muzzle, the ears,
    # the hands and the feet) has no texture and no fur: the colors of
    # its points on the mean gray of the texture.
    assert m.materials.fur["image"] == Coat.texture()
    assert_in_delta m.materials.fur["image_scale"], m.params["uv_size"] / Coat.tile(), 0.1
    [bare] = for n <- scene.nodes, p <- n.primitives, p.material == :bare, do: p
    assert bare.fur == nil and length(bare.colors) == length(bare.positions)
    assert m.materials.bare["color"] == List.duplicate(round(255 * Coat.mean()), 3)
    refute Map.has_key?(m.materials.bare, "image")

    # The edge of the bare skin: a fringe of the coat over it (MASK), with
    # the hair of each point (0 to 1) as the alpha of its colors. The fur
    # and the fringe share one image in the GLB.
    [fringe] = for n <- scene.nodes, p <- n.primitives, p.material == :fringe, do: p
    alphas = Enum.map(fringe.colors, &elem(&1, 3))
    assert Enum.min(alphas) < 0.5 and Enum.max(alphas) > 0.5 and Enum.all?(alphas, &(&1 >= 0 and &1 <= 1))
    assert m.materials.fringe["alpha_mode"] == "MASK" and m.materials.fringe["image"] == Coat.texture()
    json = World.GLBHelper.json(World.GLB.encode(scene))
    assert length(json["images"]) == 1
    assert Enum.find(json["materials"], &(&1["name"] == "fringe"))["alphaMode"] == "MASK"

    # The face: four morph targets on all the parts of the mesh. The jaw
    # opens (the chin goes down, the body stays), the lips go to the
    # front for a lip-smack; the inside of the mouth is dark.
    names = ~w(brows_up jaw_open lips_back lips_forward)
    assert Enum.map(bare.targets, &elem(&1, 0)) == names and Enum.map(fur.targets, &elem(&1, 0)) == names
    move = fn prim, name -> prim.targets |> Enum.find(&(elem(&1, 0) == name)) |> elem(1) end
    assert move.(bare, "jaw_open") |> Enum.map(&elem(&1, 2)) |> Enum.min() < -0.01
    assert move.(bare, "lips_forward") |> Enum.map(&elem(&1, 1)) |> Enum.max() > 0.003

    assert move.(fur, "jaw_open")
           |> Enum.zip(fur.joints)
           |> Enum.all?(fn {d, j} -> elem(j, 0) != 0 or Vec.len(d) == 0 end)

    assert Enum.any?(bare.colors, &(elem(&1, 0) < 60))

    # The eyes: a dark pupil at the front of an amber iris.
    [iris] = for n <- scene.nodes, p <- n.primitives, p.material == :iris, do: p
    assert m.materials.iris["color"] == [135, 88, 38] and m.materials.eye["color"] == [20, 16, 14]
    assert length(iris.positions) > length(eye.positions)
    front = fn p -> p.positions |> Enum.map(&elem(&1, 1)) |> Enum.max() end
    assert front.(eye) > front.(iris) - 1.0e-9
    big = Animals.animal("macaque", size: 2.0)

    assert_in_delta Enum.max(hd(for n <- Build.scene(big).nodes, p <- n.primitives, p.material == :fur, do: p).fur),
                    0.05,
                    1.0e-9

    s = m.skeleton
    rest = s.rest

    # The left side is at -x; five bones of the tail (of the mesh of
    # BigMaQ); the arms are about 0.9 of the legs.
    assert elem(rest["hand_l"].at, 0) < 0 and elem(rest["hand_r"].at, 0) > 0
    assert Enum.count(Map.keys(rest), &String.starts_with?(&1, "tail_")) == 5
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

    # The walk: the clip of BigMaQ (a real rhesus macaque). No hand or foot
    # goes into the ground, each comes down to it and is on it for a part
    # of the step (the lowest point of the skin of the hand and its middle
    # finger, of the foot and its toes, in parts of the height of the
    # pelvis), and they lift in the diagonal order of a primate (hind left,
    # front right, hind right, front left).
    [walk, run, sit, climb, hang, jump] = m.animations

    paws = %{
      "foot_l" => ~w(foot_l ball_l),
      "foot_r" => ~w(foot_r ball_r),
      "hand_l" => ~w(hand_l middle_01_l middle_02_l),
      "hand_r" => ~w(hand_r middle_01_r middle_02_r)
    }

    lows = fn clip ->
      each = heights(m, clip, paws |> Map.values() |> List.flatten())
      Map.new(paws, fn {p, bones} -> {p, bones |> Enum.map(&each[&1]) |> Enum.zip_with(&Enum.min/1)} end)
    end

    # The ground: the lowest foot at rest (the smooth skin is a little
    # over the points of the mesh). For each paw: its heights in the
    # clip, and the part of the clip that it is on the ground.
    walking = lows.(walk)
    ground = min(hd(walking["foot_l"]), hd(walking["foot_r"]))

    steps = fn lows, limb ->
      [_rest | zs] = lows[limb]
      zs = zs |> Enum.drop(-1) |> Enum.map(&(&1 - ground))
      assert Enum.min(zs) > -0.01 and Enum.min(zs) < 0.02, "#{limb} #{Enum.min(zs)}"
      {zs, Enum.count(zs, &(&1 < Enum.min(zs) + 0.03)) / length(zs)}
    end

    tops =
      for limb <- ~w(foot_l hand_r foot_r hand_l) do
        {zs, on} = steps.(walking, limb)
        assert on > 0.3 and on < 0.9, "#{limb} #{on}"
        Enum.find_index(zs, &(&1 == Enum.max(zs)))
      end

    n = length(hd(Map.values(walking))) - 2
    gaps = for [a, b] <- Enum.chunk_every(tops ++ [hd(tops)], 2, 1, :discard), do: rem(b - a + n, n)
    assert Enum.sum(gaps) == n, inspect(gaps)

    # The run: the clip of BigMaQ, a bound. Each paw comes down to the
    # ground, and is on it for less of the cycle than in the walk.
    running = lows.(run)

    for limb <- ~w(foot_l hand_r foot_r hand_l) do
      {_, on} = steps.(running, limb)
      assert on > 0.0 and on < 0.6, "#{limb} #{on}"
    end

    # The sit: the clip of BigMaQ (an animal that rests): the hips low and
    # still, the back up, the tail on the ground and not under it.
    [first | _] = sits = frames(m, sit)

    for f <- sits do
      assert elem(f["pelvis"].at, 2) < 0.6 * elem(w["pelvis"].at, 2)
      assert elem(Vec.norm(Vec.sub(f["neck_01"].at, f["pelvis"].at)), 2) > 0.6
      assert Vec.len(Vec.sub(f["pelvis"].at, first["pelvis"].at)) < 0.03
      for b <- s.bones, String.starts_with?(b.name, "tail_"), do: assert(elem(f[b.name].at, 2) > -0.01)
    end

    # The climb: the body upright off the ground, the hands over the
    # shoulders on the trunk in front, the fingers closed on it; each hand
    # goes up and down by a step.
    climbs = frames(m, climb)

    for f <- climbs do
      assert elem(Vec.norm(Vec.sub(f["neck_01"].at, f["pelvis"].at)), 2) > 0.8
      assert elem(f["foot_l"].at, 2) > ground + 0.01
      for side <- ~w(l r), do: assert(elem(f["hand_#{side}"].at, 2) > elem(f["upperarm_#{side}"].at, 2))
    end

    assert Vec.dot(hd(climbs)["index_02_l"].y, hd(climbs)["hand_l"].y) < 0.9
    hand = Enum.map(climbs, &elem(&1["hand_l"].at, 2))
    assert Enum.max(hand) - Enum.min(hand) > 0.05

    # The hang: the hands over the head, the feet off the ground.
    for f <- frames(m, hang) do
      assert elem(f["hand_l"].at, 2) > elem(f["head"].at, 2) and elem(f["foot_r"].at, 2) > ground + 0.05
    end

    # The jump: the hips go down, then all the animal is in the air.
    jumps = frames(m, jump)
    hips = Enum.map(jumps, &elem(&1["pelvis"].at, 2))
    assert Enum.min(hips) < elem(w["pelvis"].at, 2) - 0.02

    assert Enum.any?(jumps, fn f -> Enum.all?(~w(foot_l foot_r hand_l hand_r), &(elem(f[&1].at, 2) > ground + 0.05)) end)
  end

  test "more primates: the rhesus, the pig-tailed macaque, the douc, and the gibbon upright" do
    for name <- ~w(rhesus_macaque pig_tailed_macaque douc gibbon) do
      a = Animals.animal(name, [])
      assert a.params["walk_speed"] > 0.3, name
      # The clips of the template are on four limbs: the gibbon has no run.
      assert Animals.animations(name) ==
               if(name == "gibbon", do: ~w(walk sit climb hang jump), else: ~w(walk run sit climb hang jump))
    end

    # The gibbon stands and walks on two legs with its arms up; its arms
    # are about 1.3 times its legs.
    g = Animals.animal("gibbon", animations: ~w(walk sit))
    s = g.skeleton
    span = fn a, b -> Vec.len(Vec.sub(s.rest[b].at, s.rest[a].at)) end
    arms = span.("upperarm_l", "lowerarm_l") + span.("lowerarm_l", "hand_l")
    legs = span.("thigh_l", "calf_l") + span.("calf_l", "foot_l")
    assert_in_delta arms / legs, 1.3, 0.1
    w = Skeleton.world(s, Skeleton.locals(s, g.pose))
    assert elem(Vec.norm(Vec.sub(w["neck_01"].at, w["pelvis"].at)), 2) > 0.9
    assert elem(w["hand_r"].at, 2) > elem(w["head"].at, 2)

    # The template `primate_upright`: no tail, the arms up at rest (the
    # hands over the head), and the stance near the rest (the arms turn
    # by less than 45 degrees; from the rest with the arms down they turn
    # by about 150).
    refute Enum.any?(s.bones, &String.starts_with?(&1.name, "tail_"))
    assert Figure.limbs(g) == ~w(arm_l arm_r head leg_l leg_r)
    assert elem(s.rest["hand_l"].at, 2) > elem(s.rest["head"].at, 2)

    for side <- ~w(l r) do
      dir = fn f -> Vec.norm(Vec.sub(f["lowerarm_#{side}"].at, f["upperarm_#{side}"].at)) end
      assert Vec.dot(dir.(w), dir.(s.rest)) > :math.cos(45 * :math.pi() / 180)
    end

    [walk, sit] = g.animations

    for f <- frames(g, walk) do
      assert elem(f["hand_l"].at, 2) > elem(f["neck_01"].at, 2)
      assert min(elem(f["foot_l"].at, 2), elem(f["foot_r"].at, 2)) < elem(s.rest["foot_l"].at, 2) + 1.0e-3
    end

    # The sit of the body plan: the hips low, the tail on the ground and
    # not under it, the head turns to look around.
    [first | _] = sits = frames(g, sit)
    assert elem(first["pelvis"].at, 2) < 0.5 * elem(s.rest["pelvis"].at, 2)
    for f <- sits, b <- s.bones, String.starts_with?(b.name, "tail_"), do: assert(elem(f[b.name].at, 2) > -0.01)
    turned = for f <- sits, do: elem(f["head"].z, 0)
    assert Enum.max(turned) - Enum.min(turned) > 0.5
  end

  test "a fish: the carp and the tilapia, a body from the bones, fins, a swim" do
    for {name, length} <- [{"carp", 0.5}, {"tilapia", 0.3}] do
      a = Animals.animal(name, animations: ~w(swim idle))
      assert Animals.animations(name) == ~w(swim idle)
      assert a.params["swim_speed"] > 0.2

      # The length of the fish is the size of its species, its belly on
      # the ground; the fins have their own material.
      [_, l, _] = Build.scene(a).extras["size"]
      assert_in_delta l, length, 0.02
      assert Map.has_key?(a.materials, :fin) and Map.has_key?(a.materials, :eye)
      # A fish has no hair: no texture of a coat.
      refute Enum.any?(Map.values(a.materials), &Map.has_key?(&1, "image"))

      # The swim: a wave to the sides, larger at the tail fin than at the
      # head; the idle is smaller.
      [swim, idle] = a.animations
      side = fn clip, bone -> clip |> then(&frames(a, &1)) |> Enum.map(&elem(&1[bone].at, 0)) |> Enum.min_max() end
      width = fn {lo, hi} -> hi - lo end
      assert width.(side.(swim, "tail_04")) > 0.1 * length
      assert width.(side.(swim, "tail_04")) > 3 * width.(side.(swim, "head"))
      assert width.(side.(idle, "tail_04")) < width.(side.(swim, "tail_04"))
    end

    # The tilapia is deeper than the carp, for its length.
    depth = fn name ->
      [_, l, h] = Build.scene(Animals.animal(name, [])).extras["size"]
      h / l
    end

    assert depth.("tilapia") > depth.("carp") + 0.05
  end

  test "a bird: the chicken and the duck, a walk, a peck, a flap" do
    for {name, height} <- [{"chicken", 0.45}, {"duck", 0.5}] do
      a = Animals.animal(name, animations: ~w(walk idle peck flap))
      assert Animals.animations(name) == ~w(walk idle peck flap)
      assert a.params["walk_speed"] > 0.1
      [_, _, h] = Build.scene(a).extras["size"]
      assert_in_delta h, height, 0.02
      s = a.skeleton
      [walk, idle, peck, flap] = a.animations
      ground = elem(s.rest["ball_l"].at, 2)

      # The walk: the feet go to the front and the back, in turn, and one
      # is in the air while the other is on the ground.
      steps = frames(a, walk)
      ys = Enum.map(steps, &elem(&1["ball_l"].at, 1))
      assert Enum.max(ys) - Enum.min(ys) > 0.15 * height

      assert Enum.any?(steps, fn f ->
               elem(f["ball_l"].at, 2) > ground + 0.01 and abs(elem(f["ball_r"].at, 2) - ground) < 0.005
             end)

      # The peck: the beak goes down near the ground, the feet stay; the
      # idle and the flap keep the feet too.
      pecks = frames(a, peck)
      assert Enum.min(Enum.map(pecks, &elem(&1["beak"].at, 2))) < 0.3 * height

      for f <- pecks ++ frames(a, idle) ++ frames(a, flap),
          do: assert(Vec.len(Vec.sub(f["ball_l"].at, s.rest["ball_l"].at)) < 0.01)

      # The flap: the wings open to the sides.
      out = frames(a, flap) |> Enum.map(&elem(&1["hand_l"].at, 0)) |> Enum.max()
      assert out > elem(s.rest["hand_l"].at, 0) + 0.1 * height
    end

    # The duck has a longer and wider beak, and no comb.
    beak = fn name ->
      a = Animals.animal(name, [])
      b = Enum.find(a.skeleton.bones, &(&1.name == "beak"))
      [_, _, h] = Build.scene(a).extras["size"]
      {Vec.len(Vec.sub(b.tail, b.head)) / h, a}
    end

    {chicken, c} = beak.("chicken")
    {duck, d} = beak.("duck")
    assert Map.has_key?(c.materials, :comb) and not Map.has_key?(d.materials, :comb)
    assert Map.has_key?(d.materials, :beak)
    assert duck > 1.4 * chicken
  end
end
