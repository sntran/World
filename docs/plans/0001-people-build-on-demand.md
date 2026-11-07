# 0001 The people build on demand

| Field | Value |
|---|---|
| Status | In progress |
| Depends on | The matter of World as it is (`docs/format.md`), the drawing format (`docs/format.md`, "A drawing"), the MCP server (`World.MCP`), the stores (`World.Store`), the log (`World.Log`). |
| Changes | `docs/world.md` (the world layer: the run, the foreman, the workers), `specs/Order.tla`, `docs/factory.md` (the calls of the site), plan 0023 of Vũng Tàu (the fetch at compile time) and a new plan of Vũng Tàu (the QA mode). |

## 1. Goal

World is an Erlang node. Its people are processes. A game, or a person
at the web page, sends a job: a blueprint and a budget. World looks at
the constructions in progress and the people free, gives the job its
share of the people (an architect, an engineer, a foreman, workers of
the trades, a driver) and opens a construction. The crew builds from the
ground up: the foundation, the pours, the walls, the roof. The game
watches the model grow element by element over a connection, can pause
it, and can change the request midway.

World has no code for "a statue" or "a van": it has materials, standard
parts, the skills of the trades (lay a wall, cast concrete, turn a post,
bend a sheet) and people. The blueprint is data that an architect
outside World writes (a person or an LLM). World keeps the models it
built and the common components, and builds the rest on demand.

At <https://world.mkfifo.com> a person sees the world itself: the
people, then the vehicles and the factories they build, then each
construction as it happens.

At the end of this plan:

- The people of the node build each model, element by element, and
  many constructions run at one time on one node and share the people.
- A game watches a build over one connection, pauses it, changes it,
  and keeps the finished model.
- The statue on Núi Nhỏ is a drawing (data), built with the skills of
  the trades, with no code of its own. The other kinds of things follow,
  one at a time.
- The web page is the world.

## 2. What is wrong today

The people of the world exist (`World.Run` starts a foreman and workers
as processes), but they do not build the model. A worker computes a part
and throws it away (`lib/world/people/worker.ex`); the foreman then
builds the whole model again, alone (`lib/world/people/foreman.ex`,
`deliver/2`). The hard work of a statue happens before the first task,
in one call of `World.Statues.statue/1`. The model comes out only at
the end, as one file. A game cannot watch, pause or change anything.
And each kind of thing is a code module (`World.Statues`, `World.Towers`,
`World.Vehicles.Van`, `World.Buildings.Lot`): a new kind of thing is new
code.

## 3. Out of scope

- A WebSocket (two ways on one connection). Server-sent events first.
- The engineers that read the log and change a plan (more workers on a
  slow trade, a component that many jobs share).
- A crane and a scaffold as things of the site.
- The materials of an element by the cubic meter.
- An export of a drawing to IFC.
- Skills as tools of an MCP server outside the repository.
- The stream to the map of Phượt.
- The code of Vũng Tàu: this plan writes a draft plan for it (step 6).

## 4. Decisions

