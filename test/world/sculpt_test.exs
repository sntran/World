defmodule World.SculptTest do
  # The bricks of a sculpture: a tree of processes finds the cells near
  # its surface (plan 0008, D3 and D5; R2).
  use ExUnit.Case, async: true

  alias World.{SDF, Sculpt, Vec}

  defp stone(n), do: World.Stone.edits(n)

  test "each brick has the field of all the edits at its points, with its border, in the limit of the field" do
    edits = stone(30)
    %{bricks: bricks, step: step} = Sculpt.bricks(edits, 0.05)
    assert bricks != [] and Sculpt.cells() == 8 and Sculpt.points() == 11
    assert Sculpt.limit(edits, 0.05) == 4 * 0.05 + 2 * 0.03

    for b <- bricks, i <- [-1, 0, 4, 8, 9], j <- [-1, 3, 9], k <- [-1, 0, 7, 9] do
      p = Vec.add(Sculpt.corner(b.at, step), {i * step, j * step, k * step})
      # The field is in floats of 32 bits; near the surface it is the field with no limit.
      want = SDF.value(edits, p, b.limit)
      assert_in_delta Sculpt.at(b, {i, j, k}), want, 1.0e-6 * max(1.0, abs(want))
      if abs(want) < 2 * step, do: assert_in_delta(want, SDF.value(edits, p), 1.0e-12)
    end
  end

  test "each cell of the grid that the surface crosses is in a brick" do
    edits = stone(30)
    step = 0.05
    %{bricks: bricks} = Sculpt.bricks(edits, step)
    have = MapSet.new(bricks, & &1.at)
    {{lx, ly, lz}, {hx, hy, hz}} = SDF.bounds(edits)
    range = fn lo, hi -> floor(lo / step)..ceil(hi / step) end
    v = fn i, j, k -> SDF.value(edits, {i * step, j * step, k * step}) end

    for i <- range.(lx, hx), j <- range.(ly, hy), k <- range.(lz, hz) do
      signs = for a <- 0..1, b <- 0..1, c <- 0..1, uniq: true, do: v.(i + a, j + b, k + c) < 0

      if length(signs) == 2 do
        brick = {Integer.floor_div(i, 8), Integer.floor_div(j, 8), Integer.floor_div(k, 8)}
        assert MapSet.member?(have, brick), inspect({i, j, k})
      end
    end
  end

  test "the processes and one process give the same bricks; a sculpture with no edit that adds has none" do
    edits = stone(20)
    assert Sculpt.bricks(edits, 0.05) == Sculpt.bricks(edits, 0.05, parallel: false)
    assert %{bricks: [], evaluations: 0} = Sculpt.bricks([], 0.05)
    assert %{bricks: []} = Sculpt.bricks([SDF.edit(:ball, {1}, mode: :subtract)], 0.05)
  end

  test "a sculpture of 100 edits with cells of 2 cm: less than 5% of the work of each edit at each point of its bounds (R2)" do
    edits = stone(100)
    step = 0.02
    {{lx, ly, lz}, {hx, hy, hz}} = SDF.bounds(edits)
    brute = length(edits) * round((hx - lx) / step + 1) * round((hy - ly) / step + 1) * round((hz - lz) / step + 1)
    %{evaluations: n, bricks: bricks} = Sculpt.bricks(edits, step)
    assert n < 0.05 * brute and length(bricks) > 100
  end

  test "the levels of detail: cells of 2, 8 and 32 cm; fewer faces at each level; a budget" do
    edits = stone(30)
    assert Enum.map([:near, :mid, :far], &Sculpt.step/1) == [0.02, 0.08, 0.32]
    faces = fn meshes -> meshes |> Enum.map(&length(&1.faces)) |> Enum.sum() end
    mid = Sculpt.model(edits, level: :mid)
    far = World.Detail.with(:far, fn -> Sculpt.model(edits) end)
    assert faces.(far) > 0 and faces.(far) < faces.(mid)
    assert Sculpt.model(edits, level: :mid, parallel: false) == mid
    assert faces.(Sculpt.model(edits, level: :mid, budget: 1_000)) <= 1_000
    assert faces.(Sculpt.model(edits, step: 0.05)) > faces.(mid)
  end
end
