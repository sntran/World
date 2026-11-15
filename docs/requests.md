# How a project asks World for a model

This guide is for a person or an agent of another project (Vũng Tàu,
Phượt, DIY, Humans Must Die, Tre). It tells how to write a request,
check it, and build it. The full rules are in `docs/format.md`,
`docs/skills.md` and `docs/factory.md`; the reasons are in
`docs/plans/0019-world-serves-the-projects.md`.

## The idea

World is an engine. It has rules; a project has requests. A project
does not add its things to World: it keeps its requests in its own
repository, and asks World to build them.

- **World owns:** the rules, the checks, the builds, the files.
- **A project owns:** its requests, the list of its orders, the look
  (materials, light), and the place of each thing in its world.

## The three kinds of request

Use the first kind that can make the thing.

| Kind | When | What you write |
|---|---|---|
| 1. The words of a rule | The thing is of a family that World knows | The options of a blueprint by its name |
| 2. A blueprint in data | A family of things of your project, with options | `name`, `doc`, `sources`, `params`, `drawing` (`docs/skills.md`, "How a project sends a blueprint") |
| 3. A drawing of edits | One thing with a free form: a statue, a boat, a hat | Parts, each a list of simple shapes that add, take away or paint (`docs/format.md`, "A sculpture") |

The blueprints by name: `person`, `traveler`, `exercise`, `animal`,
`plant`,
`scooter`, `motorcycle`, `car`, `bicycle`, `van`, `house`, `lot_house`,
`tube_house`, `tower`, `statue`, `extrusion`, `strut`, `l_track`.
`GET /blueprints` (or the MCP tool `get_blueprint`) gives the options
of each, with the type, the default and the range.

Some rules give a drawing from a few words, for the kind 3:

- a house of a street: the MCP tool `draw_house`, and `plan_street` for
  a row (`docs/format.md`, "A house and a street from rules");
- a building (a hotel, an office, a villa): the MCP tool
  `draw_building`;
- a house of a village of old Việt Nam (posts, a porch, stilts, a roof
  of thatch or tiles that curves): the MCP tool `draw_village_house`;
- a thing of the yard of such a village (a well, a fence of bamboo, a
  gate, a haystack, a bridge of bamboo, a jar): the MCP tool
  `draw_village_thing`;
- an appliance of a home from its kind and its size (a fridge, a
  range, a battery, a busbar, the two units of an air conditioner and
  12 more): the MCP tool
  `draw_appliance`;
- a very small model for a view from far (a building, an aircraft, a
  ship, a vehicle, a wind turbine or a tree in about 220 triangles):
  the MCP tool `draw_mini`. Ask for the file `flat` of its order.

A person (`person`) has an age from 1 to 90 years: a child has its own
size and proportions. The clothes of a village of old Việt Nam are
items of `clothes`: `world_ao_canh` (a loose tunic with long sleeves),
`world_ao_coc` (short sleeves), `world_quan_ong_rong` (wide pants) and
`world_quan_dui` (short pants), each with its color in
`clothes_colors`. With no shoes in `clothes`, the person has bare feet.
The animal `buffalo_calf` is the calf of a water buffalo, and the plant
`areca` is the areca palm.

## An order

An order is JSON. Each key but `blueprint` is optional.

```text
{"blueprint": "scooter",
 "options": {"front_tire": "80/90-14"},
 "colors": {"paint": "#1d3b5a"},
 "joints": {"stand": 1}}
```

A drawing is an order of the blueprint `drawing`:

```text
{"blueprint": "drawing", "options": {"drawing": {...the drawing...}}}
```

The same order gives the same files. Its hash is the name of its
files.

## Check, then build

1. **Check.** The MCP tool `check_order` (or `check_drawing`,
   `check_blueprint`) gives the full order with each default, or each
   error with its path and its rule. Correct the request and check
   again. A check takes milliseconds.
2. **Look at a small level first.** Build the far or the mid level, and
   look at it. Build the near level one time, when the mid level is
   right.
3. **Build.** From a checkout of World:

   ```sh
   mix.com world.order ORDER.json --dir OUT
   ```

   It writes `HASH.glb` (near), `HASH.mid.glb`, `HASH.far.glb`,
   `HASH.parts.json` (the parts, the joints, the ports, the sizes),
   `HASH.receipt.json` (the order, the sources, the licenses) and the
   log of the build. With the server of World, `POST /orders` gives the
   URLs of the same files (`docs/factory.md`).
