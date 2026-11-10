defmodule World.Supervisor do
  @moduledoc """
  The supervisor of the node (`docs/plans/0001-people-build-on-demand.md`,
  D13). It starts the registries of the node, the people, the
  constructions, the census, the haul and the yard (`World.Haul`,
  `World.Yard`: the first start builds the places) when `WORLD_YARD` is
  `"true"`, and the HTTP server of `World.Service` when `WORLD_SERVER` is
  `"true"` (on `PORT`, 4000 by default). It decides nothing: `World`,
  `World.Census` and `World.Yard` decide.

  - `World.Names`: a construction by its id (unique keys).
  - `World.Events`: the processes that watch a construction, or the whole
    world with the key `:world` (duplicate keys, in partitions by key: a
    dispatch reads one partition).
  - `World.Log.Server`: the log of the node, each event with its id.
  - `World.Persons`: the people (a dynamic supervisor).
  - `World.Constructions`: the constructions (a dynamic supervisor).
  """
  use Supervisor

  @doc "Start the supervisor of the node, for the environment `env`."
  def start_link(env \\ System.get_env()), do: Supervisor.start_link(__MODULE__, env, name: __MODULE__)

  @impl true
  def init(env) do
    scale(env)
    Supervisor.init(children(env), strategy: :one_for_one)
  end

  @doc """
  The scale of the clock of the world from `WORLD_SCALE` (world seconds
  in one second of the wall clock, `World.Clock.world/0`), when the
  environment has it.
  """
  def scale(%{"WORLD_SCALE" => text}) do
    {n, ""} = Integer.parse(text)
    Application.put_env(:world, :scale, n)
  end

  def scale(_env), do: :ok

  @doc "The children for the environment `env`: the node, and the server with `WORLD_SERVER`."
  def children(env) do
    [
      {Registry, keys: :unique, name: World.Names},
      {Registry, keys: {:duplicate, :key}, name: World.Events, partitions: System.schedulers_online()},
      World.Log.Server,
      {DynamicSupervisor, name: World.Persons, strategy: :one_for_one},
      {DynamicSupervisor, name: World.Constructions, strategy: :one_for_one},
      World.Census
    ] ++ yard(env) ++ server(env)
  end

  @doc "The haul and the yard for the environment `env`, or nothing."
  def yard(%{"WORLD_YARD" => "true"}), do: [World.Haul, World.Yard]
  def yard(_env), do: []

  @doc "The HTTP server for the environment `env`, or nothing."
  def server(%{"WORLD_SERVER" => "true"} = env),
    do: [
      {Bandit,
       plug: World.Service,
       port: String.to_integer(Map.get(env, "PORT", "4000")),
       thousand_island_options: [num_acceptors: 1]}
    ]

  def server(_env), do: []
end
