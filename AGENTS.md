# How to work on World

Read `README.md` first: it tells what World is, and the state of each
step. `docs/format.md` tells the format of a model. This file tells how
to work on the project, and the facts that are not in the code.

## The sources of truth

1. The code. When the code and a doc do not agree, the code is correct:
   change the doc in the same branch.
2. `docs/format.md`: the format of a part, an assembly, a voxel model,
   and of each file.
3. `README.md`: the product, and the state of each step ("Progress").
4. `specs/` and `docs/specs.md`: the flows of the node in TLA+. A
   change of the people of the node (`World.Construction`,
   `World.Census`, `World.Person`), of the stream (`World.Stream`) or of
   the log (`World.Log.Server`) changes its specification in the same
   commit, and the replay test must pass.

An idea that is not a decision goes into `TODO.md`. The owner decides
about it.

## The rules of the owner

- Write all text in ASD-STE100 Simplified Technical English: docs, code
  comments, names, log text, error messages and commit messages. See
  `CONTRIBUTING.md`.
- Give each size of a part its source (`sources`): a standard, a data
  sheet, or a measurement. A size that is a guess says so.
- Each change has tests of its behavior, also for errors and limits.
  Write property tests (StreamData) where you can.
- Keep the coverage of the tests at 100%. Remove code that no feature
  uses.
