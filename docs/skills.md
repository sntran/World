# The skills of the trades

World builds any blueprint whose skills it has (plan 0002, D1). A skill
is the work of one trade (`World.Skill`): a node of a drawing names it
and gives its data, and a person of the trade does the task of the node.
The skills are the words; a blueprint is a sentence of them. A project
(Vũng Tàu, Phượt) owns its blueprints; World owns the skills.

This document gives each skill: its trade, its data, its takeoff (the
materials of the stock that the trucks bring before the task starts;
`priv/places.json`), and what it makes. The format of a blueprint in
data is in `docs/format.md` ("A blueprint in data", "A drawing").

## How a project sends a blueprint

1. Write the blueprint in data: `name`, `doc`, `sources`, `params` (the
   options of its orders), and `drawing` (its nodes, each a skill with
   its data; a value can be `{"param": NAME}`, `{"var": NAME}` in a
   `repeat`, `{"sum": [...]}`).
2. Check it: the MCP tool `check_blueprint` gives each error with its
   path (`blueprint.drawing.nodes.3.skill.course.side`), or its options,
   its hash and the plan of the people at the level far.
3. Order it, in one of two ways:
   - give the blueprint itself in the order:
     `{"blueprint": {...the blueprint...}, "options": {...}}`;
   - or keep it with `POST /blueprints` (the answer gives its `hash`),
     then order `{"blueprint": {"hash": HASH}, "options": {...}}`.

   The full order has the blueprint itself: its hash names the
   blueprint and the options, so the same blueprint and options give the
   same files. `POST /builds` (or the MCP tool `build`) starts its
   construction, and the stream gives each element as the people make it.

An order of a bicycle of a frame of 58 cm, from its geometry sheet (the
blueprint `bicycle`):

```text
{"blueprint": "bicycle", "options": {"stack": 0.62, "reach": 0.39, "seat_tube": 0.58}}
```

When a blueprint needs a skill that World does not have, World adds it
(one module of `lib/world/skills/`, with its tests), or the drawing uses
the shapes and the parts of `docs/format.md` ("A drawing").

A small example: a house of one floor with a door, from the skills of a
site (the full blueprint is `priv/blueprints/tube_house.json`).

```json
{
  "name": "nha_nho",
  "params": [{"name": "width", "type": "number", "default": 4.0, "min": 2.5, "max": 12.0, "unit": "m"}],
  "drawing": {
    "kind": "house",
    "nodes": [
      {"name": "plan", "skill": {"house_plan": {"width": {"param": "width"}, "floors": 1,
        "openings": [{"side": "front", "floor": 1, "kind": "door", "x": 0.0, "width": 0.9, "height": 2.2, "sill": 0.0}]}}},
      {"name": "slab_0", "skill": {"footing": {}}, "from": ["plan"]},
      {"name": "col_1", "skill": {"column": {"floor": 1}}, "from": ["plan"], "after": ["slab_0"]},
      {"name": "slab_1", "skill": {"slab": {"floor": 1}}, "from": ["plan"], "after": ["col_1"]},
      {"repeat": {"for": "side", "in": ["front", "back", "left", "right"]},
       "node": {"name": "wall_{side}", "skill": {"course": {"side": {"var": "side"}, "floor": 1, "band": 1, "bands": 1, "finish": "bare"}},
                "from": ["plan"], "after": ["slab_0"]}},
      {"name": "door", "skill": {"opening": {"side": "front", "floor": 1}}, "from": ["plan"], "after": ["wall_front"]},
      {"name": "roof", "skill": {"roof": {}}, "from": ["plan"], "after": ["slab_1"]}
    ]
  }
}
```

## A house, as on a real site (`World.Skills.House`)

The data of each skill of a site are names of the options of
`World.Skills.House` (`check/3`): a `plan` node of an engineer gives the
plan, and each other node takes it in `from`.

| Skill | Trade | Data | Takeoff | What it makes |
|---|---|---|---|---|
| `house_plan` | engineer | `width`, `depth`, `floors`, `ground`, `storey`, `slab`, `column`, `beam`, `bays`, `wall`, `parapet`, `balcony`, `roof`, `stair_width`, `openings` | | The plan of the house: data only. |
| `footing` | concreter | | cement, rebar | The pads and the ground beams (at near) and the ground slab. |
| `column` | concreter | `floor` | cement, rebar | The columns of a floor. |
| `slab` | concreter | `floor` | cement, rebar | The beams and the slab over a floor, with the well of the stair and the balcony. |
| `course` | mason | `side`, `floor`, `band`, `bands`, `finish` | bricks | One band of the courses of a wall of a floor, between the columns, with its openings. |
| `plaster` | plasterer | `side`, `floor`, `finish` | mortar | The render of a wall. |
| `paint` | painter | `side`, `floor`, `finish` | paint | The paint on the render. |
| `opening` | joiner | `side`, `floor` | | The doors, the windows and the shutter of a wall. |
| `flight` | concreter | `floor` | | The stair to the floor over it (at near). |
| `iron` | smith | `floor` | steel | The rail of the balcony over a floor. |
| `roof` | roofer | | bricks, roof sheets | The parapet, and a roof of corrugated steel. |

