defmodule World.PropsTest do
  use ExUnit.Case, async: true

  alias World.{Assembly, Build, Detail, Figure, Frame, Part, Scene, Vec}
  alias World.Materials.Stock
  alias World.People.{Human, Pose, Props}

  setup_all do
    {:ok, person: Detail.with(:far, fn -> Human.person("p", hair: nil, clothes: [], pose: "stand") end)}
  end

  defp world_at(scene, name) do
    frames = Scene.world_frames(scene)
    frames[Enum.find_index(scene.nodes, &(&1.name == name))]
  end

  test "the ports on the bones of a person: the grips in the hands, the crown, the back, the soles", %{person: person} do
    for side <- ~w(l r) do
      grip = Figure.port_frame(person, "grip_#{side}")
      hand = Figure.bone_frame(person, "hand_#{side}")
      assert Vec.len(Vec.sub(grip.at, hand.at)) < 0.12
      sole = Figure.port_frame(person, "sole_#{side}")
      assert abs(elem(sole.at, 2)) < 0.05
      assert Figure.port!(person, "sole_#{side}").bone == "foot_#{side}"
    end

    {_, _, crown} = Figure.port_frame(person, "crown").at
    assert crown > 1.55 and crown < 1.9
    {_, back, _} = Figure.port_frame(person, "back").at
    assert back < -0.08
    assert Figure.port_frame(person, "ground") == Frame.identity()
    assert Figure.limbs(%Figure{}) == []
    assert "arm_r" in Figure.limbs(person)
    assert_raise ArgumentError, ~r/no bone "tail"/, fn -> Figure.bone_node(person, "tail") end
  end

  test "a prop in a hand is in the node of the hand, and follows the hand in a pose", %{person: person} do
    fan = Props.prop("fan")
    p = Detail.with(:far, fn -> Human.person("p", hair: nil, clothes: [], hold: [{"grip_r", fan}]) end)
    assert [{"grip_r", ^fan, "grip"}] = p.props
    # The hand closes on the prop.
    assert p.pose["index_02_r"] == [flex: 80]

    rest = Build.scene(p)
    up = Build.scene(p, pose: %{"shoulder_r.flex" => 150, "elbow_r" => 0})
    [node] = for {n, i} <- Enum.with_index(rest.nodes), n.primitives != [] and n.name == "hand_r", do: i
    assert Enum.at(rest.nodes, node).parent == Enum.find_index(rest.nodes, &(&1.name == "lowerarm_r"))
    assert elem(world_at(up, "hand_r").at, 2) > elem(world_at(rest, "hand_r").at, 2) + 0.5

    assert "tai_chi_fan" in Enum.map(Build.parts(p), & &1["name"])
    # A prop on a port that is not on a bone is in the root of the figure.
    mat = Figure.hold(person, "ground", Stock.rod(0.01, 0.1, :steel), Part.port("end", {0, 0, 0}, {0, 0, 1}))
    [root] = for {n, i} <- Enum.with_index(Build.scene(mat).nodes), n.primitives != [] and n.name == "p", do: i
    assert root == 1
    assert_raise ArgumentError, ~r/no port "wing"/, fn -> Figure.hold(p, "wing", fan) end
    assert_raise ArgumentError, ~r/no port "grip"/, fn -> Figure.hold(p, "crown", Props.prop("non_la"), "grip") end
  end

  test "a node of an assembly on a port of a bone goes in the node of the bone", %{person: person} do
    rod = Stock.rod(0.01, 0.3, :steel) |> Part.with_ports([Part.port("grip", {0, 0, 0.15}, {0, 0, 1}, {0, 1, 0})])

    a =
      Assembly.new("held", person, root: "p")
      |> Assembly.add("rod", rod, to: "p", at: "grip_l", port: "grip")
      |> Assembly.add("hat", Props.prop("non_la"), to: "p", at: "crown", port: "crown")
      |> Assembly.add("mark", Stock.rod(0.01, 0.1, :steel),
        to: "p",
        at: "hips",
        port: Part.port("end", {0, 0, 0}, {0, 0, 1})
      )

    scene = Build.scene(a)
    hand = Enum.find_index(scene.nodes, &(&1.name == "hand_l"))
    assert Enum.at(scene.nodes, hand).primitives != []
    # The frame of the port of the bone at rest is the place of the rod.
    assert Vec.len(Vec.sub(Assembly.node_frame(a, "rod").at, Figure.port_frame(person, "grip_l").at)) < 0.2
  end

  test "the hands that hold a prop keep their shape in an animation" do
    bones = Human.skeleton().bones
    moved = fn a -> MapSet.new(a.channels, & &1.node) end
    # The point is with the left hand.
    index = 1 + Enum.find_index(bones, &(&1.name == "index_02_l"))
    assert index in moved.(Pose.animation("point", bones))
    refute index in moved.(Pose.animation("point", bones, hands: %{l: "grip"}))
    refute index in moved.(Pose.animation("tai_chi", bones, hands: %{l: "grip"}))
  end

  test "the props: their names, their ports, and a name that is not a prop" do
    assert Props.names() == ["bottle", "fan", "non_la"]
    assert Props.on("fan") == "grip" and Props.on("bottle") == "grip" and Props.on("non_la") == "crown"

    for name <- Props.names() do
      p = Props.prop(name)
      assert Map.has_key?(p.ports, Props.on(name))
      assert p.sources != []
    end

    assert_raise ArgumentError, ~r/unknown prop "kite"/, fn -> Props.prop("kite") end
  end
end
