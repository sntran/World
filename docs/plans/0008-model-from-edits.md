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
- **R2.** For a sculpture of 100 edits, the evaluations of an edit at a
  cell are less than 5% of 100 edits at each cell of the grid of its
  bounds, and the surface is the same as the surface of the full grid.
- **R3.** The surface of a sculpture is closed and has its faces to the
  outside (`World.Check.model/1`), with no gap at the faces of the
  bricks; a box of hard edits has its 12 edges sharp (the angle of its
  faces within 1° of 90°).
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

- **The model of step 6.** A simple animal (its body is a field today,
  `World.Blob`), the rubble of the take-down of plan 0006, or another
  one?
- **The manifold mesh.** Dual contouring can give a vertex shared by two
  sheets of the surface (a thin wall). Manifold dual contouring [P12]
  splits it; is it needed in step 3, or later when a model needs it?
- **The sizes of the cells** of D8 are an estimate: the measure of step
  3 sets them.
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