| # | Decision | Reason |
|---|---|---|
| D1 | An architect outside World (a person or an LLM) writes the blueprint of a new thing, as data. World checks it and builds it. The code for each kind of thing goes away as its blueprint becomes data. | World needs only materials, parts, skills and people. A new kind of thing is a new drawing, not new code. The owner, 2026-11-07. |
| D2 | The budget of a build is computer limits: seconds of real time, memory, and the size of the model (triangles). | A phone asks for a small model, a desktop for a big one; the edge has 128 MB. The owner, 2026-11-07. |
| D3 | A game gets a model at run time, when it needs it, and keeps it after. The same calls serve a fetch at compile time. | Vũng Tàu takes its known places at compile time, and in a QA mode the owner asks for a house at an address and watches it go up. The owner, 2026-11-07. |
| D4 | Keep the matter (meshes, materials, standard parts, the GLB writer, the drawing format, the checks, the log, the stores). Replace the world layer (the run, the foreman, the workers) with the people of the node. | The matter works and has its tests. The world layer does not do what the vision says. The owner, 2026-11-07. |
| D5 | No nested namespace. `World` is the door of the node; `World.Supervisor` is its supervisor; `World.Construction` is one build; `World.Person` is one person; `World.Store` keeps the files (it exists). | The owner, 2026-11-07. |
| D6 | Many constructions run at one time on one node, and they split and share the people. | A node is a city, not one factory. The owner, 2026-11-07. |
| D7 | The words: an **element** is one piece of a thing (a wall, a pour, a stair, a cabinet); a **task** is the work of one element; the **sequence** says which task comes after which. These are the words of IFC (section 5, R4). | One vocabulary for a house, a statue and a van, and the vocabulary of the building standard. The owner, 2026-11-07. |
| D8 | A **skill** is one module of the behaviour `World.Skill`: the work of a trade on its data. Others can contribute a skill, or a better skill of the same name. | A skill is the common pattern of a building site and of an agent. The owner, 2026-11-07. |
| D9 | The web app is the world: people first, then the vehicles and the factories being built, then each construction in real time. | The owner, 2026-11-07. |
| D10 | There is no line between a building and another thing. A camper van is a house on wheels: its cabinets, its insulation, its wires and its appliances are elements of the same kinds as in a house. A cup is one element of one task. One drawing holds every thing. | The owner, 2026-11-07. |
| D11 | The drawing of World stays its own small JSON. It takes the words of IFC (element, storey, material, task, sequence) and the names of elements of IFC where IFC has one (a wall, a slab, a stair, a cabinet), and the word of World where IFC has none (a wheel, a hull, a robe). An export to IFC can come later. | The full IFC is hundreds of kinds of things, too big for the builder at the edge. A person who knows BIM reads the drawing. |
| D12 | The clock stays: one second of the wall clock is one day of the world. The log of a construction is the truth: the web page and the statistics read it. | `docs/world.md`. |
| D13 | `World.Supervisor` is the module of the supervisor of the node, and `World.Application` starts it. Its children: `World.Census`, the registries `World.Names` (a construction by its id) and `World.Events` (the watchers), the dynamic supervisors with the names `World.Persons` and `World.Constructions` (names, not modules), the log of the node, and Bandit when `WORLD_SERVER` is set. | Flat names. A supervisor decides nothing. |
| D14 | `World.Census` keeps the pool of the people: the free people of each trade, the people that each construction holds, and the queue of the constructions that wait. The construction that holds fewer workers gets the next free person first. A construction hires and lets go through `World.Person.hire/2` and `World.Person.release/2`. | D6 and R5. |
| D15 | In step 1, the work of a worker is the triangles of the meshes of its element (`World.Mesh.triangles/1`, the pass of Wings: the cost of a build). `World.Build.scene/2` takes them with the option `triangles`, in place of its own memo, so the file has the same bytes. From step 2, a worker also runs the skill of its element. | The worker does real work, and the construction joins the elements with no second pass. |
| D16 | At the edge, one Durable Object with the name `world` is the node: the people, the constructions, the stream and the log. The four builders of today go. A file that R2 has still goes out with no VM. | One node, one census. The memory budget (R22) keeps one or two builds at one time there. |
| D17 | `POST /builds` with `accept: text/event-stream` gives the stream at once: the request keeps the Durable Object alive while the people build. With `accept: application/json` it gives the id and the plan. | A Durable Object with no open request can stop. A client that watches keeps it. |
| D18 | The log of the node goes into the SQLite of the Durable Object through the port `/env/LOG_STORE`, in batches, as the orders go to R2 through `/env/ORDER_STORE`. The full log of a build also goes to R2 as `/o/HASH.log.json`. | A page that opens later replays the history (with `Last-Event-ID`), then follows the stream. A deploy starts the Durable Object again. |
| D19 | A blueprint in data has parameters: `params`, with the types of the options of `World.Orders.Blueprint` (a default, a minimum, a maximum, a unit, a text). A value of a drawing can be `{"param": "height"}`. The files are in `priv/blueprints/`, next to the blueprints in code. A model of the catalog is an order of a blueprint (`priv/drawings/NAME.json` with `blueprint` and `options`). | Vũng Tàu orders the statue, the tower and the lot house with options. A drawing with no options cannot do that. |
| D20 | A node of a drawing can be an element made by a skill: `{"name", "skill": {"cast": {...}}, "trade", "after", "from"}`. `from` names the elements whose data it takes. A skill gives the part (or the smaller assembly) of the element, its data for the elements that take it, and model extras, which go into the model in the order of the nodes. A drawing also gets `extras`, the kinds `statue`, `tower` and `house`, and the role `open`. | A statue needs the data of its figure, a lot house the data of its plan, a van the data of its hull. The extras hold `site`, `sizes`, `ports`, `collision` and `surface`. |
| D21 | The code of a kind does not go away: it becomes skills of the trades in `lib/world/skills/`. What goes is the module of the kind and its blueprint in code. The elements, their sequence and their numbers become data. | The lot house has 1,639 lines of rules, and the line of the vans has about 2,500 lines. A skill keeps them, so another person can make a better skill. |
| D22 | `World.Places.family_of/1` becomes `World.Plan.trade/1`: the kind of an item gives the trade of its workers. | The new world has trades, not factories by family. |
| D23 | A person has its PID as its name in the log (`"<0.123.0>"`). | The owner, 2026-11-07 (Q3). |
| D24 | A construction has a priority alias (Erlang/OTP 28, EEP 76): the deadline comes to it as a priority message (`:timer.apply_after/4`, because a timer cannot send to an alias), and so do the pause, the resume, the cancel and the change (step 3). It watches each person that it holds with a monitor of priority, and the census watches the constructions and the people in the same way. | The results of the people fill the mailbox of a construction (thousands for a house of bricks). A message of priority does not wait behind them. The owner, 2026-11-07. |
| D25 | Each worker has a limit of its heap, its part of the memory budget, with its shared binaries (`max_heap_size` with `include_shared_binaries`, Erlang/OTP 27). A worker over its limit stops alone, and its task fails with the reason `memory` (step 3). | The edge has 128 MB. One big element must not stop the VM and each construction in it. |
| D26 | Each process of the node has a label (`Process.set_label/1`): `{:person, job, trade}`, `{:construction, id}`, `{:stream, key}`. | A crash report and the observer name the person or the construction, not only a PID. |
| D27 | The watchers are in a registry with duplicate keys in partitions by key (`keys: {:duplicate, :key}`, Elixir 1.20). | A dispatch to the watchers of one construction reads one partition only. |
| D28 | The sequence of the elements of a drawing is a graph (`:graph`, Erlang/OTP 29): its check finds a cycle (`get_cycle`), and a build with no world takes the elements in the order of `topsort` (step 2). | A functional graph of the standard library, with no table to delete. |
| D29 | A check of a whole number in a range uses the guard `:erlang.is_integer/3` (Erlang/OTP 29), for example the workers of a budget, 1 to 64. | One guard, and a float is not a whole number. |
| D30 | The cast of a statue is one task (the skill `shell`), not pours from the feet up. A test in step 2 showed that the pass of the distances of `World.Cast` depends on the order of the triangles: the first nearest sample of a cell wins, and a sample adds to the sums of a loose cell only when it is not the nearest at that time. So pours in parallel, merged after, give other bytes. The blueprint of the statue is `priv/blueprints/statue.json` (the options of before as params), and the statue on Núi Nhỏ is an order of it in `priv/drawings/`. | The bytes stay the same (R7). A cast in pours needs a new pass of the distances, with its own files: an idea for later (`TODO.md`). |
| D32 | A change comes in a pause, as a call (it needs an answer), and it keeps the nodes of the drawing: a drawing with other nodes is a new build. The key of a node is a hash of its data and of the keys of the nodes that it waits for, so a change of a node changes each node after it. A task in hand that a change makes again ends for nobody (`task_dropped`). In `specs/Build.tla` a change is one `Redo` for each task, the tasks after a task first. | The tasks of the plan stay the same, so the replay of a log with a change is one behavior of the specification. |
| D33 | The memory budget (step 3) is `memory_mb`: each person runs a task in a process of its own with a limit of its heap (its part of the budget), and a task over it fails with the message `memory`. Two parts of R22 are not done yet: the node does not wait for room in the memory before it opens a construction, and the estimate of a skill does not come from the log (Q1). | One big element stops alone, not the VM. The rest needs measures at the edge (`TODO.md`). |
| D31 | A node of a drawing that a skill makes is one task of a construction, and the key of the GLB of an element is a hash of its meshes. The elements go to the watchers in the order of the nodes: a node is in the model when the nodes before it are made. | A person makes the part of a skill on its own; the hash needs no count that the people share. |

