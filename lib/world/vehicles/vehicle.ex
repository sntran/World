defmodule World.Vehicles.Vehicle do
  @moduledoc """
  A vehicle of the world (`docs/world.md`, "The words"): a model of the
  catalog that moves parts, its top speed (km/h), the count of items it
  carries, its place, and its driver.
  """

  defstruct name: nil, model: nil, speed: 100, capacity: 1, place: nil, driver: nil

  @doc "A vehicle. The options: `speed` (km/h), `capacity`, `place`, `driver`."
  def new(name, model, opts \\ []) do
    v = struct!(__MODULE__, [name: name, model: model] ++ opts)

    unless is_number(v.speed) and v.speed > 0 and is_integer(v.capacity) and v.capacity > 0,
      do: raise(ArgumentError, "a vehicle has a speed and a capacity more than 0")

    v
  end
end
