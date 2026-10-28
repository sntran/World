defmodule Xuong.Models do
  @moduledoc "The models made from parts: vehicles, people, and the items of DIY."

  @doc "Each model as `{name, fun}`."
  def all do
    [
      {"honda_vision_110", &Xuong.Models.HondaVision.model/0},
      {"chevy_bolt_ev", &Xuong.Models.ChevyBolt.model/0},
      {"ford_transit_148_camper", &Xuong.Models.FordTransit.model/0},
      {"royal_enfield_himalayan", &Xuong.Models.RoyalEnfieldHimalayan.model/0},
      {"touring_bicycle", &Xuong.Models.TouringBicycle.model/0},
      {"traveler", &Xuong.Models.People.traveler/0},
      {"man", &Xuong.Models.People.man/0},
      {"woman", &Xuong.Models.People.woman/0},
      {"honda_vision_110_rider", &Xuong.Models.People.rider/0},
      {"fridge_lg_lrfxs2503s", &Xuong.Models.Appliances.fridge/0},
      {"washer_lg_wm4000hwa", &Xuong.Models.Appliances.washer/0},
      {"dryer_lg", &Xuong.Models.Appliances.dryer/0},
      {"dishwasher_24in", &Xuong.Models.Appliances.dishwasher/0},
      {"range_30in", &Xuong.Models.Appliances.range/0},
      {"microwave_panasonic_nn_sn966s", &Xuong.Models.Appliances.microwave/0},
      {"freezer_frigidaire_ffcl1542aw", &Xuong.Models.Appliances.freezer/0},
      {"water_heater_rheem_prog50", &Xuong.Models.Systems.water_heater/0},
      {"ac_goodman_gsx140361", &Xuong.Models.Systems.ac/0},
      {"mini_split_mitsubishi_msz_gl12na", &Xuong.Models.Systems.mini_split/0},
      {"ceiling_fan_52in", &Xuong.Models.Systems.ceiling_fan/0},
      {"tv_samsung_un50cu7000", &Xuong.Models.Systems.tv/0}
    ] ++
      Xuong.Models.PowerStations.all() ++
      Xuong.Models.VanGear.all() ++
      [{"van_bed_platform", &Xuong.Models.VanBuilds.bed_platform/0}, {"van_galley", &Xuong.Models.VanBuilds.galley/0}] ++
      Xuong.Models.Houses.all()
  end
end
