# 0008 A model from edits: shapes added and taken away, as in Dreams

| Field | Value |
|---|---|
| Status | Draft |
| Depends on | Plan 0007 (the people build each model as actors). |
| Changes | A new module of fields of distances (`World.SDF`); an evaluator in blocks of cells that the people share; a skill `sculpt` for blueprints and drawings; the format of a sculpture in `docs/format.md`; one model of the catalog made again from edits. |

## 1. Goal

World can make a part from a short list of edits: simple shapes (a
ball, a box, a cylinder, a cone, a ring, a tube along a curve) that are
added to the part, taken away from it, or only paint it, each with a
blend that makes a smooth joint. Any shape can come from a few edits,
as in the game Dreams of Media Molecule.

At the end:

- **A sculpture is data.** A list of edits in JSON is small: a project
  sends a sculpture over MCP as it sends a blueprint, and World keeps it
  as the source of the part.
- **The people share the work of one part.** The space of the part is
  in blocks of cells, and each block has the short list of the edits
  that can reach it. Each block is a task for a person, so the people
  of a construction evaluate one part at the same time (plan 0007).
- **The levels of detail come from the same edits:** the cells are
  smaller at near and larger at far.
- **One model of the catalog** comes from edits, and the measure
  (`mix world.bench`) compares it with the model of today.

## 2. What the owner asked

On 2026-11-12:

> Somebody mentioned about Sony Dreams engine, which is one of the kind,
> and the technical talk at https://www.youtube.com/watch?v=u9KNtnCZDMI.
> At quick glance, it seems to be a very powerful way to build...
> Anything, from a few primitives by adding or substracting them. Can
> we learn more about that and see what we can use?

Then, on the summary and the proposal of this plan: "Yes" (write it as a
draft).

## 3. What Dreams does

