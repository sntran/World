# Plan 0010: The detail of a sculpture in maps, in parts, and at once

Status: In progress (the owner, 2026-11-13: "You make decisions and
proceed all the way to achieve that level of Sony Dreams!").

Depends on: plan 0009 (a sculpture with a fine finish, a rich
vocabulary, and motion).

## 1. Goal

At the end, the detail of a model from edits does not depend on the size
of its cells or on the count of its triangles:

- **The maps have the detail.** A sculpture of few triangles has a color
  map and a normal map, made from the field of its edits at each texel:
  a scale of a fish, a ray of a fin and the border of a pupil are as
  sharp as the texels, at each level of detail.
- **A small part has small cells.** A sculpture can have details:
  sculptures of their own, with their own cells, on the same bones.
- **A change shows at once.** A live sculpture gives a coarse piece of a
  change first, then the fine piece.
- **More bodies move.** A sculpture with the bones of another body plan
  has its clips.

## 2. What the owner asked

The message of the status line, after the report of plan 0009. That
report named the limits: cells of one size, one body plan with clips,
and R5 of plan 0009. The builder decides the order and each decision
here; the owner can change each one.

## 2a. What a user of Dreams has (the owner, 2026-11-13: "If not clear, do research on Sony Dreams in details to know what the expectations are.")

Plan 0008, section 3, has the engine of Dreams (the list of edits, the
evaluator, the renderers). This section has what a user of the sculpt
mode, the coat mode and the puppets has, from the guide of Media
Molecule and the reference of the community (sources [U1] to [U7] at
the end of the section), next to World on 2026-11-13.

| Dreams | World | Gap |
|---|---|---|
| **A sculpture is an ordered list of edits**; each edit changes only what the edits before it made [U1]. | The same (`World.SDF`). | None. |
| **Shapes:** cube, cylinder, sphere, cone, donut, filled donut, wedge, hexagon, pyramid, rounded cube, curve (with a taper and a thickness along it); most shapes stretch on each side [U2]. | ball, box, round box, capsule, cylinder, cone, ring, ellipsoid, superellipsoid, tube. | **A wedge, a prism of n sides, a pyramid** (step 5). |
| **Modes:** add, subtract, **crop** (only what is inside the shape stays), spraypaint (a color, with an opacity), looseness, **cutout** (the shape becomes a new sculpture) [U1][U3]. | add, subtract, paint (a color, and a raise since step 2). | **Crop, and an opacity for a paint** (step 5). A cutout is two lists of edits: a tool of a client can make them. |
| **Blend:** soft (a smooth joint) or **hard (a flat slope between the two surfaces)**, with an amount [U1][U3]. | The soft blend. | **The hard blend** (a chamfer; step 5). |
| **Each edit can move, turn, stretch, go, and be cloned**; many clones along a line or a spiral; the guides mirror and kaleidoscope [U1][U3]. | A live sculpture changes one edit at a time; `mirror`, `repeat` (a ring, a row, a spiral), `groups`. | None for the data. |
| **Color and finish:** a color for each edit; a finish (default, plastic, shiny, rough, metal, wax, and their pairs) for a sculpture, for a stroke, or put on with a brush in the coat mode; tint, hue and **glow** with a brush [U4][U5]. | A color for each edit with soft borders; a material (a role of the palette) for each edit, with a border that follows the cells. | **A finish and a glow for each edit, with soft borders, in the maps** (step 4). |
| **Detail:** each sculpture has its own detail; looseness makes a part of it coarser; the cost of a sculpture is its surface times its detail (the thermometer) [U1][U6]. | Cells for each sculpture and level; details with their own cells (step 3); the maps have the fine detail (steps 1 and 2). | None in kind. Dreams has no maps: its strokes are the detail. |
| **Style** (flecks, looseness, impasto, ruffle): the painted look of the renderer [U3]. | Not in a GLB. | Out of scope (a renderer). |
| **Speed of the evaluator:** 10 to 100 million cells in a second on a PS4 (a GPU); 8,274 edits make 5.2 million cells in 0.09 s; a smear adds a shape 60 times in a second [E1 of plan 0008][U1]. Dreams makes one sculpture at a time, and no sculpture changes while a game plays [U7]. | About 0.2 million points of the field in a second on 4 schedulers (a stone of 1,000 edits: 846,000 points of 636 bricks in 4.4 s). A change of one edit: 0.4 s to 0.5 s. | **A factor of 50 to 500, and it stays:** the field of World is Elixir on a CPU, with no code for a GPU (section 4). World gets its speed from what it does not make again: the cache of the bricks and of the cells, a change that walks only what it reaches, and maps that are baked one time. |
| **Puppets:** a figure of sculptures on bones (each sculpture on its bone, joints between them); a walk, a run and a jump that the puppet makes itself; keyframes and recordings on top [U7][U8]. | A sculpture with bones: a skinned mesh, each point on the bones of the edit of its surface (step 3); the body plans of a fish and of a bird; clips from keys. | **A body plan on two legs with its walk** (step 6). A recording of a hand is a tool of a client. |

- [U1] The reference of the community for the sculpt mode:
  https://tapgiles.com/docs/modes/sculpt.html
- [U2] The shapes: https://docs.indreams.me/en/create/resources/edit-mode-guide/sculpt/shapes
- [U3] The tools of the sculpt mode and of the style mode:
  https://docs.indreams.me/en/create/resources/edit-mode-guide/sculpt/tools,
  https://docs.indreams.me/en/create/resources/edit-mode-guide/style/tools
- [U4] The finishes: https://docs.indreams.me/en/create/resources/edit-mode-guide/sculpt/finishes
- [U5] The tools of the coat mode: https://docs.indreams.me/en/create/resources/edit-mode-guide/coat/tools
- [U6] The limits: https://tapgiles.com/docs/limits.html
- [U7] "Dreams Under the Hood #2 with Alex Evans", a summary:
  https://dreamskool.wordpress.com/2019/11/27/dreams-under-the-hood-2-with-alex-evans/
- [U8] The puppets, from the forum of Dreams:
  https://forums.indreams.me/hc/de/community/posts/360014021558-Creating-a-fully-custom-puppet

## 3. The state before this plan

- The color of a sculpture is the color of each point of its mesh, and
  its normal is the normal of each point. A detail smaller than about
  three cells is not in the model: the pupil of the carp needs cells of
  2.5 mm, and the near level needs 30,000 triangles for its scales.
- At mid and far a pattern of colors is its mean color.
- A sculpture has cells of one size.
- A change of one edit of a live sculpture of 1,000 edits shows its
  first new piece after 0.10 s to 0.18 s, and its last after 0.41 s to
  0.53 s.
- Only the body plan of a fish gives clips to a sculpture.

## 4. Out of scope

- A renderer, and a tool with a screen to sculpt by hand (plan 0009).
- Code that is not Elixir or Erlang for the field (a NIF, a GPU).

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **Maps from the field.** With `bake` in its data (the side of the image at a level, in texels), a sculpture has a color map and a normal map. Each texel is a place on a triangle of the mesh; its color is the color of the edits there, and its normal comes from the gradient of the field there. The mesh has no color for each point then. | This is how a model of a game gets its detail: a fine surface is baked on a mesh of few triangles. World has the fine surface as a function, so the bake needs no fine mesh. Dreams draws its field as points; a GLB for any app needs maps. |
| D2 | **A chart for each triangle.** Each triangle has its own right triangle of texels, two in a square, with a border of one texel that has the values of the field past the edge. The size of a square follows the area of its triangle. The squares go into the image in rows, the largest first. The sampler of the image has no smaller copies (no mipmaps): a level of detail has its own image. | A chart for each triangle needs no cut of the mesh into flat pieces, and has no stretch that the user must repair. The border keeps a texel of one chart out of the next one. |
| D3 | **The gradient at a texel from its neighbors.** The texels of a chart are on the plane of its triangle. The change of the field from a texel to the next gives the gradient in the plane, and one more value off the plane gives the rest. The edits of a triangle are the edits of its brick that reach its ball. | Two values of the field for each texel, each with a short list: the bake of an image of 512 texels must take about one second. |
| D4 | **The normal map is in the tangent space of glTF**, with the tangents that `World.GLB` gives to a primitive with a normal map. The bake uses the same rule for the tangent of each corner. | A skinned mesh turns its tangents with its bones; each app reads the same map. |
| D5 | **Details** (`details` in the data of the skill): each one is a sculpture of its own (its edits, its cells, its budget, a mirror), built with its own tree, and its meshes are in the same part or figure. | Dreams makes a figure from many sculptures, each with its own detail. A barbel of 3 mm needs cells of 1 mm only in its own small box. |
| D6 | **A live sculpture gives a coarse piece first.** A change walks the tree at cells of 4 times the size first (1/16 of the work), sends those pieces with their level, then the fine pieces. | The eye needs an answer in less than 0.1 s; the fine surface can come later. |
| D8 | **A paint with a raise** (added in step 2): an edit of the mode `paint` can move the surface out or in by a height in its shape, with a slope across its border. With maps, a raise of less than half a cell is in the maps only: the mesh is made from the edits with no such raise. | The carp needs scales, rays and grooves that follow its surface. A shape that adds does not follow a surface; a paint already has its place on any surface. The relief that a mesh cannot show makes its points uneven, so it stays out of the mesh. |
| D9 | **A point follows the bones of the edit of its surface** (added in step 3): the bones with a part of their line inside the shape of that edit; across a smooth joint of two edits, a part of each. | In Dreams each sculpture of a puppet is on its bone. With weights from the distance only, the back of a bird followed its wings. |
| D10 | **A finish and a glow for each edit** (after the research, section 2a): `roughness`, `metal` and `glow` of an edit, folded as its color is, and baked into the maps (the metal and roughness map and the emissive map of glTF). | The coat mode of Dreams puts a finish and a glow on a part of a sculpture with a soft border. A material for each quad cannot do that. |
| D11 | **Crop, the hard blend, an opacity for a paint, and three shapes** (after the research): the mode `crop`, `blend_type: hard` (a flat slope), `opacity` of a paint, and the shapes `wedge`, `prism` and `pyramid`. | The words of the sculpt mode of Dreams that World does not have. |
| D12 | **A body plan on two legs** (after the research) for a sculpture with the bones of a person of World: its walk and its other clips. | The puppet of Dreams walks by itself. World has the walk of a person; a sculpture can take it. |
| D13 | **The hot loop of the field with no boxes** (after the research): the short list of a cell becomes a list of tuples of numbers, one for each edit, and the fold is one function with a clause for each kind of edit, with guards that tell the JIT that each number is a float. The JIT of OTP then keeps the numbers of a clause in registers. A paint with no raise is not in the list of the value. The values are the same to the bit. | The speed of the evaluator is the largest gap to Dreams (section 2a). A measure on 2026-11-13: a list of 39 balls takes 150 ns for each edit in the fold of today and 44 ns in such a loop (3.4 times faster). |
| D7 | **The body plan of a bird** for a sculpture with bones, with its clips (`walk`, `idle`, `peck`, `flap`): its animations need no clips of a template. | A second body plan proves that the bones of a sculpture are general. |

## 6. Requirements

- **R1.** The color of a baked sculpture at a place of its surface (the
  texel of its image there) is the color of the edits at that place,
  within 8 of 255, where the color changes over more than one texel; a
  sharp border of two colors is at most one texel wide.
- **R2.** The normal of a baked ball of 200 triangles, from its normal
  map and its tangents, is within 2 degrees of the normal of the ball at
  each texel of a chart. A relief smaller than a triangle (a bump of
  1/10 of a cell) is in the normal map.
- **R3.** The charts of two triangles share no texel; the values of a
  chart go one texel past its edges.
- **R4.** The bake of an image of 512 texels for the carp at mid takes
  less than 1.5 s, and of 1,024 texels at near less than 5 s (4
  schedulers).
- **R5.** The GLB of a baked sculpture, with bones or with none, passes
  the validator of glTF; its materials have the two maps.
- **R6.** A detail with cells of 1 mm on a sculpture with cells of
  2.5 mm adds less than 0.5 s to the build of the carp.
- **R7.** A change of one edit of a live sculpture of 1,000 edits shows
  its first coarse piece in less than 60 ms.
- **R8.** A sculpture with the bones of a bird has its four clips, and
  its `flap` moves its wings.
- **R10.** A sculpture of one material with a part of metal, a part of
  wax and a part that glows has those in its maps, with soft borders
  where the edits have a blend; the GLB passes the validator.
- **R11.** The mode `crop` keeps only what is inside its shape; a hard
  blend of two boxes has a flat slope between them; a paint with an
  opacity of a half gives the mean of the two colors; each new shape has
  a distance with a slope of at most 1.
- **R12.** A sculpture with the bones of a person has the walk of a
  person of World, and its feet move in turn.
- **R13.** The stone of 1,000 edits at near takes less than 3 s (it
  takes 4.4 s), and a change of one edit less than 0.35 s (it takes
  0.41 s to 0.53 s), with the same bricks to the bit.
- **R9.** The carp of the catalog shows the maps and a detail, with
  shots at each level next to the carp of plan 0009, and its times.

## 7. Steps

The steps changed on 2026-11-13, after the research of section 2a.

1. **The maps** (D1 to D4; R1 to R5): `World.Sculpt.Bake`, the UVs of a
   mesh, the sampler, the data `bake` of the skill. Done.
2. **A paint with a raise, and the carp with maps** (D8; R9, first
   part). Done.
3. **Details, the body plan of a bird, and the bones of an edit** (D5,
   D7, D9; R6, R8).
4. **A finish and a glow for each edit** (D10; R10).
5. **Crop, the hard blend, the opacity, three shapes** (D11; R11).
6. **A body plan on two legs** (D12; R12).
7. **The hot loop of the field** (D13; R13), and **the coarse piece
   first** (D6; R7): a measure first; the coarse piece goes on only when
   the measure allows R7.
8. **The measure and the documents** (R9).

## 8. Acceptance criteria

- The tests of R1 to R8.
- The shots and the times of R9.
- The full check passes on the tip of each push.

## 9. Open questions

- **R5 of plan 0009** (a change in less than 7% of the whole): the field
  of each eighth of a brick in the cache. It is not in this plan; D6
  gives the answer that the eye needs.
- **A map of the roughness** (an edit with its own roughness).

## 10. The measure

### Step 1: the maps (2026-11-13)

`World.Sculpt.Bake` makes the two maps; the data `bake` of the skill
`sculpt` gives the side of the image at each level
(`docs/format.md`, "The maps of a sculpture"). The carp of plan 0009
with maps, on 4 schedulers:

| Level | Triangles | Image | The bake | The whole level |
|---|---|---|---|---|
| near | 10,000 | 1,024 | 3.9 s | 6.0 s |
| mid | 3,000 | 512 | 1.2 s | 3.3 s |
| far | 600 | 256 | (not measured alone) | 2.4 s |

At mid, 247,000 of the 262,000 texels of the image are in a chart (94%).
R4 is met (1.2 s at 512, 3.9 s at 1,024). The mid level and the far
level now show the scales and the pupil of the carp, which only the
near level of 30,000 triangles showed before; the shots are in step 2.

The tests of R1, R2, R3 and R5 are in
`test/world/sculpt_bake_test.exs`: the color of each texel is the color
of the edits at its place (within 1 of 255), a sharp border has no
mixed texel, the normal of a ball of 200 triangles from its map and
its tangents is within 2 degrees of the true normal at each texel
(0.3 degrees inside the triangles), a bump of a fifth of a cell is in
the map, no texel is in two charts, and the GLB has the maps with the
sampler and the tangents.

What the work found:

- **A message is a copy, again.** The first bake of 512 texels took
  5.8 s: each process got the lists of the edits of all the triangles.
  With the lists of its own squares only: 1.7 s.
- **The ball of a chart must be its true ball.** A wide ball for each
  triangle gave long lists to the large triangles, which have the most
  texels. With the ball of the texels of the chart: 1.1 s.
- **The texels at the edge of a chart need the value past the edge.**
  A change from one side only gave normals with an error of 4 degrees
  at the edges of the triangles, where two charts meet. Now the bake
  takes the value at the place past the edge: 1.2 s, and 2 degrees at
  the most at each texel.
- **A mesh has UVs now** (`World.Mesh.map/2`): the UV of each corner of
  each face, through `World.Build` and `World.Scene` to the GLB. The
  maps of a node go to the materials of the model as the data
  `materials` of its skill (`World.Drawing.assemble/3`).

### Step 2: a paint with a raise, and the carp with maps (2026-11-13)

The carp of the catalog (`priv/drawings/carp_edits.json`) has 30 edits
in its data now. Its scales, the rays of its tail fin, of its dorsal fin
and of its anal fin, its lateral line and its nostrils are paints with
a raise of 0.5 mm to 1.5 mm (D8), and it has maps at each level. The
carp of plan 0009 and this one, on the bench (the fast clock, 4
schedulers):

| | Plan 0009 | Now |
|---|---|---|
| Triangles: near, mid, far | 30,000, 3,000, 600 | 10,000, 3,000, 600 |
| Cells at near | 2.5 mm | 3.5 mm |
| The detail of the colors and of the relief | a point of the mesh (2.5 mm at near; a mean color at mid and far) | a texel: about 0.5 mm at near, 1 mm at mid, 2 mm at far (from the area of the carp and the texels in its charts) |
| The build: near, mid, far | 3.9 s, 2.6 s, 2.0 s | 6.8 s, 3.9 s, 2.8 s |
| The peak of the memory of the node: near, mid, far | 187 MB, 139 MB, 135 MB | 223 MB, 139 MB, 140 MB |
| The files: near, mid, far | 1.09 MB, 0.12 MB, 0.04 MB | 4.33 MB, 1.35 MB, 0.35 MB |

The shots went to the owner: the mid level and the far level have the
scales, the rays and the round pupil of the near level. The price is the
time of the bake (about 1 s for each 250,000 texels) and the size of the
files (two PNG images, and three points for each triangle: a chart for
each triangle has its own UVs).

What the work found:

- **A relief smaller than the cells made the outline rough:** the points
  of the mesh went onto the ridges and the valleys of the rays at
  random. With maps, the mesh is made from the edits with no raise of
  less than half a cell (`World.SDF.coarse/2`), and the maps have the
  relief from all the edits.
- **The field with a relief is not a bound of the distance:** a raise
  moves the value by its height at the most. The ranges of a cell take
  that (the least value less the raise), and the tests of the tree for
  "no surface" take twice the relief more. A test checks each brick that
  the tree left out, for a ball with bumps and dents higher than its
  cells.
- **The memory of the bake: a message is a copy, a third time.** The
  first bench of the near level showed a peak of 413 MB: each triangle
  got its own copies of its edits back from the processes that find the
  lists (10,000 lists of 13 edits). The lists are places in the list of
  the edits now, and a process gets the edits of its squares one time:
  the bake adds 75 MB at near, not 310 MB, and is 15% faster.

### Step 3: details, the body plan of a bird, and the bones of an edit (2026-11-13)

**Details** (D5). The data `details` of the skill `sculpt`: each detail
is a sculpture of its own (its edits, its cells, its budget, its
levels), in the same part, on the same bones and in the same maps
(`World.Sculpt.Bake.maps/2` takes the meshes of some sculptures, each
with its own edits). The carp has its two pairs of barbels as a detail
at near and at mid: tubes of 1.2 mm to 3.2 mm, with cells of 0.6 mm (the
carp has cells of 3.5 mm), 800 triangles at near. R6 is met: the
sculpture of the barbels alone (4 edits, 44 bricks) takes 0.14 s to
0.17 s.

**The body plan of a bird** (D7). A sculpture with the 20 bones of a
bird has `walk`, `idle`, `peck` and `flap` (R8, by test: the tips of the
two wings go out by more than 5 cm, each on its side, and the feet move
in the walk).

**The bones of an edit** (D9). The first bird showed the limit of
weights from the distance only: the back of its body followed its wings
by 6 cm. Now a point follows the bones that have a part of their line
inside the edit of its surface (`World.SDF.shares/2` gives the part of
each edit in the surface at a point, as the fold of the colors does).
In the test the body moves less than 1 cm in the flap.

What the work found:

- **The flap of the birds of the catalog opened one wing.** The skeleton
  turns the right side the other way for a turn to the side, and the
  flap turned the sign a second time. And the template of the birds has
  its left wing at +x (the left side of World is at -x). The flap takes
  the direction from the place of the left wing at rest now; the chicken
  and the duck have new files, and a test checks the two wings.
- **The color past the edge of a long thin triangle was white:** a
  texel there can be farther from each shape than the limit of the
  field. The weights of the colors come from the value with no limit
  now.
- **A message is a copy, a fourth time.** The first bench with the new
  weights showed a peak of 1,360 MB at near: each point went to its
  process with the edits of its mesh. A process gets the edits one time
  for its group of points now: 226 MB.
