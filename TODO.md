# Ideas for later

The owner decides about each idea. An idea that the owner accepts goes
into the steps of `AGENTS.md`.

## From the owner

- A service on the web (LiveView) that makes a new model from numbers:
  from a model of the library, or from a `.wings` file that a person
  sends.
- **The crew van of the Transit.** Ford does not sell it for 2024 to
  2027. The owner wants it in the line: its sizes come from the earlier
  years. The Sprinter and the ProMaster are on the line now
  (`docs/world.md`, step W8); the crew van waits for photos. No photo
  shows its left side: its window of the second row is the window of
  the passenger van.
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
- **More plants from rules.** The nursery grows four species from their
  rules (step P7). Next: the plants in pots and the vines of the houses,
  and the trees and the rocks along a road (L-systems or space
  colonization).
- **Decals and lights.** A texture or a printed panel on the paint (the
  stripe and the star of life of an ambulance, a sign), and materials
  that glow (lamps, the light bar).

## From the development

- **More of the bamboo shop.** The fan of three spokes at the top of a
  back, the curved top rail, the seat of slats that bends between its
  rails, the culms that taper and are not quite straight, the hole of
  a rail end that shows the diaphragm, a green fresh culm. The sizes
  of the culms come from photos: measure a chair of a shop.
- **More of the hammock shop.** The clip of a person who gets in (the
  bed must change its shape under a body that moves: a bed that follows
  a person, by its morph targets). The sizes still by eye: the coils and
  the eyes of the spring (no shop gives them), the shape of the bug net
  and the pitch of the tarp, the parts of the frame of Duy Lợi, the
  place of the hips of a person on a seat; measure them in a shop and at
  a café.

- **More of the sheet metal shop.** Bends of other angles (a hem of 180
  degrees, a joggle), holes in a flange (knockouts), and a gasket for a
  box of NEMA Type 4. The gauge of the A-16N126 from its datasheet (16
  gauge now, the gauge of the A12N128).
- **The half helmet, more real.** The low part of the headform (under
  its reference plane: the point K, the chin for the buckle); the vents
  (5.12); the tests of QCVN 2:2021 as checks of the world (the impact,
  the strap at 500 N, the stability); a helmet of three quarters and a
  full helmet with a visor.
- **The footwear, more real.** The tread of a sole (the tread of a tire
  on the dép lốp); the shape of the footbed (the arch, the heel cup); the
  carved arch under a guốc cao, the burned and the lacquered decoration
  of a guốc; the left foot (a pair); a shoe on the foot of a person in a
  pose; the sizes of the hardware from a data sheet; a woven band with
  its mass for each meter. The holes of the dép tổ ong as hexagons
  (now diamonds), and its heel ring on the footbed; the knot of the
  hanao of a geta from a photo of its back.
- **More of the mold shop.** A hull of glass fiber with its plies (a
  composite thúng chai), a seat for a bus or a stadium (EN 13200-4), and
  the body of a scooter. The laminate has no ply schedule from a maker
  for a seat shell: 3 plies of mat is an estimate.
- **The ghe of Vũng Tàu, more real.** The lines from a drawing (now by
  eye, with the stern, the stem head, the wale, the propeller and the
  paint from the photos of the owner); the engine and its bed (QCVN 91,
  Bảng 4/2-B), the shaft, the fish holds and their hatches (Bảng 10/2-B
  and 11/2-B), the mast, the eyes on the bow, and the blue and white
  lines on the bow of the photos. A ghe of Hội An from the model on
  Sketchfab of the owner (CC BY, with its credit in `CREDITS.md`). Its stability: the center of buoyancy and the metacenter
  at its draft, in place of the stand check of a thing on the ground.
  The strakes of the hull (the garboard, the bilge strake, the wale and
  the sheer strake of Bảng 14/2-B) as boards of their own sizes.

- **The mass of the van, 19 % under the curb weight.** Each part of the
  van has a mass now (1967 kg at near), but Ford gives 2418 kg. The body
  is one steel sheet of 0.8 mm (an estimate): a real body has rails,
  crossmembers, pillars and floors of thicker gauges, and the van has no
  air conditioner, no wires and no insulation. A source of the gauges
  and of the rails of the body (the body in white of a Transit) closes
  the gap. The masses of the axle, the suspension, the shaft and the
  exhaust are estimates; a data sheet of each makes them true.
