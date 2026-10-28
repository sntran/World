# Ideas for later

The owner decides about each idea. An idea that the owner accepts goes
into the steps of `AGENTS.md`.

## From the owner

- A service on the web (LiveView) that makes a new model from numbers:
  from a model of the library, or from a `.wings` file that a person
  sends.
- **The crew van of the Transit.** Ford does not sell it for 2024 to
  2027. The owner wants it in the line: its sizes come from the earlier
  years. It comes with the Sprinter and the ProMaster (`docs/world.md`,
  step W7).
- **The engineers and the architects of the world.** People that read
  the log of the world and propose a new process, a new component or a
  new model. A population of plans that compete (genetic programming),
  flocks of people (boids), in Erlang. After the first world
  (`docs/world.md`, "The engineers").
- **The factories of a planet, for Humans Must Die.** Emergency
  vehicles, airplanes, ships, aircraft carriers, buildings: each family
  is a new factory of the world, with its modules and its sources.

## From the development

- **Paint the weights of a skin in the Wings plugin.** The people have
  the weights of MakeHuman. A shaped part that bends (a seat cushion, a
  cable) needs a tool for its own weights.
- **More animations of people.** "walk" is the only clip: a run, a sit
  down, the hands that turn the bars of a scooter. Each clip is a
  function of the turns of the bones in time (`World.People.Pose`).
- **Clothes in their own colors at mid and far.** A low-poly body has
  the mean color of each piece of clothes: a suit of a shirt and jeans
  is all one color. The color of each face can come from the texture
  of the clothes.
- **More people.** Children (the targets of a child are not in the
  folder yet), more hair and clothes from the packs of MakeHuman.
- **More of a house.** Floors of joists, a ceiling, inner walls, stairs,
  a second floor, a hip roof, roof tiles at the ridge, concrete columns
  and beams (the frame of a house in Việt Nam), plaster and paint on a
  wall. The nails of a frame in the list of the parts.
- **A bond of two wythes.** A wall of 220 mm in Việt Nam has headers
  across the two wythes; the wall of World has two wythes of stretchers.
- **Loops of connections.** A frame with two struts to one part: the
  tree takes one strut, and a fixed connection closes the loop.
- **Vertex colors and textures.** The core of Wings keeps UV and vertex
  colors (`wings_color` must come into `wings/` for the colors). The GLB
  writer writes them.
- **A 3MF file for a print with colors.** One file with the color of
  each material, for a printer with more than one filament.
- **An SVG of any mesh.** The painter of DIY sorts its parts (boxes and
  prisms). A mesh of Wings needs a sort of its triangles.
- **A catalog of makes and models.** Real vehicles with their real
  sizes and sources: the Chevy Bolt, the Honda Wave, the Honda Vision. A
  person chooses a vehicle in Phượt.
- **The other vans of DIY.** The Ram ProMaster (136, 159, 159 extended)
  and the Mercedes-Benz Sprinter (144, 170, 170 extended), each with its
  engine bay, as makes of `priv/data/vans.json`. First the photos of
  dealers and the drawings of the maker (the sizes, the traces, the
  windows): not a memory.
- **The heights of the passenger van.** Ford gives 97.1 in (medium
  roof) and 108.4 in (high roof) for the passenger van, and 101.3 in and
  109.6 in for the cargo van. The van uses the heights of the cargo van.
  Find the cause (the load, the tires, a rail) in the drawings of Ford.
- **The crew van at the left side.** No photo shows the left side of the
  crew van: its window of the second row is the window of the passenger
  van. A photo can correct it.
- **A belt for the second alternator.** The second alternator of the van
  has no belt and no bracket on the engine. The kit of Ford for the
  Transit has its own bracket: its shape needs a source.
- **A flood fill for voxels and for hidden parts.** The voxel maker (step
  8) fills a shell of voxels: a flood fill from a corner of the grid
  marks the outside, and each voxel that it does not reach is inside, so
  the model is solid. The same fill on a coarse grid of a model finds the
  parts that nobody can see from outside (an engine under a closed hood),
  in place of `inside: true` by hand, and a hole in a shell before a
  print (step 9). The fill of Nils M. Holm, "A stackless floodfill
  automaton" (2023, <https://t3x.org/files/floodfill.pdf>), keeps its
  state in the cells (16 states in 2D; 36 for voxels) and needs no stack
  or queue: in the 128 MB of the edge, a grid in `:atomics` or in one
  binary is the only memory.
- **Godot import.** A script for Vung_Tau that reads the joint nodes and
  the levels of detail of a GLB of World.
