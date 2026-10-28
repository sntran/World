defmodule Xuong.Application do
  @moduledoc """
  The application. With `XUONG_SERVER=true` (the Worker of the factory,
  `wrangler.jsonc`), it starts the HTTP server of `Xuong.Service` on
  `PORT` (4000 by default).
  """
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(children(System.get_env()), strategy: :one_for_one, name: Xuong.Supervisor)
  end

  @doc "The children for the environment `env`: the server, or nothing."
  def children(%{"XUONG_SERVER" => "true"} = env),
    do: [
      {Bandit,
       plug: Xuong.Service,
       port: String.to_integer(Map.get(env, "PORT", "4000")),
       thousand_island_options: [num_acceptors: 1]}
    ]

  def children(_env), do: []
end