- **The mass of the other tires.** The skin of a tire is 7.5 % of the
  height of its side: a fit to two tires. The tires of the motorcycles
  and of the scooter need a data sheet with a mass.
- **The cage of a smooth mesh.** `World.Mass` and `World.Check` use the
  cage of a mesh, before its smooth steps; the smooth surface is a bit
  inside the cage.
- **The doors of the factories.** A vehicle goes through a drive-in door
  of 12 by 14 ft (`World.Check.drive_in/0`), but the buildings of the
  factories have walls of 3 m and an overhead door of 9 by 8 ft: a plant
  for vehicles needs taller walls and its drive-in door.

- **More garments from patterns.** `World.Sewing` cuts the pieces from
  the body and its skirt. Next: a skirt and a coat (wide pieces on the
  skirt), shorts, a polo collar, sleeves to the elbow, and the colors of
  two fabrics in one garment (the cups and the band of a bra).
- **The edge of the cut faces at mid.** The faces on the breasts of the
  body of mid are cut in sixteen; the faces around them take the new
  points of their edges as polygons, and show small creases under the
  bust. A cut in four of the ring around (one more ring, one step).
- **The faults of the renders next to photos (step P1).** At mid the
  áo dài has no panels: the clothes are colors on the body there, so the
  áo dài is a suit that fits the body; a mid level of the panels (a few
  faces) can stay. The bra has no shoulder straps. The quần is narrower
  than the wide legs of the photos.
- **A hood up.** The rain shell of World has its hood folded at the
  back of the neck. A hood over the head needs room for the hair, and
  a cut for the face.
- **Layers of the clothes at near.** At near each item is its own mesh
  over the body, in the order of its `z_depth`. Wide pants come through
  the shaft of a tall boot (`toigo_wool_pants` in
  `punkduck_winter_boots`), and the top of some jeans comes through a
  T-shirt (`punkduck_female_tight_jeans`, `cortu_jeans_shorts`). An
  item under another one can move in to the body where the two meet.
  At mid and far the clothes are colors on the body, with no such
  problem.

- **Paint the weights of a skin in the Wings plugin.** The people have
  the weights of MakeHuman. A shaped part that bends (a seat cushion, a
  cable) needs a tool for its own weights.
- **More animations of people.** The clips are "walk", "wave", "point"
  and the routines of a morning of exercise. Next: a run, a sit down,
  the hands that turn the bars of a scooter. Each clip is a function of
  the turns of the bones in time (`World.People.Pose`).
- **The patterns of clothes at mid and far.** A face of a low-poly body
  under a piece of clothes has the mean color of that piece, so a check
  or a print is one color there. The color of each face can come from
  the texture of the clothes.
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
- **The colors and the UVs of a `.wings` file.** The GLB writer writes
  UVs, textures and vertex colors (the animals, the skin and the clothes
  of people). The core of Wings keeps the UVs and the vertex colors of
  a shaped part too, but `wings_color` must come into `wings/` for the
  colors.
- **A 3MF file for a print with colors.** One file with the color of
  each material, for a printer with more than one filament.
- **An SVG of any mesh.** The painter of DIY sorts its parts (boxes and
  prisms). A mesh of Wings needs a sort of its triangles.
- **The engine bays of the other vans.** The ProMaster and the Sprinter
  are on the line (step W8) with the bay of the Transit: the engine, the
  radiator and the parts of the bay of each make need their own
  sources.
- **The heights of the passenger van.** Ford gives 97.1 in (medium
  roof) and 108.4 in (high roof) for the passenger van, and 101.3 in and
  109.6 in for the cargo van. The van uses the heights of the cargo van.
  Find the cause (the load, the tires, a rail) in the drawings of Ford.
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
- **Godot import.** Godot 4 does not read `EXT_mesh_gpu_instancing`
  (godot-proposals 8787): Vung_Tau has an import script for it,
  `addons/gpu_instancing/` (`GltfGpuInstancing`, a
  `GLTFDocumentExtension` that makes a `MultiMeshInstance3D`), on its
  branch `feat/0023-gpu-instancing`. Still to do there: the joint nodes
  and the levels of detail of a GLB of World. A model with no instances
  is a build with `instances: false` (`World.Build.scene/2`).

- **More of the nursery.** The foliage of the clump of bamboo and of the
  frangipani is less dense than in the photos (cards of leaves, not a
  mass of leaves). Plumeria obtusa (evergreen) next to P. rubra; the
  bunch of a banana as hands of a real shape; a wind that moves the
  leaves (an animation).
