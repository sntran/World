# Ideas for later

The owner decides about each idea. An idea that the owner accepts goes
into the steps of `AGENTS.md`.

## From the owner

- A service on the web (LiveView) that makes a new model from numbers:
  from a model of the library, or from a `.wings` file that a person
  sends.
- People for Vung_Tau, with a skeleton.

## From the development

- **A skin.** A mesh that bends with its joints (an elbow, a knee):
  weights for each vertex, a tool to paint them in the Wings plugin, and
  a glTF skin. First for the people.
- **Clips of animation.** Key poses in time, kept in the format, and a
  glTF animation. A timeline in the Wings plugin comes after the data.
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
