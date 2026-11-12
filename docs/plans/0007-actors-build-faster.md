# 0007 The people build each model as actors: faster, better, as on a real site

| Field | Value |
|---|---|
| Status | Approved (the owner, 2026-11-12: "Approve. Proceed!") |
| Depends on | Plan 0001 (the people build on demand), plan 0002 (the people build any blueprint), plan 0006 (one clock for the world). |
| Changes | A measure of each build (`World.Bench`, `mix world.bench`); the plan of the people for each model; the work of a construction and of a person; the clock of a build; the messages of priority; the output and the memory of a build; the log server. |

## 1. Goal

World builds most models in a streaming and parallel way, so that it
uses the Erlang BEAM: actor processes, messages, and messages of
priority. The build is faster and better, and it follows the process of
real life on a real site (the owner, 2026-11-12).

At the end:

- **A measure.** One task builds each model of the catalog, each
  blueprint in data and each drawing through the people
  (`World.build/1`), and gives for each model: the result, the time, the
  most memory, and how busy the schedulers were.
- **The people build each model.** For each model, the people make its
  parts in tasks, at the same time when the parts do not wait for each
  other, as the crews of a site or the stations of a line do. The
  construction (the site manager) gives the tasks and joins the parts;
  it does not make the shapes.
- **Each actor keeps its own work.** A person gets only the inputs of its
  task, as a crew gets its materials. The construction places only the
  new parts after a task.
- **A fast clock for a build that no one watches.** The log keeps the
  days of each task on the world clock, but the people do not wait for
  those days in the time of the wall.
- **The urgent messages come first.** A stop, a pause, a change and the
  call of a person go before the results of the work. A person stops its
  work when the construction stops.
- **The output streams, and the memory has a limit.** Each part goes to
  the store when it is made; the model at the end comes from the parts;
  each construction has a limit of memory.

## 2. What the owner asked

On 2026-11-12:

> We have spent too much effort on this, and it's just for demo. It's
> not what's good for `World`. I just want to make sure `World` can
> build most models now, in a streaming and parallelizable fashion so it
> can take advantage of the Erlang BEAM.

> I just want to make sure we take advantage of Erlang, priority
> message, actor processes, so we can build a model faster, better, and
> follow the process of real life in real world.

## 3. The state before this plan

From the code at `feat/0006-hill` (9a7fd0d):

- A build is one process (`World.Construction`, a GenServer) with its
  people (`World.Person`, a GenServer each; 4 by default, 64 at most).
  The deadline, a pause, a resume and a cancel are messages of priority
  to an alias of the construction, and the construction watches each
  person with a monitor of priority (`lib/world.ex:64`,
  `lib/world/construction.ex:102`, `:252`).
- Only a drawing with a skill node (the statue, the tower, the houses
  in data, the line of vans, the vehicles in data) is a plan of tasks
  that the people make. Each other model (most of the 174 models of the
  catalog) is made whole in the construction process
  (`construction.ex:139`); the people only cut it into triangles.
- After each task of a drawing, the construction assembles the whole
  model again (`construction.ex:399`), and each task takes a copy of
  each made node (`construction.ex:582`): work and copies that grow
  with the square of the nodes.
- A person waits for the days of its task on the world clock
  (`Process.sleep` until its time): with a scale of 86,400, one day is
  1 s of the wall.
- A person runs its work in a `receive`, so a stop comes only after the
  work (`lib/world/person.ex`).
- Each event and each element streams to the watchers (SSE), but the
  model comes in one binary at the end, and the construction holds each
  triangle, each element, the log and the model.
- One log server takes each event of each build, and copies 2,000
  events at each publish.

## 4. Out of scope

- New kinds of models (the IFC house and the houses of plan 0003 stay in
  plan 0003).
