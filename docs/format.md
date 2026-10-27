# The format of a model

This file tells how Xưởng describes a part, an assembly and a voxel
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
%Xuong.Part{
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
  core of Wings makes them (`Xuong.Mesh`).
- `detail`: the class of the part for the levels of detail (below).
- `print`: `:keep`, `:skip` (not in the STL: too thin) or `:only` (only
  in the STL: a thicker stand-in).

A **standard part** is a function: `Xuong.Parts.Bolt.new("M8", 0.060)`.
Its tests compare its sizes with the tables of its standard.

A **shaped part** is a `.wings` file and a small module next to it. The
module gives the name, the sources and the ports, and reads the file
(`Xuong.Wings.read/1`). When the Wings plugin of step 6 exists, the
ports can also come from the file.

## A port

A port is a frame on a part: a point and two directions.

```elixir
%Xuong.Port{name: "hub", at: {0.0, 0.0, 0.0}, axis: {1.0, 0.0, 0.0}, up: {0.0, 0.0, 1.0}}
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
%Xuong.Connection{
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
- The triangles of a vehicle are about 50,000 or fewer in the near
  level, 10,000 or fewer in the mid level, and 2,000 or fewer in the far
  level. A test of each model checks it.

## The materials

A material is a role, not a color:

`paint` (the color of the thing), `trim` (black plastic and rubber
strips), `glass`, `glass_dark`, `tire`, `rim`, `chrome`, `metal`,
`steel`, `aluminum`, `light_front`, `light_back`, `seat`, `plastic`,
`wood`, `fabric`, `skin`, `hair`, `cloth`, `white`, `dark`.

`priv/palette.json` gives each role a color, a roughness and a
metalness. An app can give its own palette (the woodblock tones of Tre),
and it can change the `paint` of a model (the color of the car of a
person). In a `.wings` file, the name of a material is its role.

## The files of a model

The build (`mix xuong.build`) writes:

| File | Content |
|---|---|
| `priv/models/NAME.glb` | the near level |
| `priv/models/NAME.mid.glb` | the mid level |
| `priv/models/NAME.far.glb` | the far level |
| `priv/models/NAME.parts.json` | the list of the parts |
| `priv/models/NAME.stl` | the print (step 9) |
| `priv/models/NAME.vox` | the voxel version, when the model asks for one (step 8) |

The build gives the same bytes for the same model.
`mix xuong.build --check` builds again and compares; CI runs it.

## GLB

- **The axes.** glTF has +Y up and the front of a model to +Z, with the
  right hand. The writer takes a point (x, y, z) of Xưởng to
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
- `Xuong.Wings.read/1` is strict: a file from a person is data, never
  code. It decodes the term with `binary_to_term(Bin, [:safe])`, after it
  loads the names that a valid file can have (the atoms of Wings and of
  `wpc_xuong`). It refuses a file with any other name, a file larger
  than its limit, and a term that is not a Wings file.
- `Xuong.Wings.write/2` writes a part as a `.wings` file that Wings 3D
  opens.
- Before a mesh goes into the core of Wings, `Xuong.Mesh.clean/1`:
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
- **The voxel maker** (`Xuong.Voxel.from_model/2`) makes the voxel
  version of a model at a size of a block. A block is full when its
  center is in a closed part, or when a thin part (a sheet, a leaf)
  goes through it. The block takes the role of the part that fills the
  most of it.
- **The stamp of Tre** (in Tre, step 8) writes a `.vox` model into the
  fine grid of Tre at a place and a turn of 90°.
