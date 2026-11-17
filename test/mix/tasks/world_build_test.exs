defmodule Mix.Tasks.World.BuildTest do
  use ExUnit.Case

  @dir Path.join(System.tmp_dir!(), "world_build_test")

  setup do
    File.rm_rf!(@dir)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  test "writes the files of a model, and --check finds a change" do
    Mix.Tasks.World.Build.run(["--dir", @dir, "wheel_bicycle_37_622"])
    assert_received {:mix_shell, :info, ["Wrote 4 files."]}

    for f <-
          ~w(wheel_bicycle_37_622.glb wheel_bicycle_37_622.mid.glb wheel_bicycle_37_622.far.glb wheel_bicycle_37_622.parts.json),
        do: assert(File.exists?(Path.join(@dir, f)))

    Mix.Tasks.World.Build.run(["--dir", @dir, "--check", "wheel_bicycle_37_622"])
    assert_received {:mix_shell, :info, ["The 4 files are the same as the build."]}

    File.write!(Path.join(@dir, "wheel_bicycle_37_622.glb"), "x")

    assert_raise Mix.Error, ~r/not the same as the build/, fn ->
      Mix.Tasks.World.Build.run(["--dir", @dir, "--check", "wheel_bicycle_37_622"])
    end
  end

  test "an unknown model stops the task" do
    assert_raise Mix.Error, ~r/No model nope/, fn -> Mix.Tasks.World.Build.run(["--dir", @dir, "nope"]) end
  end

  # With no name, the task builds each model of the catalog. The catalog of this test has small models
  # (World.Fixtures): the tests do not build the models of World.Catalog.
  test "all the models of a catalog, with the list and the kit" do
    Application.put_env(:world, :catalog, World.Fixtures)
    on_exit(fn -> Application.delete_env(:world, :catalog) end)
    Mix.Tasks.World.Build.run(["--dir", @dir, "--kit", Path.join(@dir, "kit")])
    list = File.read!(Path.join(@dir, "list.json")) |> JSON.decode!()
    assert list == ~w(fixture_building fixture_seat fixture_wheel)

    for name <- list,
        ext <- ~w(.glb .mid.glb .far.glb .parts.json),
        do: assert(File.exists?(Path.join(@dir, name <> ext)))

    assert File.ls!(Path.join(@dir, "kit")) == ["kit.json"]

    assert_raise Mix.Error, ~r/No model wheel_bicycle_37_622 in World.Fixtures/, fn ->
      Mix.Tasks.World.Build.run(["--dir", @dir, "wheel_bicycle_37_622"])
    end
  end

  # CI checks the catalog at each commit in parts at the same time (--part I/N): the files of
  # priv/models are always the build of the code, and a file of a model that left the catalog fails it.
  test "the check of the catalog in parts: each model in one part, the list in part 1, and a file of no model fails" do
    Application.put_env(:world, :catalog, World.Fixtures)
    on_exit(fn -> Application.delete_env(:world, :catalog) end)
    kit = ["--kit", Path.join(@dir, "kit")]
    Mix.Tasks.World.Build.run(["--dir", @dir, "--part", "2/2"] ++ kit)
    # Part 2 of 2: the second model only (fixture_seat), with no list.
    assert File.ls!(@dir) |> Enum.sort() ==
             ~w(fixture_seat.far.glb fixture_seat.glb fixture_seat.mid.glb fixture_seat.parts.json)

    Mix.Tasks.World.Build.run(["--dir", @dir, "--part", "1/2", "--jobs", "1"] ++ kit)
    assert "list.json" in File.ls!(@dir) and length(File.ls!(@dir)) == 14

    for part <- ~w(1/2 2/2) do
      Mix.Tasks.World.Build.run(["--dir", @dir, "--check", "--part", part] ++ kit)
    end

    assert_received {:mix_shell, :info, ["The 10 files are the same as the build."]}
    assert_received {:mix_shell, :info, ["The 4 files are the same as the build."]}

    # The files of a model that is not in the catalog: part 1 finds them.
    File.write!(Path.join(@dir, "gone.mid.glb"), "x")

    assert_raise Mix.Error, ~r/of no model of the catalog: .*gone.mid.glb/, fn ->
      Mix.Tasks.World.Build.run(["--dir", @dir, "--check", "--part", "1/2"] ++ kit)
    end

    Mix.Tasks.World.Build.run(["--dir", @dir, "--check", "--part", "2/2"] ++ kit)

    for wrong <- ~w(3/2 0/2 2 a/b) do
      assert_raise Mix.Error, ~r/The part is I\/N/, fn ->
        Mix.Tasks.World.Build.run(["--dir", @dir, "--part", wrong])
      end
    end
  end

  test "the catalog gives the function of a model by its name" do
    names = Enum.map(World.Catalog.models(), &elem(&1, 0))
    assert names == Enum.sort(names) and names == Enum.uniq(names)
    assert {:ok, fun} = World.Catalog.fetch("wheel_bicycle_37_622")
    assert is_function(fun, 0) and World.Catalog.fetch("nope") == :error
  end
end
