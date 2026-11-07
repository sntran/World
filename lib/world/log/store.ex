defmodule World.Log.Store do
  @moduledoc """
  The store of the log of the node (`docs/plans/0001-people-build-on-demand.md`,
  D18): each event as one line of JSON with its id, through a port
  program with the code of `log_store.js`.

  - At the edge, the program is the binding `LOG_STORE` of the object of
    the VM (`/env/LOG_STORE`), on the SQLite of the Durable Object.
    `wrangler.jsonc` gives its path in `WORLD_LOG_STORE`.
  - On this computer, the program is `scripts/log-store.mjs` with a file
    (`WORLD_LOG_FILE`) when the application environment gives it.

  With no program (`WORLD_LOG_STORE` not set and no `program` in the
  application environment of `:world` for this module), the node keeps
  its log in its memory only.
  """

  @doc "The store has a program."
  def on?, do: config(:program) != nil

  @doc "Keep the lines of events (each a JSON text with its id): `:ok` or `:error`."
  def append([]), do: :ok

  def append(lines) do
    input = Enum.map_join(lines, &(&1 <> "\n"))

    case run(["append", "#{byte_size(input)}"], input) do
      {:ok, "ok\n"} -> :ok
      _ -> :error
    end
  end

  @doc "The lines of the events after the id `after`, at most `limit`: `{:ok, lines}` or `:error`."
  def read(after_id, limit) do
    with {:ok, text} <- run(["read", "#{after_id}", "#{limit}"], ""), do: {:ok, String.split(text, "\n", trim: true)}
  end

  @doc "The id of the last event in the store (0 for none): `{:ok, id}` or `:error`."
  def last do
    with {:ok, text} <- run(["last"], ""), do: {:ok, text |> String.trim() |> String.to_integer()}
  end

  defp run(args, input),
    do: World.Program.run(config(:program), args, input, [{"WORLD_LOG_FILE", config(:file)}], config(:timeout))

  defp config(key), do: Keyword.get(Application.get_env(:world, __MODULE__, []), key, default(key))

  defp default(:program), do: System.get_env("WORLD_LOG_STORE")
  defp default(:file), do: System.get_env("WORLD_LOG_FILE", "tmp/log.jsonl")
  defp default(:timeout), do: 30_000
end
