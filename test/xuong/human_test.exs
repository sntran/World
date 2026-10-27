defmodule Xuong.HumanTest do
  use ExUnit.Case, async: true

  alias Xuong.{Build, Detail, Figure, Human, Scene}
  alias Xuong.Human.{Data, Pose}

  @limits %{near: 50_000, mid: 12_000, far: 5_000}

  # The size of each person: {width, depth, height} in meters, and the
  # tolerance.
  @sizes %{
    "traveler" => {{0.50, 0.46, 1.65}, 0.05},
    "man" => {{0.50, 0.48, 1.71}, 0.05},
    "woman" => {{0.44, 0.40, 1.58}, 0.05}
  }

  for {name, fun} <- Xuong.Models.all(), Map.has_key?(@sizes, name) do
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
    scene = Build.scene(Detail.with(:far, &Xuong.Models.People.traveler/0), level: :far)
    [walk] = scene.animations
    assert walk.name == "walk"
    assert length(walk.channels) == 8

    for c <- walk.channels do
      assert length(c.times) == 13 and length(c.values) == 13
      # The loop ends where it starts.
      {first, last} = {hd(c.values), List.last(c.values)}

      assert Xuong.Vec.len(Xuong.Vec.sub(first.y, last.y)) < 1.0e-9 and
               Xuong.Vec.len(Xuong.Vec.sub(first.z, last.z)) < 1.0e-9
    end

    glb = Xuong.GLB.encode(scene)
    assert %{"animations" => [_], "skins" => [_]} = Xuong.GLBHelper.json(glb)
  end

  test "a rider sits on the scooter with the hands on the grips" do
    model = Xuong.Models.People.rider()
    scene = Build.scene(Detail.with(:far, fn -> Xuong.Models.People.rider() end), level: :far)
    assert scene.extras["kind"] == "vehicle"
    # The scooter is 1.10 m high; a rider is higher.
    [w, l, h] = scene.extras["size"]
    assert w < 0.75 and abs(l - 1.871) < 0.03 and h > 1.5
    assert Enum.any?(Build.parts(model), &(&1["name"] == "rider"))
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
    assert Human.to_xuong({1.0, 2.0, 3.0}) == {-0.1, 0.30000000000000004, 0.2}
  end

  test "the poses and the animations" do
    assert Pose.names() == ["rest", "ride", "ride_bicycle", "sit", "stand"]
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
      assert Data.dir() =~ "assets/makehuman"
    end
  end
end
