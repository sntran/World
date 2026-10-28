defmodule World.PartsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias World.Build

  alias World.Part

  alias World.Scene
  alias World.Furniture.Seats
  alias World.Materials.{Fasteners, Stock}
  alias World.Vehicles.Wheels

  defp size(part) do
    {{x0, y0, z0}, {x1, y1, z1}} = Part.bounds(part)
    {x1 - x0, y1 - y0, z1 - z0}
  end

  property "a bolt has the head and the length of its standard" do
    check all thread <- member_of(Fasteners.threads()), length <- float(min: 0.01, max: 0.2) do
      bolt = Fasteners.bolt(thread, length)
      {s, k} = Fasteners.table(:hex_head, thread)
      {w, _, h} = size(bolt)
      assert_in_delta h, length + k, 1.0e-9
      # The hexagon is s across its flats and s / cos(30°) across its corners.
      assert w >= s - 1.0e-9 and w <= s / :math.cos(:math.pi() / 6) + 1.0e-9
      assert Part.port!(bolt, "tip").at == {0.0, 0.0, -length}
    end
  end

  property "a nut and a washer have the height of their standard" do
    check all thread <- member_of(Fasteners.threads()) do
      {_, _, h} = size(Fasteners.nut(thread))
      assert_in_delta h, Fasteners.table(:nut, thread), 1.0e-9
      {d1, d2, t} = Fasteners.table(:washer, thread)
      {w, _, h} = size(Fasteners.washer(thread))
      assert_in_delta h, t, 1.0e-9
      assert_in_delta w, d2, d2 * 0.02
      assert d1 < d2
    end
  end

  test "a cap screw and the diameter of a thread" do
    screw = Fasteners.cap_screw("M6", 0.03, material: :steel)
    {dk, k} = Fasteners.table(:cap_head, "M6")
    {w, _, h} = size(screw)
    assert_in_delta h, 0.03 + k, 1.0e-9
    assert_in_delta w, dk, 1.0e-9
    assert Fasteners.diameter("M10") == 0.01
    assert hd(screw.shapes).material == :steel
  end

  property "a bearing has its bore, its diameter and its width" do
    check all code <- member_of(Stock.names(:bearing)) do
      {_d, od, b} = Stock.table(:bearing, code)
      {w, _, h} = size(Stock.bearing(code))
      assert_in_delta w, od, od * 0.02
      assert_in_delta h, b, 1.0e-9
    end
  end

  property "lumber has the dry size of its nominal size" do
    check all nominal <- member_of(Stock.names(:lumber)), length <- float(min: 0.1, max: 5.0) do
      {t, w} = Stock.table(:lumber, nominal)

      assert size(Stock.lumber(nominal, length))
             |> Tuple.to_list()
             |> Enum.zip([length, w, t])
             |> Enum.all?(fn {a, b} -> abs(a - b) < 1.0e-9 end)
    end
  end

  test "tubes, rods, sheets, plates, extrusions and springs" do
    assert {_, _, 0.5} = size(Stock.tube(0.03, 0.002, 0.5, :steel))
    assert {_, _, 0.25} = size(Stock.rod(0.01, 0.25, :steel, name: "pin"))
    assert {0.4, 0.3, 0.018} = size(Stock.sheet(0.4, 0.3, 0.018, :wood))
    assert Stock.plate([{0, 0}, {1, 0}, {0, 1}], 0.01, :steel, kind: :plate, sources: ["x"]).sources == ["x"]
    {w, d, l} = size(Stock.extrusion("2020", 0.3))
    assert_in_delta w, 0.02, 1.0e-9
    assert_in_delta d, 0.02, 1.0e-9
    assert_in_delta l, 0.3, 1.0e-9
    assert {_, _, h} = size(Stock.spring(0.05, 0.005, 0.2, 6, :steel))
    assert_in_delta h, 0.2 + 0.005, 0.002
    assert Stock.at(1, 2, 3).at == {1.0, 2.0, 3.0}
    assert Stock.plate([{0, 0}, {1, 0}, {0, 1}], 0.01, :steel).kind == :sheet
    assert Fasteners.cap_screw("M4", 0.02).kind == :cap_screw
    assert World.Port.new("p", {0, 0, 0}, {1, 0, 0}).up |> World.Vec.dot({1.0, 0.0, 0.0}) |> abs() < 1.0e-9
  end

  test "the size of a tire from its code" do
    assert %{width: 0.08, rim: rim, diameter: d} = Wheels.tire_size("80/90-14")
    assert_in_delta rim, 0.3556, 1.0e-9
    assert_in_delta d, 0.3556 + 2 * 0.072, 1.0e-9
    assert_in_delta Wheels.tire_size("215/50R17").diameter, 0.4318 + 0.215, 1.0e-9
    assert_in_delta Wheels.tire_size("120/70 - 12.5").rim, 12.5 * 0.0254, 1.0e-9
    assert_in_delta Wheels.tire_size("37-622").rim, 0.622, 1.0e-9
    assert_raise ArgumentError, ~r/unknown tire code/, fn -> Wheels.tire_size("big") end
  end

  test "a tire has its outer diameter and its width" do
    for {code, profile} <- [{"80/90-14", :round}, {"215/50R17", :flat}] do
      %{diameter: d, width: w} = Wheels.tire_size(code)
      {x, _, z} = size(Wheels.tire(code, profile: profile))
      assert_in_delta x, d, d * 0.01
      assert_in_delta z, w, w * 0.05
    end
  end

  test "each wheel has a hub port and builds" do
    for wheel <- [
          Wheels.cast_wheel("90/90-14", disc: true),
          Wheels.cast_wheel("80/90-14"),
          Wheels.spoked_wheel("37-622"),
          Wheels.car_wheel("215/50R17")
        ] do
      assert wheel.kind == :wheel
      assert World.Assembly.item_port_frame(wheel, "hub").z == {0.0, 0.0, 1.0}
      assert Build.scene(wheel) |> Scene.triangles() > 500
    end

    assert Wheels.axle({1, 0, 0}).z == {1.0, 0.0, 0.0}
    assert Wheels.brake_disc(0.2).params == %{"diameter" => 0.2}
    assert Wheels.tire("80/90-14").kind == :tire
    assert Wheels.rim(0.3556, 0.05).kind == :rim
  end

  test "a seat is a base, a cushion on its track and a back on its hinge, with a headrest" do
    seat = Seats.seat("s", track: 0.2, recline: [0, 40])
    assert Enum.map(seat.nodes, &elem(&1, 0)) == ["s_base", "s_seat", "s_back", "s_head_1"]
    assert World.Assembly.item_port_frame(seat, "floor").z == {0.0, 0.0, 1.0}

    rest = Build.scene(seat)
    assert rest.extras["joints"] == ["s_seat", "s_back"]
    {{_, y0, z0}, {_, _, z1}} = Scene.bounds(rest)
    assert_in_delta z0, 0.0, 1.0e-9
    assert z1 > 1.2 and z1 < 1.3

    # The back turns to the rear and down; the cushion moves to the front.
    {{_, back, _}, {_, _, top}} = Scene.bounds(Build.scene(seat, pose: %{"s_back" => 40}))
    assert back < y0 and top < z1
    {_, {_, front, _}} = Scene.bounds(Build.scene(seat, pose: %{"s_seat" => 0.1}))
    {_, {_, front0, _}} = Scene.bounds(rest)
    assert_in_delta front - front0, 0.1, 1.0e-6
  end

  test "a bench has a headrest for each place, on its legs, and its backs do not move" do
    bench = Seats.bench("b", 3, place_width: 0.45)
    assert length(bench.nodes) == 6
    scene = Build.scene(bench)
    assert scene.extras["joints"] == []
    [w, _, _] = scene.extras["size"]
    assert_in_delta w, 1.35, 1.0e-6
    assert bench.extras["params"]["places"] == 3

    plain = Seats.bench("b", 2, headrest: false)
    assert length(plain.nodes) == 3
    assert length(Seats.bench("b", 2).nodes) == 5
  end
end
