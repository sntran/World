# The world

## The vision

The owner, 2026-11-12:

> I think my vision for World is very similar to Dreams: an engine
> which outside users can use to make any content and models. And do
> them fast!

So World is an engine for each user outside it, not only for the
projects of the owner:

- **Any content from a few simple things.** A user makes a model from a
  short list of edits: simple shapes that it adds, takes away or paints,
  with smooth joints (plan 0008), and joins the parts with ports and
  joints (`docs/format.md`). A user sends this as data (a blueprint, a
  drawing) over MCP; World checks it and builds it. No user writes code.
- **Fast.** The people of the node build each model as actors on the
  Erlang BEAM: the work of one model goes to many people at the same
  time, each with a small part of it, and only the work that a change
  needs is done again (plan 0007, plan 0008).
- **In a budget.** Each build has its limits (the people, the seconds,
  the triangles, the memory), as each sculpture of Dreams has its
  "thermometer".

## The factory and the people

The factory of World (`docs/factory.md`) takes an order and gives the
files of a model. In the world, people make the model, as in the real
world. The node of World (one Erlang node) is a city of people: each
person is a process. A job comes in, the node opens a construction, and
the construction hires people of the trades from the census of the
node. Each person makes one element at a time (a part of the model), and
the construction joins the elements into the model. Many constructions
run at one time and share the people (`docs/plans/0001-people-build-on-demand.md`).

The world is not a picture on top of the factory. Each thing in it has
a real thing of the computer behind it. A warehouse is a store of
files. A factory is where the code builds one family of things. The
clock is the wall clock. A driver really drives the vehicle on the road
from one place to the other. The files travel with it, and the store at
the end of the road gets them when the vehicle arrives. The replay shows
what happened, with the real times.

The world has no scale of its own. It makes the models of each project
of the owner, and each project takes what it needs. DIY takes the items
of a house, Vũng Tàu a city, Phượt the roads of a trip, Humans Must Die
a planet.

This document is the plan. The owner reads it and changes it before the
work starts. The code is the source of truth after that (`AGENTS.md`).

## The words

| Word | What it is |
|---|---|
| **World** | The node: its people, its constructions, its stores, its log and its clock. |
| **Node** | One Erlang node: a city of people, each person a process. At the edge, one Durable Object. |
| **Construction** | One build of a model by the people of the node, from its job to its model. |
| **Element** | The part of a node of the model that one person makes in one task. |
| **Census** | The people of the node, their trades, and the construction that holds each one. |
| **Trade** | What a worker makes: a mason, a joiner, a wheelwright, a mechanic, and the trade of each workshop. |
| **Place** | A building with a position: a warehouse, a factory, a supplier, a yard, the site of a customer. A place is a model of World (`World.Buildings`): people build it. |
| **Warehouse** | A place that keeps stock. Its size is the limit of its store. |
| **Factory** | A place with lines and stations, where the workers build one family of things: vehicles, wheels, seats, slabs, houses, clothes. A sub-order goes to the factory of its family. |
| **Supplier** | A place outside the world that gives a part the world cannot make: the data of MakeHuman, the drawings of a maker, a supplied part of an order. |
| **Road** | The way from one place to another, with its length in meters. A vehicle drives on it at its speed, and a person walks on it. |
| **Stock** | The parts and the models that are in a warehouse now, each with its count. |
| **Person** | A process of the node with a job and a trade, with one task at a time. Its body is a figure of World on the page of the world. |
| **Job** | What a person does: a worker of a trade now. Later: engineer, architect, driver, storekeeper. A job of the node is also a request for a model: an order, a level and a budget. |
| **Vehicle** | A model of World that moves parts: a van, a truck, a cart. A driver controls it, and it has a position on the yard at each time. |
| **Order** | A request for a model: the order of the factory (`docs/factory.md`). |
| **Plan** | The list of the tasks of a construction, from the tree of its assembly, with the trade of each task and what it waits for. |
| **Task** | One step of a plan for one person: make the element of a node. |
| **Budget** | The limits of a construction: its workers at one time, its seconds, its triangles. |
| **Event** | One thing that happened, with its time, its construction, its person, and its data. |
| **Log** | The events in the order of their time. The log is the truth of the world: the replay and the statistics come from it. |
| **Replay** | The world in 3D from the log: the people walk to the lots and work, and each model grows on its lot. |
| **Clock** | The wall clock. The time of a task is the real time the code took. |

## What is real

Each thing of the world is one thing of the computer. The table gives
the rule. A new thing in the world comes with its real thing, or it
does not come.

| In the world | In the computer |
|---|---|
| The node | One Erlang node: `World.Supervisor` and its children. At the edge, one Durable Object with the name `world`. |
| A person | A process (`World.Person`, a `GenServer`) with a job and a trade. Its name is its PID (`"<0.123.0>"`). Two people are two processes: they make two elements at one time. |
| The census | The process that knows each person, its trade and the construction that holds it (`World.Census`): the pool of the people of the node. |
| A construction | The process of one build (`World.Construction`): its plan, the people that it holds, the elements that they made, and its log. It joins the elements into the model at the end. |
| An element | The part of a node of the model that one person makes in one task: the triangles of its meshes (the pass of Wings, the real cost of a build) and its GLB alone. |
| The work of a task | The real work of the code: a person makes the triangles of the meshes of its element. The time of the task is the time of that code. |
| A warehouse | A store of files: the R2 bucket of the orders (`world`), the catalog in the release (`priv/models`), the memory of the VM (`World.Store`). |
| The log of the node | The events of each construction in the order that they come, each with an id (`World.Log.Server`); in the SQLite of the Durable Object at the edge (`World.Log.Store`). |
| A watcher | A process that gets the events of a construction, or of the world: the stream of a client over HTTP (`World.Stream`). |
| The clock | The wall clock of the VM. Each event has its real time. |

The replay shows the real log. A person that works on a task in the
replay is a process that ran that task, and an element that comes in
the model is the element that the person made. Nothing in the replay is
invented.

## The places

A place is a building. The materials of World make it: bricks and
concrete blocks, lumber studs, OSB, siding, metal panels, doors and
windows (`World.Buildings`, `World.Materials.Construction`). A place is an
order too: the people of the world build it from its materials, and the
log has its build. The places of the first world (a yard of factories,
warehouses and roads) went with plan 0001; its step 5 brings the places
back as blueprints in data, built one time by the people of the node.

| Place | What it has | Its size |
|---|---|---|
| A warehouse | Racks (`World.Framing.Builds`: strut channel, shelves), a dock, a yard. | The limit of its store, in files and in bytes. The racks show the stock: a full rack is a full store. |
| A factory | Lines with stations, a dock for the parts, a yard for the finished things. One factory for each family of things (below). | The number of its workers (processes) and the memory of its VM. |
| A supplier | A gate: the parts come from outside. | None. |
| The site of a customer | Where a delivery ends: Phượt, DIY, Vũng Tàu, Humans Must Die. | None. |

Plan 0002 (D6) brings the places back in data: `priv/places.json` has
the gate of the suppliers, the warehouse, the factory of the vehicles,
the workshop of the small things, the site of the houses and the
towers, and the hill of Núi Nhỏ for the statues (`World.Places`), the stock of the warehouse in
the units of a site (`World.Stock`), and the trucks. A skill gives the
takeoff of its task (`materials/2`): a band of courses its bricks, a
column or a slab its bags of cement and bars of rebar, a render its
bags of mortar, the paint its cans. The takeoff of the frame and of the
walls of a tube house agrees with the volume of the elements that the
people make.

Plan 0006 (D3, D4) gives a place its true ground: the hill of Núi Nhỏ
(`nui_nho`) has the height tiles of the Vũng Tàu game round the hill and
the cape of Nghinh Phong (`priv/terrain/nui_nho/`, a copy with no change,
in the frame of the game; `World.Terrain`), and two lots at their points
of the game: the top, where the statue of the game is, and the cape. A
statue goes to the top; its model has its place in the game (`"geo"`),
so the game can take it back. The ground of a lot is flat in its radius
and blends into the hill.

The haul (`World.Haul`) brings the takeoff of a task to the place of its
construction by truck (`World.Truck`), before the task starts. The
materials come from the stock of the warehouse when it is open and has
them; else a supplier brings them from the gate. A takeoff goes into the
loads of a truck (1,500 kg each). While the yard has no truck of its
own, the haul rents a truck of a supplier with its driver for each load.
A drive takes its world time at the speed limit of the yard (20 km/h):
from the gate to the site, 87 world seconds, 2 ms of the wall clock. A
construction with a haul and a place (the keys `haul` and `place` of its
job) asks for the takeoff of each task when the tasks that it waits for
are done (`parts_asked`), and gives the task when the haul tells it that
the loads are there (`parts_here`). The model is the same as with no
haul. `specs/Haul.tla` and `specs/Build.tla` (`Arrive`, `PartsHere`)
specify it.

The first start of the node builds the places (D7; `World.Yard`, with
`WORLD_YARD=true`). The warehouse and the factories are closed at the
start; the gate and the site are open. The people build the building of
each as a house of one floor on its lot, with a shutter of the size of
its products, and the place opens when its building is done; then the
haul takes the materials from the stock of the warehouse. When the
factory of the vehicles opens, the people build the two trucks there
(vans), and the haul rents no more trucks. A model in data goes to the
place of its kind (a van and a scooter to the factory of the vehicles; a
house, a statue and a tower to the site); the yard holds it until the
place is open. `specs/Places.tla` specifies it: no construction waits
for a place that nobody builds, and the first start ends.

