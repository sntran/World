# Plan 0019: World serves the projects

Status: In progress. The probe of the five projects is made (section
3), and the design is in section 4. The steps of section 6 are next.

Depends on: plan 0002 (any blueprint from any project), plan 0008 (a
model from edits), plan 0012 (the crews of a node), plan 0016 and plan
0018 (the rules of a house and of a building).

## 1. Goal

Each project of the owner can ask World for its models, and World
answers in a way that is smart and fast for that project. The projects
prepare the requests (blueprints in data, drawings of edits, the words
of a rule). World has the rules and builds on demand.

## 2. What the owner asked

The owner, 2026-11-15:

- "Like Dreams, World is an engine. It has rules that let the user
  build any kind of models. The tests should test the rules ... not
  testing against the catalog of what we have built. In fact, we should
  not even have catalog of those. Models are built from edits, on
  demand."
- "I want you to get World to the place that my other projects can
  request models for."
- "The Cloudflare Worker deployment is for prototyping World. Once we
  are at the good point, I will deploy it to my mini PC with lot of RAM
  to use, and put world.mkfifo.com from Cloudflare tunnel for other
  projects to use. So resources is not a big concern."
- "Do a probe with all those projects to determine the goals, what
  kind of models are expected there, so World has a smart, performant
  way to support them. Remember, Sony Dreams run on PS4, and can build
  any models. We run in smaller box, but we don't need to build every
  models, but we have the power of Erlang, and we can scale when we
  need to."

## 3. The probe (2026-11-15)

One reader read the documents and the code of each project. A value
that a project does not give is "not found" here, not a guess.

### 3.1 The five projects in one table

| | Vũng Tàu | Phượt | DIY | Humans Must Die | Tre |
|---|---|---|---|---|---|
| What it is | A first-person game of the town in 2019 | A map for a road trip, with a traveler and a vehicle | A planner of the power of a home and a van | A game: the Earth from space | A game of history for children |
| Draws with | Godot 4.7 (Forward+, Mobile, web) | three.js with the loader of glTF | SVG from the server, 12 fixed cameras | three.js, its own geometry in batches | three.js, boxes in one instanced mesh |
| Takes a GLB file | Yes | Yes | No | No (it has no loader, and no asset file) | No (each thing is made in code from a seed) |
| Look | Real shapes; the game owns the materials | Real | Simple solids with the details of the real model | Low-poly: flat faces, a color at each point, no image | 21 flat colors, three tones by the direction of a face |
| A model on the screen | Near to far: 15 m, 40 m, 150 m | A phone, 390 px | An icon or a stage of 12 views | A few pixels: a carrier is 0.03 of the radius of the Earth | A figure of 2.3 blocks |
| When it needs a model | At the build of a release | While the app runs, for each user | While the app runs (a cache for each kind) | A fixed set can be made before a release | While the game runs, from a seed |
| How many | 76 kinds; 2,193 house outlines; 99,000 trees of 14 types | 5 kinds of vehicle and 12 vans; one traveler for each user | 70 kinds | 24 buildings, about 12 vehicles, a turbine, 3 trees | 232 looks of figures, about 150 other things |
| Uses World now | Yes: 9 orders with a lock | Yes: the order in a URL, and the kit | No | No | No |

### 3.2 Vũng Tàu

- **The game makes the ground itself:** the heights (tiles of 256 m on
  a grid of 2 m), the roads, the sea and the beach come from its
  geodata. It does not ask World for them.
- **It asks World for the things on the ground.** Its plan 0023 has a
  catalog of 76 kinds and the requests W1 to W23. The files are pinned
  by a lock (the commit of World, the hash of the order, the SHA-256 of
  each file).
- **For the scene of the owner** it has the place of each thing in its
  own frame (meters, from the center of Bãi Trước): the statue at
  (1159.87, 1893.39) on ground of 138.33 m, the lighthouse at (402.21,
  1056.5) on ground of 173.11 m, the road to the lighthouse (2,802 m),
  1,994 bàng trees and 909 coconut palms. The outlines of the buildings
  have no heights.
