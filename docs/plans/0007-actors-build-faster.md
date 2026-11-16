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

- **A measure.** One task builds each model of the catalog (with the
  drawings) and each blueprint in data through the people
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

- **R1.** `mix world.bench` builds each model of the catalog (with the
  drawings) and each blueprint in data (or the names that it gets), and
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

- **The order** (the owner, 2026-11-12, "Yes" to the order that the
  builder gave): plan 0008 (a model from edits) comes before the steps
  of this plan that are open. Its blocks of cells, each a task for a
  person, are the better way to step 2 for a model of one part (an
  animal, a person): the time of such a model is in the code that makes
  its one part in one process (the measure: 1,482 ms of 1,636 ms for the
  douc), not in its triangles. Step 6 (the output and the memory) and
  step 7 (the measure again) come after plan 0008.

## 10. The measure

### Step 1 (2026-11-12, 82323ab)

`MIX_ENV=test mix world.bench --level mid --workers 4 --timeout 300`, on
a machine with 4 schedulers:

| Measure | Value |
|---|---|
| Built | 180 of 182 |
| Failed | `egg_chair`, `egg_chair_person` ("no node bounce_egg_chair for the stretch of spring_egg_chair") |
| The time of all the builds | 81.2 s (82.9 s with the failures) |
| The schedulers that work, on average over the time | 0.9 of 4 |
| Models of one task | 62 of 180 |
| The most memory of the VM | 1,607 MB (the blueprint `statue`) |

The ten builds that take the most time:

| Model | Kind | ms | Most MB | Cores | Tasks | Triangles |
|---|---|---|---|---|---|---|
| `house_brick_vn` | catalog | 37,129 | 967.4 | 0.97 | 7,594 | 1,072 |
| `statue` | blueprint | 4,723 | 1,606.9 | 0.78 | 57 | 8,440 |
| `banh_mi_cart` | catalog | 4,540 | 216.2 | 0.67 | 12 | 15,162 |
| `tuong_chua_kito_vua` | catalog | 3,742 | 1,373.5 | 0.72 | 57 | 8,620 |
| `douc` | catalog | 1,627 | 405.6 | 0.67 | 1 | 8,244 |
| `rhesus_macaque` | catalog | 1,437 | 1,099.8 | 0.73 | 1 | 8,314 |
| `macaque` | catalog | 1,384 | 938.3 | 0.75 | 1 | 8,314 |
| `pig_tailed_macaque` | catalog | 1,359 | 1,017.6 | 0.75 | 1 | 8,314 |
| `gibbon` | catalog | 964 | 616.1 | 0.89 | 1 | 7,847 |
| `swing_porch_person` | catalog | 898 | 1,178.8 | 0.67 | 9 | 9,918 |

`house_brick_vn` takes 45% of the time with 1,072 triangles: the work
of the construction for each of its 7,594 tasks, not the shapes. The
models of one task (the animals, the people) are one part that one
person makes.

### Step 6, the first part (2026-11-12)

- **The log server** (D7, R7) keeps its last 2,000 events in a table
  (ETS) ordered by id. A publish adds one event and takes away the
  oldest one. Before, each publish copied the list of the recent events:
  at 10,000 events in the log, a publish took 9 times the work of a
  publish at 10 events (4,126 against 451 reductions). Now it takes the
  same work (`test/world/log_server_test.exs`).
- **The memory of `house_brick_vn` at near** (D6, R6). The bench gave
  1,222 MB at the peak. Its memory over the build: the construction has
  about 180 MB of live state (its elements, its model, its plan, the
  tasks that wait, the triangles, the log) and as much garbage in its old
  heap; the peak of the node is at the end, in the join: the scene keeps
  the primitives of the brick and of the mortar (7,108 and 7,256 meshes,
  of only 33 different meshes for the brick) as lists of tuples of
  boxed floats, and made each one from a list of all its corners. Three
  changes:
  - a **joiner** joins the model in a process of its own, as the
    drafter makes it at the start; the construction lets the model go,
    and the memory of the join goes back to the node at the end of the
    joiner;
  - the construction makes a **full sweep** of its heap after each 10
    collections;
  - a **primitive in one pass**: the corners of each mesh when the
    primitive comes to them, with no list of all of them, and a binary of
    the six numbers as the key of a point that it saw (the same bytes for
    each file of the catalog). The scene of the house alone: 397 MB at
    the peak, not 562 MB.

  The bench of `house_brick_vn` at near: **801 MB, not 1,222 MB**, in
  14.8 s. R6 asks for less than 424 MB.

