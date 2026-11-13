# Plan 0012: a world of sites, with models that look real

Status: In progress (the owner, 2026-11-13: "The models look rather
cartoonish. This World project would need to serve models for
Vung_Tau, Phuot, DIY, Humans_Must_Die, and maybe Tre. Sony Dreams is an
amazing platform to let players create games, with any kinds of models
that can be created quickly and beautifully in the PS4. I want World to
be like that. And because it's in Erlang, I want to utilize the
distributed nature to have a World like a real world, from which each
construction site has multiple workers/processes assigned to sculpture
the model to the requests. The amount of workers depend on how many
constructions going on at once. [...] Please make my dream project come
true, with quality and performance!").

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
| D6 | **The crew of a site.** A sculpture is a site. Each stage gives its jobs to the workers of its site with one call (`World.Crew.map`); no stage starts processes of its own. A worker takes the next job from its site when it is free. | One place decides who works where. |
| D7 | **The node gives its workers to the sites in equal parts.** The node has as many workers as schedulers (a number of the configuration). With one site, all of them work there; with two sites, half each; a site with no job now lends its workers. A change of the sites moves the workers at their next job. | The owner: "The amount of workers depend on how many constructions going on at once." |
| D8 | **A second node adds its workers.** A node joins another node (`World.Crew.join/1`); its workers take jobs from the sites of that node as its own workers do. The two nodes must have the same code (a hash of the modules). A node that goes away gives its jobs back to the site. | Erlang sends a function and its data to a process of another node as to a local one. |
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
- **R5.** With two sculptures in work, each has half of the workers of
  the node (within one) while both have jobs; the bytes of each model
  are the same as when it is built alone.
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

## 10. The measure

(the steps write here)
