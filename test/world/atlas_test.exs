defmodule World.AtlasTest do
  # (Not async: a test changes the most texels on a side of an atlas, in the application environment.)
  use ExUnit.Case, async: false

  alias World.{Atlas, GLB, GLBHelper, PNG}
  alias World.Scene
  alias World.Scene.{Node, Primitive}

  # An image of one color, `side` texels on a side (`{r, g, b}` or `{r, g, b, a}`).
  defp solid(side, color) do
    texel = color |> Tuple.to_list() |> :binary.list_to_bin()
    {"image/png", PNG.encode(List.duplicate(:binary.copy(texel, side), side), tuple_size(color))}
  end

  # An image with a different color at each texel.
  defp ramp(side) do
    rows = for y <- 0..(side - 1), do: for(x <- 0..(side - 1), into: <<>>, do: <<x * 4, y * 4, 100>>)
    {"image/png", PNG.encode(rows, 3)}
  end

  # The material of a bake: an image of color, and its normal and finish images when `full`.
  defp baked(image, full \\ true) do
    base = %{
      "image" => image,
      "atlas" => true,
      "occlusion" => true,
      "color" => [255, 255, 255],
      "roughness" => 0.5,
      "metalness" => 0.0
    }

    {"image/png", png} = image
    {side, _, _, _} = PNG.decode(png)

    if full,
      do:
        Map.merge(base, %{"normal_image" => solid(side, {120, 130, 250}), "finish_image" => solid(side, {200, 150, 10})}),
      else: base
  end

  defp tri(material, uvs \\ [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]) do
    %Primitive{
      material: material,
      positions: [{0.0, 0.0, 0.0}, {1.0, 0.0, 0.0}, {0.0, 1.0, 0.0}],
      normals: List.duplicate({0.0, 0.0, 1.0}, 3),
      indices: [0, 1, 2],
      uvs: uvs
    }
  end

  defp texel(png, x, y) do
    {_, _, c, rows} = PNG.decode(png)
    binary_part(elem(rows, y), x * c, c)
  end

  # A house of three parts with bakes (two of them with the same images) and a pane of glass with no image.
  defp house do
    red = ramp(64)

    %Scene{
      materials: %{
        part_01: baked(red),
        part_02: baked(solid(32, {0, 0, 200}), false),
        part_03: baked(red),
        glass: %{"color" => [40, 50, 60], "roughness" => 0.05, "metalness" => 0.0}
      },
      nodes: [%Node{name: "house", primitives: [tri(:part_01), tri(:part_02), tri(:part_03), tri(:glass)]}]
    }
  end

  test "the places of squares in an atlas: the largest first, each at a multiple of its side" do
    assert {:ok, 128, places} = Atlas.pack(%{a: 64, b: 32, c: 32, d: 32, e: 16})
    # (A free square of 64 is cut in four for b, c and d; one of 32 in four for e.)
    assert places == %{a: {0, 0}, b: {64, 0}, c: {96, 0}, d: {64, 32}, e: {96, 32}}
    assert {:ok, 64, %{a: {0, 0}}} = Atlas.pack(%{a: 64})
    # (When the free squares of 16 are all taken, the next square of 32 is cut in four.)
    assert {:ok, 64, %{a: {0, 0}, b: {32, 0}, c: {48, 0}, d: {32, 16}, e: {48, 16}, f: {0, 32}}} =
             Atlas.pack(%{a: 32, b: 16, c: 16, d: 16, e: 16, f: 16})

    assert Atlas.pack(%{a: 8192, b: 8192}) == :over
  end

  test "an order with an atlas: one material for the parts with bakes, one primitive, the UVs in their squares (R14, D13)" do
    scene = Atlas.scene(house())
    assert Map.keys(scene.materials) |> Enum.sort() == [:atlas, :glass]
    atlas = scene.materials.atlas
    assert atlas["roughness"] == 1.0 and atlas["metalness"] == 1.0 and atlas["atlas"] and atlas["occlusion"]
    assert scene.materials.glass == house().materials.glass

    # The three parts in one primitive; the glass stays. The images of part_01 and part_03 are the
    # same: one square of 64 at the corner; part_02 has its square of 32 next to it, in an atlas of 128.
    [%Node{primitives: [joined, glass]}] = scene.nodes
    assert joined.material == :atlas and glass.material == :glass
    assert length(joined.positions) == 9 and joined.indices == [0, 1, 2, 3, 4, 5, 6, 7, 8]
    assert Enum.take(joined.uvs, 3) == [{0.0, 0.0}, {0.5, 0.0}, {0.0, 0.5}]
    assert Enum.slice(joined.uvs, 3, 3) == [{0.5, 0.0}, {0.75, 0.0}, {0.5, 0.25}]
    assert Enum.drop(joined.uvs, 6) == Enum.take(joined.uvs, 3)

    # The images: each square at its place; the maps that part_02 does not have are its values (a
    # flat normal, the finish of its factors: the occlusion 1, the roughness 0.5, no metal).
    {"image/png", color} = atlas["image"]
    {"image/png", normal} = atlas["normal_image"]
    {"image/png", finish} = atlas["finish_image"]
    assert {128, 128, 3, _} = PNG.decode(color)
    assert texel(color, 10, 20) == <<40, 80, 100>> and texel(color, 70, 10) == <<0, 0, 200>>
    assert texel(color, 10, 100) == <<0, 0, 0>>
    assert texel(normal, 10, 10) == <<120, 130, 250>> and texel(normal, 70, 10) == <<128, 128, 255>>
    assert texel(finish, 10, 10) == <<200, 150, 10>> and texel(finish, 70, 10) == <<255, 128, 0>>
    refute Map.has_key?(atlas, "glow_image")

    # The GLB: one material with the images, and the glass.
    json = GLBHelper.json(GLB.encode(scene))
    assert length(json["materials"]) == 2 and length(json["images"]) == 3
    assert [%{"primitives" => [_, _]}] = json["meshes"]
  end

  test "the fill of each chart stays in the atlas: its texels are the texels of its image, and a level of the mipmaps has no texel of another square (R15)" do
    scene = Atlas.scene(house())
    {"image/png", color} = scene.materials.atlas["image"]
    {"image/png", ramp} = house().materials.part_01["image"]
    {_, _, _, rows} = PNG.decode(color)
    {_, _, _, own} = PNG.decode(ramp)
    assert for(y <- 0..63, do: binary_part(elem(rows, y), 0, 64 * 3)) == Tuple.to_list(own)

    # Each level of the mipmaps: the mean of 2 by 2 texels. The square of part_02 (32, at x 64) is
    # blue at each level down to 1 texel: no texel of the ramp or of the blank goes into it.
    levels = Stream.iterate({rows, 128}, fn {rows, side} -> {half(rows, side), div(side, 2)} end)

    for {rows, side} <- Enum.take(levels, 6) do
      s = div(32 * side, 128)
      x0 = div(64 * side, 128)

      assert Enum.all?(0..(s - 1), fn y ->
               binary_part(elem(rows, y), x0 * 3, s * 3) == :binary.copy(<<0, 0, 200>>, s)
             end)
    end
  end

  defp half(rows, side) do
    for y <- 0..(div(side, 2) - 1) do
      for x <- 0..(div(side, 2) - 1), c <- 0..2, into: <<>> do
        at = fn xx, yy -> :binary.at(elem(rows, yy), xx * 3 + c) end
        <<div(at.(2 * x, 2 * y) + at.(2 * x + 1, 2 * y) + at.(2 * x, 2 * y + 1) + at.(2 * x + 1, 2 * y + 1) + 2, 4)>>
      end
    end
    |> List.to_tuple()
  end

  test "an atlas over the most texels on a side: each image at half of its side, until they fit" do
    Application.put_env(:world, :atlas_most, 64)
    on_exit(fn -> Application.delete_env(:world, :atlas_most) end)

    scene = Atlas.scene(house())
    {"image/png", color} = scene.materials.atlas["image"]
    assert {64, 64, 3, _} = PNG.decode(color)
    # (The ramp at half of its side: each texel the mean of 2 by 2.)
    assert texel(color, 5, 10) == <<42, 82, 100>> and texel(color, 40, 5) == <<0, 0, 200>>
    [%Node{primitives: [joined, _]}] = scene.nodes
    assert Enum.slice(joined.uvs, 3, 3) == [{0.5, 0.0}, {0.75, 0.0}, {0.5, 0.25}]
  end

  test "a color image with an alpha, a glow, a part with no UVs, and parts with joints" do
    glow = Map.put(baked(solid(16, {10, 200, 30, 128}), false), "glow_image", solid(16, {255, 200, 100}))

    skinned = %{
      tri(:part_01)
      | joints: [{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}],
        weights: List.duplicate({1.0, 0.0, 0.0, 0.0}, 3)
    }

    scene =
      Atlas.scene(%Scene{
        materials: %{part_01: baked(solid(32, {1, 2, 3})), part_02: glow},
        nodes: [
          %Node{name: "a", primitives: [skinned, %{skinned | positions: Enum.reverse(skinned.positions)}]},
          %Node{name: "b", primitives: [tri(:part_02, nil)]}
        ]
      })

    atlas = scene.materials.atlas
    {"image/png", color} = atlas["image"]
    {"image/png", lit} = atlas["glow_image"]
    assert {64, 64, 4, _} = PNG.decode(color)
    # (The image of part_01 had no alpha: 255. The glow of part_01 is black.)
    assert texel(color, 1, 1) == <<1, 2, 3, 255>> and texel(color, 33, 1) == <<10, 200, 30, 128>>
    assert texel(lit, 1, 1) == <<0, 0, 0>> and texel(lit, 33, 1) == <<255, 200, 100>>
    # (Two primitives with joints stay two; a primitive with no UVs keeps none.)
    [%Node{primitives: [_, _]}, %Node{primitives: [%Primitive{material: :atlas, uvs: nil}]}] = scene.nodes
  end

  test "a material that is not a bake stays as it is: a repeat, a transform, maps of other sides, an image that is not a square" do
    materials = %{
      tiled: Map.put(baked(solid(16, {1, 1, 1})), "image_transform", %{"scale" => [2.0, 2.0]}),
      mixed: Map.put(baked(solid(16, {1, 1, 1})), "normal_image", solid(32, {128, 128, 255})),
      wide: %{"image" => {"image/png", PNG.encode([<<1, 2, 3, 4, 5, 6>>], 3)}, "roughness" => 0.5, "metalness" => 0.0},
      plain: %{"color" => [1, 2, 3], "roughness" => 0.5, "metalness" => 0.0}
    }

    scene = %Scene{materials: materials, nodes: [%Node{primitives: [tri(:tiled), tri(:plain)]}]}
    assert Atlas.scene(scene) == scene
    assert Atlas.scenes([scene]) == {[scene], %{}}
  end

  test "the atlas of a set: the images one time, and each GLB refers to them by a URL (R14, D12)" do
    other = %Scene{
      materials: %{part_01: baked(solid(32, {9, 9, 9})), glass: house().materials.glass},
      nodes: [%Node{name: "other", primitives: [tri(:part_01), tri(:glass)]}]
    }

    {[a, b], images} = Atlas.scenes([house(), other], uri: fn map, ext -> "../set.#{Atlas.names()[map]}.#{ext}" end)
    assert Enum.sort(Map.keys(images)) == ~w(finish_image image normal_image)
    assert {"image/png", png} = images["image"]
    assert {128, 128, 3, _} = PNG.decode(png)
    assert a.materials.atlas == b.materials.atlas
    assert a.materials.atlas["image"] == {:uri, "../set.color.png", "image/png"}

    for scene <- [a, b] do
      json = GLBHelper.json(GLB.encode(scene))

      assert Enum.sort(for(i <- json["images"], do: i["uri"])) ==
               ~w(../set.color.png ../set.finish.png ../set.normal.png)

      assert Enum.all?(json["images"], &(not is_map_key(&1, "bufferView")))
    end

    # The square of the other model is the third (32 at x 96): its UVs go there.
    [%Node{primitives: [p, _]}] = b.nodes
    assert p.uvs == [{0.75, 0.0}, {1.0, 0.0}, {0.75, 0.25}]
  end

  test "the images of an atlas as KTX2: each one a file of KTX2, and the GLB needs KHR_texture_basisu (R16, D14)" do
    scene = Atlas.scene(house(), images: "ktx2")
    atlas = scene.materials.atlas
    assert {"image/ktx2", <<0xAB, "KTX 20", 0xBB, _::binary>>} = atlas["image"]
    json = GLBHelper.json(GLB.encode(scene))
    assert json["extensionsRequired"] == ["KHR_texture_basisu"] and "KHR_texture_basisu" in json["extensionsUsed"]
    assert Enum.all?(json["images"], &(&1["mimeType"] == "image/ktx2"))

    assert Enum.all?(
             json["textures"],
             &(is_map_key(&1["extensions"]["KHR_texture_basisu"], "source") and not is_map_key(&1, "source"))
           )

    # With a URL: the images of a set as KTX2.
    {_, images} = Atlas.scenes([house()], images: "ktx2", uri: fn map, ext -> "#{map}.#{ext}" end)
    assert {"image/ktx2", _} = images["normal_image"]
  end

  test "the images of an order as KTX2 with no atlas: each image of RGB or RGBA with sides of a multiple of 4" do
    shared = solid(8, {10, 20, 30})
    odd = {"image/png", PNG.encode(List.duplicate(<<1, 2, 3, 4, 5, 6>>, 2), 3)}

    scene = %Scene{
      materials: %{
        a: %{
          "image" => shared,
          "normal_image" => solid(8, {128, 128, 255, 255}),
          "roughness" => 0.5,
          "metalness" => 0.0
        },
        b: %{"image" => shared, "roughness" => 0.5, "metalness" => 0.0},
        c: %{"image" => odd, "roughness" => 0.5, "metalness" => 0.0},
        d: %{"color" => [1, 2, 3], "roughness" => 0.5, "metalness" => 0.0}
      }
    }

    packed = Atlas.ktx2(scene)
    assert {"image/ktx2", file} = packed.materials.a["image"]
    assert packed.materials.b["image"] == {"image/ktx2", file}
    assert {"image/ktx2", _} = packed.materials.a["normal_image"]
    assert packed.materials.c == scene.materials.c and packed.materials.d == scene.materials.d
    # (The color is in sRGB, the normal is linear: two different files of one image of the same texels.)
    assert file == World.KTX2.from_png(elem(shared, 1))
  end
end