### Step 6, the second part (2026-11-12)

A message copies a term with no sharing: the house has 7,108 bricks of
33 meshes, and its model takes 19.9 MB in the process that made it and
34.4 MB after a copy. Three changes:

- **The elements are made in the construction** from the model that it
  gets from the drafter (273 ms for the house), so they share its parts
  and meshes; before, the drafter sent them with the model, each with a
  copy of its part. The construction: 201 MB at the peak, not 290 MB.
- **Each process of a material gets its different meshes once**, and an
  index for each place of a mesh.
- **A packed primitive** (`World.Scene.pack/1`): in the join of a
  construction, each process of a material gives its points and its
  normals as binaries of floats of 64 bits, which go to the joiner with
  no copy; the GLB writer and the box of the scene read them (the same
  bytes, `test/world/scene_pack_test.exs`). The joiner: 201 MB, not
  258 MB.

The bench of `house_brick_vn` at near, two runs of each on one machine
(it started again, and is slower than the machine of the first part):
the commit before these changes, 833 MB and 19.0 to 20.1 s; with them,
**667 MB to 697 MB** and 19.5 to 20.3 s (the same time). R6 (less than
424 MB) is not met. What is left:
the construction keeps its elements, its model, its plan and the tasks
that wait (about 150 MB live), and the joiner has a copy of the model
and makes the scene of 7,594 nodes. The next change of size is the join
from the GLBs that the people make for each element (D6), or instances
for the meshes that repeat (33 meshes for 7,108 bricks); each changes
the form of the GLB of a model, and the owner decides it.

### Step 7: the measure again (2026-11-12)

The machine started again during step 6 and is slower than the machine
of step 1, so the bench of step 1 (82323ab) ran again on this machine,
next to the bench of the tip (243526b): `MIX_ENV=test mix world.bench
--level mid --timeout 300`, 4 schedulers.

| Measure | Step 1, 4 people | Now, 4 people | Step 1, 8 people | Now, 8 people |
|---|---|---|---|---|
| Built | 180 of 182 | 183 of 183 | 180 of 182 | 183 of 183 |
| The time of all the builds | 99.2 s | 64.0 s | 168.3 s | 66.6 s |
| The schedulers that work, on average over the time | 0.91 of 4 | 0.85 of 4 | 0.95 of 4 | 0.89 of 4 |
| The most memory of the VM | 1,613 MB (`statue`) | 1,512 MB (`statue`) | 1,637 MB | 1,504 MB |

The two egg chairs fail no more (a stretch with no target node), and the
carp from edits (plan 0008) is a new model. R8: 100% of the models, in
less time than in step 1.

| Model | Step 1, 4 people | Now, 4 people |
|---|---|---|
| `house_brick_vn` | 49.3 s, 968 MB | 8.9 s, 1,014 MB |
| `statue` | 4.8 s, 1,613 MB | 4.4 s, 1,512 MB |
| `tuong_chua_kito_vua` | 4.1 s, 1,377 MB | 3.5 s, 1,316 MB |
| `banh_mi_cart` | 4.1 s, 216 MB | 4.1 s, 208 MB |
| `carp_edits` | (none) | 2.2 s, 240 MB, 2.27 cores |
| `douc` | 1.6 s, 392 MB | 1.8 s, 410 MB |
| `macaque` | 1.5 s, 939 MB | 1.8 s, 976 MB |

With 8 people, `house_brick_vn` takes 119.6 s in step 1 and 14.6 s now:
the queue of the tasks that can start (step 3) took the work of the
foreman for each task away. It is still faster with 4 people than with
8 (8.9 s against 14.6 s): each person more is a hire, a release and
more messages for the one construction.

What is open:

- **The schedulers** work 0.85 of 4 on average: 63 models are of one
  task (the animals, the people), and the time of such a model is the
  code that makes its one part in one process. Step 2 (the people build
  each model) is open; for a body that is a field, a model from edits
  (plan 0008) uses each scheduler (the carp: 2.27 cores).
- **R6** is not met: `house_brick_vn` at near needs about 680 MB at the
  peak (1,222 MB before step 6), and R6 asks for less than 424 MB. The
  join from the GLBs of the elements (D6), or instances for the meshes
  that repeat, changes the form of the GLB of a model: the owner
  decides it.
- **The animals** take 10% to 20% more time than in step 1 (a sample of
  one run each; the full sweeps of the construction, step 6, cost a
  little for a model of one task).