- **Budgets:** 300,000 triangles and 600 draw calls at Low; a far
  scooter in 500 triangles (World gives about 4,000 today); a house in
  40,000, 3,000 and 300; a coconut palm in 12,536 and 204, a bàng tree
  in 16,200 and 420 (a tree comes from World only with the same look in
  the same triangles or fewer).
- **Faults that it found in World:** a person with a prop does not pass
  the check of the factory; the mid and far levels of a person stand 1
  to 2 cm too high; two kinds of hair have no far level; the scooter
  has no side stand; no outdoor unit of an air conditioner.
- **A conflict in its documents:** who owns the blueprints. The owner
  now says: the projects prepare the blueprints and the edits.

### 3.3 Phượt

- **One model: the traveler** (a person, with or without a vehicle), in
  three places: the avatar (mid), the rider on the map (far, about 300
  KB), and the profile.
- **The customization is on the client.** The kit (the bodies with
  their shapes, the hair, the skins, the clothes) lets a change show in
  some milliseconds, with no build. A build happens only after a save.
  The result must be the built model within 1 mm.
- **Its complaints are about time, not shape:** the first build took
  12 to 19 s at the edge; each deploy of World builds each file again;
  the files have no compression; a cache showed the old vehicle after a
  change.
- **It wants from a van** its length and its height, for the router.
- **Vehicles:** a fixed list (car, camper, motorcycle, scooter,
  bicycle, and 12 vans). It did not ask for more makes, colors or
  racks.

### 3.4 DIY

- **It does not use World, and it cannot draw a GLB.** It draws SVG on
  the server from a list of simple solids (box, cylinder, prism, face,
  hull), with fixed cameras. An icon is about 100 bytes.
- **70 kinds**, each with one typical size in inches and its source. A
  kind is stretched to the size of the item.
- **A kind has the details of the real model:** the doors and the
  handles of a fridge, the knobs of a range, the terminals of a
  battery, one cable hood for each port of a busbar.
- **Tags:** a point on a face where a number is on the real thing (the
  label of the energy, the label of the watts).
- **Most of its values are about energy, not shape.** The shape comes
  from the kind, the size, and a few counts (the ports of a busbar).
- One VM of 128 MB serves all its users.

### 3.5 Humans Must Die

- **"The game needs no art files."** Each shape is made in JavaScript,
  merged, with a color at each point, and drawn in batches (2 draw
  calls for all the buildings). It has no loader of glTF and no images.
- **Its things are very small on the screen**, and there are many: 14
  buildings for each cell, 48 fighter jets, 16 carriers, 96 ships, 320
  wind turbines.
- **The Earth** is a Goldberg grid (40,962 cells at the default level)
  that the client makes itself. The server sends one byte for each cell
  and each value, and the surface changes while the game runs (craters,
  fire, ash). The land mask is Natural Earth at 1 degree; the relief is
  noise.
- **What a better Earth can be**, from its documents: not found, but
  for a shield. So the open part is the data of each cell (real relief
  in the place of noise), not a mesh from World.
- Police cars, ambulances and fire trucks are only lights: "a vehicle
  is too small to see".

### 3.6 Tre

- **Its rules are against a mesh file:** "Every house, tree, animal,
  and person is made in code ... not drawn"; "No mesh is made by hand";
  each thing comes from a seed while the game runs.
- **The ground stays a grid:** "the grid is the math, and it stays". A
  house too, because the child takes it apart piece by piece.
- **A figure** is rigid boxes on pivots (64 parts for a person at the
  most), with moves from code, and all figures are 3 draw calls.
- Its documents do not speak of a move away from voxels. The candidates
  are the people, the animals and the plants.

## 4. The design

### 4.1 What the probe says

