# The world

The world is the next step of Xưởng. Today the factory (`docs/factory.md`)
takes an order and gives the files of a model. In the world, people make
the model, as in the real world. A storekeeper picks the parts from a
warehouse. A driver brings them to the factory. The workers on the
line put them together. The places of the world are buildings, and
people build them too, from bricks, studs and the other materials of
Xưởng.

The world is not a picture on top of the factory. Each thing in it is a
real thing of the computer. A warehouse is a store of files. A factory
is the VM that builds. A vehicle is a transfer. The clock is the
wall clock. The replay shows what happened, with the real times.

This document is the plan. The owner reads it and changes it before the
work starts. The code is the source of truth after that (`AGENTS.md`).

## The words

| Word | What it is |
|---|---|
| **World** | The places, the roads, the people, the vehicles, the stock and the clock, in one assembly. |
| **Place** | A building with a position: a warehouse, a factory, a supplier, a yard, the site of a customer. A place is a model of Xưởng (`Xuong.Models.Houses`): people build it. |
| **Warehouse** | A place that keeps stock. Its size is the limit of its store. |
| **Factory** | A place with lines and stations, where the workers build. |
| **Supplier** | A place outside the world that gives a part the world cannot make: the data of MakeHuman, the drawings of a maker, a supplied part of an order. |
| **Road** | The way from one place to another, with its length. A vehicle drives on it. |
| **Stock** | The parts and the models that are in a warehouse now, each with its count. |
| **Person** | A figure (`Xuong.Figure`) with a job, at a place, with one task at a time. |
| **Job** | What a person does: storekeeper, driver, worker of a station, foreman. Later: engineer, architect. |
| **Vehicle** | A model of Xưởng that moves parts: a van, a truck, a cart. A driver controls it. |
| **Order** | A request for a model: the order of the factory (`docs/factory.md`), or an order of the world for a part, a delivery or a building. |
| **Plan** | The list of the tasks of an order, from the tree of its assembly, with the station of each task and what it waits for. |
| **Task** | One step of a plan for one person: pick a part, load, drive, unload, connect a part to its parent, store. |
| **Event** | One thing that happened, with its time, its place, its person or vehicle, and its order. |
| **Log** | The events in the order of their time. The log is the truth of the world: the replay and the statistics come from it. |
| **Replay** | The world in 3D from the log, at any speed: the vehicles drive, the people walk and carry, the model grows on the line. |
| **Clock** | The wall clock. The time of a task is the real time the code took. |

## What is real

Each thing of the world is one thing of the computer. The table gives
the rule. A new thing in the world comes with its real thing, or it
does not come.

| In the world | In the computer |
|---|---|
| A warehouse | A store of files: the R2 bucket of the orders (`xuong-orders`), the catalog in the release (`priv/models`), the memory of the VM (the cache next to the line), the cache of a project (the R2 of Phượt). |
| The size of a warehouse | The limit of its store: the plan of R2 that the owner sets, the size of the release, the memory of the VM. The stock can not pass it. |
| The stock of a warehouse | The files in the store, by the hash of their order. A part in stock is built: nobody builds it again. |
| A factory | The place where the code builds: the VM at the edge (the Durable Object), `mix xuong.build` on a computer, CI. |
| A line and its stations | The stations of a model (`params.station` of each part): the body shop, the closures, the paint, the trim, the chassis, the upfit of a van. |
| A worker | A process of the BEAM that runs the tasks of one station. Two workers are two processes: they build two parts at one time. |
| A storekeeper | The process that reads and writes the store. |
| A driver and a vehicle | A transfer of files from one store to another: from R2 to the VM, from the VM to R2, from Xưởng to a project. |
| A road and its length | The time of a transfer, measured. |
| A supplier | A source outside: a file of `priv/`, a URL, a supplied part in an order. |
| The clock | The wall clock of the VM. Each event has its real time. |
| The time of a task | The real time that the code of the task took: the build of a part, a transfer, a read of the store. |
| A person | A process (`GenServer`) with a mailbox. Its body is a figure of Xưởng, with the poses `walk`, `carry` and `work`. |
| The foreman | The process that makes the plan of an order from its assembly, and gives each task to a person. |

The replay shows the real log. A person that walks across the factory
in the replay is a process that waited for a part. A truck on the road
is a transfer in progress. Nothing in the replay is invented.

## The places

A place is a building. The materials of Xưởng make it: bricks and
concrete blocks, lumber studs, OSB, siding, metal panels, doors and
windows (`Xuong.Models.Houses`, `Xuong.Parts.Building`). A place is an
order too: the people of the world build it from its materials, and the
log has its build.

| Place | What it has | Its size |
|---|---|---|
| A warehouse | Racks (`Xuong.Models.Frames`: strut channel, shelves), a dock, a yard. | The limit of its store, in files and in bytes. The racks show the stock: a full rack is a full store. |
| A factory | Lines with stations, a dock for the parts, a yard for the finished models. | The number of its workers (processes) and the memory of its VM. |
| A supplier | A gate: the parts come from outside. | None. |
| The site of a customer | Where a delivery ends: Phượt, DIY, Vũng Tàu, Humans Must Die. | None. |