- **More of the streets from OpenStreetMap.** The data of Vũng Tàu is
  sparse: no building of the block of Ba Cu has a height or a roof
  shape, only 10 have levels, and many buildings are not in the data.
  The blueprints of the tube houses on the footprints (W1), the roofs,
  the sidewalks and the trees of their species. A tile of the data of the
  owner of the game (photos of the street) can correct the levels.
- **The sizes of TCVN 9366-1:2012.** The doors and the windows of Việt Nam
  have their sizes in TCVN 9366-1:2012 (Table 1), which has no open copy;
  the table of World has the least door of an exit (TCVN 4451:2012) and
  the sizes of the market.

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
  The round pan of bánh khọt.
- **Boats and the beach (W10).** The ghe is in the boatyard
  (`World.Boats.Ghe`, its next steps above). Still to do: its flags and
  its load (rope, nets, baskets and floats), the round basket boat (thúng chai, 1.5 to 2 m, of
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
- **Pinned files for a game (W14).** The same order at the same commit
  gives the same bytes on the site and with `mix world.order` in a clone
  (the workspace of Vung_Tau cannot reach the site). A field `license` in
  the receipt. A copy that never changes for a release (`/v/VERSION/`).
- **A far level for rows and crowds (W15).** About 500 triangles for a
  scooter, 1,500 for a person, 300 for a stool: the game shows rows of
  40 parked scooters and groups of people. The far scooter has about
  4,000 triangles now.
- **Houses for the lots (W17 to W23, plan 0009).** Plan 0009 of Vung_Tau
  puts thousands of houses on the real lots, so one house must be cheap
  and must come in many shapes. W1 and W2 are the first part of this.
  - **A whole house from a lot (W17).** One order makes one house from
    these options: width 3 to 6 m, depth 8 to 25 m, floors 1 to 8, kind
    (tube house, shop house, villa, mini-hotel), style (old or new), roof
    (flat terrace with a parapet, corrugated metal, clay tiles), ground
    floor (cửa cuốn, cửa xếp, door and gate, open shop), front finish
    (plain, granite, patterned tiles), paint age, a seed, and for each
    side wall: shared with a neighbor, free, or bare brick above a lower
    neighbor. Optional: a back extension and a room on the terrace. The
    same order gives the same bytes.
    Done: the tube house, the shop house, the villa and the mini-hotel
    (`World.Buildings.Lot` and the blueprint `lot_house`; a bare side
    wall is brick from the ground to the roof: the owner chose this).
    Still to do: a villa wider than 6 m with a yard at its sides (W17
    gives 3 to 6 m for each kind), a mezzanine in a shop house, a lower
    neighbor of its own height for a bare wall; the
    sizes of the floors, the balconies and the details from photos of
    the houses of Vũng Tàu next to the renders (now by eye).
  - **Ports in `parts.json` (W18).** The game puts the small parts with
    a MultiMesh, so each house lists its ports: a position, a normal, a
    size, and a kind. Front ports: AC unit, rail, pot, sign (with the
    size of the text), number plate, altar of the earth god. Roof ports:
    water tank, dish, antenna, laundry pole. Wire ports on the front,
    where the game attaches the cables from the power poles.
    Done for the tube house (`docs/format.md`, "The list of the parts").
    Still to do: the models of the small parts (W2), and an AC on a side
    wall or on the roof of a house of one floor.
  - **A family of houses (W19).** One list of orders gives a set of
    variants (for example 30 tube houses of 4 m, by seed). The game
    makes a library from the set, and picks one by the size of the lot.
    Done: `POST /sets` (`World.Orders.Set`, `docs/factory.md`). Still to
    do: a tool of the MCP server for a set; the time of a set of 64 at
    the edge (each order is checked: a build at far).
  - **One room you can enter (W20).** An option `interior: front_room`
    for the homestay and the shops: an open ground floor with a door of
    0.9 × 2.1 m, a floor 20 cm above the street, a ceiling of 3 m, and
    the stairs. Every house also has simple collision boxes (walls, the
    step, the ramp) as named nodes in the GLB, so the game does not
    use the visible mesh for collision.
    Done: the collision boxes of each house, and `interior: front_room`
    (a room behind the front, its stairs, and the door of 0.9 by 2.1 m
    in the wall at its back: `docs/format.md`, "A house on a lot"; the
    owner can change this reading). Still to do: the doors of a door
    with a gate and the cửa xếp do not move yet, so a player enters an
    open shop or under a raised shutter; the floors over the ground
    floor have no rooms.
  - **The street kit (W21).** Straight pieces of 2 m, corners, and
    junctions of: the sidewalk with the curb and tiles, the gutter with
    covers, a ramp cut for scooters, the concrete paving of a hẻm with
    cracks and patches. The concrete power pole with crossarms, bundles
    of cables, a transformer, and meter boxes (with wire ports). The
    street lamp. A trash bin.
    Done: `World.Places.StreetKit` (`docs/format.md`, "The street kit").
    Still to do: the round corner of a curb, the cables between two
    poles (the game draws them from the `wire` ports), a pole with a
    transformer on a platform between two poles, the photos of the
    streets of Vũng Tàu next to the renders (now by eye).
  - **Levels for a town (W22).** For a whole house: near at most about
    40,000 triangles, mid at most 3,000, far at most 300 (a box with the
    right roof). At most 6 materials in one house, by role, so the game
    needs few draw calls. The far level keeps the roof, because the
    player sees roofs from Núi Lớn and Núi Nhỏ.
    Done: `test/world/town_limits_test.exs` fails when a house is over a
    limit or has a role that is not of a house. A house keeps its 12
    roles; the game merges them into its 6 materials (the owner chose
    this).
  - **Roles and UVs for the wall shader (W23).** The roles `plaster`,
    `brick_ong`, `tile_granite`, `tile_pattern`, `metal_shutter`,
    `iron`, `roof_corrugated`, `roof_clay`, `concrete`, and `glass`.
    The UVs of a wall are in meters. A vertex color on the walls gives
    the height above the ground and the distance to a corner, so the
    game can put damp at the bottom and streaks at the corners.
    Done: `World.Surface` (the UVs in meters, `TEXCOORD_1` and `COLOR_0`;
    `docs/format.md`, "GLB"). A house keeps all its roles: the game
    merges them into its 6 materials (the owner chose this).
- **Buildings and statues (W13, plan 0008).** The known places of Vũng
  Tàu, and the temples and statues of other projects (Tre), are one of
  a kind, but each one is an assembly of parts with a grammar, like a
  house. A system for them, with the same materials, parts, physics,
  roles, levels, ports, and collision boxes as the houses (W17 to W23).
  An order gives the outline (from OpenStreetMap), the sizes, and a
  source for each size. The game makes the stairs and the paths on the
  ground; World makes the building or the statue.
  - **A statue (first).** A figure of the person blueprint at any size,
    in a pose from its joints, cast as one solid: the body and the
    clothes are one shell, with no gaps, of concrete, stone, or bronze,
    with the stains of the weather. The option `hollow`: walls of a real
    thickness, a spiral stair inside, and openings (the statue on Núi
    Nhỏ is 32 m high, its arms 18.4 m from hand to hand, and 133 steps
    go up inside to its shoulders, where visitors look out). A base
    with panels of figures in relief (Christ and the twelve apostles).
    Done: `World.Cast`, `World.Statues`, the blueprint `statue`, and
    `tuong_chua_kito_vua` (`docs/format.md`, "A statue"). Not yet: the
    pattern of the grilles of the windows (chữ thọ), the figures of the
    reliefs as figures of people, the inside of the base (a room), and
    the hollow at mid.
  - **A tower.** A tapered body of masonry or concrete, a gallery with a
    rail, the lantern room, and the cap (the lighthouse of Vũng Tàu,
    about 18 m).
  - **A French villa.** Walls with openings, verandas with arches and
    columns, balustrades, a hip roof of clay tiles, and a band of tiles
    under the roof (Bạch Dinh, 1898 to 1916).
  - **A church.** The nave, the steep gable, the bell tower, and the
    windows with arches.
  - **A Southern temple (đình, chùa, miếu).** A hall on a base of steps,
    columns, roofs in tiers with curved ends of the ridges and ceramic
    figures on them, the gate (tam quan), and the altars (Miếu Hòn Bà
    is small, so it is the first one).
  - **Pieces for a stone jetty.** Pieces of 2 m of the stone deck with
    its edge, as in the street kit: the game lays them along the line
    of Cầu Đá on the real ground.
