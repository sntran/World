defmodule Xuong.Blueprints do
  @moduledoc """
  The blueprints of the factory (`Xuong.Blueprint`, `docs/factory.md`):

  - `catalog`: a model of `Xuong.Catalog` by its name;
  - `person`: a person of `Xuong.Human`;
  - `house`: a house of `Xuong.Models.Houses`;
  - `extrusion`, `strut`, `l_track`: the framing of `Xuong.Parts.Framing`.
  """
  alias Xuong.Blueprint
  alias Xuong.Human.{Data, Pose}
  alias Xuong.Models.Houses
  alias Xuong.Parts.{Building, Framing, Stock}

  import Blueprint, only: [option: 3]

  @doc "The blueprints, in the order of their names."
  def all, do: Enum.sort_by([catalog(), person(), house(), extrusion(), strut(), l_track()], & &1.name)

  @doc "The names of the blueprints."
  def names, do: Enum.map(all(), & &1.name)

  @doc "A blueprint by its name."
  def fetch(name) do
    case Enum.find(all(), &(&1.name == name)) do
      nil -> :error
      b -> {:ok, b}
    end
  end

  # --- A model of the catalog ------------------------------------------------------------

  defp catalog do
    names = Enum.map(Xuong.Catalog.models(), &elem(&1, 0))

    %Blueprint{
      name: "catalog",
      doc: "A model of the catalog, by its name (/models/list.json). The order can give colors and joints.",
      options: [option("name", :choice, values: names, doc: "The name of the model.")],
      build: fn %{"name" => name} ->
        {:ok, fun} = Xuong.Catalog.fetch(name)
        fun.()
      end,
      sources: ["The sources of each model are in its receipt."]
    }
  end

  # --- A person ----------------------------------------------------------------------------

  defp person do
    assets = Data.assets()
    names = fn kind -> assets |> Map.fetch!(kind) |> Map.keys() |> Enum.sort() end
    share = fn name, default -> option(name, :number, default: default, min: 0.0, max: 1.0) end

    %Blueprint{
      name: "person",
      doc:
        "A person from the data of MakeHuman (CC0): the shape of the body from its numbers, a skeleton of 53 bones, a skin, hair and clothes.",
      options: [
        option("gender", :number, default: 1.0, min: 0.0, max: 1.0, doc: "0 is a woman, 1 is a man."),
        option("age", :number, default: 30.0, min: 25.0, max: 90.0, unit: "years"),
        share.("muscle", 0.5),
        share.("weight", 0.5),
        share.("height", 0.5),
        option("origin", :object,
          default: %{"african" => 0.0, "asian" => 1.0, "caucasian" => 0.0},
          fields: [share.("african", 0.0), share.("asian", 1.0), share.("caucasian", 0.0)],
          doc: "The weight of each origin of the shape of the body."
        ),
        option("skin", :choice, default: "young_asian_male", values: names.("skins")),
        option("eyes", :choice, default: "brown", values: names.("eye_materials")),
        option("eyebrows", :choice, default: "eyebrow001", values: names.("eyebrows")),
        option("hair", :choice, default: "short02", values: ["none" | names.("hair")]),
        option("clothes", :list,
          default: ["male_casualsuit01", "shoes01"],
          item: option("item", :choice, values: names.("clothes")),
          max: 6
        ),
        option("pose", :choice, default: "stand", values: Pose.names()),
        option("animations", :list, default: [], item: option("item", :choice, values: ["walk"]), max: 1)
      ],
      build: fn o ->
        Xuong.Human.person("person",
          gender: o["gender"],
          age: o["age"],
          muscle: o["muscle"],
          weight: o["weight"],
          height: o["height"],
          race: Map.reject(o["origin"], fn {_, w} -> w == 0 end),
          skin: o["skin"],
          eyes: o["eyes"],
          eyebrows: o["eyebrows"],
          hair: if(o["hair"] == "none", do: nil, else: o["hair"]),
          clothes: o["clothes"],
          pose: o["pose"],
          animations: o["animations"]
        )
      end,
      check: fn o ->
        if Enum.all?(o["origin"], fn {_, w} -> w == 0 end),
          do: [{"options.origin", "must have one weight more than 0"}],
          else: []
      end,
      sources: ["MakeHuman 1.x, the data of the base mesh, the targets and the assets (CC0)."]
    }
  end

  # --- A house -----------------------------------------------------------------------------

  @walls %{
    "brick_vn" => {:masonry, "brick_vn"},
    "brick_us_modular" => {:masonry, "brick_us_modular"},
    "cmu_8" => {:masonry, "cmu_8"},
    "studs" => :studs
  }

  defp house do
    %Blueprint{
      name: "house",
      doc:
        "A house of one floor: a slab of concrete, four walls, a gable roof along its length, doors and windows. Each brick, block, stud, tile and panel is in the list of the parts.",
      options: [
        option("length", :number, default: 6.0, min: 3.0, max: 12.0, unit: "m", doc: "Along x, outside the walls."),
        option("depth", :number, default: 4.2, min: 3.0, max: 10.0, unit: "m", doc: "Along y, outside the walls."),
        option("wall", :choice, default: "brick_vn", values: @walls |> Map.keys() |> Enum.sort()),
        option("wythes", :integer, default: 2, min: 1, max: 2, doc: "The wythes of a wall of masonry."),
        option("wall_height", :number, default: 3.0, min: 2.2, max: 4.0, unit: "m"),
        option("roof", :choice, default: "tile", values: ["metal", "tile"]),
        option("pitch", :number, default: 0.5, min: 0.1, max: 1.2, doc: "The rise over the run of the roof."),
        option("overhang", :number, default: 0.5, min: 0.0, max: 1.2, unit: "m"),
        option("openings", :list,
          default: [
            %{"wall" => "front", "kind" => "window", "x" => 1.1, "width" => 1.0, "height" => 1.2, "sill" => 0.91},
            %{"wall" => "front", "kind" => "door", "x" => 3.0, "width" => 0.9, "height" => 2.1, "sill" => 0.0},
            %{"wall" => "front", "kind" => "window", "x" => 4.9, "width" => 1.0, "height" => 1.2, "sill" => 0.91},
            %{"wall" => "back", "kind" => "window", "x" => 3.0, "width" => 1.0, "height" => 1.2, "sill" => 0.91},
            %{"wall" => "left", "kind" => "window", "x" => 1.9, "width" => 0.8, "height" => 1.0, "sill" => 1.05}
          ],
          max: 16,
          item:
            option("opening", :object,
              fields: [
                option("wall", :choice, values: ["back", "front", "left", "right"]),
                option("kind", :choice, values: ["door", "window"]),
                option("x", :number,
                  min: 0.0,
                  max: 12.0,
                  unit: "m",
                  doc: "The center, from the left of the wall seen from outside."
                ),
                option("width", :number, min: 0.4, max: 3.0, unit: "m"),
                option("height", :number, min: 0.4, max: 2.4, unit: "m"),
                option("sill", :number,
                  default: 0.9,
                  min: 0.0,
                  max: 2.0,
                  unit: "m",
                  doc: "The height of a window over the floor."
                )
              ]
            )
        )
      ],
      build: fn o ->
        wall =
          case @walls[o["wall"]] do
            {:masonry, unit} -> {:masonry, unit, o["wythes"]}
            :studs -> :studs
          end

        openings =
          o["openings"]
          |> Enum.group_by(&String.to_existing_atom(&1["wall"]), fn
            %{"kind" => "door"} = d -> {:door, d["x"], d["width"], d["height"]}
            w -> {:window, w["x"], w["width"], w["height"], w["sill"]}
          end)

        Houses.house("house",
          length: o["length"],
          depth: o["depth"],
          wall: wall,
          wall_height: o["wall_height"],
          roof: String.to_existing_atom(o["roof"]),
          pitch: o["pitch"],
          overhang: o["overhang"],
          openings: openings,
          sources: ["A house of the blueprint house of Xưởng, from its options."]
        )
      end,
      check: &house_check/1,
      sources: [
        "The units: TCVN 1451 (bricks of Việt Nam), ASTM C216 (bricks of the US), ASTM C90 (blocks). The frame of wood: IRC R602."
      ]
    }
  end

  # Each opening is in its wall, 0.3 m from each end, and under the top of
  # the wall.
  defp house_check(o) do
    thick =
      case @walls[o["wall"]] do
        {:masonry, unit} ->
          u = Building.unit(unit)
          o["wythes"] * u.w + (o["wythes"] - 1) * u.joint

        :studs ->
          {_, w} = Stock.table(:lumber, "2x4")
          w
      end

    lengths = %{
      "front" => o["length"],
      "back" => o["length"],
      "left" => o["depth"] - 2 * thick,
      "right" => o["depth"] - 2 * thick
    }

    for {op, i} <- Enum.with_index(o["openings"]),
        len = lengths[op["wall"]],
        top = if(op["kind"] == "door", do: 0.0, else: op["sill"]) + op["height"],
        message <- [
          if(op["x"] - op["width"] / 2 < 0.3 or op["x"] + op["width"] / 2 > len - 0.3,
            do: "must be in its wall, 0.3 m from each end: the wall is #{Float.round(len, 3)} m long"
          ),
          if(top > o["wall_height"] - 0.3, do: "must end 0.3 m under the top of the wall")
        ],
        message != nil,
        do: {"options.openings.#{i}", message}
  end

  # --- Framing -----------------------------------------------------------------------------

  defp extrusion do
    %Blueprint{
      name: "extrusion",
      doc: "A T-slot extrusion of aluminum (80/20 and the metric series), with a port at each slot.",
      options: [
        option("profile", :choice, values: Framing.profiles()),
        option("length", :number, min: 0.02, max: 6.0, unit: "m")
      ],
      build: fn o -> Framing.extrusion(o["profile"], o["length"]) end,
      sources: ["The catalogs of 80/20 Inc. and of the metric series (see Xuong.Parts.Framing)."]
    }
  end

  defp strut do
    %Blueprint{
      name: "strut",
      doc: "A strut channel of 1 5/8 in (Unistrut P1000, or P1000T with slots).",
      options: [
        option("kind", :choice, default: "slotted", values: ["slotted", "solid"]),
        option("length", :number, min: 0.05, max: 6.1, unit: "m")
      ],
      build: fn o -> Framing.strut(String.to_existing_atom(o["kind"]), o["length"]) end,
      sources: ["Unistrut, the catalog of P1000 and P1000T."]
    }
  end

  defp l_track do
    %Blueprint{
      name: "l_track",
      doc: "An L-track of aluminum for tie-downs, with a pocket each inch.",
      options: [option("length", :number, min: 0.05, max: 3.0, unit: "m")],
      build: fn o -> Framing.l_track(o["length"]) end,
      sources: ["L-track: 1 1/8 by 1/2 in, pockets each inch (see Xuong.Parts.Framing)."]
    }
  end
end