From the talk of Alex Evans, "Learning From Failure" (Umbra Ignite 2015,
the same talk as SIGGRAPH 2015, Advances in Real-Time Rendering), and its
slides with the notes of the speaker
(https://advances.realtimerendering.com/s2015/AlexEvans_SIGGRAPH-2015-sml.pdf):

- **A model is a flat list of edits, in order**, not a tree: 1 to about
  100,000 edits. The shapes: strokes along a cubic curve, cylinders,
  cones, boxes, ellipsoids, prisms, rings, "markoids" (a superellipsoid
  with a power for each axis) and pyramids. The modes: add, subtract,
  or color only. Each edit has a hard or a soft blend.
- **The soft blend** (Dave Smith, Media Molecule): `e = max(r - |a - b|,
  0); min(a, b) - e * e / (4 r)`. It is the hard minimum when the two
  distances are more than `r` apart, so an edit reaches only `r` past its
  shape. It is the same as the quadratic smooth minimum of Inigo Quilez
  (https://iquilezles.org/articles/smin).
- **Only local edits:** no deformation of the space, no blur.
- **The evaluation is a hierarchy:** a coarse grid, each cell with the
  list of the edits that can reach it (with the reach of the soft
  blend); each step splits a cell in 4 × 4 × 4 and shortens its list;
  empty and full cells stop early. Only the cells near the surface are
  evaluated: more than 99% of the work of each edit at each cell goes
  away (10 to 100 million cells in a second on a PS4).
- **The distance is of the max norm** in the evaluator: many shapes are
  simpler, and a ball of the max norm is a cube, as a cell is.
- **The surface:** they tried polygons (marching cubes, dual contouring)
  and stopped (dense meshes, sharp and smooth edges hard to get right).
  The game draws points and bricks of the field on the GPU. The files of
  the players keep the edits only, not the field.

## 4. The state before this plan

- `World.Cast` makes the cast of the statue from a field of distances on
  a grid of cells, and `World.Blob` the body of an animal from the
  smooth union of round cones along its bones. Each makes its surface by
  surface nets (one point in each cell that the surface crosses, a quad
  across each edge that it cuts).
- Each evaluates the whole grid in one process, and has its own shapes
  and its own blend: there is no general list of edits.
- A model of the catalog is code; a model in data is a blueprint or a
  drawing of skill nodes (`docs/format.md`, "A blueprint in data", "A
  drawing").

## 5. Out of scope

- The renderers of Dreams (points and bricks on the GPU): World makes
  GLB meshes.
- An editor of sculptures (a page to add edits by hand).
- Edits that move in an animation: a sculpture is rigid, or it follows
  bones as the skin of `World.Blob` does.

## 6. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **A sculpture is an ordered list of edits.** Each edit: `shape` (`ball`, `box`, `cylinder`, `cone`, `ring`, `tube` with points of a curve, `superellipsoid` with a power for each axis), its sizes, its place and turn (a frame), `mode` (`add`, `subtract`, `paint`), `blend` (m, 0 for a hard edge), and a `material` (a role of the palette). | The model of Dreams: simple to write, to send and to check. |
| D2 | **The blend of Dreams.** The soft minimum above (and its mirror for subtract), so an edit reaches only its blend past its shape. | The reach is what lets a cell skip the edits far from it. |
| D3 | **Blocks of cells, each a task.** The bounds of the sculpture are in blocks (16 × 16 × 16 cells, an estimate); each block has the edits that can reach it, and splits as in Dreams (empty and full blocks stop). The construction gives each block near the surface to a person; the surfaces of the blocks join at their shared faces. | The work of one part goes to many people at once (plan 0007): the BEAM uses each scheduler. |
| D4 | **The surface by surface nets**, as `World.Cast` and `World.Blob` make it; the cells are 2, 4 and 8 times larger at mid and far (the levels of `World.Detail`). An edge of a box stays sharp: the point of a cell goes to the corner of its edits (a step of dual contouring) when the cell has a hard edge. | One surface method in World; sharp edges where the edits are hard. |
| D5 | **The skill `sculpt`** takes the edits in a node of a blueprint or a drawing, and the trade `sculptor` makes it. Its format is in `docs/format.md` ("A sculpture"), and `check_blueprint` checks it. | A project sends a sculpture as it sends any blueprint. |
| D6 | **The euclidean distance first.** The max norm of Dreams comes only if the measure says that it is needed. | Surface nets want a smooth field; the max norm is a choice of speed on a GPU. |

## 7. Requirements

- **R1.** `World.SDF` gives the distance of each shape (a test against the
  exact distance at points inside, on and outside it), and the blend of
  D2 (the hard minimum when the distances are more than the blend apart).
- **R2.** The evaluator evaluates only the cells near the surface: for a
  sculpture of 100 edits, the evaluations are less than 5% of 100 edits
  at each cell of the grid.
- **R3.** The surface of a sculpture is closed and has its faces to the
  outside (`World.Check.model/1`), with no gap at the faces of the
  blocks.
- **R4.** With 4 people, a sculpture of 1,000 edits takes less than half
  the time that it takes with 1 person.
- **R5.** A sculpture comes in a blueprint over MCP (`check_blueprint`,
  `build`), and its errors have their paths.
- **R6.** The model of step 4 comes from at most 200 edits, has the
  triangles of the budget of its level, and its shots stand next to the
  shots of today.

## 8. Steps

1. **`World.SDF`** (D1, D2, D6; R1): the shapes, the modes, the blend,
   their tests.
2. **The evaluator in blocks** (D3, D4; R2, R3): the blocks and their
   edits, the split, the surface by surface nets with sharp edges, the
   join of the blocks.
3. **The people evaluate the blocks** (D3; R4): each block a task of the
   construction.
4. **The skill `sculpt` and its format** (D5; R5), `docs/format.md`.
5. **One model from edits** (R6): a model of the catalog made again (a
   simple animal, or the rubble of plan 0006), with its shots and the
   measure.

## 9. Acceptance criteria

- The tests of R1 to R5.
- The shots of step 5 next to the model of today, and the numbers of
  `mix world.bench`.
- The full check passes on the tip of each push.

## 10. Open questions

- **The order.** This draft comes after plan 0007 (its steps 2, 6 and 7
  are still open). Or does the owner want it first?
- **The model of step 5.** A simple animal (its body is a field today,
  `World.Blob`), the rubble of the take-down, or another one?
- **Sharp edges** (D4): a step of dual contouring in the cells with a
  hard edge, or a finer grid near hard edges only?