1. **Only two of five projects take a GLB.** The other three need the
   same model in another form: simple solids (DIY, Tre), or a small
   mesh with a color at each point (Humans Must Die).
2. **Only one project needs the realistic near level** (Vũng Tàu, for
   its landmarks). That is the build that takes minutes. All the other
   needs are small, and must be fast.
3. **The time that hurts is the time of a repeat:** a file that World
   made before, and makes again after a deploy.
4. **The things with large counts are few kinds:** houses, trees,
   figures, vehicles. A project needs a kit or a set of variants, not
   one file for each thing.
5. **No project asked World for the ground.**

### 4.2 One description, many outputs

A request first becomes a **description**: the parts of the model, each
with its simple shapes (the edits), its material roles, its joints, its
ports and its tags. A rule makes it in milliseconds, with no mesh. This
is the drawing that `draw_house` and `draw_building` give today.

A project then takes the output that it can use:

| Output | What it is | Cost | For |
|---|---|---|---|
| `drawing` | The description as JSON | Milliseconds | An agent that checks or changes a request |
| `solids` | The shapes that add, as a list of boxes, cylinders, prisms and outlines with their colors, in the units and the axes that the project asks for | Milliseconds | DIY (its SVG), Tre (its boxes) |
| `flat` | A small closed mesh in a budget of triangles, flat faces, a color at each point, no image; as a GLB or as plain arrays | Seconds | Humans Must Die, Tre, the far levels of Vũng Tàu and Phượt |
| `glb` | The mesh at the near, mid and far level, with images for a model from edits | Seconds for a model of a rule; minutes for a large model from edits at near | Vũng Tàu, Phượt |
| `kit` | The parts that a client joins itself (bodies with their shapes, hair, clothes) | Built one time | Phượt; later the people of Vũng Tàu |
| `set` | The variants of one request by a seed | One build for each variant | Houses, trees, crowds |

So World does not build each model in each form: a project that draws
boxes never pays for a mesh, and a project that needs 2,193 houses
gets a set of variants and puts them itself.

### 4.3 Three speeds, and a store that stays

| Speed | What | How World keeps it fast |
|---|---|---|
| Now (ms) | A description, the solids, a change on a kit | No build |
| Soon (s) | A model of a rule, a flat mesh | A build in the request |
| Later (min) | A large model from edits at near | A build one time, then the store |

- **The store keeps a file by the hash of its order and the version of
  its rule**, not by the commit of World. A deploy that does not change
  a rule keeps its files. (Today each deploy builds each file again:
  the complaint of Phượt.)
- **After a change of a rule**, World gives the old file while it
  builds the new one, and says so in the answer.
- **A line with two classes:** a request of a person who waits (the
  avatar of Phượt) goes before the batch of a release (the 76 kinds of
  Vũng Tàu).
- **Compression** of each file in the answer.
- **Erlang:** each build is a process of the node; the gate of plan
  0011 limits the large builds by memory; a second node adds its
  workers (plan 0012). The mini PC is the first node, and a second
  machine joins it when the line is long.

### 4.4 Who owns what

| World owns | A project owns |
|---|---|
| The rules: a house, a building, a street, a vehicle, a person, an animal, a plant, an appliance, the field of the edits | Its requests: the words of a rule, a blueprint in data, a drawing of edits |
| The outputs and the store | The list of its orders, and the lock of its files |
| The checks of a request, with the path of each error | The look: materials, light, palette, ink |
| | The place of each thing in its world |

A real thing of one project (the statue of Vũng Tàu, a hotel of Quang
Trung) is data of that project. The models of the catalog of World stay
as a reference; no test builds them (the commit `b6905ce`).

## 5. What each project can prepare now

