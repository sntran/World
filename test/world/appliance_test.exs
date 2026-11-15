defmodule World.ApplianceTest do
  # An appliance from its kind and its size (plan 0019, step 5; for DIY).
  use ExUnit.Case, async: true

  alias World.Home.Appliance

  defp edits(request), do: hd(Appliance.drawing(request)["nodes"])["skill"]["sculpt"]["edits"]

  test "each kind gives a drawing of one part from edits, with the common size of the kind" do
    assert Appliance.kinds() ==
             ~w(battery box busbar dishwasher dryer freezer fridge inverter microwave power_station range solar_panel tv washer water_heater water_tank)

    for kind <- Appliance.kinds() do
      d = Appliance.drawing(%{"kind" => kind})
      assert {:ok, _} = World.Drawing.check(d, "d"), kind
      assert JSON.decode!(JSON.encode!(d)) == d
      assert d["name"] == kind and d["kind"] == "prop"
      assert [%{"name" => name, "skill" => %{"sculpt" => sculpt}}] = d["nodes"]
      assert name == kind <> "_than" and Enum.all?(sculpt["edits"], &(&1["material"] == "part_01"))
      # The cells are small for a small thing, and each level has cells two times larger.
      %{"near" => near, "mid" => mid, "far" => far} = sculpt["cells"]
      assert near >= 0.004 and near <= 0.02 and close?(mid, 2 * near) and close?(far, 4 * near)
      [w, d_, h] = d["extras"]["appliance"]["size"]
      # The label of the real thing is on the right side.
      assert d["extras"]["tags"]["label"] == [Float.round(w / 2, 4), Float.round(-d_ / 4, 4), Float.round(h * 0.75, 4)]
    end
  end

  defp close?(a, b), do: abs(a - b) < 3.0e-4

  test "a request with no word is a plain box; the size, the color and the name of a request stay" do
    r = Appliance.request()
    assert Appliance.request(r) == r

    assert r == %{
             "kind" => "box",
             "name" => "box",
             "sources" => [],
             "size" => [0.5, 0.4, 0.4],
             "color" => "#eceeed",
             "doors" => "french",
             "ports" => 4
           }

    assert Appliance.drawing() == Appliance.drawing(%{})

    assert [%{"shape" => "round_box", "size" => [0.25, 0.2, 0.2, 0.012], "at" => [0, 0, 0.2], "color" => "#eceeed"}] =
             edits(%{})

    d =
      Appliance.drawing(%{
        "kind" => "fridge",
        "name" => "tu_lanh_lg",
        "size" => [0.83, 0.8, 1.7],
        "color" => "#101010",
        "sources" => ["A fridge of the test."]
      })

    assert d["name"] == "tu_lanh_lg" and d["sources"] == ["A fridge of the test."]
    assert %{"size" => [0.415, 0.4, 0.83, 0.012], "color" => "#101010"} = hd(hd(d["nodes"])["skill"]["sculpt"]["edits"])
  end

  test "the doors of a fridge, and the studs of a busbar" do
    handles = fn request ->
      Enum.count(edits(request), &(&1["color"] == "#b8bbbe" and &1["shape"] == "box" and Enum.max(&1["size"]) > 0.05))
    end

    lines = fn request -> Enum.count(edits(request), &(&1["color"] == "#4a4d50")) end

    # Two doors over a drawer: three handles and three seams of four lines. A small door over a large one: two. One door: one.
    assert handles.(%{"kind" => "fridge"}) == 3 and lines.(%{"kind" => "fridge"}) == 12

    assert handles.(%{"kind" => "fridge", "doors" => "top"}) == 2 and
             lines.(%{"kind" => "fridge", "doors" => "top"}) == 8

    assert handles.(%{"kind" => "fridge", "doors" => "single"}) == 1 and
             lines.(%{"kind" => "fridge", "doors" => "single"}) == 4

    studs = fn ports -> Enum.count(edits(%{"kind" => "busbar", "ports" => ports}), &(&1["shape"] == "prism")) end
    assert studs.(4) == 4 and studs.(1) == 1 and studs.(24) == 24
    # A washer has a door of glass, and a dryer a dark door.
    door = fn kind ->
      Enum.find(edits(%{"kind" => kind}), &(&1["shape"] == "cylinder" and Enum.at(&1["size"], 1) == 0.034))["color"]
    end

    assert door.("washer") == "#27323a" and door.("dryer") == "#3a3d40"
  end

  test "a word that is not possible is an error with its message" do
    wrong = [
      {[], "the request of an appliance is a map"},
      {%{"watts" => 1200}, ~s(an appliance has no key "watts")},
      {%{"kind" => "toaster"}, "the kind of an appliance is one of battery, box"},
      {%{"name" => "LG"}, "the name of an appliance"},
      {%{"sources" => "a page"}, "the sources of an appliance are lines of text"},
      {%{"size" => [1, 2]}, "the size of an appliance is [wide, deep, high]"},
      {%{"size" => [1, 2, 9]}, "the size of an appliance is [wide, deep, high]"},
      {%{"color" => "white"}, "the color of an appliance is as #a1b2c3"},
      {%{"doors" => "sliding"}, "the doors of a fridge are french, top or single"},
      {%{"ports" => 0}, "a busbar has from 1 to 24 ports"}
    ]

    for {request, text} <- wrong do
      error = assert_raise ArgumentError, fn -> Appliance.request(request) end
      assert error.message =~ text
    end
  end
end