- Keep each commit small, with one purpose. Write the message in the
  format of [Conventional Commits](https://www.conventionalcommits.org/):
  `type(scope): description`. The types are `feat`, `fix`, `docs`,
  `test`, `refactor`, `perf`, `build`, `ci` and `chore`.
- Do the work on `main`, and push to `main` (the owner chose this for
  the start of the project). Open a pull request only when the owner
  asks.
- Commit with the identity of the owner, with no trailer:

  ```sh
  git -c user.name="Sơn Trần-Nguyễn" -c user.email=github@sntran.com \
    -c commit.gpgsign=false commit
  ```

- Look at each new or changed model on the review page
  (`scripts/shot.mjs`) before a commit, from the front, the side and
  three quarters. `FOCUS=x,y,z ZOOM=4` gives a close view of a point
  (an engine bay, the inside of a cabinet).

## The tools

- [BEAM.com](https://github.com/sntran/BEAM.com) 0.1.0-rc.6: Erlang/OTP
  29.1.1 and Elixir 1.20.4 in one file (`CONTRIBUTING.md`).
- The core of Wings 3D in `wings/`: the modules of the mesh, with no
  window (below).
- The Khronos glTF validator (`gltf-validator` on npm) for each GLB.
- [Accord](https://github.com/sntran/accord), the branch
  `feat/native-tla-checker` (dev and test only): the native TLA+ checker,
  with no Java, for `specs/` (`docs/specs.md`).
- The review page (`review/index.html`): three.js from a CDN, each model
  of `priv/models` from 12 cameras, with a slider for each joint.
  Playwright makes the pictures in CI. The replay page
  (`review/replay.html`) reads the log and the replay GLB of an order:
  `?log=URL&model=URL` for a local test. The world page
  (`review/world.html`, the index of the site) reads the stream of the
  node and its places (`GET /places`), and draws the map of the yard:
  `?events=URL&places=URL&files=URL` for a local test.

## The contexts

`World` is the project. Each module under it is a part of the world.

| Module | What it holds |
|---|---|
| `World.Vec`, `World.Frame`, `World.Mesh`, `World.Shape` | Points, frames, meshes and the shapes of parts: the matter of the world. |
| `World.Part`, `World.Port`, `World.Assembly`, `World.Joint`, `World.Limb`, `World.Figure` | A part, its ports, an assembly of parts, a joint (hinge, slide or ball, with its limits), a limb (a chain of bones and its solver), a figure with a skeleton, its joints, its limbs and its props. |
| `World.Detail`, `World.Build`, `World.Scene`, `World.GLB`, `World.PNG`, `World.Textures` | The levels of detail (and `collect/1`: a full garbage collection after a big step of a build, for the 128 MB of the edge; none in `lean(false, fun)`: the people of a construction with no `memory_mb`), the build of a model into a scene (`parallel: true`: a process for each material, for the join of a construction; a big mesh in many parts, or a mirror, is in the scene once: nodes share it; 16 copies or more in one node are one node with instances, `EXT_mesh_gpu_instancing`; a part that stretches, `"stretch"` in its params, is a skin between two nodes), the GLB writer, the PNG writer, and the textures that World makes (`World.Textures`: washed stone, for the `texture` of a role of a drawing, at near). |
| `World.Kit` | Small helpers for the shapes of items (inches, round boxes, handles, feet). |
| `World.Materials` | `Stock` (tubes, lumber, sheets, extrusions), `Fasteners` (bolts, nuts, screws), `Construction` (bricks, blocks, lintels, tiles, panels, a butt hinge in its two halves), `Webbing` (a strap of webbing or leather along a path, a side-release buckle, a D-ring, a tri-glide, a pin buckle, hook and loop: for a helmet, a sandal, a bag, a harness). |
| `World.Framing` | T-slot extrusions, strut channel, L-track, and `Builds` from them. |
| `World.Buildings` | Walls, roofs, doors, windows and houses, from the materials. |
| `World.Buildings.Lot` | A whole house on a lot of Vũng Tàu in 2019, cheap for a town (W17, W23 of Vũng Tàu): a tube house, a shop house with a high ground floor, a villa behind a yard with a fence and a gate, or a mini-hotel of 5 to 8 floors with a vertical sign (each kind with its range of floors and its defaults); 3 to 6 by 8 to 25 m, old or new, a flat terrace, corrugated metal or clay tiles, a cửa cuốn on a slide, a cửa xếp, a door with a gate or an open shop, a plain, granite or tiled front, each side wall shared, free or bare brick, a room at the back, a room on the terrace; the seed picks the balconies, the cages and the places of the windows, and the paint age goes into the extras. The ports of the small parts (W18: an AC, a rail, pots, the sign, the number, the altar, the tank, a dish, an antenna, a laundry pole, the wires) go into `NAME.parts.json` (`World.Build.parts_file/2`), not into the GLB; the collision boxes (W20) are nodes `NAME-colonly` of the GLB (`World.Build`), and `interior: front_room` gives a room that a player can enter, with its stairs. Each wall is one closed slab with holes (`sheet/8`). Three levels in the limits of W22 (near 40,000, mid 3,000, far 300). The blueprint `lot_house`; the catalog has `nha_ong_4x16`, `nha_ong_cu_4x18`, `nha_ong_5x20`. |
| `World.Buildings.Panel` | The panel of a wall, a slab or a roof: one closed slab with holes, with the knots of `World.Surface` (`sheet/8`): the walls of a lot house and of a house of the people. |
| `World.Surface` | The data of the walls of a building for the shader of an app: UVs in meters, the height and the distance to the nearest corner in `TEXCOORD_1` and in `COLOR_0` (`docs/format.md`, "GLB"). `World.Build.scene/2` gives it to a model with `"surface"` in its extras. |
| `World.Furniture` | `Seats` (seats and benches), `VanBuilds` (a bed platform, a galley). |
| `World.Appliances` | The appliances of a house, and `Systems` (the water heater, the AC, the fans, the TV). |
| `World.Gear` | `PowerStations`, and `Camper` (the gear of a camper van). |
| `World.Vehicles` | `Wheels`, `Corners`, `Body`, `Hull`, the `Van` line and its stations, the order of a van (`Van.Order`: its doors, windows and rows of seats as numbers), and each vehicle (`FordTransit`, `ChevyBolt`, `HondaVision`, `RoyalEnfieldHimalayan`, `TouringBicycle`). |
| `World.Openings` | The openings factory: the doors and the windows of all kinds, each an assembly of the kind `:door` or `:window`: the prehung door (`prehung/4`), the overhead door of a workshop (`overhead/4`) and the window (`window/5`) of a building; the doors, the windshield and the windows of a van to the numbers of its order (`World.Openings.Van`). |
| `World.People` | The people of the catalog, `Human` (a person from the data of MakeHuman), `Face` (the 15 visemes for speech, from the units of the expressions of MakeHuman), `Skin` (the skin that is not like plastic: the sheen, the pores, the creases), `Data` (the data of MakeHuman; the sliders of the shape; the macros `name!/2`, `names!/2` and `asset!/2` check each name of an asset in the code when it compiles: use them for each literal name), `Skeleton` (the joints: flex, spread, twist, limits, aim, look, the hips, the spine, the hands and the feet to points), `Joints` (the joints and the limbs of a person, for an order), `Props` (the props on the ports of the bones: a fan, a bottle, a nón lá), `Pose` (the poses, the shapes of a hand, the animations, the routines of exercise). `World.People.exercise/2` is a group at a morning of exercise. `Kit` (the kit of a person: the parts of the parked traveler as static files at `/kit/`, for a viewer that joins them with no build; `docs/factory.md`, "The kit of a person"). |
| `World.Mass` | The mass of the things of the world: the density of each material role (`priv/standards/materials.json`), or a number (the density of a laminate), the volume and the centroid of a closed mesh, the area of a mesh (for a skin, `World.Mesh.skin/3`), the mass of a part (its data sheet when a shop buys it: `"mass"` in its params; 0 with no meshes; nil with an open mesh that is not a skin, or a role with no density and no `matter`), and the mass and the center of mass of a model (`of/1`, with the names of its parts with no mass). |
| `World.Contact` | The contact of a body with the things round it: an obstacle is a closed mesh at its place (`solid/2`) or a function of a point (the woven wall of a basket); a point is in a closed mesh when a ray from it goes through its faces an odd count of times (`inside?/2`, also for `World.Check`); the points of the skin of a figure in its pose (`points/1`); the most of a move before the first touch (`reach/3`: in 16 equal parts, then by halves, so a thin slat stops the body); a figure that leans to the joint values that it wants and stops at the first touch (`lean/5`). |
| `World.Check` | The checks of a true model: it stands, no two parts are in one place, its joints are in their limits, and it goes through the door of its workshop (`model/2`, `message/1`). `World.Orders.place/2` refuses an order with a model that fails. A new model of the catalog must pass (`test/world/check_test.exs`): give a thin part a skin, and join the parts that touch by a connection. |
| `World.Standards` | The standards of the world in `priv/standards/*.json`, read when it compiles: the fasteners (ISO, ASME), the stock (US lumber, the sawn timber of Việt Nam of TCVN 1075:1971, ISO 15 bearings, ASME B36.10M steel pipe), the rules of a wooden hull (QCVN 91:2025/BNNMT), the headforms and the limits of a helmet (QCVN 2:2021/BKHCN) and the units of masonry, each table with its source, its unit and its fields. `size/2`, `tuples/1`, `part/1` (a part by its standard name: `{:bolt, "M8x40"}`), and the macro `name!/2`, which stops the compile on a wrong literal name: use it for each literal name of a standard. |
| `World.Lathe` | The lathe of the world: a part turned from a profile (`{r, z}` points, a smooth curve), solid or a vessel with a wall and a floor, with fewer sides far away; its volume by Pappus and its capacity in its extras. An assembly of the kind `:turned`: the turnery of the run makes it. |
| `World.Sheet`, `World.Enclosures` | The sheet metal shop (the trade `sheet_metal_worker`): a part bent from one flat sheet (a base, a flange of 90 degrees on each edge with a return lip, the corner reliefs, the holes; the flat pattern with the bend allowance of each bend, K = 0.44), a panel pressed from a blank in a die (`stamp/4`: the body, the hood and the doors of a van), and the enclosures of steel sheet from it (`hoffman_a16n126/0`, the kind `:enclosure`). The gauges of steel sheet: `World.Materials.Stock.gauge/1`. |
| `World.Loft`, `World.Molds` | The mold shop (the trade `molder`): a shell of one thickness over sections along a spine (superellipses in frames with no twist; an apex is one point; an open arc gives an open shell), its area and its closed mesh; and the shells from it (sections of superellipses or of measured rings; `grow/2`); `World.Molds.headform/1` (the nine headforms of QCVN 2:2021/BKHCN, from `priv/standards/helmet.json`) and `half_helmet/2` (the kind `:helmet`, on a headform: the shell, the liner, the comfort pad, the edge trim, the rivets, the peak, two straps and a buckle, each a part of its own; under the mass limit of its size; `vision_up/2`); `shell_chair/1` (the kind `:chair`: a seat shell of glass fiber on four legs of steel tube). `World.Materials.Laminate`: a laminate of glass fiber and resin laid up by hand (`priv/standards/laminate.json`): its plies, its thickness (ISO 12215-5), its mass and its density. |
| `World.Footwear`, `World.Footwear.Last`, `World.Footwear.Sole`, `World.Footwear.Upper` | The shoe shop (the trade `shoemaker`, the kinds `:sandal` and `:clog`). The parts that each shoe combines: the last (the footprint of a bare foot of MakeHuman, `World.People.Human.footprint/2`; the length of the last, the rows of the foot, the gap of the toes, the EU size), a stack of soles (layers of EVA, rubber, tire or vông wood, each on the one under it, with a rim or a tip turned up), and the paths of the straps (over the foot, round the heel, the Y of a thong, two that cross, one wide band), their closures (a D-ring with hook and loop, a pin buckle), nails and plugs. The models: `sandal/1` (a sport sandal, of webbing or of leather), `thong/1` (dép tông), `tire_sandal/1` (dép lốp), `clog/1` (guốc mộc, flat or with a high heel), `honeycomb/1` (dép tổ ong: a lattice vamp, `Upper.lattice/5`), `geta/1` (a board on two teeth, `Sole.teeth/4`, and a hanao), `slide/1` (dép quai ngang); each is a right shoe, and `pair/1` (each model of the catalog) puts it beside its mirror, the left shoe. |
| `World.Furniture.Bamboo`, `World.Furniture.Bamboo.Culm`, `World.Furniture.Bamboo.Panel` | The bamboo shop (the trade `bamboo_worker`, the kind `:bamboo`). The parts that each piece of furniture combines: a piece of a culm of tầm vông (`Culm.piece/3`: a hollow tube with the rings of its nodes, each end open or closed at a node; its mesh is its wall), a slat split from a culm (`Culm.slat/6`), a cord of nylon (`Culm.cord/2`), a rail through the legs with its ends out (`rail/4`), and the panels on a rectangle of a frame (`Panel`: slats side by side, thin culms side by side, a lattice, and a lashing of two zigzag cords). The models, by eye from the photos of the shops that the owner sent: `chair/1` (ghế tre lưng tựa đứng; `cushion: true` a hard pad of the sewing shop tied to the rear legs, the model `ghe_tre_dem`), `folding/1` (ghế xếp on two frames in an X, a back of uprights or of bars; the rear legs and the seat turn on hinges of the role `:fold`, the pins of the rear legs (`pin/2`) are tight in the legs and turn with them, and the rear rail of the seat is its axle through the posts, and the clip `fold` folds it flat), `armchair/1` (ghế bành with a back of slats or of lattice; a wide one with three panels is the bench, ghế băng), `table/1` (bàn tre with a top and a shelf of slats). |
| `World.Furniture.Hanging`, `World.Furniture.Hanging.Bed`, `World.Furniture.Hanging.Rig` | The hammock shop (the trade `rigger`, the kind `:hanging`): the things that hang and swing, from the same parts. A bed (`Bed`): its middle line is a catenary of its length over its span (`catenary/3`); each thread along it has the full length of the bed, so the edges hang almost taut and the middle deep, and across the middle it is as wide as the flat cloth (`surface/3`); its ends gathered (a võng, a camping hammock), on short bars (a võng xếp) or on spreader bars; a sheet of cloth in bands across (`cloth/2`: stripes, hems) or a net of cords in diamonds with an edge cord (`net/2`); the whipping of a gathered end (`whipping/3`). The rig (`Rig`): ropes, chains, rings, the cords of the ends (`fan/3`), hooks, carabiners, swivels in two halves, tree straps, and the anchors of a site (`trunk/4`, `post/4`, `beam/3`, the kind `:site`). `hang/4`: the anchors from the hang of The Ultimate Hang (the suspension at 30 degrees, the ridgeline at 83% of the length, the lowest point at the sit height). With a person in it, the middle line is a parabola under the body and straight out of it (`loaded/4`): the bed sags more. The models (with `person: true`, a person lies in the bed or sits on the seat, `lie/4` and `sit/4`: the hips on the bed or the seat, the pose from the line of the bed or `"sit"`, the hands on the ropes by the limbs of the person; `lean:` and `obstacles:` of `sit/4`, the back leans as far as the person wants and stops at the first touch, `World.Contact`): `cafe/1` (võng lưới and võng dù between two posts), `vong_xep/1` (a net on two bars on the frame of steel of Duy Lợi; `vong_xep_frame/1`, the frame alone as it folds, with the clip `fold`), `iron_stand/1` (the arched stand of a photo), `camping/1` (ENO, between two trees: its stuff sack on its edge, `shelter: true` a tarp and a bug net on cords from tree to tree, `person: true` a person who lies in it at an angle, the diagonal lay, `lie/4`), `camping_packed/1` (the hammock in its sack, the one that a hiker carries), `spreader/1` (canvas or rope, on spreader bars), `plank_swing/1` (`cushion: true` a pad tied to the ropes), `tire_swing/1`, `porch_swing/1` (the person leans back to the slats; `cushion: true` a seat cushion and a back cushion tied to the top slat, `World.Sewing.Cushion`), `egg_chair/1` (a seat cushion in the bowl and a back cushion with tufts; the person sits on them and leans back and to the side to the cushion or the wicker; on a spring: `Rig.spring/3`, its rate and stretch, a slide of the role `:bounce`; its coils stretch with the slide). A thing on two anchors swings on one hinge about the line through them; a thing on one point swings on two hinges at the point and spins on its swivel (the role `:spin`); the site and its hooks stay. A model with the site has `"site" => true` in its extras: `World.Check` checks no stand. |
| `World.Mirror` | The mirror image across the plane x = 0 of a mesh (its faces turn over, so the outside stays outside), a port, a frame (still a turn), a part and an assembly (each node at the mirror of its place: the turn of a connection, the value of a hinge and its limits change sign). The left shoe of a pair; any left part of a thing. |
| `World.Boats` | The boats of the boatyard (the trade `shipwright`, the kind `:boat`): `World.Boats.Ghe`, the ghe of Vũng Tàu, its members to QCVN 91:2025/BNNMT (`priv/standards/qcvn91.json`) and sawn to Bảng 1 of TCVN 1075:1971 (`World.Materials.Stock.vn_section/2`). |
| `World.Plants` | The nursery (the trade `gardener`, the kind `:plant`): a plant from the rules of its species (`priv/plants/species.json`, each number with its source): `coconut/1` (a trunk that leans, fronds with leaflets in a V, nuts), `banana/1` (a pseudostem, leaves that droop, a bunch), `bamboo/1` (a clump of culms that arch out, branches with sprays of leaves), `frangipani/1` (the forks of the model of Leeuwenberg, rosettes of leaves, flowers in their months, no leaves in the dry season). Three levels: fewer leaflets, leaves and sides far away; a plant grows in the ground, so `World.Check` checks no stand and no door. |
| `World.Places.StreetKit` | The street kit of Vũng Tàu (W21): pieces of the sidewalk, the gutter and the paving of a hẻm (straight 2 m, corner, junction), the ramp cut, the concrete pole with its wire ports, the transformer and the meter boxes on it, the street lamp and the bin of 240 L; each a model of the kind `:street` with three levels and its ports in `parts.json`. |
| `World.Cast` | A solid cast from surfaces on a grid of cells: the fill of the outside, the signed distance near the surface, a hollow with a wall and openings, and the closed mesh by surface nets (each edge in two faces). Overlapping shapes (a body in a robe) become one shell with no gap. The cast is steps that many people do at the same time: `survey/2`, the `marks/2` and the `distances/4` of the bands of `bands/2` (in any order: `merge/1`), `outside/2`, `field/4`; the mesh in slabs (`surface/1`, `quads/2`, `join/3`). |
| `World.Skill`, `World.Skills` | A skill of a trade: the behaviour (`name/0`, `trade/0`, `check/2`, `make/3`, `estimate/2`, and the takeoff `materials/2`: the materials of the stock that a task needs, before it starts), pure, and the skills by their names (a name in a drawing makes no atom; the application environment can add skills). A node of a drawing names a skill and its data; the person of the trade runs it. |
| `World.Skills.Statue`, `Figure`, `Robe`, `CastSurvey`, `Formwork`, `CastOutside`, `Pour`, `CastField`, `ShellSlab`, `Shell`, `Grille`, `Halo`, `Carve`, `Set`, `Base`, `Stair`, `Rail`, `Site` | The statues (W13 of Vũng Tàu) as skills of their trades: a figure of a person at any size, in a pose (`arms_out`, the span and the hands of the sculptor), in a robe, cast as one solid of concrete or stone (`World.Cast`; at near the head and the hands carved from the full mesh of the person), with a halo and its rays, on a plinth and a base with reliefs and a rail; `hollow` gives the walls, a spiral stair, windows and balconies at near. The blueprint in data `priv/blueprints/statue.json`; the catalog has `tuong_chua_kito_vua` (Núi Nhỏ), an order in `priv/drawings/`. Each size of an order has its source in the extras (`"sizes"`); a size with no source is an estimate. `docs/format.md`, "A statue". |
| `World.Skills.House`, `HousePlan`, `Footing`, `Column`, `Slab`, `Course`, `Plaster`, `Paint`, `Opening`, `Iron`, `Flight`, `Roof` | A house as on a real site (plan 0002, D4): the plan of an engineer, the frame of reinforced concrete floor by floor, the infill of bricks in bands of courses by many masons at one time, the render and the paint, the doors, the windows and the shutter, the stair, the rail and the roof. The blueprint in data `priv/blueprints/tube_house.json`. `docs/format.md`, "A tube house that the people build". |
| `World.Skills.Van`, `VanOrder`, `VanBody`, `VanInside`, `VanClosure`, `VanTrim`, `VanGlass`, `VanSeats`, `VanChassis`, `VanUpfit` | A van as on the line of its maker (plan 0002, D5): the order of an engineer, then at the same time the body, the inside, the hood and each door, the trim, the glass, the seats, the engine bay, the drive, each corner and the items on the roof, each group of a station (`groups/0` of `World.Vehicles.Van.Closures`, `Trim`, `Chassis`) on a mark at the origin of the van. The blueprint in data `priv/blueprints/van_line.json`. `docs/format.md`, "A van that the people build". |
| `World.Skills.Vehicle`, `Wheel`, `Knuckle`, `BicycleFrame`, `BicycleFork`, `Crankset`, `Spring`, `Fastener`, `Frame`, `Swingarm`, `Fork`, `Engine`, `Panel`, `Body`, `Glass`, `Seat`, `Lamp`, `Stand` | The skills of the vehicle trades, for any vehicle (plan 0002, D5): a spec sheet where a trade has one (a wheel from its tire code, a knuckle, a bicycle frame and fork from their geometry, `World.Vehicles.Bicycle`, a crankset, a coil spring, a fastener), and shape data for the free shapes of a model (`World.Skills.Vehicle.part/3`). No skill names a model. The blueprints in data `bicycle.json`, `scooter.json`, `motorcycle.json`, `car.json`. `docs/format.md`, "The vehicles that the people build". |
| `World.Places`, `World.Stock` | The places of the yard of the node (plan 0002, D6; `priv/places.json`): the gate of the suppliers, the warehouse, the factories (each with the kinds of the models that it makes) and the site, at points in meters, with the drive between two at the speed limit of the yard; the building of each (an order of a house that the people build), the trucks (an order of a van, and its load); the stock of the warehouse in the units of a site (bricks, bags of cement, bars of rebar, bags of mortar, cans of paint, roof sheets, steel bars), a take and what is short, and the loads of a takeoff for a truck. |
| `World.Haul`, `World.Truck` | The haul of the yard (plan 0002, D6 and D8; `specs/Haul.tla`): the takeoff of a task from the open warehouse, or from the gate of a supplier, in the loads of a truck; each load on a free truck of the yard (a process with its driver: it drives to the source, takes the load, drives to the place, puts it down), or on a truck that the haul rents while the yard has none; the word to the construction when each load is there; its log (the order `haul`). A construction with `haul` and `place` in its job gives a task only after its materials are there (`parts_asked`, `parts_here`). |
| `World.Yard` | The yard of the node at its first start (plan 0002, D7; `specs/Places.tla`; with `WORLD_YARD=true`): it raises the buildings of the warehouse and the factories (houses that the people build on their lots), opens each place when its building is done (`place_open`; the haul then takes from the stock of the warehouse), makes the trucks at the factory of the vehicles when it opens (`truck_made`: each joins the haul), and starts a model in data at the place of its kind when it is open (`place_started`), or holds it until then (`place_held`). `World.build/1` asks it. |
| `World.Measure` | The measures of a model as the standards define the numbers of a real blueprint (plan 0003, D2): the box with nodes left out (the width of SAE J1100 has no mirrors), the axles (the joints of the role `wheel`), the wheelbase and the tracks, the ground clearance (the lowest face between the axles), the top of a node (the seat height), a port of a node in the axes of the model (the geometry of a frame), the curb mass, and the bill of quantities of a drawing (the sum of the takeoff of its tasks). |
| `World.References` | The references of World (plan 0003; `priv/references/`, `docs/references.md`): real things with their published numbers, the order that builds each, and the measure of each number; `run/2` has the people build it and compares each number with its tolerance. `mix world.references` prints the report. |
| `World.Sizes` | The sizes of an order of a known place with their sources (`check/3`, and `none/0` for a size with no source); `World.Drawing.fill/2` puts them into the extras of the model and the receipt; a size with no source is an estimate. |
| `World.Skills.Towers`, `TowerBody`, `Lantern`, `Tower`, `SpiralStair`, `TowerSite` | The towers (W13 of Vũng Tàu) as skills of their trades: a lighthouse of masonry on a round platform (the body, the pilasters that flare at the foot, the bands, the cove, the gallery and its rail, the drum, the lantern with its panes and lens, the dome, the rod), hollow at near with a spiral stair; a house next to it is a model of its own. The blueprint in data `priv/blueprints/tower.json`; the catalog has `hai_dang_vung_tau`, an order in `priv/drawings/`. `docs/format.md`, "A tower". |
| `World.Places.OSM` | A street from a tile of OpenStreetMap (`priv/osm/NAME.json`, ODbL): the buildings from their footprints and levels, the roads (cut at the box of the tile) of their widths with curbs, the trees as plants of the nursery; the points on a plane of meters at the center of the tile (WGS 84). The kind `:street`: the houses factory builds it on its site. |
| `World.Turned` | The parts of the turnery, each with its sources: `chen_tra`, `bat_com`, `bottle_longneck_355ml`, `baluster_con_tien`, `pot_terracotta_8in`. |
| `World.Sewing` | The sewing shop of the world: a garment is pieces of one fabric, each cut from a pattern on the base mesh of a person (MakeHuman: the body or its skirt), with its ease, joined at seams, on a layer (0 next to the skin, 1 pants, 2 a top, 3 a jacket). A fabric has its thickness, its span (the drape over the dips of the body, at the fit, on the body of the person) and its grain. A garment can give a shape to the body (the cups of `world_bra`). The garments: `world_bra`, `world_ao_dai` (a bodice, sleeves, a stand collar, two panels with slits), `world_quan`, `world_t_shirt`, `world_pants`, and the jackets `world_rain_shell`, `world_softshell`, `world_down_jacket`. `scripts/clothes.exs` writes their files in `priv/makehuman/clothes/`; `World.People.Human.dressed/1` gives the points of each item on a body, for the checks of the layers. |
| `World.Sewing.Cushion` | The sewing shop (the trade `sewer`, the kind `:mattress`): the cushions and the mattresses. A box cushion (`box/2`: a top and a bottom panel of the outline, a boxing strip, piping in the two seams; a fill that takes the shape of a bowl under it), a pad with a knife edge on a curved face (`pad/2`: two panels, tufts with buttons), ties round the bars of a frame, and a mattress (`mattress/2`: layers on a core, a cover of ticking, a tape on each seam, a quilt of diamonds). The fill is in layers (`layers`, each `{fill, thick}`): soft (`:foam`, `:fiber`), hard (`:hd_foam`, `:molded`, a `board` of plywood under it: a drop-in seat), and the fills of mattresses (`:hr_foam`, `:memory_foam`, `:latex`, `:coir`, `:pocket_coils`), each with its density and its source; the covers `:canvas` (271 g/m2) and `:ticking` (200 g/m2). A cushion is a part of the kind `:cushion` with its cut list (each piece with its area and a seam allowance of 1/2 in), its layers, its mass and its sources. A person sinks into the fill (`squash/1`, the mean of the layers); `solid/2` gives the squashed cushion as an obstacle of `World.Contact`. The models (`models/0`): `nem_cao_su_160` (natural latex, 160 by 200 by 10 cm), `nem_lo_xo_160` (pocket coils and foam, 25 cm), `nem_xo_dua_120` (coir and foam, 120 by 200 by 10 cm). |
| `World.Rig`, `World.Blob`, `World.Subdivision` | A figure from bones, with a skin: a base mesh with its weights, a material for each face and a color for each point, smooth by subdivision (Catmull and Clark), or a smooth skin around the bones (a field of distances, surface nets); parts on bones (horns). |
| `World.Animals`, `World.Animals.Quadruped`, `World.Animals.Primate`, `World.Animals.Fish`, `World.Animals.Bird`, `World.Animals.Shape`, `World.Animals.UV`, `World.Animals.Space`, `World.Animals.Coat` | The animals: a species is numbers on a template mesh (`priv/animals/templates/`, `World.Animals.Shape`: the shape, the coat and the length of the fur by region; `World.Animals.UV`: the UVs, box charts for each bone; `World.Animals.Coat`: the texture of hair of a mammal, a PNG that World makes for each kind of hair (short, long, curly, wool); `World.Animals.Space`: a shape space learned from the templates, `scripts/shape_space.exs`) of a body plan in code. Four legs: the eleven animals of the Ultimate pack of Quaternius on one rig, from `scripts/gltf_figure.exs`, and the pig and the sheep of its Farm Animals Pack (`scripts/fbx_gltf.exs` reads the FBX files; they take the clips of the cow and the deer), with their clips (walk, run, idle, idle_low, eat, attack, kick, jump, jump_stop, hit_l, hit_r, death) from `scripts/gltf_clips.exs` in `priv/animals/clips/`. Primates: the mesh of a rhesus macaque of BigMaQ (`scripts/primate_template.exs`, MIT), on the bones of a person with the fingers, on four limbs or upright (the gibbon), with hands that grip, and the walk, the run and the sit of real macaques (`scripts/bigmaq_clips.exs`, CC BY). Fish (`World.Animals.Fish`) and birds (`World.Animals.Bird`): templates that World makes from their bones (`scripts/fish_template.exs`, `scripts/bird_template.exs`), with a swim, and a walk, a peck and a flap. Now: `street_dog`, `cat`, `wolf`, `fox`, `deer`, `goat`, `pig`, `horse`, `donkey`, `cow`, `water_buffalo`, `sheep`, `alpaca`, `husky`, `red_deer`, `hyena`, `macaque`, `rhesus_macaque`, `pig_tailed_macaque`, `douc`, `gibbon`, `carp`, `tilapia`, `chicken`, `duck`. |
| `World.Drawing` | A model in the data of an order: its check (each error with its path), the repeat of a node (`expand/1`), the temporary nodes, the fill of a blueprint in data (`fill/2`), the make of each node (a part, an item, or a skill of a trade: `make/3`), and its build into an assembly (`build/1`, `assemble/2`). |
| `World.Orders` | An order in, the files out (its blueprint by name, a blueprint in data of a project in the order, or `{"hash": HASH}` of one that `POST /blueprints` keeps: `keep_blueprint/1`): `Blueprint` (also a blueprint in data, `from_data/1`, and its check, `check_data/2`), `Blueprints` (with the files of `priv/blueprints/`), `Store` (the full orders in R2, through a port of the VM), `Set` (a set of variants from one list: `POST /sets`, W19 of Vũng Tàu). |
| `World.MCP` | The MCP server of the factory (`/mcp`): the tools `list_blueprints`, `get_blueprint`, `check_blueprint` (a blueprint in data of a project: its errors, or its options, its hash and its plan), `check_order` and `place_order`, for the engineers `check_drawing` and `propose_drawing`, and for an architect `plan_build` (the tasks, the trades and the triangles of an order) and `build` (a construction to watch). |
| `World.Engineers` | The engineers (step P9): the review of a new drawing (its errors, the checks of `World.Check`, its mass, its size, its parts), a proposal in the store (`proposals/HASH.json`), and the accept of the owner into `priv/drawings/` (`mix world.review`). |
| `World.Catalog` | Each model of the library by its name. |
| `World.Service`, `World.Application` | The HTTP service of the VM, and the application. |

The node of `docs/world.md` (plan 0001):

| Module | What it holds |
|---|---|
| `World` | The door of the node: `build/1` (a job and its budget), `await/2`, `watch/1`, `budget/1` (the check of a budget, each error with its path), `census/0`, `memory/1`. |
| `World.Supervisor` | The supervisor of the node: the registries `World.Names` (a construction by its id) and `World.Events` (the watchers), the log of the node, the dynamic supervisors `World.Persons` and `World.Constructions`, the census, the haul and the yard when `WORLD_YARD` is `true`, and Bandit when `WORLD_SERVER` is `true`. |
| `World.Census` | The people of the node: the free people by trade, the person that each construction holds, the constructions that wait (the one that holds fewer people first), and the limit of the node. At the limit, a free person of another trade leaves for a new one. |
| `World.Person` | A person of a trade: a process with its PID as its name. It does one task at a time for the construction that hires it, and sends the result back. |
| `World.Construction` | A construction: the plan of a job (`World.Plan.flat/1`, the level that fits the budget of triangles), a hire for each ready task, the elements that its people make (a GLB for each new mesh), the join of the model, the deadline, and the log. Its urgent messages (the deadline, a person that stops, a pause, a resume, a cancel) are messages of priority (OTP 28), to the alias that is the value of its name; a change comes in a pause. With `memory_mb`, each task has a limit of its heap. |
| `World.Plan` | The tasks of a model, from the tree of its assembly, each with its trade (`trade/1`: the kind of an item to the trade of its people). |
| `World.Log` | The events of a construction in the order of their time, in JSON, and their checks. `World.Log.Server`: the log of the node, with an id for each event, its watchers, and its store (`World.Log.Store`, the SQLite of the Durable Object through the port `/env/LOG_STORE`). |
| `World.Stream` | The stream of the events to one client (`text/event-stream`): it watches, sends the events of the past after `Last-Event-ID`, then follows. |
| `World.Program` | A program of the VM through a port: the stores of the orders and of the log use it. |
| `World.Clock` | The clock of the world: one second of the wall clock is one day of the world. |
| `World.Store` | The store of the files: the memory of the VM, a bucket (a folder on this computer), or the catalog of the release (read only). |

## The core of Wings

`wings/` has a copy of the modules of Wings 3D that build, change and
read a mesh, from [dgud/wings](https://github.com/dgud/wings) at a fixed
commit (`wings/VERSION`). `scripts/wings.sh` copies them again from a
new commit. The copy changes only these things:

- `wings.hrl` has no lines that include the headers of wx and SDL.
  `-include_lib("wings/e3d/e3d.hrl")` becomes `-include("e3d.hrl")`.
- Three small modules take the place of modules of the window:
  - `wings_pb` (the progress bar): each call does nothing.
  - `wings_lang` (the texts): `str/2` gives the default text.
  - `wings_plugin`: `check_plugins/2` gives `[]` (no plugin state to
    keep in a merge).
- No image codecs of `e3d` (`e3d__png`, `e3d__tif`, and more).

`intl_tools` (the parse transform of the texts) compiles first.

## The decisions

| Topic | Decision | Why |
|---|---|---|
| The name | World: the OTP app `:world`, the module `World` (the door of the node), and a context of the world for each family of things (`World.People`, `World.Vehicles`, `World.Buildings`, `World.Materials`). The repository is `sntran/World`, the Worker is `world` at <https://world.mkfifo.com>, and the R2 bucket is `world`. | The project builds things as the real world does: people, materials, warehouses and factories. Each context is one part of the world, not a kind of file. |
| The levels of a model | Standard parts, shaped parts, assemblies. | A model is made as a real thing is made. The joints and the list of the parts come from the connections. |
| The language | Elixir, on BEAM.com. | DIY and Phượt are Elixir. The core of Wings is Erlang, and runs in the same VM with no window. |
| The source of a shape | Code for a standard part. A `.wings` file for a shaped part. | Wings 3D is free, small, and in Erlang. A person can open each part, change it, and save it. |
| The one format | GLB (glTF 2.0) for the screens. STL only for a printer. | Godot, three.js, Android and MapLibre read GLB. GLB has nodes for the joints, materials, and levels of detail. STL has none of them. |
| The joints | From the connections of an assembly. Rigid joints first (each part follows one joint). | They cover vehicles, furniture, machines and the figures of Tre. A person has a skin (a mesh that bends) from the skeleton of MakeHuman. |
| The people | The data of MakeHuman (CC0) in `priv/makehuman/`: a body from its numbers, the skeleton `game_engine`, skins, hair and clothes. A low-poly body of MakeHuman at mid and far. | Real shapes and real weights, free to use. A person is a `World.Figure`, and an assembly holds it at its port `hips` or `ground`. |
| The animation | Data in the format (poses), not a timeline in Wings. | The apps move the models in code: the wheels turn with the speed, the legs of Tre swing in a walk. |
| Voxels | A separate kind of model in `.vox`, and a voxel maker from any model. | The mesh of Wings cannot hold blocks that touch at an edge or a corner. Tre needs blocks at its own sizes. |
| The axes | Right hand: x to the right side, y to the front, z up, in meters. The origin of a model on the ground at the center of its box. | One rule for each model. The GLB writer turns the axes with no mirror. |
| The colors | A role of material. The palette of the package, and a palette of each app. | One model, the colors of each app. |
| The files of the build in Git | Yes, with a check in CI. | An app reads the files with no build. |
| The way the projects use World | A web service, the factory at <https://world.mkfifo.com> (`docs/factory.md`), not a library in each app. | Phượt, DIY and Vũng Tàu are on Cloudflare. A model has a URL, and a correction of World reaches them with no new deploy. |
| The MCP server | `World.MCP` in the VM at `/mcp`: Streamable HTTP with no state and no event stream, four tools on the same check and the same store as `POST /orders` (`World.Orders.place/2`). | An MCP client of another project orders a model with no code of its own. The orders and their logic stay in Elixir, with the tests at 100%; the build of a file stays at its first `GET`. |
| The work of the Worker and of the VM | The VM has the orders: the check, the store of the full orders (R2 through the port `/env/ORDER_STORE`, `World.Orders.Store`), `POST /orders` and `/mcp`. The Worker has the cache of the built files (`builds/` in R2) and of the hash of the order of each URL `/m/` (`urls/` in R2), and sends the other requests to the VM. | A file that R2 has goes out with no VM: no cold start of a Durable Object, and no wait behind a build in the same VM. The code of the Worker stays small. |
| Orders | Data in JSON, never code: a blueprint, its options, colors and joints. The hash of the full order names its files. | An order can come from any project and any language. The same order gives the same files. |
| Joints as in real life | A joint turns on the real axis (a pin, an axle, a rail that turns in its holes). Each piece of its hardware is a part of its own on the node of the part that it is fixed to: the leaf of a hinge on the door turns with the door, the pin goes with the member that holds it tight, and a rail that is its own axle has no pin (`docs/format.md`, "A joint as in real life"). | The model moves as the real thing moves, and its list of parts is the real list. |
| Realism | The sizes from a standard, a data sheet or a drawing, and the shape from photos of the real thing, never from a memory. A render and a photo side by side before a commit. | Phượt and Vũng Tàu need models that look real. |
| The world | The node is the world (`docs/world.md`, `docs/plans/0001-people-build-on-demand.md`): the people of the node are processes of a trade, a construction hires them from the census, they build each element of a model at the same time, and anyone can watch the stream of the events. Many constructions share the people. | A model is made as a real thing is made; the world makes it as the real world does. A game watches a model as it grows. |
| The flows of the node | Each flow of messages between processes has a TLA+ specification in `specs/` (`docs/specs.md`), with a fault model for each rule; the log of a real construction replays in `specs/Build.tla`. | A test sees one order of the acts; the checker sees all of them. It found a dead end of two constructions and an id of the log that names two events. |
| The license | AGPL-3.0. The core of Wings keeps its own terms in `wings/LICENSE`. | The models stay free, and nobody can close them. |

## Known problems

These come from the tests before the repository, with the core of Wings
on BEAM.com, on the 77 models of DIY, the shape kinds of Tre, and 42
trees from Blender:

- **Floats only.** The core of Wings fails on a box or a prism with
  integer points. `World.Mesh` changes each point to floats.
- **A flat face has two faces.** One polygon alone fails in
  `wings_we_build`. A flat part (a label, a window) has its front and its
  back.
- **One order of corners.** A mesh with faces in two orders fails in
  `wings_we_build:combine_half_edges`. A function that makes a mesh gives
  each face the same order, then turns the whole mesh when its volume is
  less than 0.
- **The name of a material is an atom.** A face with a string as its
  material fails in `wings_we_build:mat_face`.
- **`wings_we:build/2` can give `error`** with no exception. The code
  checks the result, not only the exceptions.
- **Hidden faces.** The core of Wings closes each open edge loop with a
  hidden face (a hole, a negative face number). The GLB writer takes
  only the visible faces (`wings_we:visible/1`), and the triangulation
  too.
- **Blocks and bad meshes become many objects.** Blocks that touch at an
  edge, points where two fans of faces meet, and pieces with faces in two
  orders go through the last steps of the import of Wings: one object for
  each piece or each face. `World.Mesh.clean/1` (`docs/format.md`) does
  the repair first.
- **Speed.** In the interpreter of BEAM.com, most models build in less
  than 2 seconds. A tree with 19,000 triangles in many small objects
  takes 20 to 26 seconds. A model has a time limit in its test.
- **The `.wings` file of a person is not safe data.** `binary_to_term`
  with no `:safe` can make new atoms. The reader is strict
  (`docs/format.md`, "Wings files").
- **Each element is one task of a construction.** A house of bricks
  has 5,206 elements: each is a message to a person and two or three
  events of the log. The element events of a large model are many; the
  memory budget and the time of a construction at the edge are not
  measured yet (plan 0001, step 3).
- **A group of people is heavy.** An `exercise` group of 7 people builds
  in about 17 s on this computer at the mid level (5 s at far), and its
  file has 4.8 MB (1.5 MB at far): each person is a full person with its
  own animation. In the interpreter of the VM it is about 10 times
  slower. Use the far level for a group, or a `person` with a routine
  for each place. At the edge (128 MB) a group of 2 or 3 people builds
  at the far level (about 650 KB, 12 to 15 s), and a group of 4 or more
  stops the VM: build it on a computer (`mix world.order`) until F4.
- **One build at a time in a VM.** Two cold builds at one time in one
  VM stopped it (128 MB). `POST /build` still builds one file at a
  time (`:global.trans`); `POST /builds` has the budget of its job: give
  it `memory_mb`, so that a task over its part fails alone. The node
  does not wait for room in the memory before it opens a construction
  yet. A near level of the
  car or the van, alone, still stops the VM (F4). F4 part 1 took the
  peak of a near person from 132 to 90 MB natively (`docs/factory.md`);
  it is not measured at the edge yet.

## The steps

Each step is one branch and one pull request in `sntran/World`, or in the
app that uses the models.

| Step | Result | Check |
|---|---|---|
| 0. The plan | `README.md`, `AGENTS.md`, `CONTRIBUTING.md`, `TODO.md`, `docs/format.md`, `LICENSE`. | The owner agrees, or changes them. |
| 1. The project and the core of Wings | Mix project, `wings/` with `scripts/wings.sh`, `World.Mesh` (build, smooth, triangulate, clean), `World.GLB`, the review page, CI on BEAM.com with the validator. | A box, a cylinder, a lathe and a loft give GLB files with no error and no warning. `scripts/wings.sh` twice gives the same files. Coverage 100%. |
| 2. Standard parts | `World.Parts`: bolt, nut, washer, bearing, tube, sheet, lumber, extrusion, rim, tire, wheel. Each with its ports and its sources. | Property tests: each size agrees with the table of its standard. Each part on the review page. |
| 3. Assemblies and joints | `World.Assembly`, `World.Connection`, joints, poses, the list of the parts, the three levels, `mix world.build` and `--check`. The Honda Vision 110 from parts. | The wheels and the bars turn on the review page. The list of the parts of the scooter. The triangles of each level are in their limits. The build gives the same bytes twice. |
| 4. Phượt uses World | The vehicle next to the avatar of Phượt is the far level of its model. It moves a little in a drive (the wheels turn, the body bobs), and stops when the vehicle stops. | On a phone of 390 px, in Phượt. With `prefers-reduced-motion`, nothing moves. |
| 5. Wings files | `World.Wings.read/1` (strict) and `write/2`. Shaped parts from `.wings` files. The body panels of the scooter as shaped parts. | A file that `write/2` makes opens in Wings 3D on the desk of the owner, and `read/1` reads its change. A file with an unknown atom is refused. |
| 6. The Wings plugin | `wpc_world`: ports and joints in the plugin state of the file, a command to try a pose, the axes in the view. | The data and its export: tests here. The window: the owner tries it in Wings 3D. |
| 7. DIY uses World | The models of DIY as assemblies of World. DIY draws its SVG from them, and depends on `:world`. | The pictures of DIY do not change: its tests compare the frames before and after. |
| 8. Voxel models | `World.Voxel`: `.vox` read and write, the voxel maker. In Tre: the stamp of a `.vox` model into the fine grid. | A stool and a cart of World in the world of Tre, with the colors of Tre. A `.vox` file opens in Goxel. |
| 9. STL for a printer | `World.STL`, a file for each material, the checks of a print (closed, outside, thick enough, the size). | A slicer (PrusaSlicer) slices the scooter at 1:43 with no error. |
