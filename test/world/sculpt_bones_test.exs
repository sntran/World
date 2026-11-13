defmodule World.Sculpt.BonesTest do
  # A sculpture with bones is a skinned mesh, and a clip moves it
  # (plan 0009, D6, R6).
  use ExUnit.Case, async: true

  alias World.{Build, Contact, Detail, Drawing, Figure, Orders, Vec}
  alias World.Sculpt.Bones
  alias World.Skills.Sculpt, as: Skill

  # A fish along y: its snout at y = 0.5, the end of its tail at y = -0.5.
  @fish [
    {"pelvis", nil, 0.0, 0.1},
    {"spine_01", "pelvis", 0.1, 0.25},
    {"head", "spine_01", 0.25, 0.5},
    {"tail_01", "pelvis", 0.0, -0.12},
    {"tail_02", "tail_01", -0.12, -0.24},
    {"tail_03", "tail_02", -0.24, -0.36},
    {"tail_04", "tail_03", -0.36, -0.5}
  ]

  defp bones do
    for {name, parent, from, to} <- @fish do
      bone = %{"name" => name, "head" => [0, from, 0], "tail" => [0, to, 0]}
      if parent, do: Map.put(bone, "parent", parent), else: bone
    end
  end

  defp data do
    %{
      "edits" => [
        %{"shape" => "ellipsoid", "size" => [0.08, 0.5, 0.12], "material" => "paint", "color" => "#c08020"},
        %{"shape" => "ball", "size" => [0.03], "at" => [0.06, 0.3, 0.04], "material" => "gray", "mirror" => "x"}
      ],
      "cells" => %{"near" => 0.02, "mid" => 0.03, "far" => 0.05},
      "ports" => %{
        "hook" => %{"at" => [0, 0.5, 0], "axis" => [0, 1, 0]},
        "ground" => %{"at" => [0, 0, -0.12], "axis" => [0, 0, -1]}
      },
      "sources" => ["A test."],
      "bones" => bones(),
      "plan" => "fish",
      "gait" => %{"period" => 0.8, "stride" => 0.6},
      "clips" => [
        %{
          "name" => "nod",
          "length" => 1.0,
          "keys" => [
            %{"at" => 0.25, "pose" => %{"head" => %{"flex" => 0}}},
            %{"at" => 0.5, "pose" => %{"head" => %{"flex" => 20}, "tail_04" => %{"spread" => 10, "twist" => 5}}},
            %{"at" => 0.75, "pose" => %{}}
          ]
        }
      ]
    }
  end

  defp drawing(data),
    do: %{"name" => "fish", "kind" => "item", "nodes" => [%{"name" => "fish", "skill" => %{"sculpt" => data}}]}

  defp paths(data) do
    case Orders.check(%{"blueprint" => "drawing", "options" => %{"drawing" => drawing(data)}}) do
      {:error, errors} -> Enum.map(errors, & &1["path"])
      {:ok, _} -> []
    end
  end

  # The figure with its bones at the frame `k` of a clip.
  defp at_frame(%Figure{nodes: nodes} = f, clip, k) do
    nodes =
      Enum.reduce(clip.channels, nodes, fn c, nodes ->
        v = Enum.at(c.values, k)

        List.update_at(nodes, c.node, fn n ->
          case c.path do
            :rotation -> %{n | frame: %{v | at: n.frame.at}}
            :translation -> %{n | frame: %{n.frame | at: v}}
          end
        end)
      end)

    %{f | nodes: nodes}
  end

  # The most that a point moves between two lists of points, for the points that `where` keeps (by the point at rest).
  defp most(rest, moved, where) do
    for {p, q} <- Enum.zip(rest, moved), where.(p), reduce: 0.0 do
      acc -> max(acc, Vec.len(Vec.sub(p, q)))
    end
  end

  test "a sculptor makes a figure of a sculpture with bones: one skinned mesh, the clips of its plan and of its keys" do
    assert paths(data()) == []
    {"fish", figure, _} = hd(Detail.with(:mid, fn -> Drawing.build(drawing(data())) end).nodes)
    assert %Figure{skins: [%{joints: joints}], sources: ["A test."], kind: :animal} = figure
    # The speed of the swim of the plan: a stride of 0.6 lengths of 1 m in a period of 0.8 s.
    assert_in_delta figure.params["swim_speed"], 0.75, 0.011
    assert length(joints) == 7
    assert Enum.map(figure.animations, & &1.name) == ~w(swim idle nod)
    assert Map.keys(figure.ports) |> Enum.sort() == ~w(ground hook mouth)
    # The port of the data is on the bone nearest to it.
    assert figure.ports["hook"].bone == "head"
    # A port of the data replaces the port of the plan of the same name.
    assert elem(World.Figure.port_frame(figure, "ground").at, 2) == -0.12

    # Each point has the normal and the color of the finish pass, and weights that sum to 1.
    mesh = List.last(figure.nodes)
    assert Enum.map(mesh.primitives, & &1.material) == [:gray, :paint]

    for p <- mesh.primitives do
      assert length(p.normals) == length(p.positions) and length(p.colors) == length(p.positions)
      for ws <- p.weights, do: assert_in_delta(ws |> Tuple.to_list() |> Enum.sum(), 1.0, 1.0e-9)
    end

    # The normals are the normals of the surface: on the body (far from the eyes), the normal of the ellipsoid.
    paint = Enum.find(mesh.primitives, &(&1.material == :paint))

    for {{x, y, z}, n} <- Enum.zip(paint.positions, paint.normals), y < 0 do
      true_n = Vec.norm({x / 0.08 ** 2, y / 0.5 ** 2, z / 0.12 ** 2})
      assert Vec.dot(n, true_n) > :math.cos(3 * :math.pi() / 180)
    end

    # The swim moves the tail much and the middle of the body little.
    rest = Contact.points(figure)
    swim = Enum.find(figure.animations, &(&1.name == "swim"))
    moved = for k <- 0..16, do: Contact.points(at_frame(figure, swim, k))
    tail = Enum.max(for m <- moved, do: most(rest, m, fn {_, y, _} -> y < -0.4 end))
    middle = Enum.max(for m <- moved, do: most(rest, m, fn {_, y, _} -> abs(y) < 0.05 end))
    assert tail > 0.05 and middle < tail / 4
    # The length of the wave is the period of the gait.
    assert swim.channels |> hd() |> Map.fetch!(:times) |> List.last() == 0.8

    # The clip from keys: 12 frames in its second; the head is down at the key in the middle, and at rest at the ends.
    nod = Enum.find(figure.animations, &(&1.name == "nod"))
    assert length(hd(nod.channels).times) == 13
    snout = fn {_, y, _} -> y > 0.45 end
    assert most(rest, Contact.points(at_frame(figure, nod, 6)), snout) > 0.05
    assert most(rest, Contact.points(at_frame(figure, nod, 0)), snout) < 1.0e-9
    assert most(rest, Contact.points(at_frame(figure, nod, 12)), snout) < 1.0e-9
    half = most(rest, Contact.points(at_frame(figure, nod, 4)), snout)
    assert half > 0.01 and half < most(rest, Contact.points(at_frame(figure, nod, 6)), snout)

    # The GLB of the model has the skin and the clips.
    <<"glTF", 2::little-32, _::little-32, size::little-32, "JSON", json::binary-size(size), _::binary>> =
      Detail.with(:far, fn -> Build.glb(Drawing.build(drawing(data()))) end)

    gltf = JSON.decode!(json)
    assert [%{"joints" => [_, _, _, _, _, _, _]}] = gltf["skins"]
    assert Enum.map(gltf["animations"], & &1["name"]) == ~w(swim idle nod)
    assert Enum.all?(hd(gltf["meshes"])["primitives"], &Map.has_key?(&1["attributes"], "JOINTS_0"))
  end

  test "bones with no plan: the weights by the distance, a blend of the data, a bone along x, a clip of one key" do
    ball = World.Sculpt.model([World.SDF.edit(:ellipsoid, {0.5, 0.1, 0.1})], step: 0.05)

    bones = [
      %{name: "a", head: {-0.5, 0, 0}, tail: {0, 0, 0}},
      %{name: "b", parent: "a", head: {0, 0, 0}, tail: {0.5, 0, 0}}
    ]

    clip = %{name: "bend", length: 0.01, keys: [{0.0, %{"b" => %{"spread" => 30}}}]}
    figure = Bones.figure("worm", ball, bones, blend: 0.1, clips: [clip])
    assert figure.animations |> Enum.map(& &1.name) == ["bend"] and figure.ports == %{}
    assert figure.kind == :item and figure.params == %{}
    [p] = List.last(figure.nodes).primitives
    assert p.colors == nil

    # A point far from the joint follows one bone; a point at the joint follows the two, half each.
    for {{x, _, _}, {a, b, _, _}, {wa, wb, _, _}} <- Enum.zip([p.positions, p.joints, p.weights]) do
      cond do
        x < -0.25 -> assert {a, wa} == {0, 1.0}
        x > 0.25 -> assert {a, wa} == {1, 1.0}
        abs(x) < 0.01 -> assert Enum.sort([a, b]) == [0, 1] and abs(wa - wb) < 0.01
        true -> assert wa >= wb
      end
    end

    # The hinge of a bone along x is z: the bend turns the points of the bone b round the joint.
    rest = Contact.points(figure)
    bent = Contact.points(at_frame(figure, hd(figure.animations), 0))
    assert most(rest, bent, fn {x, _, _} -> x > 0.4 end) > 0.1
    assert most(rest, bent, fn {x, _, _} -> x < -0.2 end) < 1.0e-9

    # With no blend in the options: half the mean length of the bones.
    wide = Bones.figure("worm", ball, bones)
    [q] = List.last(wide.nodes).primitives
    two = fn prim -> Enum.count(prim.weights, fn {_, w, _, _} -> w > 0 end) end
    assert two.(q) > two.(p)
    assert Bones.plans() == ~w(biped bird fish) and Bones.turns() == ~w(flex spread twist)
  end

  # A puppet of 1 m on two legs. With `out`, its arms are out to the sides (a T); with no `out`, down.
  defp puppet(out) do
    arm = fn s, sign ->
      points =
        if out,
          do: [[sign * 0.12, 0, 0.78], [sign * 0.3, 0, 0.78], [sign * 0.46, 0, 0.78], [sign * 0.54, 0, 0.78]],
          else: [[sign * 0.12, 0, 0.78], [sign * 0.14, 0, 0.6], [sign * 0.15, 0, 0.44], [sign * 0.155, 0, 0.36]]

      [{"upperarm", "spine_01"}, {"lowerarm", "upperarm_#{s}"}, {"hand", "lowerarm_#{s}"}]
      |> Enum.zip(Enum.chunk_every(points, 2, 1, :discard))
      |> Enum.map(fn {{name, parent}, [head, tail]} ->
        %{"name" => "#{name}_#{s}", "parent" => parent, "head" => head, "tail" => tail}
      end)
    end

    leg = fn s, sign ->
      x = sign * 0.07

      [
        %{"name" => "thigh_#{s}", "parent" => "pelvis", "head" => [x, 0, 0.5], "tail" => [x, 0, 0.27]},
        %{"name" => "calf_#{s}", "parent" => "thigh_#{s}", "head" => [x, 0, 0.27], "tail" => [x, 0, 0.05]},
        %{"name" => "foot_#{s}", "parent" => "calf_#{s}", "head" => [x, 0, 0.05], "tail" => [x, 0.1, 0.01]}
      ]
    end

    limb =
      if out,
        do: %{"shape" => "capsule", "size" => [0.2, 0.03], "at" => [0.34, 0, 0.78], "axis" => [1, 0, 0]},
        else: %{"shape" => "capsule", "size" => [0.2, 0.03], "at" => [0.14, 0, 0.58]}

    %{
      "edits" => [
        %{"shape" => "capsule", "size" => [0.12, 0.09], "at" => [0, 0, 0.66], "color" => "#4060a0"},
        %{"shape" => "ball", "size" => [0.09], "at" => [0, 0, 0.92], "color" => "#d0a080"},
        Map.merge(limb, %{"mirror" => "x", "color" => "#d0a080"}),
        %{"shape" => "capsule", "size" => [0.22, 0.04], "at" => [0.07, 0, 0.27], "mirror" => "x", "color" => "#303030"},
        %{"shape" => "box", "size" => [0.035, 0.07, 0.02], "at" => [0.07, 0.04, 0.02], "mirror" => "x"}
      ],
      "cells" => %{"mid" => 0.012},
      "bones" =>
        [
          %{"name" => "pelvis", "head" => [0, 0, 0.5], "tail" => [0, 0, 0.6]},
          %{"name" => "spine_01", "parent" => "pelvis", "head" => [0, 0, 0.6], "tail" => [0, 0, 0.8]},
          %{"name" => "neck_01", "parent" => "spine_01", "head" => [0, 0, 0.8], "tail" => [0, 0, 0.85]},
          %{"name" => "head", "parent" => "neck_01", "head" => [0, 0, 0.85], "tail" => [0, 0, 1.0]}
          # The left side is at -x.
        ] ++ arm.("l", -1) ++ leg.("l", -1) ++ arm.("r", 1) ++ leg.("r", 1),
      "plan" => "biped",
      "gait" => %{"period" => 1.0, "stride" => 0.3, "lift" => 0.05}
    }
  end

  # The mean move of the points of the figure at rest that are in a region.
  defp move(rest, moved, where) do
    moves = for {p, q} <- Enum.zip(rest, moved), where.(p), do: Vec.sub(q, p)
    Vec.scale(Enum.reduce(moves, &Vec.add/2), 1 / length(moves))
  end

  test "a sculpture with the bones of a person has the walk of a body on two legs: its feet move in turn (plan 0010, R12)" do
    data = puppet(false)
    assert paths(data) == []
    {"fish", figure, _} = hd(Detail.with(:mid, fn -> Drawing.build(drawing(data)) end).nodes)
    assert Enum.map(figure.animations, & &1.name) == ~w(walk run idle)
    assert figure.kind == :animal
    # A stride of 0.3 heights of 1.01 m in 0.6 of a period of 1 s.
    assert_in_delta figure.params["walk_speed"], 0.5, 0.011
    assert figure.params["run_speed"] > 2 * figure.params["walk_speed"]
    assert Map.keys(figure.ports) |> Enum.sort() == ~w(grip_l grip_r ground head)
    assert figure.ports["grip_l"].bone == "hand_l" and figure.ports["head"].bone == "head"
    rest = Contact.points(figure)
    walk = Enum.find(figure.animations, &(&1.name == "walk"))
    at = fn clip, k -> Contact.points(at_frame(figure, clip, k)) end
    foot = fn sign -> fn {x, _, z} -> x * sign > 0 and z < 0.045 end end
    # (The legs are 0.11 m out at the most.)
    hand = fn sign -> fn {x, _, z} -> x * sign > 0.12 and z < 0.42 end end
    stride = 0.3 * 1.01

    # The start of a step: the left foot is half a stride to the front,
    # the right foot is to the back, the two flat on the ground.
    {_, ly, lz} = move(rest, at.(walk, 0), foot.(-1))
    {_, ry, rz} = move(rest, at.(walk, 0), foot.(1))
    assert_in_delta ly, stride / 2, 0.004
    assert_in_delta ry, -stride / 3, 0.004
    assert abs(lz) < 0.002 and abs(rz) < 0.002

    # A foot on the ground does not go up or down, and goes to the back
    # at one speed (the body goes to the front over it): the left foot
    # for the first 0.6 of the step.
    for k <- 1..9 do
      {x, y, z} = move(rest, at.(walk, k), foot.(-1))
      assert abs(x) < 0.002 and abs(z) < 0.002
      assert_in_delta y, stride * (0.5 - k / 16 / 0.6), 0.004
    end

    # Then it goes up and to the front, while the right foot is on the ground.
    {_, _, up} = move(rest, at.(walk, 13), foot.(-1))
    assert up > 0.03
    assert abs(elem(move(rest, at.(walk, 13), foot.(1)), 2)) < 0.002
    # Half a step later, the feet are the other way.
    assert_in_delta elem(move(rest, at.(walk, 8), foot.(1)), 1), stride / 2, 0.004
    assert elem(move(rest, at.(walk, 8), foot.(-1)), 1) < -0.08

    # The hands swing against the feet.
    assert elem(move(rest, at.(walk, 0), hand.(-1)), 1) < -0.04 and elem(move(rest, at.(walk, 0), hand.(1)), 1) > 0.04
    assert elem(move(rest, at.(walk, 8), hand.(-1)), 1) > 0.04 and elem(move(rest, at.(walk, 8), hand.(1)), 1) < -0.04
    # The head is low when the feet are far from each other, and high over the foot on the ground.
    head = fn {_, _, z} -> z > 0.9 end
    assert elem(move(rest, at.(walk, 0), head), 2) < elem(move(rest, at.(walk, 5), head), 2) - 0.02
    assert elem(move(rest, at.(walk, 5), head), 2) <= 0.0

    # The run: in the middle of a step the body is in the air (no foot
    # at the ground), and the hands are in front of the body, the elbows bent.
    run = Enum.find(figure.animations, &(&1.name == "run"))
    assert Enum.any?(0..16, fn k -> Enum.all?([-1, 1], &(elem(move(rest, at.(run, k), foot.(&1)), 2) > 0.005)) end)
    for sign <- [-1, 1], do: assert(elem(move(rest, at.(run, 4), hand.(sign)), 1) > 0.05)
    # The idle: the feet stay, the body goes down and up a little.
    idle = Enum.find(figure.animations, &(&1.name == "idle"))
    assert Vec.len(move(rest, at.(idle, 6), foot.(-1))) < 0.002
    assert elem(move(rest, at.(idle, 6), head), 2) < elem(move(rest, at.(idle, 0), head), 2) - 0.002

    # A body with its arms out to the sides: the walk takes the two hands down to the sides, the same way.
    t = puppet(true)
    assert paths(t) == []
    {"fish", wide, _} = hd(Detail.with(:mid, fn -> Drawing.build(drawing(t)) end).nodes)
    rest = Contact.points(wide)
    tip = fn sign -> fn {x, _, _} -> x * sign > 0.47 end end

    for name <- ~w(walk run) do
      clip = Enum.find(wide.animations, &(&1.name == name))
      moved = Contact.points(at_frame(wide, clip, 4))
      {lx, ly, lz} = move(rest, moved, tip.(-1))
      {rx, ry, rz} = move(rest, moved, tip.(1))
      # The hands come in and down; in the run they are in front of the body, on the two sides.
      assert lx > 0.25 and lz < -0.15
      assert_in_delta lx, -rx, 0.01
      assert_in_delta lz, rz, 0.01
      assert_in_delta ly, ry, 0.01
      if name == "run", do: assert(ly > 0.1)
    end

    # The hinge of a forearm or of a calf that points to the front is across the body.
    assert World.Animals.Biped.hinge("lowerarm_l", {0.0, 1.0, 0.0}) == {1.0, 0.0, 0.0}
    assert World.Animals.Biped.hinge("calf_r", {0.0, -1.0, 0.0}) == {-1.0, 0.0, 0.0}
    assert World.Animals.Biped.hinge("lowerarm_l", {0.0, 0.0, -1.0}) == {1.0, 0.0, 0.0}
    assert World.Animals.Biped.hinge("calf_l", {0.0, 0.0, -1.0}) == {-1.0, 0.0, 0.0}

    # A body with no hand: the plan needs each of its bones. A lift of the gait is a part of the height.
    assert paths(Map.put(data, "bones", Enum.reject(data["bones"], &(&1["name"] == "hand_l")))) == [
             "options.drawing.nodes.0.skill.sculpt.plan"
           ]

    assert paths(put_in(data, ["gait", "lift"], 2)) == ["options.drawing.nodes.0.skill.sculpt.gait.lift"]
  end

  # The bones of one side of a small bird: its wing, folded to the back, and its leg.
  defp bird_side(s, sign) do
    {x, l} = {sign * 0.05, sign * 0.03}

    for {name, parent, head, tail} <- [
          {"upperarm", "spine_01", [x, 0.03, 0.2], [x * 1.2, -0.02, 0.19]},
          {"lowerarm", "upperarm_#{s}", [x * 1.2, -0.02, 0.19], [x * 1.2, -0.06, 0.18]},
          {"hand", "lowerarm_#{s}", [x * 1.2, -0.06, 0.18], [x * 1.1, -0.1, 0.17]},
          {"thigh", "pelvis", [l, -0.01, 0.15], [l, 0.0, 0.11]},
          {"calf", "thigh_#{s}", [l, 0.0, 0.11], [l, -0.015, 0.06]},
          {"foot", "calf_#{s}", [l, -0.015, 0.06], [l, -0.005, 0.01]},
          {"ball", "foot_#{s}", [l, -0.005, 0.01], [l, 0.03, 0.005]}
        ] do
      %{"name" => "#{name}_#{s}", "parent" => parent, "head" => head, "tail" => tail}
    end
  end

  test "a sculpture with the bones of a bird has its clips: the flap opens the two wings, the walk moves the feet (plan 0010, R8)" do
    bones =
      [
        %{"name" => "pelvis", "head" => [0, -0.06, 0.16], "tail" => [0, 0.0, 0.17]},
        %{"name" => "spine_01", "parent" => "pelvis", "head" => [0, 0.0, 0.17], "tail" => [0, 0.06, 0.19]},
        %{"name" => "neck_01", "parent" => "spine_01", "head" => [0, 0.06, 0.19], "tail" => [0, 0.08, 0.26]},
        %{"name" => "head", "parent" => "neck_01", "head" => [0, 0.08, 0.26], "tail" => [0, 0.1, 0.29]},
        %{"name" => "beak", "parent" => "head", "head" => [0, 0.1, 0.28], "tail" => [0, 0.14, 0.275]},
        %{"name" => "tail_01", "parent" => "pelvis", "head" => [0, -0.06, 0.16], "tail" => [0, -0.13, 0.19]}
        # The left side is at -x (x is to the right side).
      ] ++ bird_side("l", -1) ++ bird_side("r", 1)

    data = %{
      "edits" => [
        %{"shape" => "ellipsoid", "size" => [0.06, 0.09, 0.06], "at" => [0, 0, 0.17]},
        %{"shape" => "ball", "size" => [0.035], "at" => [0, 0.09, 0.275], "blend" => 0.03},
        %{"shape" => "cone", "size" => [0.012, 0.0, 0.02], "at" => [0, 0.135, 0.275], "axis" => [0, 1, 0]},
        %{"shape" => "ellipsoid", "size" => [0.012, 0.06, 0.035], "at" => [0.062, -0.03, 0.185], "mirror" => "x"},
        %{"shape" => "capsule", "size" => [0.05, 0.008], "at" => [0.03, -0.008, 0.06], "mirror" => "x"},
        %{"shape" => "box", "size" => [0.012, 0.03, 0.005], "at" => [0.03, 0.01, 0.005], "mirror" => "x"},
        %{"shape" => "ellipsoid", "size" => [0.03, 0.05, 0.012], "at" => [0, -0.1, 0.18], "blend" => 0.02}
      ],
      "cells" => %{"mid" => 0.008},
      "bones" => bones,
      "plan" => "bird",
      "gait" => %{"period" => 0.5, "stride" => 0.3}
    }

    assert paths(data) == []
    assert Bones.plans() == ~w(biped bird fish)
    {"fish", figure, _} = hd(Detail.with(:mid, fn -> Drawing.build(drawing(data)) end).nodes)
    assert Enum.map(figure.animations, & &1.name) == ~w(walk idle peck flap)
    assert figure.kind == :animal and Map.has_key?(figure.params, "walk_speed")
    assert Map.keys(figure.ports) |> Enum.sort() == ~w(back beak ground)
    rest = Contact.points(figure)

    # In the middle of the flap the wings are open: the tips of the two wings are far out, each on its side.
    flap = Enum.find(figure.animations, &(&1.name == "flap"))
    open = Contact.points(at_frame(figure, flap, 12))
    tips = for {{x, y, _}, {qx, _, _}} <- Enum.zip(rest, open), y < -0.08, abs(x) > 0.05, do: {x, qx}
    assert Enum.any?(tips, fn {x, _} -> x < 0 end) and Enum.any?(tips, fn {x, _} -> x > 0 end)
    for {x, qx} <- tips, do: assert(abs(qx) > abs(x) + 0.05 and qx * x > 0)
    # The body stays.
    assert most(rest, open, fn {x, y, z} -> abs(x) < 0.02 and abs(y) < 0.03 and z > 0.14 end) < 0.01

    # The walk: the feet go to the front and to the back in turn; the peck takes the beak down.
    walk = Enum.find(figure.animations, &(&1.name == "walk"))
    foot = fn {_, _, z} -> z < 0.02 end
    assert Enum.max(for k <- 0..16, do: most(rest, Contact.points(at_frame(figure, walk, k)), foot)) > 0.03
    peck = Enum.find(figure.animations, &(&1.name == "peck"))
    assert most(rest, Contact.points(at_frame(figure, peck, 2)), fn {_, y, _} -> y > 0.13 end) > 0.05

    # A bird with no beak: the plan needs each of its bones.
    assert paths(Map.put(data, "bones", Enum.reject(bones, &(&1["name"] == "beak")))) == [
             "options.drawing.nodes.0.skill.sculpt.plan"
           ]
  end

  test "the errors of the bones, the plan, the gait and the clips, each with its path" do
    d = data()
    bad = fn key, value -> paths(Map.put(d, key, value)) end
    at = "options.drawing.nodes.0.skill.sculpt"

    assert "#{at}.bones" in bad.("bones", [])
    assert "#{at}.bones" in bad.("bones", 7)

    bones = fn change -> bad.("bones", change.(bones())) end
    assert "#{at}.bones.0.parent" in bones.(&List.update_at(&1, 0, fn b -> Map.put(b, "parent", "head") end))
    assert "#{at}.bones.1.parent" in bones.(&List.update_at(&1, 1, fn b -> Map.put(b, "parent", "tail_04") end))
    assert "#{at}.bones.1.parent" in bones.(&List.update_at(&1, 1, fn b -> Map.delete(b, "parent") end))
    assert "#{at}.bones.2.name" in bones.(&List.update_at(&1, 2, fn b -> Map.put(b, "name", "pelvis") end))
    assert "#{at}.bones.2.name" in bones.(&List.update_at(&1, 2, fn b -> Map.put(b, "name", "Head 1") end))
    assert "#{at}.bones.3.tail" in bones.(&List.update_at(&1, 3, fn b -> Map.put(b, "tail", b["head"]) end))
    assert "#{at}.bones.3.head" in bones.(&List.update_at(&1, 3, fn b -> Map.put(b, "head", [0, 0]) end))
    assert "#{at}.bones.4.radius" in bones.(&List.update_at(&1, 4, fn b -> Map.put(b, "radius", 1) end))
    assert "#{at}.bones.5" in bones.(&List.replace_at(&1, 5, "tail_03"))
    # The plan needs each of its bones.
    assert bones.(&Enum.take(&1, 6)) == ["#{at}.plan", "#{at}.clips.0.keys.1.pose.tail_04"]

    assert bad.("plan", "snake") == ["#{at}.plan"]
    assert bad.("bone_blend", 0) == ["#{at}.bone_blend"]

    assert bad.("gait", %{"period" => 0, "stride" => 9, "lift" => 2}) ==
             ~w(period stride lift) |> Enum.map(&"#{at}.gait.#{&1}")

    assert bad.("gait", 3) == ["#{at}.gait"]
    assert paths(Map.delete(d, "plan")) == ["#{at}.gait"]
    # With no bones, each key of the bones is an error.
    assert paths(Map.delete(d, "bones"))
           |> Enum.filter(&(&1 in for(k <- ~w(clips gait plan), do: "#{at}.#{k}")))
           |> length() == 3

    clip = fn change -> bad.("clips", [change.(hd(d["clips"]))]) end
    assert bad.("clips", 3) == ["#{at}.clips"]
    assert bad.("clips", [3]) == ["#{at}.clips.0"]
    assert bad.("clips", d["clips"] ++ d["clips"]) == ["#{at}.clips"]
    assert clip.(&Map.put(&1, "name", "swim")) == ["#{at}.clips"]
    assert clip.(&Map.put(&1, "name", "Nod!")) == ["#{at}.clips.0.name"]
    assert clip.(&Map.put(&1, "length", 0)) == ["#{at}.clips.0.length"]
    assert clip.(&Map.put(&1, "length", "long")) == ["#{at}.clips.0.length"]
    assert clip.(&Map.put(&1, "keys", [])) == ["#{at}.clips.0.keys"]
    assert clip.(&Map.put(&1, "keys", [1])) == ["#{at}.clips.0.keys.0"]

    assert clip.(&Map.put(&1, "keys", [%{"at" => 2, "pose" => 1}])) == [
             "#{at}.clips.0.keys.0.at",
             "#{at}.clips.0.keys.0.pose"
           ]

    pose = fn pose -> clip.(&Map.put(&1, "keys", [%{"at" => 0, "pose" => pose}])) end
    assert pose.(%{"fin" => %{"flex" => 1}}) == ["#{at}.clips.0.keys.0.pose.fin"]
    assert pose.(%{"head" => 20}) == ["#{at}.clips.0.keys.0.pose.head"]

    assert pose.(%{"head" => %{"flex" => 200, "bend" => 1}}) == [
             "#{at}.clips.0.keys.0.pose.head.bend",
             "#{at}.clips.0.keys.0.pose.head.flex"
           ]

    assert Skill.estimate(d, :far) > 0
  end
end