| Project | It prepares | World must add first |
|---|---|---|
| Vũng Tàu | Its orders, as now. For each real building: the request of `World.Town.Building` with photos. For each landmark: the drawing of edits. For houses: a set of variants for each kind of lot | The fixes of section 3.2; far levels in the budgets; trees in the budgets of the game |
| Phượt | Nothing new: its URLs stay | The store that stays, compression, the sizes of a van in the answer (done: the `size` of the receipt of an order) |
| DIY | For each of its 70 kinds: the kind, the size, the details, the tags | The rule of an appliance, and the output `solids` |
| Humans Must Die | The list of its shapes with the size on the screen and a budget of triangles for each | The output `flat` as plain arrays, with a light at each point for the windows |
| Tre | Five things for a trial: two figures, an animal, a tree, a prop | The output `solids` on a grid, and `flat` |

## 6. Steps

1. **The guide for a project** (`docs/requests.md`): how to write a
   request, check it and build it. Done with this plan.
2. **The output `solids`** for a drawing and for an order. Done
   (`World.Solids`, the file `solids` of an order, `HASH.solids.json`):
   the shapes of a drawing from edits with no build (a building of 80
   shapes: 16 KB in 4 ms), and one box for each part and material of a
   model of a rule (a scooter: 1.6 s, with its build at the far level).
   Open: the units and the axes of the project, and the tags of a part
   (a point on a face, for DIY).
3. **The output `flat`. Done** (`World.Flat`, the file `flat` of an
   order at each level, `?triangles=N`): one mesh, a color at each
   point, no image. A scooter at the far level: 4,088 triangles, and 500
   with a budget (58 KB; 14 KB in gzip). A house of a village at the
   far level: 1,706 triangles, and 928 with a budget of 600 (the posts
   and the bars are many small parts). Open: a smaller file (colors and
   normals in fewer bytes), and a light at each point for the windows.
4. **The store that stays. Done** (`World.Files`, `World.Line`, the
   routes `/o/` and `/m/` of `World.Service`): a file is kept by the
   hash of its order, with the version of the code of World that built
   it; a file of an older version goes out at once and is built again
   one time; each file has a copy in gzip; the line has two classes. A
   van at the mid level: 6.2 s the first time, 0.18 s after it.
5. **The rule of an appliance. Done** (`World.Home.Appliance`, the MCP
   tool `draw_appliance`): 18 kinds, each a body of the size of the
   request with the details of the real thing, in about 1 s at the mid
   level. Open: the other kinds of DIY (its catalog has 70), a model of
   one maker (the front of each power station), and doors that open.
6. **The faults of Vũng Tàu** (section 3.2), and the far levels in
   their budgets. Done:
   - A person stands on z = 0 at each level (with shoes it was 1 to 3
     cm above the ground at mid and far: the shoes are only a color on
     the feet there, so the soles of the feet now go down to the
     ground).
   - A person at far has the form of its hair (each kind, in 80
     triangles at the most), so it is as high as at near (it was 1.2%
     short) and long hair is long; the eyes have 24 triangles (172
     before). A person at far is about 1,550 triangles.
   - The scooter has a side stand (the joint `side_stand`).
   - A person with a thing in a hand, and the indoor unit of the
     catalog (it hangs on a wall), pass the check of an order.
   - The outdoor unit of a split air conditioner is a kind of
     `draw_appliance` (`ac_outdoor`, and `ac_indoor`).

   - The budgets of the game: the file `light` of an order (a
     primitive for each role, no image) takes `triangles` and `wrap`.
     A scooter at far is 500 triangles with a wrap (it was 4,120; a
     collapse alone breaks it into pieces, so the wrap makes one
     closed skin first). A person at far is about 1,550. A house of
     `lot_house` at far is 124, and a house of `tube_house` 276.
   - The blueprint `plant` (coconut, banana, bamboo, frangipani). A
     coconut palm at far is 204 triangles with `triangles=204`.

   Open: the look of the 14 kinds of trees of the game (its plan 0020)
   from World, with the near level in its budget (a coconut palm at
   near is 30,004 triangles; the game has 12,536), and a bàng tree
   from a rule (the bàng tree of World is one drawing of edits).
