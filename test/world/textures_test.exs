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

  test "the textures of made things: a tile of one pitch with the pattern of a surface, at each level (plan 0020, D8)" do
    assert Enum.all?(~w(corrugated shutter panes), &(&1 in Textures.names()))

    for {name, scale} <- [{"corrugated", [4.0, 4.0]}, {"shutter", [12.5, 12.5]}, {"panes", [1.8182, 1.5385]}],
        level <- [:near, :mid, :far] do
      spec = Textures.spec(name, level)
      assert spec["image_transform"] == %{"scale" => scale} and spec["normal_scale"] == 1.0
      assert {"image/png", color} = spec["image"]
      assert {"image/png", normal} = spec["normal_image"]
      assert {64, 64, 3, _} = World.PNG.decode(color)
      assert {64, 64, 3, _} = World.PNG.decode(normal)
    end

    assert Textures.made("panes") == Textures.made("panes")
    normals = fn name -> name |> Textures.made() |> elem(1) |> World.PNG.decode() |> elem(3) end
    across = fn row -> for i <- 0..63, do: :binary.at(row, 3 * i) end

    # The ribs of a roof go along v: each row is the same, and the normal turns across u.
    rows = normals.("corrugated")
    assert elem(rows, 10) == elem(rows, 50)
    assert Enum.max(across.(elem(rows, 10))) - Enum.min(across.(elem(rows, 10))) > 40
    # The ribs of a shutter go along u: each row is even, and the rows are not the same.
    rows = normals.("shutter")
    assert across.(elem(rows, 10)) |> Enum.uniq() |> length() == 1 and elem(rows, 10) != elem(rows, 30)
    # The frames of the panes are darker than the panes.
    {_, _, _, rows} = "panes" |> Textures.made() |> elem(0) |> World.PNG.decode()
    assert :binary.at(elem(rows, 32), 0) < :binary.at(elem(rows, 32), 3 * 32)

    # A drawing gives the texture to a role: its images at far too.
    raw = %{
      "name" => "shed",
      "materials" => %{"roof_corrugated" => %{"texture" => "corrugated"}},
      "parts" => %{
        "roof" => %{
          "shapes" => [%{"box" => %{"from" => [0, 0, 0], "to" => [3, 4, 0.05]}, "material" => "roof_corrugated"}]
        }
      },
      "nodes" => [%{"name" => "roof", "part" => "roof"}]
    }

    assert {:ok, _} = Drawing.check(raw, "d")
    far = Build.scene(Drawing.build(raw), level: :far).materials.roof_corrugated
    assert far["normal_image"] && far["image_transform"] == %{"scale" => [4.0, 4.0]}
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
