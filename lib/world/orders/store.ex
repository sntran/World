defmodule World.Orders.Store do
  @moduledoc """
  The store of the full orders (`orders/HASH.json`), so that
  `/o/HASH.glb` can build the files of an order later: a port program
  with the code of `order_store.js`.

  - At the edge, the program is the binding `ORDER_STORE` of the object
    of the VM (`/env/ORDER_STORE`, BEAM.com "Ports to bindings"), with
    the R2 bucket `ORDERS`. `wrangler.jsonc` gives its path in
    `WORLD_ORDER_STORE`.
  - On this computer and in the tests, the program is
    `scripts/order-store.mjs`, with a folder in place of the bucket
    (`WORLD_ORDER_DIR`, `tmp/orders` by default).

  The keys `program`, `dir` and `timeout` of the application environment
  of `:world` for this module come before these defaults.
  """

  @script Path.expand("../../../scripts/order-store.mjs", __DIR__)

  @doc "The key of the full order of a hash."
  def key(hash), do: "orders/#{hash}.json"

  @doc """
  The key of a proposal of a new drawing of a hash (`World.Engineers`):
  the owner reviews it.
  """
  def proposal(hash), do: "proposals/#{hash}.json"

  @doc "Puts the full order (its JSON) of a hash in the store."
  @spec put(String.t(), binary()) :: :ok | :error
  def put(hash, json), do: put_key(key(hash), json)

  @doc "Puts a JSON text in the store at a key."
  @spec put_key(String.t(), binary()) :: :ok | :error
  def put_key(key, json) when byte_size(json) > 0 do
    case run(["put", key, "#{byte_size(json)}"], json) do
      {:ok, "ok\n"} -> :ok
      _ -> :error
    end
  end

  @doc """
  The full order (its JSON) of a hash: `:none` when the store has no
  order of the hash, `:error` when the store failed.
  """
  @spec get(String.t()) :: {:ok, binary()} | :none | :error
  def get(hash), do: get_key(key(hash))

  @doc "The JSON text at a key: `:none` when the store has none, `:error` when the store failed."
  @spec get_key(String.t()) :: {:ok, binary()} | :none | :error
  def get_key(key) do
    case run(["get", key], "") do
      {:ok, ""} -> :none
      other -> other
    end
  end

  defp run(args, input),
    do: World.Program.run(config(:program), args, input, [{"WORLD_ORDER_DIR", config(:dir)}], config(:timeout))

  defp config(key), do: Keyword.get(Application.get_env(:world, __MODULE__, []), key, default(key))

  defp default(:program), do: System.get_env("WORLD_ORDER_STORE", @script)
  defp default(:dir), do: System.get_env("WORLD_ORDER_DIR", "tmp/orders")
  defp default(:timeout), do: 30_000
end
