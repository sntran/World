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
      # The head of a game is larger: its parts too.
      big = Human.person("p", age: 35, hair: nil, pose: "stand", head: 1.3, wear: ["mu_bao_hiem_edits"])
      [{_, large, _}] = big.props
      {{z0, _, _}, {z1, _, _}} = box(large)
      assert_in_delta (z1 - z0) / (x1 - x0), 1.3, 0.01

      # The model has the image of each part, and the part is on the bone of the head.
      scene = Build.scene(man, level: :far)
      assert scene.materials[:part_10] || scene.materials["part_10"]
      assert scene.materials[:part_11] || scene.materials[:part_11]
      # With no part, a person has no prop.
      assert Human.person("p", pose: "stand").props == []
    end)
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
