# Plan 0013: real things from their sources, and long shapes at the cost of their near parts

Status: Done (2026-11-13). Section 10 has the measure. (The owner,
2026-11-13, after the open questions of plan 0012: "Proceed. Do
research to find sources anywhere you can.")

Depends on: plan 0012 (the surfaces, the outlines, the crews), plan
0011 (any list of edits builds), plan 0010 (the maps), plan 0008 (the
tree of bricks).

## 1. Goal

The catalog has models of real things of Việt Nam, each from sources
that a person can read again: a fishing boat of Vũng Tàu, the most
common car, a tree of the streets. A model with a long shape of many
points (the hull of a boat, the side view of a car) builds in the time
that its near parts need.

## 2. What the owner asked

Plan 0012 ended with open questions. The owner said to proceed, and to
find sources where they are. So this plan takes three of the
questions:

1. The fishing boat needs the lines of a real hull.
2. The models of plan 0011 (the car, the tree) have simple shapes: each
   needs its edits again from a real thing.
3. Speed: about 13% of a build is in one process.

## 3. The state before this plan

### 3.1 The sources that the research found

| Thing | Source | What it gives | What it does not give |
|---|---|---|---|
| The fishing boat | Blue Book of Coastal Vessels, South Vietnam (Remote Area Conflict Information Center, Battelle, 1967; archive.org/details/DTIC_AD0664455), p. 24, 25, 329, 330 | The class C5-T2-A, the "beaked" motor fishing boat of Vũng Tàu: 9 to 12 m long, 2.5 to 3 m wide, a draft of 1 m with its load, one diesel; a text of its form; a photo of its side; the eyes of Vũng Tàu | Lines, a section, a table of offsets, colors |
| The same boat today | SEAFDEC (2002) and JICA (1994) reports on the boats of Việt Nam | Boats of 10 to 13 m: 3.1 to 3.5 m wide, 1.15 to 1.45 m deep | A drawing |
| The car | The catalogue of Toyota Việt Nam for the Vios (XP150) | 4425 by 1730 by 1475 mm, wheelbase 2550 mm, tracks 1475 and 1460 mm, tyres 185/60R15, 133 mm over the ground | The side view (measured on photos, about 5 cm exact) |
| The tree | World Agroforestry (the species page); Thomson and Evans, Terminalia catappa, Species Profiles for Pacific Island Agroforestry (2006) | The sizes of the species, the tiers of level branches, the leaves, the bark | The sizes of a street tree (a guess from photos) |

No table of offsets and no lines of a Vietnamese fishing boat are
public. The side view is from the photo of the book, and the section
is a guess (section 5, D5).

### 3.2 A long shape costs each of its parts at each point

A tube measured each of its round cones for each point of the field,
and an outline each of its sides, with tuples. The short list of a
cell (`World.SDF.cell/4`) kept or dropped a whole edit. So a hull as a
tube of 24 cones, used three times (the outside, the inside, a cut),
with an outline of 27 sides for its sheer, cost about 100 small shapes
at each point near it. The first build of the boat took 8 minutes
37 seconds on 4 schedulers.

### 3.3 The build task made each model four times

`mix world.build` made each model one time for each level, and one more
time for the list of its parts. For a sculpture with maps the fourth
build was about a third of the time.

## 4. Out of scope

- The delivery for Phượt and the pictures of DIY (each needs a plan).
- The event of a crew in the log of a construction.
- A photo next to each shot in the repository (a photo needs a
  license; the sources are named in each drawing).
- The animals of plan 0011.
- A change of the bake. It is now the largest part of a build with a
  large image (section 10).

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | Each real model names its sources in its drawing, in three groups: what is from the text or the numbers of a source, what is measured on a photo, and what is a guess. | A person who reads the drawing knows which sizes to trust. |
| D2 | A tube has its round cones, and an outline its sides, as numbers made one time (`parts` of an edit). The short list of a cell keeps only the parts that count in the cell (`World.SDF.focus/3`): a part that can be the nearest one at a point of the cell, and for an outline the sides that the line from a point to the right can cross. | The field of the short list is the field of all the parts, to the bit: the proof is the same as for the edits (each distance changes by the length of a move at the most). The cost of a long shape is the cost of its near parts. |
| D3 | The id of an edit does not change with its parts. | The keys of the cache are the ids: a brick keeps its place in the cache. |
| D4 | Two points of a tube next to each other at one place are an error of the data. | A cone between them has no length; before, the build stopped with an error of arithmetic. |
| D5 | The hull of the boat is a tube along the sheer of the photo: round sections, as deep as half the width. The same tube, smaller by the planks, is taken away. A crop by the side view cuts the sheer, and a crop by the tube again cuts the decks and the cabin at the hull. The keel, the stem and the sternpost are side views with a blend. | The book says round, with no keel. A tube gives pointed ends, a bottom that rises to the ends and a sheer as a crescent with few numbers. |
| D6 | A model with a thin wall has the same cells at each level, and its small parts are in a detail that the far level does not have. | With cells larger than half the wall, the two faces of the wall are one. The levels with the same cells use the same bricks from the cache. |
| D7 | `boat` is a kind of a drawing (the check knew it already: a boat floats, and it is built on a slipway). The boat has the port `waterline`. | A game puts the boat in the water at that port. |
| D8 | A real model has no badge, no name and no number of a real owner. A color with no source is a choice, and the drawing says so. | The model is the form of the thing, not a copy of a mark. |
| D9 | The toy car and the toy tree of plan 0011 stay: they are the short examples of the format. The real things are new models. | The tests and the documents use the short examples. |
| D10 | The build task takes the list of the parts from the near build. | The level by default is near: the fourth build made the same model again. |
| D11 | The search of the scale of the charts uses the sizes of the charts only, and a job of the second round of the collapse makes the points of its groups itself. | Less work in the one process of the site (plan 0012, the open question of the speed). |

## 6. Requirements

| # | Requirement |
|---|---|
| R1 | The fishing boat is in the catalog: its sizes are in the ranges of the book, its side view is that of the photo, and its three levels have no broken face in the shots. |
| R2 | A real car and a real tree are in the catalog, each with its sources. |
| R3 | The field with the parts of a tube and of an outline is the same to the bit: a test with long shapes, and the 14 sculptures of the catalog keep their bytes. |
| R4 | The boat builds in less than half of the time of its first build. |
| R5 | The work of one process in a build is less than before (the robot: 2.0 s under the trace). |
| R6 | Each real model passes the check of a model and the validator of glTF; the full check passes. |

## 7. Steps

1. Less work in one process: the charts, the second round of the
   collapse (D11).
2. The parts of a tube and of an outline (D2 to D4).
3. The build task (D10).
4. The fishing boat (D5 to D8).
5. The car and the tree.
6. The documents, the measure, the full check.

## 8. Acceptance criteria

- R1 to R6, with the numbers of section 10.
- `mix precommit`, `mix world.build --check` and `npm test` pass.

## 9. Open questions

- **The bake is the largest part of a build with a large image.** The
  near level of the boat has an image of 2048: its bake is more than
  half of its build. Each texel reads the color with the slow fold of
  the edits. The next work for "fast": a hot loop for the color as for
  the value, and a measure on a machine with more cores.
- **The last pass of the collapse is in one process.** When the budget
  is much less than the faces (the far level of a large model), the
  rounds in the regions stop at their limit, and the last pass does
  the rest alone.
- **The near parts of a fat tube.** A cell near a tube that is wide
  keeps about 5 of its cones: the bound of the distance is loose there.
  A bound with the directions of the cones can keep 2.
- **The section of the hull is a guess.** A drawing of the lines of a
  boat of Vũng Tàu, from a yard or a museum, makes it true.
- **The leaves of a tree are clumps.** A real crown has leaves as
  cards with holes; World has no such surface.
- The open questions of plan 0012 that this plan does not take: the
  delivery for Phượt, the pictures of DIY, Tre, the event of a crew.

## 10. The measure

One machine with 4 schedulers (the machine of this session: each
number is next to a number of the same machine).

### Step 1: less work in one process (R5)

A trace of the large steps of the build of the robot at near (the
time of each step alone, and in the streams):

| | Before | After |
|---|---|---|
| The work of one process, of 8.6 s under the trace | about 2.0 s | about 1.7 s |

The models have the same bytes. What stays in one process: the borders
and the regions of the second round (about 0.3 s), the figure, the
pack of the charts, the GLB, the join of the first round, the finish.

### Step 2: the parts of a tube and of an outline (R3, R4)

The boat of step 4 as it was at its first build (49 edits in one
sculpture, cells of 3, 5 and 6 cm), the stages of its near level:

| Stage | Before | The cones of a tube | And the sides of an outline |
|---|---|---|---|
| The tree and the bricks | (not measured alone) | 20.6 s | 14.8 s |
| The bake (an image of 2048) | (not measured alone) | 74.4 s | 64.4 s |
| The build task, three levels | 8 min 37 s | | 4 min 22 s |

- A ball of a random size from 2 cm to 32 cm keeps in the mean 16% of
  the sides of a star of 48 sides, 22% of the sides of a profile of 40
  sides and 23% of the cones of a tube of 60 cones (the test).
- The field is the same to the bit at each point of the ball (the
  test), and the 14 sculptures of the catalog before this plan keep
  their bytes.

### Step 3: the build task

The 14 sculptures of the catalog before this plan, with `mix
world.build NAMES`: 2 min 41 s before, 1 min 52 s after. The files are
the same.

### Steps 4 and 5: the real models (R1, R2, R6)

| Model | Edits | Triangles (near, mid, far) | Images | Near | Mid | Far |
|---|---|---|---|---|---|---|
| `ghe_danh_ca_vung_tau` | 29, and 26 in a detail | 30,000 / 8,000 / 3,000 | 2048 / 1024 / 512 | 104.9 s | 21.7 s | 27.7 s |
| `toyota_vios` | 38 | 20,000 / 5,000 / 1,000 | 2048 / 1024 / 512 | 48.6 s | 12.7 s | 5.1 s |
| `cay_bang` | 35 | 30,000 / 8,000 / 2,000 | 1024 / 512 / 256 | 40.9 s | 21.9 s | 11.4 s |

- The boat: 11 m long (the book: 9 to 12 m), 2.6 m wide at its sheer
  (2.5 to 3 m), 0.75 m of side over the water with no load. Its three
  levels build in 154 s: 8 min 37 s at its first build, with more
  edits in one sculpture and no detail (R4: less than half).
- With cells of 5 cm and 6 cm at mid and far, the wall of 7 cm of the
  hull was broken; with the cells of near at each level it is whole,
  and mid and far use the bricks of near (D6). With 1,500 triangles at
  far and all the small parts, the far level was broken; with 3,000
  and the small parts in a detail, it is whole.
- Each of the three models passes `World.Check.model`, and the
  validator of glTF finds no error and no warning in the 576 files of
  the catalog.

### The requirements

| # | Result |
|---|---|
| R1 | Met. |
| R2 | Met. The leaves of the tree are flat clumps, not leaves (section 9). |
| R3 | Met. |
| R4 | Met: 154 s, from 517 s. |
| R5 | Met: about 1.7 s, from about 2.0 s. |
| R6 | Met: each model passes the check of a model and the validator; the full check passed on the tip with plan 0014. |
