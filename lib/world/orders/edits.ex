defmodule World.Orders.Edits do
  @moduledoc """
  The edits of an order (`docs/factory.md`, "An edit of an order"): a
  project asks for a model, looks at the files that World made, and
  sends small changes to the order. World makes the changes on the full
  order (each option with its default), checks the new order as each
  order, keeps it, and keeps its history. So a project does not send a
  full request again, and World does not have a rule for each fault
  that a project can find: the project says what to change.

  An edit is one of:

  - `{"set": PATH, "to": VALUE}`: the value at the path. In an object, a
    new key is possible. In a list, the index of the count of its items
    adds the value at the end.
  - `{"remove": PATH}`: no key of an object, or no item of a list, at the
    path.
  - `{"insert": PATH, "value": VALUE}`: a new item of a list before the
    item at the path.

  A path is the path of an error of a check: the keys from the order
  down, with a point between them (`options.height`, `colors.paint`,
  `options.drawing.nodes.0.skill.sculpt.edits.3.size`). An item of a
  list is its index (from 0), or its name when the items have names
  (`options.drawing.nodes.roof`).
  """
  alias World.Orders
  alias World.Orders.Store

  @doc "The key of the history of the order of a hash in the store."
  def key(hash), do: "history/#{hash}.json"

  @doc """
  The order after the edits, in their order: `{:ok, order}`, or
  `{:error, errors}` with the path of the edit that is not possible
  (`edits.2`). The order is not checked here.
  """
  def change(order, [_ | _] = edits) do
    edits
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, order}, fn {edit, i}, {:ok, order} ->
      case one(order, edit) do
        {:ok, order} -> {:cont, {:ok, order}}
        {:error, message} -> {:halt, {:error, [%{"path" => "edits.#{i}", "message" => message}]}}
      end
    end)
  end

  def change(_order, _edits), do: {:error, [%{"path" => "edits", "message" => "must be a list of one edit or more"}]}

  defp one(order, %{"set" => path, "to" => value} = edit) when is_binary(path) and map_size(edit) == 2,
    do: walk(order, String.split(path, "."), {:set, value}, path)

  defp one(order, %{"remove" => path} = edit) when is_binary(path) and map_size(edit) == 1,
    do: walk(order, String.split(path, "."), :remove, path)

  defp one(order, %{"insert" => path, "value" => value} = edit) when is_binary(path) and map_size(edit) == 2,
    do: walk(order, String.split(path, "."), {:insert, value}, path)

  defp one(_order, _edit),
    do: {:error, ~s(must be {"set": PATH, "to": VALUE}, {"remove": PATH} or {"insert": PATH, "value": VALUE})}

  # The change at the end of a path, and each value on the way with its new part.
  defp walk(map, [key], {:set, value}, _path) when is_map(map), do: {:ok, Map.put(map, key, value)}

  defp walk(map, [key], :remove, path) when is_map(map) do
    if is_map_key(map, key), do: {:ok, Map.delete(map, key)}, else: {:error, "#{path}: there is no #{key} to remove"}
  end

  defp walk(map, [_key], {:insert, _}, path) when is_map(map),
    do: {:error, "#{path}: an insert is for an item of a list"}

  defp walk(list, [key], op, path) when is_list(list) do
    case {op, index(list, key)} do
      {{:set, value}, i} when is_integer(i) and i < length(list) -> {:ok, List.replace_at(list, i, value)}
      {{:set, value}, i} when i == length(list) -> {:ok, list ++ [value]}
      {:remove, i} when is_integer(i) and i < length(list) -> {:ok, List.delete_at(list, i)}
      {{:insert, value}, i} when is_integer(i) -> {:ok, List.insert_at(list, i, value)}
      _ -> {:error, "#{path}: the list has no item #{key} (it has #{length(list)} items)"}
    end
  end

  defp walk(map, [key | rest], op, path) when is_map(map) do
    case map do
      %{^key => child} -> with {:ok, new} <- walk(child, rest, op, path), do: {:ok, Map.put(map, key, new)}
      _ -> {:error, "#{path}: there is no #{key} (the keys there: #{Enum.join(Enum.sort(Map.keys(map)), ", ")})"}
    end
  end

  defp walk(list, [key | rest], op, path) when is_list(list) do
    case index(list, key) do
      i when is_integer(i) and i < length(list) ->
        with {:ok, new} <- walk(Enum.at(list, i), rest, op, path), do: {:ok, List.replace_at(list, i, new)}

      _ ->
        {:error, "#{path}: the list has no item #{key} (it has #{length(list)} items)"}
    end
  end

  defp walk(_value, [key | _], _op, path), do: {:error, "#{path}: the value before #{key} is not an object or a list"}

  # The index of an item of a list: a whole number from 0 to the count of the items, or the name of an item.
  defp index(list, key) do
    case Integer.parse(key) do
      {i, ""} when i >= 0 and i <= length(list) -> i
      _ -> Enum.find_index(list, &(is_map(&1) and &1["name"] == key))
    end
  end

  @doc """
  The edits on the order of a hash of the store (`POST
  /orders/HASH/edits`, the MCP tool `edit_order`): the new order is
  checked and kept as `World.Orders.place/2` does. Gives `{:ok, placed}`
  with the keys of a placed order, `"parent"` (the hash of the order
  before) and `"history"` (each order from the first one to this one:
  its hash, and the edits that made it); `{:error, errors}` (a hash that
  the store does not have has the path `order`); or `{:error, :store}`.
  """
  def place(hash, edits, origin) when is_binary(hash) do
    with {:ok, json} <- fetch(hash),
         {:ok, order} <- change(JSON.decode!(json), edits),
         {:ok, placed} <- Orders.place(order, origin) do
      history = history(hash) ++ [%{"hash" => placed["hash"], "edits" => edits}]

      case Store.put_key(key(placed["hash"]), Orders.encode(history)) do
        :ok -> {:ok, Map.merge(placed, %{"parent" => hash, "history" => history})}
        :error -> {:error, :store}
      end
    end
  end

  defp fetch(hash) do
    case hash =~ ~r/^[0-9a-f]{32}$/ && Store.get(hash) do
      {:ok, json} -> {:ok, json}
      :error -> {:error, :store}
      _ -> {:error, [%{"path" => "order", "message" => "the store has no order of this hash: place the order first"}]}
    end
  end

  @doc "The history of the order of a hash: each order from the first one to it. An order with no edits is its own history."
  def history(hash) do
    case Store.get_key(key(hash)) do
      {:ok, json} -> JSON.decode!(json)
      _ -> [%{"hash" => hash}]
    end
  end
end
