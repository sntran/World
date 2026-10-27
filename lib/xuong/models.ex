defmodule Xuong.Models do
  @moduledoc "The models made from parts: vehicles, people, and the items of DIY."

  @doc "Each model as `{name, fun}`."
  def all do
    [
      {"honda_vision_110", &Xuong.Models.HondaVision.model/0},
      {"chevy_bolt_ev", &Xuong.Models.ChevyBolt.model/0},
      {"ford_transit_148_camper", &Xuong.Models.FordTransit.model/0},
      {"royal_enfield_himalayan", &Xuong.Models.RoyalEnfieldHimalayan.model/0},
      {"touring_bicycle", &Xuong.Models.TouringBicycle.model/0}
    ]
  end
end
