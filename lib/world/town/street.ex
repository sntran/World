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

  A real street gives its lots (`lots`, from a survey:
  `World.Town.Survey`): the plan keeps what is known of each lot, and
  the seed makes only the choices that the survey does not have.
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
  # What a lot takes from the lot before it when the two are one building.
  @same ~w(type family use wall ground rail sign awning vents roof age)

  @doc """
  The plan of one side of a street: `%{"seed", "road", "lots"}`. Each lot
  is the request of its house (`World.Town.House.request/1`) with `at`,
  the place of the middle of its front along the street (m, from the
  start of the row).

  The options: `seed`; `road` (the width of the road, 13 m by default:
  it gives the reach of the balconies); `count` (the lots, 5 by
  default) or `length` (the row is not longer than this, m); `types`,
  `families` and `widths` (each a list of `[value, weight]`, in the
  place of the shares of a common street); `depth` (of each house);
  `sidewalk` (its width, 2 m to 10 m, 3 m by default).

  With `lots` (a list of maps, 1 to 200), the row has those lots in
  their order. A lot gives what is known of it: keys of the request of
  a house (`type`, `family`, `width`, `depth`, `use`, `wall`, `sign` and
  the others), `number` and `name` (the address and the name of the
  real house: the plan keeps them), and `same` (true: the lot and the
  lot before it are one building, with the same choices). The seed
  makes each other choice.
  """
  def plan(opts \\ %{}) do
    unless is_map(opts), do: raise(ArgumentError, "the request of a street is a map")
    seed = Map.get(opts, "seed", 1)
    road = Map.get(opts, "road", 13.0)

    shares = fn key, default ->
      for([value, weight] <- Map.get(opts, key, []), do: {value, weight}) |> then(&if(&1 == [], do: default, else: &1))
    end

    {types, families, widths} = {shares.("types", @types), shares.("families", @families), shares.("widths", @widths)}

    given = Map.get(opts, "lots", [])

    unless is_list(given) and Enum.all?(given, &is_map/1),
      do: raise(ArgumentError, "the lots of a street are a list of maps")

    count =
      case opts do
        _ when given != [] -> length(given)
        %{"length" => length} when is_number(length) -> max(floor(length / 5.0), 1)
        _ -> Map.get(opts, "count", 5)
      end

    unless is_integer(count) and count in 1..200, do: raise(ArgumentError, "a street has from 1 to 200 lots")
    sidewalk = Map.get(opts, "sidewalk", @sidewalk)

    unless is_number(sidewalk) and sidewalk >= 2 and sidewalk <= 10,
      do: raise(ArgumentError, "the sidewalk of a street is from 2 m to 10 m wide")

    {lots, _} =
      Enum.map_reduce(1..count, {0.0, nil}, fn i, {x, before} ->
        known = Enum.at(given, i - 1, %{})
        # (One building on two lots: the choices of the lot before it.)
        known = if known["same"] && before, do: Map.merge(Map.take(before, @same), known), else: known
        width = Map.get(known, "width") || pick(seed, {:width, i}, widths)

        family =
          cond do
            known["family"] -> known["family"]
            before && unit(seed, {:copy, i}) < @copy -> before["family"]
            true -> pick(seed, {:family, i}, families)
          end

        base =
          Map.merge(
            %{
              "depth" => Map.get(opts, "depth", 16.0),
              "left" => if(i == 1, do: "free", else: "shared"),
              "right" => if(i == count, do: "free", else: "shared")
            },
            known
          )
          |> Map.merge(%{
            "type" => Map.get(known, "type") || pick(seed, {:type, i}, types),
            "family" => family,
            "width" => width,
            "road" => road
          })

        # (Not the color of the house before it: the next seed gives another one. A lot with its color keeps it.)
        request =
          :erlang.phash2({seed, i}, 1_000_000)
          |> Stream.iterate(&(&1 + 1))
          |> Stream.map(&House.request(Map.put(base, "seed", &1)))
          |> Enum.find(&(before == nil or known["wall"] != nil or &1["wall"] != before["wall"]))

        lot = request |> Map.merge(Map.take(known, ~w(number name))) |> Map.put("at", Float.round(x + width / 2, 4))
        {lot, {x + width, lot}}
      end)

    %{"seed" => seed, "road" => road, "sidewalk" => sidewalk * 1.0, "lots" => lots}
  end

  @doc """
  The drawing of a plan: each house at its place (its parts are parts of
  the drawing), and the ground in front of the row (the sidewalk with
  its tiles, the curb, one lane of the road, a pole at a wall between
  two houses, and the ground of the lots under the houses). A drawing has 16 parts with an image at the
  most: 5 houses and the ground. The option `only` (a range of the
  numbers of the lots, from 1) gives the drawing of a part of a long
  row: its middle is the middle of that part.

  On a sidewalk of 4.5 m or more, a parasol with a table stands in
  front of each lot with the use `bar`.
  """
  def drawing(plan, opts \\ [])

  def drawing(%{"lots" => all} = plan, opts) do
    lots = if opts[:only], do: Enum.slice(all, (opts[:only].first - 1)..(opts[:only].last - 1)//1), else: all

    unless length(lots) in 1..5,
      do: raise(ArgumentError, "a drawing of a street has from 1 to 5 lots (the option `only` gives a part of a row)")

    name = Keyword.get(opts, :name, "pho_#{plan["seed"]}")
    # (The lots of the drawing start at 0.)
    start = hd(lots)["at"] - hd(lots)["width"] / 2
    lots = for lot <- lots, do: %{lot | "at" => lot["at"] - start}
    long = lots |> List.last() |> then(&(&1["at"] + &1["width"] / 2))
    sidewalk = Map.get(plan, "sidewalk", @sidewalk)

    houses =
      for {lot, i} <- Enum.with_index(lots) do
        house =
          House.drawing(Map.drop(lot, ~w(at number name)),
            at: lot["at"] - long / 2,
            name: "#{name}_nha_#{i + 1}",
            image: 1024
          )

        for {node, k} <- Enum.with_index(house["nodes"]), do: role(node, 3 * i + k + 1)
      end

    ground = %{
      "name" => "#{name}_duong",
      "skill" => %{
        "sculpt" => %{
          "edits" => ground(lots, long, sidewalk),
          "dirt" => 0.5,
          "wear" => 0.2,
          "cells" => %{"near" => 0.06, "mid" => 0.12, "far" => 0.3},
          "budget" => %{"near" => 3_000, "mid" => 600, "far" => 100},
          "bake" => %{"near" => 1024, "mid" => 256, "far" => 64}
        }
      }
    }

    # The things on the sidewalk are thin: their own cells, the same at near and mid (a pole of 7 cm and a
    # table of 4 cm are lost with larger cells).
    things = for lot <- lots, lot["use"] == "bar", sidewalk >= 4.5, edit <- parasol(plan["seed"], lot, long), do: edit

    ground =
      if things == [],
        do: ground,
        else:
          put_in(ground, ["skill", "sculpt", "details"], [
            %{
              "edits" => things,
              "cells" => %{"near" => 0.012, "mid" => 0.012},
              "budget" => %{"near" => 1_500 * length(lots), "mid" => 500 * length(lots)},
              "levels" => ["near", "mid"]
            }
          ])

    nodes = Enum.concat(houses) ++ [role(ground, 3 * length(lots) + 1)]

    %{
      "name" => name,
      "kind" => "house",
      "sources" => [
        "One side of a street of Vũng Tàu from rules (plan 0016): #{length(lots)} houses wall to wall on a road of #{plan["road"]} m, the seed #{plan["seed"]}. It is no real street. The plan of the street makes the choices that neighbors share; each house is then made from its own request (World.Town.House).",
        "The shares of the types and of the widths of the lots are from adverts of houses in Vũng Tàu and from photos of its streets; no count of a real street is public. The sidewalk of 3 m and its tiles of 0.4 m are from photos; the height of the curb and the pole are a guess."
        | Keyword.get(opts, :sources, [])
      ],
      "materials" =>
        Map.new(nodes, fn node ->
          {node["skill"]["sculpt"]["edits"] |> hd() |> Map.fetch!("material"),
           %{"color" => "#ffffff", "roughness" => 0.85, "metalness" => 0.0}}
        end),
      "extras" => %{"street" => %{plan | "lots" => lots}},
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
  defp ground(lots, long, sidewalk) do
    half = long / 2 + 0.5
    tile = %{"mode" => "paint", "blend" => 0.006, "raise" => -0.004}
    pole = (lots |> hd() |> then(&(&1["at"] + &1["width"] / 2))) - long / 2
    deep = lots |> Enum.map(& &1["depth"]) |> Enum.max()
    # (Each part of the ground goes down to the same level: the row stands on all of it.)
    low = -(@curb + 0.2)
    slab = fn top -> {(top - low) / 2, (top + low) / 2} end
    {walk_h, walk_z} = slab.(0.0)
    {lots_h, lots_z} = slab.(-0.02)
    {road_h, road_z} = slab.(-@curb)

    [
      e("box", [half, sidewalk / 2, walk_h], [0, sidewalk / 2, walk_z], "#b9a78e", %{
        "roughness" => 0.8,
        "surface" => %{"kind" => "concrete", "scale" => 0.03}
      }),
      # The joints of the tiles, each 0.4 m, along the street and across it.
      e(
        "box",
        [half, 0.006, 0.02],
        [0, 0.4, 0],
        "#8d7f6c",
        Map.put(tile, "repeat", %{"count" => floor(sidewalk / 0.4) - 1, "move" => [0, 0.4, 0]})
      ),
      e(
        "box",
        [0.006, sidewalk / 2, 0.02],
        [-half + 0.4, sidewalk / 2, 0],
        "#8d7f6c",
        Map.put(tile, "repeat", %{"count" => floor(2 * half / 0.4) - 1, "move" => [0.4, 0, 0]})
      ),
      e("box", [half, 0.09, walk_h], [0, sidewalk + 0.09, walk_z], "#a9a59c", %{
        "roughness" => 0.85,
        "surface" => %{"kind" => "concrete", "scale" => 0.05}
      }),
      e("box", [half, @lane / 2, road_h], [0, sidewalk + 0.18 + @lane / 2, road_z], "#414347", %{
        "roughness" => 0.95,
        "surface" => %{"kind" => "concrete", "scale" => 0.02}
      }),
      # The pole: 8.5 m over the sidewalk, with a cross arm.
      e("cone", [0.15, 0.1, 4.25], [pole, sidewalk - 0.45, 4.25], "#a7a59d", %{
        "roughness" => 0.9,
        "surface" => %{"kind" => "concrete", "scale" => 0.05}
      }),
      e("box", [0.7, 0.04, 0.04], [pole, sidewalk - 0.45, 8.0], "#8f8d86", %{"roughness" => 0.9}),
      # The ground of the lots, under the houses.
      e("box", [half, (deep + 0.5) / 2, lots_h], [0, -(deep + 0.5) / 2, lots_z], "#8f8a7e", %{
        "roughness" => 0.95,
        "surface" => %{"kind" => "concrete", "scale" => 0.08}
      })
    ]
  end

  # A parasol with its table on the sidewalk in front of a bar: a pole
  # in a foot of concrete, a cone of cloth 2.6 m across, a round table.
  defp parasol(seed, lot, long) do
    x = lot["at"] - long / 2 + (unit(seed, {:parasol, lot["at"]}) - 0.5) * 0.8
    y = 2.9
    cloth = pick(seed, {:cloth, lot["at"]}, [{"#b3261e", 2}, {"#1f4f9c", 2}, {"#1d7a46", 1}, {"#ece8dc", 2}])
    steel = %{"roughness" => 0.4, "metal" => 0.8}

    [
      e("cylinder", [0.035, 1.2], [x, y, 1.2], "#d8d8d4", steel),
      e("cylinder", [0.22, 0.05], [x, y, 0.05], "#8f8d86", %{"roughness" => 0.9}),
      e("cone", [1.3, 0.03, 0.22], [x, y, 2.3], cloth, %{
        "roughness" => 0.9,
        "surface" => %{"kind" => "fabric", "scale" => 0.004}
      }),
      e("cylinder", [0.45, 0.02], [x, y, 0.74], "#e6e2d6", %{"roughness" => 0.5})
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
