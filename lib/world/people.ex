defmodule World.People do
  @moduledoc """
  People of the catalog (`World.People.Human`, from the data of MakeHuman):

  - `traveler`: a traveler on foot for Phượt, with the animation "walk";
  - `man` and `woman`: adults of Việt Nam, standing;
  - `honda_vision_110_rider`: a rider on the Honda Vision 110, in the pose
    "ride", with the hips on the seat.

  `traveler/3` puts a person on each vehicle of Phượt (the position of a
  traveler on the map), or next to it, parked (the avatar of the
  traveler).
  """
  alias World.{Assembly, Frame, GLB, Part}
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
  # the model (the middle of the model at y = 0, the ground at z = 0), the
  # pose, and the place of the person next to the parked vehicle (on its
  # right side, +x, a little to the back). The car and the van go on the
  # left: the seat of the driver in Việt Nam and in the United States.
  @vehicles %{
    "car" => {&ChevyBolt.model/0, {-0.37, -0.15, 0.65}, "drive", {1.3, -0.6}},
    # The seat of the van at the front of its track, so the head of the
    # driver is in the window of the door (an opening at the near level).
    "camper" => {&FordTransit.model/0, {-0.45, 1.1, 1.15}, "drive", {1.55, -1.0}},
    "motorcycle" => {&RoyalEnfieldHimalayan.model/0, {0.0, -0.3, 0.88}, "ride", {0.75, -0.25}},
    "motorbike" => {&HondaVision.model/0, @seat, "ride", {0.65, -0.2}},
    "bicycle" => {&TouringBicycle.model/0, {0.0, -0.3, 1.03}, "ride_bicycle", {0.55, -0.15}}
  }

  # The vehicles on two wheels: the rider has a helmet.
  @two_wheels ["motorcycle", "motorbike", "bicycle"]

  # The color of a helmet when the order gives none.
  @helmet [236, 232, 222]

  # The animations of the parked traveler (the avatar), to play once.
  @moments ["wave", "point"]

  @doc "The vehicles of a traveler (the names of Phượt), and \"foot\"."
  def vehicles, do: Enum.sort(["foot" | Map.keys(@vehicles)])

  @doc """
  A traveler: a person (the options of `World.People.Human.person/2`, with
  no pose) and a vehicle of Phượt (`vehicles/0`), in a scene:

  - `"ride"` (the position on the map): the person on the vehicle, in the
    pose of the vehicle, with a helmet on two wheels (`helmet`: its color,
    else a light gray). On foot, the person walks (the animation "walk").
    In a car or a van, the glass is clear, so the driver shows.
  - `"parked"` (the avatar): the person stands next to the parked vehicle,
    on its right side, and looks to the right (+x), to the viewer of the
    side of the vehicle. On foot, the person stands. The person has the
    animations "wave" (to the viewer) and "point" (with the left hand, to
    the front of the vehicle, +y), each to play once.

  A moving vehicle has its driver in a safe pose: the eyes on the road,
  the hands on the bars or on the wheel.
  """
  def traveler(vehicle, opts \\ [], scene \\ "ride")

  def traveler("foot", opts, "ride"),
    do: Human.person("traveler", Keyword.merge(opts, pose: "stand", animations: ["walk"], helmet: nil))

  def traveler("foot", opts, "parked"),
    do: facing(Human.person("traveler", Keyword.merge(opts, pose: "stand", animations: @moments, helmet: nil)))

  def traveler(vehicle, opts, "ride") do
    {model, hips, pose, _} = Map.fetch!(@vehicles, vehicle)
    helmet = if vehicle in @two_wheels, do: Keyword.get(opts, :helmet) || @helmet
    person = Human.person("traveler", Keyword.merge(opts, pose: pose, helmet: helmet))
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

  def traveler(vehicle, opts, "parked") do
    {model, _, _, {x, y}} = Map.fetch!(@vehicles, vehicle)
    person = Human.person("traveler", Keyword.merge(opts, pose: "stand", animations: @moments, helmet: nil))
    m = model.()

    Assembly.new("traveler_" <> vehicle <> "_parked", m,
      root: "vehicle",
      kind: :vehicle,
      sources: ["The #{m.name} of World, parked, and a person of World next to it."]
    )
    |> Assembly.add("traveler", person, at: Part.port("stand", {x, y, 0.0}, {0, 0, 1}, {1, 0, 0}), port: "ground")
  end

  # A person that looks to the right (+x): the root turns.
  defp facing(%{nodes: [root | rest]} = person),
    do: %{person | nodes: [%{root | frame: Frame.turn({0.0, 0.0, 1.0}, -90)} | rest]}
end
