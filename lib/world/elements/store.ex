defmodule World.Elements.Store do
  @moduledoc """
  The store of the parts of the models (`World.Elements`), in the store
  of the orders (`World.Orders.Store`: the R2 bucket `ORDERS` at the
  edge, a folder on a computer): the GLB of a part by its key,
  `parts/KEY.glb`, and the recipe of a part that is not built yet,
  `parts/KEY.json`. A key is a hash of the data of the part, so a part
  in the store does not change, and it stays there.
  """

  alias World.Orders.Store

  @doc "The GLB of a part: `{:ok, glb}`, `:none`, or `:error` when the store failed."
  def get(key), do: Store.get_key(glb(key))

  @doc "Put the GLB of a part into the store."
  def put(key, glb), do: Store.put_key(glb(key), glb)

  @doc "True when the store has the GLB of a part."
  def has?(key), do: Store.has?(glb(key))

  @doc "The recipe of a part (JSON): `{:ok, json}`, `:none` or `:error`."
  def recipe(key), do: Store.get_key(json(key))

  @doc "Put the recipe of a part (JSON) into the store."
  def put_recipe(key, json), do: Store.put_key(json(key), json)

  defp glb(key), do: "parts/#{key}.glb"
  defp json(key), do: "parts/#{key}.json"
end
