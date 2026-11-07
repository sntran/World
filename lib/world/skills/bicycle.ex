defmodule World.Skills.Bicycle do
  @moduledoc """
  The geometry sheet of a bicycle with a diamond frame, for the skills
  `bicycle_frame`, `bicycle_fork` and `crankset` (plan 0002, D5;
  `World.Vehicles.Bicycle`): each number of the sheet, with the numbers
  of a touring frame of 54 cm as the defaults.
  """
  import World.Orders.Blueprint, only: [option: 3]
  alias World.Skills.Vehicle
  alias World.Vehicles.{Bicycle, Wheels}

  @ranges %{
    "sag" => {0.0, 0.02},
    "chainstay" => {0.35, 0.55},
    "bb_drop" => {0.0, 0.12},
    "stack" => {0.45, 0.75},
    "reach" => {0.3, 0.5},
    "head_angle" => {60.0, 80.0},
    "seat_angle" => {65.0, 80.0},
    "seat_tube" => {0.35, 0.7},
    "head_tube" => {0.06, 0.3},
    "seatpost" => {0.05, 0.4},
    "rear_spacing" => {0.1, 0.2},
    "top_tube_d" => {0.015, 0.06},
    "down_tube_d" => {0.015, 0.07},
    "head_tube_d" => {0.025, 0.07},
    "chainstay_d" => {0.01, 0.04},
    "seatstay_d" => {0.008, 0.04},
    "bar_width" => {0.3, 0.8},
    "rake" => {0.0, 0.08},
    "arm" => {0.14, 0.2}
  }

  @doc "The options of a sheet: its numbers, the code of its tire, and the teeth of its chainring."
  def options do
    touring = Bicycle.touring()

    [
      option("tire", :data, default: touring["tire"], check: &tire/2),
      option("teeth", :integer, default: 44, min: 22, max: 60)
    ] ++
      for {name, {lo, hi}} <- Enum.sort(@ranges),
          do:
            option(name, :number,
              default: touring[name],
              min: lo,
              max: hi,
              unit: if(name =~ "angle", do: "degrees", else: "m")
            )
  end

  defp tire(raw, path) do
    _ = Wheels.tire_size(raw)
    {:ok, raw}
  rescue
    _ -> {:error, [{path, "must be the code of a tire: 37-622"}]}
  end

  @doc "The errors of a sheet."
  def check(data, path), do: Vehicle.check(data, path, options())

  @doc "The sheet of the data, with the default of each number."
  def sheet(data),
    do:
      Map.new(Vehicle.o(data, options()), fn {k, v} -> {k, if(is_integer(v) and k != "teeth", do: v / 1, else: v)} end)
end