7. **The server on the mini PC. Done in World** (`docs/factory.md`,
   "The server on a computer"): the native server has each route that
   the Worker had, the pages of the site, the store on its disk and the
   line. Open: the tunnel and the start of the server on the mini PC
   (the owner), and a release with no `mix`.
8. **The Earth of Humans Must Die:** real heights and kinds of land for
   the points that the game sends (section 7.2). Done for the heights
   (`World.Earth`, `POST /earth/heights`): ETOPO1 of NOAA at a quarter
   of a degree (1.7 MB in `priv/earth`), 40,962 points in 21 ms, and
   one byte for each cell is 41 KB. Open: the kind of land (ice,
   desert, forest) from a real source.
9. **The trial of Tre** (section 7.1).
10. **The small models of Humans Must Die. Done** (`World.Mini`, the
    MCP tool `draw_mini`): 26 kinds (9 buildings, 3 aircraft, 5 ships,
    5 vehicles, a wind turbine, 3 trees), each at most 12 thick shapes
    with the look `flat`. The file `flat` at the far level is about
    220 triangles and 6 KB in gzip (the 26 files: 157 KB), each built
    in less than 1 s. The cells of a sculpture can be 10 m (they were
    1 m at the most), for a ship of 300 m. Open: a light at each point
    for the windows, and more kinds when the game asks for them.

## 7. The answers of the owner (2026-11-15)

