defmodule World.Sculpt.Cache do
  @moduledoc """
  The cache of the bricks of the sculptures of the node
  (`docs/plans/0008-model-from-edits.md`, D6): a table (ETS) from the key
  of a brick to its piece of the surface.

  The key of a brick is a hash of its place, the size of its cells and
  its short list of edits (`key/3`). Two bricks with the same key have
  the same field, so the same piece: the brick of the next build of the
  same sculpture, of a sculpture after a change of one edit (the bricks
  that the edit does not reach keep their short lists), or of the
  sculpture of another user. The processes of the bricks read and write
  the table at the same time, with no message to this process; this
  process only owns the table.

  The table has a limit of memory (`:world, World.Sculpt.Cache, bytes:`,
  32 MB by default, for the edge of 128 MB). A write that goes past the
  limit empties the table first.
  """

  use GenServer

  @table __MODULE__
  @bytes 32 * 1024 * 1024

  @doc false
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The key of the brick `at` with cells of `step` m and its edits."
  def key(at, step, edits), do: :crypto.hash(:sha256, :erlang.term_to_binary({at, step / 1, edits}))

  @doc "The piece of the brick of a key, or nil (also with no table)."
  def get(key) do
    case :ets.whereis(@table) do
      :undefined ->
        nil

      table ->
        case :ets.lookup(table, key) do
          [{^key, piece}] -> piece
          [] -> nil
        end
    end
  end

  @doc "Keep the piece of the brick of a key (nothing with no table)."
  def put(key, piece) do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      table ->
        if :ets.info(table, :memory) * :erlang.system_info(:wordsize) > limit(), do: :ets.delete_all_objects(table)
        :ets.insert(table, {key, piece})
        :ok
    end
  end

  @doc "Empty the table."
  def clear, do: :ets.delete_all_objects(@table)

  @doc "The count of the bricks in the table."
  def size, do: :ets.info(@table, :size)

  defp limit, do: Application.get_env(:world, __MODULE__, []) |> Keyword.get(:bytes, @bytes)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])
    {:ok, nil}
  end
end
