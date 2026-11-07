defmodule World.Application do
  @moduledoc """
  The application: it starts the node (`World.Supervisor`) with the
  environment of the system.
  """
  use Application

  @impl true
  def start(_type, _args), do: World.Supervisor.start_link(System.get_env())
end
