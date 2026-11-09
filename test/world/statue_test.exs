defmodule World.StatueTest do
  use ExUnit.Case, async: true

  alias World.{Build, Check, Detail, Drawing, Mass, Mesh, Orders, Scene}
  alias World.Orders.Blueprints

  defp scene(item, level), do: Build.scene(item, level: level)
  defp roles(s), do: for(n <- s.nodes, p <- n.primitives, uniq: true, do: p.material)
  defp part(item, name), do: item.nodes |> List.keyfind(name, 0) |> elem(1)
  defp nui_nho(level), do: Detail.with(level, fn -> Drawing.file("tuong_chua_kito_vua") end)

  # A statue of the blueprint in data, with the options of an order.
  defp statue(level, options) do
    {:ok, full} = Orders.check(%{"blueprint" => "statue", "options" => options})
    {:ok, b} = Blueprints.fetch("statue")
    Detail.with(level, fn -> b.build.(full["options"]) end)
  end

  @tag timeout: 300_000
  test "the statue on Núi Nhỏ as measured: 27.5 m from the feet to the halo, the hands 23.5 m apart, hollow at near, the checks" do
    near = nui_nho(:near)
    assert near.kind == :statue and Check.model(near) == :ok
    s = scene(near, :near)
    {{x0, _, z0}, {x1, _, _}} = Scene.bounds(s)
    assert_in_delta x1 - x0, 23.5, 0.2
    assert_in_delta z0, 0.0, 1.0e-6
    # The base of 4 m and the plinth of 3.7 m under the feet.
    assert_in_delta elem(elem(Mesh.bounds(hd(part(near, "be").shapes)), 1), 2), 0.6, 1.0e-6
    # The budget of a monument (plan 0004, D2).
    assert Scene.triangles(s) < 100_000
    assert :stone_wash in roles(s) and :steel in roles(s)

    # The stair of 133 steps from the floor of the room in the base (0.6 m
    # over the ground) up through the plinth to the floor of the
    # shoulders, inside.
    stair = part(near, "cau_thang")
    # 133 treads, the rail and 45 posts.
    assert length(stair.shapes) == 179 and stair.params["steps"] == 133
    assert stair.params["rise"] > 0.19 and stair.params["rise"] < 0.23
    {{_, _, first}, _} = stair.shapes |> hd() |> Mesh.bounds()
    assert_in_delta first, 0.6 + stair.params["rise"] - 0.08, 0.01
    ports = Map.new(near.extras["ports"], &{&1["kind"], &1})
    assert ports["stair"]["at"] == {0.0, 0.0, 0.6}
    assert ports["door"]["at"] == {0.0, -7.25, 0.0}

    # The extras: each size with its source, or an estimate.
    sizes = Map.new(near.extras["sizes"], &{&1["name"], &1})
    assert sizes["height"]["value"] == 27.5 and sizes["height"]["source"] =~ "32 m"
    assert sizes["span"]["source"] =~ "18.4"
    assert sizes["wall"]["source"] == "estimate (no source)"
    assert sizes["windows"]["value"] |> length() == 3
    assert sizes["material"]["value"] == "concrete"
    assert ~w(door light stair view) -- Enum.map(near.extras["ports"], & &1["kind"]) == []
    # The base: a box for each wall (the back in two, at the door) and the
    # roof; then the plinth, the robe, the arms and the head.
    assert length(near.extras["collision"]) == 10

    # Hollow at near only: the mid level weighs more.
    mid = nui_nho(:mid)
    assert Mass.of(mid).mass > Mass.of(near).mass
    refute List.keyfind(mid.nodes, "cau_thang", 0)
    assert Scene.triangles(scene(mid, :mid)) < Scene.triangles(s)

    # The far form: at most 300 triangles (R9 of plan 0008), the same size.
    far = nui_nho(:far)
    fs = scene(far, :far)
    assert Scene.triangles(fs) <= 300
    {{fx0, _, _}, {fx1, _, fz1}} = Scene.bounds(fs)
    assert_in_delta fx1 - fx0, 23.5, 0.01
    assert fz1 > 34.5 and fz1 < 35.5
    refute List.keyfind(far.nodes, "lan_can", 0)
  end

  # The measures of the front shot (plan 0005, R6): the height of a
  # feature over the hem, in m, at 18.4 m from cuff to cuff along the
  # line of the three windows (scripts/measure/sizes.py).
  defp measured do
    p = "priv/measures/tuong_chua_kito_vua/front/points.json" |> File.read!() |> JSON.decode!()
    at = fn names -> names |> String.split("+") |> Enum.map(&List.to_tuple(p[&1]["xyz"])) |> World.Vec.mean() end
    up = World.Vec.norm(World.Vec.sub(at.("window_1"), at.("window_3")))
    across = fn v -> World.Vec.sub(v, World.Vec.scale(up, World.Vec.dot(v, up))) end
    cuffs = World.Vec.sub(at.("cuff_l_top+cuff_l_bottom"), at.("cuff_r_top+cuff_r_bottom"))
    s = 18.4 / World.Vec.len(across.(cuffs))
    fn name -> World.Vec.dot(World.Vec.sub(at.(name), at.("hem")), up) * s end
  end

  @tag timeout: 300_000
  test "the built statue is within 0.5 m of each measure of the drone video, across and up (plan 0005, R6)" do
    h = measured()
    near = nui_nho(:near)
    feet = 4.0 + 3.7
    statue = part(near, "tuong_chua_kito_vua")
    points = fn keep -> for m <- statue.shapes, keep.(m), p <- m.points, do: p end
    stone = points.(&(&1.material != :steel))
    z = fn {_, _, z} -> z - feet end

    # The top of the halo: the highest point of stone.
    assert_in_delta stone |> Enum.map(z) |> Enum.max(), h.("halo_top"), 0.5
    # The three windows: the middles of the dark of their openings.
    windows =
      for m <- statue.shapes,
          m.material == :dark,
          do: m |> Mesh.bounds() |> then(fn {a, b} -> z.(World.Vec.mean([a, b])) end)

    for {w, name} <- Enum.zip(Enum.sort(windows), ~w(window_3 window_2 window_1)), do: assert_in_delta(w, h.(name), 0.5)
    # The cuffs: the band at the end of each sleeve.
    cuff = for {x, _, _} = p <- stone, abs(x) > 9.0 and abs(x) < 9.3, do: z.(p)
    assert_in_delta Enum.min(cuff), (h.("cuff_l_bottom") + h.("cuff_r_bottom")) / 2, 0.5
    assert_in_delta Enum.max(cuff), (h.("cuff_l_top") + h.("cuff_r_top")) / 2, 0.5
    # The foot of the plinth, and the two numbers of the sources: 32 m
    # from the foot of the plinth to the top of the halo (-2.5%).
    assert_in_delta -3.7, h.("plinth_foot"), 0.5
    assert_in_delta h.("halo_top") - h.("plinth_foot"), 32.0, 0.05 * 32.0
  end

  test "a statue of other options: a pose of a person, no robe, no halo, of stone, with no base" do
    o = %{
      "height" => 3.0,
      "pose" => "stand",
      "robe" => false,
      "halo" => false,
      "material" => "stone",
      "base_height" => 0.0,
      "plinth_height" => 0.0
    }

    item = statue(:mid, o)
    assert Check.model(item) == :ok
    s = scene(item, :mid)
    {{_, _, z0}, {_, _, z1}} = Scene.bounds(s)
    assert_in_delta z1 - z0, 3.0, 0.1
    assert roles(s) -- [:collision] == [:stone]
    # No base and no plinth: the statue is the root, and the only node.
    assert [{"tuong", _, nil}] = item.nodes
    assert length(item.extras["collision"]) == 3

    far = statue(:far, Map.merge(o, %{"halo" => true, "rays" => 4, "rail" => 0.0, "base_height" => 1.0}))
    assert Scene.triangles(scene(far, :far)) <= 300

    # The rays: an even count has no ray up.
    near = statue(:mid, %{"height" => 3.0, "rays" => 4, "base_height" => 0.0, "plinth_height" => 0.0})
    assert Enum.count(part(near, "tuong").shapes, &(&1.material == :steel)) == 4

    # A square base with a rail, and a plinth of facets with no room.
    square = %{
      "height" => 3.0,
      "base_height" => 1.2,
      "base_width" => 3.0,
      "base_depth" => 3.0,
      "corner" => 0.4,
      "rail" => 0.5,
      "plinth_height" => 0.4,
      "plinth_radius" => 0.8,
      "plinth_top" => 0.5,
      "plinth_sides" => 8
    }

    for level <- [:mid, :near] do
      item = statue(level, square)
      assert Check.model(item) == :ok
      assert part(item, "lan_can").shapes != []
    end

    # The defaults: a statue of 32 m with its arms out, on a base.
    assert Scene.triangles(scene(statue(:far, %{}), :far)) <= 300

    assert_raise ArgumentError, ~r/span/, fn -> statue(:far, %{"span" => 1.0, "hand" => 0.5}) end
  end

  @tag timeout: 300_000
  test "a statue of forms (plan 0005): the forms outside at near, the head, the hands and the halo where the data puts them" do
    o = %{
      "height" => 6.0,
      "span" => 5.0,
      "hand" => 0.5,
      "hollow" => true,
      "steps" => 20,
      "hair" => "none",
      "race" => %{"caucasian" => 1.0},
      "face" => %{"head-square" => 0.5},
      "forms" => [
        %{"rings" => [%{"oct" => [0.7, -0.6, 0.6, 0.2, 0.0]}, %{"oct" => [0.8, -0.6, 0.6, 0.2, 4.6]}]},
        %{
          "rings" => [%{"xrect" => [0.6, -0.3, 0.3, 4.0, 4.6]}, %{"xrect" => [1.9, -0.2, 0.2, 4.2, 4.6]}],
          "mirror" => true
        },
        %{"box" => [[-0.1, 0.55, 2.0], [0.1, 0.65, 2.3]], "detail" => true, "material" => "dark"}
      ],
      "head" => %{"top" => 5.5, "nose" => [0.5, 5.15], "narrow" => 0.9},
      "hands" => %{"length" => 0.5, "turn" => 210.0, "wrist" => [2.0, 4.4]},
      "ring" => %{"center" => [-0.4, 5.1], "radius" => 0.6, "tube" => 0.06, "lean" => 30.0, "rods" => 1},
      "rays" => 3,
      "plinth_height" => 0.6,
      "plinth_radius" => 1.0,
      "plinth_top" => 0.7,
      "plinth_sides" => 8,
      "base_height" => 3.0,
      "base_width" => 6.0,
      "base_depth" => 6.0,
      "base_plan" => "curved",
      "base_curve" => 0.6,
      "base_room" => true,
      "relief_metal" => true,
      "reliefs" => [%{"side" => "front", "figures" => 2}, %{"side" => "left", "figures" => 2}],
      "terrace" => 4.5
    }

    near = statue(:near, o)
    assert Check.model(near) == :ok
    shapes = part(near, "tuong").shapes
    # The dark of the window, the forms, and the inner walls of the cast.
    assert Enum.count(shapes, &(&1.material == :dark)) == 1
    # The hands to 2.5 m each side (the wrists at 2.0, 0.5 m long).
    {{x0, _, _}, {x1, _, _}} = shapes |> Enum.flat_map(& &1.points) |> World.Vec.bounds()
    assert_in_delta x1 - x0, 5.0, 0.05
    # One rod up and one ray each side.
    assert Enum.count(shapes, &(&1.material == :steel)) == 3
    # The top of the carved head where the data puts it (over the feet).
    feet = 3.0 + 0.6
    tops = for m <- shapes, m.material != :steel, {{_, _, _}, {_, _, z}} = Mesh.bounds(m), do: z - feet
    assert Enum.any?(tops, &(abs(&1 - 5.5) < 1.0e-6))
    # The plinth: an octagon, hollow round the stair.
    base = part(near, "be").shapes
    plinth = List.last(base)
    angles = plinth.points |> Enum.map(fn {x, y, _} -> Float.round(:math.atan2(y, x), 3) end) |> Enum.uniq()
    assert length(angles) <= 9
    assert plinth.points |> Enum.map(fn {x, y, _} -> :math.sqrt(x * x + y * y) end) |> Enum.min() > 0.5
    # The base: its bronze panels (the back in two, at the door) and
    # figures, the dark of its door, windows and slots, and the terrace.
    assert Enum.count(base, &(&1.material == :bronze)) == 5 + 4
    assert Enum.count(base, &(&1.material == :dark)) == 1 + 8 + 24
    {{tx0, _, _}, {tx1, _, _}} = base |> Enum.flat_map(& &1.points) |> World.Vec.bounds()
    assert_in_delta tx1 - tx0, 9.0, 0.01
    # The stair from the floor of the room, and the room in the collision.
    {{_, _, first}, _} = part(near, "cau_thang").shapes |> hd() |> Mesh.bounds()
    assert first < 1.0
    assert Enum.any?(near.extras["collision"], &(&1["name"] == "be_mai"))
    # The rail along the curves.
    assert length(part(near, "lan_can").shapes) > 20

    mid = statue(:mid, o)
    assert Check.model(mid) == :ok
    assert length(part(mid, "lan_can").shapes) == 1
    # At far: the ring, with no arm, rod or ray; a plinth of facets of no
    # given top.
    far = statue(:far, Map.delete(o, "plinth_top"))
    assert Enum.count(part(far, "tuong").shapes, &(&1.material == :steel)) == 0
  end

  test "the errors of the options of a statue of forms" do
    bad = %{
      "race" => %{"martian" => 1},
      "face" => %{"no-slider" => 0.5, "head-square" => 2},
      "head" => %{"top" => 1.0, "nose" => [0.5, 2.0], "narrow" => 0.9},
      "hands" => %{"length" => 0.5, "turn" => 0, "wrist" => [-1.0, 1.0]},
      "ring" => %{"center" => [0, 1], "radius" => 0.1, "tube" => 0.1, "lean" => 0, "rods" => 1},
      "forms" => [%{"box" => [[0, 0, 0]]}]
    }

    assert {:error, errors} = Orders.check(%{"blueprint" => "statue", "options" => bad})
    paths = Map.new(errors, &{&1["path"], &1["message"]})
    assert paths["options.race"] =~ "african, asian, caucasian"
    assert paths["options.face"] =~ "head-square, no-slider"
    assert paths["options.head"] =~ "top over the nose"
    assert paths["options.hands"] =~ "wrist at x over 0"
    assert paths["options.ring"] =~ "twice the tube"
    assert paths["options.forms.0.box"] =~ "two corners"

    shapes = %{"race" => 1, "face" => 1, "head" => %{"top" => 1}, "hands" => [], "ring" => %{}}
    assert {:error, errors} = Orders.check(%{"blueprint" => "statue", "options" => shapes})
    paths = Map.new(errors, &{&1["path"], &1["message"]})
    assert paths["options.race"] =~ "a map of"
    assert paths["options.face"] =~ "a map of"
    assert paths["options.head"] =~ "{top, nose: [y, z], narrow}"
    assert paths["options.hands"] =~ "{length, turn, wrist: [x, z]}"
    assert paths["options.ring"] =~ "{center: [y, z], radius, tube, lean, rods}"
  end

  test "the choices of the blueprint in data are the hair and the poses of a person" do
    {:ok, b} = Blueprints.fetch("statue")
    values = Map.new(b.options, &{&1.name, &1.values})
    hair = World.People.Data.assets() |> Map.fetch!("hair") |> Map.keys() |> Enum.sort()
    assert values["hair"] == ["none" | hair]
    assert values["pose"] == ["arms_out" | World.People.Pose.names()]
    assert values["material"] == Enum.map(World.Skills.Statue.materials(), &Atom.to_string/1)
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

  test "the halo is behind the head, as in the photos: no point of it is in front of the back of the head" do
    data = %{"height" => 32.0, "span" => 18.4, "hand" => 2.2}
    {_, %{"figure" => fig}, _} = World.Skills.Figure.make(data, %{}, %{})
    {_, %{"meshes" => halo}, _} = World.Skills.Halo.make(%{}, %{"figure" => %{"figure" => fig}}, %{level: :near})
    neck = elem(fig.marks["head"], 2)
    head = for {ps, _} <- fig.surfaces, {_, _, z} = p <- ps, z > neck, do: p
    {{_, back, _}, {_, face, _}} = World.Vec.bounds(head)
    {{_, _, _}, {_, front, _}} = World.Vec.bounds(Enum.flat_map(halo, & &1.points))
    # The figure looks to +y: the halo is behind the back of the head.
    assert front <= back + 1.0e-6 and face > back
  end

  @tag timeout: 300_000
  test "at near the head and the hands are carved from the full mesh, out of the cast; at mid the cast has them" do
    data = %{"height" => 32.0, "span" => 18.4, "hand" => 2.2}
    {_, %{"figure" => near}, _} = World.Skills.Figure.make(data, %{}, %{level: :near})
    {_, %{"figure" => mid}, _} = World.Skills.Figure.make(data, %{}, %{level: :mid})
    assert mid.carved == [] and mid.hands != [] and near.hands == []
    assert Enum.map(near.carved, &elem(&1, 0)) == ~w(head hand_l hand_r)

    # The face of the full mesh, with its eyes: thousands of triangles.
    {head_points, head_tris} = near.carved |> List.keyfind("head", 0) |> elem(1)
    assert length(head_tris) > 3000 and length(head_points) > 1500

    # The open hands reach the span.
    tips = for {"hand_" <> _, {ps, _}} <- near.carved, do: ps |> Enum.map(fn {x, _, _} -> abs(x) end) |> Enum.max()
    for t <- tips, do: assert_in_delta(t, 9.2, 1.0e-6)

    # The cast has no triangle of the skin of the head and the hands.
    count = fn fig -> fig.surfaces |> Enum.map(fn {_, tris} -> length(tris) end) |> Enum.sum() end
    assert count.(near) < count.(mid)

    {_, %{"meshes" => meshes}, _} = World.Skills.Carve.make(%{}, %{"figure" => %{"figure" => near}}, %{})
    assert length(meshes) == 3 and Enum.all?(meshes, &(&1.material == :stone_wash))
    assert {_, %{"meshes" => []}, _} = World.Skills.Carve.make(%{}, %{"figure" => %{"figure" => mid}}, %{})
  end
end
