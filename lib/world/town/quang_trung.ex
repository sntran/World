defmodule World.Town.QuangTrung do
  @moduledoc """
  The street Quang Trung of Vũng Tàu (the street of the Front Beach) as
  it is, from its survey (`priv/surveys/quang_trung.json`;
  `docs/plans/0018-quang-trung-street.md`).

  The first part is the block of the numbers 4 to 26, between the
  office of the port at number 2 and the corner of Nguyễn Trãi: a row of
  bars, restaurants and shops, 70 m long. The survey gives the order,
  the numbers and the names of its lots, and the corner house (three
  storeys, white). The rules of `World.Town.House` make each other
  choice from the seed: no photo shows each lot.
  """

  alias World.Town.{Street, Survey}

  # The seed of the choices that the survey does not have.
  @seed 26
  # The street between the fronts and the park: two roads of 10 m with a median (m, from photos).
  @road 23.0
  # The sidewalk of the side of the town (m, from a photo from the air).
  @sidewalk 5.5

  @sources [
    "The block of the numbers 4 to 26 of the street Quang Trung, Vũng Tàu, from its survey (priv/surveys/quang_trung.json, 2026-11-14). The order, the numbers and the uses of the lots are from addresses and from OpenStreetMap (© OpenStreetMap contributors, ODbL). The length of the block (70 m) and its depth (20 m) are from the Microsoft building footprints (ODbL).",
    "A guess, from the seed: the width of each lot (the mean, 5.8 m), its storeys, its roof, its family and its colors. No photo shows each lot. The corner house (24-26) has three storeys and is white (photos of 2014 and 2021, Wikimedia Commons). A sign has no words."
  ]

  @doc "The plan of the block of the numbers 4 to 26: 12 lots (two buildings are on two lots)."
  def plan do
    Street.plan(%{
      "seed" => @seed,
      "road" => @road,
      "sidewalk" => @sidewalk,
      "families" => [["old", 1], ["steel", 1]],
      "lots" => Survey.lots(Survey.rows("quang_trung", "QT-T02", "QT-T11"))
    })
  end

  @doc """
  The drawings of the block, from the south to the north: `{name,
  drawing}`, four lots each (a drawing has 16 parts with an image at the
  most).
  """
  def drawings do
    plan = plan()

    for {only, name} <- [{1..4, "quang_trung_4_10"}, {5..8, "quang_trung_12_18"}, {9..12, "quang_trung_20_26"}] do
      {name, Street.drawing(plan, only: only, name: name, sources: @sources)}
    end
  end
end
