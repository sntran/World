defmodule World.StatuesTest do
  use ExUnit.Case, async: true

  alias World.{Build, Check, Detail, Mass, Mesh, Orders, Scene, Statues}

  defp at(level, fun), do: Detail.with(level, fun)
  defp scene(item, level), do: Build.scene(item, level: level)
  defp roles(s), do: for(n <- s.nodes, p <- n.primitives, uniq: true, do: p.material)
  defp part(item, name), do: item.nodes |> List.keyfind(name, 0) |> elem(1)

  @no_base [plaza_radius: 0.0, base_height: 0.0, dome_height: 0.0]

  @tag timeout: 300_000
  test "the statue on Núi Nhỏ: 32 m from the feet to the halo, the hands 18.4 m apart, hollow at near, the checks" do
    near = at(:near, &Statues.nui_nho/0)
    assert near.kind == :statue and Check.model(near) == :ok
    s = scene(near, :near)
    {{_, _, z0}, _} = Scene.bounds(s)

    {{x0, _, _}, {x1, _, _}} =
      part(near, "tuong_chua_kito_vua").shapes |> Enum.flat_map(& &1.points) |> World.Vec.bounds()

    assert_in_delta x1 - x0, 18.4, 0.05
    assert_in_delta z0, 0.0, 1.0e-6
    # The base: the plaza of 21 m with 3 steps of 15 cm, the block of
    # 6.5 m, the dome of 3 m under the feet; the relief of gold, the
    # windows with grilles, the balustrade of the terrace.
    {{px0, _, _}, {px1, _, pz1}} = Mesh.bounds(hd(part(near, "be").shapes))
    assert_in_delta px1 - px0, 21.0, 0.01
    assert_in_delta pz1, 0.45, 1.0e-6
    {{_, _, feet}, _} = Mesh.bounds(hd(part(near, "tuong_chua_kito_vua").shapes))
    assert feet > 9.95 - 0.5 and feet < 9.95 + 0.5
    assert Scene.triangles(s) < 400_000
    assert ~w(stone_wash steel gold dark)a -- roles(s) == []
    assert part(near, "lan_can").shapes |> length() > 50

    # The stair of 133 steps to the floor of the shoulders, inside.
    stair = part(near, "cau_thang")
    # 133 treads, the rail and 45 posts.
    assert length(stair.shapes) == 179 and stair.params["steps"] == 133
    assert stair.params["rise"] > 0.15 and stair.params["rise"] < 0.19

    # The extras: each size with its source, or an estimate.
    sizes = Map.new(near.extras["sizes"], &{&1["name"], &1})
    assert sizes["height"]["value"] == 32.0 and sizes["height"]["source"] =~ "32 m"
    assert sizes["span"]["source"] =~ "18.4"
    assert sizes["wall"]["source"] == "estimate (no source)"
    assert sizes["windows"]["value"] |> length() == 3
    assert sizes["material"]["value"] == "concrete"
    assert ~w(door light stair view) -- Enum.map(near.extras["ports"], & &1["kind"]) == []
    assert length(near.extras["collision"]) == 6
    assert sizes["base_height"]["source"] =~ "measured from photos (Vung_Tau landmarks.md)"
    assert sizes["dome_sides"]["value"] == 8
    assert sizes["head"]["value"] == 4.0 and sizes["head"]["source"] =~ "photo 3"
    assert sizes["mantle"]["value"] == 21.5 and sizes["mantle"]["source"] =~ "photos 1, 3, 4"
    assert sizes["heart"]["value"] == 24.5

    # The Sacred Heart: a cast of its own on the chest, 0.7 m by 1.6 m.
    assert [{{cx0, _, cz0}, {cx1, _, cz1}}] =
             for(
               sh <- part(near, "tuong_chua_kito_vua").shapes,
               {{x0, _, z0}, {x1, _, z1}} = b = World.Vec.bounds(sh.points),
               x1 - x0 < 1.0 and z0 > 33.0 and z1 < 36.5,
               do: b
             )

    assert_in_delta cx1 - cx0, 0.72, 0.1
    assert_in_delta cz1 - cz0, 1.6, 0.1

    # The head: a cast of its own on the fine grid, from its top down past
    # the end of the beard (4 m) to the neck.
    [{{hx0, _, hz0}, {hx1, _, hz1}}] =
      for sh <- part(near, "tuong_chua_kito_vua").shapes,
          {{x0, _, z0}, {x1, _, z1}} = b = World.Vec.bounds(sh.points),
          x1 - x0 < 3.5 and z1 > 40.0 and z0 < 37.0,
          do: b

    assert hx1 - hx0 > 2.0 and hz1 < 41.5 and hz1 - hz0 > 4.0

    # Hollow at near only: the mid level weighs more.
    mid = at(:mid, &Statues.nui_nho/0)
    assert Mass.of(mid).mass > Mass.of(near).mass
    refute List.keyfind(mid.nodes, "cau_thang", 0)
    assert Scene.triangles(scene(mid, :mid)) < Scene.triangles(s)

    # The far form: at most 300 triangles (R9 of plan 0008), the same size.
    far = at(:far, &Statues.nui_nho/0)
    fs = scene(far, :far)
    assert Scene.triangles(fs) <= 300
    {_, {_, _, fz1}} = Scene.bounds(fs)

    {{fx0, _, _}, {fx1, _, _}} =
      part(far, "tuong_chua_kito_vua").shapes |> Enum.flat_map(& &1.points) |> World.Vec.bounds()

    assert_in_delta fx1 - fx0, 18.4, 0.01
    assert fz1 > 41.0 and fz1 < 42.5
    refute List.keyfind(far.nodes, "lan_can", 0)
  end

  test "a statue of other options: a pose of a person, no robe, no halo, of stone, with no base" do
    o = [height: 3.0, pose: "stand", robe: false, halo: false, material: :stone] ++ @no_base
    item = at(:mid, fn -> Statues.statue(o) end)
    assert Check.model(item) == :ok
    s = scene(item, :mid)
    {{_, _, z0}, {_, _, z1}} = Scene.bounds(s)
    assert_in_delta z1 - z0, 3.0, 0.1
    assert roles(s) -- [:collision] == [:stone]
    assert [_] = item.nodes
    assert length(item.extras["collision"]) == 3

    far = at(:far, fn -> Statues.statue(o ++ [halo: true, rays: 4, terrace_rail: 0.0, base_height: 1.0]) end)
    assert Scene.triangles(scene(far, :far)) <= 300

    # A robe with no hair and the head of the person, at mid.
    bald = at(:mid, fn -> Statues.statue([height: 3.0, hair: nil] ++ @no_base) end)
    assert Check.model(bald) == :ok

    # The rays: an even count has no ray up.
    near = at(:mid, fn -> Statues.statue([height: 3.0, rays: 4] ++ @no_base) end)
    assert Enum.count(part(near, "tuong").shapes, &(&1.material == :steel)) == 4

    # The defaults: a statue of 32 m with its arms out, on a base.
    assert Scene.triangles(scene(at(:far, fn -> Statues.statue() end), :far)) <= 300

    # A small base: no curve in its front, no room for a panel; and a base
    # with a panel of no letters and no windows.
    small =
      [height: 3.0, base_width: 4.0, base_depth: 4.0, base_height: 2.0, plaza_radius: 3.0, plaza_steps: 1] ++
        [dome_width: 2.0, dome_height: 0.5, reliefs: [%{"side" => "left", "figures" => 2}]]

    assert Check.model(at(:mid, fn -> Statues.statue(small) end)) == :ok
    plain = [height: 10.0, letters: false, grilles: 0, reliefs: [%{"side" => "back", "figures" => 3}]]
    item = at(:mid, fn -> Statues.statue(plain) end)
    assert Check.model(item) == :ok
    refute :dark in roles(scene(item, :mid))

    assert_raise ArgumentError, ~r/span/, fn -> at(:far, fn -> Statues.statue(span: 1.0, hand: 0.5) end) end
  end

  test "the blueprint statue: an order, its receipt with the sizes and their sources, the errors" do
    order = %{
      "blueprint" => "statue",
      "options" => %{
        "height" => 10.0,
        "span" => 6.0,
        "hand" => 0.7,
        "hollow" => true,
        "windows" => [%{"z" => 6.0}],
        "reliefs" => [%{"side" => "front", "figures" => 4, "title" => "A"}],
        "hair" => "none",
        "head" => 2.0,
        "beard" => true,
        "sources" => %{"height" => "A drawing of 2026."}
      }
    }

    assert {:ok, full} = Orders.check(order)
    assert full["options"]["material"] == "concrete" and full["options"]["steps"] == 133
    assert {:ok, _} = Orders.build(order, "mid", "glb")
    assert {:ok, receipt} = Orders.build(order, "far", "receipt")
    sizes = JSON.decode!(receipt)["sizes"]

    assert Enum.find(sizes, &(&1["name"] == "height")) == %{
             "name" => "height",
             "value" => 10.0,
             "unit" => "m",
             "source" => "A drawing of 2026."
           }

    assert Enum.find(sizes, &(&1["name"] == "span"))["source"] == "estimate (no source)"
    {:ok, house} = Orders.build(%{"blueprint" => "strut", "options" => %{"length" => 0.3}}, "far", "receipt")
    refute Map.has_key?(JSON.decode!(house), "sizes")

    for {options, path} <- [
          {%{"sources" => %{"colour" => "x"}}, "options.sources.colour"},
          {%{"sources" => %{"height" => 3}}, "options.sources.height"},
          {%{"sources" => "x"}, "options.sources"},
          {%{"reliefs" => [%{"side" => "front", "title" => 5}]}, "options.reliefs.0.title"},
          {%{"height" => 0.5}, "options.height"}
        ] do
      assert {:error, [%{"path" => ^path} | _]} = Orders.check(%{"blueprint" => "statue", "options" => options})
    end
  end
end
