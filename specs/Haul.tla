---- MODULE Haul ----
(***************************************************************************)
(* The haul of the materials of the tasks to the places of their          *)
(* constructions (World.Haul, World.Truck; plan 0002, D6 and D8). A task  *)
(* with a takeoff asks the haul for its loads. The haul gives each load   *)
(* to a free truck; the truck drives to the source (the warehouse, or the *)
(* gate of a supplier), takes the load, drives to the place of the task,  *)
(* and puts the load down there. When each load of the task is at its    *)
(* place, the haul tells its construction, and the task can start.       *)
(* The time of a drive is not in the model: a drive is the step between a *)
(* take and a drop.                                                       *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Tasks,      \* the tasks with a takeoff
    Loads,      \* the loads of all the tasks
    Of,         \* Of[l]: the task of the load l
    Mass,       \* Mass[l]: the mass of the load l, in kg
    Trucks,     \* the trucks of the yard (and the trucks that it rents)
    Cap,        \* the most mass that a truck holds
    Guard,      \* FALSE: the fault model where a truck takes a load while it holds one
    Count       \* FALSE: the fault model where the haul tells a task at its first load

VARIABLES
    asked,      \* the tasks that asked for their loads
    queue,      \* the loads that wait for a truck
    carry,      \* carry[k]: the loads that the truck k holds
    at,         \* the loads at the place of their task
    told,       \* the tasks whose construction knows that their loads are there
    started     \* the tasks that started

vars == <<asked, queue, carry, at, told, started>>

LoadsOf(t) == {l \in Loads : Of[l] = t}

Init ==
    /\ asked = {}
    /\ queue = {}
    /\ carry = [k \in Trucks |-> {}]
    /\ at = {}
    /\ told = {}
    /\ started = {}

\* The construction asks for the loads of a task.
Ask(t) ==
    /\ t \notin asked
    /\ asked' = asked \cup {t}
    /\ queue' = queue \cup LoadsOf(t)
    /\ UNCHANGED <<carry, at, told, started>>

\* A free truck takes a load at the source. Guard: only an empty truck.
Take(k, l) ==
    /\ l \in queue
    /\ Guard => carry[k] = {}
    /\ carry' = [carry EXCEPT ![k] = @ \cup {l}]
    /\ queue' = queue \ {l}
    /\ UNCHANGED <<asked, at, told, started>>

\* The truck drives to the place of the task and puts the load down.
Drop(k, l) ==
    /\ l \in carry[k]
    /\ carry' = [carry EXCEPT ![k] = @ \ {l}]
    /\ at' = at \cup {l}
    /\ UNCHANGED <<asked, queue, told, started>>

\* Each load of t is at its place: the haul tells its construction.
\* Count: each load; the fault model: one load is enough.
Tell(t) ==
    /\ t \in asked /\ t \notin told
    /\ IF Count THEN LoadsOf(t) \subseteq at ELSE LoadsOf(t) \cap at /= {}
    /\ told' = told \cup {t}
    /\ UNCHANGED <<asked, queue, carry, at, started>>

\* The task starts when the haul told its construction.
Start(t) ==
    /\ t \in told /\ t \notin started
    /\ started' = started \cup {t}
    /\ UNCHANGED <<asked, queue, carry, at, told>>

\* Each task started: no deadlock at the end.
Over == started = Tasks /\ UNCHANGED vars

Next ==
    \/ \E t \in Tasks : Ask(t) \/ Tell(t) \/ Start(t)
    \/ \E k \in Trucks, l \in Loads : Take(k, l) \/ Drop(k, l)
    \/ Over

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* --- Invariants --------------------------------------------------------

\* A truck holds at most one load, and a load is never more than a truck holds.
InLoad == \A k \in Trucks : Cardinality(carry[k]) <= 1 /\ \A l \in carry[k] : Mass[l] <= Cap

\* A load is in one place only: in the queue, on one truck, or at its place.
OnePlace ==
    \A l \in Loads :
        /\ l \in queue => (\A k \in Trucks : l \notin carry[k]) /\ l \notin at
        /\ \A k, j \in Trucks : (l \in carry[k] /\ l \in carry[j]) => k = j
        /\ l \in at => \A k \in Trucks : l \notin carry[k]

\* A task starts only after each of its loads is at its place.
PartsFirst == \A t \in started : LoadsOf(t) \subseteq at

\* --- Liveness ----------------------------------------------------------

\* Each task starts in the end.
AllStarted == <>(started = Tasks)
====
