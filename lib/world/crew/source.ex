defmodule World.Crew.Source do
  @moduledoc """
  The hash of the source of World (`World.Crew.version/0`): the files of
  the source, each with its path from the root of the project, and the
  versions of Elixir and Erlang/OTP and the environment of Mix.

  The files are `mix.exs`, `mix.lock`, and the files in `lib`, `wings`
  and `priv`, less the files that `mix world.build` writes
  (`priv/models`, `priv/kit`).

  It is not a hash of the compiled modules. The code of some modules has
  the path of the folder of the build (an attribute with `__DIR__`), and
  the compiler gives some names in the order of the compile. So two
  builds of one commit in two folders have modules that are not the
  same: the edge in Workers Builds, and a construction shift on a runner
  of GitHub Actions. The hash of the source is the same for the two.
  """

  # The files that `mix world.build` writes: they are not a part of the source.
  @outputs ~w(priv/models/ priv/kit/)

  @doc "The files of the source under `root`: their paths from `root`, in order."
  def files(root) do
    for pattern <- ~w(mix.exs mix.lock lib/**/* wings/**/* priv/**/*),
        file <- Path.wildcard(Path.join(root, pattern)),
        path = Path.relative_to(file, root),
        not String.starts_with?(path, @outputs),
        File.regular?(file) do
      path
    end
    |> Enum.sort()
  end

  @doc """
  The hash (16 bytes) of the files `paths` under `root` (each path and
  its content), with the versions of Elixir and Erlang/OTP and the
  environment of Mix `env`.
  """
  def hash(root, paths, env) do
    paths
    |> Enum.reduce(:erlang.md5_init(), fn path, md5 ->
      content = File.read!(Path.join(root, path))
      md5 |> :erlang.md5_update(:erlang.term_to_binary({path, byte_size(content)})) |> :erlang.md5_update(content)
    end)
    |> :erlang.md5_update(:erlang.term_to_binary({System.version(), :erlang.system_info(:otp_release), env}))
    |> :erlang.md5_final()
  end
end

defmodule World.Crew.Version do
  @moduledoc """
  The hash of the source of World when this module was compiled
  (`World.Crew.Source`). Mix compiles this module again when a file of
  the source changes, comes or goes.
  """
  alias World.Crew.Source

  @root Path.expand("../../..", __DIR__)
  @paths Source.files(@root)
  for path <- @paths, do: @external_resource(Path.join(@root, path))
  @version Source.hash(@root, @paths, Mix.env())

  @doc "The hash of the source (16 bytes)."
  def get, do: @version

  @doc false
  def __mix_recompile__?, do: Source.files(@root) != @paths
end