Each place has a position. In the first world, the positions are in
meters, in one flat frame, on a yard of Xưởng. Later, a place can have a
latitude and a longitude, so the world of Phượt puts the factory on its
map.

## The people

A person is a figure of Xưởng (`Xuong.Models.People`), with a name, a
job and a place. A person does one task at a time, and walks between
the tasks. The time of a walk is real: the person walks while the
process waits.

| Job | The tasks |
|---|---|
| Storekeeper | Check the stock. Pick a part from a rack. Put a model on a rack. Refuse a part when the warehouse is full. |
| Driver | Load a vehicle at a dock. Drive on a road. Unload at a dock. |
| Worker | The tasks of one station of a line: connect a part to its parent at its port, in the order of the plan. |
| Foreman | Make the plan of an order. Give each task to a free person. Ask a supplier or another factory for a part that is not in stock. |
| Engineer, architect (later) | Read the log. Propose a new process, a new part or a new model. |

A person is a process. Its mailbox holds its tasks. A person with no
task stands at its place. The world does not stop when a person waits:
the other people work.

## An order, from start to end

The example is a van of the blueprint `van`.

1. **The order comes in.** `POST /orders`, or an order from the world
   itself (a building, a part for another order). The log gets
   `order_received`.
2. **The foreman makes the plan.** The tree of the assembly gives the
   tasks. Each node after the root is one task: "connect this part to
   that node at that port", at the station of the part. A task waits for
   the task of its parent node. Two tasks that do not wait for each
   other can run at one time. The parts list of the assembly gives the
   parts to get.
3. **The storekeeper checks the stock.** A part with its hash in the
   store is in stock: the storekeeper picks it. A part that is not in
   stock becomes an order of its own: the world builds it in the same
   factory or in another, or asks a supplier. The wheels of the van are
   an order of four wheels; a wheel is a tire on a rim.
4. **The driver brings the parts.** The parts go on a vehicle at the dock
   of the warehouse, drive on the road, and come off at the dock of the
   factory. The time is the time of the transfer.
5. **The workers build.** Each station takes its tasks in the order of
   the plan. The body shop makes the body on the hull. The closures hang
   the doors. The trim puts the glass, the lamps and the seats. The
   chassis marries the engine bay and the wheels. The time of each task
   is the time the code took to make that part.
6. **The model goes to the warehouse.** The storekeeper puts the files in
   the store, under the hash of the order. The log gets `model_done` and
   `stored`.
7. **The delivery.** A driver brings the model to the site of the
   customer: the project reads the files. The log gets `delivered`.

A second order of the same van finds it in stock: step 3 picks it, and
the order ends at step 7. That is the cache of the factory today, seen
as a warehouse.

## The plan from an assembly

An assembly is a tree. The first node is the root. Each other node
connects to a node that comes before it. This order is the order of the
work, with no new data:

| In the assembly | In the plan |
|---|---|
| The root item | The first task: make the root part, or get it from stock. |
| A node with a `fixed` connection | A task: connect the part to its parent at the two ports. |
| A node with a joint (`turns`, `slides`) | The same task, and the joint goes into the log of the model. |
| A node that holds a smaller assembly | An order of its own, in the same factory or in another, then one task to connect it. |
| `params.station` of a part | The station of the task. |
| The parts list (`Xuong.Build.parts/1`) | The parts to get from stock. |

The time of a task is not in the assembly. The world measures it when
a worker does the task, and the log keeps it. The second plan of the
same model knows the times of the first, and the foreman can give the
long tasks first.

## Time

Time is real. The clock of the world is the wall clock of the VM. The
log keeps the real time of each event, in UTC, with milliseconds.

- The time of a task is the time the code took: the build of a part,
  a transfer, a read of the store.
- The time of a walk of a person is the time the process waited for
  its next task.
- The time of a road is the time of the transfer on it, measured.

The replay runs the log at any speed: one hour of the world in one
minute, or in real time. The statistics come from the log: the time of
an order from `order_received` to `delivered`, the time of each station,
the stock of each warehouse over time, the orders by blueprint.

## The events and the log

An event is one line of JSON. The log is the events in the order of
their time, in the SQLite of the VM, and in R2 as one file for each
order (`/o/HASH.log.json`).

| Event | Who and where | Data |
|---|---|---|
| `order_received` | The factory | The order and its hash. |
| `plan_made` | The foreman | The tasks and their stations. |
| `stock_checked` | The storekeeper, the warehouse | Each part: in stock or not. |
| `part_ordered` | The foreman | The order of the part, to which factory or supplier. |
| `picked`, `stored`, `refused` | The storekeeper, the warehouse | The part, the rack, the stock after. |
| `loaded`, `departed`, `arrived`, `unloaded` | The driver, the vehicle, the road | The parts on the vehicle, the time of the road. |
| `task_started`, `task_done` | The worker, the station | The task, its part, the time it took. |
| `model_done` | The factory | The hash, the size of the files. |
| `delivered` | The driver, the site of the customer | The project that reads the files. |
| `build_started`, `build_done` | A place | A new building of the world, from its own order. |

