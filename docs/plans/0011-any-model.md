# Plan 0011: World builds any model, on each core

Status: Done (2026-11-13), but for R1: the build of the robot uses 3.1
of 4 cores and takes 5.4 s (the aim: 3.2 cores and 4.5 s; before: 2.4
cores and 7.2 s). Section 10 has the measure. (The owner, 2026-11-13:
"You could get the project
`World` to the finish line, that can build any models in parallel, the
way Dreams project did for Sony. Get it done! Not just build a model or
two, but any model!").

Depends on: plan 0010 (the maps, the words of an edit, the body plans),
plan 0007 (the measure of each build).

## 1. Goal

A client gives the edits of a model, of any kind, and World builds it:
with no code for that model, with each core of the computer at work in
each stage, and with other models at the same time.

At the end:

- **Any list of edits builds.** No valid list of edits stops a build or
  gives a broken mesh, broken maps or a file that an app refuses. A
  test makes random sculptures and proves it.
- **Each stage of a build uses each core.** The tree and the bricks do
  (3.98 of 4 cores). The collapse (1.63), the charts and the bake
  (1.96) do not: a model from edits uses 2.2 to 2.4 of 4 cores.
- **Many kinds of models are in the catalog, each from edits only:**
  animals on two and on four legs, a bird, a fish, a vehicle, a
  building, a plant, a piece of furniture, a vessel, a tool. Each has
  its levels, its maps and, where it moves, its bones.
- **Many models build at the same time,** with each core in use and a
  limit of the memory.

## 2. What the owner asked

2026-11-13, after plan 0010 (a carp and a robot from edits): "May I
wasn't clear. You are the top frontier, you could get the project
`World` to the finish line, that can build any models in parallel, the
way Dreams project did for Sony. Get it done! Not just build a model or
two, but any model!"

## 3. The state before this plan

The build of the robot at near (12,000 triangles, an image of 1,024
texels), stage by stage, on 4 schedulers (a spin test gives 4 real
cores: 12.1 units of work in a second with 4 processes, 3.5 with 1):

| Stage | Time | Cores at work |
|---|---|---|
| The tree and the bricks | 0.71 s | 3.98 |
| The collapse to the budget | 2.53 s | 1.63 |
| The finish | 0.13 s | 1.46 |
| The charts and the bake | 3.9 s to 4.9 s | 1.96 |
| The PNG files | 0.15 s | 0.98 |
| The scene and the GLB | 0.13 s | 0.66 |
| All of the skill | 7.2 s | 2.41 |

The catalog has two models from edits (the carp, the robot) and three
body plans for a sculpture (`fish`, `bird`, `biped`). No test builds a
random list of edits through the whole skill.

## 4. Out of scope

- An editor for a person (a screen with tools). The edits come as data
  (a drawing, the MCP tools, the live sculpture).
- A GPU. The plan uses the cores of the BEAM.
- The models of the catalog that are not from edits stay as they are.

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **A measure of each stage first,** with the cores at work (`:scheduler_wall_time`), on the robot and on the carp. A stage is done when it uses at least 3 of 4 cores, or when it takes less than 5% of the build. | A change is better only if the numbers say so (plan 0007, D1). |
| D2 | **The collapse works in regions that do not wait for one process.** The measure of the collapse decides the way: more of the work in the regions, or a last pass in parts. | 2.5 s of the 7.2 s of the robot are in a stage with 1.63 cores at work. |
| D3 | **The charts are made for each region of the mesh in its own process,** and the bake sends each process only what it needs. | The charts are made in one process (0.76 s), and the bake uses half of the cores. |
| D4 | **A property test builds random sculptures** through the skill: each shape, each mode, each blend, a finish, copies, a budget, maps. It checks the mesh (each edge in two faces, the budget), the maps (each triangle has texels) and the file (the validator of glTF). | "Any model" needs a proof over many lists of edits, not two models. |
| D5 | **A body on four legs is a body plan of a sculpture** (the bones of a four-legged animal of World, with its walk). | Most animals walk on four legs. |
| D6 | **A gallery in the catalog:** each kind of model from edits only, small (10 to 40 edits), with its levels and its maps, and a line in its sources that it is not a copy of a real thing. The bench builds each one. | The proof that a kind of model needs no code of its own. |
| D7 | **Many models at once share the cores:** the work of each model goes to the same schedulers, and a build waits when the memory of the node has no room. | A node gets many orders at the same time. |

## 6. Requirements

- **R1.** The build of a model from edits at near uses at least 3.2 of 4
  cores on average, and the robot at near takes less than 4.5 s (it
  takes 7.2 s).
- **R2.** 200 random sculptures build with no error; each mesh is
  closed and in its budget; each triangle with an area has a texel in
  the maps; the GLB of each passes the validator.
- **R3.** A sculpture with the bones of an animal on four legs walks:
  its four feet move in the order of a walk, and a foot on the ground
  does not slide.
- **R4.** The catalog has at least 10 kinds of models from edits, and
  the bench builds each at each level.
- **R5.** 8 models from edits built at the same time take less time
  than the 8 one after the other, with at least 3.2 of 4 cores at work.

## 7. Steps

1. **Each stage on each core** (D1 to D3; R1).
2. **Any list of edits builds** (D4; R2).
3. **Four legs, and the gallery** (D5, D6; R3, R4).
4. **Many models at once, the measure and the documents** (D7; R5).

## 8. Acceptance criteria

- The tests of R2 and R3.
- The tables of R1, R4 and R5 in this plan.
- The full check passes on the tip of each push.

## 9. Open questions

- **R1 is not met.** The parts of a build that one process does are
  left: the join of the regions, the last pass of the collapse, the
  finish, the places of the charts in the image, the figure, the file.
  Each is small, but together they keep one core of four free for about
  a quarter of the build. A next plan can put the finish and the last
  pass in regions.

## 10. The measure

One machine with 4 schedulers (4 processes of a spin test do 3.5 times
the work of one). The cores at work come from `:scheduler_wall_time`.

### Step 1: each stage on each core (R1)

The build of the robot at near (12,000 triangles, an image of 1,024
texels), after all the steps:

| Stage | Time | Cores at work | Before |
|---|---|---|---|
| The tree and the bricks | 0.75 s | 3.97 | 0.71 s, 3.98 |
| The collapse to the budget | 1.46 s | 2.60 | 2.53 s, 1.63 |
| The finish | 0.12 s | 1.64 | 0.13 s, 1.46 |
| The charts and the bake | 2.79 s | 3.12 | 3.9 s to 4.9 s, 1.96 |
| The PNG files | 0.17 s | 0.97 | 0.15 s, 0.98 |
| The scene and the GLB | 0.20 s | 0.49 | 0.13 s, 0.66 |
| All of the skill | 5.36 s | 3.14 | 7.2 s, 2.41 |

The carp at near: 4.15 s with 3.06 cores at work. The house at near:
5.91 s with 3.08. Two builds of one model give the same bytes.

What changed:

- **The collapse.** The first round is the regions (as before). The
  second round is new: the points that the regions held (the points at
  their borders, most of the points that are left) move in groups, each
  group in a process of its own; then each region gives the cost of
  each of its collapses, and the budget takes the collapses with the
  least costs over all the regions. The last pass has little work.
- **The charts** are made for each group of 4,000 triangles in its own
  process, and the texels of the maps in two processes for each
  scheduler (a process waits at times). One fold over the edits gives
  the color and the finish of a texel. The PNG files are made in their
  own processes while the figure is made.

**R1 is not met:** 3.14 of 4 cores (the aim: 3.2) and 5.4 s (the aim:
4.5 s).

### Step 2: any list of edits builds (R2)

`test/world/sculpt_random_test.exs` builds random sculptures through
the skill (each shape, each mode, blends, a finish, a glow, a paint
with a raise, a mirror, a ring, a row, a budget, maps). 1,000 of them
(5 seeds of 200) build with no failure, and the validator of glTF has
0 errors and 0 warnings for the 200 files of a run.

The faults that the test found, each with a repair and a test of its
own:

| Fault | Repair |
|---|---|
| A sculpture with no surface (a crop took all of it) stopped the bake. | No maps for no triangles. |
| A GLB with an empty list of materials did not pass the validator. | No list. |
| Two bricks gave two places (different in the last bit) to a point of the grid that they share. A surface through such a point was open. | The place of a point comes from its number in the whole grid. |
| A flat face exactly at a border of bricks had no brick on its outer side: an open mesh. | The root of the tree has one cell more on each side. |
| The bounds of the edits did not hold a blend at the sharp edge of a wedge, a prism, a pyramid or a superellipsoid. | The box of such a shape is the box of the points where its field is less than the reach of the blends. |

### Step 3: four legs, and the gallery (R3, R4)

The body plan `quadruped` of a sculpture (`World.Animals.FourLegs`):
`walk` (one foot after the other, three feet on the ground at most
times), `trot` (the two feet of a diagonal at one time) and `idle`.
The test of the dog (`test/world/sculpt_bones_test.exs`) checks the
order of the feet, and that a foot on the ground does not slide: R3.

The gallery found one more fault: a region had its share of the budget
by its count of faces, so the chimney of the house (a small box on a
large flat roof) became a lump. Now a flat part keeps few faces, the
budget goes to the regions by the cost of their collapses, and no
round moves the surface by more than half a cell before the last pass.

The catalog has 10 kinds of models from edits. `mix world.bench` builds
each at each level (through a construction, with 4 people): R4.

| Model | Kind | Edits | Near (time, triangles) | Mid | Far |
|---|---|---|---|---|---|
| `carp_edits` | A fish (the body plan `fish`) | 30 | 4.8 s, 10,800 | 2.5 s, 3,240 | 1.6 s, 600 |
| `robot_edits` | A robot on two legs (`biped`) | 29 | 5.8 s, 12,000 | 2.0 s, 4,000 | 0.7 s, 600 |
| `dog_edits` | A dog on four legs (`quadruped`) | 15 | 4.7 s, 8,000 | 1.3 s, 3,000 | 0.5 s, 600 |
| `bird_edits` | A bird (`bird`) | 10 | 2.0 s, 6,000 | 0.8 s, 2,000 | 0.4 s, 500 |
| `car_edits` | A car | 17 | 4.9 s, 10,000 | 1.5 s, 3,000 | 0.4 s, 600 |
| `house_edits` | A house | 10 | 6.7 s, 6,000 | 1.8 s, 2,000 | 0.5 s, 500 |
| `tree_edits` | A tree | 10 | 2.3 s, 6,000 | 0.8 s, 2,000 | 0.2 s, 400 |
| `chair_edits` | A chair | 9 | 4.3 s, 8,000 | 1.1 s, 2,500 | 0.4 s, 600 |
| `teapot_edits` | A teapot | 10 | 2.0 s, 6,000 | 0.7 s, 2,000 | 0.2 s, 500 |
| `hammer_edits` | A hammer | 6 | 1.2 s, 3,294 | 0.3 s, 1,500 | 0.1 s, 400 |
| All | | | 38.7 s | 12.8 s | 5.0 s |

### Step 4: many models at once (R5)

The 8 models of the gallery of this plan, at near
(`mix world.bench NAMES --level near --at-once N`):

| Builds | Time | Cores at work | Most memory |
|---|---|---|---|
| One at a time | 30.0 s | 2.57 | 498 MB |
| 8 at one time, with no gate | 25.0 s | 3.89 | 1,106 MB |
| 2 at a time | 23.1 s | 3.52 | 678 MB |
| 8 at one time, through the gate | 25.8 s | 3.59 | 489 MB |

The 10 models at one time, through the gate: 35.2 s with 3.71 cores at
work and 502 MB, against 42.7 s one at a time.

One build has most of the cores at work already, so many builds at one
time gain little time, and without a limit each of them has its memory
at the same time. So the node has a gate (`World.Sculpt.Gate`): half of
the schedulers are the builds of sculptures in work, and the others
wait in their order; with a limit of memory (`memory_mb`), a build
waits also while the VM has more. A build gives the waste of its heap
back when it goes out, so 8 builds through the gate need the memory of
one. **R5 is met:** 25.8 s against 30.0 s, with 3.59 cores at work.

### The requirements

| # | Result |
|---|---|
| R1 | Not met: 3.14 cores at work (the aim: 3.2) and 5.4 s for the robot (the aim: 4.5 s; before: 2.41 cores and 7.2 s). |
| R2 | Met: 1,000 random sculptures, and the validator on 200 files. |
| R3 | Met: the test of the dog. |
| R4 | Met: 10 kinds, each built at each level by the bench. |
| R5 | Met: 8 at one time take 25.8 s, one at a time 30.0 s; 3.59 cores at work. |
