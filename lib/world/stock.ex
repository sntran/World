defmodule World.Stock do
  @moduledoc """
  The stock of the warehouse (plan 0002, D6): each material by its name,
  with its count in its unit and the mass of one unit (`priv/places.json`).
  The count is never less than zero: a take of more than the stock takes
  nothing, and gives what is short. The suppliers bring the rest
  (`World.Haul`).
  """

  defstruct items: %{}

  @doc "The stock of the yard at the start: the counts of `priv/places.json`."
  def new, do: new(World.Places.data()["stock"])

  @doc "A stock of the given materials: a map of a name to `%{\"count\", \"unit\", \"kg\"}`."
  def new(items), do: %__MODULE__{items: items}

  @doc "The count of a material, 0 for a material that the stock does not have."
  def count(%__MODULE__{items: items}, name), do: get_in(items, [name, "count"]) || 0

  @doc """
  Take the materials of a takeoff (a map of a name to a count): `{:ok,
  stock}`, or `{:short, wants}` with the count that is short of each
  material that the stock does not have enough of.
  """
  def take(%__MODULE__{} = stock, wants) do
    short = for {name, n} <- wants, n > count(stock, name), into: %{}, do: {name, n - count(stock, name)}

    if short == %{},
      do: {:ok, Enum.reduce(wants, stock, fn {name, n}, s -> add(s, name, -n) end)},
      else: {:short, short}
  end

  @doc "Put materials into the stock (a delivery of a supplier)."
  def put(%__MODULE__{} = stock, wants), do: Enum.reduce(wants, stock, fn {name, n}, s -> add(s, name, n) end)

  defp add(%__MODULE__{items: items} = s, name, n) do
    item = Map.get(items, name, %{"count" => 0, "unit" => "", "kg" => 0.0})
    %{s | items: Map.put(items, name, Map.update!(item, "count", &(&1 + n)))}
  end

  @doc "The mass in kg of a takeoff."
  def mass(%__MODULE__{items: items}, wants),
    do: Enum.sum(for({name, n} <- wants, do: n * get_in(items, [name, "kg"]))) / 1

  @doc """
  The loads of a takeoff for trucks of `load_kg`: each a map of a name to
  a count, each at most `load_kg` (one unit heavier than a load is a load
  of its own), in the order of the names.
  """
  def loads(%__MODULE__{items: items}, wants, load_kg) do
    units = for {name, n} <- Enum.sort(wants), _ <- 1..ceil(n)//1, do: {name, items[name]["kg"]}

    units
    |> Enum.chunk_while(
      {%{}, 0.0},
      fn {name, kg}, {load, mass} ->
        if mass > 0 and mass + kg > load_kg,
          do: {:cont, load, {%{name => 1}, kg}},
          else: {:cont, {Map.update(load, name, 1, &(&1 + 1)), mass + kg}}
      end,
      fn
        {load, _} when load == %{} -> {:cont, {%{}, 0.0}}
        {load, _} -> {:cont, load, {%{}, 0.0}}
      end
    )
  end
end
