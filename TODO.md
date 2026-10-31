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
- **A hẻm of tube houses (nhà ống).** A blueprint for the narrow houses
  of a town of Việt Nam: a front of 3 to 5 m, 2 to 4 floors on a frame
  of concrete, walls of `brick_vn`, a roof of clay tiles or a flat
  terrace with a parapet, balconies with iron railings, striped
  awnings, shutters and folding doors, potted plants, a sign. Then a
  hẻm: a row of houses on each side, the sidewalks with their curbs, the
  paving of the street. A reference: the 3D chess game "Xóm Cờ Vua,
  Hẻm Nắng".
- **Plants from rules.** A trunk, branches, leaves and flowers from a
  few numbers (L-systems or space colonization): the plants in pots and
  the vines of the houses, the trees and the rocks along a road.
- **Decals and lights.** A texture or a printed panel on the paint (the
  stripe and the star of life of an ambulance, a sign), and materials
  that glow (lamps, the light bar).

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

## For Vũng Tàu

Vũng Tàu gets its models from World (plan 0023 of Vung_Tau,
[`docs/plans/0023-models-from-world.md`](https://github.com/sntran/Vung_Tau/blob/main/docs/plans/0023-models-from-world.md)).
Section 9 of that plan is the catalog: each model of the game, with its
details, the places and the times. Section 10 lists the requests below.
The game is in Vũng Tàu in January and February 2019, so each model is
as it was in 2019. The models are real: the shapes of the common makes
of 2019, from photos and data sheets. The game puts no badge, no name
and no logo on them.

- **The tube house and the hẻm (W1).** The idea "A hẻm of tube houses"
  above, with the options of the house kit of Vung_Tau (plan 0004): the
  kind (tube house, villa, mini-hotel of 5 to 8 floors), the style (old
  or new), the roof (a flat terrace with a parapet, corrugated metal,
  clay tiles). Walls of hollow red bricks (gạch ống) under a role
  `plaster`: the game paints the plaster with its own shader (damp,
  streaks, patches of brick). A roll-up shutter (cửa cuốn) or a folding
  iron gate (cửa xếp) at the ground floor, a front of granite or of
  patterned tiles, a step and a small concrete ramp for the scooters,
  iron cages over the windows and the balconies, back extensions, a
  small room or a metal roof on posts on the terrace.
- **The parts of a house front (W2).** Each one a model with a port on
  the wall, so that the game can put many of them in one MultiMesh: rail
  bars, balusters, pots with plants (bougainvillea, small bonsai), the
  outdoor unit of an AC on a bracket, a water tank of stainless steel, a
  solar water heater, a dish, an antenna, laundry on a pole, a bird cage,
  a metal awning, a sign with a text decal, the plate of the house
  number, the altar of the earth god on the floor near the door. Then
  the street: concrete power poles with bundles of cables, transformers,
  meter boxes, street lamps, tiled sidewalks and curbs.
- **People of the South of Việt Nam (W3, W4, W5).** The approved look of
  Vung_Tau `docs/prototype/people/` (plan 0006 there): a wider nose with
  a lower bridge, a shorter face, high cheekbones, skin of people who
  live in the sun, the marks of age. Clothes: đồ bộ (a printed shirt and
  trousers that match), áo ba lỗ, quần đùi with checks, faded plain
  colors, sun jackets, face masks, long sun gloves, wrap skirts, dép (no
  shoes). Hair: a bun, hair tied back. Hats: the half-shell helmet and a
  cap, with the nón lá. Ages from 18 (students, drivers), and children
  (the idea "More people" above).
- **Faces for speech (W6).** The 15 visemes of the Meta standard are
  morph targets of a person with `speech`, and 30 face shapes of the
  ARKit standard (Vung_Tau, plan 0006, R10) with `expressions`
  (`World.People.Face`). Still to do: the other 22 shapes of ARKit (no
  unit of MakeHuman: the looks of the eyes as turns of the eyes, the
  jaw and the mouth to the sides, the rolls and the shrugs of the lips,
  `mouthClose`, `mouthLowerDown`, `cheekPuff`, `tongueOut`), a head
  mesh of its own (now the
  targets are on the skin of all the body, sparse), and mixes of the
  visemes and the shapes from measured faces (now a guess). The check
  of lip sync (renders of "Chào anh, đi đâu đó?" and "Hello, where are
  you going?" from cues, the option `talk`) found: the tongue did not
  move with the jaw, the upper lip hid the upper teeth, and the teeth
  were too bright in the mouth (fixed). Still to do: the cues from a
  real voice (a voice service gives them; there is none in CI), the
  weight of a viseme by its sound (a closed `PP` must reach 1; a vowel
  less), and the corners of the lips at rest, where the relaxed face
  shows a little of the side teeth.
- **Skin (W6).** The skin is less like plastic (`World.People.Skin`: a
  sheen, less reflection, pores, darker creases). Still to do: a
  texture of the skin in more detail (MakeHuman has 1024 pixels), a real
  subsurface scatter in the app (glTF has no standard extension for
  it), the marks of age, and values from measured skin (now a guess).
- **Animations of daily life (W7).** The idea "More animations of
  people" above, with: talk with gestures, sit on a low stool, squat
  with flat feet (ngồi chồm hổm), eat with chopsticks and a spoon, drink
  from a glass, fan oneself, sweep, push a cart, carry a shoulder pole
  (đòn gánh), row a basket boat, pull a net, sit behind a rider (also
  sideways), lie in a hammock, swim with a ring, badminton, Chinese chess
  (cờ tướng).
- **The vehicles of 2019 (W8).** The idea "A catalog of makes and
  models" above, for Vũng Tàu: the step-through motorbike with gears (the
  shapes of the Honda Wave and Dream) with a rack for goods, a city
  bicycle with a front basket, a small sedan and a 7-seat car as taxis,
  the 16-seat passenger van (the Ford Transit) and a coach of 29 or 45
  seats, a motor tricycle for goods (ba gác máy). A port for the license
  plate, with a text decal from the order. Small things by seed: a helmet
  on the mirror, a phone holder, a raincoat under a strap, a seat cover.
- **Carts and stalls (W9).** The carts of bánh mì (a glass case, a
  grill), hủ tiếu gõ (a pot of broth, a glass case, a lamp, bowls),
  nước mía (a press with a motor, a case of cane) and fruit (a case on
  ice). A shoulder pole with two baskets. Low plastic stools of about 25
  cm and of about 45 cm, and their stacks. Low tables of stainless steel
  and of plastic. A market stall: plastic baskets, aluminum basins, tanks
  with air pumps, a dial scale, a tarp umbrella, boxes of polystyrene.
  The round pan of bánh khọt. A hammock.
- **Boats and the beach (W10).** A small wooden fishing boat (ghe, 8 to
  12 m: the length, the colors, a cabin, flags, the load of rope, nets,
  baskets and floats), the round basket boat (thúng chai, 1.5 to 2 m, of
  bamboo with a dark coat, one oar), rows of fishing stakes with nets,
  ships at anchor (the far level only), a fast ferry, swim rings, beach
  umbrellas, canvas chairs, thatched huts.
- **Animals (W11).** Next steps of the templates of four legs:
  - The shape space (`priv/animals/spaces/`): the farm pig and sheep
    (their rig has other bones in the legs: map the rays along the legs
    by the height over the ground, not by the bone), CC0 scans; a space
    for the primates; the hooves and the paws, the mane and the horns of
    a template are not in the space of the wolf. A region of the coat
    for spots (the hyena, a leopard), and a back that slopes down to the
    hips (the hyena has longer front legs); round ears (the ears of the
    wolf stay pointed with a larger `ear_width`).
  - The fur (`_FUR`, `_FUR_DIR`, the UVs): the lengths from
    measurements, not from photos; whorls and partings in the direction
    of the fur (now only along the bones); the fur in the apps (Phượt,
    Vũng Tàu).
  - The primates: the template is the mesh of BigMaQ (MIT, but the
    paper says the mesh came from MPI-IS and M. J. Black): ask its
    owners to confirm the license. More clips of motion data: the
    file of BigMaQ gives the walk, the run and the sit; its jumps are
    short hops that turn. Its climbs are not cycles: of the 69 tracks
    with the label "Climbing", 18 have no file, and only 3 have the
    hips up by 25 cm or more with the back up; they are a leap up to a
    ledge (row 637, G: 65 cm in 1.9 s, then a sit) and pull-ups with
    the legs free (rows 106, L and 603, G). The animals climb onto the
    things in the room, not up a trunk. So the climb, the hang and the
    jump stay the poses of the body plan. The leap could be a clip
    "jump up" (it moves the animal up: a clip needs a speed up for
    it); a
    faster walk
    (the clip is 0.39 m/s, a slow walk: few straight walks in the file,
    the animals are in a room). The feet of the mesh grip, but the plan has no bones for the
    toes; the thumb of the hand does not fold well in `"grip"`; a speed
    for the climb; the gibbon has the body of a macaque (no mesh of a
    gibbon); the sit of the animals with a long tail (the end of the tail is near the
    ground).
  - Fur on the template of primates: a crest of hair on the head and
    long hair on the cheeks.
  - The face of the macaque: the teeth are flat strips (one row, no
    molars, no tongue), and they show only when the jaw opens (the fear
    grimace shows no teeth: the lips meet); the cut of the mouth stops
    1.3 cm in front of the corners of the mouth (the fold of the low-poly
    mesh goes back along the jaw). The shapes are in the units of the
    template: the gibbon (a flat face) has the shapes of the macaque.
  - Faces of primates (the method of MF3D, Murphy and Leopold 2019): a
    shape space of the face from the head surfaces of CT scans with open
    licenses (MF3D used 23 rhesus macaques), and expressions from it in
    place of the four shapes of World. The images of MF3D are CC BY-NC:
    not for World.
  - The skin and the hair of mammals: four kinds of hair, one texture
    for all the coat of an animal (no long hair on the tail and short
    hair on the face, no texture that follows the length of the fur at
    each point); a pupil of one size (no pupil that gets small in the
    sun).
  - The birds: a rooster (a larger comb and tail, hackles); feet with
    webs for the duck, a bill deeper at its root, smaller eyes, the body
    of a duck at 40º; feathers (a pattern, the direction); a bird that
    flies (a pigeon, a swallow); a sit (a hen on its nest); a run.
  - The fish: scales and the gill cover; the barbels of the carp; a tail
    fin that is not forked (the tilapia) and the bands of the tilapia; a
    koi (a region for spots); more fish of Việt Nam (cá trê, cá lóc).
- **Plants for Vũng Tàu (W12).** The idea "Plants from rules" above,
  first with the 14 tree types of Vung_Tau (`data/trees/types.json` there,
  plan 0020): the same look as the sheets of its report 0020, with the
  same triangles or fewer. Then the trees of Vung_Tau move to World.
  Also the Tết plants (mai in a glazed pot, kumquat trees, marigolds,
  chrysanthemums), the garden plants (rice on terraces, herbs, mãng cầu,
  đu đủ, chuối, xoài, dừa), and the plants in pots.
- **Statues and known places (W13).** A large figure of a person (an
  option of scale, robes, a stone material) for the statues, and a
  drawing for each known place of Vũng Tàu (plan 0008 there), with the
  sources of its sizes.
- **Pinned files for a game (W14).** The same order at the same commit
  gives the same bytes on the site and with `mix world.order` in a clone
  (the workspace of Vung_Tau cannot reach the site). A field `license` in
  the receipt. A copy that never changes for a release (`/v/VERSION/`).
- **A far level for rows and crowds (W15).** About 500 triangles for a
  scooter, 1,500 for a person, 300 for a stool: the game shows rows of
  40 parked scooters and groups of people. The far scooter has about
  4,000 triangles now.
