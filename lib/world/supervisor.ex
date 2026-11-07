defmodule World.Supervisor do
  @moduledoc """
  The supervisor of the node (`docs/plans/0001-people-build-on-demand.md`,
  D13). It starts the registries of the node, the people, the
  constructions, the census, and the HTTP server of `World.Service` when
  `WORLD_SERVER` is `"true"` (on `PORT`, 4000 by default). It decides
  nothing: `World` and `World.Census` decide.

  - `World.Names`: a construction by its id (unique keys).
  - `World.Events`: the processes that watch a construction, or the whole
    world with the key `:world` (duplicate keys).
  - `World.Persons`: the people (a dynamic supervisor).
  - `World.Constructions`: the constructions (a dynamic supervisor).
  """
  use Supervisor

  @doc "Start the supervisor of the node, for the environment `env`."
  def start_link(env \\ System.get_env()), do: Supervisor.start_link(__MODULE__, env, name: __MODULE__)

  @impl true
  def init(env), do: Supervisor.init(children(env), strategy: :one_for_one)

  @doc "The children for the environment `env`: the node, and the server with `WORLD_SERVER`."
  def children(env) do
    [
      {Registry, keys: :unique, name: World.Names},
      {Registry, keys: :duplicate, name: World.Events},
      {DynamicSupervisor, name: World.Persons, strategy: :one_for_one},
      {DynamicSupervisor, name: World.Constructions, strategy: :one_for_one},
      World.Census
    ] ++ server(env)
  end

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
