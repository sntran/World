defmodule World.StatuePartsTest do
  # The statue of Christ of Vũng Tàu in parts, from edits (plan 0014): the
  # check of its sizes against its sources, as the inspection of a site
  # before the parts go together.
  use ExUnit.Case, async: true

  alias World.{Build, Catalog, Detail, Mesh, Scene}

  # (Eight sculptures at the far level, when the other tests work too.)
  @moduletag timeout: 1_800_000

  test "the statue in parts has the sizes of its sources: 31 m to the top of its halo, 18.4 m from fingertip to fingertip" do
    {:ok, fun} = Catalog.fetch("tuong_chua_kito_vua")
    model = Detail.with(:far, fun)
    assert model.kind == :statue
    assert Enum.any?(model.sources, &(&1 =~ "kitovungtau.com"))

    # Eight parts, each a sculpture with a role and an image of its own.
    names = ~w(de vom ao ao_choang tay_ao ban_tay dau hao_quang)
    assert Enum.map(model.nodes, &elem(&1, 0)) == names
    roles = for {_, part, _} <- model.nodes, do: part.shapes |> Enum.map(& &1.material) |> Enum.uniq()
    assert roles == for(i <- 1..8, do: [:"part_0#{i}"])
    images = for [role] <- roles, do: model.materials[role]["image"]
    assert Enum.all?(images) and length(Enum.uniq(images)) == 8

    # The monument on its ground: a base of 6 m, a dome of 3 m, and 22 m
    # from the soles to the top of the halo (the rod of 1 m over it is not
    # at the far level).
    {{x0, _, z0}, {x1, _, z1}} = model |> Build.scene(level: :far) |> Scene.bounds()
    assert_in_delta z0, 0.0, 0.05
    assert_in_delta z1, 31.0, 0.3
    # From fingertip to fingertip.
    assert_in_delta x1 - x0, 18.4, 0.6

    # Each part in the axes of the figure: 0 at the soles.
    box = fn name ->
      {_, part, _} = Enum.find(model.nodes, &(elem(&1, 0) == name))
      part.shapes |> Enum.map(&Mesh.bounds/1) |> Enum.flat_map(&Tuple.to_list/1) |> World.Vec.bounds()
    end

    {{_, _, base}, {_, _, roof}} = box.("de")
    assert_in_delta base, -9.0, 0.05
    assert_in_delta roof, -3.0, 0.3
    {{_, _, foot}, {_, _, top}} = box.("vom")
    assert_in_delta foot, -3.0, 0.15
    assert_in_delta top, 0.0, 0.7
    # The top of the head at 20.8 m, the cuffs 14.15 m apart, the halo 4.6 m across.
    assert_in_delta elem(elem(box.("dau"), 1), 2), 20.8, 0.3
    {{left, _, _}, {right, _, _}} = box.("tay_ao")
    assert_in_delta right - left, 14.15, 0.3
    {{h0, _, _}, {h1, _, _}} = box.("hao_quang")
    assert_in_delta h1 - h0, 4.6, 0.2
  end

  test "the statue has its inside at the near level: a room, a well, a stair of 133 steps, six open windows" do
    drawing = "priv/drawings/tuong_chua_kito_vua.json" |> File.read!() |> JSON.decode!()
    data = Map.new(drawing["nodes"], &{&1["name"], &1["skill"]["sculpt"]})
    inside = fn name -> for e <- data[name]["edits"], e["levels"] == ["near"], e["mode"] == "subtract", do: e end
    # The room of the base with its door and the hole in its roof; the dome; the well in the robe and in the cape.
    assert length(inside.("de")) == 3 and length(inside.("vom")) == 2
    assert length(inside.("ao_choang")) == 2
    # The well of the robe, and an opening for each of its three windows (each goes through the front and the back).
    assert length(inside.("ao")) == 4
    # At mid and far the windows are paints.
    assert Enum.count(data["ao"]["edits"], &(&1["levels"] == ["mid", "far"] and &1["mode"] == "paint")) == 3 * 14

    # The stair is a detail of the robe at near: 133 steps of 18.6 cm round a post, 12 steps for each turn,
    # from the floor of the room (0.3 m over the ground) to the floor of the shoulders.
    [stair] = data["ao"]["details"]
    assert stair["levels"] == ["near"]
    [step | _] = stair["edits"]
    assert %{"count" => 133, "angle" => 30, "move" => [0, 0, rise]} = step["repeat"]
    assert_in_delta rise, 0.186, 0.001
    [_, _, first] = step["at"]
    assert_in_delta first + 0.04 - rise, -8.7, 0.001
    assert_in_delta first + 0.04 + 132 * rise, 16.0, 0.01
    # The grilles of the six windows are in the same detail.
    assert length(stair["edits"]) == 2 + 6 * 13
    assert World.Drawing.check(drawing, "d") |> elem(0) == :ok
  end
end
