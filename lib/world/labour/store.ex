defmodule World.Labour.Store do
  @moduledoc """
  The store of the queue of the parts (`World.Labour`): each part that
  waits for a construction shift, with its ticket (its place in the
  queue), and the node of each part in work, through a port program with
  the code of `labour_store.js`. A VM that starts again (a deploy, the
  limit of its memory) reads them back (`World.Labour.restore/1`), so no
  part goes and the order of the queue stays.

  - At the edge, the program is the binding `LABOUR_STORE` of the object
    of the VM (`/env/LABOUR_STORE`), on the SQLite of the Durable Object.
    `wrangler.jsonc` gives its path in `WORLD_LABOUR_STORE`.
  - On this computer, the program is `scripts/labour-store.mjs` with a
    file (`WORLD_LABOUR_FILE`) when the application environment gives it.

  With no program, the queue is in the memory of the VM only.
  """

  @doc "The store has a program."
  def on?, do: config(:program) != nil

  @doc """
  A part that waits: the ticket of the part in the store (the first
  ticket of the key stays), or `ticket` when the store has no program or
  fails.
  """
  def wait(key, ticket) do
    with true <- on?(),
         {:ok, text} <- run(["wait", key, Integer.to_string(ticket)]),
         {stored, "\n"} <- Integer.parse(text) do
      stored
    else
      _ -> ticket
    end
  end

  @doc "The part is in work on `node`: `:ok` or `:error` (`:ok` with no program)."
  def give(key, node), do: ok(["give", key, Atom.to_string(node)])

  @doc "The part waits again, at its place: `:ok` or `:error`."
  def back(key), do: ok(["back", key])

  @doc "The part is built, or failed (its projects go too): `:ok` or `:error`."
  def done(key) do
    if on?(), do: ok(["done", key]), else: memory(&Map.delete(&1, key))
  end

  @doc """
  A project asked for the part (a name of `x-world-project`): `:ok` or
  `:error`. With no program, the projects are in the memory of the VM
  (`World.Labour.Projects`).
  """
  def ask(key, project) do
    if on?() do
      ok(["ask", key, project])
    else
      memory(&Map.update(&1, key, [project], fn list -> if project in list, do: list, else: list ++ [project] end))
    end
  end

  @doc "The projects that asked for the part, in the order of their first request ([] when the store fails)."
  def projects(key) do
    cond do
      not on?() ->
        if Process.whereis(World.Labour.Projects), do: Agent.get(World.Labour.Projects, &Map.get(&1, key, [])), else: []

      match?({:ok, _}, result = run(["projects", key])) ->
        {:ok, text} = result
        String.split(text, "\n", trim: true)

      true ->
        []
    end
  end

  defp memory(fun) do
    if Process.whereis(World.Labour.Projects), do: Agent.update(World.Labour.Projects, fun)
    :ok
  end

  @doc """
  Each part in the store, in the order of the queue: `{:ok, [%{key,
  ticket, node}]}` (`node` nil for a part that waits; none with no
  program), or `:error`.
  """
  def all do
    if on?() do
      with {:ok, text} <- run(["all"]) do
        rows =
          for line <- String.split(text, "\n", trim: true) do
            [key, ticket, node] = String.split(line, " ")
            %{key: key, ticket: String.to_integer(ticket), node: if(node == "-", do: nil, else: String.to_atom(node))}
          end

        {:ok, rows}
      end
    else
      {:ok, []}
    end
  end

  defp ok(args) do
    if on?() do
      case run(args) do
        {:ok, "ok\n"} -> :ok
        _ -> :error
      end
    else
      :ok
    end
  end

  defp run(args),
    do: World.Program.run(config(:program), args, "", [{"WORLD_LABOUR_FILE", config(:file)}], config(:timeout))

  defp config(key), do: Keyword.get(Application.get_env(:world, __MODULE__, []), key, default(key))

  defp default(:program), do: System.get_env("WORLD_LABOUR_STORE")
  defp default(:file), do: System.get_env("WORLD_LABOUR_FILE", "tmp/labour-parts.json")
  defp default(:timeout), do: 30_000
end
