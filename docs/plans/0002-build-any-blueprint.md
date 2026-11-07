# 0002 The people build any blueprint, as on a real site

| Field | Value |
|---|---|
| Status | In progress |
| Depends on | Plan 0001 (the people, the constructions, the stream, the skills, the blueprints in data). |
| Changes | Plan 0001: its steps 4 and 5 move here. `docs/world.md` (the places come back, as a real flow), `docs/format.md` (a blueprint in an order, a repeat of a node), `specs/Build.tla`, and plan 0025 of Vũng Tàu (the game sends its blueprints). |

## 1. Goal

World is a building system, not a catalog. A project sends a blueprint
in data (Vũng Tàu the lot houses, the statue and the lighthouse; Phượt
the scooters and the vans), and the people of World build it on demand,
in real time, as on a real site or a real line: many people of many
trades at the same time, element by element. A model of this approach
is better, faster to build and more like the real thing than a model of
the catalog. It does not have the bytes of the old files.

The order of the work, as in the real world: the people build houses
and vehicles first; then they build the factories (houses) and the
trucks (vans) of the world; then they build the models that the
projects ask for, each in the factory of its trade, with its parts
brought by truck.

## 2. Out of scope

- The memory of the edge (128 MB). BEAM.com runs anywhere; first the
  work is correct, then it uses less memory.
- The catalog models that no project asks for: they stay as files until
  the cleanup (D9).
- A blueprint that needs a skill that World does not have: World adds
  the skill (one module), or the drawing uses shapes and parts.

## 3. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | A blueprint can come with the order: `{"blueprint": {...data...}, "options": {...}}`, or by its hash after `POST /blueprints` (kept in the store of the orders). The blueprints of `priv/blueprints/` are examples and the places of the world. | The projects own their blueprints; World owns the skills. The skills are the words, the blueprints the sentences. |
| D2 | A drawing can repeat a node: `{"repeat": {"for": "floor", "in": [1, 2, 3]}, "node": {...}}` or `"in": {"count": 8}`; the name and the values of the node take `{"var": "floor"}`. The fill expands it before the check. | Floors, courses, pours, wheels, rows of seats: many tasks of one kind, for many people at one time. |
| D3 | A big task splits into pieces in the drawing (D2): the cast of a statue is pours by bands from the feet up, in parallel, then one merge. `World.Cast` gets a pass of the distances that does not depend on the order (the least distance, then the least index of the triangle, then of the sample; the sums of the normals of all the samples near a loose cell), so any order of pours gives one field. The files of the statue keep their bytes: the new pass gives the same field. | The owner: one big task is a bottleneck (plan 0001, D30 goes). |
| D4 | The skills of a house are the work of a real site: `footing`, `column` and `beam` (formwork, rebar, pour), `slab`, `course` (one band of courses of a wall of a unit, with the openings and lintels: the mason), `stair`, `roof` (purlins, tiles or sheets), `opening` (a door or a window: the joiner), `iron` (rails, cages, gates: the smith), `plaster` and `paint` (the plasterer, the painter). The model shows plaster where a wall is plastered, and bricks where it is bare. | The owner: as on a real site. A tube house of Vũng Tàu is a frame of concrete with an infill of bricks. |
| D5 | The skills of a vehicle are the work of a line: `hull` (data), `frame` (a welder: tubes of a frame), `panel` (a sheet metal worker: a panel on a hull or a loft), `door` (hung on its hinges), `glass`, `seat` (the upholsterer), `wheel` and `corner` (the wheelwright, the mechanic), `engine`, `lamp`, `paint`. | Phượt sends the blueprints of scooters and vans. |
| D6 | The places are real: `World.Places` (a warehouse, a factory for each trade, a site for each house), the roads of a yard, `World.Stock`, and trucks (vans of the van blueprint) with their drivers. A construction of a model of a trade goes to the factory of its trade, and waits until the factory stands. Its parts go from the warehouse to the factory by truck, with the time of the drive on the world clock. A house, a statue and a tower are built on their site. | The owner (2026-11-07): the real flow. |
| D7 | The first start of a node builds the places once (plan 0001, Q2): the people build the warehouse and the factories as houses (`priv/blueprints/factory.json`, with a door of the size of its products) and the trucks as vans; then the factories open. A later start reads the log and the files of the store. | Houses and vehicles first, then the factories, then the models. |
| D8 | Each new flow has a TLA+ specification with fault models, and the logs replay in it: `specs/Haul.tla` (a part arrives at its factory once; a truck holds at most its load; a task starts only after its parts are at its factory) and `specs/Places.tla` (no construction waits for a factory that nobody builds; the bootstrap ends). | A test sees one order of the acts; the checker sees all. |
| D9 | The kind modules of the catalog (`World.Buildings.Lot`, the van line, the vehicles) stay until their skills are done and the projects send blueprints; then they go, with their files. The skills reuse their code (`Lot.sheet/8`, `World.Vehicles.Hull`, `World.Sheet`, `World.Vehicles.Wheels`). | No model of Vũng Tàu or Phượt breaks while it moves. |

