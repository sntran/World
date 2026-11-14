defmodule World.HaiDangTest do
  # The lighthouse of Vũng Tàu from edits (plan 0018, section 10), next to the tower of the catalog.
  use ExUnit.Case, async: true

  defp file(name), do: JSON.decode!(File.read!("priv/drawings/#{name}.json"))

  test "the lighthouse from edits: the sizes of the tower of the catalog, and the forms of its photos" do
    d = file("hai_dang_vung_tau_edits")
    assert {:ok, _} = World.Drawing.check(d, "d")
    assert "hai_dang_vung_tau_edits" in World.Drawing.names()
    # The tower that the people build from its blueprint, with its stair inside, keeps its name.
    assert %{"blueprint" => "tower", "options" => %{"name" => "hai_dang_vung_tau", "hollow" => true}} =
             file("hai_dang_vung_tau")

    assert [%{"name" => "hai_dang_vung_tau_edits_thap"} = tower, %{"name" => "hai_dang_vung_tau_edits_nen"} = base] =
             d["nodes"]

    edits = tower["skill"]["sculpt"]["edits"]
    # The round body is a form turned round the z: 3.2 m across under its gallery (1.7 m from the axis at its
    # foot), with the floor of the gallery at 12.6 m, 2.9 m from the axis.
    assert %{"shape" => "revolve", "size" => %{"profile" => body}} = hd(edits)
    assert [1.7, 0] in body and [1.6, 10.8] in body and [2.9, 12.6] in body
    # Four ribs: 5.1 m across, with a foot of 6.6 m at the ground.
    ribs = for %{"shape" => "extrude", "size" => %{"outline" => outline, "depth" => 0.9}} <- edits, do: outline
    assert length(ribs) == 4 and Enum.all?(ribs, &([3.3, 0] in &1 and [2.55, 11.6] in &1))
    # The lantern is 2.85 m across, and the top of the ball on its dome is at 18 m.
    revolves = for %{"shape" => "revolve", "size" => %{"profile" => profile}} <- edits, do: profile
    assert Enum.any?(revolves, &([1.42, 12.6] in &1))
    assert %{"size" => [0.22], "at" => [0, 0, 17.78]} = Enum.find(edits, &(&1["shape"] == "ball"))
    # The plate of brass on one face.
    assert Enum.any?(edits, &(&1["color"] == "#b8923c" and &1["mode"] == "paint"))
    # The rail of 72 bars, the ladder, the two pipes, the rod and the flag are thin: a detail with small cells
    # at near and mid.
    assert [%{"levels" => ["near", "mid"], "cells" => %{"near" => 0.012, "mid" => 0.012}, "edits" => thin}] =
             tower["skill"]["sculpt"]["details"]

    assert Enum.count(thin, &(&1["shape"] == "tube")) == 72 + 2 + 2 + 1 + 3 + 1
    # The round step is the platform of OpenStreetMap: 7.8 m across.
    assert %{"shape" => "cylinder", "size" => [3.9, 0.1]} = hd(base["skill"]["sculpt"]["edits"])
    assert [what, sizes, forms] = d["sources"]
    assert what =~ "hai_dang_vung_tau" and sizes =~ "tower of the catalog" and forms =~ "A guess"
  end
end