Each event has: `at` (the time), `order` (the hash), `place`, `person`
or `vehicle`, `kind`, and the data of its kind. A test reads a log and
checks three things: the events are in order; the stock after each
event is never less than zero and never more than the size; each task
started after the task it waits for ended.

## The replay

The review page gets a page of the world. From a log, it shows:

- the places, as their building models;
- the stock on the racks of each warehouse;
- the vehicles on the roads, at the time of each event;
- the people, with the poses `walk`, `carry` and `work`, at their
  tasks;
- the model on the line, with one part more at each `task_done`.

The replay is a model of Xưởng too: an assembly of the world at a time,
with a pose for each person and each vehicle. So the files of the world
at a time are GLB files, and a project can show them.

## The scales

The world builds the models for each project of the owner, at its
scale:

| Project | Scale | What it takes from the world |
|---|---|---|
| DIY | A house | The items of a house, the vans, the builds of wood, as today. |
| Vũng Tàu | A city | The buildings, the vehicles, the people of a city, in Godot. |
| Phượt | A country, the roads of a trip | The vehicle of the traveler, the places along the road; later, the factory on its map. |
| Humans Must Die | A planet | The models of a planet, from the same parts. The owner gives the needs of this project: this document has only its scale. |

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

## The decisions

| Topic | Decision | Why |
|---|---|---|
| The name | Xưởng stays for now. The owner decided to rename the project "World" after the foundation of the world is in place. | One rename, at one time, when the shape of the world is clear. |
| Real, not invented | Each thing of the world is one thing of the computer, and each time is a measured time. | The replay is a record, and the statistics are true. |
| The log is the truth | The replay, the statistics and the engineers read the log only. | One source. A test reads a log. |
| A place is a model | A warehouse and a factory are orders, built by the people from the materials of Xưởng. | The world builds itself from the ground up. |
| People are processes | One `GenServer` for each person, one mailbox of tasks. | The BEAM is made for this. A person that waits does not stop the world. |
| The plan comes from the assembly | No new data for the plan: the tree, the stations and the parts list of the assembly. | Each model of Xưởng is buildable in the world with no change. |
| The crew van of the Transit | It comes with the Sprinter and the ProMaster, after the first world. | The owner wants the crew van in the line. Ford does not sell it for 2024 to 2027: its sizes come from the earlier years. |

## The steps

Each step is a small series of commits on `main`, with tests at 100%
and a picture of the replay where there is one.

| Step | Result | Check |
|---|---|---|
| W0. The plan | This document. | The owner agrees, or changes it. |
| W1. The data of the world | `Xuong.World`: places, roads, stock, people, jobs, vehicles, the clock, the events and the log. The plan of an order from its assembly (`Xuong.World.Plan`). | A property test: the plan of each model of the catalog has one task for each node, and each task waits for the task of its parent. A log with a bad order of events is refused. |
| W2. One thin slice | One order of a van. One warehouse, one truck with its driver, one factory with a foreman and two workers. The people are processes. The log of the order, with real times. | A test runs the slice and reads its log: the van is delivered, the events are in order, the stock is never negative. The same order a second time comes from stock. |
| W3. The replay | The page of the world on the review page, from a log. The world at a time as a GLB. | A picture of the truck on the road, and of a worker at the trim station with the seats. |
| W4. The buildings | The warehouse and the factory are orders: the people build them from bricks and studs, and the log has the build. The racks show the stock. | The log of a build of a warehouse. The size of the warehouse from the limit of its store. |
| W5. The stores | The warehouses are the real stores: R2, the release, the memory of the VM, the cache of a project. The stock is the files. A full warehouse refuses. | A test with a small limit: the storekeeper refuses, and the foreman sends the model to another warehouse. |
| W6. The site | The orders of the projects go through the world at <https://3d.mkfifo.com>. `/o/HASH.log.json` and the replay of an order. | An order of Phượt gives its files and its log. The times in the log agree with the times of the service. |
| W7. The other vans | The Sprinter, the ProMaster and the crew van of the Transit, built on the line of the world. | As the Transit: a render next to the photo of the dealer. |
| W8. The engineers | Later, with the owner. | — |

## Open questions for the owner

- **The positions of the places.** Meters on a yard of Xưởng first, or
  the real map of Phượt from the start?
- **One warehouse for each store, or one store with many warehouses?**
  The R2 bucket is one store. Many warehouses in it are folders with
  their own limits.
- **Humans Must Die.** What the planet needs from the world: the kinds
  of models, their levels and their counts.
