defmodule World.Stock do
  @moduledoc """
  The stock of a warehouse: each item by its name, with its count and the
  bytes of one item (the size of its files). The `limit` is the size of
  the warehouse, in bytes: the limit of its store (`docs/world.md`, "What
  is real"). The stock is never less than zero, and never more than the
  limit.
  """

  defstruct limit: 0, items: %{}

  @doc "An empty stock with a limit in bytes."
  def new(limit) when is_integer(limit) and limit >= 0, do: %__MODULE__{limit: limit}

  @doc "The bytes in the stock."
  def used(%__MODULE__{items: items}), do: items |> Map.values() |> Enum.map(fn {n, b} -> n * b end) |> Enum.sum()

  @doc "The bytes that the stock can still take."
  def free(%__MODULE__{limit: limit} = s), do: limit - used(s)

  @doc "The count of an item in the stock."
  def count(%__MODULE__{items: items}, name), do: items |> Map.get(name, {0, 0}) |> elem(0)

  @doc """
  Put `count` items of `bytes` each. A warehouse that is too full
  refuses all of them: `{:error, :full}`. The items of one name have one
  size: an item of the same name with another size is refused,
  `{:error, :other_size}`.
  """
  def put(%__MODULE__{items: items} = s, name, count, bytes)
      when is_integer(count) and count > 0 and is_integer(bytes) and bytes >= 0 do
    {n, b} = Map.get(items, name, {0, bytes})

    cond do
      b != bytes -> {:error, :other_size}
      count * bytes > free(s) -> {:error, :full}
      true -> {:ok, %{s | items: Map.put(items, name, {n + count, bytes})}}
    end
  end

  @doc "Take `count` items. With less in the stock: `{:error, :missing}`."
  def take(%__MODULE__{items: items} = s, name, count) when is_integer(count) and count > 0 do
    case Map.get(items, name) do
      {n, b} when n > count -> {:ok, %{s | items: Map.put(items, name, {n - count, b})}}
      {^count, _} -> {:ok, %{s | items: Map.delete(items, name)}}
      _ -> {:error, :missing}
    end
  end
end
