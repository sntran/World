defmodule World.People do
  @moduledoc """
  People of the catalog (`World.People.Human`, from the data of MakeHuman):

  - `traveler`: a traveler on foot for Phượt, with the animation "walk";
  - `man` and `woman`: adults of Việt Nam, standing;
  - `honda_vision_110_rider`: a rider on the Honda Vision 110, in the pose
    "ride", with the hips on the seat.

  `traveler/2` puts a person on each vehicle of Phượt: the avatar of a
  traveler on the map.
  """
  alias World.{Assembly, GLB, Part}
  alias World.People.Human
  alias World.Vehicles.{ChevyBolt, FordTransit, HondaVision, RoyalEnfieldHimalayan, TouringBicycle}

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
      sources: ["The Honda Vision 110 of World, and a person of World in the pose \"ride\"."]
    )
    |> Assembly.add("rider", rider, at: Part.port("seat", @seat, {0, 0, 1}, {0, 1, 0}), port: "hips")
  end

  # The vehicles of Phượt: the model, the hips of the person in the axes of
  # the model (the middle of the model at y = 0, the ground at z = 0), and
  # the pose. The car and the van go on the left: the seat of the driver in
  # Việt Nam and in the United States.
  @vehicles %{
    "car" => {&ChevyBolt.model/0, {-0.37, -0.15, 0.65}, "drive"},
    # The seat of the van at the front of its track, so the head of the
    # driver is in the window of the door (an opening at the near level).
    "camper" => {&FordTransit.model/0, {-0.45, 1.1, 1.15}, "drive"},
    "motorcycle" => {&RoyalEnfieldHimalayan.model/0, {0.0, -0.3, 0.88}, "ride"},
    "motorbike" => {&HondaVision.model/0, @seat, "ride"},
    "bicycle" => {&TouringBicycle.model/0, {0.0, -0.3, 1.03}, "ride_bicycle"}
  }

  @doc "The vehicles of a traveler (the names of Phượt), and \"foot\"."
  def vehicles, do: Enum.sort(["foot" | Map.keys(@vehicles)])

  @doc """
  A traveler: a person (the options of `World.People.Human.person/2`, with
  no pose) on a vehicle of Phượt (`vehicles/0`), in the pose of the
  vehicle. On foot, the person stands, with the animation "walk". In a car
  or a van, the glass is clear, so the driver shows.
  """
  def traveler(vehicle, opts \\ [])

  def traveler("foot", opts),
    do: Human.person("traveler", Keyword.merge(opts, pose: "stand", animations: ["walk"]))

  def traveler(vehicle, opts) do
    {model, hips, pose} = Map.fetch!(@vehicles, vehicle)
    person = Human.person("traveler", Keyword.merge(opts, pose: pose))
    m = model.()
    glass = if vehicle in ["car", "camper"], do: %{glass_dark: GLB.palette()["glass"]}, else: %{}

    Assembly.new("traveler_" <> vehicle, m,
      root: "vehicle",
      kind: :vehicle,
      materials: Map.merge(m.materials, glass),
      sources: ["The #{m.name} of World, and a person of World in the pose \"#{pose}\"."]
    )
    |> Assembly.add("traveler", person, at: Part.port("seat", hips, {0, 0, 1}, {0, 1, 0}), port: "hips")
  end
end
