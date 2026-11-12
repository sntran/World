defmodule World.Stone do
  @moduledoc false
  # A stone for the tests of the sculptures: an ellipsoid with balls added
  # and taken away on its surface (the same edits each time).

  alias World.{Frame, SDF, Vec}

  def edits(n) do
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
end
