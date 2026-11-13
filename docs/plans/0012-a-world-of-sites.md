# Plan 0012: a world of sites, with models that look real

Status: Done (2026-11-13), but for a part of R8 (three of four models,
no fishing boat) and the 15% of R1 for the house (17%). Section 10 has
the measure. (The owner, 2026-11-13: "The models look rather
cartoonish. This World project would need to serve models for
Vung_Tau, Phuot, DIY, Humans_Must_Die, and maybe Tre. Sony Dreams is an
amazing platform to let players create games, with any kinds of models
that can be created quickly and beautifully in the PS4. I want World to
be like that. And because it's in Erlang, I want to utilize the
distributed nature to have a World like a real world, from which each
construction site has multiple workers/processes assigned to sculpture
the model to the requests. The amount of workers depend on how many
constructions going on at once. [...] Please make my dream project come
true, with quality and performance!"; and then, on the word
distributed: "I actually meant running the actor model and lightweight
processes, with Elixir `Task` and `Stream`, but actual distributed
nodes help too. I want to be able to build models fast, and can scale
up if needed.")

Depends on: plan 0011 (any list of edits builds, the gate, the bench),
plan 0010 (the maps), plan 0008 (the tree of bricks), plan 0001 (the
people and the census).

## 1. Goal

A project sends some edits and gets a model that looks like the real
thing, fast. The work of each sculpture is done by a crew of worker
processes at its site. The node gives its workers to the sites that
work now, in equal parts, and a second Erlang node adds its workers to
the same sites.

## 2. What the owner asked

1. The models of plan 0011 look like toys. They must look real.
2. World serves the models of five projects.
3. A model is made quickly and looks good, as in Dreams.
4. Each construction site has many worker processes; how many depends
   on how many constructions work at one time; World uses distributed
   Erlang.
5. Quality and performance.

## 3. The state before this plan

### 3.1 The five projects (read on 2026-11-13)

| Project | What it draws | The look it wants | Uses World now |
|---|---|---|---|
| Vũng Tàu | A first-person game in Godot 4, on real streets. | Real: "a model has the shape of the real make", true to size, a budget of triangles for each level (a house: 40,000, 3,000 and 300). About 90 kinds in its plan 0023 (scooters, vans, boats, tube houses, people, landmarks), thousands of buildings, and builds while the game runs (its plan 0025: 8 workers and 120 s for a house at most). | Yes, on a branch: a scooter, a fan, seven people. |
| Phượt | A traveler on a vehicle, on a map (three.js). | A person with the larger head of a game, in a safe pose. | Yes: its one model comes from World. A first build takes 12 s to 19 s, the files are not compressed, a deploy of World builds each model again. |
| DIY | Pictures in SVG that the server draws, two fixed cameras. | "A picture that an artist drew": warm colors, lines of ink. 69 kinds of items at true size. | No. |
| Humans Must Die | A low-poly Earth (three.js). | "Flat facets, flat colors, and no textures." 26 buildings, aircraft, ships, trees, as code. | No. |
| Tre | A voxel world in the style of Đông Hồ prints (three.js). | Three flat tones, no light in the shader, no request to another site. | No. |

So one model must have more than one look: real with maps (Vũng Tàu,
Phượt), and flat facets with flat colors and no textures (Humans Must
Die, Tre). The pictures of DIY are a render, not a model: out of scope
here (section 4).

### 3.2 Why the gallery of plan 0011 looks like toys

The page that shows a model has tone mapping, soft shadows and the
light of a room: the light is not the cause. The models are:

- **Few simple shapes.** 6 to 30 balls, boxes and tubes. A real thing
  has outlines (the side of a car, the section of a hull) that these
  shapes cannot make.
- **One flat color and one roughness for each part.** No grain, no
  weave, no wear at an edge, no dirt in a crease.
- **No occlusion.** A crease is as light as an open face. The red of
  the finish map is free for it.

### 3.3 The workers of a sculpture

- The people of the node (`World.Census`) do the tasks of a
  construction. A sculpture is one task of one sculptor.
- Inside that task, the stages of a sculpture start processes of their
  own (`Task.async_stream` in the tree of bricks, the collapse, the
  finish, the bake). The census does not know them, and no log shows
  them. Each call takes each scheduler, so two sculptures at one time
  take the node two times.
- The gate of plan 0011 lets half of the schedulers in as whole
  builds, and the others wait.
- Nothing runs across two Erlang nodes. The runtime of this project
  (one file, no `epmd`) starts a node with a fixed port
  (`-start_epmd false -erl_epmd_port`); two nodes on one machine need a
  module that gives each node its own port.
- The edge (a Durable Object of Cloudflare, WebAssembly, 128 MB, one
  scheduler) cannot join other nodes. A node with many cores (a
  container, a computer of the owner) can.

## 4. Out of scope

- The delivery for Phượt (compressed files, a cache that a deploy
  keeps): a plan of its own, after this one.
- The pictures of DIY (a render of a model as SVG or PNG from a fixed
  camera).
- An editor for a person. The edits come as data.
- A GPU.

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **Occlusion from the field, in the maps.** For each point of the mesh, some values of the field along its normal give how open the place is; the texels between the points take it by the weights of their triangle. It goes into the red of the finish map (glTF reads the occlusion there), so a model with maps has it with no more images. | The largest change of the look for the least work: a crease is dark in each app, with no light of the app. |
| D2 | **Dirt and wear from the same values.** `dirt` darkens and roughens the creases; `wear` lightens and smooths (for a metal: shows) the sharp edges, where the field inside is near. Numbers of the sculpture, 0 by default. | A real thing is not clean and not new. |
| D3 | **A surface for each edit:** a word (`wood`, `bark`, `brushed`, `cast`, `plaster`, `concrete`, `fabric`, `weave`, `leather`, `rubber`, `leaves`, `stone`, `rust`) with a scale. It is a relief, a change of the color and a change of the roughness, from a function of the place in the axes of the edit. Only the maps have it (as the raise of a paint): no more triangles. | Grain and weave are what a flat color does not have. The bake reads the field at each texel already. |
| D4 | **Outlines as shapes:** `extrude` (a closed outline in a plane, with a depth and a round edge) and `revolve` (a profile round an axis). The field of an outline is the true distance. | The side of a car, the section of a hull, a bottle, a baluster: real things are made from outlines. |
| D5 | **A look for each order:** `real` (the maps; by default) or `flat` (flat facets, the color of each face from the field, no textures). | Humans Must Die and Tre draw flat facets with no textures. |
| D6 | **The crew of a site.** A sculpture is a site. Each stage of its work is a stream of tasks, through one call (`World.Crew.map`): one light process for each job (`Task.Supervisor.async_stream`), linked to the site. | One place decides how many tasks a site has. The owner (2026-11-13): "running the actor model and lightweight processes, with Elixir `Task` and `Stream`". |
| D7 | **A stream has its part of the workers of the node.** The node has two workers for each scheduler (a number of the configuration): the tasks that it runs at one time for all its sites. With one site, a stream runs all of them at one time; with two sites, half; and so on. The part is counted at the start of each stream. | The owner: "The amount of workers depend on how many constructions going on at once." |
| D8 | **A second node adds its workers.** Two connected nodes with the same code (a hash of the modules) share their workers: a stream gives a part of its jobs to tasks of the supervisor of the other node. A job that the other node does not end is done on this node. | The owner: "actual distributed nodes help too [...] can scale up if needed". Erlang runs a task on another node as on this one. |
| D9 | **The census shows the crews,** and the log of a construction has an event when the crew of its sculpture changes. | A person who watches the world sees who works where. |
| D10 | **Each change keeps the bytes of a model the same** for one worker and for many, on one node and on two; and no stage is slower than before (the bench of plan 0011). | Performance is a measure, not a hope. |
| D11 | **Models that Vũng Tàu asks for, as the proof:** a basket boat (thúng chai), a low plastic stool, an outdoor unit of an air conditioner, a fishing boat (ghe). Each from edits, at true size from a source, next to a photo. The gallery of plan 0011 gets the new means too. | The proof of "real" is a real thing next to its photo. |

## 6. Requirements

- **R1.** A model with maps has occlusion: under the body of the car
  and in the creases of the robot, the red of its finish map is less
  than 60% of its value on an open face. The bake of the robot at near
  takes at most 15% more time.
- **R2.** A sculpture with a surface on each edit has a normal map and
  a color map that change inside one edit (a measure of the change in
  a patch of texels), and the same triangles as with no surface.
- **R3.** An outline with 32 points builds, closed, and its mesh is
  within one cell of the outline.
- **R4.** A model with the look `flat` has no texture and no image,
  one normal for each face, and passes the validator.
- **R5.** With two sites in work, a stream of each runs half of the
  workers of the node at one time; the bytes of each model are the same
  as when it is built alone.
- **R6.** With a second node of the same code, the workers of that
  node do jobs of a site of the first node (a count for each node),
  and the model has the same bytes. When the second node stops in the
  middle of a build, the build ends with the same bytes.
- **R7.** One sculpture alone is not slower than in plan 0011 (the
  robot at near: 5.4 s), and 8 at one time are not slower (25.8 s).
- **R8.** The four models of D11 are in the catalog, each with its
  sizes from a source and a shot next to a photo in this plan.

## 7. Steps

1. **Occlusion, dirt and wear** (D1, D2; R1).
2. **A surface for each edit** (D3; R2).
3. **The crew of a site, and the workers of the node in equal parts**
   (D6, D7, D9, D10; R5, R7).
4. **A second node** (D8; R6).
5. **Outlines** (D4; R3).
6. **The models of Vũng Tàu, and the gallery again** (D11; R8).
7. **The flat look, the measure and the documents** (D5; R4).

## 8. Acceptance criteria

- The tests of R1 to R6.
- The table of R7 in this plan.
- The shots of R8 in this plan.
- The full check passes on the tip of each push.

## 9. Open questions

- The delivery for Phượt, and the pictures of DIY: each needs a plan.
- Tre has the rule of no request to another site and no file of art:
  a model of World can only be a source for its own code. The owner
  decides if Tre uses World.
- **Speed past 4 cores.** About 13% of a build is in one process
  (section 10, step 3). The next work for "fast" is to make those
  parts streams too, then to measure on a machine with more cores.
- **The log of a construction has no event of its crew** (the second
  half of D9): the census has the crews, the log does not.
- **The models of plan 0011** (the car, the tree, the animals) still
  have their simple shapes. With outlines and surfaces, each needs its
  edits again from a real thing, as the three models of step 6.
- **The fishing boat** needs the lines of a real hull.

Plan 0013 takes the fishing boat, a real car and a real tree, and a
part of the speed.

## 10. The measure

One machine with 4 schedulers. It is slower than the machine of plan
0011 (the robot at near: 6.4 s to 7.0 s here before this plan, 5.4 s
there), so each number here is next to a number of the same machine.

### Step 1: occlusion, dirt and wear (R1)

How open a place is comes from the field along its normal: two near
distances (1.5 and 4 cells) at each fourth texel, two far ones (10 and
25 cells) at each sixteenth, and the texels between take the values of
the grid. The test (`test/world/sculpt_bake_test.exs`): at the foot of
a post on a slab, the red of the finish map is less than 60% of its
value on the open slab; dirt makes that place darker and more rough;
wear makes the edge of the post lighter and less rough.

| The bake at near | No look | Occlusion | Occlusion, dirt and wear |
|---|---|---|---|
| The robot | 3.58 s | 3.86 s (8% more) | 3.88 s |
| The house | 2.79 s | 3.26 s (17% more) | 3.51 s |

**R1:** the test passes; the robot is in the 15%, the house (large
flat faces, so many texels read the far distances) is at 17%.

The occlusion changes a model little in an app with a strong sun: glTF
uses it for the light of the sky only. The dirt and the surfaces
change the look more.

### Step 2: a surface for each edit (R2)

13 kinds (`World.Sculpt.Texture`): wood, bark, brushed, cast, plaster,
concrete, fabric, weave, leather, rubber, leaves, stone, rust. The test:
a box with the surface `wood` has the same mesh as with no surface;
its color map has more than 20 values on one face (1 with no surface),
its normal map more than 8, its roughness more than 3; the grain goes
along the long side of a plank; a mark smaller than 1.5 texels does not
show. The hammer at near: 1.1 s with a surface on each edit.

### Step 3: the crews (R5, R7)

The first crews of this plan were a pool of worker processes with
messages of their own (commit `fc9c4ae`). The owner then said what he
meant by distributed (2026-11-13): "running the actor model and
lightweight processes, with Elixir `Task` and `Stream`, but actual
distributed nodes help too. I want to be able to build models fast, and
can scale up if needed." So the crews are now streams of tasks
(`Task.Supervisor.async_stream/4`): one light process for each job,
linked to its site, and a stream runs its part of the workers of the
node at one time. They are 318 lines in the place of 573, and faster
than the pool:

| 8 models at near (`mix world.bench --at-once N`) | Before the crews | The pool | Streams of tasks |
|---|---|---|---|
| One at a time | 43.0 s, 2.67 cores at work | 42.0 s, 2.61 | 38.1 s, 2.63 |
| 8 at one time | 37.1 s, 3.73 cores at work | 34.9 s, 3.52 | 31.0 s, 3.56 |
| The robot alone | 6.9 s to 7.2 s | 6.9 s to 7.2 s | 6.8 s to 7.0 s |

Before the crews, each stage of each site ran two tasks for each
scheduler, so two sites ran two times that. Now the node has two
workers for each scheduler for all its sites: a stream of a site alone
runs 8 tasks at one time, with two sites 4 (`test/world/crew_test.exs`:
**R5 is met**). The ten models from edits have the same bytes as before
the crews. **R7 is met:** no build is slower, and 8 at one time are 16%
faster than before the crews.

The robot at near by the schedulers of the VM (`+S`), for "scale up if
needed":

| Schedulers | Time | Times as fast as one |
|---|---|---|
| 1 | 25.0 s | 1 |
| 2 | 10.9 s | 2.3 |
| 4 | 6.7 s | 3.7 |

From 2 to 4 schedulers the build is 1.6 times as fast, not 2: about
13% of the work of the robot is in one process (the join of the
regions, the last pass of the collapse, the places of the charts, the
figure, the file). With that part as it is, 8 cores give about 4.6 s
and 16 cores about 3.6 s (an estimate, not a measure). To scale past
that, those parts must be streams too: the open question of plan 0011.

### Step 4: a second node (R6)

Two connected nodes with the same code share their workers: a stream
gives a part of its jobs to tasks of the supervisor of the other node
(`Task.Supervisor.async_nolink/4` with `{World.Crew.Tasks, node}`), in
lanes, by the workers of each node. `test/world/crew_nodes_test.exs`
starts two VMs on one machine, each an Erlang node with no `epmd`
(`World.Epmd`). Of 20,000 small jobs of one site, the tasks of each
node do some. The dog at near has the bytes of the file of the catalog
three times: with the two nodes (in more than 10 looks at the other
node, it has tasks of the build), when the second node stops in the
middle of the build (its jobs are done on the first), and alone after
that. **R6 is met.**

The two nodes are on one machine with 4 cores, so the test proves that
the work is right, not that it is faster. The time with a second
machine is not measured. The jobs go to the nodes in fixed parts at the
start of a stream: a slow node keeps its part.

### Step 5: outlines (R3)

Two shapes: `extrude` (a closed outline with a depth and round edges)
and `revolve` (a profile round an axis), each with `smooth` (the
corners cut, so a few points make a curve). The field of an outline is
the true distance. The tests: an extrude of a rectangle is the box, a
revolve of a rectangle is the cylinder (to 1e-9); a gear of 32 points
and a bowl of 32 points build closed, each point of the mesh within a
cell of the shape. The random sculptures have outlines too. **R3 is
met.**

### Step 6: the models of Vũng Tàu (R8)

| Model | Size and its source | Edits | Near |
|---|---|---|---|
| `thung_chai_edits`: a basket boat | 1.8 m across (a travel source: 1.8 m or 2.2 m); 0.6 m deep (from photos: no source has the depth) | 8 | 16,000 triangles |
| `ghe_nhua_thap_edits`: a low plastic stool | 26 cm high, a top of 23 cm (the common stool: no data sheet found) | 9 | 8,000 |
| `cuc_nong_may_lanh_edits`: the outdoor unit of an air conditioner | 550 x 658 x 275 mm (the Daikin data books of the RXF25C and the RXP25M) | 18 | 10,000 |

The boat is a profile turned round its axis with the surface `weave`,
a rim of two rings of bamboo with lashings, a plank and a paddle. The
stool is its side view as an outline, cut to the same view from the
other side, with an arch under each side. The unit is a round box with
paints for the grille, the louvers and the seams, and rust at its foot.
Each passes the check of a model (it stands, and goes through a door).

**R8 is met in part:** three models of the four. The fishing boat
(ghe) is not made: a hull needs its lines (the sections of a real
boat), which no source of this plan has. The shots are next to no
photo in this plan: the owner compares them. The gallery of plan 0011
has surfaces, dirt and wear now; its car, its tree and its animals
still have the simple shapes of that plan.

### Step 7: the flat look (R4)

`"look": "flat"`: each face has its own three points, the normal of
the face and one color (the color of the edits at its middle); no
image at any level. `thung_chai_flat_edits` is the basket boat with
that look (1,200 triangles at near, 200 at far), and the validator of
glTF takes it. **R4 is met.**

### The requirements

| # | Result |
|---|---|
| R1 | Met for the robot (the bake takes 8% more time); the house is at 17% (the aim: 15%). |
| R2 | Met. |
| R3 | Met. |
| R4 | Met. |
| R5 | Met: a stream of a site alone runs all the workers, with two sites half. The part is counted at the start of each stream, not in the middle of one. |
| R6 | Met on one machine. The time with a second machine is not measured. |
| R7 | Met: 8 models at one time take 31.0 s (37.1 s before the crews). |
| R8 | Met in part: three of the four models; no fishing boat; no photo next to the shots. |
