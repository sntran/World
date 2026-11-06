defmodule World.StatuesTest do
  use ExUnit.Case, async: true

  alias World.{Build, Check, Detail, Mass, Mesh, Orders, Scene, Statues}

  defp at(level, fun), do: Detail.with(level, fun)
  defp scene(item, level), do: Build.scene(item, level: level)
  defp roles(s), do: for(n <- s.nodes, p <- n.primitives, uniq: true, do: p.material)
  defp part(item, name), do: item.nodes |> List.keyfind(name, 0) |> elem(1)

  @tag timeout: 300_000
  test "the statue on Núi Nhỏ: 32 m from the feet to the halo, the hands 18.4 m apart, hollow at near, the checks" do
    near = at(:near, &Statues.nui_nho/0)
    assert near.kind == :statue and Check.model(near) == :ok
    s = scene(near, :near)
    {{x0, _, z0}, {x1, _, _}} = Scene.bounds(s)
    assert_in_delta x1 - x0, 18.4, 0.05
    assert_in_delta z0, 0.0, 1.0e-6
    # The base of 4 m and the plinth of 1.2 m under the feet.
    assert_in_delta elem(elem(Mesh.bounds(hd(part(near, "be").shapes)), 1), 2), 0.6, 1.0e-6
    assert Scene.triangles(s) < 50_000
    assert :stone_wash in roles(s) and :steel in roles(s)

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
    assert length(near.extras["collision"]) == 5

    # Hollow at near only: the mid level weighs more.
    mid = at(:mid, &Statues.nui_nho/0)
    assert Mass.of(mid).mass > Mass.of(near).mass
    refute List.keyfind(mid.nodes, "cau_thang", 0)
    assert Scene.triangles(scene(mid, :mid)) < Scene.triangles(s)

    # The far form: at most 300 triangles (R9 of plan 0008), the same size.
    far = at(:far, &Statues.nui_nho/0)
    fs = scene(far, :far)
    assert Scene.triangles(fs) <= 300
    {{fx0, _, _}, {fx1, _, fz1}} = Scene.bounds(fs)
    assert_in_delta fx1 - fx0, 18.4, 0.01
    assert fz1 > 36.0 and fz1 < 37.3
    refute List.keyfind(far.nodes, "lan_can", 0)
  end

  test "a statue of other options: a pose of a person, no robe, no halo, of stone, with no base" do
    o = [height: 3.0, pose: "stand", robe: false, halo: false, material: :stone, base_height: 0.0, plinth_height: 0.0]
    item = at(:mid, fn -> Statues.statue(o) end)
    assert Check.model(item) == :ok
    s = scene(item, :mid)
    {{_, _, z0}, {_, _, z1}} = Scene.bounds(s)
    assert_in_delta z1 - z0, 3.0, 0.1
    assert roles(s) -- [:collision] == [:stone]
    assert [_] = item.nodes
    assert length(item.extras["collision"]) == 3

    far = at(:far, fn -> Statues.statue(o ++ [halo: true, rays: 4, rail: 0.0, base_height: 1.0]) end)
    assert Scene.triangles(scene(far, :far)) <= 300

    # The rays: an even count has no ray up.
    near = at(:mid, fn -> Statues.statue(height: 3.0, rays: 4, base_height: 0.0, plinth_height: 0.0) end)
    assert Enum.count(part(near, "tuong").shapes, &(&1.material == :steel)) == 4

    # The defaults: a statue of 32 m with its arms out, on a base.
    assert Scene.triangles(scene(at(:far, fn -> Statues.statue() end), :far)) <= 300

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
        "sources" => %{"height" => "A drawing of 2026."}
      }
    }

    assert {:ok, full} = Orders.check(order)
    assert full["options"]["material"] == "concrete" and full["options"]["steps"] == 133
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