- **Tre:** "Tre's rules were made by me, so I can change them. I chose
  Voxel so models could be made by code, as Tre runs on the browser,
  but I do want to see if World can build models better looking (as I
  don't like Voxel look), then I can changes the rules. Tre uses
  three.js so it can use World models."
- **Humans Must Die:** "the player plays from outer space against a
  region on Earth. I let you decide how you want to handle the Earth,
  as long as the game can run on mobile phone (we can assume high end
  phones for now)."
- **DIY:** "DIY can build a converter to convert GLB to SVG if it needs
  to. World keeps making GLB models."

So each project takes a GLB. The output `solids` stays as a cheap view
of a drawing, but no project waits for it. The output `flat` is a GLB
too: a small mesh with a color at each point.

### 7.0 Requests and edits, not rules for each model

The owner (2026-11-15), after the rules of sections 6 and 7.1: "We can
fix them, but we can't fix everything. What I would like for World to
have is the ability to be able to take requests and create and edit any
models. That is, Phuot can request World for a coconut palm with
specifications. Phuot will check World's output, and if it see issues,
will issue edit to World to edit. World should be able to handle those,
instead of trying to predict and pre build those models."

So the work changes direction. World does not get a rule for each kind
of thing that a project can want. It gets these abilities:

1. **An edit of an order. Done** (`World.Orders.Edits`, `POST
   /orders/HASH/edits`, the MCP tool `edit_order`): `set`, `remove` and
   `insert` at a path of the full order, the check of the new order,
   its parent and its history in the store.
2. **The numbers of a rule in the request. Done for a plant:** the
   option `numbers` of the blueprint `plant`. A palm of 9 m with 14
   fronds and a lean of 20 degrees, then four edits (32 fronds, a lean
   of 7 degrees, the trunk of the species, lighter leaves): a new order
   in 0.5 s, and its near level in 2 s. Open: the same for each other
   rule (the numbers that are fixed in the code of a house, of a
   vehicle, of a thing of a yard).
3. **Any model from free edits.** The blueprint `drawing` takes any
   shape, and an edit of the order changes, adds or removes a shape (a
   jar gets higher, with two ears and a band, in four edits). The check
   of a model from edits no longer refuses a thing that stands (its
   base is as high as a cell of its far level).
4. **Open:** the drawing of a model of a rule as a file of its order,
   so that a project can take the model into free edits when the
   options of the rule are not sufficient; a picture of a model from
   the server, so that a project with no viewer can look; and edits of
   one order from two projects at the same time.

The rules that exist stay as a fast first answer. A new rule is made
only when many requests of the same kind show that it saves time.

### 7.1 Tre: a trial of the look

Step T1 (done): a sheet of twelve models that World has and that fit
the content of Tre (a buffalo, a chicken, a duck, a dog, a carp,
bamboo, a banana plant, a tree, a woman with a nón lá, a basket boat in
two looks, a house). It shows three looks: real, soft, and flat faces.
The owner chooses the look.

The owner (2026-11-15): "Tre is about the old Vietnam. Buildings there
have different look than what World currently has, so World need to
support them. ... I want real, soft faces, with kids. There are a lot
of kids in that game."

Step T2 (in progress):

- **Children. Done:** a person has an age from 1 to 90 years, from the
  shapes of a baby and of a child of MakeHuman (48 targets, CC0, 1.7
  MB). A girl of 7 is about 1.2 m high, with the proportions of a
  child.
- **The clothes of old Việt Nam. Done** (`World.Sewing`): a loose tunic
  of homespun cotton with a round neck that hangs from the waist, with
  long sleeves (`world_ao_canh`) or short sleeves (`world_ao_coc`),
  wide pants to the middle of the calf (`world_quan_ong_rong`) and
  short pants (`world_quan_dui`). An order gives the brown of the dye
  (`clothes_colors`), and a person with no shoes has bare feet. Open:
  the cloth follows the chest of the body too much, the hem of a
  garment is not a straight line, a scarf for the head, and a softer
  face.
- **The buildings of old Việt Nam. Done for a house:**
  `World.Village.House` makes a house of a village from a few words: a
  house on stilts with a roof of thatch, or a house of three or five
  bays on a low base with a roof of tiles that curves, with its corners
  lifted. The mid level of a house builds in 9 to 13 s. A communal
  house (đình) and a school are requests of the same rule (more bays,
  tiles, a larger curve); a rule of their own is open.
- **The things of a yard. Done** (`World.Village.Yard`, the MCP tool
  `draw_village_thing`): a round well of brick, a fence of bamboo of a
  length, the gate of the village, a haystack, a bridge of bamboo
  poles, a jar for water. Each builds in 6 to 12 s at the near level.
- **The buffalo calf (nghé). Done:** the species `buffalo_calf` of the
  blueprint `animal` (0.8 m at the withers, long legs, a large head,
  horns that only start), with each move of the water buffalo.
- **The areca palm (cau). Done:** the species `areca` of the blueprint
  `plant`: the rule of the coconut palm with the numbers of its species
  and a green crown shaft (10,542 triangles at near, 508 at mid).
- **Open:** tools and toys for the hands (a hoe, a basket, a kite, a
  flute), a rule of its own for the đình, and the moves of each
  thing in the game.

### 7.2 Humans Must Die: the Earth

The decision of World:

1. **The game keeps its grid and its live state.** The ground changes
   while the game runs (a crater, fire, ash), so it cannot be one mesh
   file. The client draws it from its cells, as now.
2. **World gives real data for each cell**, in the place of noise. The
   game sends the points of its cells (latitude and longitude), and
   World answers one or two bytes for each point: the height of the
   land and of the sea floor, and the kind of land. At the default
   level (40,962 cells) that is 41 to 82 KB: the size of the files of
   the game today. So a phone does the same work as now, and the Earth
   has its real mountains, coasts and deserts.
3. **A finer patch for the region in play** comes later, if the look
   from the play height needs it: the same answer for more points
   near one place.
4. **The things on the Earth are flat GLB files**: the buildings, the
   vehicles, the turbines, the trees, each in a small budget of
   triangles with a color at each point and a light for the windows.
   The client loads each one time and draws its copies in a batch.

World needs a source of heights of the Earth for step 2 (a public
grid, for example ETOPO of NOAA), with its license in `CREDITS.md`.
