defmodule World.Epmd do
  @moduledoc """
  The ports of the Erlang nodes of World, with no port mapper daemon
  (`docs/plans/0012-a-world-of-sites.md`, D8).

  Two Erlang nodes find the port of each other with a small program on
  each machine (`epmd`). The runtime of World is one file with no such
  program. This module takes its place: the port of a node is in its
  name. The digits at the end of the name (before the `@`) are its
  port: `world4371@10.0.0.2` listens on the port 4371. A name with no
  digits has the port 4370.

  Start the VM with `-start_epmd false -epmd_module Elixir.World.Epmd`
  (in `ERL_FLAGS`), then start the node (`WORLD_NODE`,
  `World.Supervisor`). It is a module of node discovery of Erlang
  (`erl_epmd` is the one by default).
  """

  @default 4370

  @doc "The port of a node from its name (the part before the `@`, or the whole name)."
  def port(name) do
    name = name |> to_string() |> String.split("@") |> hd()

    case Regex.run(~r/(\d+)$/, name) do
      [_, digits] -> String.to_integer(digits)
      nil -> @default
    end
  end

  @doc false
  def start_link, do: :ignore

  @doc false
  def register_node(name, port), do: register_node(name, port, :inet)

  # (No daemon keeps the names. The number is the creation of the node: a new one at each start.)
  @doc false
  def register_node(_name, _port, _family), do: {:ok, :rand.uniform(4_294_967_291) + 3}

  @doc false
  def listen_port_please(name, _host), do: {:ok, port(name)}

  @doc false
  def port_please(name, host), do: port_please(name, host, :infinity)

  # (5 is the version of the protocol of the distribution.)
  @doc false
  def port_please(name, _host, _timeout), do: {:port, port(name), 5}

  @doc false
  def address_please(_name, host, family), do: :inet.getaddr(host, family)

  @doc false
  def names(_host), do: {:error, :address}
end
