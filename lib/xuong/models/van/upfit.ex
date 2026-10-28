defmodule Xuong.Models.Van.Upfit do
  @moduledoc """
  The last station of a van (`Xuong.Models.Van`), after the line: the
  items of DIY on the roof. A roof fan (the MaxxAir MaxxFan) and a solar
  panel on four feet, each at a distance `d` from the front.
  """
  alias Xuong.{Assembly, Shape}
  alias Xuong.Models.VanGear
  alias Xuong.Models.Van.Kit

  @station "upfit"

  @doc "The van with the items on its roof: `{:fan, d}` and `{:solar, d}`."
  def fit(asm, %{h: h}, items) do
    Enum.reduce(Enum.with_index(items), asm, fn
      {{:fan, d}, i}, asm ->
        Assembly.add(asm, "roof_fan_#{i}", Kit.station(VanGear.maxxfan(), @station),
          at: Kit.port("roof_fan_#{i}", {0.0, h.length - d, h.top}, {0, 0, 1}, {0, 1, 0}),
          port: "o"
        )

      {{:solar, d}, i}, asm ->
        Assembly.add(asm, "solar_#{i}", solar_on_feet(),
          at: Kit.port("solar_#{i}", {0.0, h.length - d, h.top}, {0, 0, 1}, {0, 1, 0}),
          port: "o"
        )
    end)
  end

  # The solar panel of DIY on four feet of aluminum, 4 cm over the roof.
  defp solar_on_feet do
    feet =
      for x <- [-0.5, 0.5],
          y <- [-0.7, 0.7],
          do: Shape.box({x - 0.02, y - 0.04, 0.0}, {x + 0.02, y + 0.04, 0.04}, :aluminum)

    Assembly.new(
      "solar_on_feet",
      Kit.part(@station, "solar_feet", :bracket, feet, [Kit.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})]),
      root: "feet"
    )
    |> Assembly.add("panel", Kit.station(VanGear.solar_panel(), @station),
      at: Kit.port("top", {0.0, 0.0, 0.04}, {0, 0, 1}, {0, 1, 0}),
      port: "o"
    )
  end
end
