# 0008 A model from edits, made by many hands at once

| Field | Value |
|---|---|
| Status | Approved (the owner, 2026-11-12: "I approve plan") |
| Depends on | Plan 0007 (the people build each model as actors). It comes before the open steps of plan 0007 (the owner, 2026-11-12). |
| Changes | A new module of fields of distances (`World.SDF`); a tree of processes that finds the cells near the surface; bricks of the field in binaries; a surface with sharp edges and no gaps between bricks; a cache of bricks by hash; a skill `sculpt` for blueprints and drawings; the format of a sculpture in `docs/format.md`; one model of the catalog made again from edits. |

## 1. Goal

The vision of the owner (`docs/world.md`, "The vision"): World is an
engine that outside users use to make any content and models, and fast,
as Dreams is. Dreams and the papers are a reference (sections 3 and 4):
World learns from them, and chooses the way that is best for it, on the
parallel architecture of Erlang (the owner, 2026-11-12).

At the end:

- **Any shape from a few simple things.** A part is a short list of
  edits: simple shapes (a ball, a box, a cylinder, a cone, a ring, a
  capsule, a tube along a curve) that are added to it, taken away from
  it, or only paint it, each with a blend that makes a smooth joint.
- **A sculpture is data.** The list of edits is small JSON. A user sends
  it over MCP in a blueprint or a drawing, World checks it (with the
  path of each error), and the edits are the source of the part: World
  makes the part again from them, as Dreams does.
- **Fast, on the BEAM.** A tree of processes finds the cells near the
  surface: each cell process takes the short list of the edits that can
  reach it, and starts a process only for each child cell that the
  surface can cross. So the work goes to each scheduler as the tree
  grows, and only the cells near the surface do the work of the field.
  When one edit changes, only the bricks that it reaches are made
  again.
- **Each level of detail from the same edits**, and in the budget of its
  triangles.
- **A live sculpture.** A sculpture can be a process that keeps its
  edits and takes each edit as a message: it makes again only the bricks
  that the edit reaches, and streams them, so a user sees each change
  soon.
- **One model of the catalog** comes from edits, and the measure
  (`mix world.bench`) compares it with the model of today.

## 2. What the owner asked

On 2026-11-12:

> Somebody mentioned about Sony Dreams engine, which is one of the kind,
> and the technical talk at https://www.youtube.com/watch?v=u9KNtnCZDMI.
> At quick glance, it seems to be a very powerful way to build...
> Anything, from a few primitives by adding or substracting them. Can
> we learn more about that and see what we can use?

> Do more research on Dreams, find any papers on it. Let get this right!

> I think my vision for World is very similar to Dreams: an engine which
> outside users can use to make any content and models. And do them
> fast!

Then "Yes" to the order: this plan before the open steps of plan 0007,
and:

> The research is just for reference. We learn from them and choose the
> best approach for us, taking advantage of the parallel architecture of
> Erlang.

> For the open question, yes, live sculpture is part of the plan. I
> approve plan.

## 3. What Dreams does (a reference)

The sources are in section 12 ([E1] and the others).

**The model.** A sculpture of Dreams is a flat list of edits in order,
not a tree: 1 to about 100,000 edits [E1]. The shapes: strokes along a
cubic curve, cylinders, cones, boxes, ellipsoids, prisms, rings,
"markoids" (a superellipsoid with a power for each axis) and pyramids.
The modes: add, subtract, or color only. Each edit has a hard or a soft
blend. No edit deforms the space or blurs it: each edit is local [E1].
The game keeps the edits, not the field, and makes each sculpture again
from them [E1][E4].

**The soft blend** (Dave Smith, Media Molecule) [E1]:
`e = max(r - |a - b|, 0); min(a, b) - e * e / (4 r)`. It is the hard
minimum when the two distances are more than `r` apart, so an edit
reaches only `r` past its shape. It is the quadratic smooth minimum of
Inigo Quilez [P2].

**The evaluation** [E1]. A brute force (100,000 edits at each cell of a
grid of 1,000³) is too much. Dreams starts from a coarse grid, gives
each cell the list of the edits that can reach it (with the reach of
the soft blend), splits each cell in 4 × 4 × 4 and shortens its list,
and stops at empty and full cells. More than 99% of the work goes away:
10 to 100 million cells in a second on a PS4 (8,274 edits make 5.2
million cells near the surface in 0.09 s). The renderers need 1 to 1.5
cells of good field on each side of the surface. The evaluator uses the
max norm (a ball of it is a cube, as a cell is).

**What shipped** [E2][E3][E4]. Dreams tried polygons (marching cubes,
dual contouring) and stopped: the meshes were dense, sharp and smooth
edges were hard to tune, and a mesh that is both manifold and with no
self-intersection was hard [E1]. The game draws:

- **hulls:** the field in bricks of 8 × 8 × 8 cells (a payload of
  7 × 7 × 7 and a border of one cell), with the color and the distance,
  only near the surface, at several levels of detail; a ray goes through
  each brick from its faces [E2][E3]. Alex Evans, 2021: "exactly" the
  sparse tiles of Sebastian Aaltonen, "down to the same constants" [E3];
- **fluff ("flecks"):** painterly strokes on the hull [E2][E4].

The budget of a sculpture (the "thermometer") grows with its surface
and its detail [E5]. Its collision is up to 65,536 spheres [E5].

No patent of Media Molecule or Sony covers Dreams. A later patent of
Alex Evans at NVIDIA covers rays through sparse grids of fields
(US11887245B2) [E6].

## 4. What the papers give (a reference)

- **The distance of each shape** [P1]. The ball, the box, the round
  box, the capsule, the cylinder, the capped cone and the ring have an
  exact distance; the ellipsoid and the superellipsoid have a bound only
  [P3]. A tube along a quadratic curve has an exact distance (a cubic
  equation); a cubic curve goes in quadratic pieces.
- **A bound is enough to skip a cell** [P4][P5]. When the field changes
  by at most the distance (a Lipschitz constant of 1), a cell whose
  field is more than its half diagonal from zero has no surface.
  `min` and `max` of such fields, and the smooth minimums of Quilez
  (quadratic, root, exponential), keep the constant at 1 (their partial
  derivatives are not negative and add to 1); a stretch of a shape on
  one axis breaks it unless the field is divided by the largest stretch
  [P2][P11].
- **Each cell with its own short list** [P6][P7][P8]. Interval
  arithmetic over a box gives the range of the field in it (Duff 1992);
  a `min` or `max` whose branch wins over all the box drops the other
  branch for the box and its children (Keeter 2020, "tapes"); the same
  with smooth blends and Lipschitz bounds gives a short list of edits
  for each cell (Barbier et al. 2025, "Lipschitz Pruning") — the
  evaluator of Dreams, as a paper.
- **The surface.** Surface nets: one point in each cell that the surface
  crosses, a quad across each edge of the grid that it cuts [P9] (World
  makes its casts and its blobs so). Dual contouring puts the point at
  the least squared distance to the planes of the edges that the cell
  cuts, so a sharp edge stays sharp [P10]; manifold dual contouring
  keeps the mesh manifold [P12]; probabilistic quadrics solve the point
  in closed form, with no SVD [P13].
- **The bricks and their seams.** A brick with a border of one cell and
  one rule for the owner of each shared edge makes one surface with no
  gaps [E3][P14]; a seam between levels needs cells of transition
  (Transvoxel) [P15].
- **The budget of triangles:** an edge collapse by quadric error metrics
  [P16].
- **Sparse storage:** a shallow tree of nodes of 8³ cells (OpenVDB)
  [P17].

## 5. The state before this plan

- `World.Cast` makes the cast of the statue from a field of distances on
  a grid of cells, and `World.Blob` the body of an animal from the
  smooth union of round cones along its bones. Each makes its surface by
  surface nets [P9], evaluates the whole grid in one process, and has
  its own shapes and blend. There is no general list of edits.
- A model of the catalog is code; a model in data is a blueprint or a
  drawing of skill nodes (`docs/format.md`).
- Plan 0007 measured that the time of a model of one part (an animal, a
  person) is in the code that makes its one part in one process (1,482
  ms of 1,636 ms for the douc), not in its triangles.

## 6. Out of scope

- The renderers of Dreams (rays through bricks, flecks on the GPU):
  World gives GLB meshes, which each app shows.
- An editor of sculptures (a page to add edits by hand); a user sends
  the edits as data.
- Edits that move in an animation: a sculpture is rigid, or it follows
  bones as the skin of `World.Blob` does.
- Collision shapes from the field (Dreams uses spheres [E5]): a later
  plan.

## 7. Decisions

What the BEAM is good at: many small processes, messages (and messages
of priority), supervision, and large binaries that go from one process
to another with no copy. What it is not good at: arithmetic in bulk
(no GPU, no SIMD). So each evaluation of a cell costs much, and World
must evaluate few cells: the cut of the work comes first, and the
parallel work second.

