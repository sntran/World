defmodule World.SewingTest do
  use ExUnit.Case, async: true

  alias World.Detail
  alias World.Sewing
  alias World.Vec
  alias World.People.{Data, Human}

  doctest Sewing

  @jackets ~w(world_rain_shell world_softshell world_down_jacket)

  test "the files of the garments in priv are the same as the module makes them (scripts/clothes.exs)" do
    dir = Path.join(:code.priv_dir(:world), "makehuman/clothes")

    for {name, bin} <- Sewing.files() do
      assert File.read!(Path.join(dir, name)) == bin, "run mix run scripts/clothes.exs: #{name}"
    end
  end

  test "a garment is an item of the clothes: it fits the body, it hides the points inside it, and not the head" do
    head = Data.weights()["head"] |> Enum.filter(fn [_, w] -> w > 0.9 end) |> MapSet.new(fn [p, _] -> p end)

    for name <- Sewing.names() do
      a = Data.asset("clothes", name)
      entry = get_in(Data.assets(), ["clothes", name])
      assert entry["license"] == "AGPL-3.0"
      assert entry["layer"] in 0..3
      assert Map.has_key?(Sewing.fabrics(), entry["fabric"])
      assert tuple_size(a.fit.refs) == tuple_size(a.mesh.points)
      assert MapSet.size(a.fit.delete) > 100
      assert MapSet.disjoint?(a.fit.delete, head)

      # Each point refers to one point of the body (or of the skirt of the
      # base mesh), with an offset out of it: the base of the layer and
      # the thickness of the fabric at least.
      least = Sewing.layers()[a.layer] + Sewing.fabrics()[entry["fabric"]].thick

      for {[v, v, v], [1.0, +0.0, +0.0], d} <- Tuple.to_list(a.fit.refs) do
        assert v < 19158
        assert Vec.len(d) >= least - 1.0e-4
      end
    end
  end

  test "the pieces of a garment join at their seams" do
    assert [{"band", "cups", _}, {"band", "straps", _}, {"cups", "straps", _}] = Sewing.seams("world_bra")
    # The panels of the áo dài are on the skirt: no seam with the bodice.
    assert [{"bodice", "collar", _}, {"bodice", "sleeves", _}] = Sewing.seams("world_ao_dai")
    assert [{"body", "sleeves", n}] = Sewing.seams("world_t_shirt")
    assert n > 20
    assert_raise ArgumentError, "no garment nope", fn -> Sewing.seams("nope") end
  end

  test "a bra gives its shape to the body; the cloth of a garment of a fabric with a span drapes" do
    bra = Data.asset("clothes", "world_bra")
    assert {"breast/breast-trans-up", 1.0} in bra.shape
    assert bra.drape == nil
    assert %{points: [_ | _], steps: 24} = Data.asset("clothes", "world_ao_dai").drape

    # The cups lift the bust: the top of a T-shirt over the bra is higher.
    top = fn clothes ->
      {_, _, pts} = Human.dressed(gender: 0.0, clothes: clothes) |> List.last()

      pts
      |> Enum.filter(fn {v, _, _} -> v in Data.breast_points() end)
      |> Enum.map(fn {_, {_, y, _}, _} -> y end)
      |> Enum.sum()
    end

    assert top.(~w(world_bra world_t_shirt)) > top.(~w(world_t_shirt))
  end

  test "no skin shows between two layers or through a layer" do
    looks = [
      ~w(world_bra world_quan world_ao_dai),
      ~w(world_bra world_pants world_t_shirt),
      ~w(world_pants world_t_shirt world_down_jacket)
    ]

    for clothes <- looks, bust <- [0.5, 1.0] do
      items = Human.dressed(gender: 0.0, bust: bust, clothes: clothes)

      # Each point of the body under two items: the outer layer is out of
      # the body more than the inner one.
      outs =
        for {name, layer, pts} <- items, do: {name, layer, Map.new(for {v, _, out} <- pts, v < 13380, do: {v, out})}

      for {a, la, inner} <- outs, {b, lb, outer} <- outs, la < lb, {v, d} <- inner, Map.has_key?(outer, v) do
        assert outer[v] > d, "#{b} goes into #{a} at the point #{v} (bust #{bust})"
      end

      # The top and the pants overlap: the hem of the top is under the
      # top of the pants (on the body: the panels of the áo dài are not).
      ys = fn name ->
        {_, _, pts} = Enum.find(items, &(elem(&1, 0) == name))
        for {v, {_, y, _}, _} <- pts, v < 13380, do: y
      end

      [_, pants, top | _] = clothes
      assert Enum.max(ys.(pants)) > Enum.min(ys.(top)) + 0.3
    end
  end

  test "the shape of the bust shows under a top, with no point" do
    nipples = Data.target("breast/nipple-point-decr") |> MapSet.new(&elem(&1, 0))

    for {name, clothes} <- [{"world_t_shirt", ~w(world_t_shirt)}, {"world_ao_dai", ~w(world_bra world_ao_dai)}],
        bust <- [0.5, 0.75, 1.0] do
      a = Data.asset("clothes", name)
      {_, _, pts} = Human.dressed(gender: 0.0, bust: bust, clothes: clothes) |> Enum.find(&(elem(&1, 0) == name))
      pos = pts |> Enum.map(&elem(&1, 1)) |> List.to_tuple()
      faces = a.mesh.groups |> Map.values() |> Enum.concat()

      {ring, normals} =
        Enum.reduce(faces, {%{}, %{}}, fn f, {ring, normals} ->
          vs = Enum.map(f, &elem(&1, 0))
          [p0, p1, p2, p3] = Enum.map(vs, &elem(pos, &1))
          n = Vec.cross(Vec.sub(p2, p0), Vec.sub(p3, p1))

          Enum.reduce(vs, {ring, normals}, fn v, {r, ns} ->
            {Map.update(r, v, vs -- [v], &Enum.uniq(&1 ++ (vs -- [v]))), Map.update(ns, v, n, &Vec.add(&1, n))}
          end)
        end)

      # The bend of the cloth at a point: its distance out of the mean of
      # its neighbors, along its normal. At a point (a nipple) the cloth
      # bends more than around it.
      bend = fn i ->
        Vec.dot(Vec.sub(elem(pos, i), ring[i] |> Enum.map(&elem(pos, &1)) |> Vec.mean()), Vec.norm(normals[i]))
      end

      left =
        for {{v, {x, _, _}, _}, i} <- Enum.with_index(pts), MapSet.member?(nipples, v), x > 0, do: i

      around = left |> Enum.flat_map(&ring[&1]) |> Enum.flat_map(&ring[&1]) |> Enum.uniq() |> Kernel.--(left)
      top = left |> Enum.map(bend) |> Enum.max()
      mean = Enum.sum(Enum.map(around, bend)) / length(around)
      assert top < 1.25 * mean, "#{name}, bust #{bust}: a point (#{top} over #{mean})"
    end
  end

  test "of two items that cover a face at mid, the outer layer gives its color" do
    clothes = ["world_bra", "world_t_shirt", "world_pants"]
    colors = [[250, 250, 250], [200, 40, 30], [50, 50, 50]]
    mid = Detail.with(:mid, fn -> Human.person("t", gender: 0.0, clothes: clothes, clothes_colors: colors) end)
    materials = mid.nodes |> List.last() |> Map.fetch!(:primitives) |> Enum.map(& &1.material)
    assert :color_world_t_shirt in materials
    refute :color_world_bra in materials
  end

  test "a person in a jacket over a shirt has the color of the jacket at mid, and the jacket at near" do
    for name <- @jackets do
      clothes = [name, "elvs_crude_t-shirt_male", "cortu_cargo_pants"]
      colors = [[200, 40, 30], [240, 240, 240], [50, 50, 50]]

      mid = Detail.with(:mid, fn -> Human.person("t", gender: 1.0, clothes: clothes, clothes_colors: colors) end)
      prims = List.last(mid.nodes).primitives
      jacket = Enum.find(prims, &(&1.material == :"color_#{name}"))
      shirt = Enum.find(prims, &(&1.material == :"color_elvs_crude_t-shirt_male"))
      # The jacket is on the outer layer: it has the torso and the arms.
      assert length(jacket.indices) > 3 * length((shirt && shirt.indices) || [])

      near = Detail.with(:near, fn -> Human.person("t", gender: 1.0, clothes: clothes, clothes_colors: colors) end)
      assert Enum.any?(List.last(near.nodes).primitives, &(&1.material == :"clothes_#{name}"))
    end
  end

  test "a down jacket is thicker than a softshell, with baffles" do
    thick = fn name ->
      Data.asset("clothes", name).fit.refs |> Tuple.to_list() |> Enum.map(fn {_, _, d} -> Vec.len(d) end)
    end

    down = thick.("world_down_jacket")
    soft = thick.("world_softshell")
    assert Enum.min(down) > Enum.max(soft) - 0.12
    # The baffles: the thickness of the down jacket changes, of the softshell only at the hem.
    assert Enum.max(down) - Enum.min(down) > 0.1
  end
end
