# Plan 0016: a house of Vũng Tàu that looks real, and the rules for a street of houses

Status: Done for the first four types (2026-11-13). Section 10 has the
measure. (The owner, 2026-11-13: "Then build a realistic typical house
with two stories in Vung Tau. Do research how they look. Then
determine the algorithms so that one can request various types of
houses in Vung Tau to form a real street.")

Depends on: plan 0014 (a model in parts), plan 0012 (the surfaces, the
dirt), plan 0010 (the maps).

## 1. Goal

A project sends a request of a few words (a type, a family, a width, a
seed) and gets the drawing of a house that looks as a house of Vũng
Tàu looks: its door, its balcony, its sign, its tank, its stains. A
request for a street gives a row of such houses, each different, that
fit each other as neighbors.

## 2. What the owner asked

1. A realistic, typical house of two storeys of Vũng Tàu, from
   research.
2. The algorithms for a request of various types of houses, that form a
   real street.

## 3. The state before this plan, and the research

### 3.1 What World had

`World.Buildings.Lot` makes a house on a lot from options (a tube
house, a shop house, a villa, a mini-hotel): cheap meshes with roles,
for a town of thousands of houses. The application gives the
materials. A house there has no stains, no sign, no tank, and the
houses of the catalog have 4 floors. `World.Places.OSM` puts boxes on
the plan of a real street.

### 3.2 The typical house (the research)

The sources, with what each gives:

| Source | What it gives |
|---|---|
| TCVN 9411:2012 (the standard of row houses) | A lot of 3 m by 3 m and 15 m² at the least. A ground storey of 3.6 m at the least, a floor 0.15 m over the sidewalk at the least. The reach of a balcony by the width of the road: none under 5 m, 0.5 m to 7 m, 0.9 m to 12 m, 1.2 m to 15 m, 1.4 m over that. Its underside 3.5 m over the sidewalk at the least. A stair of 0.9 m, a riser of 190 mm at the most, a tread of 250 mm at the least. No opening in a wall on the line of a neighbor. |
| QCVN 01:2021/BXD (the national rule of planning) | No yard in front is necessary for a house lower than 19 m; a lot of 90 m² or less can be all built. |
| TCVN 4451 (dwellings) | A storey of 3 m at the least. |
| Ten sample drawings of town houses of 4 m and 5 m with sizes (sites of architects) | The levels -0.45, 0, +3.6, +7.1 and +9.8 m; a ground opening of 3.4 m by 2.85 m in a front of 5 m; columns of 200 mm on the lines of the party walls; walls of 200 and 100 mm; a head of the stair (tum) of 2.7 m. |
| 90 adverts of houses in Vũng Tàu (mogi, homedy, 2026-11) | Lots of 5 m by 15 to 20 m the most, then 4 m. Of the houses with a count of storeys: one storey 19%, two 35%, three 28%, four or more 19%. |
| 26 photos of streets of Vũng Tàu (Wikimedia Commons, adverts): Trưng Nhị, Ba Cu, Bà Triệu, Trần Phú, Thống Nhất, 30/4 | The look: see below. Rows of the old center are mostly of two storeys. |
| Data sheets of makers | A water tank of 1,000 liters: 0.96 m across, 1.7 m high with its legs. The outdoor box of an air conditioner of 1 HP: 0.68 by 0.43 by 0.29 m. |

The look of a street front, from the photos:

- **The ground storey** is open between two piers: a folding gate of
  iron (old), a roll-up door, or doors of glass behind a white gate of
  cut steel (new). The piers have tiles or red granite as high as the
  door.
- **A sign** goes across the front at the first floor, and it often
  hides the balcony. An old shop has an awning of cloth with stripes.
- **The upper storey** has a balcony of 0.9 to 1.2 m with a rail of
  iron bars, a low wall, tubes of stainless steel (from about 2000) or
  glass (new); a door and a window; a flat shade over them; on an old
  house blocks for the air over the shade.
- **The top** is a flat terrace with a parapet, the head of the stair
  and a stainless tank; or a roof of steel sheet behind a low wall; or
  red tiles on a wider lot.
- **The paint** is cream or light yellow the most, then white and
  pastels; a new house is white and gray.
- **The sea air** makes dark lines under each parapet and balcony, and
  rust on each gate.

Not found: the text of the rules of the city for its streets, a
count of the types on a real street, a drawing with sizes of a house
that stands in Vũng Tàu, a front photo with a high resolution. So the
shares of the choices are a guess, and each drawing says so.

### 3.3 The algorithms (the research)

| Method | Its idea | Its place here |
|---|---|---|
| Split grammars (Wonka and others 2003, "Instant Architecture"; Müller and others 2006, "Procedural Modeling of Buildings": CGA shape) | A shape is cut by rules into smaller shapes with names (a front into storeys, a storey into bays), until each shape is a thing (a door, a window). A rule can choose by chance from a seed. | The rules of a house. |
| The plan of a city (Parish and Müller 2001), parcels (Vanegas and others 2012) | Roads first, then blocks, then lots cut along the street edge. | The plan of a street: a row of lots. |
| Layouts of rooms (Merrell and others 2010), treemaps | A search for the rooms of a plan. | Not used: a tube house has one row of rooms, and its inside is not in this plan. |
| Model synthesis, wave function collapse (Merrell 2007) | Tiles that fit their neighbors by local rules. | Not used for a house (it gives no true sizes). It can make a pattern (the blocks for the air, a gate) later. |

## 4. Out of scope

- The inside of a house, and the back yard.
- The types that the research names and this plan does not make: the
  shop with a sign over all its front, the house with moldings (tân cổ
  điển), the hotel, the villa, the empty lot.
- A street with two sides, a corner, trees, wires from the pole to the
  houses, motorbikes, people.
- The site of a house (the people who build it): `tube_house` of plan
  0002 does that for the house of meshes.

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | A house that must look real is a model in parts from edits (plan 0014): the front with small cells and a large image, the body and the roof with large cells. | The maps give the stains, the stone, the rust and the shadows under each balcony with no work of an application. `World.Buildings.Lot` stays for a town of thousands of cheap houses. |
| D2 | The rules are a split grammar in code (`World.Town.House`): the front is cut into the ground storey and the upper storeys, a storey into piers and openings, and each rule gives edits. The output is a drawing: data that a person can read and change. | The grammar is the known method for fronts. A drawing is what each tool of World takes. |
| D3 | A request is a small map: `type`, `family`, `width`, `depth`, `road`, `seed`, the two sides. `request/1` gives it back with each choice made (the color, the door, the rail, the sign, the awning, the blocks, the roof, the age), and a value of the request stays. | One call shows what the rules chose; a project can change one choice and keep the others. |
| D4 | A choice is from the seed, the name of the rule and its place (a hash), never from a generator that the work shares. | The same request gives the same house in any order of the work, on any node. |
| D5 | The family is the years of the build. It gives the door, the rail, the colors and the age (the dirt and the wear of the maps). | A real street is a mix of years, and the parts of one year go together. |
| D6 | The sizes that a rule of building fixes are fixed in the code with their source; the reach of the balcony is from the width of the road. | A house on a hẻm has no balcony over the street: the rule, not chance. |
| D7 | A street is two steps. The plan of the street (`World.Town.Street.plan/1`) cuts the row into lots and makes the choices that neighbors share (the widths, the types, the shared walls, the family of a group, no color two times in a row). Each house is then made from its own request. | No house waits for its neighbor: each is a job for a crew. A real street is planned so: the lots first. |
| D8 | A thin part (a rail of bars or tubes, a sheet of glass, the cloth of an awning) is in a detail at near with cells of 12 mm. A rail as a low wall is in the part itself. | The rule of a thin wall (plan 0013). |
| D9 | A sign has no words, and a house has no number. | A model is not the mark of a real shop (plan 0013, D8). |
| D10 | The drawing of a street has 5 houses at the most: each part has its own image, and a drawing has 16 roles for parts. A longer street is its plan and one drawing for each lot. | A game places each house as its own model. |
| D11 | Two tools of the MCP server: `draw_house` (a request to a drawing) and `plan_street` (a request to the plan, and to the drawing of a short row). | A project asks for a house in the way it asks for each other model. |

## 6. Requirements

| # | Requirement |
|---|---|
| R1 | The typical house of two storeys is in the catalog (`nha_pho_2_tang_vung_tau`), with the sizes of section 3.2, and its shots next to the photos show the same kind of house. |
| R2 | Four types and three families give houses that are different and each a true drawing. |
| R3 | The same request gives the same drawing; a test. |
| R4 | A row of five houses is in the catalog (`day_pho_vung_tau`): each type and each family, wall to wall, on its sidewalk. |
| R5 | The two tools give the drawings; a test. |
| R6 | The full check passes. |

## 7. Steps

1. The research (two reports: the house, the algorithms).
2. The rules of a house, with the typical house next to the photos.
3. The plan and the drawing of a street.
4. The tools, the two models of the catalog, the documents, the full
   check.

## 8. Acceptance criteria

- R1 to R6, with the numbers of section 10.
- `mix precommit`, `mix world.build --check` and `npm test` pass.

## 9. Open questions

- **The shares are a guess.** A count of the houses of one real street
  (their types, widths, colors) makes the plan of a street true. The
  owner can name the street.
- **The other types** (section 4), and for each type more rules: a
  front with two windows, a loggia, a front yard with a gate, a
  terrace with a roof of steel on posts, plants in pots.
- **A house costs about 1.5 minutes at near.** A street of 100 houses
  is hours on one machine. The houses are jobs with no order, so more
  nodes help (plan 0012); a front of one family can also share its
  bricks through the cache.
- **The far level of a row** is one mesh and one image for each part.
  A skyline needs one mesh for a block.
- **The link to `World.Buildings.Lot`.** The two ways to make a house
  have no common request yet: one request can give the cheap house
  for the far streets and the house from edits for the near ones.
- **The people of World do not build this house yet** (the site, the
  trades, the time lapse).

## 10. The measure

One machine with 4 schedulers. The times are with the full check of
another commit in work on the same machine: a build alone is faster.

### The typical house (R1)

`nha_pho_2_tang_vung_tau`: the type `pho2_flat`, the family `steel`,
5 m by 16 m, the seed 3, a blue sign.

| | Near | Mid | Far |
|---|---|---|---|
| Triangles | 27,000 | 4,000 | 550 |
| File | 7.5 MB | 0.41 MB | 0.10 MB |
| The image of the front | 2048 | 512 | 128 |

- 51 edits: 34 in the front, 6 in the body, 11 in the roof; and 6 more
  in the detail of the front (its rail of tubes).
- Its sizes are the sizes of section 3.2: the floor at 0.3 m, the first
  floor at 3.9 m, the terrace at 7.3 m, the parapet to 8.3 m, the head
  of the stair to 10.0 m and the tank to 11.8 m; an opening of 3.4 m
  by 2.85 m between piers of 0.8 m; a balcony of 1.2 m.
- At near alone it builds in about 90 s.
- It passes the check of a model at each level.

### The types and the families (R2, R3)

Each of the 4 types with each of the 3 families, with two seeds, is a
true drawing (24 drawings in a test). The same request gives the same
drawing. Each type meets the budget of each of its parts at far.

A first build of a row did not: the parapet of 12 cm and the legs of
the tank were not whole at far with cells of 20 cm, and one roof had
672 triangles for a budget of 150. The roof has the same cells at each
level now (the rule of a thin wall).

### The row of five houses (R4)

`day_pho_vung_tau`: the plan of the seed 2 on a road of 13 m, 26 m
long.

| Lot | Type | Family | Width | What the rules chose |
|---|---|---|---|---|
| 1 | `pho2_flat` | `steel` | 5 m | A roll-up door, tubes, a yellow sign |
| 2 | `pho3` | `old` | 5 m | A folding gate, bars, an awning, blocks for the air |
| 3 | `pho2_tile` | `modern` | 6 m | Glass doors, a rail of glass, red tiles |
| 4 | `pho2_flat` | `steel` | 5 m | A roll-up door, tubes, a yellow sign, another color of paint |
| 5 | `cap4` | `modern` | 5 m | One storey, a roof of steel |

| | Near | Mid | Far |
|---|---|---|---|
| Triangles | 132,000 | 20,600 | 2,850 |
| File | 15.1 MB | 2.2 MB | 0.47 MB |

- 16 parts, each with its image (a front in a row has an image of
  1024).
- The two models build in 12 min 40 s, three levels each.

### The tools (R5)

`draw_house` and `plan_street` give the same drawings as the modules;
a wrong word of a request is an error with its message (a test).

### The requirements

| # | Result |
|---|---|
| R1 | Met for the form and the sizes. It is a model of the type, not of one real house; the shots are next to a photo of a row of Trưng Nhị street. |
| R2 | Met. |
| R3 | Met. |
| R4 | Met. |
| R5 | Met. |
| R6 | Met: the full check passed on the tip. |