| # | Decision | Why |
|---|---|---|
| D1 | **A sculpture is an ordered list of edits.** Each edit: `shape` (`ball`, `box`, `round_box`, `capsule`, `cylinder`, `cone`, `ring`, `ellipsoid`, `superellipsoid` with a power for each axis, `tube` through the points of a curve), its sizes (m), its place and turn (a frame), `mode` (`add`, `subtract`, `paint`), `blend` (m; 0 is a hard edge), and a `material` (a role of the palette). The edits are the source: World keeps them, and makes the part again from them. | Simple to write, to send, to check and to keep [E1]. |
| D2 | **The quadratic smooth minimum** for a blend (its mirror for `subtract`; `paint` changes the material only, in its blend). A shape with no exact distance (the ellipsoid, the superellipsoid, a stretch) gives a bound with a Lipschitz constant of 1. | An edit reaches only its blend past its shape, and each field stays a safe bound, so a cell can skip each edit that cannot reach it [E1][P2][P4]. |
| D3 | **A tree of processes finds the cells near the surface.** The cell of the bounds of the sculpture is a process with the edits that can reach it. It splits in 4 × 4 × 4: for each child, the ranges of the field over the child, folded edit by edit (`World.SDF.prune/3`), give its short list (an edit goes when, at its step, it changes the field at no point of the child), or tell that it is empty or full. (Step 1 found that the box of an edit grown by its blend is not enough: the blend of a later edit bends the field of the edits before it.) It starts a process only for each child that the surface can cross, and waits for their results (fork and join). A cell of 8 × 8 × 8 cells of the grid is a leaf: a brick. | Only the cells near the surface do the work of the field; the work spreads to each scheduler as the tree grows, with no plan of the work before it [E1][P6][P7][P8]. |
| D4 | **One sculptor and its crew.** The construction gives one task `sculpt` to a person of the trade `sculptor`; the tree of D3 is the crew of its hand (plan 0007, D5): the processes of the tree are linked to the hand, so a stop of the person (a message of priority) stops the whole tree at once. The log has the task, not each brick. | The construction and its log stay small (a sculpture can have thousands of bricks), and the tree uses each scheduler, not only the people of the budget. |
| D5 | **A brick is a binary.** The field of a brick (its 9 × 9 × 9 points with a border of one cell: 2.9 KB of floats of 32 bits) and its piece of the surface are binaries. A binary of more than 64 bytes goes from one process to another with no copy (a reference). A brick gives its piece of the surface as soon as it is made, so the pieces stream to the hand. | The data of the work moves between the processes with no cost, and the memory stays in the bricks near the surface. |
| D6 | **A cache of bricks by hash.** The key of a brick is a hash of its place, its level and its short list of edits; its piece of the surface goes into a table (ETS) of the node by that key. A brick with the same key is not made again: in the next build of the same sculpture, after a change of one edit (only the bricks that the edit reaches have a new key), or in the sculpture of another user. | The two speeds of the vision: the work of many processes at once, and no work for what did not change. |
| D7 | **The surface by dual contouring in each brick**: one point in each cell that the surface crosses, at the least squared distance to the planes of its cut edges (probabilistic quadrics [P13]), kept in its cell; a quad across each cut edge [P10]. Each shared edge has one owner brick, and the border of each brick makes its points match those of the next one [P14]. | Sharp edges stay sharp where the edits are hard, and the surface has no gap between bricks. Surface nets (World today) is the same method with the point at the mean. |
| D8 | **The levels of detail:** cells of 2 cm, 8 cm and 32 cm (an estimate) at near, mid and far (the levels of `World.Detail`), then an edge collapse by quadric error metrics to the budget of triangles of the level [P16]. | The same edits at each level, each level in its budget. |
| D9 | **The skill `sculpt`** takes the edits in a node of a blueprint or a drawing. Its format is in `docs/format.md` ("A sculpture"), and `check_blueprint` checks it (the shapes, the sizes, the modes, at most 10,000 edits: an estimate). | A user sends a sculpture as it sends any blueprint. |
| D11 | **A live sculpture is a process** (a GenServer under a supervisor, by the hash of its first edits or a name of its user): it keeps the edits, the tree of its cells and the keys of its bricks. A message `{:edit, i, edit}` (add, change or take away the edit `i`) finds the bricks that the old and the new edit reach (their bounds, grown by their blends), makes only those again with the tree of D3, and sends their new pieces of the surface to each watcher as they come (the events of World, `World.watch/1`). A new edit while the bricks of the last one are in work stops their processes (a message of priority) and starts again from the newest edits. | A user sees each change soon: the work is the bricks of the change, on each scheduler, and the newest edit wins. |
| D10 | **The euclidean distance, in plain Erlang.** No NIF (the node runs at the edge in WebAssembly too). Each function of the field takes and gives floats in tuples, with no maps in the hot path. A compiled form of the short list of a brick (a function made for it) comes only if the measure asks for it [P7]. | One code at the edge and on a server; the measure decides each change of speed. |

