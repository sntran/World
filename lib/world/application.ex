defmodule World.Application do
  @moduledoc """
  The application. With `WORLD_SERVER=true` (the Worker of the factory,
  `wrangler.jsonc`), it starts the HTTP server of `World.Service` on
  `PORT` (4000 by default).
  """
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(children(System.get_env()), strategy: :one_for_one, name: World.Supervisor)
  end

  @doc "The children for the environment `env`: the server, or nothing."
  def children(%{"WORLD_SERVER" => "true"} = env),
    do: [
      {Bandit,
       plug: World.Service,
       port: String.to_integer(Map.get(env, "PORT", "4000")),
       thousand_island_options: [num_acceptors: 1]}
    ]

  def children(_env), do: []
end
