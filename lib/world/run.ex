defmodule World.Run do
  @moduledoc """
  A run of the world (`docs/world.md`, step W2): one order through the
  places and the people of a yard. The yard has one warehouse, one truck
  with its driver on the road to one factory, a supplier, and the site of
  the customer. The people are processes: a storekeeper, a driver, a
  foreman, and the workers of the factory. Each act is an event of the
  log, at its real time.
  """
  alias World.{Clock, Places, Yard}
  alias World.Log.Server
  alias World.People.{Driver, Foreman, Person, Storekeeper, Worker}
  alias World.Vehicles.Vehicle

  @workers ["dung", "em"]

  @doc """
  The yard of the run. The options: `limit` (the bytes of the warehouse,
  1 GB by default), `capacity` (the items on the truck, 20 by default),
  `workers` (their names), `clock`.
  """
  def yard(opts \\ []) do
    Yard.new(clock: Keyword.get_lazy(opts, :clock, &Clock.new/0))
    |> Yard.add(Places.warehouse("warehouse", {0, 0}, Keyword.get(opts, :limit, 1_000_000_000)))
    |> Yard.add(Places.factory("vehicles", {300, 400}, :vehicles))
    |> Yard.add(Places.supplier("supplier", {-200, 0}))
    |> Yard.add(Places.site("customer", {300, 900}))
    |> Yard.road("warehouse", "vehicles")
    |> Yard.road("vehicles", "customer")
    |> Yard.add(Person.new("an", :storekeeper, "warehouse"))
    |> Yard.add(Person.new("binh", :driver, "warehouse"))
    |> Yard.add(Person.new("chi", :foreman, "vehicles"))
    |> add_workers(Keyword.get(opts, :workers, @workers))
    |> Yard.add(
      Vehicle.new("truck", "ford_transit_148_camper",
        capacity: Keyword.get(opts, :capacity, 20),
        place: "warehouse",
        driver: "binh"
      )
    )
  end

  defp add_workers(yard, names),
    do: Enum.reduce(names, yard, &Yard.add(&2, Person.new(&1, :worker, "vehicles", station: nil, figure: "man")))

  defstruct yard: nil, log: nil, storekeeper: nil, driver: nil, foreman: nil, workers: %{}

  @doc """
  Start the people of a yard (`yard/1`) as processes, with the log of
  the run. The stock of the warehouse stays between the orders.
  """
  def start(yard \\ yard()) do
    {:ok, log} = Server.start_link(yard.clock, Yard.describe(yard))
    {:ok, sk} = Storekeeper.start_link(name: "an", place: "warehouse", stock: yard.places["warehouse"].stock, log: log)
    {:ok, driver} = Driver.start_link(name: "binh", vehicle: "truck", yard: yard, log: log)

    workers =
      for {name, %Person{job: :worker}} <- yard.people, into: %{} do
        {:ok, pid} = Worker.start_link(name: name, place: "vehicles", log: log)
        {name, pid}
      end

    {:ok, foreman} =
      Foreman.start_link(
        name: "chi",
        place: "vehicles",
        warehouse: "warehouse",
        site: "customer",
        supplier: "supplier",
        storekeeper: sk,
        driver: driver,
        workers: workers,
        log: log
      )

    %__MODULE__{yard: yard, log: log, storekeeper: sk, driver: driver, foreman: foreman, workers: workers}
  end

  @doc """
  Run an order of an item (or of a function that makes the item: the
  foreman calls it), and wait for its delivery: `{:ok, result}`
  (`from: :factory` with the plan, the bytes of each part and of the
  model, and its files; or `from: :stock`), or `{:error, reason}`. The
  option `files` is the function that makes the files of the model from
  the item (the GLB at near by default): an order with a level, a pose
  and colors gives its own.
  """
  def order(%__MODULE__{foreman: foreman}, item, order \\ nil, opts \\ []),
    do:
      Foreman.order(
        foreman,
        order || "order-#{System.unique_integer([:positive])}",
        item,
        Keyword.get(opts, :files, &Foreman.files/1)
      )

  @doc "The log of the run (`World.Log`)."
  def log(%__MODULE__{log: log}), do: Server.log(log)

  @doc "Stop the people of the run."
  def stop(%__MODULE__{} = run) do
    for pid <- [run.foreman, run.driver, run.storekeeper, run.log | Map.values(run.workers)], do: GenServer.stop(pid)
    :ok
  end
end
