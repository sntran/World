# The specifications of World

The people of the node are processes (`docs/plans/0001-people-build-on-demand.md`).
They act at the same time, and the order of their acts changes from run
to run. A test sees one order of the acts. A specification sees all of
them.

This document tells what World specifies, what the checks prove, what
they do not prove, and how to run them.

## The chain of the checks

| Check | What it reads | What it proves | Where |
|---|---|---|---|
| 1. The model checks | Each specification of `specs/`, a small model | In each possible order of the acts, the invariants hold, and the liveness property holds. | `test/world/build_spec_test.exs`, `test/world/node_spec_test.exs` |
| 2. The fault models | The same specifications, with one rule removed | The checker finds the fault. A check that cannot fail proves nothing. | the same tests |
| 3. The replay | The log of a real construction | The code does only what `specs/Build.tla` allows: each event of the log is one step of the specification, and the invariants hold after each step. | `test/support/build_spec.ex`, `test/world/construction_test.exs` |
| 4. The log check | Each log, at each read | The events are in the order of their time, and each task starts once, after the tasks that it waits for. | `World.Log.check/1` |

The checks 1 and 2 prove the design. The check 3 ties the code to the
design. The check 4 runs on each log that the site gives.

## The specifications

| Specification | The flow | The code |
|---|---|---|
| `specs/Build.tla` | The constructions, their tasks, and the people that they share: a hire, the start and the end of a task, a release, the end of a construction, its deadline or a cancel, a pause, a resume, and a change that makes tasks again. | `World.Construction`, `World.Census` |
| `specs/Census.tla` | The people of the node at its limit: a construction asks for a person of a trade, and the census gives a free person, a new one, or a new one in the place of a free person of another trade. | `World.Census`, `World.Construction` |
| `specs/Stream.tla` | A stream to one client: it watches, reads the events of the past, then follows the new events. | `World.Stream`, `World.Log.Server` |
| `specs/LogStore.tla` | The log of the node and its store: the batches, a stop of the VM, a new log. | `World.Log.Server`, `World.Log.Store` |
| `specs/Places.tla` | The first start of the node: the yard raises the buildings of its plan, a place opens when its building is done, and a construction starts at its place when the place is open (the yard holds it until then). | `World.Yard` |
| `specs/Haul.tla` | The haul of the materials of the tasks: the loads of a takeoff, a truck for each load, the drive to the source and to the place, and the word to the construction when each load is there. | `World.Haul`, `World.Truck` |

### `specs/Build.tla`

The constants: the constructions (`Builds`), the tasks of all of them
(`Tasks`, `BuildOf`, `Waits`, `Trade`), the people and their trades
(`People`, `Skill`), the budget of workers of each construction
(`Budget`), the most pauses of a construction (`Pauses`, a bound of the
model), and four guards for the fault models.

| Action | When it can occur | Event of the log |
|---|---|---|
| `Hire(b, p)` | Nobody holds `p`, `b` is under its budget, a task of `b` of the trade of `p` can start, and `b` holds no free person of that trade. | `hired` |
| `Start(b, p, t)` | `p` is free and held by `b`, `t` is of its trade, and each task that `t` waits for is done. | `task_started` |
| `Finish(p, t)` | `p` does `t`. | `task_done` |
| `Release(b, p)` | `p` is free, and `b` has no task of its trade to start; or no task of its trade can start now, and a task that can start needs a trade that `b` holds nobody of. | `released` |
| `Done(b)` | Each task of `b` is done, and `b` holds nobody. | `done` |
| `Deadline(b)` | Any time before the end, also for a cancel: `b` stops, its people go back at once, and a person that works ends its task for nobody. | `stopped` |
| `Pause(b)` | Before the end: `b` gives no task and hires nobody; it lets its free people go. | `paused` |
| `Resume(b)` | `b` is in a pause. | `resumed` |
| `Redo(b, t)` | In a pause, `t` started, and each task that waits for `t` did not start: `t` is not started and not done, and a person that works on it ends it for nobody (stale). | `changed` (one `Redo` for each task of `redo`) |
| `Drop(p)` | `p` ends a task that a change made again. | `task_dropped` |
| `Arrive(b, t)` | `t` has a takeoff (`Hauled`): its materials are at the place of `b` (`specs/Haul.tla`). A task of `Hauled` is ready only after it. | `parts_here` |

| Invariant | What it says | The fault that it stops |
|---|---|---|
| `OneWorkerOneTask` | Two people never do one task. | A part in the model two times. |
| `WaitsFirst` | A task starts only after each task that it waits for. | A door on a body that is not there. |
| `MadeOnce` | A task that is done is never made again. | Work done two times. |
| `OnePlace` | A busy person works for the construction that holds it, or for one that stopped. | A person at two constructions. |
| `InBudget` | A construction never holds more people than its budget. | A build that takes the people of the node. |
| `QuietPause` | In a pause, the tasks in work are the tasks in work at its start, or fewer. | A task that starts in a pause. |
| `KeepsWhatIsSame` | A task that started is done, or a person works on it. | A change that forgets the work of a task that it keeps. |
| `PartsHere` | A task with a takeoff starts only after its materials are at the place. | A wall with no bricks. |