Each place has a position in meters, in one flat frame: the yard of
World. Later, a place can have a latitude and a longitude, so the world
of Phượt puts the factory on its map.

### The factories

The world has many factories, as the real world does. Each factory makes
one family of things, from the modules of World of that family. An
order for a thing goes to the factory of its family. A part of it from
another family is a sub-order to that factory, and a vehicle brings
the part by road.

| Factory | What it makes | From |
|---|---|---|
| The materials | Bricks, concrete blocks, slabs, lintels, lumber, OSB, siding, metal panels. | `World.Materials.Construction`, `World.Materials.Stock` |
| The frames | T-slot frames, strut channel, racks, shelves. | `World.Framing`, `World.Framing.Builds` |
| The houses | Walls, roofs, houses, warehouses, factories (their doors and windows come from the openings factory). | `World.Buildings` |
| The wheels | Tires, rims, wheels. | `World.Vehicles.Wheels` |
| The seats | Seats and benches. | `World.Furniture.Seats` |
| The openings | Doors and windows of all kinds: the prehung doors and the windows of the houses and the buildings; the doors of a van (with the glass of their windows and the mirrors), its windshield and the windows of its body, each to the numbers of the order of the van. | `World.Openings`, `World.Openings.Van` |
| The vehicles | Vans, cars, scooters, motorcycles, bicycles; their bodies, hoods and engine bays (the doors and the windows of a van come from the openings factory). | `World.Vehicles.Van`, `World.Vehicles.Corners` and the other vehicles |
| The appliances and the power | Fridges, washers, ranges, power stations, the gear of a van. | `World.Appliances`, `World.Gear.PowerStations`, `World.Gear.Camper` |
| The clothes | The clothes and the hair of the people. | `World.People.Human` |
| The people | A person from the data of MakeHuman. | `World.People` |

A new family of things (an airplane, a ship) is a new factory, with its
modules. The people of the world build the factory first, from the
materials and the houses factories.

## The people

A person is a process of the node (`World.Person`), with a job (a
worker, for now) and a trade (`World.Plan.trade/1`): a mason for a
house, a street, a statue or a tower; a wheelwright for a wheel; a
joiner for a door or a window; a mechanic for a vehicle; and the trade
of each workshop (a turner, a shipwright, a molder, a shoemaker, a
gardener, a bamboo worker, a rigger, a sewer, a sheet metal worker). A
task of no trade goes to a builder.

The census (`World.Census`) knows each person. A construction asks for a
person of a trade; the census gives a free person of the trade, or a
new person while the node has fewer people than its limit, or, at the
limit, a free person of another trade leaves and a new person of the
trade comes. With no free person, the construction waits. The census
gives the next free person to the construction that waits and holds the
fewest people. So the constructions of the node share the people.

A person does one task at a time, and gives its element back to its
construction. A construction lets a person go when it has no task of
its trade, or when a task needs a trade that it holds nobody of: then
it gives back its free people of the trades that no task needs now, so
two constructions never wait for each other at the limit of the node
(`specs/Census.tla`).

## A job, from start to end

The example is a job of the blueprint `strut` at the level far.

1. **The job comes in.** `POST /builds` with the order, the level and
   the budget; or an order of the site (`/o/HASH.glb`), which a
   construction builds too. The node opens a construction with the id
   of the job: the hash of the order and the level. The log gets
   `requested` (the budget and the level).
2. **The plan.** The construction makes the item at the level that fits
   the triangles of the budget, and the plan from the tree of its
   assembly: one task for each node, each with its trade (`plan_made`).
3. **The people.** For each task that can start, the construction gives
   it to a free person of its trade that it holds, or asks the census
   for one, in its budget of workers (`hired`).
4. **The work.** Each person makes the element of its task
   (`task_started`, `task_done`), and the log gets each part of the
   element at its place in the model (`element`): a watcher draws it at
   once.
5. **The model.** When each task is done, the construction lets its
   people go (`released`) and joins the model: one build of the scene
   with the triangles that the people made, a process for each
   material, so the file has the bytes of a build with no world
   (`done`). The log gets the time and the memory of the construction
   (`run_done`).
6. **The files.** The files go to the job, and through the Worker into
   R2. A second request of the same job finds the files in R2.

The budget: the most workers at one time, the seconds (at its deadline
a construction stops, with `stopped` and no model), the triangles, and
the memory of the people (`memory_mb`: a task over its part fails), and
the clock (`clock`: `fast` keeps the days of each task in the log, but
the people do not wait for them).
Only with `memory_mb` do the people and the join do a full collection
after each big step (`World.Detail.collect/1`): with no limit, nobody
waits for it.

A client can pause a construction (`paused`: no task starts, the people
end the tasks in hand, the free people go), change it in the pause (a
new order of the same blueprint in data: each node whose data is the
same stays made; `changed`), resume it (`resumed`), or cancel it
(`stopped`, the reason `cancelled`). A person does each task in a hand
(a process that it watches), and takes a stop of priority while the hand
works: when a construction stops, fails or is cancelled, each person with
a task stops it at once and is free (plan 0007, D5); the hand sends its
result to the construction itself. A change has a cost on the site
(plan 0006, D7): each built element that it drops is taken down by
people before its node is made again, the last built first (a task
`remove/NODE` of the trade of the node, `action` `remove`, a third of
the days of the task that made it; `element_removed` when it is down).
A change of the lot (`lot` of the job) drops each node.

A site has a method (plan 0006, D6; `World.Method`): the option
`method` of an order (`today` or `1974` for a statue). The method gives
the rates of the crews (`World.Site`), the most people on the site (50),
and the stages of the construction. Today is one stage that builds
each node. 1974 is the true history of the statue on Núi Nhỏ
(`priv/history/tuong_chua_kito_vua.json`, each fact with its sources):

1. `first_build`: the first statue (8.6 m on a base of 5 m) at the cape
   of Nghinh Phong, up to the fourth band of its cast, from 1 July 1972;
2. `first_pause`: the land is claimed; the part that is built stands;
3. `first_down`: the change of 16 February 1974 gives the order its
   full options and the lot on the top of the hill: the first statue is
   taken down (`changed`, `remove/NODE`, `element_removed`);
4. `rough`: the rough structure on the top, to 30 April 1975;
5. `pause`: 17 years with no work; the statue gets old (`aged`: each
   year, the dirt of the concrete and the weeds from 0 to 1, and the
   copper cable of the lightning rod that goes);
6. `finish`: the repair (`repaired`), the render, the halo, the stair,
   the rail, to 1 December 1994.

The people of a site do the work of their trade (plan 0006, D10): a
person of the blueprint `person` can have the animations of the work
(`World.People.Pose.work/0`: `carry`, `set_panel`, `pour`, `trowel`,
`hammer`, `climb`, `guide`) and the props of a site (`hard_hat`, `bucket`,
`trowel`, `hammer`). On the world page the people of a stage walk in on
the way to the lot (the path of the hill when there is one) before its
work starts: the people that it hires, and the helpers of the crews (as
many as work at one time in the stage, at most 60). A person and the
crew of its task go to the place of the task, each to a place of its own
round the work: on the ground round the part, or on the deck of the
scaffold of its band. To a deck they climb onto the base at its edge and
up the ladder at the corner of the scaffold, and from deck to deck on
the ladder. There each does the work cycle of its trade (plan 0006,
D12): it goes to the source of its materials, takes a load (a panel, a
bar, a tube, a bucket), carries it to the next point of the work on the
surface of the part, and works there, in about 6 s of the film. The
person of a task takes a load in one cycle of three; its helpers in each
cycle. The source of a deck is the lift: the bucket of the tower crane
today, filled at the stack at the foot of the mast; the bucket on the
rope of a pulley at the ladder in 1974. The source on the ground is the
heap: the mixing board, or the stack of the panels, the bars and the
tubes. A free helper goes on at its place until a task takes it (the
nearest first), or works at the heap: it mixes, carries loads up the
ladder to the deck, to the foot of the lift or to the work on the
ground, or works the lift. A
person that waits for its next task works at the heap too. At the end
of a stage the people walk out on the way. A site has at most 50 people (the 50
skilled workers of 1974).

The time lapse is the world page that follows one construction (plan
0006, D11): `review/world.html?follow=ORDER&events=LOG` replays the log
on its clock at `days` days of the world in one second of the page (20
by default), the same for each step and each pause, so a film is the
days of the site over that number. The camera turns with the mouse or a
finger, has its views (three quarters, the front, the side, the back,
the base, above), a slow turn, and takes `cam`, `target` and `fov` from
the URL ("Copy the camera"). The work goes at `days` days in one second
(5 by default) and a pause at `pause` (365: a year in a second): the
steps of the work keep their days to each other. At the start of each
stage the day waits 4 s: the people of the stage walk in (at a pause:
the people and the carriers walk out). The first stage on a new lot
waits longer: 1 s at the old site when it is down, then 8 s up the
road to the new lot: the camera follows the road from the old lot along
the ground to the foot of the path and up the path, 30 m behind and 22 m
over it, looking along the road to the hill, while the people of the
stage walk up with it. A task that takes a part down (`remove/NODE`)
takes it from its top to its foot over its days, and its crew works at
the part; pieces fall from its top, and a heap of broken concrete grows
round its foot and stays. Each part grows from
its foot to its top over the days of its task. The film shows the
finished model from the first pour: each pour is the band of the
finished model at the heights of its rough band, in its concrete; the
render covers the bands with the stone of the model from the foot to
the top, and the halo puts up its steel. So the model at the end is the
model that the people built (a model that a change takes down before its
end keeps its rough bands). The crew of each task
works round it; the carriers walk the path; in a pause the grass and the
bushes grow on the lot. The label gives the day, the date of the
history, the stage, the task and the speed. `scripts/timelapse_log.exs` makes the
log and the files of a construction of the statue (`today` or `1974`),
and `scripts/timelapse.mjs` makes its video (ffmpeg).

