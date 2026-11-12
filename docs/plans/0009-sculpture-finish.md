# Plan 0009: A sculpture with a fine finish, a rich vocabulary, and motion

Status: In progress (the owner, 2026-11-12: "Let get this `World`
project to the finish line ... build the world-class model builder that
rival Sony Dreams in concept and performance, and can produce AAA-level
models fast and accurate, taking advantaged of latest Erlang and Elixir.
Go.").

Depends on: plan 0008 (a model from edits), plan 0007 (the people build
each model as actors).

## 1. Goal

At the end, a user outside World makes a model that looks finished from
a short list of edits, sees each change at once, and gets a model that
moves:

- **The surface is the true surface.** After the cut to a budget of
  triangles, each point of the mesh is on the surface of the edits again,
  its normal is the normal of the surface, and its color is the color of
  the edits there, with soft borders where the user asks for them.
- **A few edits make much.** An edit can have a mirror and a repeat; a
  group of edits has one place and can be used many times.
- **A change is fast.** A change of one edit of a live sculpture walks
  only the cells of the tree that the change reaches.
- **A sculpture moves.** A sculpture with bones is a skinned mesh, with
  the clips of World.

## 2. What the owner asked

The message of the status line. The builder reads it with the vision of
`docs/world.md` ("an engine which outside users can use to make any
content and models. And do them fast!") and the open questions of plans
0007 and 0008. The owner can change each requirement and the order of
the steps.

## 3. The state before this plan

- A sculpture is a list of edits; a tree of processes finds its bricks,
  dual contouring makes its surface, and an edge collapse takes it to a
  budget (plan 0008). The carp of 21 edits builds in 1.8 s at near.
- Each quad has one material, so a border of two colors follows the grid
  in steps. The normals come from the angles between the triangles. After
  the collapse, the points are not on the surface.
- An edit has no mirror and no repeat: a fish with scales needs an edit
  for each scale.
- A live change takes 10% of the time of the whole sculpture: the walk
  of the tree visits each brick.
- A sculpture has no bones.

## 4. Out of scope

- A renderer (Dreams draws points; World gives a GLB to any app).
- A tool with a screen to sculpt by hand: World takes data over MCP.
- The form of the GLB of the other models of the catalog (plan 0007,
  R6): that decision stays with the owner.

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **A finish pass after the collapse.** For each point of the mesh, with the short list of edits of its brick: one or two steps of Newton along the gradient of the field put it on the surface; the gradient there is its normal; the edits give its color. The points go to processes in groups (each scheduler has work). | The collapse moves the points by its error; the field is exact and cheap at a few thousand points. The normal of the surface makes a mesh of few triangles look smooth. |
| D2 | **A color for an edit** (`color`, `#rrggbb`), next to its material. The color of the surface at a point is the fold of the edits: an edit that adds takes the color to its own by the weight of its smooth minimum; an edit that paints, by a smooth step over its `blend` across its border. A point with no color is white. The mesh has a color for each point (`COLOR_0`), which the color of its material multiplies. | The color is a function of the place, as the field is: no step of the grid shows, and the collapse needs no rule for a border of two colors. |
| D3 | **A mesh can carry its normals and its colors** (`World.Mesh`, for a mesh of triangles): a corner takes the normal of its point when it is within the angle of the mesh from the normal of its face, and the rule of the angle else (a hard edge stays hard). | One path to the GLB for each mesh; the parts of the catalog do not change. |
| D4 | **Mirror and repeat** in the data of the skill `sculpt`: `mirror` (`x`, `y` or `z`, or more of them) makes the copies of an edit across the planes of the sculpture; `repeat` (`count`, `axis`, `angle`, `move`) makes copies round an axis or along a line. **A group** (`groups`: a name to a list of edits) is used by an edit of the shape `group` with a place, a scale, a mirror and a repeat. The check counts the edits after the copies (10,000 at most). | A fish has a hundred scales, a tower a ring of windows: the user writes one and its rule (Dreams: mirror, kaleidoscope, clone). |
| D5 | **A key for each cell of the tree.** A cell keeps in the cache the keys of the bricks under it, by the hash of its short list. A walk of a cell whose key is in the cache takes its bricks from there, with no visit of its children. | A change of one edit then costs the cells that it reaches; R8 of plan 0008 with a margin. |
| D6 | **A sculpture with bones.** The data of the skill can have `bones` (a name, a head, a tail, a parent) and the name of a body plan for its clips. Each point takes weights for the bones near it (as `World.Blob`), and the part is a skinned mesh. | A model from edits swims, walks and waves as the models of the catalog do. |
| D7 | **The newest Erlang and Elixir, where they pay** (OTP 29, Elixir 1.20): processes with labels, messages of priority, aliases, `Task.async_stream` with a limit, binaries that move with no copy, ETS with `write_concurrency`, `:atomics` and `:persistent_term`. Each use has a measure in the plan. | The speed must come from the measure, not from a list of features. |

## 6. Requirements

- **R1.** After the finish pass, each point of a sculpture is at most
  1% of a cell from the surface (the value of the field there), at each
  level; before it, the points of the far carp are up to some cells away.
- **R2.** A sculpture of one material with two colors and a paint with a
  blend has no step of the grid at the border of the colors: the color of
  each point is the color of the fold of the edits at its place, within
  1 of 255.
- **R3.** The normal of each corner of a smooth sculpture (a ball) is
  within 1° of the normal of the true surface; a box of hard edits keeps
  its hard edges.
- **R4.** `mirror`, `repeat` and `group` give the same model as the list
  of their copies written by hand; the check gives each error with its
  path, and counts the copies.
- **R5.** A change of one edit of a live sculpture of 1,000 edits at near
  takes less than 7% of the time of the whole sculpture.
- **R6.** A sculpture with bones is a skinned mesh that passes the
  validator of glTF, and a clip of its body plan moves it.
- **R7.** A model of the catalog from edits shows these (colors with soft
  borders, a mirror, a repeat, bones), with shots next to the model of
  before, the triangles of its budget, and its time on the bench.

## 7. Steps

1. **The finish pass** (D1, D3; R1, R3): the points on the surface, the
   normals of the surface.
2. **Colors** (D2, D3; R2).
3. **Mirror, repeat and groups** (D4; R4), `docs/format.md`.
4. **The keys of the cells** (D5; R5).
5. **Bones** (D6; R6).
6. **The model and the measure** (R7), the docs.

## 8. Acceptance criteria

- The tests of R1 to R6.
- The shots of step 6 next to the model of before, and the numbers of
  `mix world.bench`.
- The full check passes on the tip of each push.

## 9. Open questions

- **The model of step 6.** The carp from edits, with its scales and its
  colors, unless the owner names another one.

## 10. The measure

### Steps 1 and 2: the finish pass and the colors (2026-11-12)

`World.Sculpt.Finish` runs after the collapse, in `World.Sculpt.model/2`
and in the meshes of a live sculpture. The carp from edits (cells of
3.5 mm at each level), the distance of its points from the surface of
its edits, as a part of a cell:

| Level | Points | Before: the most, the mean | After: the most, the mean | The time of the pass |
|---|---|---|---|---|
| near (20,000 faces) | 10,642 | 62%, 1.8% | 0.01%, 0.0007% | 0.24 s |
| mid (3,000) | 1,815 | 62%, 2.9% | 0.01%, 0.0008% | 0.06 s |
| far (600) | 428 | 41%, 4.2% | 0.01%, 0.001% | 0.03 s |

R1 is met. The volume of the far carp is 2,006 cm³, not 1,990 (the
surface has 2,121): the points are on the surface again, and the rest is
the flat faces between them.

Two steps of Newton were not enough at the tip of a thin fin (8% of a
cell): there the field of an ellipsoid is only a bound, with a short
gradient. A point takes up to five steps, and stops as soon as it is on
the surface, so only such points pay.

The carp has its colors on its edits now, on one white material: a
gold body, a dark back and a pale belly as paints with a blend of 3 cm,
bronze fins. The borders of the colors are smooth at each level (the
shots went to the owner), and the far level has the light of the true
surface. One fault came out: a paint with a color and no material gave
its faces no material (a second mesh, in blocks); a paint with no
material keeps the material under it.

### Step 3: mirror, repeat and groups (2026-11-12)

The data of the skill `sculpt` takes `mirror` and `repeat` on each edit,
and `groups` with edits of the shape `group` (`docs/format.md`, "A
sculpture"). Each gives the same field as its copies written by hand
(R4, `test/world/skills/sculpt_test.exs`), and each wrong value gives its
path. Two points of the work:

- **The copy of a group is the whole group**, in the order of its edits,
  then the next copy: the order of the edits changes a smooth joint, so
  a copy edit by edit gave another surface than the group by hand.
- **A mirror keeps the right hand:** the frame of a copy is made again
  from its mirrored axis and up, so its x is the other way. Each shape
  is the same across its x; the points of a tube turn theirs.

A change of a live sculpture is one shape: an edit with a mirror or a
repeat is refused there with its path.

### Step 5: bones (2026-11-12)

The data of the skill `sculpt` takes `bones`, `bone_blend`, `plan`,
`gait` and `clips` (`docs/format.md`, "A sculpture with bones"). With
bones, the sculptor makes a `World.Figure` in place of a part
(`World.Sculpt.Bones`): the build, the people and the GLB take it as
they take an animal of the catalog. The points of the work:

- **The weights come from the distance to the bones.** Each point
  follows the bone nearest to it (the line from its head to its tail),
  and each other bone less, down to nothing at `bone_blend` more than
  the nearest. This is the rule of `World.Blob`; a sculpture has no
  radius for each bone, so its user gives only the lines of the bones.
- **The rig takes the normals of the surface** (`World.Rig`, the mesh
  option `normals`): the finish pass gave them, and the normals from the
  faces of a mesh in its budget are less smooth.
- **A body plan gives its clips where its animations need no clips of a
  template:** `fish` now (`swim`, `idle`). The other plans (a bird, an
  animal of four legs, a primate) need bones and limbs that a test must
  cover first: they stay open.
- **Clips from keys** are for each other motion: a key is a time and a
  pose (a bone to its `flex`, `spread` and `twist`), the pose between
  two keys is the mean by the time.

R6 by test (`test/world/sculpt_bones_test.exs`): a fish of two edits and
seven bones is one skinned mesh in the GLB, each point has weights that
add to 1, its `swim` moves the points of its tail more than 5 cm and
the middle of its body less than a quarter of that, and a clip of three
keys puts its head down at the middle key. The validator of glTF checks
the carp of step 6.

