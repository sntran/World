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
| Phượt | Nothing new: its URLs stay | The store that stays, compression, the sizes of a van in the answer |
| DIY | For each of its 70 kinds: the kind, the size, the details, the tags | The rule of an appliance, and the output `solids` |
| Humans Must Die | The list of its shapes with the size on the screen and a budget of triangles for each | The output `flat` as plain arrays, with a light at each point for the windows |
| Tre | Five things for a trial: two figures, an animal, a tree, a prop | The output `solids` on a grid, and `flat` |

## 6. Steps

1. **The guide for a project** (`docs/requests.md`): how to write a
   request, check it and build it. Done with this plan.
2. **The output `solids`** for a drawing and for an order, with the
   units and the axes of the project, and the tags of a part.
3. **The output `flat`** for any order: a budget of triangles, a color
   at each point, as a GLB and as plain arrays. (A model from edits has
   the look `flat` today; a model of a rule does not.)
4. **The store that stays:** a version for each rule, the old file
   while the new one builds, compression, the two classes of the line.
5. **The rule of an appliance** (`World.Home.Appliance`), as the rule
   of a building: a kind, a size, and details from a few words.
6. **The faults of Vũng Tàu** (section 3.2), and the far levels in
   their budgets.
7. **The server on the mini PC:** the release, the tunnel, the store on
   its disk, the measure of the line.
8. **The Earth of Humans Must Die:** real relief for each cell of its
   grid, as data. It needs a source of heights of the Earth and the
   word of the owner on what "better" is.

## 7. Open questions for the owner

- **Tre:** its own rules say that each thing is made in code from a
  seed. Is the trial of five things the right first step, or do its
  rules change first?
- **Humans Must Die:** is a better Earth real relief and real coasts on
  its grid, or more than that (cities, clouds, a look from the ground)?
- **DIY:** does it keep its SVG from solids, or does it want pictures
  that World draws (12 views of each kind)?
