defmodule World.OrderSpecTest do
  # The model checks of specs/Order.tla, with the native checker of Accord.
  use ExUnit.Case, async: true

  alias Accord.TLA.Checker

  @model Path.expand("../../specs/MCOrder.tla", __DIR__)

  test "in the small model, each invariant holds and each order is delivered in the end" do
    assert {:ok, %{distinct_states: states}} = Checker.check(@model)
    assert states > 10_000
  end

  test "in the fault model, the checker finds two workers on one task" do
    assert {:error, %{kind: :invariant, property: "OneWorkerOneTask"}, _} =
             Checker.check(@model, config: Path.rootname(@model) <> "Fault.cfg")
  end

  test "with a warehouse too small for the files of the model, the checker finds the dead end" do
    assert {:error, %{kind: :deadlock}, _} = Checker.check(@model, config: Path.rootname(@model) <> "Small.cfg")
  end
end
