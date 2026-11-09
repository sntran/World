defmodule World.TexturesTest do
  # The textures that World makes (plan 0004, D7): washed stone at near,
  # the same bytes each time, and none at mid and far.
  use ExUnit.Case, async: true

  alias World.{Build, Drawing, Textures}

  test "washed stone: a base color image and a normal image that repeat each 0.3 m, only at near" do
    spec = Textures.spec("washed_stone", :near)
    assert {"image/png", <<137, "PNG", _::binary>> = color} = spec["image"]
    assert {"image/png", <<137, "PNG", _::binary>>} = spec["normal_image"]
    assert_in_delta spec["image_scale"], 1 / 0.3, 1.0e-3
    assert Textures.washed_stone() == Textures.washed_stone() and byte_size(color) > 1000
    <<_::binary-16, w::32, h::32, _::binary>> = color
    assert {w, h} == {256, 256}
    assert Textures.spec("washed_stone", :mid) == nil and Textures.spec("washed_stone", :far) == nil
    assert Textures.spec("marble", :near) == nil
  end

  test "a drawing gives a texture to a role: at near the GLB has its images, at far none" do
    raw = %{
      "name" => "slab",
      "materials" => %{"stone_wash" => %{"texture" => "washed_stone", "roughness" => 0.85}},
      "parts" => %{
        "slab" => %{"shapes" => [%{"box" => %{"from" => [0, 0, 0], "to" => [1, 1, 0.1]}, "material" => "stone_wash"}]}
      },
      "nodes" => [%{"name" => "slab", "part" => "slab"}]
    }

    assert {:ok, _} = Drawing.check(raw, "d")
    # The level of the scene chooses: the drawing keeps the name.
    item = Drawing.build(raw)
    near = Build.scene(item, level: :near).materials.stone_wash
    assert (near["normal_image"] && near["roughness"] == 0.85) and not Map.has_key?(near, "texture")
    assert near["color"] == World.GLB.palette()["stone_wash"]["color"]
    far = Build.scene(item, level: :far).materials.stone_wash
    refute Map.has_key?(far, "image") or Map.has_key?(far, "texture")
  end

  test "a photo of a relief is once on its panel: its image, its normal image, and the transform of the panel" do
    assert "relief_last_supper" in Textures.names()
    spec = Textures.spec("relief_last_supper", :near)
    assert {"image/jpeg", <<0xFF, 0xD8, _::binary>>} = spec["image"]
    assert {"image/jpeg", <<0xFF, 0xD8, _::binary>>} = spec["normal_image"]
    assert Textures.spec("relief_last_supper", :mid) == nil

    raw = %{
      "name" => "panel",
      "materials" => %{"relief_front" => %{"texture" => "relief_last_supper", "panel" => [-2.0, 1.0, 2.0, 2.0]}},
      "parts" => %{
        "panel" => %{
          "shapes" => [%{"box" => %{"from" => [-2, 0, 1], "to" => [2, 0.1, 2]}, "material" => "relief_front"}]
        }
      },
      "nodes" => [%{"name" => "panel", "part" => "panel"}]
    }

    assert {:ok, _} = Drawing.check(raw, "d")
    item = Drawing.build(raw)
    near = Build.scene(item, level: :near).materials.relief_front
    # u from -2 to 2 and v from 1 to 2 go to 0 to 1.
    assert near["image_transform"] == %{"scale" => [0.25, 1.0], "offset" => [0.5, -1.0]}
    refute Map.has_key?(near, "panel")
    json = World.GLBHelper.json(World.GLB.encode(Build.scene(item, level: :near)))
    [m] = json["materials"]
    assert m["pbrMetallicRoughness"]["baseColorTexture"]["extensions"]["KHR_texture_transform"]["offset"] == [0.5, -1.0]
    assert m["normalTexture"]["extensions"]["KHR_texture_transform"]["scale"] == [0.25, 1.0]
    far = Build.scene(item, level: :far).materials.relief_front
    refute Map.has_key?(far, "image") or Map.has_key?(far, "image_transform")

    bad = put_in(raw, ["materials", "relief_front", "panel"], [2.0, 1.0, -2.0, 2.0])

    assert {:error, [{"d.materials.relief_front.panel", "must be [u0, v0, u1, v1], u1 over u0 and v1 over v0"}]} =
             Drawing.check(bad, "d")

    assert {:error, [{"m.relief_back", _}]} = Drawing.check_materials(%{"relief_back" => 3}, "m")
  end
end