The other new features of Erlang/OTP 28 and 29 and of Elixir 1.19 and 1.20 are not used: native records are experimental and Elixir has no syntax for them; the zip, strict and multi-valued comprehensions are syntax of Erlang only; nominal types are for Dialyzer, which World does not use; and the people already hibernate after each task (`erlang:hibernate/0` adds nothing for a `GenServer`). The type inference of Elixir 1.20 checks each commit, because `mix precommit` compiles with the warnings as errors.

## 5. Requirements

### The people of the node

- **R1.** `World` is the door of the node: `World.build(blueprint, budget)`,
  `pause/1`, `resume/1`, `change/2`, `cancel/1`, `watch/1` (the events
  of a construction) and `census/0` (the people and what they do). The
  rules of the budget and of the share of the people are plain
  functions here.
- **R2.** `World.Supervisor` is the supervisor of the node (today
  `World.Application` starts it). It starts the store, the people and
  the constructions (a `DynamicSupervisor` for each). It decides nothing.
- **R3.** `World.Construction` is one build: a process that holds the
  blueprint, the plan (the tasks and the sequence, from `World.Plan`:
  one task for each node of the assembly), the elements done, and the
  log of the build. It hires people, gives each ready task to one of its
  workers of the trade, takes each finished element, sends it to the
  watchers, and joins the elements into the model at the end (one pass
  of `World.Build.scene/2`, from the elements the workers made, not a
  build again). It pauses and resumes. On a change it keeps the elements
  whose task is the same (the same data, the same sequence) and redoes
  the rest. It stops at the deadline of the budget and gives what is
  done.
