---- MODULE Census ----
(***************************************************************************)
(* The census of the node and the constructions that share its people    *)
(* (World.Census, World.Construction). Each construction does its tasks   *)
(* in order; each task needs a person of its trade. A construction asks   *)
(* the census for a person; the census gives a free person of the trade,  *)
(* or a new person while the node has fewer than Limit, or, at the limit, *)
(* a free person of another trade leaves and a new person of the trade    *)
(* comes. A person that ends a task stays with its construction, free.    *)
(* With Yield, a construction that waits for a person gives back the free *)
(* people that it holds, so two constructions never wait for each other.  *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets, Sequences

CONSTANTS
    Builds,     \* the constructions
    Persons,    \* the names that the people of the node can have
    Limit,      \* the most people of the node
    Work,       \* Work[b]: the trades of the tasks of b, in order
    Yield,      \* FALSE: the fault model where a construction keeps its free people
    Guard       \* FALSE: the fault model where the census can give a person that works

VARIABLES
    alive,      \* the people of the node
    trade,      \* trade[p]: the trade of the person p
    by,         \* by[p]: the construction that holds p, or ""
    task,       \* task[p]: the construction of the task of p, or ""
    next,       \* next[b]: the index of the next task of b
    want,       \* want[b]: b waits for a person
    done        \* the constructions that are done

vars == <<alive, trade, by, task, next, want, done>>

Trades == UNION {{Work[b][i] : i \in 1..Len(Work[b])} : b \in Builds}
Free(p) == p \in alive /\ by[p] = ""
Need(b) == Work[b][next[b]]
Left(b) == next[b] <= Len(Work[b])
Idle(b, p) == by[p] = b /\ task[p] = ""

Init ==
    /\ alive = {}
    /\ trade = [p \in Persons |-> CHOOSE t \in Trades : TRUE]
    /\ by = [p \in Persons |-> ""]
    /\ task = [p \in Persons |-> ""]
    /\ next = [b \in Builds |-> 1]
    /\ want = [b \in Builds |-> FALSE]
    /\ done = {}

\* b holds no free person of the trade of its next task: it asks the census.
Ask(b) ==
    /\ b \notin done /\ Left(b) /\ ~want[b]
    /\ ~\E p \in Persons : Idle(b, p) /\ trade[p] = Need(b)
    /\ want' = [want EXCEPT ![b] = TRUE]
    /\ UNCHANGED <<alive, trade, by, task, next, done>>

\* The census gives b the person p: a free person of the trade, a new
\* person under the limit, or a new person in the place of a free person
\* of another trade at the limit. Guard keeps it from a person that works.
Give(b, p) ==
    /\ want[b]
    /\ \/ Free(p) /\ trade[p] = Need(b)
       \/ p \notin alive /\ Cardinality(alive) < Limit
       \/ Free(p) /\ trade[p] /= Need(b) /\ Cardinality(alive) = Limit
          /\ ~\E q \in alive : Free(q) /\ trade[q] = Need(b)
       \/ ~Guard /\ p \in alive /\ by[p] /= "" /\ by[p] /= b
    /\ alive' = alive \cup {p}
    /\ trade' = [trade EXCEPT ![p] = Need(b)]
    /\ by' = [by EXCEPT ![p] = b]
    /\ want' = [want EXCEPT ![b] = FALSE]
    /\ UNCHANGED <<task, next, done>>

\* A free person of b starts the next task of b.
Start(b, p) ==
    /\ Left(b) /\ Idle(b, p) /\ trade[p] = Need(b)
    /\ task' = [task EXCEPT ![p] = b]
    /\ next' = [next EXCEPT ![b] = @ + 1]
    /\ want' = [want EXCEPT ![b] = FALSE]
    /\ UNCHANGED <<alive, trade, by, done>>

\* The person ends its task, and stays with its construction.
Finish(p) ==
    /\ task[p] /= ""
    /\ task' = [task EXCEPT ![p] = ""]
    /\ UNCHANGED <<alive, trade, by, next, want, done>>

\* b waits, and gives back a free person that it does not need now.
Give_back(b, p) ==
    /\ Yield /\ want[b] /\ Idle(b, p) /\ trade[p] /= Need(b)
    /\ by' = [by EXCEPT ![p] = ""]
    /\ UNCHANGED <<alive, trade, task, next, want, done>>

\* Each task of b is done: b lets its people go.
Done(b) ==
    /\ b \notin done /\ ~Left(b)
    /\ \A p \in Persons : by[p] = b => task[p] = ""
    /\ by' = [p \in Persons |-> IF by[p] = b THEN "" ELSE by[p]]
    /\ done' = done \cup {b}
    /\ UNCHANGED <<alive, trade, task, next, want>>

\* Each construction is done: no deadlock at the end.
Over == done = Builds /\ UNCHANGED vars

Next ==
    \/ \E b \in Builds : Ask(b) \/ Done(b)
    \/ \E b \in Builds, p \in Persons : Give(b, p) \/ Start(b, p) \/ Give_back(b, p)
    \/ \E p \in Persons : Finish(p)
    \/ Over

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* --- Invariants --------------------------------------------------------

\* The node never has more people than its limit.
InLimit == Cardinality(alive) <= Limit

\* A person that works works for the construction that holds it.
NoSteal == \A p \in Persons : task[p] /= "" => by[p] = task[p]

\* --- Liveness ----------------------------------------------------------

\* Each construction is done in the end.
AllDone == <>(done = Builds)
====
