defmodule World.ClothesTest do
  use ExUnit.Case, async: true

  alias World.Detail
  alias World.Clothes
  alias World.People.{Data, Human}

  doctest Clothes

  test "the files of the clothes in priv are the same as the module makes them (scripts/clothes.exs)" do
    dir = Path.join(:code.priv_dir(:world), "makehuman/clothes")

    for {name, bin} <- Clothes.files() do
      assert File.read!(Path.join(dir, name)) == bin, "run mix run scripts/clothes.exs: #{name}"
    end
  end

  test "a jacket is an item of the clothes: it fits the body, it hides the points inside it, and not the head" do
    for name <- Clothes.names() do
      a = Data.asset("clothes", name)
      assert get_in(Data.assets(), ["clothes", name, "license"]) == "AGPL-3.0"
      assert tuple_size(a.fit.refs) == tuple_size(a.mesh.points)
      assert MapSet.size(a.fit.delete) > 1000
      # Each point refers to one point of the body, with an offset out of it.
      for {[v, v, v], [1.0, +0.0, +0.0], d} <- Tuple.to_list(a.fit.refs) do
        assert v < 13380
        assert World.Vec.len(d) > 0.1
      end

      head = Data.weights()["head"] |> Enum.filter(fn [_, w] -> w > 0.9 end) |> MapSet.new(fn [p, _] -> p end)
      assert MapSet.disjoint?(a.fit.delete, head)
    end
  end

  test "a down jacket is thicker than a softshell, with baffles" do
    thick = fn name ->
      Data.asset("clothes", name).fit.refs |> Tuple.to_list() |> Enum.map(fn {_, _, d} -> World.Vec.len(d) end)
    end

    down = thick.("world_down_jacket")
    soft = thick.("world_softshell")
    assert Enum.min(down) > Enum.max(soft) - 0.12
    # The baffles: the thickness of the down jacket changes, of the softshell only at the hem.
    assert Enum.max(down) - Enum.min(down) > 0.1
  end

  test "a person in a jacket over a shirt has the color of the jacket at mid, and the jacket at near" do
    for name <- Clothes.names() do
      clothes = [name, "elvs_crude_t-shirt_male", "cortu_cargo_pants"]
      colors = [[200, 40, 30], [240, 240, 240], [50, 50, 50]]

      mid = Detail.with(:mid, fn -> Human.person("t", gender: 1.0, clothes: clothes, clothes_colors: colors) end)
      prims = List.last(mid.nodes).primitives
      jacket = Enum.find(prims, &(&1.material == :"color_#{name}"))
      shirt = Enum.find(prims, &(&1.material == :"color_elvs_crude_t-shirt_male"))
      # The jacket comes first: it has the torso and the arms.
      assert length(jacket.indices) > 3 * length((shirt && shirt.indices) || [])

      near = Detail.with(:near, fn -> Human.person("t", gender: 1.0, clothes: clothes, clothes_colors: colors) end)
      assert Enum.any?(List.last(near.nodes).primitives, &(&1.material == :"clothes_#{name}"))
    end
  end
end
