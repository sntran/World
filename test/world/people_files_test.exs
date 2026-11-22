defmodule World.People.FilesTest do
  # (The tests change the application environment of World.People.Files.)
  use ExUnit.Case, async: false

  alias World.People.{Data, Files}

  setup do
    before = Application.get_env(:world, Files)

    on_exit(fn ->
      if before, do: Application.put_env(:world, Files, before), else: Application.delete_env(:world, Files)
    end)

    :ok
  end

  defp path(name), do: Path.join(Data.dir(), name)

  test "from the folder: each file, its parts, and an error for a part out of the file" do
    base = path("base.obj.gz")
    assert Files.read!(base) == File.read!(base)
    assert Files.exists?(base)
    refute Files.exists?(path("clothes/none.swatch.png"))
    assert Files.pread!(path("targets.pack"), [{0, 4}, {4, 0}]) == ["XTP1", ""]
    size = File.stat!(path("targets.pack")).size

    assert_raise ArgumentError, ~r/a part out of the file/, fn ->
      Files.pread!(path("targets.pack"), [{size - 2, 4}])
    end
  end

  test "from the static files of the site, as at the edge: the program gives the same bytes" do
    Application.put_env(:world, Files, local: false)
    base = path("base.obj.gz")
    assert Files.read!(base) == File.read!(base)
    assert Files.exists?(base)
    refute Files.exists?(path("clothes/none.swatch.png"))

    {:ok, file} = :file.open(path("targets.pack"), [:read, :binary, :raw])
    {:ok, a} = :file.pread(file, 0, 12)
    {:ok, b} = :file.pread(file, 1000, 300)
    :file.close(file)
    assert Files.pread!(path("targets.pack"), [{0, 12}, {1000, 300}]) == [a, b]

    # (The data of a person, as a build reads it: the targets and a swatch.)
    assert Data.targets() |> map_size() > 100

    assert_raise ArgumentError, ~r/no file .*none.obj.gz of MakeHuman in the static files/, fn ->
      Files.read!(path("none.obj.gz"))
    end

    assert_raise ArgumentError, ~r/not a file of MakeHuman: \/etc\/hostname/, fn -> Files.read!("/etc/hostname") end
    assert_raise ArgumentError, ~r/no file/, fn -> Files.pread!(path("targets.pack"), [{-1, 2}]) end
  end

  @tag :tmp_dir
  test "a program that gives fewer or more bytes than the parts: an error", %{tmp_dir: dir} do
    program = fn name, bytes ->
      script = Path.join(dir, name)
      File.write!(script, "#!/bin/sh\nprintf '#{bytes}'\n")
      File.chmod!(script, 0o755)
      script
    end

    Application.put_env(:world, Files, local: false, program: program.("short", "abc"))

    assert_raise ArgumentError, ~r/a part out of the file/, fn ->
      Files.pread!(path("targets.pack"), [{0, 2}, {2, 2}])
    end

    Application.put_env(:world, Files, local: false, program: program.("long", "abcdef"))

    assert_raise ArgumentError, ~r/more bytes than the parts/, fn ->
      Files.pread!(path("targets.pack"), [{0, 2}, {2, 2}])
    end

    assert Files.pread!(path("targets.pack"), [{0, 6}]) == ["abcdef"]
  end
end