## 8. Requirements

- **R1.** `World.SDF` gives the distance of each shape: exact within
  1e-9 for the shapes with an exact distance, and a bound (never more
  than the true distance, and within 10% of it near the surface) for the
  others, at points inside, on and outside it; and the blend of D2 (the
  hard minimum when the distances are more than the blend apart).
- **R2.** For a sculpture of 100 edits with cells of 2 cm or less, the
  evaluations of an edit at a point are less than 5% of 100 edits at
  each point of the grid of its bounds, and the surface is the same as
  the surface of the full grid. (A brick has 11³ points for its 8³
  cells, so with larger cells its border costs more: 20% at 4 cm.)
- **R3.** The surface of a sculpture is closed (each edge of the mesh in
  as many faces one way as the other) and has its faces to the outside,
  with no gap at the faces of the bricks; a box of hard edits has its 12
  edges sharp (each face within 1° of a face of the box) and its volume
  within 0.1%. (Step 3: at a face of a cell whose inside corners are on
  its diagonal, two sheets of the surface touch at an edge in four
  faces; manifold dual contouring [P12] splits them later.)
- **R4.** On 4 schedulers, a sculpture of 1,000 edits takes less than
  half the time that it takes on 1 scheduler (`+S 1`), and a stop of its
  person ends each process of its tree in less than 100 ms.
- **R5.** When one edit of a sculpture of 1,000 edits changes, the bricks
  that are made again are only the bricks that it reaches, before or
  after the change; the others come from the cache.
- **R8.** A live sculpture of 1,000 edits takes a change of one edit and
  sends the new pieces of its surface in less than a tenth of the time of
  the whole sculpture; its surface after the change is the surface of a
  new build of the same edits; an edit that comes while the last one is
  in work stops that work.
- **R6.** A sculpture comes in a blueprint over MCP (`check_blueprint`,
  `build`), and each error has its path.
- **R7.** The model of step 6 comes from at most 200 edits, has the
  triangles of the budget of its level, and its shots stand next to the
  shots of today.

## 9. Steps

Each step is a small commit (or a few), with its tests, the quick checks
on each commit, and the full check on the tip before a push.

1. **`World.SDF`** (D1, D2, D10; R1): the shapes, the modes, the blend,
   their tests.
2. **The tree of cells** (D3, D5; R2, R4): the processes of the cells,
   their short lists, the bricks as binaries.
3. **The surface** (D7, D8; R3): dual contouring in each brick, the
   seams, the levels, the edge collapse.
4. **The sculptor and its crew, and the cache** (D4, D6; R4, R5): the
   task `sculpt`, the tree as the crew of the hand, the table of bricks.
5. **The live sculpture** (D11; R8): the process, its edits as
   messages, the bricks of a change, the stream of their pieces.
6. **The skill `sculpt` and its format** (D9; R6), `docs/format.md`, and
   the live sculpture over MCP (tools to open one, to send an edit, and
   to watch it).
7. **One model from edits** (R7): a model of the catalog made again,
   with its shots and the measure.

## 10. Acceptance criteria

- The tests of R1 to R6.
- The shots of step 6 next to the model of today, and the numbers of
  `mix world.bench`.
- The full check passes on the tip of each push.

## 11. Open questions

- **The model of step 7** (the owner, 2026-11-12): a simple animal. It
  is the carp (`priv/drawings/carp_edits.json`, section 13).
- **The memory of a sculpture at the edge.** The carp from edits needs
  202 MB to 374 MB at its peak, and the edge has 128 MB. The catalog
  keeps its files, so the edge sends them with no build; an order of a
  sculpture at near at the edge needs less memory first (the pieces as
  binaries in the tree, fewer points in the collapse).
- **The borders of the materials** follow the grid in steps, because
  each quad has one material. A color for each point, with a blend at
  the border, makes them smooth.
- **An animal from edits has no rig yet.** The carp from edits is a
  static model; the carp of the catalog has its bones and swims.
- **The manifold mesh.** Step 3 found the case: at a face of a cell
  whose inside corners are on its diagonal, two sheets of the surface
  touch at one edge (10 edges of a stone of 41 edits). The mesh stays
  closed. Manifold dual contouring [P12] splits them; it comes when a
  model needs it (a print of the model, a check of its edges).
- **The sizes of the cells** of D8: the measure of step 3 (section 13)
  keeps 2, 8 and 32 cm. A stone of 1.6 m has 58,304 faces at near, 3,424
  at mid and 156 at far, so each level is near the budget of an item
  before the collapse.
- **The collapse is one process.** It takes 2.4 s of the 6.1 s of the
  near stone to 40,000 faces. A collapse in each region of bricks, with
  the points at the borders of the regions kept, can use each scheduler;
  it comes when a model needs it.
