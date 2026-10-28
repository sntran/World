# Xưởng

Xưởng ("workshop" in Vietnamese) is the library of 3D models of the
projects of the owner: [Phượt](https://github.com/sntran/phuot),
[DIY](https://github.com/sntran/DIY), [Tre](https://github.com/sntran/Tre)
and [Vung_Tau](https://github.com/sntran/Vung_Tau).

A model in Xưởng is made as a real thing is made: from real parts.
A bolt, a bearing, a wheel and a panel are parts. A scooter is an
assembly of parts and of smaller assemblies. Each part has its real size,
from a standard or from a measurement, in meters.

The library writes each model as GLB (glTF 2.0, binary): one format for
the screens of each project. It also writes STL for a 3D printer, and a
list of the parts (a bill of materials).

This file is the plan. The repository has no code yet.

## Why

Four projects draw 3D things, and none shares its models with another:

| Project | Language | Its models | How it draws |
|---|---|---|---|
| DIY | Elixir | Parts in code (box, cylinder, prism, face): about 60 kinds of items of a house, 9 camper vans, an electric car, power stations | SVG on the server |
| Tre | JavaScript | A world of blocks (voxels), figures of parts on pivots, smooth meshes for the living things | three.js |
| Vung_Tau | GDScript (Godot) | Boxes and cylinders in code, trees from Blender (not final) | Godot |
| Phượt | Elixir, Kotlin | None yet: the vehicle next to the avatar is a line icon | MapLibre, Android |

The projects use four languages, so one library of code cannot serve
them all. A file can: each project reads GLB. Xưởng is a library in
Elixir that makes the files, and the files are in the repository and in
each release.

## The three levels of a model

1. **Standard parts.** A function makes the part from its numbers and its
   standard: a bolt from its thread and its length (ISO 4014), a nut
   (ISO 4032), a washer (ISO 7089), a bearing (the 6000 series), a tube,
   a sheet, a piece of lumber, an aluminum extrusion, a wheel from the
   size of its rim and the code of its tire (ETRTO: 100/90-14).
2. **Shaped parts.** A part with a free shape: the body panel of a
   scooter, a seat, the door of a fridge. A person makes it in
   [Wings 3D](https://www.wings3d.com/), and the repository keeps its
   `.wings` file.
3. **Assemblies.** A tree of parts and smaller assemblies. Each child
   connects to its parent at two ports: for example, the axle bolt goes
   through the hub of the wheel and through the fork. The kind of the
   connection (fixed, turns, slides) gives the joints of the model.

Tre also needs **voxel models** (models of blocks). They are a separate
kind, in the MagicaVoxel format (`.vox`). A tool of Xưởng makes the voxel
version of any model, at the size of a block (`docs/format.md`, "Voxel
models").

## The ideas

- **Real parts, real sizes.** The size of each part comes from a
  standard, a data sheet or a measurement, and the model says which
  (`sources`). A wheel of the scooter and a wheel of the food cart are
  the same function with other numbers.
- **The joints come from the parts.** The axle bolt of a wheel is the
  axis of the joint of the wheel. The bearing of the steering stem is the
  axis of the steering. A hinge is the axis of a door. Nobody draws a
  joint by hand.
- **A model knows its parts.** The build writes the list of the parts of
  each model, with their counts: a van of DIY gives the screws, the
  lumber and the batteries that its build needs.
- **Detail for the size on the screen.** A scooter has hundreds of bolts.
  The build writes three levels of detail (near, mid, far), and drops the
  parts that are too small for a level, or that a body hides.
- **The core of Wings in Elixir.** The library uses the mesh core of
  Wings 3D (Erlang) with no window: the same mesh, the same smooth
  (Catmull-Clark) and the same file format as the program on the desk.
  A person can open each part in Wings 3D, change it, and save it.
- **Code is the source.** A standard part and an assembly are code. A
  shaped part is a `.wings` file. The GLB, STL and list files are the
  output: the build makes them again, byte by byte, and CI compares them.

## Progress

| Step | Result | State |
|---|---|---|
| 0. The plan | This file, `AGENTS.md`, `CONTRIBUTING.md`, `TODO.md`, `docs/format.md`. | Done |
| 1. The project and the core of Wings | A Mix project on [BEAM.com](https://github.com/sntran/BEAM.com). The core of Wings 3D in `wings/`. `Xuong.Mesh`, `Xuong.GLB`, the check of the Khronos validator, the review page. CI. | Done |
| 2. Standard parts | Bolts, nuts, washers, bearings, tubes, sheets, lumber, extrusions, wheels and tires, each from its standard, with its ports. | Done |
| 3. Assemblies and joints | Connections, joints, the list of the parts, three levels of detail, GLB with a node for each joint. The vehicles of Phượt: the Honda Vision 110, the Chevrolet Bolt EV, the Ford Transit 148 camper, the Royal Enfield Himalayan, a touring bicycle. | Done |
| 3b. People | People from the data of MakeHuman (CC0): the shape of the body from its numbers, a skeleton of 53 bones with a skin, skins, hair and clothes, poses ("stand", "sit", "ride"), the animation "walk", and the three levels. A traveler, a man and a woman of Việt Nam, and a rider on the Honda Vision 110. | Done |
| 4. Phượt uses Xưởng | The vehicle next to the avatar of Phượt is the model of Xưởng, and it moves with the trip. | To do |
| 5. Wings files | A strict reader and a writer of `.wings`. Shaped parts from `.wings` files. The clean-up of a mesh before Wings takes it. | To do |
| 6. The Wings plugin | `wpc_xuong` for Wings 3D: ports and joints in the file, a pose to try, the axes in the view. | To do |
| 7a. The items of DIY | The appliances (a fridge, a washer and a dryer, a dishwasher, a range, a microwave, a freezer, a water heater, the AC, a mini split, a ceiling fan, a TV), the seven power stations, the gear of a van (a LiFePO4 battery, the Victron MultiPlus-II, SmartShunt, Lynx Distributor and Orion XS, a battery switch, a 12 V fridge, a roof fan, a diesel heater, a water tank, a solar panel), and builds of wood (a bed platform, a galley) with their lumber and screws. Doors, lids, drawers, fans and knobs are joints. | Done |
| 7b. Houses | The materials (bricks of Việt Nam and of the US, concrete blocks, lintels, lumber, OSB, siding, clay tiles, metal panels, hinges), walls of masonry and of wood studs with openings, gable roofs, doors and windows that open, and houses from them: a house of bricks of Việt Nam with a roof of tiles, a cabin of wood with a metal roof. The list of the parts counts each brick, stud, tile and panel. | Done |
| 7c. Framing systems | T-slot extrusions (80/20 10 and 15 series, metric 20, 30 and 40 mm) with T-nuts, corner brackets and button head screws; strut channel (Unistrut P1000 and P1000T) with spring nuts, fittings and threaded rod; L-track with fittings that slide. Inch threads for the fasteners. Builds: a shelf of 80/20, a rack and a trapeze of strut channel, a floor with L-track. | Done |
| 7. DIY uses Xưởng | DIY draws its SVG from the models, and keeps its pictures. | To do |
| 8. Voxel models | The `.vox` reader and writer, the voxel maker, and the stamp of a model into the grid of Tre. | To do |
| 9. STL for a printer | STL at a scale, for each material too, and the checks of a print. | To do |

`AGENTS.md`, "The steps", gives the check of each step. `TODO.md` has
the ideas for later.

## Use the models

An Elixir app adds the package and calls its functions:

```elixir
{:xuong, github: "sntran/Xuong", ref: "COMMIT"}
```

Another app takes the files: `priv/models/NAME.glb` in the repository,
or the files of a release on GitHub.

## The license

The code, the models, and the files that the build makes are under the
**GNU Affero General Public License 3.0** (`LICENSE`):

- Each person can use, change, share and print the models.
- A person who changes them and gives them to others, or runs them in a
  service on the web, must give the changes under the same license.
- The models come with no warranty (sections 15 and 16 of the license).
  A print of a model is a model. Do not use it as a part of a vehicle or
  to hold a load.

The owner has the copyright, so the other projects of the owner use the
models with no change to their own licenses. A model from another person
comes in only when that person agrees to the AGPL-3.0
(`CONTRIBUTING.md`).

The core of Wings 3D in `wings/` keeps its own license (`wings/LICENSE`,
the terms of Wings 3D: free use, copy and change, with its copyright
notice kept). An asset from outside keeps its own license in its own
folder, with a line in `CREDITS.md`.
