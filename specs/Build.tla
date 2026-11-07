---- MODULE Build ----
(***************************************************************************)
(* The constructions of one node (docs/plans/0001-people-build-on-demand). *)
(* Each construction has the tasks of its plan; a task waits for other     *)
(* tasks, and needs a person of its trade. The people are one pool: a      *)
(* construction hires a free person, gives it tasks one at a time, and     *)
(* lets it go. A construction holds at most its budget of people. When     *)
(* each task of a construction is done and it holds nobody, it is done. A  *)
(* construction can stop at its deadline: its people go back at once, and *)
(* a person that works ends its task for nobody.                          *)
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
    Guard,      \* FALSE: the fault model where a task can start again
    HireGuard   \* FALSE: the fault model where a busy person can be hired

VARIABLES
    held,       \* held[p]: the construction that holds p, or ""
    busy,       \* busy[p]: the task of p, or ""
    started,    \* the tasks that started
    done,       \* the tasks that are done
    finished,   \* the constructions that are done
    stopped     \* the constructions that stopped at their deadline

vars == <<held, busy, started, done, finished, stopped>>

TasksOf(b) == {t \in Tasks : BuildOf[t] = b}
Count(b) == Cardinality({p \in People : held[p] = b})
\* A task that is not started and is not done.
Pending(b, trade) == {t \in TasksOf(b) : Trade[t] = trade /\ t \notin started}
Ready(t) == t \notin started /\ Waits[t] \subseteq done
\* b holds a person of the trade, and a free one.
Holds(b, trade) == \E p \in People : held[p] = b /\ Skill[p] = trade
HoldsFree(b, trade) == \E p \in People : held[p] = b /\ busy[p] = "" /\ Skill[p] = trade
\* A task of b of the trade can start now.
ReadyFor(b, trade) == \E t \in TasksOf(b) : Ready(t) /\ Trade[t] = trade

Init ==
    /\ held = [p \in People |-> ""]
    /\ busy = [p \in People |-> ""]
    /\ started = {}
    /\ done = {}
    /\ finished = {}
    /\ stopped = {}

\* b hires the person p that nobody holds, for a task of its trade that can
\* start, when b holds no free person of that trade, in its budget.
\* HireGuard keeps a person that a construction holds from a second hire.
Hire(b, p) ==
    /\ b \notin finished
    /\ IF HireGuard THEN held[p] = "" ELSE held[p] /= b
    /\ Count(b) < Budget[b]
    /\ ReadyFor(b, Skill[p]) /\ ~HoldsFree(b, Skill[p])
    /\ held' = [held EXCEPT ![p] = b]
    /\ UNCHANGED <<busy, started, done, finished, stopped>>

\* A person of b starts a task of b of its trade, after the tasks it
\* waits for. Guard keeps a task from a second start.
Start(b, p, t) ==
    /\ held[p] = b /\ busy[p] = ""
    /\ BuildOf[t] = b /\ Trade[t] = Skill[p]
    /\ Guard => t \notin started
    /\ Waits[t] \subseteq done
    /\ b \notin finished
    /\ started' = started \cup {t}
    /\ busy' = [busy EXCEPT ![p] = t]
    /\ UNCHANGED <<held, done, finished, stopped>>

\* The person ends its task.
Finish(p, t) ==
    /\ t /= "" /\ busy[p] = t
    /\ done' = done \cup {t}
    /\ busy' = [busy EXCEPT ![p] = ""]
    /\ UNCHANGED <<held, started, finished, stopped>>

\* b lets a free person go: it has no task of its trade that did not
\* start; or no task of its trade can start now, and a task that can start
\* needs a trade that b does not hold (b makes room in its budget, and in
\* the people of the node: specs/Census.tla).
Release(b, p) ==
    /\ held[p] = b /\ busy[p] = ""
    /\ \/ Pending(b, Skill[p]) = {}
       \/ /\ ~ReadyFor(b, Skill[p])
          /\ \E t \in TasksOf(b) : Ready(t) /\ ~Holds(b, Trade[t])
    /\ held' = [held EXCEPT ![p] = ""]
    /\ UNCHANGED <<busy, started, done, finished, stopped>>

\* Each task of b is done, and b holds nobody: the model is made.
Done(b) ==
    /\ b \notin finished
    /\ TasksOf(b) \subseteq done
    /\ \A p \in People : held[p] /= b
    /\ finished' = finished \cup {b}
    /\ UNCHANGED <<held, busy, started, done, stopped>>

\* The deadline of b: b stops, and its people go back at once. A person
\* that works ends its task, and its result goes to nobody.
Deadline(b) ==
    /\ b \notin finished
    /\ finished' = finished \cup {b}
    /\ stopped' = stopped \cup {b}
    /\ held' = [p \in People |-> IF held[p] = b THEN "" ELSE held[p]]
    /\ UNCHANGED <<busy, started, done>>

\* Each construction is done: no deadlock at the end.
Over == finished = Builds /\ UNCHANGED vars

Next ==
    \/ \E b \in Builds, p \in People : Hire(b, p) \/ Release(b, p)
    \/ \E b \in Builds, p \in People, t \in Tasks : Start(b, p, t)
    \/ \E p \in People, t \in Tasks : Finish(p, t)
    \/ \E b \in Builds : Done(b) \/ Deadline(b)
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

\* --- Liveness ----------------------------------------------------------

\* Each construction is done in the end.
Delivers == <>(finished = Builds)
====