- **A live sculpture** is a part of this plan (the owner, 2026-11-12):
  D11, R8, step 5.

## 12. Sources

Dreams:

- [E1] A. Evans, "Learning from Failure: a Survey of Promising,
  Unconventional and Mostly Abandoned Renderers for 'Dreams PS4'",
  SIGGRAPH 2015, Advances in Real-Time Rendering (slides with the notes
  of the speaker):
  https://advances.realtimerendering.com/s2015/AlexEvans_SIGGRAPH-2015-sml.pdf;
  the same talk at Umbra Ignite 2015:
  https://www.youtube.com/watch?v=u9KNtnCZDMI
- [E2] A. Evans on the renderer of Dreams, 2017 and 2020: "a mad
  hybrid" (cubes, then rays through the field, then strokes),
  https://twitter.com/mmalex/status/941755154772250624; hulls and fluff,
  quoted in full at
  https://www.resetera.com/threads/this-was-built-in-dreams-on-a-base-ps4-my-jaw-is-on-the-floor.177884/post-30413009
- [E3] S. Aaltonen on sparse tiles of 8³ (a payload of 7³), and A. Evans:
  "exactly" what Dreams used, 2021:
  https://twitter.com/SebAaltonen/status/1393112819181264896,
  https://twitter.com/mmalex/status/1393120228750594048
- [E4] "Dreams: Under the Hood with Alex Evans", Media Molecule, 2019:
  https://www.youtube.com/watch?v=1Gce4l5orts; a summary of episode 2:
  https://dreamskool.wordpress.com/2019/11/27/dreams-under-the-hood-2-with-alex-evans/
- [E5] The tools and the limits of Dreams:
  https://docs.indreams.me/en/create/resources/edit-mode-guide/sculpt/tools,
  https://tapgiles.com/docs/limits.html (a reference of the community)
- [E6] US11887245B2, "Techniques for rendering signed distance
  functions" (NVIDIA; Hansson Söderlund, Evans, Akenine-Möller):
  https://patents.google.com/patent/US11887245B2/en

Papers and references:

- [P1] I. Quilez, distance functions:
  https://iquilezles.org/articles/distfunctions/
- [P2] I. Quilez, smooth minimum: https://iquilezles.org/articles/smin/
- [P3] I. Quilez, the ellipsoid: https://iquilezles.org/articles/ellipsoids/
- [P4] J. C. Hart, "Sphere tracing: a geometric method for the
  antialiased ray tracing of implicit surfaces", The Visual Computer
  12(10), 1996.
- [P5] E. Galin, E. Guérin, A. Paris, A. Peytavie, "Segment Tracing
  Using Local Lipschitz Bounds", Computer Graphics Forum 39(2), 2020:
  https://hal.archives-ouvertes.fr/hal-02507361/
- [P6] T. Duff, "Interval arithmetic and recursive subdivision for
  implicit functions and constructive solid geometry", SIGGRAPH 1992.
- [P7] M. Keeter, "Massively Parallel Rendering of Complex Closed-Form
  Implicit Surfaces", ACM TOG 39(4), 2020:
  https://www.mattkeeter.com/research/mpr/keeter_mpr20.pdf
- [P8] W. Barbier et al., "Lipschitz Pruning: Hierarchical
  Simplification of Primitive-Based SDFs", Computer Graphics Forum
  44(2), 2025: https://diglib.eg.org/handle/10.1111/cgf70057
- [P9] S. Gibson, "Constrained Elastic Surface Nets", MICCAI 1998:
  https://www.merl.com/publications/docs/TR99-24.pdf
- [P10] T. Ju, F. Losasso, S. Schaefer, J. Warren, "Dual Contouring of
  Hermite Data", SIGGRAPH 2002:
  https://www.cs.wustl.edu/~taoju/research/dualContour.pdf
- [P11] I. Quilez, the bounds of a field:
  https://iquilezles.org/articles/sdfbounding/
- [P12] S. Schaefer, T. Ju, J. Warren, "Manifold Dual Contouring", IEEE
  TVCG 13(3), 2007:
  https://people.engr.tamu.edu/schaefer/research/dualsimp_tvcg.pdf
- [P13] P. Trettner, L. Kobbelt, "Fast and Robust QEF Minimization using
  Probabilistic Quadrics", Computer Graphics Forum 39(2), 2020:
  https://github.com/Philip-Trettner/probabilistic-quadrics
- [P14] N. Gildea, dual contouring of chunked terrain (seams), 2014:
  https://ngildea.blogspot.com/2014/09/dual-contouring-chunked-terrain.html
