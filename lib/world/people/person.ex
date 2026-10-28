defmodule World.People.Person do
  @moduledoc """
  A person of the world (`docs/world.md`, "The people"): a name, a job, a
  place, and the station of a worker. Its body is a person of the
  catalog (`figure`: `"man"`, `"woman"`). A person walks at 1.4 m/s.

  The jobs: `:storekeeper` (the stock of a warehouse), `:driver` (a
  vehicle on a road), `:worker` (the tasks of one station of a line) and
  `:foreman` (the plan of an order, and a task for each free person).
  """

  @jobs [:storekeeper, :driver, :worker, :foreman]
  # The speed of a walk, in meters for each second of the world.
  @speed 1.4

  defstruct name: nil, job: nil, place: nil, station: nil, figure: "man"

  @doc "The jobs of a person."
  def jobs, do: @jobs

  @doc "The speed of a walk, in meters for each world second."
  def speed, do: @speed

  @doc "A person with a job at a place. The options: `station`, `figure`."
  def new(name, job, place, opts \\ []) do
    unless job in @jobs, do: raise(ArgumentError, "no job #{inspect(job)}")
    struct!(__MODULE__, [name: name, job: job, place: place] ++ opts)
  end

  @doc "The world time of a walk of `meters`, in milliseconds."
  def walk(meters) when meters >= 0, do: round(meters / @speed * 1000)
end
