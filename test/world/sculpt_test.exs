defmodule World.SculptTest do
  # The bricks of a sculpture: a tree of processes finds the cells near
  # its surface (plan 0008, D3 and D5; R2).
  use ExUnit.Case, async: true

  alias World.{Frame, SDF, Sculpt, Vec}

  # A stone: an ellipsoid with balls added and taken away on its surface.
  def stone(n) do
    :rand.seed(:exsss, {3, 3, 3})
    base = SDF.edit(:ellipsoid, {0.8, 0.6, 0.5}, material: :stone)

    bumps =
      for i <- 1..(n - 1) do
        dir = Vec.norm({:rand.normal(), :rand.normal(), :rand.normal()})
        at = {elem(dir, 0) * 0.8, elem(dir, 1) * 0.6, elem(dir, 2) * 0.5}
        mode = if rem(i, 3) == 0, do: :subtract, else: :add
        SDF.edit(:ball, {0.05 + :rand.uniform() * 0.1}, frame: Frame.move(at), mode: mode, blend: 0.03)
      end

    [base | bumps]
  end

  test "each brick has the field of all the edits at its points, with its border" do
    edits = stone(30)
    %{bricks: bricks, step: step} = Sculpt.bricks(edits, 0.05)
    assert bricks != [] and Sculpt.cells() == 8 and Sculpt.points() == 11

    for b <- bricks, i <- [-1, 0, 4, 8, 9], j <- [-1, 3, 9], k <- [-1, 0, 7, 9] do
      p = Vec.add(Sculpt.corner(b.at, step), {i * step, j * step, k * step})
      # The field is in floats of 32 bits.
      assert_in_delta Sculpt.at(b, {i, j, k}), SDF.value(edits, p), 1.0e-6 * max(1.0, abs(SDF.value(edits, p)))
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
end
