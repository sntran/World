defmodule World.Shift.Store do
  @moduledoc """
  The store of the passes of the construction shifts (`World.Shift.Passes`):
  each pass with the name of its node, the cookie of that node and the
  time of its join, through a port program with the code of
  `shift_store.js`. A VM that starts again reads the passes back, so the
  shifts that run connect again.

  - At the edge, the program is the binding `SHIFT_STORE` of the object
    of the VM (`/env/SHIFT_STORE`), on the SQLite of the Durable Object.
    `wrangler.jsonc` gives its path in `WORLD_SHIFT_STORE`.
  - On this computer, the program is `scripts/shift-store.mjs` with a
    file (`WORLD_SHIFT_FILE`) when the application environment gives it.

  With no program, the passes are in the memory of the VM only.
  """

  @doc "The store has a program."
  def on?, do: config(:program) != nil

  @doc "Keep a pass: `:ok` or `:error` (`:ok` with no program)."
  def put(pass, node, cookie, at) do
    if on?() do
      case run(["put", pass, Atom.to_string(node), Atom.to_string(cookie), Integer.to_string(at)]) do
        {:ok, "ok\n"} -> :ok
        _ -> :error
      end
    else
      :ok
    end
  end

  @doc "Forget a pass: `:ok` or `:error` (`:ok` with no program)."
  def drop(pass) do
    if on?() do
      case run(["drop", pass]) do
        {:ok, "ok\n"} -> :ok
        _ -> :error
      end
    else
      :ok
    end
  end

  @doc """
  Each pass that the store keeps: `{:ok, [%{pass, node, cookie, at}]}`
  (none with no program), or `:error`.
  """
  def all do
    if on?() do
      with {:ok, text} <- run(["all"]) do
        rows =
          for line <- String.split(text, "\n", trim: true) do
            [pass, node, cookie, at] = String.split(line, " ")
            %{pass: pass, node: String.to_atom(node), cookie: String.to_atom(cookie), at: String.to_integer(at)}
          end

        {:ok, rows}
      end
    else
      {:ok, []}
    end
  end

  defp run(args),
    do: World.Program.run(config(:program), args, "", [{"WORLD_SHIFT_FILE", config(:file)}], config(:timeout))

  defp config(key), do: Keyword.get(Application.get_env(:world, __MODULE__, []), key, default(key))

  defp default(:program), do: System.get_env("WORLD_SHIFT_STORE")
  defp default(:file), do: System.get_env("WORLD_SHIFT_FILE", "tmp/shift-passes.json")
  defp default(:timeout), do: 30_000
end
