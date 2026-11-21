# The rebuild of the check of the bucket (docs/factory.md, "The check of
# the bucket"), in a checkout of one commit of World:
#
#   WORLD_ORDER_DIR=STORE MIX_ENV=prod mix.com run PATH/bucket-rebuild.exs TASKS OUT
#
# STORE is a folder store (scripts/order-store.mjs) with the orders, the
# blueprints in data, and the recipes of before the window, and no part.
# TASKS (JSON) has:
#
# - "files": [{"key", "hash", "level", "file"}]: the file of an order at
#   a level (builds/COMMIT/HASH.LEVEL.FILE) goes to OUT/KEY.
# - "lists": [{"hash", "level"}]: the parts list of an order at a level.
#   It puts its parts and the recipes of its parts into STORE.
# - "parts": [KEY]: each part with a recipe in STORE and no GLB there is
#   built from its recipe (World.Elements.part/1), WORLD_CHECK_WIDTH (2)
#   parts at the same time.
# - "hashes": [KEY]: an order or a blueprint in data (orders/HASH.json,
#   blueprints/HASH.json) whose content gives its hash (World.Orders.hash/1)
#   and its bytes again.
#
# Then each part and recipe of STORE goes to OUT/parts/, the result of the
# hashes to OUT/hashes.json, and each error or time out of a task to
# OUT/errors.json. The script goes on after an error.
[tasks_path, out] = System.argv()
tasks = JSON.decode!(File.read!(tasks_path))
store = System.fetch_env!("WORLD_ORDER_DIR")
limit = String.to_integer(System.get_env("WORLD_CHECK_MINUTES", "20")) * 60_000

defmodule BucketRebuild do
  # A task in a process of its own, for at most `limit` ms: {:ok, value} or {:error, text}.
  def run(limit, fun) do
    task =
      Task.async(fn ->
        try do
          {:ok, fun.()}
        rescue
          e -> {:error, Exception.message(e)}
        catch
          kind, value -> {:error, "#{kind} #{inspect(value)}"}
        end
      end)

    case Task.yield(task, limit) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, "no end after #{div(limit, 60_000)} minutes"}
    end
  end

  def order(store, hash), do: JSON.decode!(File.read!(Path.join(store, "orders/#{hash}.json")))

  def timed(label, fun) do
    t0 = System.monotonic_time(:millisecond)
    result = fun.()
    IO.puts("#{label}: #{System.monotonic_time(:millisecond) - t0} ms")
    result
  end
end

{:ok, errors} = Agent.start_link(fn -> %{} end)
note = fn what, text -> Agent.update(errors, &Map.put(&1, what, text)) end

for %{"key" => key, "hash" => hash, "level" => level, "file" => file} <- tasks["files"] || [] do
  BucketRebuild.timed("file #{key}", fn ->
    case BucketRebuild.run(limit, fn -> World.Orders.build(BucketRebuild.order(store, hash), level, file) end) do
      {:ok, {:ok, bytes}} ->
        path = Path.join(out, key)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, bytes)

      {:ok, {:error, e}} ->
        note.(key, inspect(e))

      {:error, e} ->
        note.(key, e)
    end
  end)
end

for %{"hash" => hash, "level" => level} <- tasks["lists"] || [] do
  BucketRebuild.timed("list #{hash} #{level}", fn ->
    case BucketRebuild.run(limit, fn -> World.Orders.build(BucketRebuild.order(store, hash), level, "elements") end) do
      {:ok, {:ok, _}} -> :ok
      {:ok, {:error, e}} -> note.("list #{hash} #{level}", inspect(e))
      {:error, e} -> note.("list #{hash} #{level}", e)
    end
  end)
end

parts = Path.join(store, "parts")
File.mkdir_p!(parts)

# (The parts at the same time: WORLD_CHECK_WIDTH of them, 2 by default.)
width = String.to_integer(System.get_env("WORLD_CHECK_WIDTH", "2"))

(tasks["parts"] || [])
|> Enum.uniq()
|> Enum.filter(&(not File.exists?(Path.join(parts, "#{&1}.glb")) and File.exists?(Path.join(parts, "#{&1}.json"))))
|> Task.async_stream(
  fn key ->
    BucketRebuild.timed("part #{key}", fn ->
      case BucketRebuild.run(limit, fn -> World.Elements.part(key) end) do
        {:ok, {:ok, _}} -> :ok
        {:ok, other} -> note.("parts/#{key}.glb", inspect(other))
        {:error, e} -> note.("parts/#{key}.glb", e)
      end
    end)
  end,
  max_concurrency: width,
  timeout: :infinity,
  ordered: false
)
|> Stream.run()

hashes =
  Map.new(tasks["hashes"] || [], fn key ->
    bytes = File.read!(Path.join(store, key))
    [_, hash] = Regex.run(~r"/([0-9a-f]{32})\.json$", key)

    agrees =
      case JSON.decode(bytes) do
        {:ok, data} -> World.Orders.hash(data) == hash and World.Orders.encode(data) == bytes
        _ -> false
      end

    {key, agrees}
  end)

File.mkdir_p!(Path.join(out, "parts"))
for name <- File.ls!(parts), do: File.cp!(Path.join(parts, name), Path.join([out, "parts", name]))
File.write!(Path.join(out, "hashes.json"), JSON.encode!(hashes))
File.write!(Path.join(out, "errors.json"), JSON.encode!(Agent.get(errors, & &1)))