4. **Keep the order and a lock** in your repository: the commit of
   World, the hash of the order, and the SHA-256 of each file. Do not
   keep a model of your project in World.

## From the server

With the server of World (`https://world.mkfifo.com`):

- `POST /orders` keeps an order and gives the URLs of its files:
  `/o/HASH.glb`, `/o/HASH.mid.glb`, `/o/HASH.far.glb`,
  `/o/HASH.parts.json`, `/o/HASH.receipt.json`, `/o/HASH.solids.json`.
- An order of a blueprint by name can be a URL:
  `/m/van.mid.glb?model=transit_148`.
- The size of a model (`[wide, long, high]` in m, with each part that
  stands out) is the `size` of its receipt:
  `/m/van.receipt.json?model=transit_148` gives `[2.408, 4.946,
  2.3308]` for the first van of the list.
- The first request of a file builds it; each request after it reads
  it from the store (0.2 s). The files stay after a deploy of World.
- A tool that gets all the files of a project adds `?class=batch`, so
  that a person who waits for one model goes first.
- Ask for gzip (`accept-encoding: gzip`): a GLB is about 3 times
  smaller.

## What to prepare for a thing

- **A name and a kind.**
- **The sizes, each with its source.** A size with no source is a
  guess: say so.
- **For a real thing, about ten photos**, from more than one side. One
  photo is not sufficient. A size from an article must agree with the
  photos.
- **The parts that move** (a door, a wheel, a stand): each is a joint
  with a name.
- **The points that other things use** (a seat, a hook, a terminal):
  each is a port.
- **The material role of each part** (`paint`, `glass`, `brick`, ...):
  your project gives each role its material.
- **The levels that you need, and a budget of triangles for each.**

## What a build costs

| Request | Time on four cores |
|---|---|
| A check, or a drawing from a rule | Milliseconds |
| A model of a rule (a vehicle, a person, a house of `lot_house`) | Less than a second to some seconds |
| A model from edits at the far or mid level | Seconds to 2 minutes |
| A small building from edits, three levels | 2.5 minutes |
| A large building from edits (a hotel of 40 m), three levels | 7 minutes |

So build before a release, or keep the files: do not ask for a large
model from edits while a person waits.

## Many things of one kind

Do not order one file for each house or each tree. Order a set of
variants (`POST /sets`: one order with `count`, `seed` and `vary`), and
put each variant many times in your world.

## A planet

A project with a planet (Humans Must Die) keeps its own grid and its
own state. It asks World for the real height at each point of its
grid: `POST /earth/heights` with `{"points": [[latitude, longitude],
...]}` gives one whole number of meters for each point (40,962 points
in 21 ms). From a checkout: `World.Earth.heights/1`. Put the source of
the answer in the credits of the project.

## A small file, for many copies or for a project with no images

- **`solids`** (`HASH.solids.json`, the file `solids` of an order): the
  simple shapes of the model as a list, for a project that draws boxes
  or SVG itself. For a drawing from edits it needs no build: a building
  of 80 shapes is 16 KB in 4 ms. Each solid has its `shape` and `size`
  (as in the data of an edit), its place `at`, its axes `x`, `y` and
  `z`, its `mode` (`add`, `subtract`, `paint`), its `color` and its
  `role`. A model of a rule gives one box for each part and each
  material. The lengths are in meters, z is up, the front is to +y.
- **`flat`** (`HASH.flat.glb`, `HASH.mid.flat.glb`,
  `HASH.far.flat.glb`): the model at a level as one mesh with a color at
  each point, no image and no skin, for a project that draws many small
  things in one batch. With `?triangles=N` the mesh has at most N
  faces, or as few as World can make: a scooter at the far level is
  4,088 triangles, and 500 with `triangles=500` (58 KB, 14 KB in gzip).
  A model of many small parts does not go under some hundreds of
  triangles: add `?wrap=1` (one closed skin round the whole model), or
  make a request with few shapes (the MCP tool `draw_mini` gives such
  a request for 26 kinds of things).
- **`light`** (`HASH.light.glb`, `HASH.mid.light.glb`,
  `HASH.far.light.glb`): as `flat`, but with a primitive for each role
  of the model and no color at the points, for a project that gives
  each role its own material. A scooter for a row of parked scooters:
  `/m/scooter.far.light.glb?triangles=500&wrap=1`. A coconut palm far
  away: `/m/plant.far.light.glb?species=coconut&triangles=204`.
