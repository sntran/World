defmodule World.Orders.Blueprints do
  @moduledoc """
  The blueprints of the factory (`World.Orders.Blueprint`, `docs/factory.md`):

  - `catalog`: a model of `World.Catalog` by its name;
  - `person`: a person of `World.People.Human`;
  - `traveler`: a person on a vehicle of Phượt (`World.People.traveler/2`);
  - `exercise`: a group at a morning of exercise (`World.People.exercise/2`);
  - `animal`: an animal of a species (`World.Animals.animal/2`);
  - `drawing`: a model in the data of the order (`World.Drawing`);
  - `house`: a house of `World.Buildings`;
  - `lot_house`: a whole house on a lot of Vũng Tàu (`World.Buildings.Lot`);
  - `statue`: a statue cast from a figure of a person (`World.Statues`);
  - `tower`: a tower of masonry, a lighthouse (`World.Towers`);
  - `van`: a van of `World.Vehicles.Van`;
  - `extrusion`, `strut`, `l_track`: the framing of `World.Framing`.
  """
  alias World.{Buildings, Framing}
  alias World.Materials.{Construction, Stock}
  alias World.Orders.Blueprint
  alias World.People.{Data, Human, Pose, Props}
  require Data
  alias World.Vehicles.Van
  import Blueprint, only: [option: 3]

  @doc "The blueprints, in the order of their names."
  def all,
    do:
      Enum.sort_by(
        [
          catalog(),
          drawing(),
          person(),
          traveler(),
          exercise(),
          animal(),
          house(),
          lot_house(),
          statue(),
          tower(),
          van(),
          extrusion(),
          strut(),
          l_track()
        ],
        & &1.name
      )

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
    names = Enum.map(World.Catalog.models(), &elem(&1, 0))

    %Blueprint{
      name: "catalog",
      doc: "A model of the catalog, by its name (/models/list.json). The order can give colors and joints.",
      options: [option("name", :choice, values: names, doc: "The name of the model.")],
      build: fn %{"name" => name} ->
        {:ok, fun} = World.Catalog.fetch(name)
        fun.()
      end,
      sources: ["The sources of each model are in its receipt."]
    }
  end

  # --- A drawing: a model in the data of the order -----------------------------------------------

  defp drawing do
    %Blueprint{
      name: "drawing",
      doc:
        "A model in the data of the order (docs/format.md, \"A drawing\"): its parts from shapes and ports, its nodes with their joints, the items of other blueprints (a model of the catalog, a person, an animal), and the clips of its joints.",
      options: [
        option("drawing", :data,
          check: &World.Drawing.check/2,
          doc: "The drawing: name, kind, materials, parts, nodes, clips, sources."
        )
      ],
      build: fn o -> World.Drawing.build(o["drawing"]) end,
      sources: ["The data of the order: its sources are in the drawing."]
    }
  end

  # --- A person ----------------------------------------------------------------------------

  defp person do
    %Blueprint{
      name: "person",
      doc:
        "A person from the data of MakeHuman (CC0): the shape of the body from its numbers, a skeleton of 53 bones, a skin, hair and clothes.",
      options:
        person_options() ++
          [
            option("pose", :choice, default: "stand", values: Pose.names()),
            option("animations", :list,
              default: [],
              item: option("item", :choice, values: ["walk" | Pose.routines()]),
              max: 1
            ),
            option("right_hand", :choice,
              default: "none",
              values: ["none" | Props.hand()],
              doc: "A prop in the right hand: the hand closes on it."
            ),
            option("left_hand", :choice, default: "none", values: ["none" | Props.hand()]),
            option("hat", :choice, default: "none", values: ["none" | Props.head()])
          ],
      build: fn o ->
        hold =
          for {key, port} <- [{"right_hand", "grip_r"}, {"left_hand", "grip_l"}, {"hat", "crown"}],
              o[key] != "none",
              do: {port, Props.prop(o[key])}

        World.People.Human.person(
          "person",
          person_opts(o) ++ [pose: o["pose"], animations: o["animations"], hold: hold]
        )
      end,
      check: &origin_check/1,
      sources: ["MakeHuman 1.x, the data of the base mesh, the targets and the assets (CC0)."]
    }
  end

  # --- An animal ------------------------------------------------------------------------------

  defp animal do
    %Blueprint{
      name: "animal",
      doc:
        "An animal from its bones (World.Animals): a species of a body plan, on a base mesh. The species: " <>
          Enum.map_join(World.Animals.species(), " ", &"#{&1}: #{World.Animals.spec(&1)["about"]}") <>
          " Its joints and limbs are in the order too.",
      options: [
        option("species", :choice, default: "street_dog", values: World.Animals.species()),
        option("coat", :color, default: nil, doc: "The color of the coat (the color of the species by default)."),
        option("size", :number, default: 1.0, min: 0.6, max: 1.4, doc: "A scale of the animal: 1 is its common size."),
        option("shape", :object,
          default: %{},
          fields:
            for(
              {name, {min, max, _}} <- Enum.sort(World.Animals.Shape.numbers()),
              do: option(name, :number, default: nil, min: min, max: max)
            ),
          doc:
            "Numbers of the shape over the numbers of the species (World.Animals.Shape): the lengths and the thickness of the body, the legs, the arms (a primate), the neck, the head, the skull (a primate), the muzzle, the ears, the tail; horns."
        ),
        option("markings", :object,
          default: %{},
          fields: for(r <- World.Animals.Shape.regions(), do: option(r, :color, default: nil)),
          doc: "A region of the coat to its color, over the colors of the species."
        ),
        option("space", :list,
          default: [],
          item: option("item", :number, min: -4.0, max: 4.0),
          # One for each component of the space.
          max: length(World.Animals.space("wolf")["components"]),
          doc:
            "The coefficients of the shape space of the template (World.Animals.Space), over the space of the species: only for a species on a template with a space (the template wolf: the wolf and the hyena). The space file lists the coefficients of each template that it comes from: the horse, the cow, the deer and more."
        ),
        option("animations", :list,
          default: [],
          item:
            option("item", :choice,
              values:
                World.Animals.species() |> Enum.flat_map(&World.Animals.animations/1) |> Enum.uniq() |> Enum.sort()
            ),
          max: 5,
          doc:
            "walk, run (a gallop), idle, idle_low (the head low), eat, attack, kick (only the animals with hooves), jump (in a gallop), jump_stop, hit_l, hit_r (a hit on the left or the right side) and death: the clips of the template of a four-legged animal, in place (an app moves the animal at walk_speed, run_speed or jump_speed of the parts list, in m/s); walk, sit, climb, hang and jump of a primate: a walk on four limbs, or on two legs for the gibbon (an app moves the animal at walk_speed), a sit on the ground that looks around, a climb up a trunk, a hang from a branch and a jump, in place; swim and idle of a fish: a wave along the body to the tail (an app moves the fish at swim_speed) and slow waves in place; walk, idle, peck and flap of a bird: a walk with the head that stays and then goes to the front (an app moves the bird at walk_speed), a look around, two pecks on the ground and a beat of the wings; wag: the tail of a four-legged animal. Each species has the animations of its body plan that the clips of its template have."
        )
      ],
      build: fn o ->
        World.Animals.animal(o["species"],
          coat: o["coat"] && rgb(o["coat"]),
          size: o["size"],
          shape: for({k, v} <- o["shape"], v != nil, into: %{}, do: {k, v}),
          markings: for({k, v} <- o["markings"], v != nil, into: %{}, do: {k, rgb(v)}),
          space: if(o["space"] != [], do: o["space"]),
          animations: o["animations"]
        )
      end,
      check: &animal_check/1,
      sources: ["The sizes of each species are in its sources: a guess from photos when there are no measurements."]
    }
  end

  defp animal_check(o) do
    known = World.Animals.animations(o["species"])

    space =
      if o["space"] != [] and World.Animals.space(o["species"]) == nil,
        do: [
          {"options.space",
           "a #{o["species"]} has no shape space; the species with one: #{Enum.join(Enum.filter(World.Animals.species(), &World.Animals.space/1), ", ")}"}
        ],
        else: []

    space ++
      for {a, i} <- Enum.with_index(o["animations"]),
          a not in known,
          do: {"options.animations.#{i}", "a #{o["species"]} has no animation #{a}: #{Enum.join(known, ", ")}"}
  end

  # --- A group at a morning of exercise ------------------------------------------------------

  defp exercise do
    %Blueprint{
      name: "exercise",
      doc:
        "A group at a morning of exercise, as on the beach of Vũng Tàu: a leader at the origin who faces the group (+y) and does the routine as in a mirror, and the people in rows of three in front, who face the leader (-y). Each person is different, from the seed, and starts a little late. The routine is one animation of the model, in a loop.",
      options: [
        option("routine", :choice, default: "tai_chi", values: Pose.routines()),
        option("count", :number, default: 6.0, min: 1.0, max: 12.0, doc: "The people in front of the leader."),
        option("seed", :number, default: 1.0, min: 1.0, max: 1_000_000.0, doc: "Another seed gives other people."),
        option("fans", :boolean,
          default: false,
          doc: "Each person holds an open tai chi fan in the right hand (the leader, in the mirror, in the left hand)."
        )
      ],
      build: fn o ->
        World.People.exercise(o["routine"], count: round(o["count"]), seed: round(o["seed"]), fans: o["fans"])
      end,
      sources: ["People of World from the data of MakeHuman (CC0), and the routines of World.People.Pose."]
    }
  end

  # --- A traveler: a person on a vehicle of Phượt -----------------------------------------------

  defp traveler do
    %Blueprint{
      name: "traveler",
      doc:
        "A person (the options of the blueprint person) and a vehicle of Phượt. The scene ride: the person in the pose of the vehicle, in the seat of the driver of a car or a van, on a motorcycle, a motorbike or a bicycle with a helmet, or on foot with the animation walk. The scene parked: the person stands next to the parked vehicle, on its right side, and looks to the right (+x), with the animations wave and point (once each). The vehicle goes to the front (+y).",
      options:
        [
          option("vehicle", :choice, default: "motorbike", values: World.People.vehicles()),
          option("scene", :choice,
            default: "ride",
            values: ["parked", "ride"],
            doc: "ride: on the vehicle (the position on a map); parked: next to it (an avatar)."
          ),
          option("helmet_color", :color,
            default: nil,
            doc: "The color of the helmet of a rider on two wheels. None: a light gray."
          ),
          option("van", :choice,
            default: "transit_148",
            values: Van.models(),
            doc:
              "The van of the camper (the blueprint van): transit_148 is the Ford Transit of DIY, with the items in its engine bay. Only for the vehicle camper."
          ),
          option("part", :choice,
            default: "all",
            values: ["all", "person", "vehicle"],
            doc:
              "all: the person and the vehicle; person: the person alone, at the same place (a change of the person needs no new vehicle); vehicle: the vehicle alone. A traveler on foot has no vehicle."
          )
        ] ++ person_options(),
      build: fn o ->
        opts =
          person_opts(o) ++
            [helmet: o["helmet_color"] && rgb(o["helmet_color"]), van: o["van"], part: o["part"]]

        World.People.traveler(o["vehicle"], opts, o["scene"])
      end,
      check: fn o ->
        foot =
          if o["vehicle"] == "foot" and o["part"] == "vehicle",
            do: [{"options.part", "a traveler on foot has no vehicle"}],
            else: []

        origin_check(o) ++ foot
      end,
      sources: ["The vehicles of World, and a person from the data of MakeHuman (CC0)."]
    }
  end

  # The options of the body and the looks of a person.
  defp person_options do
    assets = Data.assets()
    names = fn kind -> assets |> Map.fetch!(kind) |> Map.keys() |> Enum.sort() end
    share = fn name, default -> option(name, :number, default: default, min: 0.0, max: 1.0) end

    [
      option("gender", :number, default: 1.0, min: 0.0, max: 1.0, doc: "0 is a woman, 1 is a man."),
      option("age", :number, default: 30.0, min: 25.0, max: 90.0, unit: "years"),
      share.("muscle", 0.5),
      share.("weight", 0.5),
      share.("height", 0.5)
    ] ++
      for(
        {name, doc} <- Human.shapes(),
        do:
          option(Atom.to_string(name), :number,
            default: 0.5,
            min: 0.0,
            max: 1.0,
            doc: doc <> ": 0.5 is the shape of MakeHuman."
          )
      ) ++
      [
        option("shape", :object,
          default: Map.new(Data.sliders(), fn {name, _} -> {name, 0.0} end),
          fields:
            for(
              {name, s} <- Enum.sort(Data.sliders()),
              do: option(name, :number, default: 0.0, min: -1.0, max: 1.0, doc: "A slider of MakeHuman (#{s.group}).")
            ),
          doc:
            "The sliders of MakeHuman (targets/target.json of MPFB), from -1 to 1: 0 is the shape of MakeHuman. A slider here wins over its short name."
        ),
        option("head", :number,
          default: 1.0,
          min: 1.0,
          max: 2.0,
          doc: "The size of the head: 1 is the size of the body, more is the bigger head of a game."
        ),
        option("origin", :object,
          default: %{"african" => 0.0, "asian" => 1.0, "caucasian" => 0.0},
          fields: [share.("african", 0.0), share.("asian", 1.0), share.("caucasian", 0.0)],
          doc: "The weight of each origin of the shape of the body."
        ),
        option("skin", :choice, default: Data.name!("skins", "young_asian_male"), values: names.("skins")),
        option("eyes", :choice, default: Data.name!("eye_materials", "darkbrown"), values: names.("eye_materials")),
        option("eyebrows", :choice, default: Data.name!("eyebrows", "eyebrow001"), values: names.("eyebrows")),
        option("hair", :choice, default: Data.name!("hair", "short02"), values: ["none" | names.("hair")]),
        option("hair_color", :color, default: nil, doc: "The color of the hair. None: the color of its texture."),
        option("clothes", :list,
          default: Data.names!("clothes", ["male_casualsuit01", "shoes01"]),
          item: option("item", :choice, values: names.("clothes")),
          max: 6
        ),
        option("clothes_colors", :list,
          default: [],
          item: option("item", :color, []),
          max: 6,
          doc:
            "A color for each item of the clothes, in their order: at mid and far its color, at near a tint of its texture."
        ),
        option("face", :choice,
          default: "relaxed",
          values: ["relaxed", "neutral"],
          doc: "The face at rest: relaxed (the eyelids a little lower, a hint of a smile) or neutral."
        ),
        option("blink", :boolean,
          default: true,
          doc: "The shapes of a blink as morph targets, and the animation blink (a loop of 4 s)."
        )
      ]
  end

  # The options of World.People.Human.person/2 from the options of an order.
  defp person_opts(o) do
    for({name, _} <- Human.shapes(), do: {name, o[Atom.to_string(name)]}) ++
      [
        shape: Map.reject(o["shape"], fn {_, v} -> v == 0 end),
        gender: o["gender"],
        age: o["age"],
        muscle: o["muscle"],
        weight: o["weight"],
        height: o["height"],
        head: o["head"],
        race: Map.reject(o["origin"], fn {_, w} -> w == 0 end),
        skin: o["skin"],
        eyes: o["eyes"],
        eyebrows: o["eyebrows"],
        hair: if(o["hair"] == "none", do: nil, else: o["hair"]),
        hair_color: o["hair_color"] && rgb(o["hair_color"]),
        clothes: o["clothes"],
        clothes_colors: Enum.map(o["clothes_colors"], &rgb/1),
        face: o["face"],
        blink: o["blink"]
      ]
  end

  defp origin_check(o) do
    if Enum.all?(o["origin"], fn {_, w} -> w == 0 end),
      do: [{"options.origin", "must have one weight more than 0"}],
      else: []
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

        Buildings.house("house",
          length: o["length"],
          depth: o["depth"],
          wall: wall,
          wall_height: o["wall_height"],
          roof: String.to_existing_atom(o["roof"]),
          pitch: o["pitch"],
          overhang: o["overhang"],
          openings: openings,
          sources: ["A house of the blueprint house of World, from its options."]
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
          u = Construction.unit(unit)
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

  # --- A house on a lot --------------------------------------------------------------------

  defp lot_house do
    c = Buildings.Lot.choices()
    names = fn key -> Enum.map(c[key], &Atom.to_string/1) end

    %Blueprint{
      name: "lot_house",
      doc:
        "A whole house on a lot of a town of Việt Nam, as the houses of Vũng Tàu were in 2019: a tube house (nhà ống) on a narrow, deep lot, with its ground floor, its balconies, its roof and its side walls. The origin is at the center of the front of the lot, on the street; the front looks to +y. Three levels for a town: near, mid and far.",
      options: [
        option("kind", :choice,
          default: "tube",
          values: names.(:kind),
          doc:
            "A tube house (nhà ống), a shop house (nhà phố), a villa (biệt thự) behind a yard, or a mini-hotel (khách sạn mini). An option with no value (null) has the default of the kind."
        ),
        option("width", :number,
          default: 4.0,
          min: 3.0,
          max: 6.0,
          unit: "m",
          doc: "The front of the lot, on the street."
        ),
        option("depth", :number,
          default: 16.0,
          min: 8.0,
          max: 25.0,
          unit: "m",
          doc: "The lot from the street to its back."
        ),
        option("floors", :integer,
          default: nil,
          min: 1,
          max: 8,
          doc: "A tube house 1 to 8 (3), a shop house 2 to 6 (4), a villa 1 to 3 (2), a mini-hotel 5 to 8 (6)."
        ),
        option("style", :choice,
          default: "new",
          values: names.(:style),
          doc: "Old: wood shutters, rails of bars, a folding gate. New: glass in aluminum frames, rails of tubes."
        ),
        option("roof", :choice,
          default: nil,
          values: names.(:roof),
          doc: "A flat terrace with a parapet, corrugated metal, or clay tiles."
        ),
        option("ground", :choice,
          default: nil,
          values: names.(:ground),
          doc:
            "The front of the ground floor: a roll-up shutter, a folding iron gate, a door with an iron gate, or an open shop."
        ),
        option("finish", :choice,
          default: nil,
          values: names.(:finish),
          doc: "The front of the ground floor plain or of polished granite, or all the front of patterned tiles."
        ),
        option("left", :choice,
          default: nil,
          values: names.(:side),
          doc:
            "The left side wall, as seen from the street: shared with a neighbor, free with windows, or bare brick over a lower neighbor."
        ),
        option("right", :choice, default: nil, values: names.(:side), doc: "The right side wall, as the left."),
        option("extension", :boolean, default: false, doc: "A room of one floor at the back."),
        option("terrace_room", :boolean, default: nil, doc: "A room on a flat terrace."),
        option("interior", :choice,
          default: "none",
          values: names.(:interior),
          doc:
            "front_room: a room on the ground floor that a player can enter from the street: its floor 0.2 m over the street, a ceiling 3 m over the floor, the stairs, and a door of 0.9 by 2.1 m at its back."
        ),
        option("paint_age", :number,
          default: 0.3,
          min: 0.0,
          max: 1.0,
          doc: "The age of the paint, for the shader of the app: no change of the shape."
        ),
        option("seed", :integer,
          default: 1,
          min: 0,
          max: 1_000_000,
          doc: "The details: the balconies, the cages, the places of the doors and the windows."
        )
      ],
      build: fn o ->
        atom = fn key -> o[key] && String.to_existing_atom(o[key]) end

        # The options with no value have the defaults of the kind.
        Buildings.Lot.house(
          kind: atom.("kind"),
          width: o["width"],
          depth: o["depth"],
          floors: o["floors"],
          style: atom.("style"),
          roof: atom.("roof"),
          ground: atom.("ground"),
          finish: atom.("finish"),
          left: atom.("left"),
          right: atom.("right"),
          extension: o["extension"],
          terrace_room: o["terrace_room"],
          interior: atom.("interior"),
          paint_age: o["paint_age"],
          seed: o["seed"]
        )
      end,
      sources: [
        "TCVN 9411:2012 (nhà ở liên kế): the ground floor 3.6 m clear at the least. The other sizes: by eye, from the photos of the streets of Vũng Tàu (World.Buildings.Lot)."
      ]
    }
  end

  # --- A statue ------------------------------------------------------------------------------

  defp statue do
    hair = Data.assets() |> Map.fetch!("hair") |> Map.keys() |> Enum.sort()

    m = fn name, default, min, max, doc ->
      option(name, :number, default: default, min: min, max: max, unit: "m", doc: doc)
    end

    %Blueprint{
      name: "statue",
      doc:
        "A statue: a figure of a person at any size and in a pose, in a long robe, cast as one solid of concrete or stone, with a halo, on a base: a round plaza with steps in rings, a block with round corners and a front that curves in, with panels of gold and figures in relief in white frames, a band of letters and small windows with grilles, a terrace with a pierced balustrade, and a low dome with a stair up its front to the feet. The option hollow gives walls, a spiral stair and openings inside, at the near level. Each size can have its source; a size with no source is an estimate, and the receipt says so. The origin is on the ground at the center of the base; the figure looks to +y.",
      options: [
        m.(
          "height",
          32.0,
          1.0,
          100.0,
          "From the feet to the top of the figure (the top of the halo, when it has one)."
        ),
        m.(
          "span",
          nil,
          0.5,
          100.0,
          "The hands, tip to tip, with the pose arms_out. None: the proportions of the person."
        ),
        m.("hand", nil, 0.1, 10.0, "A hand, from the wrist to the tip of the middle finger, with the pose arms_out."),
        option("pose", :choice,
          default: "arms_out",
          values: ["arms_out" | Pose.names()],
          doc: "arms_out: the arms straight out to the sides. Else a pose of a person."
        ),
        option("lift", :number,
          default: 8.0,
          min: -45.0,
          max: 60.0,
          unit: "deg",
          doc: "The arms of arms_out over the level."
        ),
        option("gender", :number, default: 1.0, min: 0.0, max: 1.0, doc: "0 is a woman, 1 is a man."),
        option("age", :number, default: 35.0, min: 25.0, max: 90.0, unit: "years"),
        option("hair", :choice, default: Data.name!("hair", "long01"), values: ["none" | hair]),
        option("robe", :boolean, default: true, doc: "A long robe with wide sleeves and two long panels at its sides."),
        m.(
          "head",
          nil,
          0.1,
          20.0,
          "In a robe: from the top of the head to the end of the beard. None: the head of the person."
        ),
        option("beard", :boolean,
          default: false,
          doc: "In a robe, with head: a beard along the jaw to a point, and a mustache."
        ),
        option("halo", :boolean, default: true, doc: "A ring behind the head with a cross."),
        option("rays", :integer, default: 9, min: 0, max: 17, doc: "The metal rays of the halo (lightning rods)."),
        option("material", :choice,
          default: "concrete",
          values: Enum.map(World.Statues.materials(), &Atom.to_string/1),
          doc: "Concrete with a render of washed stone, or stone (granite)."
        ),
        option("hollow", :boolean,
          default: false,
          doc: "Walls, a spiral stair and openings inside (at the near level)."
        ),
        m.("wall", 0.3, 0.1, 2.0, "The wall of a hollow statue (at the least two cells of the cast)."),
        option("steps", :integer,
          default: 133,
          min: 10,
          max: 1000,
          doc: "The steps of the spiral stair, to the shoulders."
        ),
        m.("well", 1.0, 0.3, 4.0, "The open well in the middle of the spiral stair."),
        option("windows", :list,
          default: [],
          max: 12,
          item:
            option("window", :object,
              fields: [
                m.("z", :required, 0.0, 100.0, "Its center, over the feet."),
                m.("width", 1.2, 0.2, 5.0, ""),
                m.("height", 1.2, 0.2, 5.0, "")
              ]
            ),
          doc: "The openings in the front of the robe of a hollow statue."
        ),
        m.("plaza_radius", 10.5, 0.0, 100.0, "The round plaza round the base. 0: no plaza."),
        option("plaza_steps", :integer, default: 3, min: 1, max: 20, doc: "The steps in rings of the plaza."),
        m.("plaza_rise", 0.15, 0.05, 0.5, "Each step of the plaza."),
        m.("plaza_tread", 0.6, 0.2, 5.0, "Each step of the plaza."),
        m.("base_width", 13.0, 1.0, 100.0, "The block, along x."),
        m.("base_depth", 13.0, 1.0, 100.0, "The block, along y."),
        m.("base_height", 6.5, 0.0, 50.0, "The block, from the plaza to the terrace. 0: no block."),
        m.("corner", 1.5, 0.1, 10.0, "The radius of the round corners of the block."),
        m.("base_curve", 0.8, 0.0, 5.0, "How far the front of the block curves in, at its middle."),
        m.("panel_width", 8.0, 0.5, 100.0, "The panel of each relief."),
        m.("panel_height", 3.0, 0.3, 20.0, "The panel of each relief."),
        option("letters", :boolean, default: true, doc: "A band of letters over each panel."),
        option("grilles", :integer,
          default: 2,
          min: 0,
          max: 12,
          doc: "The small windows with grilles under the panel of the front."
        ),
        option("reliefs", :list,
          default: [],
          max: 4,
          item:
            option("relief", :object,
              fields: [
                option("side", :choice, values: ~w(front back left right)),
                option("figures", :integer, default: 3, min: 1, max: 20),
                option("title", :data, default: "", check: &World.Statues.check_text/2)
              ]
            ),
          doc: "The panels of figures in relief on the sides of the base."
        ),
        m.("terrace_rail", 1.0, 0.0, 3.0, "The pierced balustrade of the terrace on the block. 0: none."),
        m.("dome_width", 8.0, 1.0, 50.0, "The low dome under the feet, across its faces."),
        m.("dome_height", 3.0, 0.0, 20.0, "0: no dome."),
        option("dome_sides", :integer, default: 8, min: 4, max: 32, doc: "The faces of the dome."),
        m.("dome_stair", 1.2, 0.5, 5.0, "The stair up the front of the dome."),
        option("weathering", :number,
          default: 0.5,
          min: 0.0,
          max: 1.0,
          doc: "The stains of the sea air, for the shader of an app: no change of the shape."
        ),
        option("sources", :data,
          default: %{},
          check: &World.Statues.check_sources/2,
          doc: "The source of each size or choice, by its name (height, span, steps, base_width, ...)."
        )
      ],
      build: fn o ->
        World.Statues.statue(
          height: o["height"],
          span: o["span"],
          hand: o["hand"],
          pose: o["pose"],
          lift: o["lift"],
          gender: o["gender"],
          age: o["age"],
          hair: if(o["hair"] == "none", do: nil, else: o["hair"]),
          robe: o["robe"],
          head: o["head"],
          beard: o["beard"],
          halo: o["halo"],
          rays: o["rays"],
          material: String.to_existing_atom(o["material"]),
          hollow: o["hollow"],
          wall: o["wall"],
          steps: o["steps"],
          well: o["well"],
          windows: for(w <- o["windows"], do: {w["z"], w["width"], w["height"]}),
          plaza_radius: o["plaza_radius"],
          plaza_steps: o["plaza_steps"],
          plaza_rise: o["plaza_rise"],
          plaza_tread: o["plaza_tread"],
          base_width: o["base_width"],
          base_depth: o["base_depth"],
          base_height: o["base_height"],
          corner: o["corner"],
          base_curve: o["base_curve"],
          panel_width: o["panel_width"],
          panel_height: o["panel_height"],
          letters: o["letters"],
          grilles: o["grilles"],
          reliefs: o["reliefs"],
          terrace_rail: o["terrace_rail"],
          dome_width: o["dome_width"],
          dome_height: o["dome_height"],
          dome_sides: o["dome_sides"],
          dome_stair: o["dome_stair"],
          weathering: o["weathering"],
          sources: o["sources"]
        )
      end,
      sources: [
        "MakeHuman (CC0): the person of the figure. The sources of each size come with the order; the receipt lists them."
      ]
    }
  end

  # --- A tower -------------------------------------------------------------------------------

  defp tower do
    m = fn name, default, min, max, doc ->
      option(name, :number, default: default, min: min, max: max, unit: "m", doc: doc)
    end

    %Blueprint{
      name: "tower",
      doc:
        "A tower of masonry on a round platform: a lighthouse (a round body with pilasters that flare at the foot, bands, a cove under the gallery, the gallery and its rail, the drum, the lantern with its panes and its lens, the dome, a lightning rod). A house next to it is a model of its own. The option hollow gives the wall and a spiral stair inside at the near level. The ledge, the bands and the flare are over the platform, the other heights over the ground. Each size can have its source; a size with no source is an estimate, and the receipt says so. The origin is on the ground at the center of the platform.",
      options: [
        m.("height", 18.0, 3.0, 80.0, "From the ground to the top of the dome."),
        m.("platform_width", 7.8, 0.0, 40.0, "The round platform."),
        m.("platform_height", 0.3, 0.0, 3.0, ""),
        m.("body", 3.2, 0.5, 20.0, "The round body at its foot."),
        m.("top", 3.2, 0.5, 20.0, "The round body at the cornice."),
        m.("ledge", 0.8, 0.0, 5.0, "The ledge round the foot of the body."),
        option("bands", :list,
          default: [4.1, 7.5],
          max: 8,
          item: option("band", :number, min: 0.0, max: 80.0, unit: "m"),
          doc: "The heights of the bands round the body."
        ),
        option("pilasters", :integer, default: 4, min: 0, max: 16),
        m.("pilaster_width", 0.7, 0.1, 3.0, ""),
        m.("across", 5.1, 0.5, 30.0, "Across the pilasters."),
        m.("foot", 6.4, 0.5, 40.0, "Across the flared foot of the pilasters."),
        m.("flare", 3.1, 0.0, 30.0, "The height of the flare."),
        m.("cornice", 10.2, 1.0, 80.0, "The foot of the cove under the gallery."),
        m.("gallery", 12.7, 1.0, 80.0, "The floor of the gallery."),
        m.("gallery_width", 5.6, 0.5, 30.0, ""),
        m.("rail", 1.0, 0.5, 2.0, "The rail of the gallery."),
        m.("drum", 2.5, 0.5, 20.0, "The drum under the lantern (the watch room)."),
        m.("lantern_from", 15.4, 1.0, 80.0, ""),
        m.("lantern_to", 17.3, 1.0, 80.0, ""),
        m.("lantern_width", 2.2, 0.3, 10.0, ""),
        option("panes", :integer, default: 10, min: 6, max: 24),
        m.("rod", 21.0, 1.0, 100.0, "The top of the lightning rod."),
        m.("door_width", 0.9, 0.5, 3.0, ""),
        m.("door_height", 2.1, 1.5, 5.0, ""),
        option("door_angle", :number,
          default: 270.0,
          min: 0.0,
          max: 360.0,
          unit: "deg",
          doc: "The side of the door: 0 to +x (the east), 90 to +y."
        ),
        option("hollow", :boolean, default: false, doc: "The wall and a spiral stair inside (at the near level)."),
        m.("wall", 0.5, 0.1, 3.0, ""),
        option("steps", :integer, default: 55, min: 5, max: 500),
        option("light", :data,
          default: nil,
          check: &World.Towers.check_light/2,
          doc: "The light for the app: {color, flashes, period (s), range (nm)}."
        ),
        option("sources", :data,
          default: %{},
          check: &World.Towers.check_sources/2,
          doc: "The source of each size, by its name."
        )
      ],
      build: fn o ->
        World.Towers.tower(
          height: o["height"],
          platform: {o["platform_width"], o["platform_height"]},
          body: o["body"],
          top: o["top"],
          ledge: o["ledge"],
          bands: o["bands"],
          pilasters: o["pilasters"],
          pilaster_width: o["pilaster_width"],
          across: o["across"],
          foot: o["foot"],
          flare: o["flare"],
          cornice: o["cornice"],
          gallery: o["gallery"],
          gallery_width: o["gallery_width"],
          rail: o["rail"],
          drum: o["drum"],
          lantern: {o["lantern_from"], o["lantern_to"], o["lantern_width"]},
          panes: o["panes"],
          rod: o["rod"],
          door: {o["door_width"], o["door_height"]},
          door_angle: o["door_angle"],
          hollow: o["hollow"],
          wall: o["wall"],
          steps: o["steps"],
          light: o["light"],
          sources: o["sources"]
        )
      end,
      sources: ["The sources of each size come with the order; the receipt lists them."]
    }
  end

  # --- A van -------------------------------------------------------------------------------

  # The values of the options of a van, as the atoms of `World.Vehicles.Van`.
  @van_atoms Map.new(
               ~w(dc_charger second_alternator fan solar)a,
               &{Atom.to_string(&1), &1}
             )

  defp van do
    %Blueprint{
      name: "van",
      doc:
        "A van from the traces of its make and the photos of dealers: its body, its doors that open, its wheels that turn and steer, the items of DIY in the engine bay, and the items on the roof. The color of the role paint is the color of the body.",
      options: [
        option("model", :choice,
          default: "transit_148",
          values: Van.models(),
          doc: "The make, the wheelbase and the roof."
        ),
        option("windows", :list,
          default: "cargo",
          presets: Van.Order.presets(),
          max: 4,
          item:
            option("window", :object,
              fields: [
                option("at", :choice, values: Van.Order.places()),
                option("from", :number, default: nil, min: 0.0, max: 8.0, unit: "m", doc: "Behind the front axle."),
                option("to", :number, default: nil, min: 0.0, max: 8.0, unit: "m", doc: "Behind the front axle."),
                option("bottom", :number, default: nil, min: 0.0, max: 3.5, unit: "m", doc: "Over the ground."),
                option("top", :number, default: nil, min: 0.0, max: 3.5, unit: "m", doc: "Over the ground.")
              ]
            ),
          doc:
            "The windows behind the cab: a preset (cargo: none, the windows of the cab only; crew: the window of the second row at the left, the window of the sliding door and those of the rear doors; passenger: the windows all around) or a list. Each window has its place (at: left or right in a side of the body, slider in the sliding door, rear_doors in the rear doors; one window at a place) and its numbers; a number that the window does not give is that of the model. The openings factory makes the windows and the doors with their windows."
        ),
        option("rows", :integer,
          default: nil,
          min: 0,
          max: 4,
          doc:
            "The rows of seats behind the front seats. By default: 1 for the preset crew, all that go in the body for the preset passenger, and none else."
        ),
        option("doors", :object,
          default: %{},
          fields: [
            option("front", :object,
              default: %{},
              fields: [
                option("back", :number,
                  default: nil,
                  min: 0.0,
                  max: 3.0,
                  unit: "m",
                  doc: "Its back edge, behind the front axle."
                ),
                option("top", :number, default: nil, min: 1.5, max: 3.0, unit: "m", doc: "Over the ground.")
              ]
            ),
            option("sliding", :object,
              default: %{},
              fields: [
                option("from", :number, default: nil, min: 0.5, max: 4.0, unit: "m", doc: "Behind the front axle."),
                option("to", :number, default: nil, min: 1.0, max: 5.0, unit: "m", doc: "Behind the front axle."),
                option("top", :number, default: nil, min: 1.5, max: 3.5, unit: "m", doc: "Over the ground.")
              ]
            ),
            option("rear", :object,
              default: %{},
              fields: [
                option("height", :number,
                  default: nil,
                  min: 1.0,
                  max: 2.5,
                  unit: "m",
                  doc: "The opening over the floor."
                )
              ]
            )
          ],
          doc:
            "The numbers of the doors over those of the model. The openings factory makes each door to its numbers. A door moves only a little from that of the model and stays in the body: a number out of its limits gives an error with the limits."
        ),
        option("engine_bay", :list,
          default: [],
          item: option("item", :choice, values: ["dc_charger", "second_alternator"]),
          max: 2,
          doc: "The items of DIY in the engine bay."
        ),
        option("roof", :list,
          default: [],
          max: 6,
          item:
            option("item", :object,
              fields: [
                option("kind", :choice, values: ["fan", "solar"]),
                option("at", :number, min: 0.0, max: 8.0, unit: "m", doc: "The center, from the front of the van.")
              ]
            ),
          doc: "The items on the roof: a roof fan (MaxxFan) or a solar panel of 400 W."
        ),
        option("size", :object,
          default: %{},
          fields: [
            option("length", :number, default: nil, min: 3.0, max: 9.0, unit: "m"),
            option("width", :number, default: nil, min: 1.5, max: 2.5, unit: "m", doc: "With no mirrors."),
            option("height", :number, default: nil, min: 1.5, max: 3.5, unit: "m")
          ],
          doc:
            "The sizes of the van, over those of the model. The model has the sizes that the maker gives for the US; the sizes for another market can be different (the Sprinter of Mercedes-Benz Australia is 2.331 m high with a standard roof, the US page gives 100 in). Each size can be only a little different from the model: a size out of the limits of the model gives an error with the limits."
        )
      ],
      build: fn o ->
        Van.build(o["model"],
          name: "van",
          size: o["size"],
          doors: o["doors"],
          windows: o["windows"],
          rows: o["rows"],
          engine_bay: Enum.map(o["engine_bay"], &Map.fetch!(@van_atoms, &1)),
          roof: for(%{"kind" => k, "at" => d} <- o["roof"], do: {Map.fetch!(@van_atoms, k), d})
        )
      end,
      check: &van_check/1,
      sources: [
        "The sources of the model are in the receipt: the sizes of Ford, the traces of DIY and the photos of dealers."
      ]
    }
  end

  # The sizes, the doors, the windows and the rows are in the limits of
  # the model; each item on the roof is on its flat part, and two items
  # do not touch.
  defp van_check(o) do
    errors = Van.check(o["model"], Map.take(o, ["size", "doors", "windows", "rows"]))
    if errors == [], do: roof_check(o), else: errors
  end

  defp roof_check(o) do
    {d0, d1} = Van.roof_span(o["model"], %{"size" => o["size"]})

    spans =
      for {%{"kind" => k, "at" => d}, i} <- Enum.with_index(o["roof"]) do
        half = Van.roof_item(Map.fetch!(@van_atoms, k))
        {i, d - half, d + half}
      end

    outside =
      for {i, a, b} <- spans,
          a < d0 or b > d1,
          do:
            {"options.roof.#{i}",
             "must be on the flat part of the roof: its center from #{Float.round(d0, 3)} m + its half length to #{Float.round(d1, 3)} m - its half length"}

    touch =
      for {i, a, b} <- spans,
          {j, c, e} <- spans,
          i < j,
          a < e and c < b,
          do: {"options.roof.#{j}", "must not touch the item #{i}"}

    outside ++ touch
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
      sources: ["The catalogs of 80/20 Inc. and of the metric series (see World.Framing)."]
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
      sources: ["L-track: 1 1/8 by 1/2 in, pockets each inch (see World.Framing)."]
    }
  end

  # A color "#rrggbb" as [r, g, b].
  defp rgb("#" <> hex), do: for(<<c::binary-size(2) <- hex>>, do: String.to_integer(c, 16))
end