- [P15] E. Lengyel, Transvoxel (seams between levels), 2010:
  https://transvoxel.org
- [P16] M. Garland, P. Heckbert, "Surface Simplification Using Quadric
  Error Metrics", SIGGRAPH 1997.
- [P17] K. Museth, "VDB: High-Resolution Sparse Volumes with Dynamic
  Topology", ACM TOG 32(3), 2013:
  http://www.museth.org/Ken/Publications_files/Museth_TOG13.pdf

Open code to read: libfive and Fidget (M. Keeter), fogleman/sdf, hg_sdf
(Mercury), sdf-explorer (Takikawa, Glassner, McGuire, JCGT 2022).

## 13. The measure

### Step 2 (2026-11-12)

A stone of 100 edits (an ellipsoid with balls added and taken away on
its surface, blends of 3 cm), on a machine with 4 schedulers:

| Cells | Bricks | Evaluations, of the brute force | 4 schedulers | 1 scheduler (`+S 1`) | The tree, against one process (4 / 1 schedulers) |
|---|---|---|---|---|---|
| 4 cm | 120 | 20.3% | 1.4 s | 4.2 s | 8.8 / 2.0 times faster |
| 2 cm | 500 | 3.9% | 2.3 s | 7.2 s | 7.1 / 2.4 times faster |
| 1 cm | 2,164 | 0.94% | 5.1 s | 14.6 s | 8.0 / 2.9 times faster |

The tree is about 3 times faster on 4 schedulers than on 1 (R4). It is
also 2 to 3 times faster than one process on one scheduler: one process
keeps all the data on one heap, and its collection of garbage grows;
each small process of the tree has its own small heap, and gives it back
when it ends.

### Step 3 (2026-11-12)

The same stone of 100 edits, its meshes from `World.Sculpt.model/2` (the
piece of the surface of each brick in the process of the brick), on 4
schedulers:

| Level | Cells | Faces | Time | To a budget |
|---|---|---|---|---|
| near | 2 cm | 58,304 | 3.7 s | 40,000 faces in 6.1 s; 10,000 in 7.1 s |
| mid | 8 cm | 3,424 | 0.9 s | 3,000 faces in 1.0 s |
| far | 32 cm | 156 | 0.17 s | (under 300) |

At near the bricks take 1.8 s and their pieces 1.9 s more. Each cut of
an edge of the grid, and its normal, is found once in a brick (the
first version found it again for each cell round the edge, and took
6 s). The collapse to the budget is one process (section 11).

### Step 4: the cache (2026-11-12)

The first cache missed too often: after a move of one bump (a ball of
5 cm, 5 cm up) of the stone of 100 edits, 70 of 501 bricks at 2 cm (14%)
had a new short list. A brick kept each edit that changes the field at
one of its points, and far from the surface (0.4 m at a brick of 2 cm
with its border) the field is large, so many edits change it there, with
no change to the surface.

So the field of a sculpture has a limit (`World.SDF.field/3`,
`World.Sculpt.limit/2`: four cells and two of its largest blends): after
each edit, each value stays in the limit. Far from the surface each
value is the limit, so an edit there changes nothing, and the prune lets
it go, with no error (the prune of D3 is exact for this field). The
field stays a bound (Lipschitz 1). The tree tests the centers of the
eight parts of a brick, so it does not keep a brick at the limit.

| Cells | Bricks | Edits in a short list (mean) | Bricks made again after the move | Bricks (time) |
|---|---|---|---|---|
| 4 cm, no limit | 120 | 43.3 | 61 (51%) | |
| 2 cm, no limit | 501 | 14.7 | 70 (14%) | 1.8 s |
| 4 cm, limit | 110 | 33.0 | 30 (27%) | |
| 2 cm, limit | 452 | 13.9 | 48 (11%) | 1.3 s |

The bricks that are made again are all near the old or the new edit
(`test/world/sculpt_cache_test.exs`), and the other bricks come from the
cache with the same pieces (R5).

### Step 4: the crew (2026-11-12)

The tree of a sculpture runs in the hand of a sculptor: its processes
are linked to the hand, and a stop of the person (a message of
priority) ends each of them in less than 100 ms
(`test/world/sculpt_crew_test.exs`, R4).

A stone of 1,000 edits (the same ellipsoid of 1.6 m with 999 balls on
it, so the balls lie on each other), its meshes with no cache:

| Level | Faces | The tree, 4 schedulers | The tree, 1 scheduler (`+S 1`) | One process |
|---|---|---|---|---|
| mid | 5,508 | 9.9 s | 38.2 s | 38.9 s |
| near | 104,928 | 35.3 s | 152.1 s | 118.8 s |

