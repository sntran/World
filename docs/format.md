# The format of a model

This file tells how World describes a part, an assembly and a voxel
model, and how it writes them as files. It is a plan: the code comes in
the steps of `README.md`.

## The units and the axes

- The unit of length is the meter. An angle is in degrees.
- The axes have the right hand:
  - x goes to the right side of the model (the right of a rider),
  - y goes to its front,
  - z goes up.
- **A part** has its own origin, at a point that its standard gives: a
  bolt has its origin at the center of the bottom of its head, with its
  shank along -z.
- **A model** (the top assembly) has its origin on the ground, at the
  center of its box in x and y. A vehicle stands with its wheels on
  z = 0, with its front to +y.

## A part

```elixir
%World.Part{
  name: "bolt_m8x60",
  kind: :bolt,
  params: %{thread: "M8", length: 0.060},
  sources: ["ISO 4017: the head is 13 mm across the flats and 5.3 mm high."],
  ports: [...],
  shapes: [...],
  detail: :fastener,
  print: :keep
}
```

- `name`: the key of the part, in lower case with `_`.
- `kind`: the family of the part: `:bolt`, `:nut`, `:washer`,
  `:bearing`, `:tube`, `:sheet`, `:lumber`, `:extrusion`, `:rim`,
  `:tire`, `:shaped`, and more.
- `params`: the numbers that make the part. The same params give the
  same part, byte by byte.
- `sources`: where each size comes from, in words: a standard, a data
  sheet, or a measurement. A size that is a guess says so.
- `ports`: the places where the part connects to another part (below).
- `shapes`: the meshes of the part, each with its material role. The
  core of Wings makes them (`World.Mesh`).
- `detail`: the class of the part for the levels of detail (below).
- `print`: `:keep`, `:skip` (not in the STL: too thin) or `:only` (only
  in the STL: a thicker stand-in).

A **standard part** is a function: `World.Materials.Fasteners.bolt("M8", 0.060)`.
Its tests compare its sizes with the tables of its standard.

A **shaped part** is a `.wings` file and a small module next to it. The
module gives the name, the sources and the ports, and reads the file
(`World.Wings.read/1`). When the Wings plugin of step 6 exists, the
ports can also come from the file.

## A port

A port is a frame on a part: a point and two directions.

```elixir
%World.Port{name: "hub", at: {0.0, 0.0, 0.0}, axis: {1.0, 0.0, 0.0}, up: {0.0, 0.0, 1.0}}
```

- `at`: the point, in the axes of the part.
- `axis`: the main direction: the axis of a hole, of a shaft, of a
  thread.
- `up`: a second direction at a right angle to `axis`. It fixes the
  turn around the axis.

Examples: a bolt has the ports `head` (under the head) and `tip` (the
end of the thread). A wheel has `hub`. A fork has `axle_left` and
`axle_right`. A hinge has `leaf_a` and `leaf_b` on one axis.

## An assembly

An assembly is a tree. The root is a part or an assembly. Each child
connects to its parent with one connection:

```elixir
%World.Connection{
  child: "rear_wheel",
  child_port: "hub",
  parent_port: "rear_axle",
  kind: :turns,
  offset: 0.0,
  turn: 0.0,
  limits: nil
}
```

The build puts the child so that its port is on the port of its parent:
the two points are at the same place, the two axes are the same, and the
two `up` directions are the same. Then it moves the child by `offset`
along the axis and turns it by `turn` around the axis.

The kinds of a connection:

| Kind | The child can | `limits` |
|---|---|---|
| `:fixed` | not move (a bolt in a hole, a panel on a frame) | `nil` |
| `:turns` | turn around the axis (a wheel, a door, the bars, a knee) | `nil` for a wheel, else `[min, max]` in degrees |
| `:slides` | move along the axis (a drawer, a fork tube in a shock) | `[min, max]` in meters |

Each connection that is not `:fixed` is a **joint**. A joint has a
`role` that tells an app what to do with it:

- `wheel`: it turns with the speed.
- `steer`: the bars and the front wheel, around the steering axis.
- `suspension`: a fork or a shock, a small move along its axis.
- `door`, `lid`, `drawer`: a part that opens.
- `recline`: the back of a seat that turns to the rear.
- `handle`: a handle that slides out (the trolley of a power station).
- `spin`: a part that turns when the item runs (a fan, the drum of a
  washer, a turntable).
- `knob`: a knob or a dial, and a faucet that swivels.
- `vane`: a vane that turns the flow of air (a mini split).
- `slide`: a part that a person moves along a track and locks (a
  fitting in an L-track).
- `limb`: a part of a person or of an animal.

A model has no joint for the lean of a vehicle with two wheels. An app
turns the whole model around the line on the ground under its wheels.

A **pose** is the value of each joint, by its name:
`%{"rear_wheel" => 45, "steer" => -10}`.

A loop of connections (a frame with two struts to one part) is not a
tree. The build refuses it in step 3. `TODO.md` has the idea of a loop
that closes with a fixed connection.