## A statue, cast in pours (`World.Skills.Statue`)

| Skill | Trade | Data | What it makes |
|---|---|---|---|
| `figure` | sculptor | `name`, `height`, `span`, `hand`, `pose`, `lift`, `gender`, `age`, `hair`, `halo`, `race`, `face` | The figure of a person at its size and pose: data for the cast; its head with the race and the face of the sculptor. |
| `robe` | sculptor | `robe`, `forms`, `material` | The robe on the figure, or its `forms` as data (`World.Forms`, plan 0005): the outside of the statue at near. |
| `cast_survey` | surveyor | `height` | The grid of the cast. |
| `cast_outside` | caster | `bands` | The fill of the outside of the grid, the triangles of each band, and the box of each band on a site. |
| `scaffold` | scaffolder | `band`, `bands`, `feet`, `method` | The scaffold of one band (temporary): steel today, bamboo with a pulley in 1974. |
| `formwork` | carpenter | `band`, `bands`, `feet`, `method` | The forms of one band (temporary): plywood today, timber boards in 1974. |
| `pour` | caster | `band`, `bands`, `feet` | The pour of one band: the distances near its surface, and the band in rough grey concrete (temporary). |
| `site_step` | (its node) | | A step of a site with no part: the strip of the forms, the fall of the scaffold or of the crane. |
| `crane` | rigger | `height`, `jib`, `at`, `turn` | The tower crane of a site of today (temporary). |
| `mixing` | caster | `at` | The board of the mixing of the concrete by hand of 1974 (temporary). |
| `cast_field` | caster | `hollow`, `wall`, `well`, `windows` | The field of the solid, from the pours in any order. |
| `shell_slab` | finisher | `band`, `bands` | The mesh of the surface of one slab of the grid. |
| `shell` | caster | `hand`, `material` | The shell of the statue, from its slabs; with the forms of the robe, at near only its inner walls. |
| `set` | sculptor | `name`, `feet` | The statue set on its base. |
| `halo` | smith | `material`, `halo`, `rays`, `ring` | The halo and its rays; with `ring`, where the measures put it, leaning to the front. |
| `carve` | sculptor | `material`, `head`, `hands` | The head and the hands, carved from the full mesh of the person at near; with `head` and `hands`, where the measures put them. |
| `grille` | smith | `material`, `hollow`, `windows` | The grilles of the windows. |
| `base` | mason | `material`, `base_width`, `base_depth`, `base_height`, `corner`, `reliefs`, `plinth_radius`, `plinth_height`, `plinth_top`, `plinth_sides`, `base_plan`, `base_curve`, `base_room`, `relief_metal`, `terrace`, `well` | The plinth (round, or a dome of facets) and the base, square or curved, with the reliefs; with `base_room`, a room with a door and a hollow plinth. |
| `stair` | mason | `hollow`, `steps`, `well`, `feet`, `base_room` | The spiral stair inside a hollow statue, from the plinth or from the floor of the room of the base. |
| `rail` | mason | `material`, `rail`, `base_width`, `base_depth`, `base_height`, `base_plan`, `base_curve` | The rail round the base, along its curves. |
| `site` | surveyor | `hand`, `hollow`, `well`, `base_width`, `base_depth`, `base_height`, `plinth_radius`, `feet`, `base_room` | The ports and the collision of the site: data only. |

## A sculpture (`World.Skills.Sculpt`)

| Skill | Trade | Data | What it makes |
|---|---|---|---|
| `sculpt` | sculptor | `edits`, `groups`, `details`, `ports`, `sources`, `budget`, `cells`, `bake`, `bones`, `bone_blend`, `plan`, `gait`, `clips` | A part from a list of edits: simple shapes that add, take away or paint, each with a blend, a color and copies (`docs/format.md`, "A sculpture"). The tree of its bricks is the crew of the hand of the sculptor. With `bake`, a color map and a normal map from the field of the edits. With `bones`, a figure: one skinned mesh that follows the bones, with the clips of its body plan and of its keys. |

## A tower (`World.Skills.Towers`)

| Skill | Trade | Data | What it makes |
|---|---|---|---|
| `tower_site` | surveyor | the sizes of the tower and its `light` | The sizes of the tower: data only. |
| `tower_body` | mason | `platform_width`, `platform_height`, `body`, `top`, `ledge`, `bands`, `pilasters`, `door_width`, and more | The platform, the body, the pilasters, the bands and the cove. |
| `lantern` | smith | `height`, `gallery`, `rail`, `drum`, `lantern_from`, `lantern_to`, `panes`, `rod`, and more | The gallery and its rail, the drum, the lantern, the dome and the rod. |
| `spiral_stair` | mason | `hollow`, `body`, `wall`, `gallery`, `steps`, `platform_height` | The spiral stair inside the tower. |
| `tower` | mason | `name` | The tower, joined. |

## The vehicle trades (`World.Skills.Vehicle`)

