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
end