## The levels of detail

The build writes three levels of each model:

| Level | Parts that stay | Smooth of a shaped part | Use |
|---|---|---|---|
| near | all | the level of the part (most often 2) | close views, the sheet of a vehicle |
| mid | the parts of 2 cm or more, not `inside` | one level less | a model in a scene |
| far | the parts of 10 cm or more, not `inside` | none | small or far models, the bar of Phượt |

- The size of a part is the longest side of its box.
- A part with `inside: true` (a bolt in a body, a bearing in a hub) is
  only in the near level.
- `detail` can move a part up or down a level: a light of a vehicle
  stays in the far level, because the eye looks for it.
- A model is made again for each level (`World.Detail`): at the mid
  level a round shape has half of its sides and one smooth step less,
  and the sections of a body are two times farther apart; at the far
  level, a quarter of the sides, no smooth step, and four times farther.
- The root part of a model stays at each level: a small model (a switch
  of 7 cm) keeps its body at far.
- A part with `detail: :low` is only in the mid and far levels: it
  stands in for many small parts (a solid wall for its bricks, a solid
  roof for its tiles). It is not in the list of the parts.
- The triangles of a vehicle or an item are 50,000 or fewer in the near
  level, 12,000 or fewer in the mid level, and 5,000 or fewer in the far
  level. A house can have 300,000 in the near level (one part for each
  brick and tile), 20,000 in the mid level and 12,000 in the far level.
  A test of each model checks it.

## A house

A house is an assembly of its materials (`World.Buildings`):

- **A wall of masonry**: units (`World.Materials.Construction`: the brick of
  Việt Nam, TCVN 1451, 220 by 105 by 60 mm; the modular brick, ASTM
  C216; the hollow concrete block of 8 in, ASTM C90) in running bond,
  with joints of mortar of 10 mm, one or two wythes. At the end of a
  course and at an opening a unit is cut: a cut unit has the name of the
  whole unit, so the list counts the units to buy. A lintel of concrete
  goes over each opening; a gable narrows to its ridge.
- **A wall of wood studs**: 2x4 at 16 in, a bottom plate (cut at each
  door), a double top plate, a king stud, a jack stud and a header of two
  2x8 at each opening, a sill and cripples under a window; OSB of 7/16 in
  (its params count the sheets of 4 by 8 ft) and lap siding.
- **A gable roof**: rafters of 2x6 at 24 in, a ridge board of 2x8, OSB,
  fascia, and clay tiles (10 to the square meter) or metal panels (PBR,
  36 in of cover; the last panel is cut to the width).
- **Doors and windows**: a prehung door (jambs, a slab on three hinges, a
  knob) that opens to the inside; a casement window that opens out, or a
  fixed window.

The axes of a wall: along x from 0 to its length, its outside face at
y = 0, z up. An opening is `{kind, x, width, z, height}` in the axes of
the wall: the rough opening.

## The materials

A material is a role, not a color:

`paint` (the color of the thing), `trim` (black plastic and rubber
strips), `glass`, `glass_dark`, `tire`, `rim`, `chrome`, `metal`,
`steel`, `aluminum`, `light_front`, `light_back`, `seat`, `plastic`,
`wood`, `fabric`, `skin`, `hair`, `cloth`, `white`, `dark`, `black`,
`gray`, `rubber`, `copper`, `stainless`, `screen`, `blue`, `orange`,
`red`, `plywood`, `solar_cell`. A person
has more roles with their textures: `eyes`, `eyebrows`, `eyelashes`,
`clothes_NAME`, and `color_NAME` (the mean color of an asset at mid and
far).

`priv/palette.json` gives each role a color, a roughness and a
metalness. Glass also has an alpha (0.35 for `glass`, 0.85 for
`glass_dark`): its glTF material has the alpha mode `BLEND`. An app can give its own palette (the woodblock tones of Tre),
and it can change the `paint` of a model (the color of the car of a
person). In a `.wings` file, the name of a material is its role.

## A person

A person (`World.People.Human.person/2`) is a `World.Figure`: a set of nodes
that is ready, from the data of MakeHuman (`priv/makehuman/`). An
assembly holds a figure as a part, at one of its two ports:

- `ground`: on the ground, between the feet, with z up;
- `hips`: at the head of the bone `pelvis`, with z up (the seat of a
  rider).

The GLB of a person has:

- a root node, then a node for each of the 53 bones of the skeleton
  `game_engine` (parents first), with the frames of the pose;
- one mesh node with a skin. It is a root node of the scene: glTF does
  not use the frame of a skinned mesh, and the bones place it;
- 4 joints and 4 weights for each point, with the sum 1;
- textures in the GLB (the skin, the eyes, the hair, the clothes). Hair,
  eyebrows and eyelashes have the alpha mode `MASK`;
- the animations by name (`walk`: a loop of 1.1 s).

