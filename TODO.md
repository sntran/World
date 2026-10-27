# Ideas for later

The owner decides about each idea. An idea that the owner accepts goes
into the steps of `AGENTS.md`.

## From the owner

- A service on the web (LiveView) that makes a new model from numbers:
  from a model of the library, or from a `.wings` file that a person
  sends.

## From the development

- **Paint the weights of a skin in the Wings plugin.** The people have
  the weights of MakeHuman. A shaped part that bends (a seat cushion, a
  cable) needs a tool for its own weights.
- **More animations of people.** "walk" is the only clip: a run, a sit
  down, the hands that turn the bars of a scooter. Each clip is a
  function of the turns of the bones in time (`Xuong.Human.Pose`).
- **Clothes in their own colors at mid and far.** A low-poly body has
  the mean color of each piece of clothes: a suit of a shirt and jeans
  is all one color. The color of each face can come from the texture
  of the clothes.
- **More people.** Children (the targets of a child are not in the
  folder yet), more hair and clothes from the packs of MakeHuman.
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
- **Godot import.** A script for Vung_Tau that reads the joint nodes and
  the levels of detail of a GLB of Xưởng.
