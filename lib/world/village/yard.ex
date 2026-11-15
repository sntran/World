defmodule World.Village.Yard do
  @moduledoc """
  The things of the yard and of the lanes of a village of old Việt Nam,
  each from its kind (`docs/plans/0019-world-serves-the-projects.md`,
  7.1; for Tre): a round well of brick, a fence of bamboo, the gate of
  the village, a haystack round its pole, a bridge of bamboo poles, a
  large jar for water.

  `drawing/1` gives a model of one part from edits
  (`World.Skills.Sculpt`). The middle of the thing is at x = 0 and
  y = 0, and it stands on z = 0. A fence and a bridge go along x.

  The sizes are common sizes, as a guess: a project gives the photos
  and the sizes of a real thing in a drawing of its own.
  """

  alias World.Town.Wall

  @bamboo %{"roughness" => 0.75, "surface" => %{"kind" => "wood", "scale" => 0.02}}
  @straw %{"roughness" => 0.95, "surface" => %{"kind" => "hair", "scale" => 0.03}}
  @brick %{"roughness" => 0.9, "surface" => %{"kind" => "stone", "scale" => 0.08}}
  @stone %{"roughness" => 0.9, "surface" => %{"kind" => "stone", "scale" => 0.2}}
  @along_x %{"axis" => [1, 0, 0], "up" => [0, 0, 1]}

  # Each kind: its longest size (m), the color of its main part, the cells at the near level (m), and the
  # budgets of triangles of its three levels.
  @kinds %{
    "well" => {2.8, "#a5673f", 0.03, [5_000, 1_500, 300]},
    "fence" => {4.0, "#b89a55", 0.012, [9_000, 1_200, 200]},
    "gate" => {5.0, "#b0563a", 0.04, [6_000, 1_800, 300]},
    "haystack" => {3.2, "#cfae5c", 0.04, [4_000, 1_200, 250]},
    "bridge" => {6.0, "#b89a55", 0.02, [5_000, 1_200, 250]},
    "jar" => {0.85, "#6e4630", 0.012, [3_000, 900, 200]}
  }

  @doc "The kinds of a thing of a village."
  def kinds, do: @kinds |> Map.keys() |> Enum.sort()

  @doc """
  The request with each choice made. A key that has a value keeps it; a
  value that is not possible raises an `ArgumentError`.

    * `kind`: one of `kinds/0`.
    * `name` (small letters, digits and `_`) and `sources` (lines of
      text).
    * `length`: the length of a fence or of a bridge along x, 1 to 20 m
      (4 m for a fence, 6 m for a bridge).
    * `color`: the color of the main part (the brick of a well or of a
      gate, the bamboo, the straw, the glaze of a jar).
  """
  def request(opts \\ %{}) do
    need(is_map(opts), "the request of a thing of a village is a map")

    case Map.keys(opts) -- ~w(kind name sources length color) do
      [] ->
        :ok

      [key | _] ->
        raise(
          ArgumentError,
          "a thing of a village has no key #{inspect(key)}: its keys are kind, name, sources, length, color"
        )
    end

    kind = Map.get(opts, "kind", "well")
    need(is_map_key(@kinds, kind), "the kind of a thing of a village is one of #{Enum.join(kinds(), ", ")}")
    {long, color, _, _} = @kinds[kind]
    name = Map.get(opts, "name", kind)

    need(
      is_binary(name) and name =~ ~r/^[a-z][a-z0-9_]*$/,
      "the name of a thing of a village has small letters, digits and _"
    )

    sources = Map.get(opts, "sources", [])
    need(is_list(sources) and Enum.all?(sources, &is_binary/1), "the sources of a thing of a village are lines of text")
    # (Only a fence and a bridge have a length that a request changes.)
    length = if kind in ~w(fence bridge), do: Map.get(opts, "length", long), else: long

    need(
      is_number(length) and (kind not in ~w(fence bridge) or (length >= 1 and length <= 20)),
      "the length of a fence or of a bridge is from 1 m to 20 m"
    )

    color = Map.get(opts, "color", color)

    need(
      is_binary(color) and color =~ ~r/^#[0-9a-f]{6}$/,
      "the color of a thing of a village is as #a1b2c3 (small letters)"
    )

    %{"kind" => kind, "name" => name, "sources" => sources, "length" => length * 1.0, "color" => color}
  end

  defp need(true, _text), do: :ok
  defp need(false, text), do: raise(ArgumentError, text)

  @doc """
  The drawing of the thing of a request (`request/1`): one part from
  edits. The extras have the request (`village_thing`).
  """
  def drawing(request \\ %{}) do
    r = request(request)
    {_, _, cell, budget} = @kinds[r["kind"]]
    levels = fn list -> Map.new(Enum.zip(~w(near mid far), list)) end

    data = %{
      "edits" => Enum.map(edits(r["kind"], r["length"], r["color"]), &Map.put(&1, "material", "part_01")),
      "cells" => levels.([cell, r4(cell * 2.5), r4(cell * 5)]),
      "budget" => levels.(budget),
      "bake" => levels.(Enum.zip_with(budget, [1024, 512, 128], &image/2)),
      "dirt" => 0.3,
      "wear" => 0.2
    }

    %{
      "name" => r["name"],
      # (A thing of a yard is made where it stands.)
      "kind" => "building",
      "sources" => r["sources"],
      "materials" => %{"part_01" => %{"color" => "#ffffff", "roughness" => 0.85, "metalness" => 0.0}},
      # (The bed of the canal holds the poles of a bridge: its site holds it.)
      "extras" => Map.merge(%{"village_thing" => r}, if(r["kind"] == "bridge", do: %{"site" => true}, else: %{})),
      "nodes" => [%{"name" => "#{r["name"]}_than", "skill" => %{"sculpt" => data}}]
    }
  end

  defp image(budget, side),
    do: Enum.find([64, 128, 256, 512, 1024, 2048, 4096], &(&1 >= max(side, World.Sculpt.Bake.least(budget))))

  # --- The edits of each kind ---------------------------------------------------------

  defp e(shape, size, at, color, more), do: Wall.edit(shape, Enum.map(size, &r4/1), Enum.map(at, &r4/1), color, more)

  # A round well: a low platform of stone, a wall of brick 70 cm high with a lighter curb, and the water.
  defp edits("well", _length, color) do
    [
      e("cylinder", [1.4, 0.05], [0, 0, 0.05], "#8f8a7d", @stone),
      e("cylinder", [0.9, 0.35], [0, 0, 0.45], color, @brick),
      e("cylinder", [0.92, 0.04], [0, 0, 0.78], "#b9b2a0", Map.put(@stone, "mode", "paint")),
      e("cylinder", [0.7, 0.33], [0, 0, 0.5], "#6b5a48", %{"mode" => "subtract"}),
      e("cylinder", [0.7, 0.05], [0, 0, 0.17], "#2f4a44", %{"mode" => "paint", "roughness" => 0.1})
    ]
  end

  # A fence of bamboo: a post each meter, two rails, and thin upright slats in front of the rails. At the
  # mid and far levels the slats are one panel.
  defp edits("fence", long, color) do
    posts = round(long)

    posts =
      for i <- 0..posts,
          do: e("cylinder", [0.035, 0.65], [-long / 2 + long * i / posts, 0, 0.65], shade(color, 0.85), @bamboo)

    rails = for z <- [0.35, 0.95], do: e("cylinder", [0.022, long / 2], [0, 0, z], color, Map.merge(@bamboo, @along_x))
    count = round(long / 0.11)

    slats =
      for i <- 0..count do
        x = -long / 2 + long * i / count
        e("cylinder", [0.012, 0.55], [x, 0.035, 0.6], color, Map.put(@bamboo, "levels", ["near"]))
      end

    panel = [
      e("box", [long / 2, 0.02, 0.5], [0, 0.035, 0.62], color, Map.put(@bamboo, "levels", ["mid"])),
      e("box", [long / 2, 0.06, 0.5], [0, 0.035, 0.62], color, Map.put(@bamboo, "levels", ["far"]))
    ]

    posts ++ rails ++ slats ++ panel
  end

  # The gate of a village: two pillars of brick with caps of stone, a beam with a red board for the name of
  # the village on each side, and a small roof of tiles with two slopes.
  defp edits("gate", _length, color) do
    pillars =
      for x <- [-1.7, 1.7],
          edit <- [
            e("box", [0.35, 0.35, 1.5], [x, 0, 1.5], color, @brick),
            e("box", [0.42, 0.42, 0.08], [x, 0, 3.08], "#b9b2a0", @stone),
            e("box", [0.42, 0.42, 0.12], [x, 0, 0.12], "#8f8a7d", @stone)
          ],
          do: edit

    pillars ++
      [
        e("box", [2.3, 0.3, 0.3], [0, 0, 3.45], "#d8cfb8", %{"roughness" => 0.9}),
        e("box", [1.2, 0.5, 0.18], [0, 0, 3.45], "#7a2a22", %{"mode" => "paint", "roughness" => 0.6}),
        Wall.outline(
          [[-0.8, 3.75], [0.8, 3.75], [0, 4.25]],
          5.0,
          [0, 0, 0],
          "#8d4a35",
          Map.put(@along_x, "roughness", 0.8)
        ),
        e("box", [2.55, 0.06, 0.06], [0, 0, 4.25], "#6f3a2a", %{"roughness" => 0.8})
      ]
  end

  # A haystack: straw round a pole, wide at the middle and round at the top.
  defp edits("haystack", _length, color) do
    [
      e("cylinder", [0.06, 2.1], [0, 0, 2.1], "#7a5a3a", @bamboo),
      e("cone", [1.3, 1.55, 0.6], [0, 0, 0.6], color, @straw),
      e("cone", [1.55, 0.6, 1.0], [0, 0, 2.25], color, Map.put(@straw, "blend", 0.1)),
      e("ellipsoid", [0.7, 0.7, 0.5], [0, 0, 3.2], shade(color, 0.92), Map.put(@straw, "blend", 0.2))
    ]
  end

  # A bridge of bamboo over a canal (cầu khỉ): one pole to walk on, a rail for the hand, and two trestles of
  # crossed poles that stand in the water.
  defp edits("bridge", long, color) do
    trestles =
      for x <- [-long / 3, long / 3],
          {from, to} <- [{[x, -0.7, 0.0], [x, 0.5, 2.2]}, {[x, 0.7, 0.0], [x, -0.25, 1.6]}],
          do: Wall.tube([Enum.map(from, &r4/1), Enum.map(to, &r4/1)], [0.04, 0.035], shade(color, 0.85), @bamboo)

    [
      e("cylinder", [0.06, long / 2], [0, 0, 1.2], color, Map.merge(@bamboo, @along_x)),
      e("cylinder", [0.03, long / 2], [0, 0.42, 2.05], color, Map.merge(@bamboo, @along_x))
      | trestles
    ]
  end

  # A large jar for water (chum): a round body of glazed clay with a thick lip, open at the top, with water.
  defp edits("jar", _length, color) do
    glaze = %{"roughness" => 0.35}

    [
      e("ellipsoid", [0.4, 0.4, 0.44], [0, 0, 0.4], color, glaze),
      # (A flat foot, and a flat top for the lip.)
      e("box", [0.5, 0.5, 0.1], [0, 0, -0.1], color, %{"mode" => "subtract"}),
      e("box", [0.5, 0.5, 0.1], [0, 0, 0.84], color, %{"mode" => "subtract"}),
      e("cylinder", [0.27, 0.03], [0, 0, 0.74], shade(color, 0.8), glaze),
      e("cylinder", [0.2, 0.25], [0, 0, 0.6], shade(color, 0.6), %{"mode" => "subtract"}),
      e("cylinder", [0.2, 0.03], [0, 0, 0.36], "#2f4a44", %{"mode" => "paint", "roughness" => 0.1})
    ]
  end

  defp r4(v), do: Wall.r4(v)

  # A color, darker by a part.
  defp shade("#" <> hex, part) do
    <<r::8, g::8, b::8>> = Base.decode16!(hex, case: :lower)
    "#" <> Base.encode16(<<round(r * part), round(g * part), round(b * part)>>, case: :lower)
  end
end
