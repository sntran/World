# Plan 0020: The look of a town: a tint for each copy, a finish at each point, and the surfaces of made things

Status: Approved (2026-11-22).

Depends on: plan 0010 (the maps of a sculpture: color, normal, finish,
glow), plan 0012 (occlusion, dirt, wear, and a surface for each edit),
plan 0019 (World serves the projects), and the fill of the empty texels
of the maps (issue #43, which comes before step 4).

## 1. Goal

A project can make a whole town, a port or a forest from few parts, and
draw it in few draw calls, with the look of real made things:

- each copy of a part has its own tint and its own scale (issue #45);
- a level with no image has its occlusion and its finish at each point
  (issue #46);
- the faces of a building or a vehicle can have windows, panels, or
  corrugated sheets with one surface, not with thousands of paints
  (issue #48);
- the images of a set of models are in one atlas, and can be in a GPU
  format (issue #47).

## 2. Why this order

Vũng Tàu needs #45, #46 and #48 for the houses of its whole town (its
plan 0009, phase 3): corrugated roofs, rolling shutters, windows, and a
color for each house. So they come first. #47 comes last: an atlas of
many models has more borders between charts, so it needs the fill of
#43 first, and Humans Must Die is the only project that asks for it now.

Issue #44 (the far level of `mini`) waits: Humans Must Die does not use
`mini`.

## 3. Out of scope

- A shader for a project. World writes data (attributes, extras,
  images); the project draws it.
- A change to the keys of the parts that this plan does not change: a
  tint and a scale of a copy are data of the node, not of the part, so
  the part keeps its key and its file (D2).
- The far level of `mini` (#44).

## 4. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | A node of a drawing takes `tint` (`#rrggbb`) and `scale` (a number from 0.1 to 10, the same on each axis). The tint multiplies the color of the part. | The two keys of a clone of Dreams. A scale on one axis only would change the normals and the thickness of the walls: a new part is the correct tool for that. |
| D2 | The tint and the scale go in the node, not in the part. A part with copies of other tints is one mesh and one key. | One house is a whole street of colors, with one file and one recipe. |
| D3 | In the GLB, a copy has its `scale` and `extras.tint`. A node with `EXT_mesh_gpu_instancing` has `SCALE` and `_COLOR_0` (the tint of each copy). The parts list (`elements.json`) has `tint` and `scale` next to `matrix` (the matrix has the scale in it too). | The forms that three.js and Godot read, and the same data for a project that puts the parts together itself. |
| D4 | The rule of the copies goes in `docs/format.md` ("GLB", "The copies"): a mesh of 100 triangles or more, or 16 copies or more in one node, is shared. A node takes `share: true` to share its copies always. A copy with a tint or a scale is always shared. | A copy with its own tint cannot be in a merged primitive. An app that draws instances wants the copies; an app that draws each node alone wants the merge. |
| D5 | A level with a `budget` and no `bake`, with the look `real`, has the occlusion (with `dirt` and `wear`) at each point. The option `occlusion` of the sculpture chooses where: `alpha` (the alpha of `COLOR_0`, the default) or `color` (multiplied into `COLOR_0`). | The alpha keeps the color true, and a project that does not read it loses nothing. `color` is for a project with no shader of its own. |
| D6 | The same level has `_FINISH` (`VEC3`: the roughness, the metal and the glow at each point, from 0 to 1). | One attribute for all three, as the finish image has them in its channels (plan 0010, step 4). |
| D7 | The cut to the budget keeps the points where the finish or the glow changes, as it keeps the points where the color changes (`World.Sculpt.Finish`). | Else a pane of glass or a lit window melts into the wall. |
| D8 | Three new kinds of surface (`World.Sculpt.Texture`): `windows`, `panels` and `corrugated`. Each is a pattern in the axes of the edit, with its scale. A rule in code (a house of `World.Town.House`) gets the same patterns as a texture of a role (`World.Textures`): `roof_corrugated`, `metal_shutter`, and the glass of the windows. | One pattern for the edits and for the rules, so a house of Vũng Tàu and a building of Humans Must Die look the same. |
| D9 | `windows`: the width and the height of a pane, the width of the frame, `lit` (a share of the panes, from 0 to 1, chosen by a hash of the row, the column and a `seed`), and a warm and a cold color of the light. A pane has the finish of glass (roughness 0.05, metal 0), the frame has the color of the edit, and the pane is 2 cm in from the frame (in the normal map, and in the relief). The light of a pane goes into the glow. | The data of issue #48. A hash of the row and the column gives the same panes each time, so a key does not change. The light in the glow lets a game turn it off with one multiply. |
| D10 | `panels`: plates of a width and a height, with seams of a width and a depth, and `rivets` (a step, or none). `corrugated`: ribs along z of the edit, with a profile, a pitch and a depth. The profile is `round` (a sine) or `square` (flat tops with sloped sides, and the width of the top). Most metal roofs in Việt Nam have square ribs: the common sheets have 5, 9 or 11 ribs on a useful width of 1 070 mm, with a pitch of 250, 125 or 100 mm and a depth of 32, 21 or about 19 mm (https://www.tonthephoangphuc.com/cac-loai-song-ton-pho-bien, status Source). The round ribs of 76 mm and 18 mm stay as an example; a rolling shutter has ribs across, with a pitch of 80 mm. Vũng Tàu gives the profile, the pitch and the depth of each roof from its photos. | The surfaces of a hull, a wing, a tank, a container, a roof and a shutter. |
| D11 | At a level with a bake, a surface goes into the maps (color, normal, finish, glow). At a level with no bake, a surface gives its mean color, finish and glow to the points (D5 and D6); a pane that is larger than about two cells of the level keeps its own points. | A far house of 30 pixels shows lit windows as points of glow; a near house shows each pane. |
| D12 | `POST /sets` takes `atlas: true`: World puts the charts of the parts of all the models of the set into one color image, one normal image, one finish image, and one glow image. The answer gives the images one time, and each GLB refers to them (a URL of the set), with no image of its own. | One material for a batch (a `BatchedMesh` of three.js, a `MultiMesh` of Godot). |
| D13 | An order can take `atlas: true` for its own parts (one set of images for each model, not for each role). | The container ship of Humans Must Die is then one draw call for its body. |
| D14 | The option `images: "ktx2"` of an order or a set writes the images as KTX2 with Basis (`KHR_texture_basisu`). The default stays PNG. | A GPU format keeps the images packed on a phone, 4 to 6 times smaller. WebP only makes the file smaller. |

## 5. Requirements

### Step 1: a tint and a scale for each copy (#45)

- **R1.** `World.Drawing` checks `tint` (`#rrggbb`) and `scale` (0.1 to
  10) of a node, and of a node in a `repeat`, with the path of each error.
- **R2.** `World.Build` writes the scale of a copy in its node, and the
  tint in `extras.tint`. A shared mesh with instances has `SCALE` and
  `_COLOR_0` for each instance.
- **R3.** `World.Elements` writes `tint` and `scale` for each part of a
  copy in the parts list. The key of the part does not change.
- **R4.** `share: true` of a node shares its copies. A copy with a tint or
  a scale is always shared.
- **R5.** `docs/format.md` ("GLB", "The copies") says the rule of 100
  triangles and of 16 copies, `share`, `tint` and `scale`.

### Step 2: the occlusion and the finish at each point (#46)

- **R6.** At a level with a `budget` and no `bake`, with the look `real`,
  the GLB has the occlusion at each point (D5) and `_FINISH` (D6).
- **R7.** The cut to the budget keeps the borders of the finish and of
  the glow (D7).
- **R8.** The flat look (`/o/HASH.flat.glb`) keeps its form: it has no
  `_FINISH`.
- **R9.** `docs/format.md` says the two attributes, and the option
  `occlusion`.

### Step 3: the surfaces windows, panels and corrugated (#48)

- **R10.** The three kinds of `World.Sculpt.Texture`, with their data
  (D9, D10) and the check of each value with its path.
- **R11.** The same patterns as textures of the roles of a rule in code
  (`World.Textures`): the corrugated sheet of a roof and the ribs of a
  rolling shutter of `World.Town.House`, and the panes of its windows.
  The relief of the ribs of a roof (`World.Skills.Roof`) stays at near
  and mid.
- **R12.** At a level with no bake, a surface gives its means to the
  points (D11).
- **R13.** A building of Humans Must Die from its issue (a tower of 40
  storeys with 30 windows on each side) is some `add` edits and one
  surface on each, and its far level shows the lit windows.

### Step 4: one atlas for a set, and KTX2 (#47)

- **R14.** `POST /sets` with `atlas: true` (D12), and an order with
  `atlas: true` (D13).
- **R15.** The fill of the empty texels of #43 holds in the atlas: each
  chart has its border of fill.
- **R16.** `images: "ktx2"` (D14), with a test that reads the file back.

## 6. Steps

Each step is one pull request, with its tests, its documents and its
pictures. The steps go in this order; a step starts only after I look
at the pictures of the step before it.

1. **A tint and a scale for each copy** (R1 to R5). Pictures: one tube
   house of Vũng Tàu as a street of ten copies with ten tints, and the
   16 jets of the carrier of Humans Must Die with two scales.
2. **The occlusion and the finish at each point** (R6 to R9). Pictures:
   a tube house at far with no bake, before and after, in daylight and
   at night (the glow).
3. **The surfaces** (R10 to R13). Pictures: a tube house of Vũng Tàu at
   near, mid and far with corrugated roofs, a rolling shutter and
   windows with some lit at night; the tower of 40 storeys of R13; a
   container with corrugated sides.
4. **One atlas, and KTX2** (R14 to R16). Measure: the draw calls, the
   bytes of the files and the bytes of the images on the GPU for the 13
   models of Humans Must Die, before and after (the table of #47).

## 7. Acceptance criteria

- The tests of each requirement pass, with the coverage of 100%.
- A part with ten tints is one file and one key.
- A level with no bake has no image, and its creases are dark in a
  viewer that reads only `COLOR_0` with `occlusion: color`.
- A house of Vũng Tàu at mid has corrugated roofs, rolling shutters and
  windows from surfaces, and its count of triangles does not go up.
- The 13 models of Humans Must Die in one set with `atlas: true` draw in
  one draw call each kind of material.

## 8. Open questions

- **Q1.** A scale on one axis (a longer container) as a part of D1, or a
  new part? I propose a new part (D1).
  **My answer (2026-11-22):** yes. A scale on one axis is a new part.
- **Q2.** KTX2 needs a Basis encoder in the VM (C code or WebAssembly).
  I propose to measure its time and its memory at the edge before step
  4, and to make KTX2 only on a construction shift if it does not fit.
  **My answer (2026-11-22):** yes. I measure the time and the memory of
  KTX2 at the edge before step 4.
- **Q3.** Godot reads `_COLOR_0` of `EXT_mesh_gpu_instancing`?
  **My answer (2026-11-22):** no: Godot does not read
  `EXT_mesh_gpu_instancing`. Vũng Tàu has its own import plugin
  (`addons/gpu_instancing/`), which makes a `MultiMeshInstance3D` of a
  mesh with instances; today it reads `TRANSLATION`, `ROTATION` and
  `SCALE`, and it will read `_COLOR_0` for the tint of each copy. So
  World writes `_COLOR_0` as the extension says (R2): an attribute of
  the extension of the node, with an underscore because it is not one of
  the three attributes of the extension, and an accessor with one color
  for each copy. Vũng Tàu changes its plugin when step 1 is there.
- **Q4.** Godot reads `_FINISH`?
  **My answer (2026-11-22):** no. The glTF import of Godot 4.7.2 reads
  only `POSITION`, `NORMAL`, `TANGENT`, `TEXCOORD_0` to `TEXCOORD_7`,
  `COLOR_0` (with its alpha), `JOINTS_0`, `JOINTS_1`, `WEIGHTS_0` and
  `WEIGHTS_1` (`modules/gltf/gltf_document.cpp` at 4.7.2-stable). World
  writes `_FINISH` as the glTF format says (an attribute of an
  application starts with an underscore), and Vũng Tàu reads it in its
  import (Vũng Tàu report 0009, section 10.5a).
