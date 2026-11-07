# 0003 World builds real blueprints, and the tests compare them

| Field | Value |
|---|---|
| Status | In progress |
| Depends on | Plan 0002 (the skills of the trades, the blueprints in data, the vehicles of the skills of the vehicle trades, the takeoff of a task). |
| Changes | `World.Mass` and `priv/standards/materials.json` where a mass is wrong; the skills and the blueprints where a number of a real blueprint is wrong; new skills for the materials and the trades of the real blueprints. |

## 1. Goal

The owner (2026-11-07): "The better tests would be looking at real
blueprints for actual buildings and vehicles, and build them in World.
That would let us test 'building anything' from standards."

The tests of plan 0002 compare a blueprint of World with a model of
World. That proves that the skills can copy the catalog; it does not
prove that World builds a real thing right. A real blueprint gives
numbers that World did not choose: the sizes, the quantities and the
mass that an engineer or a maker published. At the end of this plan,
World builds real blueprints (the spec sheets of vehicles, a house of an
engineer in IFC, a standard house of Việt Nam, open source houses), and
each number of each one agrees with the model that the people of World
build.

## 2. Out of scope

- A copy of a drawing whose license does not let it in: the reference
  keeps the numbers (facts) with their source.
- The vehicles in STEP (ISO 10303-242): a vehicle comes from its spec
  sheet and the skills of plan 0002.

## 3. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | A **reference** is a real thing (`priv/references/NAME.json`): its source (the document, the page, the license), the order that builds it in World (a blueprint of World with the numbers of the document, a blueprint in data that World reads from the document, or an IFC file), and each published number with its unit, its tolerance and the name of its measure. | One format for a van, a bicycle and a house; the numbers are facts with their sources. |
| D2 | **The measures follow the standards** that define the numbers (`World.Measure`): the dimensions of a motor vehicle as SAE J1100 defines them (the overall length, the width with no mirrors, the height at curb mass, the wheelbase, the track, the ground clearance), the seat height and the wheelbase of a two-wheeler, the geometry of a bicycle frame, the curb mass (`World.Mass`); for a building, the quantities of IFC (`Qto_WallBaseQuantities`, `Qto_SlabBaseQuantities`, `Qto_SpaceBaseQuantities`, `Qto_WindowBaseQuantities`, `Qto_DoorBaseQuantities`), the storey heights, and the bill of quantities of a Vietnamese design (bricks, m3 of concrete, kg of rebar, m2 of render and of roof). | A number means what its standard says; a test that measures something else proves nothing. |
| D3 | **No gaps** (the owner): each number of each reference is in its tolerance (the tolerance of its source, or 1% for a size, 5% for a mass, 5% for a quantity, with the reason). A reference that fails is a bug of a skill, a blueprint, a material or a standard of World, and its step fixes it. | The owner chose it. |
| D4 | **IFC in** (ISO 16739; the files of ISO 10303-21): `World.IFC` reads an IFC file and gives a blueprint in data of the skills of World. A part that no skill can make is an error with its IFC id, so the list of the missing skills is a result. | IFC is the open standard of the blueprints of the engineers of buildings; any house in IFC becomes an order. |
| D5 | **New skills from the references**, each with its standard: a wall of a layer set, the members of a timber roof, a panel of plywood or OSB cut by CNC, a stud wall of lumber, and the materials of the layers of IFC. | A real blueprint uses materials and trades that World does not have yet. |
| D6 | The report: `mix world.references` builds each reference through the people of the node, measures it, and prints each number (the real value, the value of the model, the error, the tolerance); `test/world/references_test.exs` asserts each. | The owner and the projects see how true each model is. |

## 4. Requirements

- **R1.** `World.Measure` measures a model as the standards define the
  numbers (D2), with a test of each measure on a model whose numbers are
  known.
- **R2.** `World.References`, `mix world.references` and the test (D1,
  D6).
- **R3.** The vehicles of World against their spec sheets: the Honda
  Vision 110, the Royal Enfield Himalayan 411, the Chevrolet Bolt EV, the
  Ford Transit 148 high roof, and the Surly Long Haul Trucker of two
  sizes; each number in its tolerance (D3).
- **R4.** `World.IFC` reads an IFC house and gives a blueprint in data
  (D4); the FZK house of the Karlsruhe Institute of Technology agrees
  with the quantities of its file.
- **R5.** A standard house of a province of Việt Nam agrees with its
  sizes and its bill of quantities.
- **R6.** A WikiHouse and the Seed Eco-Home of Open Source Ecology agree
  with their parts and their bills of materials (D5).

## 5. Steps

1. **The references and the measures.** R1, R2.
2. **The spec sheets of vehicles.** R3, and the fixes.
3. **A house of an engineer in IFC.** R4.
4. **A standard house of Việt Nam.** R5. If no design with its
   quantities is public, the owner gives one.
5. **Open source houses.** R6, with the new skills of D5.
6. **The docs.** `docs/references.md` and the state of the plan.

## 6. Acceptance criteria

- `mix world.references` gives each number of each reference in its
  tolerance, and the test asserts it.
- The people build each reference, and its log replays in
  `specs/Build.tla`.

## 7. Open questions

None now.
