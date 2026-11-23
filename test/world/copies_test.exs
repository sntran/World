defmodule World.CopiesTest do
  # The copies of plan 0020, step 1 (#45): a node with a tint, a scale or
  # `share`; how the drawing checks them, and how the frames, the build,
  # the GLB and the mass take them. (The parts list: elements_test.exs.)
  use ExUnit.Case, async: true

  alias World.{Assembly, Build, Drawing, Frame, GLB, GLBHelper, Mass, Mirror, Part, Scene, Shape, Tint}

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})
  @top Part.port("top", {0.1, 0.05, 0.06}, {0, 0, 1}, {0, 1, 0})

  defp brick(name \\ "brick"), do: Part.new(name, :brick, [Shape.box({0, 0, 0}, {0.2, 0.1, 0.06}, :brick)], [@o, @top])
  defp base, do: Part.new("base", :part, [Shape.box({0, 0, -0.01}, {4.0, 0.1, 0.0}, :steel)], [@o])
  defp at(i), do: Part.port("p#{i}", {0.2 * i, 0, 0}, {0, 0, 1}, {0, 1, 0})

  defp near({a, b, c}, {x, y, z}), do: abs(a - x) < 1.0e-9 and abs(b - y) < 1.0e-9 and abs(c - z) < 1.0e-9

  # Each point of a scene in its axes (each instance of a node too).
  defp points(%Scene{} = s) do
    frames = Scene.world_frames(s)

    s.nodes
    |> Enum.with_index()
    |> Enum.flat_map(fn {n, i} ->
      for f <- if(n.instances, do: Enum.map(n.instances, &Frame.compose(frames[i], &1)), else: [frames[i]]),
          p <- n.primitives,
          pt <- p.positions,
          do: pt |> then(&Frame.point(f, &1)) |> Tuple.to_list() |> Enum.map(fn v -> Float.round(v / 1, 6) end)
    end)
    |> MapSet.new()
  end

  test "a frame with a scale: its points, its inverse, its turn, and the scale of its axes" do
    rigid = Frame.compose(Frame.move({1.0, 2.0, 3.0}), Frame.turn({0.0, 0.0, 1.0}, 90))
    f = Frame.compose(rigid, Frame.scale(2))
    assert_in_delta Frame.scale_of(f), 2.0, 1.0e-12
    assert Frame.scale_of(rigid) == 1.0 and Frame.scale_of(Frame.scale(1)) == 1.0

    p = {0.5, -0.25, 1.0}
    assert near(Frame.point(f, p), {1.5, 3.0, 5.0})
    assert near(Frame.point(Frame.invert(f), Frame.point(f, p)), p)
    assert near(Frame.point(Frame.compose(Frame.invert(f), f), p), p)

    # The turn of a frame with a scale is the turn of its axes with no scale.
    {a, b, c, d} = Frame.quaternion(f)
    {w, x, y, z} = Frame.quaternion(rigid)
    assert near({a, b, c}, {w, x, y}) and abs(d - z) < 1.0e-9
  end

  test "the tint of a copy in a copy, and in linear values" do
    assert Tint.mix(nil, nil) == nil
    assert Tint.mix(nil, "#FF8000") == "#ff8000" and Tint.mix("#FF8000", nil) == "#ff8000"
    assert Tint.mix("#808080", "#ff0000") == "#800000"
    assert Tint.mix("#ffffff", "#0a0b0c") == "#0a0b0c"

    assert Tint.linear(nil) == {1.0, 1.0, 1.0}
    assert {1.0, g, +0.0} = Tint.linear("#ff0800")
    assert_in_delta g, 8 / 255 / 12.92, 1.0e-5
  end

  defp drawing(nodes, root \\ %{}) do
    box = %{
      "shapes" => [%{"box" => %{"from" => [0, 0, 0], "to" => [1, 1, 1]}}],
      "ports" => %{"top" => %{"at" => [0.5, 0.5, 1]}}
    }

    %{
      "name" => "street",
      "parts" => %{"box" => box},
      "nodes" => [Map.merge(%{"name" => "ground", "part" => "box"}, root) | nodes]
    }
  end

  test "the check of a tint, a scale and share: in a node, in each copy of a repeat, and not for the root" do
    good = %{"name" => "a", "part" => "box", "to" => "ground", "tint" => "#AABBCC", "scale" => 0.5, "share" => true}
    assert {:ok, _} = Drawing.check(drawing([good]), "drawing")

    bad = %{good | "tint" => "red", "scale" => 11, "share" => "yes"}

    assert {:error, errors} = Drawing.check(drawing([bad]), "drawing")

    assert Enum.sort(errors) == [
             {"drawing.nodes.1.scale", "must be a number from 0.1 to 10"},
             {"drawing.nodes.1.share", "must be one of: true, false"},
             {"drawing.nodes.1.tint", "must be a color #rrggbb"}
           ]

    assert {:error, [{"drawing.nodes.1.scale", _}]} = Drawing.check(drawing([%{good | "scale" => 0.05}]), "drawing")

    # A node of a repeat: the error is in each copy, at its path.
    repeat = %{
      "repeat" => %{"for" => "i", "in" => %{"count" => 2}},
      "node" => %{"name" => "r_{i}", "part" => "box", "to" => "ground", "tint" => "\#{i}"}
    }

    assert {:error, errors} = Drawing.check(drawing([repeat]), "drawing")

    assert errors == [
             {"drawing.nodes.1.tint", "must be a color #rrggbb"},
             {"drawing.nodes.2.tint", "must be a color #rrggbb"}
           ]

    assert {:error, errors} =
             Drawing.check(drawing([], %{"tint" => "#ffffff", "scale" => 2, "share" => true}), "drawing")

    assert Enum.sort(errors) == for(k <- ~w(scale share tint), do: {"drawing.nodes.0.#{k}", "is not for the root"})
  end

  test "a drawing gives the tint, the scale and share of each node to its connection, and each copy of a repeat its own tint" do
    repeat = %{
      "repeat" => %{"for" => "c", "in" => ["ff0000", "00ff00"]},
      "node" => %{"name" => "r_{c}", "part" => "box", "to" => "ground", "tint" => "\#{c}"}
    }

    d =
      drawing([
        %{"name" => "a", "part" => "box", "to" => "ground", "tint" => "#AABBCC", "scale" => 0.5, "share" => true},
        %{"name" => "b", "part" => "box", "to" => "a", "at" => "top"},
        repeat
      ])

    assert {:ok, _} = Drawing.check(d, "drawing")
    a = Drawing.build(Drawing.expand(d))
    [_, {"a", _, ca}, {"b", _, cb}, {"r_ff0000", _, c1}, {"r_00ff00", _, c2}] = a.nodes
    assert {ca.tint, ca.scale, ca.share} == {"#AABBCC", 0.5, true}
    assert {cb.tint, cb.scale, cb.share} == {nil, 1.0, false}
    assert {c1.tint, c2.tint} == {"#ff0000", "#00ff00"}

    assert Build.copies(a, :near) == %{
             "a" => %{tint: "#aabbcc", scale: 0.5, share: true},
             "r_ff0000" => %{tint: "#ff0000", scale: 1.0, share: false},
             "r_00ff00" => %{tint: "#00ff00", scale: 1.0, share: false}
           }
  end

  test "a copy with a tint or a scale is a node of its own with the mesh of the part; a node on its port keeps its own size" do
    row = fn scale ->
      Assembly.new("row", base(), root: "base")
      |> Assembly.add("b1", brick(), at: at(1), port: "o", tint: "#ff0000")
      |> Assembly.add("b2", brick(), at: at(2), port: "o", scale: scale)
      |> Assembly.add("b3", brick(), at: at(3), port: "o")
      |> Assembly.add("b4", brick(), to: "b2", at: "top", port: "o")
    end

    a = row.(2)
    s = Build.scene(a)
    # (b3 and b4 are small and not copies: in the mesh of the root.)
    assert [root, b1, b2] = s.nodes
    assert b1.extras == %{"tint" => "#ff0000"} and b2.extras == %{}
    assert b1.mesh == b2.mesh and b1.primitives == b2.primitives
    assert Frame.scale_of(b1.frame) == 1.0
    assert_in_delta Frame.scale_of(b2.frame), 2.0, 1.0e-12
    assert length(root.primitives) == 2

    # The top of b2 is at twice its place; b4 on it has the size of a brick.
    [_, _, f2, _, f4] = for {f, _} <- Build.placed(a), do: f
    assert near(Frame.point(f2, {0.2, 0.1, 0.06}), {0.8, 0.2, 0.12})
    assert near(f4.at, {0.6, 0.1, 0.12}) and Frame.scale_of(f4) == 1.0
    assert near(Assembly.node_frame(a, "b4").at, f4.at)
    assert_in_delta Scene.bounds(s) |> elem(1) |> elem(2), 0.18, 1.0e-9

    # The GLB: the tint in the extras of the node, the scale in the node.
    json = s |> GLB.encode() |> GLBHelper.json()
    [_, n1, n2] = json["nodes"]
    assert n1["extras"] == %{"tint" => "#ff0000"} and n1["scale"] == nil and n1["mesh"] == n2["mesh"]
    assert n2["scale"] == [2.0, 2.0, 2.0]

    # The mass of a copy at twice the size: 8 times the mass.
    one = Mass.part(brick()).mass
    assert one > 0
    assert_in_delta Mass.of(a).mass - Mass.of(row.(1)).mass, 7 * one, 1.0e-9
  end

  test "16 copies in one node are one node with instances, with the scale and the tint of each when one copy has them" do
    a =
      Enum.reduce(1..16, Assembly.new("row", base(), root: "base"), fn i, a ->
        copy = if(i <= 4, do: [tint: "#00ff00"], else: if(i <= 8, do: [scale: 0.5], else: []))
        Assembly.add(a, "b#{i}", brick(), [at: at(i), port: "o"] ++ copy)
      end)

    s = Build.scene(a)
    assert [_, %Scene.Node{name: "brick", instances: frames, tints: tints}] = s.nodes
    assert length(frames) == 16 and tints == List.duplicate("#00ff00", 4) ++ List.duplicate(nil, 12)

    glb = GLB.encode(s)

    %{"attributes" => attributes} =
      glb |> GLBHelper.json() |> get_in(["nodes", Access.at(1), "extensions", "EXT_mesh_gpu_instancing"])

    assert attributes |> Map.keys() |> Enum.sort() == ~w(ROTATION SCALE TRANSLATION _COLOR_0)
    scales = GLBHelper.floats(glb, attributes["SCALE"])

    assert scales ==
             List.duplicate({1.0, 1.0, 1.0}, 4) ++
               List.duplicate({0.5, 0.5, 0.5}, 4) ++ List.duplicate({1.0, 1.0, 1.0}, 8)

    colors = GLBHelper.floats(glb, attributes["_COLOR_0"])
    assert colors == List.duplicate({0.0, 1.0, 0.0}, 4) ++ List.duplicate({1.0, 1.0, 1.0}, 12)

    # With no instances: a node for each copy with a tint or a scale, at the same points.
    flat = Build.scene(a, instances: false)
    assert [_ | copies] = flat.nodes
    assert length(copies) == 8 and Enum.count(copies, &(&1.extras == %{"tint" => "#00ff00"})) == 4
    assert points(s) == points(flat)

    # 16 copies with no tint and no scale: no SCALE and no _COLOR_0.
    plain =
      Enum.reduce(
        1..16,
        Assembly.new("row", base(), root: "base"),
        &Assembly.add(&2, "b#{&1}", brick(), at: at(&1), port: "o")
      )

    assert [_, %{tints: nil}] = Build.scene(plain).nodes

    %{"attributes" => attributes} =
      plain
      |> Build.glb()
      |> GLBHelper.json()
      |> get_in(["nodes", Access.at(1), "extensions", "EXT_mesh_gpu_instancing"])

    assert attributes |> Map.keys() |> Enum.sort() == ~w(ROTATION TRANSLATION)
  end

  test "share: true shares the mesh of a small part; a mirror in a copy has its scale of -1 on x times the scale of the copy" do
    a =
      Assembly.new("row", base(), root: "base")
      |> Assembly.add("b1", brick(), at: at(1), port: "o", share: true)
      |> Assembly.add("b2", brick(), at: at(2), port: "o")
      |> Assembly.add("m", Mirror.part(brick(), "brick_left"), at: at(3), port: "o", scale: 2)

    s = Build.scene(a)
    assert [_root, b1, m] = s.nodes
    assert b1.extras == %{} and b1.mesh == m.mesh and m.scale == {-1.0, 1.0, 1.0}
    [_, n1, nm] = s |> GLB.encode() |> GLBHelper.json() |> Map.fetch!("nodes")
    assert n1["scale"] == nil and nm["scale"] == [-2.0, 2.0, 2.0]

    assert Build.copies(a, :near) == %{
             "b1" => %{tint: nil, scale: 1.0, share: true},
             "m" => %{tint: nil, scale: 2.0, share: false}
           }
  end

  test "a copy in a copy: the product of the tints and of the scales; a node on a port of a copy is not in it" do
    inner =
      Assembly.new("pair", base(), root: "base")
      |> Assembly.add("x", brick(), at: at(1), port: "o", tint: "#ff0000", scale: 0.5)

    a =
      Assembly.new("street", base(), root: "base")
      |> Assembly.add("house", inner, at: at(1), port: "o", tint: "#808080", scale: 2, share: true)
      |> Assembly.add("next", brick(), to: "house", at: "x/top", port: "o")

    house = %{tint: "#808080", scale: 2.0, share: true}

    assert Build.copies(a, :near) == %{
             "house" => house,
             "house/base" => house,
             "house/x" => %{house | tint: "#800000", scale: 1.0}
           }

    # The brick x is at its own size again (2 × 0.5), at its place in the house at twice its size.
    [_, fb, fx, fnext] = for {f, _} <- Build.placed(a), do: f
    assert_in_delta Frame.scale_of(fb), 2.0, 1.0e-12
    assert Frame.scale_of(fx) == 1.0 and near(fx.at, {0.6, 0.0, 0.0})
    assert Frame.scale_of(fnext) == 1.0 and near(fnext.at, {0.7, 0.05, 0.06})

    s = Build.scene(a)
    tints = for n <- s.nodes, n.extras["tint"], into: %{}, do: {n.name, n.extras["tint"]}
    assert tints == %{"house/base" => "#808080", "house/x" => "#800000"}
  end

  test "a replay file (split: true) has the tint of a copy in the extras of its node" do
    a =
      Assembly.new("row", base(), root: "base")
      |> Assembly.add("b1", brick(), at: at(1), port: "o", tint: "#ff0000")
      |> Assembly.add("b2", brick(), at: at(2), port: "o")

    extras = for n <- Build.scene(a, split: true).nodes, into: %{}, do: {n.name, n.extras}
    assert extras["b1"] == %{"task" => "b1", "tint" => "#ff0000"} and extras["b2"] == %{"task" => "b2"}
  end
end