The liveness property `Delivers`: each construction is done in the end
(or stops).

The small model (`specs/MCBuild.tla`): a house (a wall of a mason, then
a rail of a steelworker) and a shed (two walls of a mason), three people
of two trades; each construction can pause once. `MCBuildFault.cfg`
lets a task start again: the checker must find `MadeOnce` violated.
`MCBuildHire.cfg` lets a construction hire a person that another
construction holds: the checker must find `OnePlace` violated.
`MCBuildPause.cfg` lets a task start in a pause: `QuietPause` violated.
`MCBuildKeep.cfg` lets a change forget that a task it keeps is done:
`KeepsWhatIsSame` violated. The rail has a takeoff; `MCBuildParts.cfg`
lets a task start before its materials: `PartsHere` violated.

### `specs/Census.tla`

Each construction does its tasks in order, each with a person of its
trade. The census gives a free person of the trade, or a new person
under `Limit`, or, at the limit, a new person in the place of a free
person of another trade. With `Yield`, a construction that waits gives
back its free people that it does not need now.

| Invariant or property | What it says |
|---|---|
| `InLimit` | The node never has more people than its limit. |
| `NoSteal` | A person that works works for the construction that holds it. |
| `AllDone` | Each construction is done in the end. |

The small model (`specs/MCCensus.tla`): a node of two people; the house
needs a mason then a steelworker, the shed a steelworker then a mason.
`MCCensusKeep.cfg` is the fault model where a construction keeps its free
people: each holds one person and waits for the other, so the checker
finds the dead end. This fault was in the code: `World.Construction` now
gives back its free people when a task needs a trade that it holds
nobody of. `MCCensusSteal.cfg` lets the census give a person that works:
the checker must find `NoSteal` violated.

### `specs/Stream.tla`

The log publishes the events 1 to `N` in order, to the mailbox of each
process that watches. A stream starts after the id `Start`
(`Last-Event-ID`): it watches, reads the events of the past (the memory
keeps `Keep` events; the store has the older ones), then sends each
event of its mailbox with an id over the last id that it sent.

| Invariant or property | What it says |
|---|---|
| `InOrder` | The client gets the events in the order of their ids, each one time. |
| `AfterStart` | Each event that the client gets is after `Start`. |
| `NoGap` | At the end, the client got each event after `Start`. |
| `AllSent` | In the end, the stream sent each event after `Start`. |

The fault models: `MCStreamLate.cfg` reads the past before it watches
(the checker finds a gap: an event published between the two),
`MCStreamTwice.cfg` sends each event of its mailbox with no check of the
id (an event comes two times), and `MCStreamMemory.cfg` has a memory of
one event and no store (the older events are not there).

### `specs/LogStore.tla`

The log gives each new event the next id and sends it at once. It keeps
the event in a buffer, and puts the buffer into the store at `Batch`
events or after a time. The VM can stop (a deploy, too little memory):
the buffer is lost. A new log starts after the last id of the store,
plus `Gap`, and with `Mark` puts its first id into the store at once.

| Invariant | What it says |
|---|---|
| `OneName` | An id names one event only: a client that knows an id never gets another event with it. |
| `SmallBuffer` | The buffer never has `Batch` events: a stop loses fewer than `Batch` ids. |
| `UpOnly` | Each new id is over each id of the store. |

The fault models: `MCLogStoreReuse.cfg` (a new log goes on from the last
id of the store: the id of a lost event goes to a new event) and
`MCLogStoreTwice.cfg` (a new log leaves `Batch` ids but does not keep its
first id: after two stops in a row, one id names two events). Both
faults were in the design: `World.Log.Server` now leaves 50 ids and puts
the event `started` into the store when it starts.

### `specs/Haul.tla`

The constants: the tasks with a takeoff (`Tasks`), the loads of all of
them (`Loads`, `Of`, `Mass`), the trucks (`Trucks`) and the most mass of
a truck (`Cap`), and two guards for the fault models. The time of a
drive is not in the model: a drive is the step between a take and a
drop.

| Action | When it can occur | Event of the log |
|---|---|---|
| `Ask(t)` | Once for each task: its loads go into the queue. | `haul_asked` |
| `Take(k, l)` | `l` is in the queue, and the truck `k` holds no load. | `loaded` |
| `Drop(k, l)` | `k` holds `l`: it puts it down at the place of its task. | `unloaded` |
| `Tell(t)` | Each load of `t` is at its place. | `hauled` |
| `Start(t)` | The haul told the construction of `t`. | `task_started` |