- **R4.** `World.Person` is one person: a process with a job (architect,
  engineer, foreman, mason, carpenter, steelworker, caster, driver,
  storekeeper), a trade and a place. A worker makes one element at a
  time and gives it back. A driver moves files between stores. A
  storekeeper keeps a store. A person is a process while they have work;
  `World.census/0` counts them.
- **R5.** The pool of people is shared. A construction hires a free
  person of a trade (`World.Person.hire/2`), waits when none is free,
  and lets the person go when the task is done. Each construction holds
  at most its budget of workers at one time. A construction that waits
  gets the next free person before one that holds more (a queue by the
  count held).
- **R6.** `World.Store` keeps the files of the models by the hash of
  their job, as today (the memory of the VM, an R2 bucket, the catalog
  of the release). A job whose model is in a store is delivered from
  the store.
- **R7.** The same job gives the same bytes: with one worker, with
  eight, and with two constructions at one time. The order of the nodes
  of the assembly fixes the order of the meshes in the file; the
  schedule of the workers does not touch it.

### A blueprint is data

- **R8.** A drawing (`docs/format.md`, "A drawing") gets the skills: a
  shape of an element can be the result of a skill of a trade with its
  data, for example `{"wall": {"line": [...], "height": 3.0, "unit": "brick_vn"}}`
  (a mason lays it from bricks), `{"cast": {"surfaces": "figure", "step": 0.32, "hollow": 0.3, "openings": [...]}}`
  (a caster pours it in forms), `{"stair": ...}`, `{"turn": ...}` (the
  lathe), `{"bend": ...}` (the sheet shop), `{"roof": ...}`,
  `{"figure": ...}` (a person of MakeHuman in a pose).
- **R9.** A skill is a module of the behaviour `World.Skill` in
  `lib/world/skills/`: `name/0`, `trade/0`, `check/2` (the errors of its
  data, with their paths, as a drawing is checked today), `make/2` (the
  data and the inputs give a part) and `estimate/1` (its size, for the
  budget). A skill is pure: no clock, no random number, so a job gives
  the same bytes each time. The first skills are thin doors to the
  functions that exist: `World.Buildings.masonry_wall/5`, `World.Cast`,
  `World.Lathe`, `World.Sheet`, `World.People.Human`. A new skill is one
  module; a better skill of the same name replaces it.
- **R10.** A node of a drawing can name the tasks it comes after
  (`"after": ["foundation"]`) and the trade that makes it
  (`"trade": "mason"`). With no `after`, a node comes after its parent,
  as `World.Plan` does today. The order of a real site (the base, the
  pours from the feet up, the stair, the halo) is in the drawing,
  written by the architect.
- **R11.** A node is one element of the stream: when a worker finishes
  it, the watchers get it.
- **R12.** Each size has its source or says it is an estimate, as today.
- **R13.** The limits of a drawing grow for a building (today 64 parts
  and 128 nodes). A wall of 5,000 bricks is one line of the drawing: the
  skill makes the bricks inside one element.
- **R14.** The code of each kind of thing moves into `priv/drawings/`
  as data, one at a time, with the review page as the check (the same
  picture before and after): the statue first (the skills `figure`,
  `cast`, `stair`, `rail`, `halo`), then the tower, then the houses on a
  lot, then the vans. The module of a kind goes when its picture is the
  same.
- **R15.** The MCP tools of the outside architect: `check_drawing` and
  `propose_drawing` as today, `plan_build` (the plan of a drawing: the
  tasks, the trades, the estimate) and `build` (start a job).

