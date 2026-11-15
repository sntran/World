defmodule World.FilesTest do
  # The files that the node built, on its disk (plan 0019, 4.3).
  use ExUnit.Case, async: true

  alias World.Files

  defp hash, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  test "a file goes into the store with its copy in gzip, its ETag and the version of the code" do
    hash = hash()
    assert Files.get(hash, "near", "glb") == :error
    body = String.duplicate("glTF a model ", 500)
    entry = Files.put(hash, "near", "glb", body)
    assert Files.get(hash, "near", "glb") == {:ok, entry}
    assert entry.body == body and :zlib.gunzip(entry.gzip) == body and byte_size(entry.gzip) < byte_size(body)
    assert entry.etag =~ ~r/^"[0-9a-f]{32}"$/ and entry.etag == Files.put(hash(), "far", "glb", body).etag
    assert entry.version == Files.version() and Files.version() =~ ~r/^[0-9a-f]{12}$/
    assert Files.fresh?(entry)
    # Each level and each file of an order is a file of its own, in the folder of the store.
    assert Files.get(hash, "mid", "glb") == :error and Files.get(hash, "near", "parts") == :error
    assert File.exists?(Path.join(Files.dir(), "#{hash}.near.glb.gz"))
  end

  test "a file from another version of the code is stale; a file with no data is not in the store" do
    hash = hash()
    Files.put(hash, "far", "parts", "{}")
    meta = Path.join(Files.dir(), "#{hash}.far.parts.meta")
    File.write!(meta, JSON.encode!(%{"etag" => ~s("x"), "version" => "000000000000"}))
    assert {:ok, %{version: "000000000000"} = old} = Files.get(hash, "far", "parts")
    refute Files.fresh?(old)
    # A new put is from the code now.
    assert Files.fresh?(Files.put(hash, "far", "parts", "{}"))
    File.rm!(meta)
    assert Files.get(hash, "far", "parts") == :error
    File.write!(meta, "not JSON")
    assert Files.get(hash, "far", "parts") == :error
  end
end
