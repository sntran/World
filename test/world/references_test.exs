defmodule World.ReferencesTest do
  # The references (plan 0003, D1, D3, D6): each real thing of
  # priv/references is built by the people of the node, and each of its
  # numbers is in its tolerance. The measures and the report on numbers
  # that the blueprints of World set by their construction.
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias World.References

  @bicycle %{
    "name" => "bicycle_of_world",
    "title" => "The bicycle of World",
    "level" => "far",
    "order" => %{"blueprint" => "bicycle", "options" => %{}},
    "numbers" => [
      %{"name" => "wheelbase", "value" => 1.0173, "measure" => %{"wheelbase" => true}},
      %{
        "name" => "chainstay",
        "value" => 0.43,
        "measure" => %{"distance" => [["frame", "bb"], ["frame", "rear_axle"]]}
      },
      %{
        "name" => "bottom bracket drop",
        "value" => 0.07,
        "tolerance" => %{"abs" => 0.001},
        "measure" => %{"along" => "z", "from" => ["frame", "bb"], "to" => ["frame", "rear_axle"]}
      },
      %{"name" => "head angle", "value" => 72.0, "measure" => %{"angle" => ["frame", "steer"]}},
      %{"name" => "curb mass", "value" => 1.0, "tolerance" => 1000.0, "measure" => %{"mass" => true}}
    ]
  }

  @car %{
    "name" => "car_of_world",
    "title" => "The car of World",
    "level" => "far",
    "order" => %{"blueprint" => "car", "options" => %{}},
    "numbers" => [
      %{"name" => "front track", "value" => 1.5, "measure" => %{"track" => "front"}},
      %{"name" => "rear track", "value" => 1.5, "measure" => %{"track" => "rear"}},
      %{"name" => "length", "value" => 4.145, "tolerance" => 0.02, "measure" => %{"size" => "length"}},
      %{"name" => "height", "value" => 1.611, "tolerance" => 0.02, "measure" => %{"size" => "height", "without" => []}},
      %{
        "name" => "roof",
        "value" => 1.616,
        "tolerance" => 0.02,
        "measure" => %{"top" => "body", "span" => [-1.0, 1.0]}
      },
      %{
        "name" => "width (SAE J1100: no mirrors)",
        "value" => 1.765,
        "measure" => %{"size" => "width", "without" => ["mirrors"]}
      },
      %{
        "name" => "the low top of the body at the rear",
        "value" => 0.98,
        "tolerance" => 0.01,
        "measure" => %{"seat" => "body", "span" => [-1.0, 1.0]}
      },
      %{
        "name" => "ground clearance",
        "value" => 0.2,
        "tolerance" => 1.0,
        "measure" => %{
          "ground_clearance" => %{"without" => ~w(front_right_wheel front_left_wheel rear_right_wheel rear_left_wheel)}
        }
      }
    ]
  }

  test "the references of priv/references: each number of each is in its tolerance" do
    for ref <- References.all(), r <- References.run(ref), do: assert(r["ok"], "#{ref["name"]}: #{inspect(r)}")
    assert References.fetch("no such thing") == :error
    assert {:ok, %{"title" => "Surly Long Haul Trucker" <> _}} = References.fetch("surly_long_haul_trucker_26_54")
    assert capture_io(fn -> Mix.Tasks.World.References.run(["surly_long_haul_trucker_26_54"]) end) =~ "wheelbase"
    refute References.__mix_recompile__?()
  end

  test "the measures of a reference: each kind, with the people of the node" do
    for ref <- [@bicycle, @car],
        r <- References.run(ref, workers: 4),
        do: assert(r["ok"], "#{ref["name"]}: #{inspect(r)}")
  end

  test "the bill of quantities of a house, and a number out of its tolerance in the report" do
    {:ok, job} = World.Orders.job(%{"blueprint" => "tube_house", "options" => %{"floors" => 1}}, "far")
    bricks = World.Measure.takeoff(job.drawing)["brick"]

    house = %{
      "name" => "house_of_world",
      "title" => "A house of World",
      "level" => "far",
      "order" => %{"blueprint" => "tube_house", "options" => %{"floors" => 1}},
      "numbers" => [
        %{"name" => "bricks", "value" => bricks, "measure" => %{"takeoff" => "brick"}},
        %{"name" => "stone", "value" => 3, "measure" => %{"takeoff" => "stone"}}
      ]
    }

    out =
      capture_io(fn ->
        assert_raise Mix.Error, ~r/house_of_world: stone/, fn -> Mix.Tasks.World.References.report([house]) end
      end)

    assert out =~ "bricks" and out =~ "! stone"
    assert capture_io(fn -> Mix.Tasks.World.References.run([]) end) |> is_binary()
    assert_raise Mix.Error, ~r/No reference nope/, fn -> Mix.Tasks.World.References.run(["nope"]) end
  end
end