Each stage of a build has the means of the people of the time
(`means`, `World.Method.means/0`; in `stage_started`). Today: the trucks
drive to the lot, a tower crane lifts the loads (the node `crane`), a
pump gives the concrete, a scaffold of steel, forms of plywood. In 1974
and in the repair of 1992 to 1994 no machine (the facts `carry` and
`carry_1992`): the people carry the materials up the path of the hill
from its foot (`path` of the history, an estimate; the world page draws
the crew of carriers), mix the concrete by hand on a board (the node
`mixing`), lift the buckets with a pulley on the scaffold, on a scaffold
of bamboo with forms of timber boards. What no source gives is an
estimate (`means_estimate` of each stage).

A pause takes the parts of its `takes` in its first year: the scaffold
of bamboo and the board of the mixing of 1975 rot or go (an estimate;
`element_removed` with `lost`). The build after it makes the parts of
its `again` first (the scaffold of the repair of 1992): a task
`again/NODE` each, that the other tasks of the stage wait for (the event
`changed` gives the new tasks and the new waits). Each task has the
people of its crew (`crew` of `task_started`, the crew of the rate of
its work for the method: 12 for a pour by hand, 6 with a pump).

Each stage starts at its date (`stage_started`, with its days from the
start and its `fit`) and ends when its tasks are done (`stage_done`). The
days of the tasks of a stage are fitted to the days between its dates;
between two stages no task starts. The model at the end is the model of
the method of today.

## The plan from a drawing

A drawing with skills (a blueprint in data: the statue, the tower) is
one task for each node of the drawing (`World.Plan.of_drawing/1`). A
node waits for its parent, its `after` and its `from`; its trade is the
trade of its skill. The person of the trade runs the skill with the
data of the nodes `from`, and makes the GLB of each mesh of the part.
The elements go to the watchers in the order of the nodes.

| The statue | Its people |
|---|---|
| The base and the plinth | A mason. |
| The figure and its robe | A sculptor. |
| The cast | A caster: one task (plan 0001, D30). |
| The grilles and the halo | A smith. |
| The part of the statue | A sculptor sets the pieces. |
| The stair and the rail | A mason. |
| The ports and the collision boxes | A surveyor. |

## The plan from an assembly

An assembly is a tree. The first node is the root. Each other node
connects to a node that comes before it. This order is the order of the
work, with no new data:

| In the assembly | In the plan |
|---|---|
| The root item | The first task: make the root part. |
| A node with a part | A task: make the element of the part, after the task of its parent. |
| A node that holds a smaller assembly | Its tasks, with the name of its node before their ids (`wheel/rim`), and a task `wheel/order` that waits for each of them. |
| The kind of the nearest assembly | The trade of the task (`World.Plan.trade/1`). |

The time of a task is not in the assembly. The world measures it when
a person does the task, and the log keeps it.

## Time

Time is real. The clock of the world comes from the wall clock of the
VM, and the code takes real time to build a thing. But the code builds
much faster than people do. The camper van takes 0.46 s of code, and
about 30 hours of work in a real plant. So the world has a scale: one
second of the wall clock is one day of the world (86,400 world seconds).

### The scale from the measurements

The code times are the mean of three builds at the near level, with
`World.Build.scene/2`, on the computer of the development (BEAM.com
0.1.0-rc.6, native code).

| Thing | The time of the code | The time of the real work | Real ÷ code |
|---|---|---|---|
| The camper van (`ford_transit_148_camper`) | 0.46 s | About 30 hours of work for each vehicle in the plants of North America: stamping, engine and assembly (the Harbour Report of 2007: 30.37 hours). | About 240,000 |
| A wall of 164 bricks (`wall_brick_sample`) | 15 ms | 164 × 58 s: a bricklayer lays about 500 bricks in a day of 8 hours. | About 650,000 |
| A house of 7,108 bricks (`house_brick_vn`) | 1.9 s | About 114 hours of bricklaying. | About 215,000 |

At the edge, the VM runs in WebAssembly. The first guess was 10 times
slower than native code; step W7 measured 2 to 3 times (V8 compiles
the WebAssembly), so there the ratio is about 15,000 for the van.

One day for one second (86,400) is near the two. With this scale, a
worker of the world builds a van in 11 hours (native code) to about 28
hours (the edge, 2.5 times slower). A real plant takes about 30 hours: the same order of size. A faster computer is a faster factory, as a better tool is in the
real world. Step W7 measured the edge again ("The measures of a run"):
the code there is 2 to 3 times slower than native code, and the ratio
for the van is about 15,000. The owner
can change the scale: it is one number of the world, and each log keeps
it.

### The rules of the clock

- The world has one clock (plan 0006, D1; `World.Clock.world/0`): it
  starts with the node, and each construction, the yard and the haul
  keep their times on it. The time of the world: its start, plus the
  scale times the wall time since its start (86,400 by default; the
  variable `WORLD_SCALE` of the node; 1,000 days in a second in the
  tests). The log keeps the world time and the wall time of each event,
  in milliseconds.
- The time of a task is the days of its work on a site (plan 0006,
  `World.Site`, `priv/standards/site.json`): the work of its node (`"work"`:
  10 m3 of concrete, 186 m2 of forms), or the work of its takeoff (70
  bags of cement are 10 m3 of concrete), over the rate of the crew of
  the work for the method of the site; a task with neither is one hour.
  The person does the work of the code at once and is busy until the
  end of the days of the task on the clock (`task_started` has `days`).
- A task can have a wait after it (`"cure"` of its node: `lift`, `strip`,
  `set`): the tasks that wait for it start after the days of the cure.
  The band of a cast waits for the cure of the band under it.
- The speeds are real, in world time. A person walks at 1.4 m/s. A
  vehicle on the yard drives at 20 km/h; on a road between two places,
  at the limit of the road. The wall time of a drive is its world time
  over the scale: the world waits for the vehicle.
- A walk of 100 m takes 71 world seconds (0.8 ms of the wall clock). A
  van takes hours of the world. The world is as the real world: a
  walk across the yard is short, and a build is long.
- The calendar of the world runs fast: one hour of the wall clock is
  about 10 years of the world. The world gives its time as days since
  its start ("day 412, 14:05"), not as dates of the real calendar.

The replay runs the log at any speed: one world day in one second, or
slower to see a worker at a station. The statistics come from the log:
the time of an order from `order_received` to `delivered`, the time of
each station, the stock of each warehouse over time, the orders by
blueprint.

