defmodule World.NodeSpecTest do
  # The model checks of the stream (specs/Stream.tla), of the store of the
  # log (specs/LogStore.tla) and of the census (specs/Census.tla), with the
  # native checker of Accord.
  use ExUnit.Case, async: true

  alias Accord.TLA.Checker

  @stream Path.expand("../../specs/MCStream.tla", __DIR__)
  @store Path.expand("../../specs/MCLogStore.tla", __DIR__)
  @census Path.expand("../../specs/MCCensus.tla", __DIR__)

  defp config(model, name), do: [config: Path.rootname(model) <> name <> ".cfg"]

  test "a stream that watches first, then reads the past, gives each event after its start one time, in order" do
    assert {:ok, %{distinct_states: states}} = Checker.check(@stream)
    assert states > 50
  end

  test "a stream that reads the past before it watches loses an event" do
    assert {:error, %{kind: :invariant, property: "NoGap"}, _} = Checker.check(@stream, config(@stream, "Late"))
  end

  test "a stream with no check of the id gives an event two times" do
    assert {:error, %{kind: :invariant, property: "InOrder"}, _} = Checker.check(@stream, config(@stream, "Twice"))
  end

  test "with no store, a memory too small for the past loses events" do
    assert {:error, %{kind: :invariant, property: "NoGap"}, _} = Checker.check(@stream, config(@stream, "Memory"))
  end

  test "a new log that leaves a batch of ids after the store, and puts its first id into it, never gives one id to two events" do
    assert {:ok, %{distinct_states: states}} = Checker.check(@store)
    assert states > 50
  end

  test "a new log that goes on from the last id of the store gives an id of a lost event to a new event" do
    assert {:error, %{kind: :invariant, property: "OneName"}, _} = Checker.check(@store, config(@store, "Reuse"))
  end

  test "a new log that leaves a batch of ids but does not keep its first id gives one id two times after two stops" do
    assert {:error, %{kind: :invariant, property: "OneName"}, _} = Checker.check(@store, config(@store, "Twice"))
  end

  test "constructions that give back their free people when they wait share the people of the node, and each is done" do
    assert {:ok, %{distinct_states: states}} = Checker.check(@census)
    assert states > 20
  end

  test "constructions that keep their free people wait for each other at the limit of the node" do
    assert {:error, %{kind: :deadlock}, _} = Checker.check(@census, config(@census, "Keep"))
  end

  test "a census that gives a person that works takes it from its construction" do
    assert {:error, %{kind: :invariant, property: "NoSteal"}, _} = Checker.check(@census, config(@census, "Steal"))
  end
end
