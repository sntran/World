defmodule Xuong.Models.People do
  @moduledoc """
  People of the catalog (`Xuong.Human`, from the data of MakeHuman):

  - `traveler`: a traveler on foot for Phượt, with the animation "walk";
  - `man` and `woman`: adults of Việt Nam, standing;
  - `honda_vision_110_rider`: a rider on the Honda Vision 110, in the pose
    "ride", with the hips on the seat.
  """
  alias Xuong.{Assembly, Human, Part}
  alias Xuong.Models.HondaVision

  @doc "A traveler on foot: a t-shirt, cargo pants and shoes."
  def traveler do
    Human.person("traveler",
      age: 28,
      clothes: ["elvs_crude_t-shirt_male", "cortu_cargo_pants", "shoes02"],
      hair: "short04",
      pose: "stand",
      animations: ["walk"]
    )
  end

  @doc "A man of Việt Nam, 35 years old."
  def man do
    Human.person("man", age: 35, height: 0.55, muscle: 0.55, pose: "stand")
  end

  @doc "A woman of Việt Nam, 30 years old."
  def woman do
    Human.person("woman",
      gender: 0.0,
      age: 30,
      height: 0.55,
      weight: 0.4,
      skin: "young_asian_female",
      eyebrows: "eyebrow010",
      hair: "ponytail01",
      clothes: ["female_casualsuit01", "shoes02"],
      pose: "stand"
    )
  end

  # The hips of the rider on the seat of the scooter, in the axes of the
  # scooter (its center at y = 0).
  @seat {0.0, -0.33, 0.86}

  @doc "A rider on the Honda Vision 110: the scooter is the root."
  def rider do
    rider =
      Human.person("rider",
        age: 30,
        clothes: ["elvs_crude_t-shirt_male", "cortu_cargo_pants", "shoes01"],
        pose: "ride"
      )

    Assembly.new("honda_vision_110_rider", HondaVision.model(),
      root: "scooter",
      kind: :vehicle,
      sources: ["The Honda Vision 110 of Xưởng, and a person of Xưởng in the pose \"ride\"."]
    )
    |> Assembly.add("rider", rider, at: Part.port("seat", @seat, {0, 0, 1}, {0, 1, 0}), port: "hips")
  end
end
