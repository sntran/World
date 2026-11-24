defmodule World.Sculpt.ShadeTest do
  # The look of a level of a sculpture with a budget and no maps (plan
  # 0020, step 2: R6 to R9): the occlusion in the alpha of COLOR_0 (or in
  # the color), `_FINISH` with the roughness, the metal and the glow of
  # each point, the cut that keeps the borders of the glow, and the flat
  # look with neither.
  use ExUnit.Case, async: true

  alias World.{Build, Detail, Drawing, GLB, GLBHelper, Mesh, Orders, Scene, SDF}
  alias World.Sculpt.Shade

  # A slab of 2 m by 2 m, 0.5 m high, with a groove along it (a crease on
  # each of its sides), a lamp (a paint that glows) and a plate of metal.
  defp slab(more \\ %{}) do
    Map.merge(
      %{
        "edits" => [
          %{
            "shape" => "box",
            "size" => [1.0, 1.0, 0.25],
            "at" => [0, 0, 0.25],
            "material" => "plaster",
            "color" => "#c0b090"
          },
          %{"shape" => "box", "size" => [0.06, 1.2, 0.2], "at" => [0, 0, 0.5], "mode" => "subtract"},
          %{
            "shape" => "box",
            "size" => [0.2, 0.2, 0.05],
            "at" => [0.6, 0, 0.5],
            "mode" => "paint",
            "glow" => 0.8,
            "color" => "#ffe0a0",
            "blend" => 0.01
          },
          %{
            "shape" => "box",
            "size" => [0.2, 0.2, 0.05],
            "at" => [-0.6, 0, 0.5],
            "mode" => "paint",
            "metal" => 1.0,
            "roughness" => 0.2,
            "blend" => 0.01
          }
        ],
        "cells" => %{"far" => 0.04},
        "budget" => %{"far" => 2000}
      },
      more
    )
  end

  defp drawing(data),
    do: %{"name" => "slab", "kind" => "item", "nodes" => [%{"name" => "slab", "skill" => %{"sculpt" => data}}]}

  # The meshes of the sculpture at far.
  defp meshes(data), do: elem(hd(Detail.with(:far, fn -> Drawing.build(drawing(data)) end).nodes), 1).shapes

  # The points of the meshes with their colors and their finish.
  defp points(meshes) do
    for m <- meshes,
        {p, c, f} <- Enum.zip([m.points, m.colors, m.finish || List.duplicate(nil, length(m.points))]),
        do: {p, c, f}
  end

  defp mean(list), do: Enum.sum(list) / max(length(list), 1)

  # The color of the slab (#c0b090), within the mean over the faces round a point (`World.Sculpt.Finish`).
  defp slab_color?({r, g, b}), do: abs(r - 192) <= 10 and abs(g - 176) <= 10 and abs(b - 144) <= 10

  # The points in the groove (its walls and its floor, 0.12 m wide and 0.2 m deep), and on the top far from the
  # groove and the paints.
  defp groove?({x, y, z}), do: abs(x) < 0.07 and z < 0.48 and abs(y) < 0.9
  defp open?({x, y, z}), do: abs(z - 0.5) < 0.01 and abs(x) > 0.3 and abs(x) < 0.4 and abs(y) < 0.8

  test "a level with a budget and no bake: the occlusion in the alpha of COLOR_0, and the finish of each point (R6)" do
    meshes = meshes(slab())
    all = points(meshes)

    assert Enum.all?(all, fn {_, {r, g, b, a}, {_, _, _}} ->
             r in 0..255 and g in 0..255 and b in 0..255 and a >= 0 and a <= 1
           end)

    # A point in the groove is less open than a point on the open top; the color stays the color of the edits.
    alpha = fn pick -> mean(for {p, {_, _, _, a}, _} <- all, pick.(p), do: a) end
    assert alpha.(&groove?/1) < alpha.(&open?/1) - 0.1
    assert alpha.(&open?/1) > 0.8
    assert Enum.all?(for {p, {r, g, b, _}, _} <- all, open?(p), do: slab_color?({r, g, b}))

    # The finish: the lamp glows (0.8 of 255), the plate is metal and smooth, the rest has the finish of
    # plaster. (The inside of the lamp is one flat face after the cut: its border keeps its points.)
    lamp = for {{x, y, z}, _, f} <- all, abs(x - 0.6) <= 0.2, abs(y) <= 0.2, abs(z - 0.5) < 0.01, do: f
    plate = for {{x, y, z}, _, f} <- all, abs(x + 0.6) <= 0.2, abs(y) <= 0.2, abs(z - 0.5) < 0.01, do: f
    assert Enum.count(lamp, &(elem(&1, 2) == 204)) >= 3
    assert Enum.count(plate, &(elem(&1, 1) == 255 and elem(&1, 0) == 51)) >= 3
    {rough, metal} = GLB.palette()["plaster"] |> then(&{&1["roughness"], &1["metalness"]})
    assert Enum.all?(for {p, _, f} <- all, open?(p), do: f == {round(rough * 255), round(metal * 255), 0})

    # The GLB: COLOR_0 with four floats, and _FINISH: three bytes of each point, normalized, each element in 4 bytes.
    glb = GLB.encode(Build.scene(Detail.with(:far, fn -> Drawing.build(drawing(slab())) end), level: :far))
    json = GLBHelper.json(glb)
    [prim] = for m <- json["meshes"], p <- m["primitives"], do: p
    color = Enum.at(json["accessors"], prim["attributes"]["COLOR_0"])
    finish = Enum.at(json["accessors"], prim["attributes"]["_FINISH"])
    assert color["type"] == "VEC4" and color["componentType"] == 5126
    assert %{"type" => "VEC3", "componentType" => 5121, "normalized" => true} = finish
    view = Enum.at(json["bufferViews"], finish["bufferView"])
    assert view["byteStride"] == 4 and view["byteLength"] == 4 * finish["count"] and view["target"] == 34962
    assert finish["count"] == Enum.at(json["accessors"], prim["attributes"]["POSITION"])["count"]
    bytes = finish_bytes(glb, finish)
    assert Enum.any?(bytes, &match?({_, _, 204}, &1)) and Enum.any?(bytes, &match?({51, 255, _}, &1))
  end

  # The values of an accessor of bytes with a byte stride of 4.
  defp finish_bytes(
         <<"glTF", 2::little-32, _::little-32, len::little-32, "JSON", _::binary-size(len), rest::binary>> = glb,
         acc
       ) do
    <<_::little-32, "BIN", 0, bin::binary>> = rest
    view = Enum.at(GLBHelper.json(glb)["bufferViews"], acc["bufferView"])
    data = binary_part(bin, Map.get(view, "byteOffset", 0), view["byteLength"])
    for <<r, m, g, 0 <- data>>, do: {r, m, g}
  end

  test "occlusion color: the color times how open each point is, no alpha; occlusion false: the colors of the edits" do
    all = points(meshes(slab(%{"occlusion" => "color"})))
    assert Enum.all?(all, fn {_, c, _} -> tuple_size(c) == 3 end)
    gray = fn pick -> mean(for {p, {r, g, b}, _} <- all, pick.(p), do: (r + g + b) / 3) end
    assert gray.(&groove?/1) < gray.(&open?/1) - 10

    # (The GLB has COLOR_0 with three floats.)
    json =
      GLBHelper.json(
        GLB.encode(
          Build.scene(Detail.with(:far, fn -> Drawing.build(drawing(slab(%{"occlusion" => "color"}))) end), level: :far)
        )
      )

    [prim] = for m <- json["meshes"], p <- m["primitives"], do: p
    assert Enum.at(json["accessors"], prim["attributes"]["COLOR_0"])["type"] == "VEC3"

    # With no occlusion, no dirt and no wear, the color of each point is the color of the edits, and the finish of the edits stays.
    none = points(meshes(slab(%{"occlusion" => false})))
    assert Enum.all?(for {p, c, _} <- none, open?(p), do: slab_color?(c))
    assert Enum.any?(none, fn {_, _, f} -> f && elem(f, 2) == 204 end)

    # With no finish of an edit either, the meshes stay as they are: no finish.
    plain = %{"occlusion" => false, "edits" => Enum.take(slab()["edits"], 2)}
    assert Enum.all?(meshes(slab(plain)), &(&1.finish == nil))
  end

  test "dirt makes the creases darker and more rough, wear makes the sharp edges lighter" do
    clean = points(meshes(slab(%{"occlusion" => "color"})))
    dirty = points(meshes(slab(%{"occlusion" => "color", "dirt" => 1.0, "wear" => 1.0})))
    gray = fn all, pick -> mean(for {p, {r, g, b}, _} <- all, pick.(p), do: (r + g + b) / 3) end
    rough = fn all, pick -> mean(for {p, _, {r, _, _}} <- all, pick.(p), do: r) end
    assert gray.(dirty, &groove?/1) < gray.(clean, &groove?/1) - 5
    assert rough.(dirty, &groove?/1) > rough.(clean, &groove?/1)

    # The top edges of the slab (x or y near 1, z near 0.5): lighter with wear.
    edge? = fn {x, y, z} -> abs(z - 0.5) < 0.03 and (abs(abs(x) - 1.0) < 0.03 or abs(abs(y) - 1.0) < 0.03) end
    assert gray.(dirty, edge?) > gray.(clean, edge?)
  end

  test "no look of the points: a level with a bake, a level with no budget, the flat look" do
    # (With a bake: the maps have it; the mesh has no colors.)
    baked = meshes(slab(%{"bake" => %{"far" => 128}}))
    assert Enum.all?(baked, &(&1.colors == nil and &1.finish == nil))
    # (No budget: the colors of the edits.)
    loose = meshes(Map.delete(slab(), "budget"))
    assert Enum.all?(loose, &(&1.finish == nil and match?([{_, _, _} | _], &1.colors)))
    flat = meshes(slab(%{"look" => "flat"}))
    assert Enum.all?(flat, &(&1.finish == nil and match?([{_, _, _} | _], &1.colors)))
  end

  test "the flat look of an order (/o/HASH.flat.glb) has no _FINISH and no alpha in COLOR_0 (R8)" do
    order = %{"blueprint" => "drawing", "options" => %{"drawing" => drawing(slab())}}
    assert {:ok, glb} = Orders.build(order, "far", "glb")
    assert "_FINISH" in Map.keys(hd(hd(GLBHelper.json(glb)["meshes"])["primitives"])["attributes"])

    assert {:ok, flat} = Orders.build(order, "far", "flat")
    json = GLBHelper.json(flat)
    attributes = for m <- json["meshes"], p <- m["primitives"], key <- Map.keys(p["attributes"]), uniq: true, do: key
    refute "_FINISH" in attributes
    [prim] = for m <- json["meshes"], p <- m["primitives"], do: p
    assert Enum.at(json["accessors"], prim["attributes"]["COLOR_0"])["type"] == "VEC3"
  end

  test "a light that the larger cells lose, with no cells between in the budget: the mesh of the larger cells (D7)" do
    # (A thin ring that glows: no mesh of a closed ring is in a budget of 12 triangles, and the larger cells lose the ring.)
    data = %{
      "edits" => [%{"shape" => "ring", "size" => [0.1, 0.003], "material" => "plaster", "glow" => 1.0}],
      "cells" => %{"far" => 0.002},
      "budget" => %{"far" => 12}
    }

    {part, _, _} = Detail.with(:far, fn -> World.Skills.Sculpt.make(data, %{}, %{level: :far, name: "ring"}) end)
    assert part.shapes == []
  end

  test "the piece of a brick has the finish of each point when an edit has one (the pins of the cut, D7)" do
    step = 0.04
    %{bricks: bricks} = World.Sculpt.bricks(World.Skills.Sculpt.edits(slab()["edits"]), step)
    pieces = Enum.map(bricks, &World.Sculpt.Surface.decode(World.Sculpt.Surface.piece(&1, step)))
    glows = for p <- pieces, {_, _, glow} <- Map.values(p.finish), do: glow
    assert 204 in glows and 0 in glows
  end

  test "a level with a bake cuts as before step 2: no pins of the finish and of the glow (its maps have them)" do
    data = slab(%{"bake" => %{"far" => 512}, "budget" => %{"far" => 600}})
    edits = World.Skills.Sculpt.edits(data["edits"])
    points = fn meshes -> meshes |> Enum.flat_map(& &1.points) |> MapSet.new() end

    cut = fn pins ->
      World.Sculpt.model(SDF.coarse(edits, 0.04), step: 0.04, budget: 600, cache: false, finish_pins: pins)
    end

    assert points.(meshes(data)) == points.(cut.(false))
    # (With the pins, the cut keeps other points: the borders of the lamp and of the plate.)
    refute points.(cut.(true)) == points.(cut.(false))
  end

  test "the check of occlusion: true, false, alpha or color" do
    for v <- [true, false, "alpha", "color"],
        do: assert(World.Skills.Sculpt.check(slab(%{"occlusion" => v}), "s") == [])

    assert World.Skills.Sculpt.check(slab(%{"occlusion" => "red"}), "s") == [
             {"s.occlusion", "must be one of: true, false, alpha, color"}
           ]

    # (mipmaps stays true or false.)
    assert World.Skills.Sculpt.check(slab(%{"mipmaps" => true}), "s") == []
    assert World.Skills.Sculpt.check(slab(%{"mipmaps" => "yes"}), "s") == [{"s.mipmaps", "must be true or false"}]
  end

  test "the finish of a corner in a primitive and in a GLB; a point with no face; a primitive with a finish is not packed" do
    # A corner with no finish in a primitive with finishes: rough, no metal, no glow.
    a = {{0.0, 0.0, 0.0}, {0.0, 0.0, 1.0}, {255, 255, 255, 0.5}, nil, {10, 20, 30}}
    b = {{1.0, 0.0, 0.0}, {0.0, 0.0, 1.0}}
    c = {{0.0, 1.0, 0.0}, {0.0, 0.0, 1.0}, {255, 0, 0}}
    p = Scene.primitive(:paint, [a, b, c])
    assert p.finish == [{10, 20, 30}, {153, 0, 0}, {153, 0, 0}]
    assert p.colors == [{255, 255, 255, 0.5}, {255, 255, 255, 1.0}, {255, 0, 0, 1.0}]
    assert Scene.pack(p) == p

    # A mesh with a point that no face has: the point keeps its own values (no faces round it to even them).
    edits = [SDF.edit(:box, {1.0, 1.0, 0.25}, at: {0.0, 0.0, 0.25})]
    up = {0.0, 0.0, 1.0}
    # (The fourth point is on the top too, in no face; the second face has no area.)
    points = [{0.0, 0.0, 0.5}, {0.5, 0.0, 0.5}, {0.0, 0.5, 0.5}, {0.9, 0.9, 0.5}]
    mesh = %Mesh{points: points, faces: [[0, 1, 2], [0, 0, 1]], normals: [up, up, up, up]}
    look = %{occlusion: true, into: :alpha, dirt: 0.0, wear: 0.0}
    [shaded] = Shade.meshes([mesh], edits, 0.05, %{}, look)
    assert [{_, _, _, a0}, _, _, {255, 255, 255, a3}] = shaded.colors
    assert a0 > 0.9 and a3 > 0.9
    assert [{_, _, {_, _, _, _}, nil, {_, _, _}} | _] = Mesh.triangles(shaded)
    assert length(shaded.finish) == 4
  end
end
