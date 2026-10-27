defmodule Xuong.AssemblyTest do
  use ExUnit.Case, async: true

  alias Xuong.{Assembly, Build, Frame, GLBHelper, Part, Port, Scene, Shape, Vec}
  alias Xuong.Parts.{Fasteners, Stock, Wheels}

  # A frame of a cart: a plate with an axle port on each side.
  defp frame_part do
    Part.new("cart_frame", :frame, Shape.box({-0.3, -0.5, 0.2}, {0.3, 0.5, 0.25}, :paint), [
      Part.port("axle_right", {0.3, 0.3, 0.2}, {1, 0, 0}, {0, 0, 1}),
      Part.port("axle_left", {-0.3, 0.3, 0.2}, {-1, 0, 0}, {0, 0, 1}),
      Part.port("hole", {0.0, 0.0, 0.25}, {0, 0, -1}, {0, 1, 0})
    ])
  end

  defp cart do
    wheel = Wheels.spoked_wheel("37-622", spokes: 8)

    Assembly.new("cart", frame_part(), kind: :vehicle, sources: ["A test."])
    |> Assembly.add("wheel_right", wheel, at: "axle_right", port: "hub", kind: :turns, role: :wheel)
    |> Assembly.add("wheel_left", wheel, at: "axle_left", port: "hub", kind: :turns, role: :wheel)
    |> Assembly.add("bolt", Fasteners.bolt("M8", 0.05), at: "hole", port: "head")
    |> Assembly.add("nut", Fasteners.nut("M8", inside: true), to: "bolt", at: "tip", port: "face", turn: 30)
    |> Assembly.add("lid", Stock.sheet(0.2, 0.2, 0.01, :plastic),
      at: Port.new("lid", {0, -0.4, 0.25}, {0, 0, 1}, {0, 1, 0}),
      port: "bottom",
      kind: :turns,
      role: :lid,
      limits: [0, 90]
    )
    |> Assembly.add("shock", Stock.rod(0.01, 0.1, :steel),
      at: Port.new("s", {0, 0.4, 0.25}, {0, 0, 1}, {0, 1, 0}),
      port: "end_a",
      kind: :slides,
      role: :suspension,
      limits: [0, 0.02]
    )
    |> Assembly.expose("front_axle", "axle_right")
  end

  test "a port of a node and an exposed port" do
    a = cart()
    f = Assembly.item_port_frame(a, "wheel_right/hub")
    assert Vec.len(Vec.sub(f.at, {0.3, 0.3, 0.2})) < 1.0e-9
    assert Vec.len(Vec.sub(f.z, {1.0, 0.0, 0.0})) < 1.0e-9
    assert Assembly.item_port_frame(a, "front_axle") == Assembly.item_port_frame(a, "axle_right")
    # A path whose first name is not a node is a port of the root.
    assert_raise ArgumentError, ~r/has no port "nope\/axle_left"/, fn ->
      Assembly.item_port_frame(a, "nope/axle_left")
    end
  end

  test "the nut is on the far side of the bolt" do
    a = cart()
    nut = Assembly.node_frame(a, "nut")
    assert_in_delta elem(nut.at, 2), 0.25 - 0.05, 1.0e-9
    assert Assembly.node_frame(a, "body") == Frame.identity()
  end

  test "the build: a node for each joint, with its role and limits" do
    scene = Build.scene(cart())
    names = Enum.map(scene.nodes, & &1.name)
    assert names == ["cart", "wheel_right", "wheel_left", "lid", "shock"]
    assert Enum.at(scene.nodes, 3).extras["limits"] == [0, 90]
    assert Enum.at(scene.nodes, 4).extras["kind"] == "slides"
    assert scene.extras["joints"] == ["wheel_right", "wheel_left", "lid", "shock"]
    assert scene.extras["kind"] == "vehicle"
    [w, l, h] = scene.extras["size"]
    assert w > 0.6 and l > 0.6 and h > 0.6
  end

  test "a pose turns a joint" do
    open = Build.scene(cart(), pose: %{"lid" => 90, "shock" => 0.02})
    closed = Build.scene(cart())
    lid = fn s -> Enum.at(s.nodes, 3).frame end
    refute lid.(open) == lid.(closed)
    assert_in_delta elem(Enum.at(open.nodes, 4).frame.at, 2), 0.25 + 0.02, 1.0e-9
  end

  test "the levels drop small, thin and hidden parts" do
    near = Build.scene(cart(), level: :near) |> Scene.triangles()
    mid = Build.scene(cart(), level: :mid) |> Scene.triangles()
    far = Build.scene(cart(), level: :far) |> Scene.triangles()
    assert near > mid and mid > far
    json = GLBHelper.json(Build.glb(cart(), level: :far))
    assert hd(json["scenes"])["extras"]["level"] == "far"
  end

  test "a part with detail :always stays, and :near goes" do
    lamp = %{Fasteners.washer("M3") | detail: :always}
    small = %{Stock.rod(0.2, 0.2, :steel) | detail: :near}

    a =
      Assembly.new("lamps", frame_part())
      |> Assembly.add("lamp", lamp, at: "hole", port: "face")
      |> Assembly.add("small", small, at: "hole", port: "end_a")

    assert Build.scene(a, level: :far).nodes |> hd() |> Map.get(:primitives) |> Enum.map(& &1.material) == [
             :paint,
             :steel
           ]
  end

  test "the list of the parts" do
    parts = Build.parts(cart())
    names = Enum.map(parts, & &1["name"])
    assert names == Enum.sort(names)
    assert %{"count" => 16} = Enum.find(parts, &(&1["name"] == "spoke_wire"))

    assert %{"count" => 1, "kind" => "bolt", "params" => %{"thread" => "M8"}} =
             Enum.find(parts, &(&1["name"] == "bolt_m8x50"))
  end

  test "errors: a node twice, an unknown node, a port, a joint with no role" do
    a = Assembly.new("x", frame_part())

    assert_raise ArgumentError, ~r/has a node body/, fn ->
      Assembly.add(a, "body", frame_part(), at: "hole", port: "hole")
    end

    assert_raise ArgumentError, ~r/has no node nope/, fn ->
      Assembly.add(a, "b", frame_part(), to: "nope", at: "hole", port: "hole")
    end

    assert_raise ArgumentError, ~r/has no port "nope"/, fn ->
      Assembly.add(a, "b", frame_part(), at: "nope", port: "hole")
    end

    assert_raise ArgumentError, ~r/has no role/, fn ->
      Assembly.add(a, "b", frame_part(), at: "hole", port: "hole", kind: :turns)
    end

    assert_raise ArgumentError, ~r/has no node nope/, fn -> Assembly.node_frame(a, "nope") end
  end

  test "an empty scene has no size" do
    a = Assembly.new("empty", %{Stock.rod(0.001, 0.001, :steel) | detail: :near})
    assert Build.scene(a, level: :far).extras["size"] == [0.0, 0.0, 0.0]
  end

  test "Part helpers" do
    p =
      Stock.rod(0.01, 0.1, :steel)
      |> Part.paint(:black)
      |> Part.rename("pin")
      |> Part.with_ports([Part.port("mid", {0, 0, 0.05}, {0, 0, 1})])

    assert p.name == "pin"
    assert hd(p.shapes).material == :black
    assert Map.has_key?(p.ports, "mid")
    assert Port.frame(Part.port!(p, "mid")).at == {0.0, 0.0, 0.05}
  end
end
