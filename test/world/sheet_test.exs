defmodule World.SheetTest do
  use ExUnit.Case, async: true

  alias World.{Mass, Sheet}
  alias World.Materials.Stock

  doctest Sheet
  doctest Stock, only: [gauge: 1]

  @t 0.0015

  test "a tray: the volume of the bent sheet is its flat area times its thickness" do
    # With k = 0.5 the neutral line is in the middle of the sheet, so the
    # flat pattern has the area of the middle of the bent sheet.
    s =
      Sheet.new(0.3, 0.2, @t, k: 0.5)
      |> Sheet.flange(:left, 0.04)
      |> Sheet.flange(:right, 0.04)

    %{size: {fx, fy}, bends: 2} = Sheet.flat(s)
    assert_in_delta fy, 0.2, 1.0e-12
    part = Sheet.part(s, "tray", :tray, [])
    volume = part.shapes |> Enum.map(&elem(Mass.mesh(&1), 0)) |> Enum.sum()
    assert abs(volume - fx * fy * @t) / (fx * fy * @t) < 0.005
    assert part.params["bends"] == 2 and part.params["flat"] == [fx, fy]
  end

  test "a box with four flanges and lips, a hole in the base, and a frame" do
    s =
      [:left, :right, :front, :back]
      |> Enum.reduce(Sheet.new(0.3, 0.4, @t, material: :paint, matter: :steel), &Sheet.flange(&2, &1, 0.1, lip: 0.012))
      |> Sheet.hole({0.05, 0.05, 0.06, 0.06})

    assert %{bends: 8} = Sheet.flat(s)
    part = Sheet.part(s, "box", :box, [], frame: World.Frame.move({1.0, 0.0, 0.0}))

    # Each mesh is closed, of paint, with steel for its mass.
    assert Enum.all?(part.shapes, &(Mass.mesh(&1) != nil and &1.matter == :steel))
    assert %{mass: m} = Mass.part(part)
    assert m > 0

    # The frame moves the sheet: its least x is 1 m.
    xs = for m <- part.shapes, {x, _, _} <- m.points, do: x
    assert_in_delta Enum.min(xs), 1.0, 1.0e-9
  end

  test "a flange too short for its bends is refused" do
    s = Sheet.new(0.3, 0.2, @t)
    assert_raise ArgumentError, fn -> Sheet.flange(s, :front, 0.005) end
    assert_raise ArgumentError, fn -> Sheet.flange(s, :front, 0.05, lip: 0.002) end
  end

  test "the enclosure A-16N126: its sizes, its cover on hinges, and a true model" do
    e = World.Enclosures.hoffman_a16n126()
    assert e.kind == :enclosure and World.Places.family_of(e) == :sheets
    assert World.Check.model(e) == :ok
    assert World.Check.joints(e, %{"cover" => 120}) == {:error, {:joints, ["cover"]}}

    points = for {f, p} <- World.Build.placed(e), m <- p.shapes, pt <- m.points, do: World.Frame.point(f, pt)
    {{x0, y0, _}, {x1, y1, z1}} = World.Vec.bounds(points)
    # 12 by 6 by 16 in; the cover and the knuckles of the hinges stand
    # out at the sides.
    assert_in_delta x1 - x0, 12 * 0.0254, 0.012
    assert_in_delta y1 - y0, 6 * 0.0254, 0.015
    assert_in_delta z1, 16 * 0.0254, 0.005

    %{mass: mass, unknown: []} = Mass.of(e)
    assert mass > 4 and mass < 8
  end
end
