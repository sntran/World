defmodule Mix.Tasks.Xuong.BuildTest do
  use ExUnit.Case

  @dir Path.join(System.tmp_dir!(), "xuong_build_test")

  setup do
    File.rm_rf!(@dir)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    :ok
  end

  test "writes the files of a model, and --check finds a change" do
    Mix.Tasks.Xuong.Build.run(["--dir", @dir, "wheel_bicycle_37_622"])
    assert_received {:mix_shell, :info, ["Wrote 4 files."]}

    for f <-
          ~w(wheel_bicycle_37_622.glb wheel_bicycle_37_622.mid.glb wheel_bicycle_37_622.far.glb wheel_bicycle_37_622.parts.json),
        do: assert(File.exists?(Path.join(@dir, f)))

    Mix.Tasks.Xuong.Build.run(["--dir", @dir, "--check", "wheel_bicycle_37_622"])
    assert_received {:mix_shell, :info, ["The 4 files are the same as the build."]}

    File.write!(Path.join(@dir, "wheel_bicycle_37_622.glb"), "x")

    assert_raise Mix.Error, ~r/not the same as the build/, fn ->
      Mix.Tasks.Xuong.Build.run(["--dir", @dir, "--check", "wheel_bicycle_37_622"])
    end
  end

  test "an unknown model stops the task" do
    assert_raise Mix.Error, ~r/No model nope/, fn -> Mix.Tasks.Xuong.Build.run(["--dir", @dir, "nope"]) end
  end

  # The build of all the models takes some minutes in the interpreter.
  @tag timeout: :infinity
  test "all the models, with the list" do
    Mix.Tasks.Xuong.Build.run(["--dir", @dir])
    list = File.read!(Path.join(@dir, "list.json")) |> JSON.decode!()
    assert list == Enum.map(Xuong.Catalog.models(), &elem(&1, 0))
    assert Xuong.Catalog.fetch("nope") == :error
  end
end
