defmodule World.Boats do
  @moduledoc """
  The boats of the world (`docs/world.md`, step P6), built by the
  boatyard (the family `:boats`) on its slipway: each an assembly of the
  kind `:boat`.

  - `World.Boats.Ghe`: the ghe of Vũng Tàu, a wooden fishing boat to the
    rules of QCVN 91:2025/BNNMT.
  """

  @doc "The boats of the catalog, as `{name, fun}`."
  def models, do: [{"ghe_vung_tau", &World.Boats.Ghe.ghe/0}]
end
