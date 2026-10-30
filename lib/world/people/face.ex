defmodule World.People.Face do
  @moduledoc """
  The mouth of a person for speech: the 15 visemes of the standard of
  Meta (the names `viseme_sil` to `viseme_U`, as the tools of lip sync
  use them). Each viseme is a mix of the units of the expressions of the
  mouth of MakeHuman (CC0, `World.People.Data.expressions/0`), and each unit a
  mix of its targets for the three origins, by the origin of the person.
  The mixes are a guess from the shapes of the mouth for each sound, not
  a measurement.

  | Viseme | Sounds | The mix |
  |---|---|---|
  | `sil` | silence | none |
  | `PP` | p, b, m | the lips pressed |
  | `FF` | f, v | the lower lip up to the upper teeth |
  | `TH` | th | the mouth a little open, the lips apart |
  | `DD` | t, d | a little open, the lips back a little |
  | `kk` | k, g | more open |
  | `CH` | ch, j, sh | the lips forward, a little open |
  | `SS` | s, z | the lips back, the teeth close |
  | `nn` | n, l | a little open |
  | `RR` | r | the lips forward and round |
  | `aa` | a | open wide |
  | `E` | e | half open, the lips back |
  | `I` | i | a little open, the lips back wide |
  | `O` | o | open, the lips round |
  | `U` | u | the lips round and forward |
  """
  alias World.People.Data

  @visemes [
    {"sil", %{}},
    {"PP", %{"compression" => 1.0}},
    {"FF", %{"open" => 0.1, "elevation" => 0.4, "depression-retraction" => 0.4}},
    {"TH", %{"open" => 0.25, "parling" => 0.4}},
    {"DD", %{"open" => 0.3, "retraction" => 0.2, "parling" => 0.2}},
    {"kk", %{"open" => 0.45, "retraction" => 0.15}},
    {"CH", %{"protusion" => 0.6, "open" => 0.2, "parling" => 0.3}},
    {"SS", %{"retraction" => 0.6, "open" => 0.1, "parling" => 0.3}},
    {"nn", %{"open" => 0.25, "retraction" => 0.1}},
    {"RR", %{"protusion" => 0.4, "pursing" => 0.3, "open" => 0.2}},
    {"aa", %{"open" => 1.0, "parling" => 0.3}},
    {"E", %{"open" => 0.5, "retraction" => 0.5}},
    {"I", %{"open" => 0.3, "retraction" => 0.7, "parling" => 0.2}},
    {"O", %{"open" => 0.6, "pursing" => 0.6}},
    {"U", %{"pursing" => 0.9, "protusion" => 0.3}}
  ]

  @doc "The names of the visemes, in the order of the standard."
  def names, do: for({n, _} <- @visemes, do: "viseme_" <> n)

  @doc """
  The visemes of a person of the origins `race` (a map of "african",
  "asian", "caucasian" to a weight): a list of `{name, moves}`, the moves
  a map of a point of the base mesh to `{dx, dy, dz}` (in the units of
  MakeHuman).
  """
  def visemes(race) do
    total = race |> Map.values() |> Enum.sum()

    unit = fn u ->
      for {r, w} <- race, {i, d} <- Data.expression("units/#{r}/mouth-#{u}"), reduce: %{} do
        acc -> Map.update(acc, i, scale(d, w / total), &add(&1, scale(d, w / total)))
      end
    end

    for {name, mix} <- @visemes do
      moves =
        for {u, k} <- mix, {i, d} <- unit.(u), reduce: %{} do
          acc -> Map.update(acc, i, scale(d, k), &add(&1, scale(d, k)))
        end

      {"viseme_" <> name, moves}
    end
  end

  defp scale({x, y, z}, k), do: {x * k, y * k, z * k}
  defp add({a, b, c}, {x, y, z}), do: {a + x, b + y, c + z}
end