Sources of the real times: the Harbour Report of 2007
(<https://europe.autonews.com/article/20080605/COPY/569014825/harbour-report-chrysler-toyota-tie-for-2007-efficiency-title>),
and the output of a bricklayer
(<https://www.mybuilder.com/questions/v/24046/how-many-brick-layed-per-day>,
<https://uk.indeed.com/hire/job-description/bricklayer>).

## The events and the log

An event is one line of JSON. The log of a construction is its events in
the order of their time, as one file for each order in R2
(`/o/HASH.log.json`). The log of the node has the events of each
construction, each with an id that grows by one, in the SQLite of the
Durable Object at the edge (`World.Log.Server`, `World.Log.Store`).

| Event | Who | Data |
|---|---|---|
| `requested` | The construction | Its budget and its level. |
| `plan_made` | The construction | The tasks with their waits, parts and trades, and the level. |
| `hired`, `released` | A person | Its trade. |
| `task_started`, `task_done` | A person | The task, its trade, its station; at the start, the days of its work and the days of the wait after it (`days`, `wait`). |
| `element` | A person | The task, the part, the key of its GLB, and its frame in the axes of glTF. |
| `done` | The construction | The bytes of the model, its level. |
| `stopped`, `failed` | The construction | The reason (`seconds`, `triangles`), or the message of the error. |
| `run_done` | The construction | The time of the wall clock (`ms`), the memory of the VM: the most (`memory_peak`) and at the end (`memory_end`), with what they count (`memory`), and the work of the construction process (`reductions`). |
| `started` | The log of the node | A new log after a stop of the VM: it leaves 50 ids after the last id of its store (`specs/LogStore.tla`). |

Each event of a construction has: `at` (the time of the world), `wall`,
`order` (the id of the construction), `who` (the name of a person), its
`kind`, and the data of its kind. A test reads a log and checks: the
events are in order, and each task starts once, after the tasks that it
waits for.

## The replay

The review page gets a page of the world. From a log, it shows:

- the places, as their building models;
- the stock on the racks of each warehouse;
- the vehicles on the roads, at the time of each event;
- the people, with the poses `walk`, `carry` and `work`, at their
  tasks;
- the model on the line, with one part more at each `task_done`.

The replay is a model of World too: an assembly of the world at a time,
with a pose for each person and each vehicle. So the files of the world
at a time are GLB files, and a project can show them.

## The projects

The world has no scale. It makes the models for each project of the
owner. Each project takes what it needs, at its own scale:

| Project | What it takes from the world |
|---|---|
| DIY | The items of a house, the vans, the builds of wood, as today. |
| Vũng Tàu | The buildings, the vehicles and the people of a city, in Godot. |
| Phượt | The vehicle of the traveler, the places along the road; later, the factory on its map. |
| Humans Must Die | A planet: its factories, its vehicles (emergency vehicles, airplanes, ships, aircraft carriers), its buildings. Each new family of things is a new factory of the world. |

The same parts, the same people and the same levels of detail serve all
four. A model of the world is one order; the project chooses its level.

## The engineers (later)

The first world does the work of a plan. The people do each task, in
the order the assembly gives. The plan comes from the assembly, not
from a person.

The second world makes plans. An engineer or an architect reads the
log: how many orders, of which blueprints, how the orders change, where
the time goes, which parts wait. From that, it proposes a change. A new process: a different order of
the tasks, or one more worker at a slow station. A new component: a
sub-assembly that many orders share. A new way to build, or a new
model. Erlang serves this well: a population of plans
that compete (genetic programming), flocks of people that move as one
(boids). That work comes after the first world, and it is research:
the owner decides each step of it.

## The flows in TLA+

The flows of the node are specifications (`docs/specs.md`):
`specs/Build.tla` (the constructions and the people that they share),
`specs/Census.tla` (the people at the limit of the node),
`specs/Stream.tla` (a stream that watches, reads the past and follows)
and `specs/LogStore.tla` (the ids of the log after a stop of the VM).
The native checker of Accord checks a small model of each one in the
tests, and a fault model of each must fail. The log of a real
construction replays as a behavior of `specs/Build.tla`.

## The measures of the people of plan 0002

The time of a construction (`run_done`) at the near level, with one
person and with 16, natively on the computer of the development (4
cores), on 2026-11-07:

| Model | Tasks | One person | 16 people | The path that is left |
|---|---|---|---|---|
| The statue on Núi Nhỏ (`statue`) | 37 | 14.9 s | 8.3 s | The figure, the survey and the field of the cast: one task each. |
| A tube house of three floors (`tube_house`) | 87 | 0.49 s | 0.30 s | |
| A van of the line (`van_line`) | 23 | 2.2 s | 1.25 s | The body shop: 0.7 s. |
| A bicycle (`bicycle`, its geometry sheet) | 7 | 0.64 s | 0.37 s | |
| A scooter (`scooter`) | 17 | 1.2 s | 0.58 s | The panels of the body. |
| A motorcycle (`motorcycle`) | 17 | 1.1 s | 0.49 s | |
| A car (`car`) | 12 | 1.7 s | 1.1 s | The body on its lofts. |

Before plan 0002 the statue was one task of the cast (16 s with one
person or with 16), and the join of a model waited for a full
collection after each primitive: the van took 3.3 s with 16 people.

## The measures of a run

Step W7. The run of an order through the world, with the measures of
its log (`run_done`), before plan 0001 (the run of the yard, not a
construction: the measures of a construction come in step 3 of the
plan). Native: BEAM.com 0.1.0-rc.6 on the computer of the
development, `mix run`. WebAssembly: the same `edge.com` in `wrangler
dev` (workerd on the same computer, with no limit of memory), the first
request of each order.

| Order | Level | Native run | Native memory (total) | WebAssembly run | WebAssembly memory (processes) | WebAssembly memory (host) |
|---|---|---|---|---|---|---|
| A traveler of Phượt on the motorbike | far | 1.9 s | 158 MB | about 8 s for the request | | 126 MB |
| A traveler of Phượt, parked | near | 4.0 s | 254 MB | 10.1 s | 55 MB | 216 MB |
| The camper van | near | 3.0 s | 277 MB | 7.3 s | 51 MB | 178 MB |

At the edge (the deploy of 3911c45 on <https://world.mkfifo.com>,
2026-10-31, the first request of each order, with the check of the
order and the start of the VM):

| Order | Level | Time of the request | Run (`run_done`) | Memory (processes) | Result |
|---|---|---|---|---|---|
| A strut of 0.5 m | near (log) | 6.3 s | 6 ms | 1 MB | Built |
| The camper van | far (GLB) | 9.4 s | | | Built |
| The camper van | near (log) | 16.1 s | 7.7 s | 56 MB | Built |
| A traveler of Phượt on the motorbike | far (GLB) | 12.5 s | | | Built |
| A traveler of Phượt on the motorbike | mid (GLB) | 7.4 s | | | Built |
| A traveler of Phượt on the motorbike | near (log) | 7.5 s | | | The VM stopped (503): not sufficient memory. After F4, part 2 (8d59a75): built, 13.0 s, a run of 7.3 s. |

What they tell:

- The code at the edge is 2 to 3 times slower than native code, not 10
  times (V8 compiles the WebAssembly): the run of the van takes 7.7 s
  at the edge and 3.0 s natively. So the ratio of the real time to the
  time of the code (section "Time") is about 15,000 for the van at the
  edge: 30 hours of work (108,000 s) over 7.7 s.
- The memory of the processes is small (about 50 MB); the host sees
  more (178 to 216 MB in `wrangler dev`), because the heap of
  WebAssembly only grows and keeps the garbage of the build. At the
  edge, the van at the near level fits; a person at the near level fits
  since F4, part 2 (`docs/factory.md`).
- The log of an order (`/o/HASH.log.json`) is a run at the near level;
  since F4, part 2 the log of a traveler is there at the edge too.

## The measure of the catalog

`mix world.bench` (`World.Bench`, plan 0007) builds each model of the
catalog and each blueprint in data through a construction, one at a
time, and gives for each one: its result, its time, the most memory of
the VM, the use of the schedulers, its tasks and its triangles
(`--level`, `--workers`, `--clock`, `--scale`, `--timeout`, and
`--out FILE` for the JSON). Plan 0007 has the numbers before and after
its steps, on one machine: at mid with 4 people, 183 of 183 models are
built in 64.0 s, against 180 of 182 in 99.2 s before the plan; with 8
people, 66.6 s against 168.3 s. The time of a model of one task (an
animal, a person) is the code that makes its one part
(`docs/plans/0007-actors-build-faster.md`, section 10).

A construction has three helpers, each a process of its own that gives
its memory back at its end: the drafter makes the model and the plan at
the start, a person makes each task in a hand (a stop of the person
kills the hand), and the joiner joins the model at the end. The log of
the node keeps its last events in a table (ETS), so a publish takes the
same work with any count of events in the log.

## The decisions

| Topic | Decision | Why |
|---|---|---|
| The name | The project is World: the module `World`, and a context of the world for each family of things (`World.People`, `World.Vehicles`, `World.Buildings`). The repository is `sntran/World`, the Worker `world` at <https://world.mkfifo.com>, and the bucket `world`. | The project builds things as the real world does. |
| Real, not invented | Each thing of the world is one thing of the computer, and each time is a measured time. | The replay is a record, and the statistics are true. |
| The log is the truth | The replay, the statistics and the engineers read the log only. | One source. A test reads a log. |
| A place is a model | A warehouse and a factory are orders, built by the people from the materials of World. | The world builds itself from the ground up. |
| People are processes | One `GenServer` for each person, one mailbox of tasks; the people of the node are one pool that the constructions share (`World.Census`). | The BEAM is made for this. A person that waits does not stop the world, and a node holds millions of processes. |
| The plan comes from the assembly | No new data for the plan: the tree and the kinds of the assembly give the tasks and their trades. | Each model of World is buildable in the world with no change. |
| The people build | A person makes the element of its task, and the construction joins the elements with no second build (plan 0001). The yard of the first world, with its factories, its trucks and its stock, went with plan 0001. | The work of the people is the real work of the build. |
| Many constructions | Many constructions at one time on one node, each in its budget. | A node is a city, not one factory. |
| No scale | The world has no scale of its own. Each project takes what it needs. | The world powers all the projects of the owner, at their own scales. |
| The clock | One second of the wall clock is one day of the world (86,400). The speeds are real speeds in world time: 1.4 m/s for a person, 20 km/h on the yard. | The code builds about 20,000 times (at the edge) to 650,000 times (native) faster than people. One day is between the two, and the real speeds keep a walk short and a build long, as in the real world. |
| The yard | The positions of the places are in meters, on one flat yard. A map comes later. | The simplest world first. |
| One bucket for each warehouse | A warehouse is one R2 bucket. A new warehouse is a new bucket. | In the game, a new warehouse is a collaboration with another city or country. |
| The flows in TLA+ | Each asynchronous flow of the node is a specification (`docs/specs.md`): the constructions and their people, the census at its limit, a stream, and the log after a stop of the VM. The native checker of Accord (`sntran/accord`, the branch `feat/native-tla-checker`, no Java) checks a small model of each in the tests, a fault model of each must fail, and the log of a real construction replays as a behavior of `specs/Build.tla`. | The people are processes: the order of their acts changes from run to run. A model check finds the races and the dead ends that a test does not find: it found the dead end of two constructions at the limit of the node, and an id of the log that named two events after two stops. |
| The pages | Static pages (three.js) that read the stream of the world (`/events`, server-sent events) and the log of an order. No Phoenix LiveView. | The Worker stays a plug (`World.Service`) in one VM of 128 MB; a stream needs no socket of two ways. |
| The crew van of the Transit | It comes with the Sprinter and the ProMaster, after the first world. | The owner wants the crew van in the line. Ford does not sell it for 2024 to 2027: its sizes come from the earlier years. |

## The real world

The goal: World builds the common things of the world (buildings,
vehicles, furniture, tools, clothes, plants, animals, and the streets
and the towns that hold them) as the real world makes them. A new model
comes from data and rules, not from new code for each model.

The rules of a model of the real world:

- **Real sizes.** Each number of a model comes from a source: a
  datasheet, a standard, a brochure, a drawing to scale, or a measure of
  a photo with a known size in it. The source is in the data, next to
  the number. A guess is marked as a guess.
- **Real materials.** Each part has a material with its density and its
  surface, so each model has a mass, a center of mass and a bill of
  materials.
- **Real processes.** A part comes from the process that makes it in the
  real world: a cut of stock, a turn on a lathe, a bend of a sheet, a
  mold, a seam, a growth. Each process is a workshop of the world, with
  its people, as the factories are.
- **Real limits.** A model stands on its base, its parts do not pass
  through each other, its joints stay in their limits, and it fits
  through the door of its workshop and on the truck that delivers it.
- **Real time.** A process takes the time of the real process, on the
  clock of the world.

### The processes

| Process | What it makes | In World |
|---|---|---|
| Cut stock to size, then join | Lumber framing, extrusions, strut channel, shelves | `World.Framing` |
| Turn on a lathe: a profile around an axis | Bottles, cups, bowls, posts, lamps, wheels, pots | Step P2 |
| Bend and cut a sheet | Bodies of cars and vans, cabinets, boxes, roofs, ducts | The body shop of the vans; step P6 for all sheets |
| Mold and cast: sections along a spine | Hulls of boats, seats, helmets, bodies of scooters | `World.Blob`; step P6 |
| Sew: pieces cut from a pattern, joined at seams | Clothes, underwear, bags, tents, covers, sails | Step P1 |
| Grow from rules | Trees, palms, bamboo, flowers, grass | Step P7 |
| Grow a body on a skeleton | People, animals | `World.People`, `World.Animals` |
| Join with standard parts | Bolts, nuts, screws, hinges, brackets | Steps P3 and P5 |

### The places and the engineers

The places come from open data: OpenStreetMap (ODbL: the attribution
"© OpenStreetMap contributors" goes with each model of a place) has the
footprints of the buildings, their levels and roof shapes, the roads
with their widths and lanes, and the trees. With the blueprints of the
buildings, World builds a real street, at three levels of detail, in
tiles (step P8).

The engineers (step P9, the second world of "The engineers" above): a
person or an agent turns a request ("a bamboo chair", "a Honda Super
Cub of 1967") into a new blueprint from the processes and the standard
parts, with the tools of `World.MCP`. The checks of step P5 stop a bad
design before an order, and the owner reviews each new blueprint.

What World does not make: art (a statue, the face of a real person),
brands (logos and trademarks), and the inside of a machine down to each
gear (World makes the outside and the parts that show). A mesh with a
license goes in only with its license in `CREDITS.md`; big data goes to
R2, not to the release (the Worker has 64 MiB).

The plan changes with what the steps teach: after each step, a render
of each new model next to its reference, and a row in "The decisions"
for each choice.

## The steps

Each step is a small series of commits on `main`, with tests at 100%
and a picture of the replay where there is one.

The rows W1 to W7 are the history of the first world. Plan 0001
(`docs/plans/0001-people-build-on-demand.md`) took the place of its
yard, its stock, its factories by family and its run (their code is
gone): the node, the census, the people by trade and the constructions
of this document.

| Step | Result | Check |
|---|---|---|
| W0. The plan | This document. | The owner agrees, or changes it. |
| W1. The data of the world | `World.Clock`, `World.Places`, `World.Yard` (the roads), `World.Stock`, `World.People.Person` (the jobs), `World.Vehicles.Vehicle`, `World.Log` (the events and the checks). The plan of an order from its assembly (`World.Plan`). Done. | A property test: the plan of each model of the catalog has one task for each node, and each task waits for the task of its parent. A log with a bad order of events is refused. |
| W2. One thin slice | One order of a van. One warehouse, one truck with its driver on a road of the yard, one vehicle factory with a foreman and two workers. The people are processes (`World.Run`, `World.People.Storekeeper`, `Driver`, `Foreman`, `Worker`). The log of the order, with real times. The flow in TLA+ (`specs/Order.tla`). Done. | A test runs the slice and reads its log: the van is delivered, the events are in order, the stock is never negative, the drive took the length of the road over the speed of the truck. The same order a second time comes from stock. |
| W3. The replay | The replay page (`review/replay.html`, `/replay.html?order=HASH`): the map of the yard with the truck on its road, what each person does, the events, and the model that grows when each task ends. The orders of the site go through the world (part of W7): `/o/HASH.log.json` and `/o/HASH.replay.glb` (`World.Build.scene/2` with `split: true`). No LiveView: the log is a file, and a static page reads it. Done. | A picture of the replay of the van at a time, on a phone and on a wide screen. A test: the replay GLB has one node for each task of the plan that takes a part. |
| W4. The factories | The wheel factory and the seat factory next to the vehicle factory, each with its foreman, its worker and the driver of its truck. The family of an item is the kind of its assembly (`World.Places.family_of/1`: `:wheel`, `:seat`). The plan of a factory (`World.Plan.flat/2` with its family) leaves a smaller assembly of another family to the factory of that family: the foreman orders it (`part_ordered`, the order `ORDER/wheels`), that factory makes it (`World.Plan.batch/2`) from the parts of the warehouse, and its truck brings it to the dock (`received`). A factory does one order at a time; the next order waits. `specs/Order.tla` has the action `Receive`. Done. | The log of a van: the wheels come from the wheel factory, the seats from the seat factory, each by a drive (`test/world/run_test.exs`). The log of the van replays in the specification. |
| W5. The buildings | The warehouse and the factories are orders: the people build them, and the log has the build. `World.Buildings.Plants`: a building is a house of World (walls of 2x4 studs, a metal roof, a door at the left end); a warehouse has one rack of strut channel for each 64 MiB of its store (a number of the world), in two rows; a factory has 3 m of length for each worker. `World.Run.build/3`: `build_started` (the model and its size), the order to the houses factory (a factory of the run now), the delivery to the place, and `build_done`. Each event of a storekeeper has the bytes in the store and its limit, and the replay draws the racks of a warehouse under it, dark when full. The materials are parts of the house, from the warehouse: no materials factory yet. Done. | The log of a build of a warehouse (`test/world/run_test.exs`): 200 MiB gives four racks. The size of a warehouse from the limit of its store (`test/world/plants_test.exs`). |
| W6. The stores | The stock is the files: each warehouse has a store (`World.Store`), and the stock keeps the files of each model in it (`World.Stock.put_files/3`). The kinds of a store: `:memory` (the memory of the VM, the store of the warehouses of a run by default), `:bucket` (an R2 bucket; on this computer a folder in its place, as the photos of Phượt), and `:release` (the catalog of the release, `priv/models`: read only and always full, `World.Places.catalog/3`). The yard of a run has an annex (a second warehouse, its storekeeper `tam`, a road to each factory) and, with the option `catalog`, the catalog. A model in the stock of a warehouse (the warehouse first, then the catalog, then the annex) goes to the customer with its files. A full warehouse refuses the files of a new model: the driver of the warehouse brings them from the factory to the annex, and its storekeeper stores them. With the annex full too, the order fails. The R2 bucket from the VM at the edge (a port to a binding, as `PHOTO_STORE` of Phượt) is not there yet: today the Worker puts the files of an order in R2 after the run. Done. | A test with a small limit: the storekeeper refuses, and the foreman sends the model to another warehouse. |
| W7. The site | The orders of the projects go through the world at <https://world.mkfifo.com> (done in W3). Each run of an order has its measures in its log (`run_done`, `World.Run.measure/3`): the time of the wall clock, and the memory of the VM, sampled each 25 ms. At the edge the emulator has no allocators of ERTS (`-Mea min`), so `:erlang.memory/1` is not there: the log then counts the memory of the processes and of their binaries (`memory: "processes"`), and the host logs the memory of all of the VM (`beam: memory N MB`). `POST /build` gives the time of the build in the header `server-timing`. The release has no `priv/models` now (the site serves them): `edge.com` goes from 87 MB to 31 MB. The deploys after 29 October 2026 did not reach the site (it served `af1ad01`); the first deploy with the smaller `edge.com` (3911c45) reached it, so the size of the Worker was the cause. The numbers are in "The measures of a run" below. Done. | An order of Phượt gives its files and its log. The times in the log agree with the times of the service. |
| W8. The other vans | The Sprinter, the ProMaster and the crew van of the Transit, built on the line of the vehicle factory. The ProMaster (2026-11-01): the make `ram_promaster` and the models `promaster_136_high`, `promaster_159_high` and `promaster_159_ext_high` in `priv/data/vans.json`. The side traces come from the render of Ram on the side of the 159 in, high roof (sent by the owner), with the length and the height of the brochure of Ram as the scales; the sizes from the brochure of Ram (2018) and the cargo page of Ram. The black band and the window of the front door are data of the make now (`trim.band`, `openings.door_window`). The Sprinter (2026-11-01): the make `mercedes_sprinter` and the models `sprinter_144_high`, `sprinter_170_high` and `sprinter_170_ext_high`. The side traces come from a drawing of the high roof van in the Body and Equipment Guideline of Mercedes-Benz (BM907, 2024-9, sent by the owner), which is to scale: with its wheelbase as the scale, its overhangs and its length are those of the guide to 6 mm; the lengths, the wheelbases and the front overhang from the tables of the guide. The standard roofs (2026-11-01): the models `promaster_118`, `promaster_136` and `sprinter_144`. The roof of the ProMaster comes from the render of Ram of the 136 in, standard roof (sent by the owner), at the scales of the render of the high roof; The roof of the Sprinter comes from the vector drawing of the minibus with a standard roof (Mercedes-Benz Vans Australia, Sprinter Technical Data MY2022, page 39). The sizes of a van are numbers of the order (`size`: `length`, `width`, `height`); the default is the size of the US market: the heights of the US page of Mercedes-Benz Vans (100 in and 107 in) and of the 2026 guide of Ram (91.7 in to 103.6 in). An order for Australia gives the heights of Mercedes-Benz Australia (2.331 m and 2.62 m). The height goes up 0.3 m, and down to the height of the traces; the length and the width go 0.05 m each way. A model can give its own `openings` (the doors of a standard roof are lower). The sliding door of the Sprinter with a high roof goes to 2.54 m now, not 2.30 m (2.30 m is the door of the standard roof); a sliding door stays under the round edge of the roof. The order of a van (2026-11-01, the decision of the owner: as the real world): its windows are a list (each window with its place and its numbers), with the presets cargo, crew and passenger; its doors and its rows of seats are numbers of the order too (`World.Vehicles.Van.Order`). The openings factory (the decision of the owner: one factory for the doors and the windows of all kinds, `World.Openings`) makes the doors and the windows of a van as a sub-order, each to its numbers, and its truck brings them to the line (`World.Openings.Van`); a house orders its doors and windows there too. A number of the make that is a guess (the windows of the Transit on a Sprinter) moves into the limits of its door or its side. Still from the Transit, for both makes: the lamps, the grille, the wheels and the dash; the super high roof of the ProMaster is not there yet. The crew van waits for photos (see "Open questions for the owner"). | As the Transit: a render next to the photo of the dealer. |
| W9. The engineers | Later, with the owner. | — |
| P1. Sewing | `World.Sewing`: a garment is a set of pieces, each cut from a pattern (an outline on the body, with the ease of the fit), joined at seams, of a fabric (thickness, stiffness, grain). The sewing shop of the world sews the pieces in the order of the seams. Each piece has its layer: an inner layer is nearer to the body, and the pieces of two layers that meet overlap. The first garments: a bra (its cups give the shape that the layers over it fit to: round, higher, no point), the áo dài (two long panels, a bodice, sleeves, a stand collar, the slits) with the quần, a T-shirt and pants. The jackets are patterns too. Done: `World.Sewing` with the five garments and the three jackets, the layers, the seams, the drape, the bra shape, and the smooth of the bust under the clothes, and a round bust at mid (the faces on the breasts cut in sixteen); the layers and the shape of the bra in `kit.json`. The renders next to photos (2026-11-04: a white áo dài from the front and from the side, a bra on a dress form; Wikimedia Commons, not in the repository): at near the áo dài has the long panels, the slits and the stand collar of the photos; it found three faults (`TODO.md`): at mid the panels are not there (the clothes are colors on the body, so the áo dài is a suit that fits the body), the bra has no shoulder straps, and the quần is narrower than the wide legs of the photos. | Renders of the áo dài and the bra next to photos, at near and mid. No skin shows between two layers or through a layer (a test of the points of each layer). The shape of the bust of a woman shows under a top, with no point. |
| P2. Turning | `World.Lathe`: a profile (points of a curve) around an axis, with its levels of detail (fewer sides far away). The lathe of the workshop. The first models: a cup, a bowl, a bottle, a post of a balcony, a pot of a plant. Done: `World.Lathe` (a smooth curve through the points of the profile, a wall and a floor for a vessel, the volume by Pappus and the capacity), `World.Turned` (a chén trà and a bát cơm of Bát Tràng, a longneck bottle of 355 ml, a con tiện lục bình, a pot of 8 in), and the turnery of the run (the family `:turned`). The renders next to photos (2026-11-04: a handleless tea cup, rice bowls, a longneck bottle of 0.33 l, a terracotta pot, balusters of a vase shape; Wikimedia Commons, not in the repository): each profile has the shape of its photo. | The volume of a cup from its mesh is the volume of its profile (Pappus), within 1%. A render next to a photo of a real cup with its sizes. |
| P3. The standards | `priv/standards/*.json`, read at compile time: metric bolts, nuts and washers (ISO 4014, 4017, 4032, 7089), lumber (the US sizes and the sizes of Việt Nam), steel pipe, tires (ETRTO), bricks, doors and windows. A part by its standard name (`{:bolt, "M8x40"}`). Done: `World.Standards` reads `priv/standards/fasteners.json`, `stock.json` and `masonry.json` when it compiles (each table with its source, its unit and its fields); the fasteners, the stock and the units of masonry take their tables from it, with the same models; steel pipe (ASME B36.10M, schedules 40 and 80, `Stock.pipe/4`); a part by its standard name (`World.Standards.part/1`); `name!/2` stops the compile on a wrong literal name. The lumber of Việt Nam: TCVN 1075:1971 (the copy of the owner). Done (2026-11-04): the tires (`priv/standards/tires.json`): the rim of each code of Table 1 of ISO 4000-1 (16 is 406 mm), the load indexes and the speed symbols (`World.Vehicles.Wheels.service/1`: 121/119R is 1450 kg and 170 km/h), and the tires of the data sheets of the makers with their outer diameters and masses (the 235/65R16C of the van is 711 mm and 15.9 kg, Michelin); the doors and the windows (`priv/standards/openings.json`, `World.Openings.standard/2`): the doors of the US (24 to 36 by 80 in), the garage doors (9 by 8 ft for the factories), the windows of the US by their codes (3040 is 3 by 4 ft), and the least door of an exit of Việt Nam (0.8 by 2.0 m, TCVN 4451:2012). To do: the sizes of the doors and the windows of TCVN 9366-1:2012 (no open copy), the mass of the tires of the motorcycles. | The head of an M8 bolt is 13 mm across the flats; a 2x4 is 38 by 89 mm. A wrong name stops the compile. |
| P4. The materials | A material has its density, its surface (color, roughness, metal; the CC0 textures of ambientCG and Poly Haven) and its price. Each assembly has its mass and its center of mass; the bill of materials has the mass of each part. Done: `priv/standards/materials.json` (the density of each material role, each with its source), `World.Mass` (the volume, the mass and the centroid of a closed mesh; the mass of a part; the mass and the center of mass of a model, with its parts at their places, `World.Build.placed/1`), the mass of each part in `NAME.parts.json`. The bolt M10x40: 34.6 g (real: 33 g); the longneck bottle: 208 g (real: 193 g; its wall of 1.6 mm comes from the real mass). With step P5: a mesh can be a skin (`World.Mesh.skin/3`: its area times its thickness, for a panel or a bumper; a closed mesh around a sheet takes half of the sheet on each face) and can have a matter for its mass when its role is a color (`World.Mesh.matter/2`); the density of expanded polystyrene (ASTM C578); the overhead door: 65 kg. Done (2026-11-03): a tire is a skin of rubber and cord, of a mean thickness of 7.5 % of the height of its side (a fit to a 235/65R16C of 15.9 kg, Michelin, and a 37-622 of 0.73 kg, Schwalbe); a rim and the pressed disc of a steel wheel are sheets of steel (the wheel of the van: 14.5 kg, a retailer gives 12.2 kg); a part that a shop buys has the mass of its data sheet (`"mass"` in its params: the 3.5 L V6 of Ford Performance, 189 kg dry; the 10R80 of the workshop manual of Ford, 106 kg; the REDARC BCDC1250D, 1 kg); a part with no meshes has a mass of 0; the seats are molded foam (60 kg/m3, US patent 8,770,666) on a frame of steel; the van has its drive (the transmission, the propeller shaft, the rear axle and its leaf springs, the front suspension, the fuel tank with 25 gal of fuel, the battery, the exhaust, the spare wheel). Each part of the van has a mass now: 1967 kg at the near level, against the curb weight of Ford, 2418 kg (the 2020 cargo van of 148 in, high roof, 3.5 L PFDi, rear-wheel drive: the order guide of Ford). The model is 19 % under: its body is one sheet of 0.8 mm (an estimate) with no rails and no crossmembers, and it has no air conditioner, no wires and no insulation; the manual of Ford for body builders gives no gauge of a panel (`TODO.md`). To do: the price, the textures. | The mass of a cup, a chair and the Transit van (empty) next to their real masses: 10% for the van. |
| P5. The checks of a true model | `World.Check`: it stands on its base (the center of mass over the support), no two parts pass through each other (boxes first, then the meshes), each joint in its limits, and it fits through the door of its workshop and on its truck. An order with a model that fails is refused, with the reason. Done: `World.Check` (`stands/1`: the center of mass, or the center of the volume of the closed meshes when a part has no mass, over the hull of the points on the ground, with a margin of 1 mm; a door, a window and a material stand in a wall or on a roof. `overlaps/1`: the meshes in a grid of 0.25 m; two meshes of two parts with boxes in one place, and a point inside one (the center of its volume, or 1 mm inside its first face for a ring) inside the other, by the count of the faces that a ray goes through; the parts that a connection joins, the nodes on one port of a node, the fasteners, the skins and the open meshes are not checked. `joints/2`: the joints of the assemblies. `fits/2`: the overhead door of 9 by 8 ft of a factory, the drive-in door of 12 by 14 ft for a vehicle; a house and a wall are built on their site, and a thing put together on its site (`"site"` in its extras: the overhead door) goes through in its parts). `World.Orders.place/2` checks the model at the level far (the house of the blueprint: 4 s) and refuses the order with each reason at the path `"model"`. The checks found real faults, now fixed: the mortar of a wall was a slab behind the bricks (now a bed joint on each course, a head joint after each unit, a collar joint), the bumpers and the bands of the van were blocks of the hull (now skins of plastic), the panels of the Honda Vision were solid (now skins of ABS), its grips filled the bar (now tubes), its stand went through the case of the engine, the chain of the Himalayan went through its crankcase, the second alternator of the van was in the air box, and the sink of the galley was over the top drawer. The factories have an overhead door of 9 by 8 ft (`World.Openings.overhead/4`: four sections of steel on a core of EPS, 65 kg, and its tracks; a header of two 2x12 over an opening wider than 6 ft). | A test model that tips over, two parts that overlap, and a model too big for its door: each one is refused. Each model of the catalog passes. |
| P6. Sheets and molds | `World.Sheet` (a flat pattern with bend lines, flanges and openings, as a real sheet metal part) and `World.Loft` (sections along a spine, for a hull or a seat). The body shop of the vans moves to `World.Sheet`. The first models: a cabinet, a ghe (the wooden fishing boat of Vũng Tàu), a helmet, a seat. Done (the ghe): `World.Boats.Ghe`, a wooden fishing boat of the sizes of BV-92479-TS (Long Hải, Bà Rịa - Vũng Tàu, 2002: Lmax 20.70 m, Bmax 6.80 m, D 3.60 m). Its members (the keel, the stem, the sternpost, a frame at each spacing of L + 20 cm with its floor, the keelson, the stringers, the beams with the clamps, the planks, the deck, the bulwark, the rudder) have the least sizes of the rules of the wooden hull of QCVN 91:2025/BNNMT (Chương II.II-B, `priv/standards/qcvn91.json`, wood group III), and each section rounds up to the least pair of Bảng 1 of TCVN 1075:1971 (`World.Materials.Stock.vn_section/2`; a keel of 220 by 308 mm is 250 by 320 mm). L at the waterline is 18.65 m, under the first band of the rules (21 m): the boat takes the sizes of the first band. The stern (a deep deadwood aft), the head of the stem, the wale, a propeller of four blades and the paint (red under the waterline, a blue side, a red band at the top) are from the photos of the owner of the boats of Vũng Tàu on their blocks. The mass of the hull: 34 t of sao đen (PROSEA), with no engine and no gear. The boatyard of the run builds it (the family `:boats`); a boat floats and is built on a slipway, so `World.Check` does not check its stand or a door. Done (the sheet): `World.Sheet`, a part bent from one flat sheet: a base, a flange of 90 degrees on each edge (with a return lip at its top), the corner reliefs and the holes; its flat pattern with the bend allowance BA = angle (R + K T), K = 0.44 (the common value for the air bending of mild steel), in the params of the part; with K = 0.5 the volume of the bent part is the flat area times the thickness (a test). The first model: the enclosure nVent HOFFMAN A-16N126 (NEMA Type 1, 16 by 12 by 6 in, steel of 16 gauge, the gauge of the A12N128 of the same line), with its cover on two butt hinges (0 to 110 degrees), a latch and four mounting holes; 5.9 kg; the sheet metal shop of the run makes it (the family `:sheets`). Done (the loft): `World.Loft`, a shell of one thickness over sections along a spine, as a mold gives it: a superellipse at each point of the spine, in frames that move with no twist; a section of no size is an apex; an open arc gives an open shell. The inside is the thickness in from the outside, along the normal of the surface, and a rim closes each open edge. The volume of the shell of a half sphere is that of the half sphere within 1%, and the volume of an open shell is its area times its thickness within 2% (tests). The sections can be rings of measured points, and a surface grows out along its normal (`grow/2`). The headforms (dạng đầu) of QCVN 2:2021/BKHCN (from the photos of the text from the owner): the nine sizes of Bảng 1 and the polar coordinates of their sections (Phụ lục A and B) in `priv/standards/helmet.json`, with the areas that a helmet protects, the mass limits, the line AA', the limits of a rivet and of the strap, and the field of vision; the length round each section at the reference plane is the circumference of its size within 2% (a test). The first model: the half helmet of Việt Nam (mũ bảo hiểm che nửa đầu), on the headform of a size (6 by default), its rim on the reference plane, under the line AA', and its parts of Hình 2 of the regulation (with an edge trim and two rivets): a shell of ABS of 4 mm over a liner of EPS of 30 mm and 45 kg/m3 (the least thicknesses and the middle density of Trzaskalska and Chwastek, Archives of Metallurgy and Materials 66, 2021), a comfort pad of PU foam, a peak, and the retention system: a strap of webbing on each side to a side-release buckle (`World.Materials.Webbing`, standard parts for any strap). Each is a part of its own, as the main parts of a helmet in the GRSP guide (Helmet standards guide, 2025: the shell, the energy absorbing liner, the comfort padding, the retention system); 0.59 kg, under the limit of QCVN 2:2021/BKHCN (1 kg for the head sizes 4 to 9; 0.45 kg for the size 1, under its 0.8 kg); the view up from the point K is 18 degrees (5.10 b asks 7); the mold shop of the run makes it (the family `:molds`); a helmet is worn, so `World.Check` does not check its stand. Done (the shoe shop): `World.Footwear`, footwear on the last of the right foot of a person of MakeHuman (`World.Footwear.Last`, from `World.People.Human.footprint/2`; the last is the foot and 2 Paris points, the EU size is 3/2 of the last in cm), each a combination of common parts: a stack of soles (`World.Footwear.Sole`: EVA, 240 kg/m3, Footwear Science; rubber, 1.1 g/cm3; vông wood, 300 kg/m3, PROSEA), the paths of the straps and their fixings (`World.Footwear.Upper`), and the straps and the hardware of `World.Materials.Webbing`. The models, each by eye from photos: a sport sandal (xăng-đan quai hậu, the photos of Wikimedia Commons: a forefoot strap and an ankle strap closed with a D-ring and hook and loop, a heel strap from the ankle strap, a rim round the footbed; of webbing or of leather with pin buckles), a thong (dép tông: a Y of rubber with a post between the first two toes, plugged into a sole of EVA), a sandal of tire rubber (dép lốp: two straps of inner tube that cross, and a heel strap, through slits in a sole cut from a tire; the photos of Wikimedia Commons, Category: Tire sandals), and the wooden clogs (guốc mộc, flat, and guốc cao with a wedge heel of 70 mm: one wide strap nailed to the sides of a sole of vông wood on a grip pad; the photos of a clog shop in Vĩnh Long, Tuổi Trẻ News, 2023). Then the dép tổ ong (a thick sole and a vamp with a lattice of holes, of EVA, in its beige: the renders of the project TỔONG, Saigoneer, 2018; the first ones were of natural rubber, Tiền Phong, Hải Phòng, the 1980s), the geta (a board of paulownia, 270 kg/m3, on two teeth, with a hanao of cloth over cotton: the photos of Wikimedia Commons) and a slide (dép quai ngang). Each model of the catalog is a pair: the right shoe and its mirror (`World.Mirror`), the left shoe. Done (the laminate and the seat, 2026-11-03): `World.Materials.Laminate`, a laminate of glass fiber and polyester laid up by hand in a mold (`priv/standards/laminate.json`): a gel coat of 0.5 mm, then plies of chopped strand mat or woven roving, each of its mass of glass and its glass fraction; the thickness of a ply is that of the formula of ISO 12215-5 (a ply of mat of 450 g/m2 is 1.05 mm; TAP Plastics gives 1.04 mm). The chair with a seat shell of glass fiber (`World.Molds.shell_chair/1`, the kind `:chair`, the mold shop): the pan and the back of one open shell along a bent spine (`World.Loft`), a gel coat and 3 plies of mat of 450 g/m2 (3.65 mm, 1399 kg/m3), on four legs of steel tube of 19 mm (MooreCo), the sizes of a molded shell chair (806 by 476 by 552 mm, the seat at 445 mm: Herman Miller); 3.6 kg. Done (the body shop on `World.Sheet`): the body, the hood and the doors of a van are panels pressed from a blank of steel sheet of 0.8 mm (`World.Sheet.stamp/4`): the outside of each panel is the hull, as before (the box of the body is that of the hull within 1 mm, a test), and its mass is that of its sheet; the params of the body give the area of its sheet. To do: the lines of the ghe from a drawing, the engine and its bed, the shaft, the holds, the mast, the eyes on the bow, its stability in the water; bends of other angles, holes in a flange, a hem; the low part of the headform (under its reference plane) and a helmet of three quarters and a full helmet; a hull of glass fiber with its plies. | The ghe next to a photo with its sizes. The van from `World.Sheet` is the same van (within 1 mm). |
| P7. Plants | `World.Plants`: a plant grows from the rules of its species (a file of data: the trunk, the branches, the leaves, the flowers, the season), with its levels of detail (cards of leaves far away). The nursery of the world. The first species: the coconut palm, the banana, bamboo, the frangipani. Done (2026-11-04): `World.Plants` with `priv/plants/species.json` (each number with its source: Chan and Elevitch for the coconut, Sunandar and Kahar for the Pisang Awak, PROSEA for Bambusa blumeana, Criley and the Flora of China for Plumeria rubra): the coconut palm of 18 m (a trunk that leans 8 degrees and curves up, 30 fronds of 5 m with leaflets of 1 m in a V, a bunch of nuts), the banana chuối sứ (a pseudostem of 2.8 m, 11 leaves that droop, a bunch of 12 hands), a clump of tre gai (20 culms of 16 m that lean out and arch, branches on the high nodes with sprays of leaves, spiny branches low down), the frangipani (a short trunk that forks 5 times, in 3, 3, 2, 2 and 2, a rosette of leaves at each end, white flowers from May to August, no leaves from January to March). The nursery of the run grows them (the family `:nursery`). The renders next to photos (Wikimedia Commons, not in the repository) show each species; the foliage of the bamboo and of the frangipani is less dense than in the photos (`TODO.md`). | Renders next to photos of each species. The far level of a palm has less than 500 faces. |
| P8. Places from OpenStreetMap | `World.Places.OSM`: a tile of OpenStreetMap gives the buildings (from their footprints, levels and roof shapes, with the blueprints of the houses), the roads (widths and lanes), the trees (step P7), at three levels of detail. The first place: a street of Vũng Tàu. Done (2026-11-04): `World.Places.OSM` and `priv/osm/ba_cu.json` (one block of the street Ba Cu, about 200 by 200 m, from the Overpass API: 27 buildings, 9 roads, 8 trees; © OpenStreetMap contributors, ODbL): each building up to its levels (3.5 m a level, 2 levels when the data has none), with a parapet and the bands of its floors; each road of its width (Ba Cu: 26 m) cut at the box of the tile, with curbs; each tree a plant of the nursery (a frangipani when the data has no species); the points on a plane of meters at the center of the tile. 37,480 triangles at near, under 20,000 at far. The data of Vũng Tàu is sparse: no building has a height or a roof shape, only 10 have levels, and many buildings are not in it. To do: the blueprints of the tube houses on the footprints (step W1 of Vũng Tàu), the roof shapes, the sidewalks. | A render of the street next to a photo of it. A tile stays under its size limit. |
| P9. The engineers | The tools of `World.MCP` make a blueprint from the processes and the standard parts; the checks of P5 are the gate; the owner reviews each new blueprint before it goes into the catalog. Done (2026-11-03): a drawing has standard parts (`"standard": "bolt M6x50"`) and the mass of each shape (`matter`, `skin`); the tool `check_drawing` gives the errors of a drawing, the checks of a true model, its mass, its size and its parts (`World.Engineers.review/1`); the tool `propose_drawing` keeps a drawing that passes, with its request, in the store (`proposals/HASH.json`); `mix world.review HASH` shows the proposal to the owner, and `--accept` puts its drawing into `priv/drawings/` (the catalog has it after the commit of the owner). A refused proposal changes nothing. The first proposal: a chair of bamboo (ghế tre), 2.1 kg, from a client of the MCP server; it passes the checks and waits for the owner. Done (the bamboo shop, 2026-11-04): the owner asked for joints with no metal, then sent photos of the bamboo furniture of the shops in a few variants; the parts that repeat in them are now the parts of `World.Furniture.Bamboo` (a culm of tầm vông with its nodes, 2 to 7.5 cm, internodes of 15 to 30 cm, PROSEA; a rail through the legs; panels of slats, of thin culms and of lattice; a lashing of white cord in a zigzag), and seven models of the catalog combine them: a chair with a straight back (2.5 kg), two folding chairs (a back of uprights, a back of bars; each folds flat: the rear legs turn on a pin at each side, the pin is tight in the leg and turns with it, the seat turns on its rear rail through holes in the posts (the rules in `docs/format.md`, "A joint as in real life"; the butt hinges of the doors and of the enclosure follow them too: the leaf on the door turns with the door), and the clip `fold` folds it to 64 mm and opens it again), two armchairs (a back of slats, a back of lattice), a bench of three panels and a low table. The bamboo shop of the run makes them (the family `:bamboo`). The second proposal of the MCP server (pegs and bands of split bamboo, no metal) waits for the owner; the catalog has the chair of the shop. Done (the hammock shop, 2026-11-04): the owner asked for all the kinds of võng, hammocks and swings; the parts that repeat in them are the parts of `World.Furniture.Hanging`: a bed (a catenary of its length over its span; gathered, on bars or spread; cloth or a net of cords), the rig (ropes, chains, rings, hooks, carabiners, swivels in two halves, tree straps) and the anchors of the site (trees, posts, the beam of a porch, a stand). Ten models of the catalog combine them: võng lưới and võng dù of the cafés, võng xếp on its stand, a camping hammock (ENO, 538 g, its lowest point at its sit height of 46 cm), two hammocks with spreader bars (canvas, rope), a plank swing and a tire swing on a branch, a porch swing on chains from the ceiling, and an egg chair on its stand. Each swings as in real life (`docs/format.md`). The hammock shop of the run makes them (the family `:hanging`). Then (the TODO of the shop): the sizes from their sources (ENO, Sunnydaze, Yellow Leaf Hammocks, HGTV, Corderie Mansas); the egg chair bounces on its spring (108 mm, a wire of 7 mm, 108 kN/m); the camping hammock with its stuff sack, packed in it, and under a tarp and a bug net; the võng xếp on the real frame of Duy Lợi, which folds in its steps; and a person who lies in the camping hammock, the bed under the weight. Then: the parts that stretch (the coils of the spring stretch as one, a skin between two nodes), the width of the frame of the võng xếp folds too, the diagonal lay, and people on the café võng, the hammock with spreader bars, the plank swing, the tire swing, the porch swing and in the egg chair. Then the owner saw parts of the egg chair through the person: a person now leans as far as they want and stops where the body touches a thing (`World.Contact`): back and to the side to the wicker of the egg chair, back to the slats of the porch swing. Then the owner asked for cushions sewn by `World.Sewing`: the cushion maker of the sewing shop (`World.Sewing.Cushion`) cuts a cover from its pieces over foam or fiber; the egg chair has a seat cushion in its bowl and a back cushion with tufts, the porch swing a seat cushion and a back cushion tied to its top slat, the plank swing a pad tied to its ropes. A person sinks into the fill and leans back to the cushion. Then the sewing shop of the run (the family `:sewing`, the foreman Thảo and the worker My) makes the mattresses: a mattress is a box cushion of layers on a core in a cover of ticking, with a tape on each seam and a quilt on its top, of the fills of a mattress (natural latex, memory foam, HR foam, pocket coils, coir), each with its density and its source: nệm cao su (latex, 160 by 200 by 10 cm), nệm lò xo túi (pocket coils, 25 cm) and nệm xơ dừa (coir, 120 by 200 by 10 cm). A hard cushion is a hard foam, with a board of plywood under it for a drop-in seat; the bamboo chair has a hard pad (`ghe_tre_dem`). | An engineer (a client of the MCP server) makes the blueprint of a bamboo chair from a request; it passes the checks, and the owner accepts or refuses it. |

## Open questions for the owner

- **The lines of the ghe (step P6).** The ghe has the sizes of
  BV-92479-TS, and its stern, stem head and paint follow the photos of
  the owner, but its plan, sheer and sections are by eye. A drawing of
  the lines of a wooden fishing boat of Vũng Tàu, or the sizes of one
  of the boats of the photos, make it true. The
  group of the wood (TCVN 12619:2019) of sao đen is a question too: the
  model takes group III, the largest sizes.

- **The scale of the clock.** One second of the wall clock is one day of
  the world (86,400). Step W7 measured the edge again: the code there
  is 2 to 3 times slower than native code, so the scale stays.

- **The sources of the other vans (step W8).** A van of the line needs
  the traces of its side (the Transit has them from the drawings of
  Outlines and a photo of the owner), its sizes, and a side photo of a
  dealer for the check. Found on 2026-10-31:
  - The sizes. The Sprinter (VS30, 144 in and 170 in, high roof): the
    page of the cargo van of Mercedes-Benz Vans Canada (length 234 and
    274 in, height 107 in, overhangs 40 and 49 or 64 in, rear door 61 by
    73 in). The ProMaster (2014 to 2022, 136 in and 159 in, high roof):
    the Ram brochure of 2018, page 22 (length 213.1 and 236.1 in, width
    80.7 in, height 99.4 in). The crew van of the Transit (148 in): the
    columns of the cargo van in the Ford Technical Specifications of
    2025, page 4; Ford gives no sheet for the crew van itself.
  - Not found: the overhangs, the tracks and the tires of the ProMaster;
    the second row and the windows of the crew van; any scaled side view
    from a body builder guide (the guides of Mercedes-Benz, Ram and Ford
    refuse this computer: 403 or 503); any side photo of a dealer.
  - The drawings of Outlines (getoutlines.com) of each van exist, at
    24 USD each, and their previews show the side.

  The owner can give one of these: the PDF of each body builder guide,
  the drawings of Outlines (or permission to buy them), or side photos
  of the three vans. With them, W8 continues as F3 did for the Transit.
  On 2026-11-01 the owner sent the renders of the ProMaster from the
  page of Ram, and the ProMaster with a high roof is in the line. The
  Sprinter guide (28 MB) is with the owner: the side pages and the size
  tables, a folder shared to the session, or a link, let the Sprinter
  start. The crew van needs side photos of its windows and its second
  row. On 2026-11-01 the owner sent pages of the guide of the Sprinter:
  its drawing of the high roof van is to scale, and the Sprinter with a
  high roof is in the line. The height of the drawing (2.614 m) is lower
  than the US page (107 in, 2.718 m). The standard roofs of the
  ProMaster (118 in, 136 in) and of the Sprinter (144 in) are in the
  line too. For the standard roof the US page also gives more (100 in,
  2.54 m) than Mercedes-Benz Australia (2331 mm) and the guide (about
  2355 mm, hard to read on page 300). The owner decided: the sizes are
  numbers of the order, with the US sizes as the default; an order for
  another market gives its own.
  The top of the windshield of the high roof (2.33 m, from point t of
  page 65 of the guide) is higher than that of the drawings of
  Mercedes-Benz Australia (2.17 m for both roofs); the model of the
  standard roof has 2.17 m.

