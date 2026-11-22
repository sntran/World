defmodule World.People.Files do
  @moduledoc """
  The files of MakeHuman (`priv/makehuman`, `World.People.Data`) for a
  build: from the folder when the node has it (a computer, the node of a
  construction shift, the tests), else from the static files of the site
  (`/makehuman/`, `scripts/site.sh`) through a port program.

  - At the edge, the program is the binding `ASSET_STORE` of the object
    of the VM (`/env/ASSET_STORE`, `asset_store.js`), with the binding
    `ASSETS` of the static files. `wrangler.jsonc` gives its path in
    `WORLD_ASSET_STORE`. The release of the edge has no
    `priv/makehuman` (`mix.exs`): those 35 MB were in `edge.com`, a
    module that stays in the isolate of 128 MB next to the memory of the
    VM. Now a build reads only the files that it needs, when it needs
    them.
  - On this computer and in the tests, the program is
    `scripts/asset-store.mjs`, with a folder in place of the static
    files (`WORLD_ASSET_DIR`, the folder of `World.People.Data.dir/0`
    by default).

  Each function takes the path of a file in the folder of
  `World.People.Data.dir/0`. The keys `program`, `dir`, `timeout` and
  `local` (false: the program also when the folder has the file, for a
  test) of the application environment of `:world` for this module come
  before these defaults.
  """

  alias World.People.Data

  @script Path.expand("../../../scripts/asset-store.mjs", __DIR__)

  @doc "The bytes of a file. It raises when its source does not have the file."
  def read!(path), do: if(remote?(), do: remote!(["get", name(path)], path), else: File.read!(path))

  @doc "True when the source has the file."
  def exists?(path), do: if(remote?(), do: remote(["has", name(path)]) == {:ok, "yes\n"}, else: File.regular?(path))

  @doc """
  The bytes at each `{offset, length}` of a file, in their order, with
  one open of the file (or one call of the program). It raises when a
  part is out of the file.
  """
  def pread!(path, ranges) do
    if remote?() do
      args = Enum.flat_map(ranges, fn {at, n} -> [Integer.to_string(at), Integer.to_string(n)] end)
      split(remote!(["range", name(path) | args], path), ranges, path)
    else
      {:ok, file} = :file.open(path, [:read, :binary, :raw])

      try do
        for {at, n} <- ranges, do: part(:file.pread(file, at, n), n, path)
      after
        :file.close(file)
      end
    end
  end

  defp part(_result, 0, _path), do: ""
  defp part({:ok, bytes}, n, _path) when byte_size(bytes) == n, do: bytes
  defp part(_result, _n, path), do: raise(ArgumentError, "a part out of the file #{path}")

  defp split(bytes, ranges, path) do
    {parts, rest} =
      Enum.map_reduce(ranges, bytes, fn {_, n}, rest ->
        case rest do
          <<part::binary-size(^n), more::binary>> -> {part, more}
          _ -> raise ArgumentError, "a part out of the file #{path}"
        end
      end)

    if rest == "", do: parts, else: raise(ArgumentError, "more bytes than the parts of the file #{path}")
  end

  # The program: at the edge (no folder of the data), or for a test.
  defp remote?, do: config(:local) == false or not File.dir?(Data.dir())

  # The path of the file in the folder of the data, for the program.
  defp name(path) do
    full = Path.expand(path)

    case Path.relative_to(full, Path.expand(Data.dir())) do
      ^full -> raise ArgumentError, "not a file of MakeHuman: #{path}"
      name -> name
    end
  end

  defp remote!(args, path) do
    case remote(args) do
      {:ok, bytes} -> bytes
      :error -> raise ArgumentError, "no file #{path} of MakeHuman in the static files of the site"
    end
  end

  defp remote(args),
    do: World.Program.run(config(:program), args, "", [{"WORLD_ASSET_DIR", config(:dir)}], config(:timeout))

  defp config(key), do: Keyword.get(Application.get_env(:world, __MODULE__, []), key, default(key))

  defp default(:program), do: System.get_env("WORLD_ASSET_STORE", @script)
  defp default(:dir), do: System.get_env("WORLD_ASSET_DIR", Data.dir())
  defp default(:timeout), do: 60_000
  defp default(:local), do: true
end
