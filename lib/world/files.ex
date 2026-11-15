defmodule World.Files do
  @moduledoc """
  The files that the node built, on its disk
  (`docs/plans/0019-world-serves-the-projects.md`, 4.3): a file of an
  order at a level stays after a new start of World and after a deploy.

  A file has the name `HASH.LEVEL.FILE` in the folder of the store (the
  application environment `:files`, from `WORLD_FILES`; `tmp/files` by
  default), with a copy in gzip (`.gz`) and its data (`.meta`): its ETag
  and the version of the code of World that built it (`version/0`).

  A file of an older version is stale: the service gives it at once, and
  builds it again one time (`World.Service`). So a deploy of World costs
  no wait, and a correction of a rule is in the file after the next
  request.
  """

  @doc "The folder of the store."
  def dir, do: Application.get_env(:world, :files, "tmp/files")

  @doc """
  The version of the code of World: a short hash of the code of each of
  its modules. It changes when a module changes.
  """
  def version do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        sums = for m <- Enum.sort(Application.spec(:world, :modules)), do: m.module_info(:md5)
        version = :crypto.hash(:md5, sums) |> Base.encode16(case: :lower) |> binary_part(0, 12)
        :persistent_term.put(__MODULE__, version)
        version

      version ->
        version
    end
  end

  @doc """
  A file of the store: `{:ok, %{body: binary, gzip: binary, etag: text,
  version: text}}`, or `:error` when the store does not have it.
  """
  def get(hash, level, file) do
    path = path(hash, level, file)

    with {:ok, meta} <- File.read(path <> ".meta"),
         {:ok, %{"etag" => etag, "version" => version}} <- JSON.decode(meta),
         {:ok, body} <- File.read(path),
         {:ok, gzip} <- File.read(path <> ".gz") do
      {:ok, %{body: body, gzip: gzip, etag: etag, version: version}}
    else
      _ -> :error
    end
  end

  @doc "Put a file into the store, with the version of the code now. Gives the file as `get/3`."
  def put(hash, level, file, body) when is_binary(body) do
    path = path(hash, level, file)
    File.mkdir_p!(dir())
    entry = %{body: body, gzip: :zlib.gzip(body), etag: etag(body), version: version()}

    # (The data goes last: a file with no data is not in the store.)
    for {ext, bin} <- [
          {"", body},
          {".gz", entry.gzip},
          {".meta", JSON.encode!(%{"etag" => entry.etag, "version" => entry.version})}
        ] do
      File.write!(path <> ext <> ".part", bin)
      File.rename!(path <> ext <> ".part", path <> ext)
    end

    entry
  end

  @doc "True when a file of the store is from the code of World now."
  def fresh?(%{version: version}), do: version == version()

  defp etag(body),
    do: ~s(") <> (:crypto.hash(:sha256, body) |> Base.encode16(case: :lower) |> binary_part(0, 32)) <> ~s(")

  defp path(hash, level, file), do: Path.join(dir(), "#{hash}.#{level}.#{file}")
end
