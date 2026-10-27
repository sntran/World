defmodule Xuong.Catalog do
  @moduledoc """
  The models of the library: each name with the function that makes it.
  `mix xuong.build` writes the files of each model in `priv/models`.
  """

  @doc "The models, in the order of their names: a list of `{name, fun}`."
  def models do
    Enum.sort_by(
      [
        {"wheel_scooter_90_90_14", fn -> Xuong.Parts.Wheels.cast_wheel("90/90-14", disc: true) end},
        {"wheel_bicycle_37_622", fn -> Xuong.Parts.Wheels.spoked_wheel("37-622") end},
        {"wheel_car_215_50r17", fn -> Xuong.Parts.Wheels.car_wheel("215/50R17") end}
      ] ++ Xuong.Models.all(),
      &elem(&1, 0)
    )
  end

  @doc "The function of a model by its name."
  def fetch(name) do
    case List.keyfind(models(), name, 0) do
      {_, fun} -> {:ok, fun}
      nil -> :error
    end
  end
end