The levels: near is the full body with the clothes and the hair; mid is
a body of about 1,600 faces with the hair; far is a body of 730 faces.
At mid and far, the faces under clothes have the mean color of the
clothes, and at far the scalp has the color of the hair.

The colors of a person (`hair_color`, `clothes_colors`):

- The texture of a hair is gray, with a mean of 200 (of 255). The
  factor of its material is the color of the hair: the color of the
  order, or the mean color of the texture before it became gray. A color
  lighter than 200 in a channel stays at 200 in that channel.
- At mid and far, an item of the clothes has the color of the order in
  place of its mean color.
- At near, the color of an item is a tint of its texture: the factor is
  the color of the order over the mean color of the texture, at most 1.
  A tint can only make a texture darker.

A pose turns bones around their heads: a map of a bone to a list of
`{axis, degrees}`, with the axes of World when the person stands at
rest (`World.People.Pose`).

## The files of a model

The build (`mix world.build`) writes:

| File | Content |
|---|---|
| `priv/models/NAME.glb` | the near level |
| `priv/models/NAME.mid.glb` | the mid level |
| `priv/models/NAME.far.glb` | the far level |
| `priv/models/NAME.parts.json` | the list of the parts |
| `priv/models/NAME.stl` | the print (step 9) |
| `priv/models/NAME.vox` | the voxel version, when the model asks for one (step 8) |

The build gives the same bytes for the same model.
`mix world.build --check` builds again and compares; CI runs it.

## GLB

- **The axes.** glTF has +Y up and the front of a model to +Z, with the
  right hand. The writer takes a point (x, y, z) of World to
  (-x, z, y) of glTF. This is a turn, not a mirror, so the order of the
  corners of each triangle stays.
- **The nodes.** The root node has the name of the model. Each joint is a
  node, a child of the node of its parent joint, with the point of its
  port as its translation. Its parts have points relative to that point.
  `extras` of a joint node gives `role`, `axis`, `kind` and `limits`.
  An engine turns or moves the node along `extras.axis`.
- **The meshes.** One mesh for each node, with one primitive for each
  material. The writer takes only the visible faces of a Wings mesh: the
  core of Wings closes an open shape with hidden faces (holes). A flat
  face (a hard edge) has the normal of its face; a smooth part has the
  normal of each vertex.
- **The materials.** One glTF material for each role, with the values of
  the palette. Its name is its role.
- **`extras` of the root.** `name`, `kind`, `size` (the box), `sources`,
  `level` (`near`, `mid` or `far`).
- **The check.** The Khronos glTF validator checks each file in CI: no
  error and no warning.

## The list of the parts

`NAME.parts.json` lists each part once, with its count, its kind, its
params and its sources, in a fixed order:

```json
{
  "name": "honda_vision_110",
  "parts": [
    {"name": "bolt_m10x180", "kind": "bolt", "count": 1, "params": {"thread": "M10", "length": 0.18}, "sources": ["ISO 4014"]},
    {"name": "tire_80_90_14", "kind": "tire", "count": 1, "params": {"code": "80/90-14"}, "sources": ["ETRTO"]}
  ]
}
```

## Wings files

- A shaped part is one `.wings` file. Each object of the file is a shape
  of the part. The name of each material is its role.
- `World.Wings.read/1` is strict: a file from a person is data, never
  code. It decodes the term with `binary_to_term(Bin, [:safe])`, after it
  loads the names that a valid file can have (the atoms of Wings and of
  `wpc_world`). It refuses a file with any other name, a file larger
  than its limit, and a term that is not a Wings file.
- `World.Wings.write/2` writes a part as a `.wings` file that Wings 3D
  opens.
- Before a mesh goes into the core of Wings, `World.Mesh.clean/1`:
  - merges the points at the same place,
  - removes the faces with no area,
  - gives the faces of each connected piece the same order of corners,
  - splits a point where two fans of faces meet at that point only,
  - splits an edge that has more than two faces.

  The core of Wings cannot hold the last two: without the clean-up, a
  mesh becomes many small objects.

## Voxel models

A voxel model is a grid of blocks, for Tre. It is a separate kind of
model, because the winged-edge mesh of Wings cannot hold two blocks that
touch only at an edge or a corner.

- The file is MagicaVoxel `.vox`: a grid of up to 256 blocks on each
  side, and a palette of 255 colors. [Goxel](https://goxel.xyz/) (free,
  open source) and MagicaVoxel open it.
- A voxel model gives a material role to each color of its palette, in
  `NAME.vox.json`. Tre maps each role to a color of its own palette.
- **The voxel maker** (`World.Voxel.from_model/2`) makes the voxel
  version of a model at a size of a block. A block is full when its
  center is in a closed part, or when a thin part (a sheet, a leaf)
  goes through it. The block takes the role of the part that fills the
  most of it.
- **The stamp of Tre** (in Tre, step 8) writes a `.vox` model into the
  fine grid of Tre at a place and a turn of 90°.