- The page of the world and the films (plan 0006).
- A build on more than one node.

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **Measure first.** `World.Bench` builds a list of orders, one at a time, through `World.build/1` at a level and with a budget of people, on a clock scale that the call gives (one day in 1 ms by default, so that the days do not hide the work). For each order: the result, the wall time, the most memory of the VM (a sample each 10 ms), the use of the schedulers (`:scheduler`), the tasks, the elements and the triangles. `mix world.bench` prints a table and can write the JSON. | A change is better only if the numbers say so. |
| D2 | **Each model is a plan of tasks for the people.** A model of the catalog becomes tasks at its assemblies: a person makes each subassembly (its shapes and its triangles), and the construction joins them, as the stations of a line make the subassemblies and the line joins them. | Most of the catalog is made in one process today; the work of the shapes is the work that must go to the people. |
| D3 | **A person gets only its inputs.** The construction sends to a task only the made nodes that the task takes (`from`), and it places only the nodes that a task makes, with the places that it keeps of the nodes before them. | A crew gets its materials, not the whole site. Work and copies grow with the nodes, not with their square. |
| D4 | **A virtual clock for a build that no one watches.** With the option `clock: :fast`, a person does its work at once; the construction keeps each result until the world time of its end (the start of the task plus its days), and goes to the next end in the order of the world times (a simulation of discrete events). The log has the same days as a build on the world clock. | The days of a site stay in the log, and the computer does not wait for them. |
| D5 | **A person can stop at once.** A person runs its work in a hand (a process that it links), and takes the messages of priority of the construction (`stop`, `pause`) while the hand works: at a stop, it kills the hand and is free. The construction sends a stop to each person with a task when it stops or is cancelled, and a pause lets each person end its task. The results stay normal messages. | On a site, a worker stops at the call, not at the end of the task. |
| D6 | **The output streams.** Each element goes to the store of the node (a file of its hash) when it is made; the construction keeps the key, not the binary. The model at the end is the join of the stored elements. A construction has a limit of memory (`memory_mb` for the whole build), and the yard does not start a build that does not fit. | The memory of a build stays low, and a big model can stream. |
| D7 | **The log server does not copy.** The events of a construction go into a table (ETS) by their id; a publish adds one event, and a watcher that comes late reads from the table. | One process takes each event of each build. |

## 6. Requirements

- **R1.** `mix world.bench` builds each model of the catalog, each
  blueprint in data and each drawing (or the names that it gets), and
  prints, for each one: the result (`built`, `failed`, `stopped`,
  `timeout`, or the error of the order), the wall time in ms, the most
  memory in MB, the use of the schedulers, the tasks and the triangles;
  `--out FILE` writes the JSON; `--level`, `--workers`, `--scale` and
  `--timeout` set the build.
- **R2.** A model of the catalog with n assemblies is a plan of at least
  n tasks that make shapes; the construction process makes no shape.
- **R3.** For a drawing of n nodes, the work of the construction process
  (its reductions) grows with n, not with n squared: a drawing of 4n
  nodes takes less than 6 times the work of a drawing of n nodes.
- **R4.** A build with `clock: :fast` has the same days for each task
  in its log as a build on the world clock, and does not wait for them.
- **R5.** At a cancel, each person with a task is free in less than
  100 ms, with a task that does not end by itself.
- **R6.** The construction holds no binary of an element; the most
  memory of the build of `house_brick_vn` at near is less than half of
  the 847 MB of today.
- **R7.** A publish of the log server takes the same time with 10 or
  10,000 events in the log.
- **R8.** At the end, `mix world.bench` at mid with 8 people builds at
  least 95% of the models, and the catalog takes less time than in
  step 1.

## 7. Steps

Each step is a small commit (or a few), with its tests, the quick checks
on each commit, and the full check on the tip before a push.

1. **The measure** (D1, R1): `World.Bench`, `mix world.bench`, its
   tests; the first numbers of the catalog go into this plan.
2. **The people build each model** (D2, R2).
3. **Each actor keeps its own work** (D3, R3).
4. **The fast clock** (D4, R4).
5. **The stop of a person** (D5, R5).
6. **The output, the memory and the log** (D6, D7, R6, R7).
7. **The measure again** (R8), `docs/world.md`, `docs/factory.md`.

## 8. Acceptance criteria

- The tests of R1 to R7.
- The table of step 1 and of step 7, side by side, in this plan.
- The full check passes on the tip of each push.

## 9. Open questions

- None yet.
