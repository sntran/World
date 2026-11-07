defmodule World.BuildSpecTest do
  # The model checks of specs/Build.tla, with the native checker of Accord.
  use ExUnit.Case, async: true

  alias Accord.TLA.Checker

  @model Path.expand("../../specs/MCBuild.tla", __DIR__)

  test "in the small model, each invariant holds and each construction is done in the end" do
    assert {:ok, %{distinct_states: states}} = Checker.check(@model)
    assert states > 100
  end

  test "in the fault model of a task that starts again, the checker finds a task made again" do
    assert {:error, %{kind: :invariant, property: "MadeOnce"}, _} =
             Checker.check(@model, config: Path.rootname(@model) <> "Fault.cfg")
  end

  test "in the fault model of a task that starts in a pause, the checker finds work that was not in hand" do
    assert {:error, %{kind: :invariant, property: "QuietPause"}, _} =
             Checker.check(@model, config: Path.rootname(@model) <> "Pause.cfg")
  end

  test "in the fault model of a change that forgets a task, the checker finds a task that nobody makes" do
    assert {:error, %{kind: :invariant, property: "KeepsWhatIsSame"}, _} =
             Checker.check(@model, config: Path.rootname(@model) <> "Keep.cfg")
  end

  test "in the fault model of a busy person that can be hired, the checker finds a person at the wrong construction" do
    assert {:error, %{kind: :invariant, property: "OnePlace"}, _} =
             Checker.check(@model, config: Path.rootname(@model) <> "Hire.cfg")
  end
end
