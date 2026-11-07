---- MODULE Places ----
(***************************************************************************)
(* The first start of the node (World.Yard; plan 0002, D7 and D8). The     *)
(* places with a building (the warehouse, the factories) are closed at the *)
(* start; the others (the gate, the site) are open. The yard raises the    *)
(* buildings of its plan: the people build each as a house on its lot, and *)
(* the place opens when its building is done. A construction of a model    *)
(* (and of a truck: a van at the factory of the vehicles) goes to the      *)
(* place of its kind, and starts only when the place is open; until then   *)
(* the yard holds it.                                                       *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    Places,     \* the places of the yard
    Built,      \* the places with a building: closed at the start
    Plan,       \* the buildings that the yard raises at its first start
    Builds,     \* the constructions of the models and of the trucks
    At,         \* At[c]: the place of the construction c
    Guard       \* FALSE: the fault model where a construction does not wait for its place

VARIABLES
    open,       \* the places that are open
    raised,     \* the buildings that the people build now
    held,       \* the constructions that the yard holds for their place
    started,    \* the constructions that started
    done        \* the constructions that are done

vars == <<open, raised, held, started, done>>

Init ==
    /\ open = Places \ Built
    /\ raised = {}
    /\ held = {}
    /\ started = {}
    /\ done = {}

\* The yard raises a building of its plan.
Raise(p) ==
    /\ p \in Plan /\ p \notin open /\ p \notin raised
    /\ raised' = raised \cup {p}
    /\ UNCHANGED <<open, held, started, done>>

\* The building is done: the place opens.
Open(p) ==
    /\ p \in raised
    /\ raised' = raised \ {p}
    /\ open' = open \cup {p}
    /\ UNCHANGED <<held, started, done>>

\* A client asks for a construction whose place is not open: the yard holds it.
Hold(c) ==
    /\ c \notin held /\ c \notin started
    /\ At[c] \notin open
    /\ held' = held \cup {c}
    /\ UNCHANGED <<open, raised, started, done>>

\* A construction starts at its place when the place is open. Guard: only then.
Start(c) ==
    /\ c \notin started
    /\ Guard => At[c] \in open
    /\ started' = started \cup {c}
    /\ held' = held \ {c}
    /\ UNCHANGED <<open, raised, done>>

Done(c) ==
    /\ c \in started /\ c \notin done
    /\ done' = done \cup {c}
    /\ UNCHANGED <<open, raised, held, started>>

\* Each construction is done, and each place is open: no deadlock at the end.
Over == done = Builds /\ open = Places /\ UNCHANGED vars

Next ==
    \/ \E p \in Places : Raise(p) \/ Open(p)
    \/ \E c \in Builds : Hold(c) \/ Start(c) \/ Done(c)
    \/ Over

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* --- Invariants --------------------------------------------------------

\* A construction works only at a place that is open.
AtOpen == \A c \in started : At[c] \in open

\* --- Liveness ----------------------------------------------------------

\* The first start ends: each place opens.
Bootstrap == <>(open = Places)

\* No construction waits for a place that nobody builds: each is done in the end.
AllDone == <>(done = Builds)
====