### The stream

- **R16.** `POST /builds` with `{"blueprint": ..., "options": ..., "budget": {"seconds": 30, "memory_mb": 64, "triangles": 40000}}`
  takes the job: `{"build": ID, "plan": [...], "estimate": {...}}`, or
  a refusal with the reason. A job whose model is in a store answers
  `done` at once.
- **R17.** `GET /builds/ID/events` is the stream of the build, as
  server-sent events: `plan` (the tasks), `started` (a task, its
  worker), `element` (a task done: its name, its place in the model,
  the URL of its small GLB `/builds/ID/NAME.glb`), `paused`, `resumed`,
  `changed` (the elements kept and the elements redone), `done` (the
  URLs of the finished files: near, mid, far, parts, log, replay),
  `stopped` (the budget ran out: the elements so far, and why).
- **R18.** `POST /builds/ID/pause`, `/resume`, `/cancel`; `POST /builds/ID/change`
  with a new blueprint; `GET /builds/ID` gives the state now, for a
  watcher that reconnects (the plan, the elements done, the files when
  done).
- **R19.** `GET /events` is the stream of the whole world: each event of
  each construction and of the people. The web page reads it.
- **R20.** The files of a finished build go into the store under the
  hash of the job, as today under `/o/HASH`. `World.Orders.build/3`
  makes the files of an order through a construction, so the files and
  the URLs of today stay for the games.

### The budget

- **R21.** Seconds: the estimate comes from the log of earlier builds
  of the same skills (the time of each task by the size of its element;
  `estimate/1` of a skill gives the size). Over the budget, the job is
  refused with the estimate. During the build, the construction stops at
  the deadline, sends `stopped` with the elements done, and stores
  nothing: a partial model is not a model of the store.
- **R22.** Memory: a construction opens only when the memory of the VM
  has room for its estimate, and hires as many workers at one time as
  the room allows (at the edge, 128 MB: one or two; on a computer, many).
- **R23.** Triangles: the construction makes the model at the level that
  fits (near, mid, far), and refuses when the far level is still over.

### The web page

- **R24.** `world.mkfifo.com` shows the world: the people (the figures
  of World at the far level, with the poses `walk`, `carry`, `work`),
  the places and the vehicles that the people build at the start of a
  node (step 5), and each construction as it happens, from `GET /events`
  and the small GLB of each element. The page is static (three.js, from
  `review/replay.html`). The log of the node persists in the SQLite of
  the Durable Object, so a page that opens later replays what happened
  and then follows the stream.

### The specification

- **R25.** `specs/Build.tla` takes the place of `specs/Order.tla`: a
  construction, its tasks and its sequence, its crew, the shared people,
  the pause and the change. The invariants: one worker on a task, a
  task starts after the tasks it comes after, an element is made once,
  a person is at one construction at a time, a change forgets no
  element. The fault models must fail. The log of a real build replays
  as a behavior of the specification (`docs/specs.md`).

## 6. Steps

Each step is a few small commits on `main`, with tests at 100%, and
something to see at the end of it.

1. **The people build the model, and anyone can watch.** R1 to R7,
   R16 to R20 (no pause, no change yet), R21 and R23, R24 (the live
   view of the constructions), R25 (without the pause and the change).
   The old run, foreman and workers go. To see: the house of bricks and
   the statue of today go up element by element on the web page, two at
   one time; the same bytes at the end as the files in `priv/models`.
2. **The blueprint of the statue as data, with the skills.** R8 to
   R15 for the statue: `priv/drawings/tuong_chua_kito_vua.json` (the
   base, the figure, the pours from the feet up, the shell, the stair,
   the grilles, the halo, the rail), with its sources; `World.Statues`
   goes; the words of IFC in `docs/format.md`. To see: an LLM client of
   the MCP server changes the drawing (a taller statue, no halo) and the
   people build it with no new code.
3. **Pause, resume, change, cancel, and the memory budget.** R18, R22,
   R25 in full. To see: pause the statue at the fifth pour, change the
   height, resume: the base and the first pours stay, the rest is made
   again.
4. **The other kinds of things as drawings.** R14 for the tower, the
   houses on a lot, a van. A new skill comes only when a drawing needs
   one.
5. **The world builds its own places.** The first jobs of a node: a
   warehouse, a yard, a factory for each trade, the trucks, from
   drawings in `priv/drawings/`, by the same people, in the log; their
   models in the store of the release, so the edge does not build them
   at each start (a job from the store is a delivery, and the page shows
   the delivery).