On 4 schedulers the tree is 3.8 and 4.3 times faster than on 1 (R4).
The time is in the field: the short lists of this stone are long (many
balls near each brick), and each point of a brick takes each edit of
its list. A compiled form of a short list (D10) is the next step of
speed, when a model needs it.

### Step 5: the live sculpture (2026-11-12)

`World.Sculpt.Live` keeps the edits and the pieces of a sculpture. An
edit comes as a message of priority; a work makes the tree with the
cache; each brick that is made sends its piece at once; a new edit
stops the work and its crew (an exit signal) and starts again from the
newest edits.

The first measure of a change found three costs, and three changes:

- **The cache was full.** At 270 bytes for each face, the near level of
  the stone of 1,000 edits (105,000 faces) and its mid level were more
  than 32 MB, so the table was emptied and a change took 42.5 s. Now a
  piece is a binary in the table (68 bytes for each face), and the table
  has two generations: a trim takes away only the pieces that no build
  used since the last trim.
- **Each point took each edit of its brick.** Now each eighth of a brick
  has its own short list (a second prune, with the same values to the
  bit), for the field and for the search of the cuts.
- **The ball of a brick was too large.** Its points go one cell past its
  sides, so its ball is the ball of its box grown by one cell on each
  axis (it had two), and the limit of the field is two cells and two
  blends, at least four cells (it was four cells and two blends).

The stone of 1,000 edits, on 4 schedulers, with a move of one ball by
3 cm (three balls, one at a time):

| Level | The whole sculpture | A change | The first piece |
|---|---|---|---|
| near | 17.0 s (it was 35.3 s) | 1.7 to 1.9 s (10% to 11%) | 62 to 85 ms |
| mid | 4.6 s | 3.0 to 3.5 s (65% to 76%) | 2 to 3 ms |

At near a change is near a tenth of the whole sculpture (R8): 56 of 636
bricks (8.8%) are made again, and the walk of the tree over the bricks
of the cache takes 0.75 s. At mid a brick is 64 cm, so one edit reaches
most of the bricks: a live sculpture works at near, and the other levels
come when the edits stop. The next step of speed: a key for each cell of
the tree, so a change walks only the cells that it reaches.

The stone of 100 edits now: 452 bricks at 2 cm, 10 edits in a short
list, 33 to 37 bricks (7% to 8%) made again after a move of one ball,
and its meshes in 2.1 s at near, 0.35 s at mid and 0.12 s at far.

### Step 6: the skill and the tools (2026-11-12)

- The skill `sculpt` (`World.Skills.Sculpt`, the trade sculptor) takes
  the edits in a node of a drawing or of a blueprint in data
  (`docs/format.md`, "A sculpture"); `check_blueprint` and `check_order`
  give each error with its path
  (`options.drawing.nodes.0.skill.sculpt.edits.3.size`), R6.
- The MCP tools `open_sculpture`, `edit_sculpture` and `close_sculpture`
  open a live sculpture, change one edit at a time, and stop it.
  `GET /sculptures/ID/events` is the stream of its pieces (each piece
  with the mesh of each material, as JSON), and `GET /sculptures/ID.glb`
  the GLB of its surface now. The node has at most 8 live sculptures at
  one time.

### Step 7: one model from edits (2026-11-12)

The owner chose a simple animal: the carp. `priv/drawings/carp_edits.json`
is a drawing of one node of the skill `sculpt`: 21 edits (an ellipsoid
for the body, the head, the snout and the stalk of the tail; a paint for
the dark back and one for the pale belly; the mouth and two grooves of
the gills taken away; the eyes; the dorsal, the tail, the pectoral, the
pelvic and the anal fins as thin ellipsoids), with the sizes of the carp
of the catalog and the colors of its species file. Its triangles are the
budget of each level (R7):

| Level | Cells | The carp of the catalog | The carp from edits | Its build (fast clock), peak of memory, cores |
|---|---|---|---|---|
| near | 2 mm | 19,056 | 20,000 | 6.6 s, 374 MB, 2.13 |
| mid | 3.5 mm | 3,176 | 3,000 | 3.1 s, 223 MB, 1.82 |
| far | 4 mm | 3,176 | 600 | 2.4 s, 202 MB, 1.93 |

The carp of the catalog builds in 0.15 s to 0.6 s: its mesh is a file.
The carp from edits lies on its belly: its fins are over the lowest
point of the belly, so it stands (`World.Check.model/1`).
The shots of the two carps at each level, next to each other, went to
the owner.

The carp found six changes:

- **The size of the cells of a sculpture** (`cells` in its data): the
  cells of the levels (2, 8 and 32 cm) are for a model of some meters;
  a carp of 50 cm with fins of 7 mm needs cells of a few millimeters. A
  part thinner than about two cells breaks into pieces.
