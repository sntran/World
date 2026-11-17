defmodule World.People.PartsTest do
  # The parts of a person from edits (plan 0017): hair as a mass, a nón lá, a helmet.
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Mesh, Vec}
  alias World.People.{Human, Parts}

  @moduletag timeout: 1_800_000

  defp box(item),
    do:
      Vec.bounds(
        for({_, part, _} <- item.nodes, m <- part.shapes, do: Mesh.bounds(m))
        |> Enum.flat_map(&Tuple.to_list/1)
      )

  test "the parts: their names, their port, and the scale of a part for a head" do
    assert Parts.names() == ~w(mu_bao_hiem_edits non_la_edits toc_bui_edits toc_dai_edits toc_ngan_edits)
    for name <- Parts.names(), do: assert(Parts.on(name) == "crown")
    # The head that the parts are drawn on, and a head that is 10% wider and 20% longer.
    assert Parts.scale("toc_ngan_edits", {0.164, 0.188}) == 1.0
    assert_in_delta Parts.scale("mu_bao_hiem_edits", {0.164 * 1.1, 0.188 * 1.2}), 1.15, 1.0e-9
    # A nón lá has one size.
    assert Parts.scale("non_la_edits", {0.2, 0.25}) == 1.0
    assert_raise ArgumentError, ~r/unknown part "hat"/, fn -> Parts.part("hat") end
  end

  test "a part is a sculpture with the port crown at the top of the head; it grows from its port, and its role takes a color" do
    Detail.with(:far, fn ->
      hat = Parts.part("non_la_edits")
      assert World.Assembly.item_port_frame(hat, "crown").at == {0.0, 0.0, 0.0}
      {{x0, _, z0}, {x1, _, z1}} = box(hat)
      # 41 cm across; its rim 11 cm under the top of the head, its top 8 cm over it (the strap goes lower).
      assert_in_delta x1 - x0, 0.41, 0.01
      assert_in_delta z1, 0.08, 0.01
      assert z0 < -0.11
      assert hat.materials[:part_09]["image"]

      hair = Parts.part("toc_bui_edits")
      large = Parts.part("toc_bui_edits", scale: 1.2, color: [38, 30, 26])
      {{a0, _, _}, {a1, _, top}} = box(hair)
      {{b0, _, _}, {b1, _, high}} = box(large)
      assert_in_delta b1 - b0, 1.2 * (a1 - a0), 1.0e-6
      assert_in_delta high, 1.2 * top, 1.0e-6
      assert large.materials[:part_11]["color"] == [38, 30, 26]
      assert hair.materials[:part_11]["color"] != [38, 30, 26]
      assert large.materials[:part_11]["image"] == hair.materials[:part_11]["image"]
    end)
  end

  test "a person wears parts on its head: each has the size of the head, and its image is in the model" do
    Detail.with(:far, fn ->
      wear = ["mu_bao_hiem_edits", {"toc_ngan_edits", [color: [38, 30, 26]]}]
      man = Human.person("p", age: 35, hair: nil, pose: "stand", wear: wear)
      assert [{"crown", helmet, "crown"}, {"crown", hair, "crown"}] = man.props
      # The head of the man is larger than the head that the parts are drawn on.
      {{x0, _, _}, {x1, _, _}} = box(helmet)
      {{y0, _, _}, {y1, _, _}} = box(Parts.part("mu_bao_hiem_edits"))
      assert (x1 - x0) / (y1 - y0) > 1.05 and (x1 - x0) / (y1 - y0) < 1.25
      assert hair.materials[:part_11]["color"] == [38, 30, 26]
      # The head of a game is larger: its parts too, by the scale of the node of the head (a part is in that node,
      # so its own points do not grow again).
      big = Human.person("p", age: 35, hair: nil, pose: "stand", head: 1.3, wear: ["mu_bao_hiem_edits"])
      [{_, large, _}] = big.props
      assert box(large) == box(helmet)
      assert Enum.find(Build.scene(big, level: :far).nodes, &(&1.name == "head")).scale == 1.3

      # A part of one size (a nón lá) on a child is the nón lá of a child: smaller, so that it sits on its head as the
      # nón lá of an adult sits on the head of an adult (the node of the head of a child has its own scale).
      [{_, adult_hat, _}] = Human.person("p", age: 35, hair: nil, wear: ["non_la_edits"]).props
      [{_, child_hat, _}] = Human.person("p", age: 6, hair: nil, wear: ["non_la_edits"]).props
      {{a0, _, _}, {a1, _, _}} = box(adult_hat)
      {{c0, _, _}, {c1, _, _}} = box(child_hat)
      assert_in_delta (c1 - c0) / (a1 - a0) * Human.child_head(6, 1.0), 0.86, 0.01
      # The same for a hat that a person holds on its crown (the hat of the blueprint person).
      [{"crown", held, "crown"}] =
        Human.person("p", age: 6, hair: nil, hold: [{"crown", World.People.Props.prop("non_la")}]).props

      part_box = fn part -> Vec.bounds(Enum.flat_map(part.shapes, &Tuple.to_list(Mesh.bounds(&1)))) end
      {{h0, _, _}, {h1, _, _}} = part_box.(held)
      {{n0, _, _}, {n1, _, _}} = part_box.(World.People.Props.prop("non_la"))
      assert_in_delta (h1 - h0) / (n1 - n0) * Human.child_head(6, 1.0), 0.86, 0.01
      # A hat of parts gets the same size: each of its parts.
      cone = World.Assembly.new("hat", World.People.Props.prop("non_la"), root: "cone")

      [{"crown", %World.Assembly{nodes: [{"cone", in_parts, nil}]}, "crown"}] =
        Human.person("p", age: 6, hair: nil, hold: [{"crown", cone}]).props

      assert part_box.(in_parts) == part_box.(held)

      # The model has the image of each part, and the part is on the bone of the head.
      scene = Build.scene(man, level: :far)
      assert scene.materials[:part_10] || scene.materials["part_10"]
      assert scene.materials[:part_11] || scene.materials[:part_11]
      # With no part, a person has no prop.
      assert Human.person("p", pose: "stand").props == []
    end)
  end

  # A tool that Vũng Tàu asked for (the half helmet on a rider who stands): an order of the blueprint
  # person puts parts from edits on the head (the option wear), as World.People.Human.person/2 does.
  test "an order of a person wears parts from edits: the option wear of the blueprint person" do
    order = %{"blueprint" => "person", "options" => %{"wear" => ["mu_bao_hiem_edits"]}}
    assert {:ok, full} = World.Orders.check(order)
    assert full["options"]["wear"] == ["mu_bao_hiem_edits"]
    {:ok, blueprint} = World.Orders.Blueprints.fetch("person")
    person = Detail.with(:far, fn -> blueprint.build.(full["options"]) end)
    assert [{"crown", %World.Assembly{}, "crown"}] = person.props
    assert {:ok, %{"options" => %{"wear" => []}}} = World.Orders.check(%{"blueprint" => "person"})

    assert {:error, [%{"path" => "options.wear.0"}]} =
             World.Orders.check(put_in(order, ["options", "wear"], ["nope"]))
  end

  test "the two people of the catalog with parts from edits" do
    Detail.with(:far, fn ->
      woman = World.People.woman_non_la()
      assert Enum.map(woman.props, &elem(&1, 0)) == ["crown", "crown"]
      man = World.People.man_helmet()
      assert length(man.props) == 2
      {{_, _, z0}, {_, _, z1}} = man |> Build.scene(level: :far) |> World.Scene.bounds()
      # The shell of the helmet is over the top of the head.
      assert z0 > -0.05 and z1 > 1.7 and z1 < 1.8
    end)
  end
end