6. **Vũng Tàu.** A draft plan in Vung_Tau, "QA mode: build a house at
   an address": walk to an address, say what stands there, the LLM
   architect writes the drawing with the tools of R15, the game watches
   the stream and shows the house go up on its lot; the owner approves
   it, and its drawing goes into the data of the game as the model of
   that lot. The known places and the houses of the lots come at compile
   time through the same calls (`tools/world/fetch.py` of plan 0023).

## 7. Acceptance criteria

| # | Criterion |
|---|---|
| 1 | `mix.com precommit` passes at each commit: the format, the tests at 100% coverage, the model checks. |
| 2 | Step 1: `mix.com world.build --check` shows no change of a `.glb` file; a test gives the same bytes with one worker, with eight, and with two constructions at one time; the log of a construction passes `World.Log.check/1` and replays in `specs/Build.tla`; `curl -N` on `/builds/ID/events` and on `/events` shows the elements; the web page shows them. |
| 3 | Step 2: the picture of the statue from the drawing is the same as the picture of today on the review page (`scripts/shot.mjs`); the glTF validator passes (`npm test`). |
| 4 | Step 3: a test of each control; the fault models fail as they must. |
| 5 | After each step: a deploy to <https://world.mkfifo.com>, and a build of the statue at mid through a construction at the edge, with its log and its memory in `docs/world.md` ("The measures of a run"). |

## 8. Is it feasible?

Yes. Each piece is known ground in Elixir or in the code that exists;
the risks are in the sizes, not in the idea.

| Piece | Why it works | The limit to know |
|---|---|---|
| People as processes, a shared pool | A process of the BEAM costs a few KB; a `DynamicSupervisor` and a `Registry` give the pool; the people of today already are `GenServer`s. | A node holds millions of processes, but the work of a worker (a mesh) takes memory: the budget, not the count of processes, is the limit. |
| Workers make the elements, the construction joins them | `World.Build.scene/2` already builds a scene from parts; the join is the same call on the parts that came back. The order of the nodes fixes the bytes. | A big element (the shell of the statue, about 10 MB as a term) is copied once from the worker to the construction. |
| The stream | A `Plug` sends chunked responses; a Durable Object streams a `Response` and stays alive while it streams; Godot and a browser read server-sent events. | A Durable Object idles out between requests; the log in its SQLite lets the page replay what happened, then follow. |
| Skills as a behaviour | A behaviour with `check`, `make` and `estimate` is plain Elixir; the first skills wrap functions that exist. | A skill must be pure so a job gives the same bytes each time. |
| A drawing as the blueprint of everything | `World.Drawing` checks and builds a model from JSON today, with items of other blueprints inside; `after`, `trade` and the skills are additions to its check. | The drawing of a house or a van is bigger than the limits of today; the limits grow with the skills. |
| An LLM as the architect | The MCP server exists, with `check_drawing` and `propose_drawing`; the checks of a true model (`World.Check`) are the gate, and the owner reviews. | The quality of a drawing from an LLM is the open question; the gate and the review page answer it one drawing at a time. |
| The budget | The log has the real time of each task; an estimate by the size of an element is a sum. | The first estimate of a new skill is a guess until its first builds are in the log. |
| The edge | The VM at the edge builds small jobs and serves the store; a computer of the owner (many cores) builds the big ones through the same calls. | 128 MB and one scheduler at the edge: one or two workers at one time there; the parallel crew shows on a computer. |
| The specification | `specs/Order.tla` and the replay of a log exist; `Build.tla` is the same method on the new flow. | The state space of the model check grows with the shared pool; the small model stays small (two constructions, three people). |

## 9. Open questions

- **Q1.** The first estimate of a skill (R21): a fixed guess in the
  skill, or a first build with no limit of seconds that fills the log?
  Answered (the owner, 2026-11-07): a first build with no time limit.
  Its log gives the estimate of the next builds.
- **Q2.** The web page at the start of a node (R24, step 5): the people
  build the places at each start of the Durable Object, or only once,
  with the log of that first build kept in the SQLite?
  Answered (the owner, 2026-11-07): once. A later start reads the log of
  that first build from the store.
- **Q3.** The names of the first people (the figures and the names of
  the yard of `World.Run` today, or new ones)?
  Answered (the owner, 2026-11-07): the PID of the process
  (`"<0.123.0>"`).
