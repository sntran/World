defmodule World.MeasureTest do
  # The measures of a model (plan 0003, D2) on a model whose numbers are
  # known: a body of 1.6 by 4 m on four wheels of 0.3 m, 2.5 m apart.
  use ExUnit.Case, async: true

  alias World.{Assembly, Measure, Part, Shape}

  @o Part.port("o", {0, 0, 0}, {0, 0, 1}, {0, 1, 0})

  defp car do
    ports =
      [@o, Part.port("head", {0.0, 3.8, 1.5}, {0, -0.5, 0.866}, {0, 1, 0})] ++
        for {name, x, y} <- [{"fr", 0.8, 3.0}, {"fl", -0.8, 3.0}, {"rr", 0.8, 0.5}, {"rl", -0.8, 0.5}],
            do: Part.port(name, {x, y, 0.3}, {1, 0, 0}, {0, 0, 1})

    body = Part.new("body", :body, [Shape.box({-0.8, 0.0, 0.2}, {0.8, 4.0, 1.5}, :paint)], ports)
    # A seat in three steps along y: 1.3 m high, then 1.2, then 1.35.
    seat =
      Part.new(
        "seat",
        :seat,
        for(
          {y0, y1, z} <- [{1.0, 1.2, 1.3}, {1.2, 1.6, 1.2}, {1.6, 1.8, 1.35}],
          do: Shape.box({-0.2, y0, 1.0}, {0.2, y1, z}, :black)
        ),
        [@o]
      )

    mirror = Part.new("mirror", :mirror, [Shape.box({0.8, 2.8, 1.0}, {1.0, 2.9, 1.1}, :black)], [@o])

    wheel =
      Part.new("wheel", :wheel, [Shape.cylinder(0.3, 0.2, :tire, sides: 16, frame: World.Frame.move({0, 0, -0.1}))], [
        Part.port("hub", {0, 0, 0}, {0, 0, 1}, {1, 0, 0})
      ])

    Enum.reduce(~w(fr fl rr rl), Assembly.new("car", body, root: "body"), fn name, a ->
      Assembly.add(a, "wheel_" <> name, wheel, at: name, port: "hub", kind: :hinge, role: :wheel)
    end)
    |> Assembly.add("mirror", mirror, at: "o", port: "o")
    |> Assembly.add("seat", seat, at: "o", port: "o")
  end

  test "the box, the axles, the wheelbase, the tracks, the ground clearance, the top, the seat, a port and the mass" do
    m = Measure.of(car(), :near)
    assert_in_delta Measure.size(m, :width), 1.9, 1.0e-9
    assert_in_delta Measure.size(m, :width, ["mirror"]), 1.8, 1.0e-6
    assert_in_delta Measure.size(m, :length), 4.0, 1.0e-9
    assert_in_delta Measure.size(m, :height), 1.5, 1.0e-6
    assert length(Measure.axles(m)) == 4 and elem(hd(Measure.axles(m)), 1) == 3.0
    assert_in_delta Measure.wheelbase(m), 2.5, 1.0e-9
    assert_in_delta Measure.track(m, :front), 1.6, 1.0e-9
    assert_in_delta Measure.track(m, :rear), 1.6, 1.0e-9
    assert_in_delta Measure.ground_clearance(m, ~w(wheel_fr wheel_fl wheel_rr wheel_rl)), 0.2, 1.0e-9
    assert_in_delta Measure.ground_clearance(m, []), 0.0, 1.0e-6
    assert_in_delta Measure.top(m, "body"), 1.5, 1.0e-9
    assert_in_delta Measure.top(m, "mirror", {2.0, 3.0}), 1.1, 1.0e-9
    assert_in_delta Measure.top(m, "seat"), 1.35, 1.0e-9
    assert_in_delta Measure.seat(m, "seat", {1.0, 1.8}), 1.2, 1.0e-9
    assert_in_delta Measure.seat(m, "seat", {1.0, 1.15}, 3), 1.3, 1.0e-9
    {at, axis} = Measure.port(m, "body", "head")
    assert at == {0.0, 3.8, 1.5} and up?(axis)
    assert Measure.mass(m) > 0
  end

  defp up?({_, y, z}), do: abs(y + 0.5) < 1.0e-3 and abs(z - 0.866) < 1.0e-3

  test "the bill of quantities of a tube house: the sum of the takeoff of its tasks" do
    {:ok, job} = World.Orders.job(%{"blueprint" => "tube_house", "options" => %{"floors" => 1}}, "far")
    q = Measure.takeoff(job.drawing)
    assert q["brick"] > 1000 and q["cement"] > 10 and q["rebar"] > 10
    assert Enum.sort(Map.keys(q)) == ~w(brick cement mortar paint rebar)
  end
end
