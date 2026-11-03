defmodule World.KitTest do
  use ExUnit.Case, async: true

  alias World.{Detail, GLB}
  alias World.People.{Human, Kit}

  doctest World.People.Human, only: [kit_targets: 1, shapes: 0, shape_targets: 0]
  doctest World.People, only: [place: 2]
  doctest World.People.Kit
  doctest World.People.Data, only: [body_points: 0, sliders: 0, known?: 2]

  test "a name of an asset in the code that no asset has stops the compile" do
    good = "require World.People.Data; World.People.Data.names!(\"clothes\", [\"shoes01\"])"
    assert {["shoes01"], _} = Code.eval_string(good)

    assert {"short02", _} =
             Code.eval_string("require World.People.Data; World.People.Data.name!(\"hair\", \"short02\")")

    assert {%{name: "teeth_base"}, _} =
             Code.eval_string("require World.People.Data; World.People.Data.asset!(\"teeth\", \"teeth_base\")")

    assert_raise CompileError, ~r{no asset hair/mohawk}, fn ->
      Code.eval_string("require World.People.Data; World.People.Data.name!(\"hair\", \"mohawk\")")
    end
  end

  test "the targets of a kit: each group has the same moves, and no group is empty" do
    for g <- [0, 1] do
      groups = Human.kit_groups(g)
      names = List.flatten(groups)
      assert names -- Human.kit_targets(g) == []
      # The targets of the mean weight have no move.
      assert length(Human.kit_targets(g)) - length(names) == 2

      for [first | rest] <- groups,
          other <- rest,
          do: assert(Map.new(World.People.Data.target(first)) == Map.new(World.People.Data.target(other)))
    end
  end

  # The points of a primitive of the kit for the numbers of a person, at
  # rest: the points, the moves of the targets by their weights, the
  # moves of the bones by the weights of the skin, and the ground.
  defp join(prim, extras, numbers, shoes) do
    weights = Map.new(Human.target_weights(numbers))
    w = for names <- extras["targets"], do: names |> Enum.map(&Map.get(weights, &1, 0.0)) |> Enum.sum()
    # The moves of the bones are in the axes of glTF.
    world = fn [x, y, z] -> {-x, z, y} end

    bones =
      for {name, moves} <- extras["bones"], into: %{} do
        {name,
         Enum.zip(moves, w) |> Enum.map(fn {d, k} -> World.Vec.scale(world.(d), k) end) |> Enum.reduce(&World.Vec.add/2)}
      end

    order = extras["order"]
    [g0, dg] = extras["ground"][shoes]
    ground = g0 + (Enum.zip(dg, w) |> Enum.map(fn {d, k} -> d * k end) |> Enum.sum())

    targets = Enum.take(prim.targets, length(w))

    for {{p, i}, {js, ws}} <- Enum.zip(Enum.with_index(prim.positions), Enum.zip(prim.joints, prim.weights)) do
      shape = Enum.zip(targets, w) |> Enum.map(fn {{_, m}, k} -> World.Vec.scale(Map.get(m, i, {0.0, 0.0, 0.0}), k) end)

      rigid =
        Enum.zip(Tuple.to_list(js), Tuple.to_list(ws))
        |> Enum.map(fn {b, k} -> World.Vec.scale(bones[Enum.at(order, b)], k) end)

      Enum.reduce(shape ++ rigid, p, &World.Vec.add/2) |> World.Vec.sub({0.0, 0.0, ground})
    end
  end

  defp mesh(figure), do: List.last(figure.nodes)

  test "the kit joined for the numbers of a person is the person of World, within 1 mm" do
    numbers = %{gender: 1.0, age: 70, muscle: 0.5, weight: 0.8, height: 0.9, race: %{"african" => 1.0}}
    kit = Human.kit(1, :body)
    node = mesh(kit)
    extras = Map.put(node.extras["kit"], "order", Enum.map(kit.skeleton.bones, & &1.name))

    person =
      Detail.with(:mid, fn ->
        Human.person("traveler",
          gender: 1.0,
          age: 70,
          weight: 0.8,
          height: 0.9,
          race: %{"african" => 1.0},
          eyebrows: "eyebrow001",
          hair: "short02",
          clothes: [],
          pose: "stand"
        )
      end)

    by = fn figure, material -> Enum.find(mesh(figure).primitives, &(&1.material == material)) end
    joined = join(by.(kit, :skin), extras, numbers, "none")
    errors = Enum.zip_with(joined, by.(person, :skin).positions, &World.Vec.len(World.Vec.sub(&1, &2)))
    assert Enum.max(errors) < 0.001

    # The hair on the same skeleton: the same targets, and the ground of
    # the body.
    hair = Human.kit(1, {:hair, "short02"})

    joined =
      join(
        hd(mesh(hair).primitives),
        Map.merge(extras, Map.take(mesh(hair).extras["kit"], ["targets"])),
        numbers,
        "none"
      )

    errors = Enum.zip_with(joined, by.(person, :hair).positions, &World.Vec.len(World.Vec.sub(&1, &2)))
    assert Enum.max(errors) < 0.003
  end

  test "the kit of a woman with the options of the shape is the person of World, within 1 mm" do
    shape = %{
      bust: 0.8,
      firmness: 0.7,
      waist: 0.3,
      hips: 0.7,
      buttocks: 0.6,
      stomach: 0.4,
      torso: 0.6,
      shoulders: 0.4,
      arms: 0.7,
      legs: 0.3,
      neck: 0.6
    }

    numbers = Map.merge(%{gender: 0.0, age: 40, muscle: 0.5, weight: 0.3, height: 0.5, race: %{"asian" => 1.0}}, shape)
    kit = Human.kit(0, :body)
    extras = Map.put(mesh(kit).extras["kit"], "order", Enum.map(kit.skeleton.bones, & &1.name))

    person =
      Detail.with(:mid, fn ->
        Human.person(
          "traveler",
          [gender: 0.0, age: 40, weight: 0.3, race: %{"asian" => 1.0}, hair: "short02", clothes: [], pose: "stand"] ++
            Map.to_list(shape)
        )
      end)

    skin = fn figure -> Enum.find(mesh(figure).primitives, &(&1.material == :skin)) end
    joined = join(skin.(kit), extras, numbers, "none")
    errors = Enum.zip_with(joined, skin.(person).positions, &World.Vec.len(World.Vec.sub(&1, &2)))
    assert Enum.max(errors) < 0.001
  end

  test "the data of a body: the ground under each pair of shoes, the faces of each item, and its color" do
    extras = mesh(Human.kit(0, :body)).extras["kit"]
    # With the 3 targets of the cups of the bra (World.Sewing).
    assert length(extras["targets"]) == 78
    assert map_size(extras["bones"]) == 53
    assert [g0, moves] = extras["ground"]["shoes01"]
    # The soles of the shoes are under the feet.
    assert g0 < hd(extras["ground"]["none"])
    assert length(moves) == 78
    assert [[_first, count, n] | _] = extras["covers"]["female_casualsuit01"]
    assert count >= 1 and n > 0
    assert [_, _, _] = extras["colors"]["shoes01"]
  end

  test "each item of the clothes of the community makes a person, with its color at mid" do
    for {name, %{"author" => _}} <- World.People.Data.assets()["clothes"] do
      person = Detail.with(:mid, fn -> Human.person("t", gender: 1.0, clothes: [name], pose: "stand") end)
      assert Enum.any?(mesh(person).primitives, &(&1.material == :"color_#{name}")), name
    end
  end

  test "the manifest: the files, and the place of a parked person next to each vehicle" do
    m = Kit.manifest()
    assert m["people"] == %{"woman" => "person/woman.glb", "man" => "person/man.glb"}
    assert m["hair"]["short02"]["man"] == "person/man-hair-short02.glb"
    assert m["skins"]["young_asian_male"] =~ ~r{^skins/young_asian_male\.}
    assert m["places"]["car"] == [-1.3, 0.0, -0.6]
    assert m["places"]["foot"] == [0.0, 0.0, 0.0]
    refute Map.has_key?(m["places"], "camper")
    assert map_size(m["vans"]) == length(World.Vehicles.Van.models())
    # The place of the default camper is the place of the camper of World.
    {x, y} = World.People.place("camper")
    assert m["vans"]["transit_148"] == Tuple.to_list(GLB.gl({x, y, 0.0}))
    # The clothes of the community name their author and license.
    assert m["credits"]["punkduck_winter_boots"] == %{"author" => "punkduck", "license" => "CC-BY"}
    assert m["credits"]["toigo_fisherman_sweater"]["license"] == "CC0"
    refute Map.has_key?(m["credits"], "shoes01")

    assert m["shapes"]["waist"] == %{
             "decr" => ["torso/measure-waist-circ-decr"],
             "incr" => ["torso/measure-waist-circ-incr"]
           }

    # The layer of each item, and the shape that the bra gives to the body.
    assert m["layers"]["world_bra"] == 0 and m["layers"]["world_ao_dai"] == 2 and m["layers"]["shoes01"] == 1
    assert ["breast/breast-trans-up", 1.0] in m["wear"]["world_bra"]
    assert Map.keys(m["wear"]) == ["world_bra"]

    assert m["credits"] |> Map.keys() |> Enum.all?(&(&1 in m["clothes"]))
    assert m["vehicles"]["car"] == "vehicles/car.glb"
    assert m["vehicles"]["camper"]["transit_148"] == "vehicles/camper-transit_148.glb"
    refute Map.has_key?(m["vehicles"], "foot")
    assert map_size(m["vehicles"]["camper"]) == length(World.Vehicles.Van.models())
  end

  test "a vehicle of the kit is the file of the order of its URL" do
    {"vehicles/car.glb", options} = Enum.find(Kit.vehicles(), &(elem(&1, 0) == "vehicles/car.glb"))

    {:ok, bin} =
      World.Orders.build(
        %{"blueprint" => "traveler", "options" => %{"vehicle" => "car", "scene" => "parked", "part" => "vehicle"}},
        "mid",
        "glb"
      )

    assert Kit.vehicle_glb(options) == bin
  end
end