| Invariant or property | What it says | The fault that it stops |
|---|---|---|
| `InLoad` | A truck holds at most one load, and a load is never more than a truck holds. | A truck over its load. |
| `OnePlace` | A load is in the queue, on one truck, or at its place: one at a time. | A load at two places. |
| `PartsFirst` | A task starts only after each of its loads is at its place. | A wall with half of its bricks. |
| `AllStarted` | Each task starts in the end. | A load that nobody takes. |

The small model (`specs/MCHaul.tla`): a band of bricks of two loads and
a slab of one load, two trucks of 1,500 kg. `MCHaulTwo.cfg` lets a truck
take a load while it holds one: `InLoad` violated. `MCHaulEarly.cfg`
lets the haul tell a task at its first load: `PartsFirst` violated.

`World.HaulSpec.replay/3` (`test/support/haul_spec.ex`) replays the log
of the haul with the logs of the constructions that asked it:
`test/world/haul_test.exs` replays the haul of a band in rented trucks,
of a slab on one truck of the yard, and of a house of one floor at the
site, and a log with a lost load diverges.

### `specs/Places.tla`

The constants: the places (`Places`), the places with a building
(`Built`: closed at the start), the buildings that the yard raises at
its first start (`Plan`), the constructions of the models and of the
trucks (`Builds`, `At`), and a guard for a fault model.

| Action | When it can occur | Event of the log |
|---|---|---|
| `Raise(p)` | `p` is in the plan, closed, and not raised. | `place_raised` |
| `Open(p)` | The building of `p` is done. | `place_open` |
| `Hold(c)` | The place of `c` is not open: the yard holds it. | `place_held` |
| `Start(c)` | The place of `c` is open. | `place_started` |
| `Done(c)` | `c` started. | `done` |

| Invariant or property | What it says | The fault that it stops |
|---|---|---|
| `AtOpen` | A construction works only at a place that is open. | A van on the line of a factory that is not there. |
| `Bootstrap` | The first start ends: each place opens. | |
| `AllDone` | No construction waits for a place that nobody builds. | A model whose factory is not in the plan. |

The small model (`specs/MCPlaces.tla`): the warehouse and the factory of
the vehicles have a building; a truck and a scooter are at the factory,
a house at the site. `MCPlacesLost.cfg` has no factory of the vehicles
in the plan: the checker finds that the truck waits forever.
`MCPlacesEarly.cfg` lets a construction start before its place is open:
`AtOpen` violated. `World.PlacesSpec.replay/3`
(`test/support/places_spec.ex`) replays the log of the yard of a first
start with the logs of a scooter that waited for its factory and of a
house at the site (`test/world/yard_test.exs`).

## The replay: the code against the specification

`World.BuildSpec.replay/3` (`test/support/build_spec.ex`) takes the logs
of constructions and:

1. writes a module `Run.tla` that extends `Build` with the constants of
   the logs: their constructions, the tasks of their plans with their
   waits and trades, the people that they hired with their trades, and
   the budget of each;
2. loads it in the machine of the checker
   (`Accord.TLA.Checker.Machine`);
3. takes each event, in the order of the wall clock, as one action of
   the specification, with its arguments;
4. checks each invariant after each step.

The result is `:ok`, `{:error, {:diverged, event}}` when the
specification has no step for an event, or `{:error, {:violated,
invariant, event}}`.

`test/world/change_test.exs` replays the logs of a pause, of a change
of a task in hand (its result goes to nobody: `task_dropped`), of a
change that takes down what it drops (the tasks `remove/NODE` of the
event `changed` are tasks of the replay), and of the statue at far
whose height changes after its base: the base stays.
`test/world/construction_test.exs` replays the log of the wall of
bricks with one worker and with eight, of two constructions at one
time, of a construction of two trades with a budget of one person (it
gives back its free person for the other trade), and of a construction
that stops at its deadline. It also proves that the replay can fail: the
log with an end of a task less diverges, and a task made again violates
`MadeOnce` in the fault model.

## What the specifications do not cover yet

- **A person that stops.** The construction gives its task to another
  person (`World.Construction`, a monitor of priority), but
  `specs/Build.tla` has no action for it: the replay of such a log
  diverges.
- **The time.** The specifications have no clock. The log has the times,
  and `World.Log.check/1` checks them.
- **The files.** The specifications do not check the GLB: the Khronos
  glTF validator does that for each file of the catalog (`npm test`).
- **The Worker at the edge.** The cache of the files in R2 is not
  specified.

## Run the checks

```sh
mix.com test test/world/build_spec_test.exs test/world/node_spec_test.exs  # the model checks and the fault models
mix.com test test/world/construction_test.exs                             # the constructions and their replay
mix.com accord.check --extra specs/MCBuild.tla                            # one model check alone, with its numbers
mix.com precommit                                                         # all the checks, with the coverage at 100%
```
