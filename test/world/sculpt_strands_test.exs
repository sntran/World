defmodule World.Sculpt.StrandsTest do
  # A sculpture with strands (plan 0017): the alpha of its image, and its shells.
  use ExUnit.Case, async: true

  alias World.{Drawing, Frame, Orders, SDF, Sculpt, Vec}
  alias World.Sculpt.Bake

  @moduletag timeout: 600_000

  # The alpha of each texel of a chart (a texel with no chart has none).
  defp alphas(maps), do: for(row <- maps.color, <<_, _, _, a <- row>>, a > 0, do: a)

  test "the bake of a sculpture with strands: the color has an alpha, from the height of the strand and the thin places" do
    # (A strand of 6 cm: some texels wide in an image of 128.)
    hair = [SDF.edit(:ball, {0.3}, color: {180, 170, 160}, surface: {:hair, 0.06})]
    meshes = Sculpt.model(SDF.coarse(hair, 0.05), step: 0.05, budget: 300, cache: false)
    bake = fn edits, look -> Bake.maps([{meshes, edits, 0.05}], 128, %{}, look) end

    # With no strands: three bytes for a texel, and no alpha.
    {_, plain} = bake.(hair, %{})
    assert plain.alpha == false and byte_size(hd(plain.color)) == 3 * 128

    # With strands: four bytes. All the density: each texel of the mass has half of the alpha or more.
    {_, maps} = bake.(hair, %{strands: %{thin: []}})
    assert maps.alpha and byte_size(hd(maps.color)) == 4 * 128 and byte_size(hd(maps.normal)) == 3 * 128
    all = alphas(maps)
    assert length(all) > 3_000 and Enum.min(all) >= 128
    # The strands have different heights: a shell with less alpha at its points shows only some of them.
    assert Enum.count(all, &(&1 > 200)) > 100 and Enum.count(all, &(&1 < 180)) > 100

    # A thin place over the low half of the ball: the low strands go first there.
    low = SDF.edit(:box, {1.0, 1.0, 0.3}, frame: Frame.move({0.0, 0.0, -0.3}), mode: :paint, blend: 0.1)
    {_, thin} = bake.(hair, %{strands: %{thin: [low]}})
    some = alphas(thin)
    assert length(some) < length(all) and Enum.count(some, &(&1 < 128)) > 100 and Enum.max(some) > 200
    # A weak thin place takes less away.
    {_, weak} = bake.(hair, %{strands: %{thin: [%{low | opacity: 0.3}]}})
    assert Enum.sum(alphas(weak)) > Enum.sum(some)

    # A place of another surface, or of none, is whole.
    band = [SDF.edit(:ball, {0.3}, color: {90, 40, 40}, surface: {:fabric, 0.02})]
    {_, whole} = bake.(band, %{strands: %{thin: []}})
    assert whole |> alphas() |> Enum.uniq() == [255]
    {_, bare} = bake.([SDF.edit(:ball, {0.3}, color: {90, 40, 40})], %{strands: %{thin: []}})
    assert bare |> alphas() |> Enum.uniq() == [255]
    # A strand that is smaller than a texel does not show: half of its height, at each place.
    fine = [SDF.edit(:ball, {0.3}, color: {180, 170, 160}, surface: {:hair, 0.0005})]
    {_, flat} = bake.(fine, %{strands: %{thin: []}})
    assert flat |> alphas() |> Enum.uniq() == [198]
  end

  @data %{
    "edits" => [
      %{"shape" => "ball", "size" => [0.1], "color" => "#b0a8a0", "surface" => %{"kind" => "hair", "scale" => 0.005}}
    ],
    "cells" => %{"near" => 0.02, "mid" => 0.02, "far" => 0.02},
    "budget" => %{"near" => 200, "mid" => 120, "far" => 60},
    "bake" => %{"near" => 128, "mid" => 64, "far" => 64},
    "strands" => %{
      "shells" => 2,
      "length" => 0.01,
      "thin" => [%{"shape" => "box", "size" => [1, 1, 0.05], "at" => [0, 0, -0.1], "mode" => "paint", "blend" => 0.03}]
    }
  }

  defp drawing(data),
    do: %{"name" => "hair", "kind" => "prop", "nodes" => [%{"name" => "hair", "skill" => %{"sculpt" => data}}]}

  defp paths(data) do
    case Orders.check(%{"blueprint" => "drawing", "options" => %{"drawing" => drawing(data)}}) do
      {:error, errors} -> Enum.map(errors, & &1["path"])
      {:ok, _} -> []
    end
  end

  test "the data `strands`: shells over the mass at near and mid, an image with alpha, a material that is cut by it" do
    assert paths(@data) == []
    at = "options.drawing.nodes.0.skill.sculpt.strands"
    with_strands = fn strands -> Map.put(@data, "strands", strands) end
    assert paths(with_strands.(%{})) == []
    assert paths(with_strands.(3)) == [at]
    assert paths(with_strands.(%{"shells" => 0})) == ["#{at}.shells"]
    assert paths(with_strands.(%{"shells" => 2, "length" => 1})) == ["#{at}.length"]
    assert paths(with_strands.(%{"thin" => []})) == ["#{at}.thin"]
    assert paths(with_strands.(%{"hairs" => 2})) == ["#{at}.hairs"]

    build = fn data, level -> World.Detail.with(level, fn -> Drawing.build(drawing(data)) end) end
    shapes = fn item -> for {_, part, _} <- item.nodes, m <- part.shapes, do: m end

    # Near: the mass and two shells; mid: one shell; far: the mass only.
    near = build.(@data, :near)
    [mass, one, two] = shapes.(near)
    assert length(shapes.(build.(@data, :mid))) == 2 and length(shapes.(build.(@data, :far))) == 1

    assert mass.colors == nil and length(one.points) == length(mass.points) and one.faces == mass.faces and
             one.uvs == mass.uvs

    # A shell is out along the normals: half of the length, then all of it; with less alpha at its points.
    for {shell, out} <- [{one, 0.005}, {two, 0.01}], {p, q, n} <- Enum.zip([mass.points, shell.points, mass.normals]) do
      assert Vec.len(Vec.sub(Vec.add(p, Vec.scale(n, out)), q)) < 1.0e-9
    end

    assert [{255, 255, 255, a1}] = Enum.uniq(one.colors)
    assert [{255, 255, 255, a2}] = Enum.uniq(two.colors)
    # (The first shell shows the strands over a third of the height, the second over two thirds.)
    assert_in_delta a1, 0.5 / (0.5 + 0.5 * (1 / 3 + 0.05)), 1.0e-12
    assert_in_delta a2, 0.5 / (0.5 + 0.5 * (2 / 3 + 0.05)), 1.0e-12

    # The material: its image has an alpha (a PNG of the color type 6), it is cut by it, and it has two sides.
    material = near.materials[:paint]
    assert %{"alpha_mode" => "MASK", "double_sided" => true, "image" => {"image/png", png}} = material
    assert <<137, "PNG", _::binary-size(21), 6, _::binary>> = png
    assert {"image/png", <<137, "PNG", _::binary-size(21), 2, _::binary>>} = material["normal_image"]
    # The GLB says so.
    <<"glTF", 2::little-32, _::32, size::little-32, "JSON", text::binary-size(size), _::binary>> =
      World.Build.glb(near, level: :near)

    json = JSON.decode!(text)
    assert [%{"alphaMode" => "MASK", "doubleSided" => true}] = json["materials"]

    # (The mass and its shells are one primitive of the material: the alpha of each point is in its color.)
    assert [%{"attributes" => %{"COLOR_0" => color}}] = json["meshes"] |> hd() |> Map.fetch!("primitives")
    assert Enum.at(json["accessors"], color)["type"] == "VEC4"

    # A primitive with an alpha in one color has an alpha in each color: a color with none is whole.
    triangle = fn x, colors ->
      %World.Mesh{points: [{x, 0.0, 0.0}, {x + 1.0, 0.0, 0.0}, {x, 1.0, 0.0}], faces: [[0, 1, 2]], colors: colors}
    end

    mixed = [
      triangle.(0.0, nil),
      triangle.(2.0, List.duplicate({10, 20, 30}, 3)),
      triangle.(4.0, List.duplicate({40, 50, 60, 0.5}, 3))
    ]

    [prim] = hd(World.Build.scene(World.Part.new("mixed", :part, mixed, [])).nodes).primitives
    assert Enum.uniq(prim.colors) == [{255, 255, 255, 1.0}, {10, 20, 30, 1.0}, {40, 50, 60, 0.5}]

    # With no strands: one mesh, an image with no alpha, a plain material.
    plain = build.(Map.delete(@data, "strands"), :near)
    assert [%{colors: nil}] = shapes.(plain)
    assert {"image/png", <<137, "PNG", _::binary-size(21), 2, _::binary>>} = plain.materials[:paint]["image"]
    refute Map.has_key?(plain.materials[:paint], "alpha_mode")
    # With no image at a level (no bake), the strands are not there.
    bare = build.(Map.delete(@data, "bake"), :near)
    assert [%{}] = shapes.(bare)
  end
end