- **The axes of an edit:** with no `axis` and no `up`, an edit has the
  axes of the sculpture (a port has a free y), so the long side of an
  ellipsoid stays on y.
- **No small pieces:** a piece of the surface less than two cells
  across goes (the pieces of a fin that the cells break).
- **A border of two materials collapses along its line:** each point of
  a border stayed, so the far level had 380 faces for a budget of 300.
  Now an edge of a border collapses, the planes of the border keep its
  line, and a point where three materials meet stays.
- **A collapse in each region** of 8 × 8 × 8 bricks, in a process of
  its own, to twice its share of the budget, with the points that it
  shares with the other regions fixed; then the whole mesh, with the
  quadrics of the first pass. The near carp: 3.8 s, not 8.1 s, with the
  same volume (2,121 cm³ of 2,123). Two faults came out on the way: a
  collapse kept the other point of an edge at the place of a fixed point
  (the place stayed, the index did not, so the regions did not join),
  and a tetrahedron became two faces on the same three points.
- **At most two processes for each scheduler in each cell of the
  tree:** the peak of the bricks of the near carp went from 273 MB to
  187 MB, in the same time.

### Faster: the cells of the budget, and the cache of the meshes (2026-11-12)

The owner asked if 6.6 s for the near carp is the best that World can
do. It was not: the near carp made 95,408 faces with cells of 2 mm, and
the collapse took 80% of them away. The time of the near carp went to
the bricks (2.7 s), the mesh (0.8 s), the collapse (3.9 s) and the GLB
(0.45 s). Two changes:

- **The cells fit the budget** (`World.Sculpt.fit/2`): with a budget and
  no `cells`, the largest cells that give about 1.5 times the budget
  before the collapse, but at most half the thinnest edit (two cells
  across a fin of 7 mm: 3.5 mm), and at least an eighth of the cells of
  the budget. The carp has no `cells` now: each level has cells of
  3.5 mm, so the three levels share their bricks in the cache.
- **The meshes in the cache**, by a hash of the edits, the cells and the
  budget: a second build of the same edits takes no time for its model.

| The near carp | Cold | A second build |
|---|---|---|
| Before (cells of 2 mm) | 6.6 s (the bench), 7.5 s for the model and its GLB | the same, less the bricks |
| Now (cells of 3.5 mm) | 4.0 s (the bench), 3.1 s for the model and 0.49 s for its GLB | 3 ms for the model, 0.41 s for its GLB |

The volume stays (2,119 cm³ of 2,123). The build of the three levels of
the carp (`mix world.build carp_edits`) takes 17.7 s, not about 30 s. A
cold mid or far takes 4.2 s and 4.4 s now (the bench, in a fresh node):
each collapses 31,016 faces in one pass. The next steps: a faster
collapse (it is half of the time, and its last pass is one process) and
a compiled form of the short lists (D10).

Then the two next steps:

- **A compiled form of each edit** (D10): the frame from the axes of the
  sculpture to the axes of an edit is a tuple of numbers (a move only,
  or a turn and a move), and the ball, the capsule and the ellipsoid
  take numbers, not vectors. An ellipsoid at a point took 521 ns, and
  takes 123 ns; ten edits, 5.2 µs and 1.7 µs. The field of the bricks of
  the near carp takes 0.54 s, not 0.94 s.
- **A faster collapse:** the plane of each face is made once (not once
  for each of its points), one map gives the faces of each edge, and
  the heap is made from a list in one step: the start of the collapse
  of 31,024 faces takes 0.68 s, not 0.85 s. Each region goes to 1.1
  times its share of the budget, or to a quarter of its faces (the more
  of the two), so the last pass has little to do, also at mid and far.
  The collapse of the carp: 1.07 s at near (it was 1.75 s), 1.10 s at mid
  (2.45 s) and 1.18 s at far (2.61 s), with the same volume.

| The carp from edits (the bench, a fresh node) | At the start | Cells of the budget, and the cache | Now |
|---|---|---|---|
| near | 6.6 s | 4.0 s | 3.3 s |
| mid | 3.1 s | 4.2 s | 2.7 s |
| far | 2.4 s | 4.4 s | 2.5 s |
| The three levels (`mix world.build carp_edits`) | about 30 s | 17.7 s | 7.7 s |
| A second build of the same edits, near | | 3 ms and its GLB (0.41 s) | 3 ms and its GLB (0.43 s) |

Now the GLB of the near level (0.43 s, one process: the normals of the
faces and the scene) is the most of a second build, and of a cold build
the bricks (1.0 s), the mesh (0.6 s) and the collapse (1.1 s).

