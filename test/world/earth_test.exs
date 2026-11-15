defmodule World.EarthTest do
  # The heights of the real Earth for the points of a project (plan 0019, 7.2).
  use ExUnit.Case, async: true

  alias World.Earth

  test "the height at a place: the mountains, the deep sea, the ice, and each longitude" do
    # The grid has a value each quarter of a degree: a high peak is lower in it.
    assert Earth.height(27.99, 86.93) > 5000
    assert Earth.height(11.35, 142.2) < -8000
    assert_in_delta Earth.height(11.94, 108.44), 1500, 200
    assert Earth.height(10.3, 107.1) < 0 and Earth.height(10.3, 107.1) > -50
    assert Earth.height(-80, 0) > 2000
    # The two ends of the grid are one meridian, and a longitude wraps.
    assert Earth.height(0, 180) == Earth.height(0, -180)
    assert Earth.height(0, 540) == Earth.height(0, 180)
    assert_in_delta Earth.height(20.1, 365.3), Earth.height(20.1, 5.3), 1.0e-6
    # The poles are in the grid.
    assert Earth.height(90, 0) < -4000 and Earth.height(-90, 123.4) > 2700
    # A point between four values is between them.
    values = for lat <- [10.0, 10.25], lon <- [106.0, 106.25], do: Earth.height(lat, lon)
    mid = Earth.height(10.125, 106.125)
    assert mid >= Enum.min(values) and mid <= Enum.max(values)
    assert_in_delta mid, Enum.sum(values) / 4, 1.0e-6
  end

  test "the heights of the points of a project, and the errors of a wrong point" do
    assert {:ok, [everest, sea]} = Earth.heights([[27.99, 86.93], [0, -150]])
    assert is_integer(everest) and everest == round(Earth.height(27.99, 86.93)) and sea < -3000
    assert Earth.heights([]) == {:ok, []}

    assert {:error, [%{"path" => "points.1", "message" => message}, %{"path" => "points.2"}]} =
             Earth.heights([[0, 0], [91, 0], ["a", 1], [-90, 720]])

    assert message =~ "[latitude, longitude]"
    assert {:error, [%{"path" => "points"}]} = Earth.heights(nil)
    assert {:error, [%{"path" => "points"}]} = Earth.heights(List.duplicate([0, 0], 200_001))
    assert Earth.source() =~ "ETOPO1" and Earth.source() =~ "NOAA"
  end
end