These skills are for any vehicle (plan 0002, D5). A skill takes the
numbers of a spec sheet where its trade has one, and shape data (the
shapes of `docs/format.md`, "A drawing") for the free shapes of a model.
No skill names a model. The joints are in the drawing.

| Skill | Trade | Data | What it makes |
|---|---|---|---|
| `wheel` | wheelwright | `tire` (`215/50R17`, `90/90-14`, `37-622`), `build` (`spoked`, `cast`, `car`), `spokes`, `rim_width`, `rim_depth`, `rim`, `rim_matter`, `hub_width`, `cross`, `disc`, `face`, `holes`, `pcd`, `lugs`, `sides`, `contents` | A wheel with its tire, its port `hub`. |
| `knuckle` | mechanic | `at` (the center of the hub), `disc` | The knuckle of a corner with its brake disc: the port `steer` goes on the port `corner_NAME` of the body, the wheel on its port `axle`. |
| `bicycle_frame` | welder | the geometry sheet (`World.Skills.Bicycle`): `tire`, `chainstay`, `bb_drop`, `stack`, `reach`, `head_angle`, `seat_angle`, `seat_tube`, `head_tube`, `seatpost`, `rear_spacing`, the diameter of each tube | A diamond frame with its saddle: the ports `steer`, `rear_axle`, `bb`, `stand`, `rack`; the model moves to its center. |
| `bicycle_fork` | welder | the geometry sheet, with `rake` and `bar_width` | The fork, the stem and a drop bar, with its fender: the ports `steer` and `axle`. |
| `crankset` | mechanic | `arm`, `teeth` | The chainring, the arms and the pedals on their hinges: the port `axle` goes on `bb`. |
| `stand` | smith | shape data: `shapes`, `ports`, `mass`, `sources`, `detail`, `inside`, `contents` | A stand, a rack, a guard, from its own port. |
| `frame` | welder | shape data | The frame of a motor vehicle, with its head tube and its ports. |
| `swingarm` | welder | shape data | A swing arm, with its ports `pivot`, `axle` and `shock`. |
| `fork` | mechanic | shape data | A telescopic fork with its fender, or the bars, the grips, the levers and the mirrors of a cockpit. |
| `engine` | mechanic | shape data, with its `mass` | An engine, with its ports, or a part of its drive (a chain). |
| `panel` | molder | shape data (a `skin` of ABS) | A panel of plastic: the body of a scooter, a fender. |
| `body` | sheet_metal_worker | shape data | A body of steel sheet on lofts with arches, a tank. |
| `glass` | glazier | shape data | The windows of a car, a screen. |
| `seat` | upholsterer | shape data | A saddle, the seat of a scooter or of a motorcycle. |
| `lamp` | electrician | shape data (detail `always`) | The lamps. |
| `spring` | smith | `diameter`, `wire`, `length`, `turns`, `material`, `inside` | A coil spring: a shock, with its ports `end_a` and `end_b`. |
| `fastener` | mechanic | `kind` (`bolt`, `nut`, `washer`), `thread`, `length` | A bolt, a nut or a washer of ISO metric sizes. |

The mass of a part from shape data is the mass of its shapes (each its
volume, or its `skin` area times its thickness, times the density of its
material or its `matter`), or the `mass` of its data sheet. Its
`contents` add the things in it that its shapes do not show: the fuel in
a tank, the oil in an engine, a battery under a seat (`World.Mass`). A
spring or a rim of a color is of steel or of aluminum for its mass.

The blueprints `bicycle.json` (its params are the numbers of its
geometry sheet), `scooter.json`, `motorcycle.json` and `car.json` are vehicles from
these skills (`docs/format.md`, "The vehicles that the people build").

## A van, as on the line of its maker (`World.Skills.Van`)

The node `order` of an engineer gives the order of the line; each other
node takes it in `from`. The data `group` names one group of a station.

| Skill | Trade | Data | What it makes |
|---|---|---|---|
| `van_order` | engineer | the options of the blueprint `van`: `model` (a name of `priv/data/vans.json`, or the data of a model in its format with the data of its make in `make`: a van of a project), `windows`, `rows`, `doors`, `engine_bay`, `roof`, `size` | The order of the line: data only, and the move of the model to its center. |
| `van_body` | sheet_metal_worker | | The body in white, with its openings at near. |
| `van_inside` | trimmer | | The floors, the wells of the wheels and the pillar (at near). |
| `van_closure` | fitter | `group`: `hood`, `front_door_right`, `front_door_left`, `sliding_door`, `rear_door_right`, `rear_door_left` | The hood or one door, on its hinges or its rail. |
| `van_trim` | trimmer | `group`: `plastic`, `lamps`, `grille`, `details`, `cab` | One group of the trim. |
| `van_glass` | glazier | | The windshield and the windows of the body. |
| `van_seats` | upholsterer | | The seats on their mounts (at near). |
| `van_chassis` | mechanic | `group`: `engine_bay`, `drive`, `front_right`, `front_left`, `rear_right`, `rear_left` | The engine bay, the drive, or the corner of one wheel. |
| `van_upfit` | electrician | | The items of DIY on the roof. |
