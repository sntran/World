---- MODULE Build ----
(***************************************************************************)
(* The constructions of one node (docs/plans/0001-people-build-on-demand). *)
(* Each construction has the tasks of its plan; a task waits for other     *)
(* tasks, and needs a person of its trade. The people are one pool: a      *)
(* construction hires a free person, gives it tasks one at a time, and     *)
(* lets it go. A construction holds at most its budget of people. When     *)
(* each task of a construction is done and it holds nobody, it is done. A  *)
(* construction can stop at its deadline, or when a client cancels it: its *)
(* people go back at once, and a person that works ends its task for       *)
(* nobody. A client can pause a construction: it gives no task, the people *)
(* end the tasks in hand, and it lets its free people go. During a pause, a *)
(* change makes tasks again (Redo): the tasks that wait for a task that a  *)
(* change makes again are made again first, and a person that works on it  *)
(* ends it for nobody (stale). Then the client resumes it. A task with a   *)
(* takeoff (Hauled) starts only after its materials are at the place of    *)
(* its construction (Arrive: the trucks of specs/Haul.tla brought them).   *)
(* World.Construction makes this flow with processes, and the log of each  *)
(* construction replays as a behavior of this module (World.BuildSpec).    *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Builds,     \* the ids of the constructions
    Tasks,      \* the ids of the tasks of all the constructions
    BuildOf,    \* BuildOf[t]: the construction of the task t
    Waits,      \* Waits[t]: the tasks that the task t waits for
    Trade,      \* Trade[t]: the trade of the task t
    People,     \* the names of the people
    Skill,      \* Skill[p]: the trade of the person p
    Budget,     \* Budget[b]: the most people that b holds at one time
    Pauses,     \* the most pauses of a construction (a bound of the model)
    Guard,      \* FALSE: the fault model where a task can start again
    HireGuard,  \* FALSE: the fault model where a busy person can be hired
    PauseGuard, \* FALSE: the fault model where a task can start in a pause
    KeepGuard,  \* FALSE: the fault model where a change forgets a task
    Hauled,     \* the tasks with a takeoff: the trucks bring their materials
    PartsGuard  \* FALSE: the fault model where a task starts before its materials

VARIABLES
    held,       \* held[p]: the construction that holds p, or ""
    busy,       \* busy[p]: the task of p, or ""
    stale,      \* the people that end a task for nobody (a change made it again)
    started,    \* the tasks that started
    done,       \* the tasks that are done
    finished,   \* the constructions that are done
    stopped,    \* the constructions that stopped (a deadline, a cancel)
    paused,     \* the constructions in a pause
    pauses,     \* pauses[b]: the pauses of b so far
    inHand,     \* inHand[b]: the tasks of b in work at the start of its pause
    here        \* the tasks whose materials are at the place of their construction

vars == <<held, busy, stale, started, done, finished, stopped, paused, pauses, inHand, here>>

TasksOf(b) == {t \in Tasks : BuildOf[t] = b}
Count(b) == Cardinality({p \in People : held[p] = b})
Free(p) == busy[p] = "" /\ p \notin stale
InWork(b) == {t \in TasksOf(b) : \E p \in People : busy[p] = t}
\* A task that is not started and is not done.
Pending(b, trade) == {t \in TasksOf(b) : Trade[t] = trade /\ t \notin started}
Parts(t) == t \in Hauled => t \in here
\* PartsGuard: a task with a takeoff is ready only when its materials are there.
Ready(t) == t \notin started /\ Waits[t] \subseteq done /\ (PartsGuard => Parts(t))
\* b holds a person of the trade, and a free one.
Holds(b, trade) == \E p \in People : held[p] = b /\ Skill[p] = trade
HoldsFree(b, trade) == \E p \in People : held[p] = b /\ Free(p) /\ Skill[p] = trade
\* A task of b of the trade can start now.
ReadyFor(b, trade) == \E t \in TasksOf(b) : Ready(t) /\ Trade[t] = trade

Init ==
    /\ held = [p \in People |-> ""]
    /\ busy = [p \in People |-> ""]
    /\ stale = {}
    /\ started = {}
    /\ done = {}
    /\ finished = {}
    /\ stopped = {}
    /\ paused = {}
    /\ pauses = [b \in Builds |-> 0]
    /\ inHand = [b \in Builds |-> {}]
    /\ here = {}

\* b hires the person p that nobody holds, for a task of its trade that can
\* start, when b holds no free person of that trade, in its budget, and
\* not in a pause. HireGuard keeps a person that a construction holds from
\* a second hire.
Hire(b, p) ==
    /\ b \notin finished /\ b \notin paused
    /\ IF HireGuard THEN held[p] = "" ELSE held[p] /= b
    /\ Count(b) < Budget[b]
    /\ ReadyFor(b, Skill[p]) /\ ~HoldsFree(b, Skill[p])
    /\ held' = [held EXCEPT ![p] = b]
    /\ UNCHANGED <<busy, stale, started, done, finished, stopped, paused, pauses, inHand, here>>

\* A free person of b starts a task of b of its trade, after the tasks it
\* waits for, and not in a pause. Guard keeps a task from a second start,
\* PauseGuard keeps a task from a start in a pause.
Start(b, p, t) ==
    /\ held[p] = b /\ Free(p)
    /\ BuildOf[t] = b /\ Trade[t] = Skill[p]
    /\ Guard => t \notin started
    /\ PauseGuard => b \notin paused
    /\ Waits[t] \subseteq done
    /\ PartsGuard => Parts(t)
    /\ b \notin finished
    /\ started' = started \cup {t}
    /\ busy' = [busy EXCEPT ![p] = t]
    /\ UNCHANGED <<held, stale, done, finished, stopped, paused, pauses, inHand, here>>

\* The materials of a task with a takeoff are at the place: the haul
\* (specs/Haul.tla) brought each load of it.
Arrive(b, t) ==
    /\ t \in Hauled /\ BuildOf[t] = b /\ t \notin here
    /\ here' = here \cup {t}
    /\ UNCHANGED <<held, busy, stale, started, done, finished, stopped, paused, pauses, inHand>>

\* The person ends its task.
Finish(p, t) ==
    /\ t /= "" /\ busy[p] = t
    /\ done' = done \cup {t}
    /\ busy' = [busy EXCEPT ![p] = ""]
    /\ UNCHANGED <<held, stale, started, finished, stopped, paused, pauses, inHand, here>>

\* A person ends a task that a change made again: its result goes to
\* nobody, and the person is free.
Drop(p) ==
    /\ p \in stale
    /\ stale' = stale \ {p}
    /\ UNCHANGED <<held, busy, started, done, finished, stopped, paused, pauses, inHand, here>>

\* b lets a free person go: it is in a pause; or it has no task of its
\* trade that did not start; or no task of its trade can start now, and a
\* task that can start needs a trade that b does not hold (b makes room in
\* its budget, and in the people of the node: specs/Census.tla).
Release(b, p) ==
    /\ held[p] = b /\ Free(p)
    /\ \/ b \in paused
       \/ Pending(b, Skill[p]) = {}
       \/ /\ ~ReadyFor(b, Skill[p])
          /\ \E t \in TasksOf(b) : Ready(t) /\ ~Holds(b, Trade[t])
    /\ held' = [held EXCEPT ![p] = ""]
    /\ UNCHANGED <<busy, stale, started, done, finished, stopped, paused, pauses, inHand, here>>

\* Each task of b is done, and b holds nobody: the model is made.
Done(b) ==
    /\ b \notin finished
    /\ TasksOf(b) \subseteq done
    /\ \A p \in People : held[p] /= b
    /\ finished' = finished \cup {b}
    /\ paused' = paused \ {b}
    /\ UNCHANGED <<held, busy, stale, started, done, stopped, pauses, inHand, here>>

\* The deadline of b, or a cancel: b stops, and its people go back at
\* once. A person that works ends its task, and its result goes to nobody.
Deadline(b) ==
    /\ b \notin finished
    /\ finished' = finished \cup {b}
    /\ stopped' = stopped \cup {b}
    /\ paused' = paused \ {b}
    /\ held' = [p \in People |-> IF held[p] = b THEN "" ELSE held[p]]
    /\ UNCHANGED <<busy, stale, started, done, pauses, inHand, here>>

Cancel(b) == Deadline(b)

\* A client pauses b: b gives no task until it resumes.
Pause(b) ==
    /\ b \notin finished /\ b \notin paused
    /\ pauses[b] < Pauses
    /\ paused' = paused \cup {b}
    /\ pauses' = [pauses EXCEPT ![b] = @ + 1]
    /\ inHand' = [inHand EXCEPT ![b] = InWork(b)]
    /\ UNCHANGED <<held, busy, stale, started, done, finished, stopped, here>>

Resume(b) ==
    /\ b \in paused
    /\ paused' = paused \ {b}
    /\ UNCHANGED <<held, busy, stale, started, done, finished, stopped, pauses, inHand, here>>

\* A change in a pause makes the task t of b again, after each task that
\* waits for it: t is not started and not done, and a person that works
\* on it ends it for nobody. KeepGuard keeps the other tasks as they are;
\* with no guard, a change forgets that a task that it keeps is done.
Redo(b, t) ==
    /\ b \in paused /\ t \in TasksOf(b) /\ t \in started
    /\ \A u \in TasksOf(b) : t \in Waits[u] => u \notin started
    /\ started' = started \ {t}
    /\ done' = IF KeepGuard THEN done \ {t} ELSE done \ TasksOf(b)
    /\ stale' = stale \cup {p \in People : busy[p] = t}
    /\ busy' = [p \in People |-> IF busy[p] = t THEN "" ELSE busy[p]]
    /\ UNCHANGED <<held, finished, stopped, paused, pauses, inHand, here>>

\* Each construction is done: no deadlock at the end.
Over == finished = Builds /\ UNCHANGED vars

Next ==
    \/ \E b \in Builds, p \in People : Hire(b, p) \/ Release(b, p)
    \/ \E b \in Builds, p \in People, t \in Tasks : Start(b, p, t)
    \/ \E p \in People, t \in Tasks : Finish(p, t)
    \/ \E p \in People : Drop(p)
    \/ \E b \in Builds : Done(b) \/ Deadline(b) \/ Pause(b) \/ Resume(b)
    \/ \E b \in Builds, t \in Tasks : Redo(b, t) \/ Arrive(b, t)
    \/ Over

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* --- Invariants --------------------------------------------------------

\* Two people never do one task.
OneWorkerOneTask ==
    \A v, w \in People : v /= w /\ busy[v] /= "" => busy[v] /= busy[w]

\* A task starts only after each task that it waits for is done.
WaitsFirst == \A t \in started : Waits[t] \subseteq done

\* A task that is done is never made again.
MadeOnce == \A p \in People : busy[p] \notin done

\* A busy person works for the construction that holds it, or for one
\* that stopped.
OnePlace == \A p \in People : busy[p] /= "" /\ BuildOf[busy[p]] \notin stopped => held[p] = BuildOf[busy[p]]

\* A construction never holds more people than its budget.
InBudget == \A b \in Builds : Count(b) <= Budget[b]

\* No task starts in a pause: the tasks in work are the tasks that were in
\* work when it started, or fewer.
QuietPause == \A b \in paused : InWork(b) \subseteq inHand[b]

\* A change keeps the work of each task that it does not make again: a
\* task that started is done, or a person works on it.
KeepsWhatIsSame == \A t \in started : t \in done \/ \E p \in People : busy[p] = t

\* A task with a takeoff starts only after its materials are at the place.
PartsHere == \A t \in started \cap Hauled : t \in here

\* --- Liveness ----------------------------------------------------------

\* Each construction is done in the end.
Delivers == <>(finished = Builds)
====