## 4. Requirements

- **R1.** A drawing repeats a node over a list or a count (D2), and the
  copies are tasks that people do at the same time.
- **R2.** The cast of a statue is pours that casters do at the same
  time, in any order, with one result (D3).
- **R3.** The people build a tube house as on a real site (D4): the
  footing, then floor by floor the columns, the beams and the slab, the
  courses of the walls by many masons, the stair, the roof, the openings
  and the iron, then the plaster and the paint. Each element goes to
  the stream when it is made.
- **R4.** The people build a van and a scooter as on a line (D5).
- **R5.** The places, the stock, the trucks and the drivers are
  processes; a construction of a trade is at its factory, and its parts
  come by truck (D6, D8).
- **R6.** The first start builds the places (D7).
- **R7.** A project sends a blueprint with its order, or once by `POST
  /blueprints`; the check gives each error of each skill with its path
  (D1). The MCP server has `check_blueprint`, and `plan_build` and
  `build` take a blueprint.
- **R8.** Faster: a construction with 16 people takes less time than
  with one; on 4 cores, at most half of the time for the statue and the
  house. The log gives the times.
- **R9.** More real: each new model next to the photos of the real
  thing, and the checks of a true model (`World.Check`).

## 5. Steps

1. **The parallel pieces.** R1, R2: the repeat of a node, the cast in
   pours, the statue with its pours.
2. **Houses.** R3: the skills of a site, `priv/blueprints/tube_house.json`.
3. **Vehicles.** R4: the skills of a line, `priv/blueprints/van_line.json`
   and `scooter_line.json` (the blueprints `van` and the Honda Vision of
   the catalog stay until step 6).
4. **The places and the real flow.** R5, R6, with `specs/Haul.tla` and
   `specs/Places.tla`, and the map of the world on the web page.
5. **Any blueprint from any project.** R7, `docs/skills.md`, plan 0025
   of Vũng Tàu.
6. **The cleanup.** D9, when the projects order by blueprint.

## 6. Acceptance criteria

- The model checks of `Build.tla`, `Haul.tla` and `Places.tla` pass, and
  each fault model fails.
- A client posts the blueprint of a tube house and watches it go up on
  its site on the world page; a van goes up in the vehicle factory with
  its parts brought by truck.
- R8 and R9 hold for the statue, the tube house, the van and the scooter.

## 7. Open questions

None now.

## 8. State (2026-11-07)

Steps 1 to 5 are done, on the branch `feat/0002-build-any-blueprint`;
step 6 waits until Vũng Tàu and Phượt order by blueprint.

| Step | Commits | What the people do now |
|---|---|---|
| 1 | `feat(drawing): repeat a node`, `feat(cast)`, `perf(mesh)`, `feat(statue)` | The statue: 37 tasks; eight casters pour its eight bands at one time, eight finishers make the slabs of its surface. |
| 2 | `feat(house)` | A tube house as on a real site: 87 tasks for three floors. |
| 3 | `feat(van)`, `perf(construction)`, `feat(scooter)` | A van on the line: 23 tasks; a scooter: 6 tasks, with the joints in the drawing. The join of the model is in parallel. |
| 4 | `feat(places)`, `feat(haul)`, `feat(yard)`, `feat(site)` | The yard: the takeoff of each task, the trucks that bring it, the first start that builds the warehouse, the factories and the trucks, and the map on the world page. `specs/Haul.tla` and `specs/Places.tla`, with their fault models and the replay of the logs. |
| 5 | `feat(orders)` | A blueprint of a project in the order or by its hash, `POST /blueprints`, the MCP tool `check_blueprint`, `docs/skills.md`; plan 0025 of Vũng Tàu sends the blueprints of the game. |

The times are in `docs/world.md` ("The measures of the people of plan
0002"). The acceptance criteria: the model checks and the fault models
pass (`test/world/build_spec_test.exs`, `haul_test.exs`,
`yard_test.exs`); a house goes up at the site with its materials brought
by truck, and a scooter waits for its factory and goes up there
(`yard_test.exs`); R8 and R9 hold for the four examples. The memory at
the edge is not measured yet (D4 of the owner: later).
