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

  test "the bust of a woman at mid is round: its faces are cut in sixteen; at far they stay" do
    triangles = fn level ->
      fig =
        Detail.with(level, fn -> Human.person("t", gender: 0.0, bust: 0.75, hair: nil, clothes: ["world_t_shirt"]) end)

      fig.nodes
      |> List.last()
      |> Map.fetch!(:primitives)
      |> Enum.filter(&(&1.material == :skin or String.starts_with?(Atom.to_string(&1.material), "color_")))
      |> Enum.map(&div(length(&1.indices), 3))
      |> Enum.sum()
    end

    # The low-poly bodies of MakeHuman: 1,584 and 730 quads (two triangles
    # each). At mid, 22 quads on the breasts become 352. (The person has no
    # hair: the hair at far has faces of its own in the color of the hair.)
    assert triangles.(:mid) >= 2 * (1584 - 22 + 352)
    assert triangles.(:far) == 2 * 730
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

  test "the clothes of a village of old Việt Nam: a tunic that hangs from the waist, wide pants, short pants" do
    names = ~w(world_ao_canh world_ao_coc world_quan_ong_rong world_quan_dui)
    assert names -- Sewing.names() == []
    garments = Map.new(Sewing.garments(), &{&1.name, &1})
    for n <- names, do: assert(garments[n].fabric == "homespun" and garments[n].shape == [])
    assert Sewing.fabrics()["homespun"].span == 90

    # The top of a tunic is on the body, its lower part is a tube on the skirt of the base mesh, and they join.
    for n <- ~w(world_ao_canh world_ao_coc) do
      assert Enum.map(garments[n].pieces, &{&1.name, &1.on}) == [
               {"body", "body"},
               {"skirt", "helper-skirt"},
               {"sleeves", "body"}
             ]

      assert [{"body", "sleeves"}] = for({a, b, _} <- Sewing.seams(n), do: {a, b})
    end

    high = fn opts, role ->
      fig = Detail.with(:near, fn -> Human.person("t", opts) end)
      prim = fig.nodes |> List.last() |> Map.fetch!(:primitives) |> Enum.find(&(&1.material == role))
      zs = Enum.map(prim.positions, &elem(&1, 2))
      {Enum.min(zs), Enum.max(zs)}
    end

    child = [gender: 1.0, age: 9, hair: nil]
    {_, top} = high.(child ++ [clothes: []], :skin)
    # The long sleeves go lower on the arm than the short ones; the tunic goes from under the hips to the neck.
    {low, neck} = high.(child ++ [clothes: ["world_ao_canh"]], :clothes_world_ao_canh)
    assert neck > 0.78 * top and neck < 0.86 * top and low > 0.4 * top and low < 0.5 * top
    {long, _} = high.(child ++ [clothes: ["world_quan_ong_rong"]], :clothes_world_quan_ong_rong)
    {short, _} = high.(child ++ [clothes: ["world_quan_dui"]], :clothes_world_quan_dui)
    assert long > 0.08 * top and long < 0.2 * top and short > 0.28 * top and short < 0.42 * top

    # A person in these clothes with bare feet is an order.
    order = %{
      "blueprint" => "person",
      "options" => %{
        "age" => 7,
        "clothes" => ["world_ao_coc", "world_quan_dui"],
        "clothes_colors" => ["#7a5237", "#3a2e2a"]
      }
    }

    assert {:ok, _} = World.Orders.place(order, "http://x")
  end

  test "a shirt has a round neck and covers the tops of the shoulders; the cloth over the nipples has no fold" do
    # The points of the shirt (the base mesh and its offsets, dm) and the joint of the neck.
    obj = Sewing.files() |> Map.new() |> Map.fetch!("world_t_shirt.obj.gz") |> :zlib.gunzip()
    points = for "v " <> rest <- String.split(obj, "\n"), do: rest |> String.split() |> Enum.map(&String.to_float/1)
    neck = Sewing.landmarks().neck
    base = Data.base()

    {_, _, nz} =
      base.groups
      |> Map.fetch!("joint-neck")
      |> Enum.concat()
      |> Enum.map(&elem(base.points, elem(&1, 0)))
      |> Vec.mean()

    # On the tops of the shoulders, near the neck: cloth up to the height of the neck.
    assert Enum.any?(points, fn [x, y, _] -> abs(x) > 0.75 and abs(x) < 1.0 and y > neck - 0.1 end)
    # No cloth round the neck over the cut: the neck is free (the cut is 0.72 dm from the axis, a little in front).
    refute Enum.any?(points, fn [x, y, z] -> y > neck - 0.4 and :math.sqrt(x * x + (z - nz) * (z - nz)) < 0.45 end)

    # The faces of the shirt on the chest of a man look to the front: no face of the cloth over a nipple is turned
    # over (the small faces of a nipple folded and made a star in the cloth).
    figure =
      Detail.with(:near, fn -> Human.person("p", gender: 1.0, age: 30, hair: nil, clothes: ["world_t_shirt"]) end)

    shirt =
      figure.nodes |> List.last() |> Map.fetch!(:primitives) |> Enum.find(&(&1.material == :clothes_world_t_shirt))

    at = List.to_tuple(shirt.positions)

    front =
      for [a, b, c] <- Enum.chunk_every(shirt.indices, 3),
          {pa, pb, pc} = {elem(at, a), elem(at, b), elem(at, c)},
          {x, y, z} = Vec.scale(Vec.add(Vec.add(pa, pb), pc), 1 / 3),
          abs(x) > 0.05 and abs(x) < 0.15 and z > 1.15 and z < 1.32 and y > 0.05,
          do: elem(Vec.norm(Vec.cross(Vec.sub(pb, pa), Vec.sub(pc, pa))), 1)

    assert length(front) > 50 and Enum.min(front) > 0.2
  end

  # The points of a person under a garment (`World.People.Human.dressed/1`): the body point at rest (the
  # base mesh, dm), its position in the cloth, and its distance out of the body.
  defp under(clothes, options \\ []) do
    base = Data.base().points
    [{_, _, pts} | _] = Human.dressed(gender: 1.0, clothes: clothes, clothes_options: options) |> Enum.reverse()
    for {v, q, out} <- pts, v < 13380, do: {elem(base, v), q, out}
  end

  defp mean(xs), do: Enum.sum(xs) / length(xs)

  test "swim trunks: a thin synthetic cloth, an elastic band with folds and a cord, loose legs to the middle of the thigh" do
    g = Enum.find(Sewing.garments(), &(&1.name == "world_swim_trunks"))
    fabric = Sewing.fabrics()[g.fabric]
    assert g.layer == 1 and g.fabric == "polyester" and fabric.span == 0
    assert fabric.thick < Sewing.fabrics()["cotton_jersey"].thick
    assert [{"band", "cord", _}, {"band", "legs", _}, {"cord", "legs", _}] = Sewing.seams("world_swim_trunks")

    l = Sewing.landmarks()
    pts = under(["world_swim_trunks"])
    ys = Enum.map(pts, fn {{_, y, _}, _, _} -> y end)
    # The hem at the middle of the thigh, and the top under the waist.
    assert_in_delta Enum.min(ys), l.hip + 0.5 * (l.knee - l.hip), 0.25
    assert Enum.max(ys) < l.waist and Enum.max(ys) > l.hip + 0.8

    # The legs are loose at the hem (2 cm and more out of the thigh), and close at the hips.
    out = fn keep -> mean(for {p, _, d} <- pts, keep.(p), do: d) end
    assert out.(fn {_, y, _} -> y < Enum.min(ys) + 0.2 end) > 0.2
    assert out.(fn {_, y, _} -> abs(y - l.hip) < 0.15 end) < 0.1

    # The band: its folds go in and out round the body.
    band = for {{_, y, _}, _, d} <- pts, y > l.waist - 0.7 and y < l.waist - 0.4, do: d
    assert Enum.max(band) - Enum.min(band) > 0.03

    # The cord at the middle of the front stands out of the cloth at the sides of the front.
    cord = fn x0, x1 ->
      out.(fn {x, y, z} -> abs(x) >= x0 and abs(x) <= x1 and z > 0 and y > l.waist - 1.3 and y < l.waist - 0.8 end)
    end

    assert cord.(0.0, 0.15) > cord.(0.4, 0.8) + 0.02
  end

  test "the options of a garment: a hem for each garment" do
    l = Sewing.landmarks()
    low = fn clothes, options -> under(clothes, options) |> Enum.map(fn {{_, y, _}, _, _} -> y end) |> Enum.min() end

    # The hem on the scale of the legs: 1 is the knee; the legs of the trunks and of the pants take it.
    assert_in_delta low.(["world_swim_trunks"], [%{hem: 0.9}]), l.hip + 0.9 * (l.knee - l.hip), 0.25
    assert_in_delta low.(["world_pants"], [%{hem: 1.0}]), l.knee, 0.25
    assert low.(["world_pants"], [%{hem: 1.5}]) < l.knee
    # A jacket to the waist: -1 is the waist.
    assert_in_delta low.(["world_softshell"], [%{hem: -0.5}]), l.hip + 0.5 * (l.waist - l.hip), 0.25
    # With no option the garment is the garment of the files.
    assert Sewing.garment("world_pants", %{}) == Enum.find(Sewing.garments(), &(&1.name == "world_pants"))
    assert Sewing.asset("world_pants", %{hem: nil}) == Data.asset("clothes", "world_pants")
    assert Sewing.asset("shoes01", %{print: "checks"}) == Data.asset("clothes", "shoes01")

    assert Sewing.check("world_swim_trunks", %{hem: -1.0}) == [{:hem, "is over the top of world_swim_trunks"}]

    assert_raise ArgumentError, "is over the top of world_swim_trunks", fn ->
      Sewing.garment("world_swim_trunks", %{hem: -1.0})
    end

    assert Sewing.check("shoes01", %{print: "checks"}) == []
  end

  test "a print: checks and stripes of two colors, on the body at rest" do
    p = %{kind: "checks", size: 0.05, colors: {:a, :b}}
    # The color changes at each step of the size (0.5 dm) along each axis, and the stripes only across.
    for {x, y, z} <- [{0.1, 0.2, 0.3}, {-1.3, 4.1, 0.7}, {2.2, -3.3, -0.9}],
        d <- [{0.5, 0.0, 0.0}, {0.0, 0.5, 0.0}, {0.0, 0.0, 0.5}] do
      q = Vec.add({x, y, z}, d)
      assert Sewing.print(p, {x, y, z}) != Sewing.print(p, q)
      stripes = %{p | kind: "stripes"}
      assert Sewing.print(stripes, {x, y, z}) == Sewing.print(stripes, q) == elem(d, 1) > 0
    end
  end
end
