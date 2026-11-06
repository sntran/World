defmodule World.Orders.Set do
  @moduledoc """
  A set of orders: one list gives a set of variants (Vũng Tàu, W19: 30
  tube houses of 4 m, by seed). The game makes a library from the set,
  and picks one variant by the size of its lot.

  A set is a map (from JSON), one of:

  - `"orders"`: a list of orders (`World.Orders`);
  - `"order"` (an order: the base of each variant), `"count"` (1 to
    #{64}), `"seed"` (an integer: the seed of the set) and `"vary"` (an
    option name to a list of its values): each variant `i` has the
    options of the base, a value of each list of `vary` (the set seed
    and `i` pick it), and the option `seed` (when the blueprint has
    one and the base and `vary` do not give it) `seed * 1000 + i`.

  The same set gives the same orders, so the same files.
  """
  alias World.Orders
  alias World.Orders.Blueprints

  @max 64

  @doc "The most variants in a set."
  def max, do: @max

  @doc """
  The full orders of a set: `{:ok, orders}`, or `{:error, errors}` (each
  with its `"path"` in the set and its `"message"`).
  """
  def check(%{"orders" => orders}) when is_list(orders) and orders != [] and length(orders) <= @max do
    orders
    |> Enum.with_index()
    |> Enum.map(fn {o, i} -> {i, Orders.check(o)} end)
    |> collect("orders")
  end

  def check(%{"orders" => _}), do: error("orders", "must be a list of 1 to #{@max} orders")

  def check(%{"order" => base} = set) when is_map(base) do
    count = Map.get(set, "count", 1)
    seed = Map.get(set, "seed", 1)
    vary = Map.get(set, "vary", %{})

    cond do
      not (is_integer(count) and count in 1..@max) ->
        error("count", "must be an integer from 1 to #{@max}")

      not is_integer(seed) ->
        error("seed", "must be an integer")

      not (is_map(vary) and Enum.all?(vary, fn {_, v} -> is_list(v) and v != [] end)) ->
        error("vary", "must map each option to a list of its values")

      true ->
        0..(count - 1) |> Enum.map(&{&1, Orders.check(variant(base, seed, vary, &1))}) |> collect("variants")
    end
  end

  def check(_set), do: error("", "must have \"orders\", or \"order\" with \"count\", \"seed\" and \"vary\"")

  # The order of the variant `i`: the base, a value of each list of
  # `vary`, and a seed of its own.
  defp variant(base, seed, vary, i) do
    options = Map.get(base, "options", %{})

    picked =
      for {key, values} <- Enum.sort(vary), into: %{} do
        <<n::unsigned-32, _::binary>> = :crypto.hash(:sha256, "#{seed}/#{i}/#{key}")
        {key, Enum.at(values, rem(n, length(values)))}
      end

    options = Map.merge(options, picked)

    options =
      if seeded?(base) and not Map.has_key?(options, "seed"),
        do: Map.put(options, "seed", seed * 1000 + i),
        else: options

    Map.put(base, "options", options)
  end

  defp seeded?(%{"blueprint" => name}) do
    case Blueprints.fetch(name) do
      {:ok, b} -> Enum.any?(b.options, &(&1.name == "seed"))
      :error -> false
    end
  end

  defp seeded?(_), do: false

  defp collect(results, prefix) do
    case for {i, {:error, errors}} <- results, e <- errors, do: %{e | "path" => join("#{prefix}.#{i}", e["path"])} do
      [] -> {:ok, for({_, {:ok, full}} <- results, do: full)}
      errors -> {:error, errors}
    end
  end

  defp join(a, ""), do: a
  defp join(a, b), do: a <> "." <> b

  defp error(path, message), do: {:error, [%{"path" => path, "message" => message}]}

  @doc """
  Place each order of a set (`World.Orders.place/2`). Gives `{:ok,
  %{"set", "variants"}}`: the hash of the set (of the hashes of its
  orders, in their order), and for each variant its hash, its full
  order, the URLs of its files, and `lot` (`width` and `depth`, when its
  options have them: a house on a lot), so that the game picks a variant
  by the size of a lot. Else `{:error, errors}`, or `{:error, :store}`.
  """
  def place(set, origin) do
    with {:ok, orders} <- check(set) do
      placed = orders |> Enum.with_index() |> Enum.map(fn {o, i} -> {i, Orders.place(o, origin)} end)

      cond do
        Enum.any?(placed, &match?({_, {:error, :store}}, &1)) ->
          {:error, :store}

        Enum.any?(placed, &match?({_, {:error, _}}, &1)) ->
          collect(placed, "variants")

        true ->
          variants =
            for {_, {:ok, p}} <- placed, do: Map.merge(Map.take(p, ["hash", "order", "files"]), lot(p["order"]))

          hash = Orders.hash(%{"set" => Enum.map(variants, & &1["hash"])})
          {:ok, %{"set" => hash, "variants" => variants}}
      end
    end
  end

  defp lot(%{"options" => %{"width" => w, "depth" => d}}), do: %{"lot" => %{"width" => w, "depth" => d}}
  defp lot(_order), do: %{}
end
