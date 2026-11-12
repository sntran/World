defmodule World.Sculpt.CacheTest do
  # The cache of the bricks of the node (plan 0008, D6; R5). One table for
  # the node, so the tests are not async.
  use ExUnit.Case, async: false

  alias World.{Frame, SDF, Sculpt, Stone}
  alias World.Sculpt.{Cache, Surface}

  setup do
    Cache.clear()
    :ok
  end

  defp build(edits, step), do: Sculpt.bricks(edits, step, each: &Surface.piece(&1, step), cache: true)

  test "the next build of the same sculpture takes each brick from the cache, with the same meshes" do
    edits = Stone.edits(40)
    first = build(edits, 0.04)
    assert first.cached == 0 and Cache.size() == length(first.bricks)
    again = build(edits, 0.04)
    assert again.cached == length(first.bricks) and again.evaluations < first.evaluations / 10
    assert Enum.map(again.bricks, & &1.piece) == Enum.map(first.bricks, & &1.piece)
    assert Sculpt.model(edits, step: 0.04) == Sculpt.model(edits, step: 0.04, cache: false)
  end

  test "after a change of one edit, only the bricks that the old or the new edit reaches are made again (R5)" do
    edits = Stone.edits(100)
    step = 0.02
    before = build(edits, step)
    old = Enum.at(edits, 10)
    new = %{old | frame: Frame.compose(Frame.move({0.0, 0.0, 0.05}), old.frame)}
    new = SDF.edit(:ball, old.size, frame: new.frame, mode: old.mode, blend: old.blend)
    edits = List.replace_at(edits, 10, new)
    after_ = build(edits, step)
    made = for b <- after_.bricks, b.field != nil, do: b.at
    assert made != [] and length(made) < length(after_.bricks) / 8

    # A brick that is made again is near the old or the new edit: in its
    # box, grown by its blend and by the ball of the brick with its border.
    side = Sculpt.cells() * step
    reach = side * :math.sqrt(3) + 2 * step * :math.sqrt(3) + old.blend

    near? = fn at, edit ->
      {{lx, ly, lz}, {hx, hy, hz}} = SDF.bounds([edit])
      {cx, cy, cz} = World.Vec.add(Sculpt.corner(at, step), {side / 2, side / 2, side / 2})
      d = fn c, lo, hi -> max(max(lo - c, c - hi), 0.0) end
      :math.sqrt(d.(cx, lx, hx) ** 2 + d.(cy, ly, hy) ** 2 + d.(cz, lz, hz) ** 2) <= reach
    end

    for at <- made, do: assert(near?.(at, old) or near?.(at, new), inspect(at))
    assert before.cached == 0

    assert Enum.map(after_.bricks, & &1.piece) ==
             Enum.map(Sculpt.bricks(edits, step, each: &Surface.piece(&1, step)).bricks, & &1.piece)
  end

  test "the table empties at its limit of memory, and with no table there is no cache" do
    Application.put_env(:world, Cache, bytes: 200_000)
    on_exit(fn -> Application.delete_env(:world, Cache) end)
    for i <- 1..400, do: Cache.put(Cache.key({i, 0, 0}, 0.02, []), List.duplicate(i, 100))
    assert Cache.size() < 400

    :ok = Supervisor.terminate_child(World.Supervisor, Cache)
    on_exit(fn -> Supervisor.restart_child(World.Supervisor, Cache) end)
    assert Cache.get(Cache.key({0, 0, 0}, 0.02, [])) == nil
    assert Cache.put(Cache.key({0, 0, 0}, 0.02, []), :piece) == :ok
    assert %{cached: 0} = build(Stone.edits(5), 0.1)
  end
end
