defmodule Xuong.Models.FordTransit do
  @moduledoc """
  The Ford Transit 148 in, high roof: the "camper" of Phượt, and the
  base van of DIY. It is the van of `Xuong.Models.Van`, with the two
  items of DIY for the engine bay: a second alternator and a DC-DC
  charger (the REDARC BCDC1250D). The roof fan and the solar panel are
  parts of the catalog (`Xuong.Models.VanGear`), not on this van.
  """

  @doc "The camper van."
  def model do
    Xuong.Models.Van.build("transit_148",
      name: "ford_transit_148_camper",
      engine_bay: [:second_alternator, :dc_charger]
    )
  end
end
