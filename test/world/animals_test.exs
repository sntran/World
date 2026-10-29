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
    assert_in_delta w, 0.34, 0.05
    assert_in_delta l, 1.13, 0.1
    assert_in_delta h, 0.71, 0.05
    {{_, _, ground}, _} = Scene.bounds(scene)
    assert_in_delta ground, 0.0, 0.01
    assert scene.extras["kind"] == "animal"
    assert Map.keys(scene.materials) -- [:eye, :fur] == []

    for p <- Enum.flat_map(scene.nodes, & &1.primitives), w <- p.weights do
      assert_in_delta Enum.sum(Tuple.to_list(w)), 1.0, 1.0e-9
    end

    big = Build.scene(Animals.animal("street_dog", size: 1.2))
    assert_in_delta Enum.at(big.extras["size"], 2), 1.2 * h, 0.01
    assert Animals.animal("street_dog", coat: [10, 20, 30]).materials.fur["color"] == [10, 20, 30]
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

  test "the walk keeps a foot on the ground while it goes back, and the wag turns the tail", %{dog: dog} do
    [walk, wag] = dog.animations
    assert walk.name == "walk" and wag.name == "wag"
    s = dog.skeleton
    rest = s.rest["front_foot_l"].at

    # A front foot up and to the back: flat.
    w = Skeleton.world(s, Skeleton.locals(s, %{{:limb, "front_l"} => %{by: {0.0, -0.03, 0.03}, flat: true}}))
    assert Vec.len(Vec.sub(w["front_foot_l"].at, Vec.add(rest, {0.0, -0.03, 0.03}))) < 1.0e-4
    # The paw keeps its turn of the rest.
    assert Vec.len(Vec.sub(w["front_foot_l"].y, s.rest["front_foot_l"].y)) < 1.0e-6
    nodes = MapSet.new(walk.channels, & &1.node)
    index = fn bone -> 1 + Enum.find_index(s.bones, &(&1.name == bone)) end
    assert index.("front_lower_l") in nodes and index.("tail_01") in nodes
    assert MapSet.new(wag.channels, & &1.node) == MapSet.new(~w(tail_01 tail_02 tail_03), index)
    assert Animals.species() == ~w(cat monkey street_dog)
    assert Animals.animal("street_dog", []).name == "dog"
    assert_raise ArgumentError, ~r/unknown species "lion"/, fn -> Animals.animal("lion", []) end

    assert_raise ArgumentError, ~r/unknown animation of a street_dog "run"/, fn ->
      Animals.animal("street_dog", animations: ["run"])
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

  test "a cat: the same body plan as the dog, with its own mesh, colors and gait" do
    cat = Animals.animal("cat", animations: ["walk", "wag"])
    scene = Build.scene(cat)
    assert cat.name == "cat"
    # 25 cm at the withers (the tail is up, above it).
    assert Enum.at(scene.extras["size"], 2) > 0.25
    assert Map.keys(scene.materials) |> Enum.sort() == [:dark, :eye, :fur, :marking, :skin]
    assert cat.materials.marking["color"] == [236, 233, 226]
    assert Figure.limbs(cat) == ~w(front_l front_r head hind_l hind_r tail)
    assert Enum.map(cat.animations, & &1.name) == ~w(walk wag)

    for p <- Enum.flat_map(scene.nodes, & &1.primitives), w <- p.weights do
      assert_in_delta Enum.sum(Tuple.to_list(w)), 1.0, 1.0e-9
    end
  end

  test "a monkey: two legs, two arms and a tail" do
    monkey = Animals.animal("monkey", animations: Animals.animations("monkey"))
    scene = Build.scene(monkey)
    [_, _, h] = scene.extras["size"]
    assert_in_delta h, 0.6, 1.0e-6
    assert Map.keys(scene.materials) |> Enum.sort() == [:dark, :fur, :skin, :white]
    assert Figure.limbs(monkey) == ~w(arm_l arm_r head leg_l leg_r tail)
    assert "elbow_l" in Figure.values(monkey) and "ankle_r" in Figure.values(monkey)
    rest = monkey.skeleton.rest

    # The left side is at -x; the toes go to the front; seven bones of
    # the tail.
    assert elem(rest["hand_l"].at, 0) < 0 and elem(rest["hand_r"].at, 0) > 0
    assert elem(rest["toes_l"].at, 1) > elem(rest["foot_l"].at, 1)
    assert Enum.count(Map.keys(rest), &String.starts_with?(&1, "tail_")) == 7

    # A hand to a point in front of the chest.
    to = Vec.add(rest["upper_arm_r"].at, {0.0, 0.12, -0.05})
    reach = Build.scene(monkey, targets: %{"arm_r" => to})
    assert Vec.len(Vec.sub(world(reach, "hand_r").at, to)) < 1.0e-3
    assert Figure.port!(monkey, "grip_r").bone == "hand_r"
    assert Figure.port!(monkey, "back").bone == "spine_02"

    # A flat foot keeps its turn of the rest; the wave moves the right
    # arm.
    [walk, wave, wag] = monkey.animations
    assert {walk.name, wave.name, wag.name} == {"walk", "wave", "wag"}
    s = monkey.skeleton
    w = Skeleton.world(s, Skeleton.locals(s, %{{:limb, "leg_l"} => %{by: {0.0, 0.03, 0.02}, flat: true}}))
    assert Vec.len(Vec.sub(w["foot_l"].y, rest["foot_l"].y)) < 1.0e-6
    hand = Enum.find_index(s.bones, &(&1.name == "upper_arm_r")) + 1
    assert hand in MapSet.new(wave.channels, & &1.node)
  end
end
