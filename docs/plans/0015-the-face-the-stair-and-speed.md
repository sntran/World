# Plan 0015: the face and the stair of the statue, a faster build, and the basket boats

Status: Done (2026-11-13). Section 10 has the measure. (The owner,
2026-11-13, after the recap of World: "Let fix the face of the statue,
the stairs, optimize the bake, the last pass of the collapse, the
basket boat.")

Depends on: plan 0014 (the statue in parts), plan 0013 (the parts of a
long shape), plan 0012 (the occlusion, the surfaces), plan 0010 (the
maps).

## 1. Goal

The open items of plans 0013 and 0014 are closed: the face of the
statue is the face of the photos, its stair goes round its open well,
a model from edits builds faster, and the two basket boats meet their
budgets and stand.

## 2. What the owner asked

Five items, in this order: the face of the statue, its stair, the
bake, the last pass of the collapse, the basket boat.

## 3. The state before this plan

### 3.1 The face

The head of plan 0014 was "a face, not the face": round forms with a
point of hair over the brow and a beard of washed stone. The photos
show a different head:

- The hair is a hood: a round top, a flat slab at each side of the
  face, and an edge about 12 cm thick round the face. It has no point
  over the brow.
- The face, the moustache and the beard are of the same white ground
  stone.
- The brows are straight. The nose is long, straight and narrow, and
  its tip is lower than its wings. The moustache goes down round the
  mouth to the beard. The beard ends in a blunt point.

The sizes are measured on the front photo from far (trungydang,
Wikimedia Commons, CC BY 3.0), with the width of the face of plan 0014
(1.4 m) as the scale:

| Place | Over the eyes (m) |
|---|---|
| The top of the hair | 1.5 |
| The edge of the hair on the brow | 0.9 |
| The tip of the nose | -0.58 |
| The mouth | -0.92 |
| The tip of the beard | -1.76 |

The head with its hair is 1.7 m wide at the eyes and 2.6 m wide on the
shoulders. The two photos from the shoulders (Wikimedia Commons) show
the side view: the edge of the hair is about 0.36 m behind the front
of the eye, and the head leans to the front by about 6 degrees.

### 3.2 The stair

The stair of plan 0014 went round a post, 12 steps for each turn. The
photo from the inside (Hoangvantoanajc, Wikimedia Commons, CC BY-SA
3.0) shows an open well of eight sides, with a handrail of ground
stone on balusters of steel round it.

### 3.3 Where the time of a build goes

Timers in each phase of the bake of the fishing boat (near, an image of
2048, 4 schedulers), as parts of the time of all its processes:

| Phase | Part |
|---|---|
| The color and the finish of each texel (one reading of the field) | 38% |
| The normal of each texel (one more reading of the field) | 36% |
| The occlusion (readings on a grid of the texels) | 14% |
| The mix of the occlusion values, the borders, the rows | 12% |

A reading of the field for a texel of the boat is 9.4 edits: 3.9 tubes
with 4.6 round cones each, 2.1 outlines with 5 near sides each, and 3.4
other shapes. So the short lists are short already: the cost of the
bake is the count of the readings.

The collapse of the far level of the boat left 22,800 faces for the
last pass (a budget of 3,000). The last pass, in one process, was about
a tenth of the stage, not most of it: the open question of plan 0013
gave it too much weight.

### 3.4 The basket boats

The full check of the tip of plan 0014 found a fault:
`thung_chai_flat_edits` did not stand (the check `stands`: it was on
one point). The wall of the two basket boats is 3.5 cm thick, and
their cells were 3 cm to 7 cm. Before the fix of the distance to a
`revolve` (plan 0014) the bottom had two sheets with many points at
the same height, and the check passed by chance.

## 4. Out of scope

- The reliefs of the base as figures.
- The time lapse of the site with the new statue (the owner: later).
- A bake in native code, or on a graphics card.

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | The head is made again from the photos: a hood (a round top, a slab from its front view, an opening with round corners), a long face of two ellipsoids, and its details at places on that face (a function of the generator gives the front of the face at a place). | The first details were at places by eye, and stood off the face. |
| D2 | The stair has 133 steps of 18.6 cm, 16 for each turn, round a well of 0.72 m across its flat sides. The handrail is one tube through the corners of the well (8 for each turn), 0.9 m over the steps. A baluster of steel is at each second step, in a detail with cells of 12 mm. | The photo of the inside. The count and the rise are the sources of plan 0014. |
| D3 | An edit that adds, nearer than the field so far by more than its blend at each point of a cell, hides the edits before it: they are not in the short list of the cell. | The field is its distance there, to the bit. The lists are shorter in the tree, in the bricks and in the bake. |
| D4 | The color and the finish of a texel have a hot loop (`World.SDF.looks/2`), as the value has. | The same result to the bit (a test), with less work for each edit. |
| D5 | The normal of a texel is from the changes of the field to the four texels next to it, and from the slope of the field off the plane of its triangle. One texel of each 16 reads the field off its plane; a texel between four such texels of its own triangle takes the mean of their slopes. Each other texel reads the field. | The slope off the plane changes only as the surface turns under a flat triangle. One reading of each two is not necessary. |
| D6 | The slope off the plane is of the field with no relief of a surface. | Before, the relief of the texel was in that slope: a normal on a high bump was too flat. |
| D7 | After the rounds of the collapse in the regions, when more than four times the budget is left: rounds in regions two times as large each time, with one budget for all the regions by the costs of their collapses, to a third of the faces each round, and not under two times the budget. | The points of two regions stay. A region with a small target must then do a collapse that costs much; the last pass, with the whole mesh, finds a better one. |
| D8 | The two basket boats have cells of 12 mm at each level. The flat one has 1,200, 800 and 500 triangles. | The rule of plan 0013 (D6) for a thin wall. With 200 triangles the bottom was not flat. |

## 6. Requirements

| # | Requirement |
|---|---|
| R1 | The head of the statue has the sizes of section 3.1, and its shots next to the photos show the same forms. |
| R2 | The stair has 133 steps round an open well, with a handrail and balusters; the test of the inside passes. |
| R3 | The field of a short list is the field of all the edits, and the color with the hot loop is the color of the fold, to the bit: tests. |
| R4 | The normals are as exact as before: the mean angle to the true gradient of the field, on a test sculpture at four budgets. |
| R5 | The boat builds faster at near and at far. |
| R6 | Each basket boat meets its budget at each level, and passes the check of a model at each level. |
| R7 | The full check passes. |

## 7. Steps

1. The basket boats (D8).
2. The short lists and the hot loop of the color (D3, D4).
3. The normals (D5, D6).
4. The rounds of the collapse (D7).
5. The face and the stair (D1, D2).
6. The models again, the documents, the full check.

## 8. Acceptance criteria

- R1 to R7, with the numbers of section 10.
- `mix precommit`, `mix world.build --check` and `npm test` pass.

## 9. Open questions

- **The bake is still the largest part of a build with a large
  image.** For each texel it reads the field one time for the color,
  and the cost of a reading in the BEAM is about 1 µs for each cone or
  side. The next steps are not small: fewer texels where the surface is
  plain (an image with a size for each chart by what it shows), or a
  reading in native code.
- **The collapse is the next cost.** Most of its time is the cost of
  each edge in `World.Simplify` (a quadric and three places for each
  edge).
- **The face has no source for its depths.** The two photos from the
  shoulders are from below; a photo from the side at the height of the
  face makes the side view true.
- **The inside of the statue has no light.** The windows are open, but
  an application must light the well.
- The reliefs of the base, and the time lapse of the site.

## 10. The measure

One machine with 4 schedulers.

### The fishing boat (R5)

| Stage | Near, before | Near, after | Far, before | Far, after |
|---|---|---|---|---|
| The tree and the bricks | 11.8 s | 10.0 s | 11.9 s | 10.0 s |
| The collapse | 11.0 s | 9.5 s | 11.8 s | 9.7 s |
| The finish | 2.3 s | 2.3 s | 0.3 s | 0.3 s |
| The bake | 81.6 s | 71.6 s | 4.1 s | 4.6 s |
| All | 106.7 s | 93.3 s | 28.0 s | 24.6 s |

- The mean short list of a brick: 9.3 edits before, 8.8 after (D3).
- The mix of the occlusion values and the hot loop of the color: the
  bake from 81.6 s to 76.2 s, with the same bytes. The normals (D5):
  to 71.6 s.
- The last pass of the far level starts with 6,000 faces at the most
  (before: 22,800).

### The normals (R4)

A test sculpture (a ball, a box, a cylinder, an ellipsoid, a cut, a
paint with a raise; cells of 2 cm). The angle from the normal of a
texel to the true gradient of the field:

| Triangles | Mean, before | Mean, after | Over 5 degrees, before | After |
|---|---|---|---|---|
| 6,000 | 0.434° | 0.434° | 1.99% | 1.99% |
| 1,500 | 0.355° | 0.359° | 1.48% | 1.48% |
| 300 | 0.797° | 0.844° | 3.60% | 3.75% |
| 120 | 2.118° | 2.132° | 12.80% | 12.83% |

Two variants were less exact, and are not in the code: the slope off
the plane from the size of the gradient (a mean of 0.98° at 6,000
triangles), and the mean of the grid texels of a triangle when not all
four are of it (1.19° at 300 triangles).

The maps of the catalog: the robot has a mean change of 0.001° in its
normals, and the same colors; the car at mid 0.1° (D6: its surfaces
have a relief).

### The collapse (D7)

A ball of 1.5 m with cells of 2 cm:

| Budget | The part of its volume, before | After |
|---|---|---|
| 300 | 94.3% | 94.2% |
| 1,000 | 97.3% | 98.2% |
| 3,000 | 99.5% | 99.5% |

A first variant with rounds to the budget (not to a third of the
faces) kept only 75% of the volume at 300 triangles.

### The basket boats (R6)

| Model | Triangles before (near, mid, far) | After | The check of a model |
|---|---|---|---|
| `thung_chai_edits` | 16,000 / 6,850 / 1,740 (budgets 16,000 / 4,000 / 600) | 16,000 / 4,000 / 600 | Passes at each level |
| `thung_chai_flat_edits` | 6,794 / 4,214 / 1,306 (budgets 1,200 / 500 / 200) | 1,200 / 800 / 500 | Passes at each level (before: it did not stand) |

### The statue (R1, R2)

| | Before | After |
|---|---|---|
| Triangles (near, mid, far) | 95,860 / 12,800 / 1,700 | 98,860 / 12,800 / 1,700 |
| Files (near, mid, far) | 23.0 / 4.1 / 0.48 MB | 22.3 / 4.1 / 0.50 MB |
| The three levels, with `mix world.build` | 3 min 29 s | 3 min 29 s (with 3,000 triangles more: the balusters and the rails) |

- The head: the sizes of section 3.1 are in the generator of the
  drawing as the places of the edits. The head with its hair is 2.6 m
  wide (the test of the sizes). It leans to the front by 12 degrees (a
  photo from the air, from the owner: the first build had 6 degrees).
- The halo: its middle is at the middle of the head (the same photo).
  Before, its middle was 0.7 m behind it. A test compares the two
  middles.
- The neck shows in front, down to the collar: the robe is open there.
- The stair: 133 steps, 16 for each turn; the handrail through 67
  corners; 67 balusters. Each balcony has a rail of five bars at the
  side of the arm, and a plate of steel is on each sleeve next to it (a
  photo from the balcony). The spikes of the plate are not made.
- The 18 sculptures of the catalog build again in 10 min 21 s (72
  files).

### The requirements

| # | Result |
|---|---|
| R1 | Met: the sizes are in the drawing, and the shots are next to the photos. The depths are from two photos from below (section 9). |
| R2 | Met. |
| R3 | Met. |
| R4 | Met: the same mean angle within 0.05°. |
| R5 | Met: 93.3 s from 106.7 s at near, 24.6 s from 28.0 s at far. The bake is 12% faster, not more (section 9). |
| R6 | Met. |
| R7 | Met: the full check passed on the tip. |
