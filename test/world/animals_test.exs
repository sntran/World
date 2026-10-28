defmodule World.AnimalsTest do
  use ExUnit.Case, async: true

  alias World.{Animals, Build, Figure, Frame, Joint, Limb, Part, Rig, Scene, Vec}
  alias World.People.Skeleton

  # A figure in a module attribute is a literal in the code of the test:
  # slow to compile. The dog is made once for the tests.
  setup_all do
    {:ok, dog: Animals.dog(animations: ["walk", "wag"])}
  end

  defp world(scene, name) do
    frames = Scene.world_frames(scene)
    frames[Enum.find_index(scene.nodes, &(&1.name == name))]
  end

  test "a street dog: its size, its skin and its materials", %{dog: dog} do
    scene = Build.scene(dog)
    [w, l, h] = scene.extras["size"]
    assert_in_delta w, 0.24, 0.05
    assert_in_delta l, 0.95, 0.1
    assert_in_delta h, 0.72, 0.05
    {{_, _, ground}, _} = Scene.bounds(scene)
    assert_in_delta ground, 0.0, 0.01
    assert scene.extras["kind"] == "animal"
    assert Map.keys(scene.materials) -- [:eye, :fur] == []

    for p <- Enum.flat_map(scene.nodes, & &1.primitives), w <- p.weights do
      assert_in_delta Enum.sum(Tuple.to_list(w)), 1.0, 1.0e-9
    end

    big = Build.scene(Animals.dog(size: 1.2))
    assert_in_delta Enum.at(big.extras["size"], 2), 1.2 * h, 0.01
    assert Animals.dog(coat: [10, 20, 30]).materials.fur["color"] == [10, 20, 30]
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
    to = {-0.075, 0.35, 0.15}
    reach = Build.scene(dog, targets: %{"front_l" => to})
    assert Vec.len(Vec.sub(world(reach, "front_foot_l").at, to)) < 1.0e-3

    collar = Figure.port_frame(dog, "collar")
    assert Vec.len(Vec.sub(collar.at, {0.0, 0.27, 0.48})) < 1.0e-6
    assert Figure.port!(dog, "mouth").bone == "muzzle"
    assert Figure.port!(dog, "ground").bone == nil
  end

  test "the walk keeps a foot on the ground while it goes back, and the wag turns the tail", %{dog: dog} do
    [walk, wag] = dog.animations
    assert walk.name == "walk" and wag.name == "wag"
    s = dog.skeleton
    rest = s.rest["front_foot_l"].at

    # The front left foot starts at the part 0.25 of the step: on the
    # ground, at the front.
    w = Skeleton.world(s, Skeleton.locals(s, %{{:limb, "front_l"} => %{by: {0.0, 0.1, 0.0}}}))
    assert_in_delta elem(w["front_foot_l"].at, 2), elem(rest, 2), 1.0e-3
    nodes = MapSet.new(walk.channels, & &1.node)
    index = fn bone -> 1 + Enum.find_index(s.bones, &(&1.name == bone)) end
    assert index.("front_lower_l") in nodes and index.("tail_01") in nodes
    assert MapSet.new(wag.channels, & &1.node) == MapSet.new(~w(tail_01 tail_02 tail_03), index)
    assert Animals.species() == ["street_dog"]
    assert Animals.animal("street_dog", []).name == "dog"
    assert_raise ArgumentError, ~r/unknown species "cat"/, fn -> Animals.animal("cat", []) end
    assert_raise ArgumentError, ~r/unknown animation of a dog "run"/, fn -> Animals.dog(animations: ["run"]) end
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
end
