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

  The face shapes of the standard of Apple ARKit (the names, as
  `eyeBlinkLeft`; the left is the left of the person): 30 of its 52
  shapes, each a mix of the units of the face of MakeHuman (the eyes,
  the brows, the nose and the mouth). A unit of the mouth has the two
  sides; for a shape of one side, the unit moves the points of that side
  only (the moves fade over 1 cm at the middle of the face). The mixes
  are a guess, not a measurement.

  | Shape | The mix |
  |---|---|
  | `eyeBlink`, `eyeSquint`, `eyeWide` (each side) | the eye closed, narrow, open wide |
  | `browDown`, `browOuterUp` (each side), `browInnerUp` | the brow down, its outer end up, the inner ends up |
  | `cheekSquint` (each side) | the eye narrow (0.4) and the corner of the mouth up (0.3) |
  | `noseSneer` (each side) | the side of the nose up |
  | `jawOpen`, `mouthFunnel`, `mouthPucker` | the mouth open; the lips forward (0.8) and a little open (0.15); the lips round |
  | `mouthSmile`, `mouthFrown`, `mouthStretch`, `mouthDimple`, `mouthPress`, `mouthUpperUp` (each side) | the corner up and back; the corner down; the lips back; the corner back and down; the lips pressed; the upper lip up and back |

  The other 22 shapes of ARKit have no unit in MakeHuman: the looks of
  the eyes (an app turns the eyes), the jaw to the front and to the
  sides, the mouth to the sides, the rolls and the shrugs of the lips,
  `mouthClose`, `mouthLowerDown`, `cheekPuff` and `tongueOut`.
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

  # The face shapes: a name to a list of {unit, weight} or {unit, weight,
  # side}; in a shape of each side, SIDE is "left" or "right".
  @sided [
    {"eyeBlink", [{"eye-SIDE-closure", 1.0}]},
    {"eyeSquint", [{"eye-SIDE-slit", 1.0}]},
    {"eyeWide", [{"eye-SIDE-opened-up", 1.0}]},
    {"browDown", [{"eyebrows-SIDE-down", 1.0}]},
    {"browOuterUp", [{"eyebrows-SIDE-extern-up", 1.0}]},
    {"cheekSquint", [{"eye-SIDE-slit", 0.4}, {"mouth-corner-puller", 0.3, "SIDE"}]},
    {"noseSneer", [{"nose-SIDE-elevation", 1.0}]},
    {"mouthSmile", [{"mouth-corner-puller", 1.0, "SIDE"}]},
    {"mouthFrown", [{"mouth-depression", 1.0, "SIDE"}]},
    {"mouthStretch", [{"mouth-retraction", 1.0, "SIDE"}]},
    {"mouthDimple", [{"mouth-depression-retraction", 1.0, "SIDE"}]},
    {"mouthPress", [{"mouth-compression", 1.0, "SIDE"}]},
    {"mouthUpperUp", [{"mouth-upward-retraction", 1.0, "SIDE"}]}
  ]

  @both [
    {"browInnerUp", [{"eyebrows-left-inner-up", 1.0}, {"eyebrows-right-inner-up", 1.0}]},
    {"jawOpen", [{"mouth-open", 1.0}]},
    {"mouthFunnel", [{"mouth-protusion", 0.8}, {"mouth-open", 0.15}]},
    {"mouthPucker", [{"mouth-pursing", 1.0}]}
  ]

  @doc "The names of the visemes, in the order of the standard."
  def names, do: for({n, _} <- @visemes, do: "viseme_" <> n)

  @doc "The names of the face shapes of ARKit that a person has."
  def shape_names, do: Enum.map(shape_mixes(), &elem(&1, 0))

  defp shape_mixes do
    for {name, mix} <- @sided, {side, s} <- [{"Left", "left"}, {"Right", "right"}] do
      {name <> side, for(unit <- mix, do: side_of(unit, s))}
    end ++ @both
  end

  defp side_of({u, k}, s), do: {String.replace(u, "SIDE", s), k}
  defp side_of({u, k, "SIDE"}, s), do: {u, k, s}

  @doc """
  The face shapes of ARKit of a person of the origins `race` (as
  `visemes/1`): a list of `{name, moves}`; with `names`, only these.
  """
  def shapes(race, names \\ nil),
    do: for({name, mix} <- shape_mixes(), names == nil or name in names, do: {name, mix(race, mix)})

  @doc """
  The face of a person at rest (`World.People.Human`): `"relaxed"` (the
  eyelids 0.25 closed and a hint of a smile, 0.15 of each side),
  `"neutral"` (the face of MakeHuman), or a map of the names of the face
  shapes to their weights. A map of a shape to its weight.
  """
  def rest("relaxed"),
    do: %{"eyeBlinkLeft" => 0.25, "eyeBlinkRight" => 0.25, "mouthSmileLeft" => 0.15, "mouthSmileRight" => 0.15}

  def rest("neutral"), do: %{}
  def rest(%{} = mix), do: mix

  @doc """
  The visemes of a person of the origins `race` (a map of "african",
  "asian", "caucasian" to a weight): a list of `{name, moves}`, the moves
  a map of a point of the base mesh to `{dx, dy, dz}` (in the units of
  MakeHuman).
  """
  def visemes(race) do
    for {name, mix} <- @visemes, do: {"viseme_" <> name, mix(race, for({u, k} <- mix, do: {"mouth-" <> u, k}))}
  end

  # The moves of a mix of units: each unit a mix of its targets for the
  # origins; a unit with a side moves the points of that side (the left
  # of the person is +x in MakeHuman; 0.05 units is 5 mm).
  defp mix(race, units) do
    total = race |> Map.values() |> Enum.sum()
    points = Data.base().points

    for unit <- units,
        {u, k, side} = with({u, k} <- unit, do: {u, k, nil}),
        {r, w} <- race,
        {i, d} <- Data.expression("units/#{r}/#{u}"),
        f = k * w / total * part(side, elem(elem(points, i), 0)),
        f != 0.0,
        reduce: %{} do
      acc -> Map.update(acc, i, scale(d, f), &add(&1, scale(d, f)))
    end
  end

  defp part(nil, _x), do: 1.0
  defp part("left", x), do: smooth((x + 0.05) / 0.1)
  defp part("right", x), do: 1.0 - smooth((x + 0.05) / 0.1)

  defp smooth(t) do
    t = min(max(t, 0.0), 1.0)
    t * t * (3 - 2 * t)
  end

  defp scale({x, y, z}, k), do: {x * k, y * k, z * k}
  defp add({a, b, c}, {x, y, z}), do: {a + x, b + y, c + z}
end
