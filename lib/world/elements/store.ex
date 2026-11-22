defmodule World.Elements.Store do
  @moduledoc """
  The store of the parts of the models (`World.Elements`), in the store
  of the orders (`World.Orders.Store`: the R2 bucket `ORDERS` at the
  edge, a folder on a computer): the GLB of a part by its key,
  `parts/KEY.glb`, the recipe of a part that is not built yet,
  `parts/KEY.json`, and the mark of a build of the part at the edge,
  `parts/KEY.edge`. A key is a hash of the data of the part, so a part
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

  @doc """
  Mark a part before its build at the edge (`World.Labour`). The mark
  stays: a part with a mark and no GLB is a build at the edge that did
  not end, because its VM ended (or the guard of the memory stopped it).
  `:ok` or `:error`.
  """
  def mark(key), do: Store.put_key(edge(key), "1")

  @doc "True when the store has the mark of a build of the part at the edge (`mark/1`), and not the GLB: a build that did not end."
  def marked?(key), do: Store.has?(edge(key)) and not has?(key)

  defp edge(key), do: "parts/#{key}.edge"
  defp glb(key), do: "parts/#{key}.glb"
  defp json(key), do: "parts/#{key}.json"
end
