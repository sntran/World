defmodule Xuong.Models.FordTransit do
  @moduledoc """
  The Ford Transit 148 in, high roof, made a camper van: the "camper" of
  Phượt, and the base van of DIY. It is the van of `Xuong.Models.Van`,
  with a solar panel and a roof fan on the roof, and the two items of
  DIY for the engine bay: a second alternator and a DC-DC charger (the
  REDARC BCDC1250D).
  """

  @doc "The camper van."
  def model do
    Xuong.Models.Van.build("transit_148",
      name: "ford_transit_148_camper",
      engine_bay: [:second_alternator, :dc_charger],
      roof: [{:solar, 3.75}, {:fan, 5.15}]
    )
  end
end
