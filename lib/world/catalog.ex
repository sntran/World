defmodule World.Catalog do
  @moduledoc """
  The models of the library: each name with the function that makes it.
  The parts (wheels, seats), the vehicles, the people, and the items of
  DIY. `mix world.build` writes the files of each model in
  `priv/models`.
  """

  # A seat of a van: the sizes of the seats of the Transit (`priv/data/vans.json`).
  @van_seat [
    place_width: 0.52,
    height: 0.5,
    sources: ["The seats of a van: by eye from the photos of the inside of a 2026 Transit passenger van."]
  ]

  @doc "The models, in the order of their names: a list of `{name, fun}`."
  def models do
    Enum.sort_by(
      [
        {"wheel_scooter_90_90_14", fn -> World.Vehicles.Wheels.cast_wheel("90/90-14", disc: true) end},
        {"wheel_bicycle_37_622", fn -> World.Vehicles.Wheels.spoked_wheel("37-622") end},
        {"wheel_car_215_50r17", fn -> World.Vehicles.Wheels.car_wheel("215/50R17") end},
        {"seat_van", fn -> World.Furniture.Seats.seat("seat_van", @van_seat ++ [track: 0.2, recline: [0, 40]]) end},
        {"bench_van_3",
         fn -> World.Furniture.Seats.bench("bench_van_3", 3, @van_seat ++ [place_width: 0.43, height: 0.45]) end}
      ] ++ items(),
      &elem(&1, 0)
    )
  end

  defp items do
    [
      {"honda_vision_110", &World.Vehicles.HondaVision.model/0},
      {"chevy_bolt_ev", &World.Vehicles.ChevyBolt.model/0},
      {"ford_transit_148_camper", &World.Vehicles.FordTransit.model/0},
      {"royal_enfield_himalayan", &World.Vehicles.RoyalEnfieldHimalayan.model/0},
      {"touring_bicycle", &World.Vehicles.TouringBicycle.model/0},
      {"traveler", &World.People.traveler/0},
      {"man", &World.People.man/0},
      {"woman", &World.People.woman/0},
      {"street_dog", fn -> World.Animals.dog(animations: ["walk", "wag"]) end},
      {"honda_vision_110_rider", &World.People.rider/0},
      {"fridge_lg_lrfxs2503s", &World.Appliances.fridge/0},
      {"washer_lg_wm4000hwa", &World.Appliances.washer/0},
      {"dryer_lg", &World.Appliances.dryer/0},
      {"dishwasher_24in", &World.Appliances.dishwasher/0},
      {"range_30in", &World.Appliances.range/0},
      {"microwave_panasonic_nn_sn966s", &World.Appliances.microwave/0},
      {"freezer_frigidaire_ffcl1542aw", &World.Appliances.freezer/0},
      {"water_heater_rheem_prog50", &World.Appliances.Systems.water_heater/0},
      {"ac_goodman_gsx140361", &World.Appliances.Systems.ac/0},
      {"mini_split_mitsubishi_msz_gl12na", &World.Appliances.Systems.mini_split/0},
      {"ceiling_fan_52in", &World.Appliances.Systems.ceiling_fan/0},
      {"tv_samsung_un50cu7000", &World.Appliances.Systems.tv/0}
    ] ++
      World.Gear.PowerStations.all() ++
      World.Gear.Camper.all() ++
      [
        {"van_bed_platform", &World.Furniture.VanBuilds.bed_platform/0},
        {"van_galley", &World.Furniture.VanBuilds.galley/0}
      ] ++
      World.Buildings.all() ++ World.Framing.Builds.all()
  end

  @doc "The function of a model by its name."
  def fetch(name) do
    case List.keyfind(models(), name, 0) do
      {_, fun} -> {:ok, fun}
      nil -> :error
    end
  end
end
