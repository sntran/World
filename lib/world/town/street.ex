defmodule World.Town.Street do
  @moduledoc """
  One side of a street of Vũng Tàu from a request: a row of lots, each
  with the request of its house (`World.Town.House`), and the drawing of
  the row on its sidewalk (`docs/plans/0016-a-house-and-a-street.md`).

  The work is in two steps, as on a real street:

  1. **The plan of the street** (`plan/1`) cuts the length of the street
     into lots, and makes for each lot the choices that its neighbors
     must know: its width, its type, its family, its color. The houses
     stand wall to wall, so each side of a house is `shared`; the two
     ends of the row are `free`. A house can take the family of the
     house before it (streets were built in groups), and it does not
     take the color of the house before it.
  2. **Each house** is then made from its request only: the houses do
     not wait for each other, and the same plan gives the same street
     in any order of the work.

  A choice is from the seed of the street and the number of the lot.
  The shares of the types and of the widths are from adverts of houses
  in Vũng Tàu and from photos of its streets (the plan, section 3): no
  count of a real street is public.
  """

  alias World.Town.House

  # The shares of the types on a common street, of the families, and of the widths of the lots (m).
  @types [{"pho2_flat", 45}, {"pho3", 26}, {"cap4", 19}, {"pho2_tile", 10}]
  @families [{"old", 4}, {"steel", 4}, {"modern", 2}]
  @widths [{5.0, 45}, {4.0, 25}, {6.0, 12}, {4.5, 10}, {5.5, 8}]
  # A house takes the family of the house before it this often.
  @copy 0.3
  # The sidewalk of a road of 13 m to 15 m, its curb, and the part of the road in the drawing (m).
  @sidewalk 3.0
  @curb 0.18
  @lane 3.5

  @doc """
  The plan of one side of a street: `%{"seed", "road", "lots"}`. Each lot
  is the request of its house (`World.Town.House.request/1`) with `at`,
  the place of the middle of its front along the street (m, from the
  start of the row).

  The options: `seed`; `road` (the width of the road, 13 m by default:
  it gives the reach of the balconies); `count` (the lots, 5 by
  default) or `length` (the row is not longer than this, m); `types`,
  `families` and `widths` (each a list of `[value, weight]`, in the
  place of the shares of a common street); `depth` (of each house).
  """
  def plan(opts \\ %{}) do
    unless is_map(opts), do: raise(ArgumentError, "the request of a street is a map")
    seed = Map.get(opts, "seed", 1)
    road = Map.get(opts, "road", 13.0)

    shares = fn key, default ->
      for([value, weight] <- Map.get(opts, key, []), do: {value, weight}) |> then(&if(&1 == [], do: default, else: &1))
    end

    {types, families, widths} = {shares.("types", @types), shares.("families", @families), shares.("widths", @widths)}

    count =
      case opts do
        %{"length" => length} when is_number(length) -> max(floor(length / 5.0), 1)
        _ -> Map.get(opts, "count", 5)
      end

    unless is_integer(count) and count in 1..200, do: raise(ArgumentError, "a street has from 1 to 200 lots")

    {lots, _} =
      Enum.map_reduce(1..count, {0.0, nil}, fn i, {x, before} ->
        width = pick(seed, {:width, i}, widths)

        family =
          if before && unit(seed, {:copy, i}) < @copy, do: before["family"], else: pick(seed, {:family, i}, families)

        base = %{
          "type" => pick(seed, {:type, i}, types),
          "family" => family,
          "width" => width,
          "depth" => Map.get(opts, "depth", 16.0),
          "road" => road,
          "left" => if(i == 1, do: "free", else: "shared"),
          "right" => if(i == count, do: "free", else: "shared")
        }

        # (Not the color of the house before it: the next seed gives another one.)
        request =
          :erlang.phash2({seed, i}, 1_000_000)
          |> Stream.iterate(&(&1 + 1))
          |> Stream.map(&House.request(Map.put(base, "seed", &1)))
          |> Enum.find(&(before == nil or &1["wall"] != before["wall"]))

        lot = Map.put(request, "at", Float.round(x + width / 2, 4))
        {lot, {x + width, lot}}
      end)

    %{"seed" => seed, "road" => road, "lots" => lots}
  end

  @doc """
  The drawing of a plan: each house at its place (its parts are parts of
  the drawing), and the ground in front of the row (the sidewalk with
  its tiles, the curb, one lane of the road, and a pole at a wall
  between two houses). A drawing has 16 parts with an image at the
  most: 5 houses and the ground.
  """
  def drawing(%{"lots" => lots} = plan, opts \\ []) when length(lots) <= 5 do
    name = Keyword.get(opts, :name, "pho_#{plan["seed"]}")
    long = lots |> List.last() |> then(&(&1["at"] + &1["width"] / 2))

    houses =
      for {lot, i} <- Enum.with_index(lots) do
        house =
          House.drawing(Map.delete(lot, "at"), at: lot["at"] - long / 2, name: "#{name}_nha_#{i + 1}", image: 1024)

        for {node, k} <- Enum.with_index(house["nodes"]), do: role(node, 3 * i + k + 1)
      end

    ground = %{
      "name" => "#{name}_duong",
      "skill" => %{
        "sculpt" => %{
          "edits" => ground(lots, long),
          "dirt" => 0.5,
          "wear" => 0.2,
          "cells" => %{"near" => 0.06, "mid" => 0.12, "far" => 0.3},
          "budget" => %{"near" => 3_000, "mid" => 600, "far" => 100},
          "bake" => %{"near" => 1024, "mid" => 256, "far" => 64}
        }
      }
    }

    nodes = Enum.concat(houses) ++ [role(ground, 3 * length(lots) + 1)]

    %{
      "name" => name,
      "kind" => "house",
      "sources" => [
        "One side of a street of Vũng Tàu from rules (plan 0016): #{length(lots)} houses wall to wall on a road of #{plan["road"]} m, the seed #{plan["seed"]}. It is no real street. The plan of the street makes the choices that neighbors share; each house is then made from its own request (World.Town.House).",
        "The shares of the types and of the widths of the lots are from adverts of houses in Vũng Tàu and from photos of its streets; no count of a real street is public. The sidewalk of 3 m and its tiles of 0.4 m are from photos; the height of the curb and the pole are a guess."
      ],
      "materials" =>
        Map.new(nodes, fn node ->
          {node["skill"]["sculpt"]["edits"] |> hd() |> Map.fetch!("material"),
           %{"color" => "#ffffff", "roughness" => 0.85, "metalness" => 0.0}}
        end),
      "extras" => %{"street" => plan},
      "nodes" => nodes
    }
  end

  # A part with the role of its number: each part of a drawing has its own image.
  defp role(node, n) do
    role = "part_#{String.pad_leading(Integer.to_string(n), 2, "0")}"
    swap = fn edits -> Enum.map(edits, &Map.put(&1, "material", role)) end

    update_in(node, ["skill", "sculpt"], fn data ->
      data = Map.update!(data, "edits", swap)

      if data["details"],
        do: Map.update!(data, "details", &Enum.map(&1, fn d -> Map.update!(d, "edits", swap) end)),
        else: data
    end)
  end

  # The ground in front of a row: the sidewalk of tiles (its top at the
  # height 0 of the houses), the curb, a lane of the road, and a pole of
  # concrete at the wall between the first two houses.
  defp ground(lots, long) do
    half = long / 2 + 0.5
    tile = %{"mode" => "paint", "blend" => 0.006, "raise" => -0.004}
    pole = (lots |> hd() |> then(&(&1["at"] + &1["width"] / 2))) - long / 2

    [
      e("box", [half, @sidewalk / 2, 0.1], [0, @sidewalk / 2, -0.1], "#b9a78e", %{
        "roughness" => 0.8,
        "surface" => %{"kind" => "concrete", "scale" => 0.03}
      }),
      # The joints of the tiles, each 0.4 m, along the street and across it.
      e(
        "box",
        [half, 0.006, 0.02],
        [0, 0.4, 0],
        "#8d7f6c",
        Map.put(tile, "repeat", %{"count" => floor(@sidewalk / 0.4) - 1, "move" => [0, 0.4, 0]})
      ),
      e(
        "box",
        [0.006, @sidewalk / 2, 0.02],
        [-half + 0.4, @sidewalk / 2, 0],
        "#8d7f6c",
        Map.put(tile, "repeat", %{"count" => floor(2 * half / 0.4) - 1, "move" => [0.4, 0, 0]})
      ),
      e("box", [half, 0.09, (0.1 + @curb) / 2], [0, @sidewalk + 0.09, -(0.1 + @curb) / 2], "#a9a59c", %{
        "roughness" => 0.85,
        "surface" => %{"kind" => "concrete", "scale" => 0.05}
      }),
      e("box", [half, @lane / 2, 0.1], [0, @sidewalk + 0.18 + @lane / 2, -@curb - 0.1], "#414347", %{
        "roughness" => 0.95,
        "surface" => %{"kind" => "concrete", "scale" => 0.02}
      }),
      # The pole: 8.5 m over the sidewalk, with a cross arm.
      e("cone", [0.15, 0.1, 4.25], [pole, @sidewalk - 0.45, 4.25], "#a7a59d", %{
        "roughness" => 0.9,
        "surface" => %{"kind" => "concrete", "scale" => 0.05}
      }),
      e("box", [0.7, 0.04, 0.04], [pole, @sidewalk - 0.45, 8.0], "#8f8d86", %{"roughness" => 0.9})
    ]
  end

  defp e(shape, size, at, color, more) do
    edit = Map.merge(%{"shape" => shape, "size" => round4(size), "at" => round4(at), "color" => color}, more)

    case edit do
      %{"raise" => h} -> Map.put(edit, "blend", max(Map.get(edit, "blend", 0), abs(h)))
      _ -> edit
    end
  end

  defp round4(list), do: Enum.map(list, &if(is_integer(&1), do: &1, else: Float.round(&1 * 1.0, 4)))

  # A number from 0 to 1 for a seed and a key, and a choice by weights.
  defp unit(seed, key), do: :erlang.phash2({seed, key}, 1_000_000) / 1_000_000

  defp pick(seed, key, options) do
    total = options |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    at = unit(seed, key) * total

    Enum.reduce_while(options, 0, fn {value, weight}, sum ->
      if at < sum + weight, do: {:halt, value}, else: {:cont, sum + weight}
    end)
  end
end
