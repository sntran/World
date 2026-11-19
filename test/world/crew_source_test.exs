defmodule World.Crew.SourceTest do
  # The hash of the source (World.Crew.version/0): the same for one
  # source in two folders, another one for another source.
  use ExUnit.Case, async: true

  alias World.Crew.{Source, Version}

  # A small source in the folder `root`.
  defp source(root) do
    for {path, content} <- [
          {"mix.exs", "defmodule A.MixProject do end"},
          {"mix.lock", "%{}"},
          {"lib/a.ex", ~s|defmodule A do\n  @root Path.expand("..", __DIR__)\nend|},
          {"wings/e3d/b.erl", "-module(b)."},
          {"priv/blueprints/house.json", "{}"},
          {"priv/models/house.glb", "a build"},
          {"priv/kit/hair.glb", "a build"},
          {"notes.md", "not a part of the source"}
        ] do
      file = Path.join(root, path)
      File.mkdir_p!(Path.dirname(file))
      File.write!(file, content)
    end

    root
  end

  @tag :tmp_dir
  test "the files of the source: their paths from the root, in order, with no files of the build", %{tmp_dir: dir} do
    root = source(Path.join(dir, "one"))
    assert Source.files(root) == ~w(lib/a.ex mix.exs mix.lock priv/blueprints/house.json wings/e3d/b.erl)
  end

  @tag :tmp_dir
  test "one source in two folders has one hash; another file, content or environment has another", %{tmp_dir: dir} do
    one = source(Path.join(dir, "one"))
    two = source(Path.join([dir, "a", "longer", "folder"]))
    hash = Source.hash(one, Source.files(one), :prod)
    assert byte_size(hash) == 16 and Source.hash(two, Source.files(two), :prod) == hash

    # (A file of the build does not count.)
    File.write!(Path.join(two, "priv/models/house.glb"), "another build")
    assert Source.hash(two, Source.files(two), :prod) == hash

    assert Source.hash(one, Source.files(one), :test) != hash
    File.write!(Path.join(two, "lib/a.ex"), "defmodule A do end")
    assert Source.hash(two, Source.files(two), :prod) != hash
    File.write!(Path.join(one, "lib/b.ex"), "defmodule B do end")
    assert Source.hash(one, Source.files(one), :prod) != hash
  end

  test "the version of the crews is the hash of the source of this build, and the source has not changed since" do
    assert World.Crew.version() == Version.get() and byte_size(Version.get()) == 16
    refute Version.__mix_recompile__?()
  end
end
