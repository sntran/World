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
  process owns the table and trims it.

  A piece is in the table as a binary (`:erlang.term_to_binary/1`), with
  its size and its generation. The table has a limit of bytes (`:world,
  World.Sculpt.Cache, bytes:`, 32 MB by default, for the edge of
  128 MB), in two generations: a piece that is put or used goes into
  the new generation, and when the new generation has half of the
  limit, the trim takes away the old generation (each piece that no
  build used since the last trim), and a new generation starts. So the
  pieces of the sculptures in work stay.
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
    with table when table != :undefined <- :ets.whereis(@table),
         [{^key, bin, g, _}] <- :ets.lookup(table, key) do
      now = generation()
      if g != now and :ets.update_element(table, key, {3, now}), do: grow(byte_size(bin))
      :erlang.binary_to_term(bin)
    else
      _ -> nil
    end
  end

  @doc "True when the table has the piece of a key (and the piece goes into the new generation)."
  def member?(key) do
    with table when table != :undefined <- :ets.whereis(@table),
         [{^key, _, g, size}] <- :ets.lookup(table, key) do
      now = generation()
      if g != now and :ets.update_element(table, key, {3, now}), do: grow(size)
      true
    else
      _ -> false
    end
  end

  @doc "Keep the piece of the brick of a key (nothing with no table)."
  def put(key, piece) do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      table ->
        bin = :erlang.term_to_binary(piece)
        :ets.insert(table, {key, bin, generation(), byte_size(bin)})
        grow(byte_size(bin))
    end
  end

  @doc "Empty the table."
  def clear, do: GenServer.call(__MODULE__, :clear)

  @doc "The count of the bricks in the table, and the bytes of the new generation."
  def size, do: {:ets.info(@table, :size), :atomics.get(counts(), 1)}

  defp limit, do: Application.get_env(:world, __MODULE__, []) |> Keyword.get(:bytes, @bytes)

  # More bytes in the new generation: a trim at half of the limit.
  defp grow(bytes) do
    if :atomics.add_get(counts(), 1, bytes) > limit() / 2, do: GenServer.cast(__MODULE__, :trim)
    :ok
  end

  # The bytes of the new generation (1) and the generation (2).
  defp counts, do: :persistent_term.get(__MODULE__)
  defp generation, do: :atomics.get(counts(), 2)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])
    :persistent_term.put(__MODULE__, :atomics.new(2, signed: false))
    {:ok, nil}
  end

  @impl true
  def handle_call(:clear, _from, s) do
    :ets.delete_all_objects(@table)
    :atomics.put(counts(), 1, 0)
    {:reply, :ok, s}
  end

  @impl true
  def handle_cast(:trim, s) do
    if :atomics.get(counts(), 1) > limit() / 2 do
      now = generation()
      :ets.select_delete(@table, [{{:_, :_, :"$1", :_}, [{:<, :"$1", now}], [true]}])
      :atomics.put(counts(), 2, now + 1)
      :atomics.put(counts(), 1, 0)
    end

    {:noreply, s}
  end
end
