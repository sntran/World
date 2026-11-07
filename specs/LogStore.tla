---- MODULE LogStore ----
(***************************************************************************)
(* The log of the node and its store (World.Log.Server, World.Log.Store). *)
(* The log gives each new event the next id, and sends it to the         *)
(* watchers at once. It keeps the event in a buffer, and puts the buffer  *)
(* into the store when it has Batch events, or after a time. The VM can   *)
(* stop (a deploy, too little memory): the buffer is lost. A new log      *)
(* starts from the last id of the store, plus Gap, and puts that id into  *)
(* the store at once (Mark). A client that knows an id (Last-Event-ID)    *)
(* must never get another event with that id.                             *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets, Sequences

CONSTANTS
    N,          \* the events that the node makes
    Batch,      \* the log puts its buffer into the store at this count
    Crashes,    \* the most times that the VM stops
    Gap,        \* the ids that a new log leaves after the last id of the store
    Mark        \* TRUE: a new log puts its first id into the store at once

VARIABLES
    up,         \* the log runs
    last,       \* the id of the last event of the log
    buffer,     \* the ids of the buffer, in order
    stored,     \* the ids in the store
    named,      \* each pair <<id, event>> that the log sent: the watchers know it
    made,       \* the events that the node made
    crashed     \* the times that the VM stopped

vars == <<up, last, buffer, stored, named, made, crashed>>

Max(S) == IF S = {} THEN 0 ELSE CHOOSE x \in S : \A y \in S : y <= x

Init ==
    /\ up = TRUE
    /\ last = 0
    /\ buffer = <<>>
    /\ stored = {}
    /\ named = {}
    /\ made = 0
    /\ crashed = 0

\* The node makes an event: it gets the next id, goes to the watchers, and
\* into the buffer; a full buffer goes into the store.
Publish ==
    /\ up /\ made < N
    /\ made' = made + 1
    /\ last' = last + 1
    /\ named' = named \cup {<<last + 1, made + 1>>}
    /\ IF Len(buffer) + 1 >= Batch
       THEN /\ stored' = stored \cup {buffer[i] : i \in 1..Len(buffer)} \cup {last + 1}
            /\ buffer' = <<>>
       ELSE /\ buffer' = Append(buffer, last + 1)
            /\ UNCHANGED stored
    /\ UNCHANGED <<up, crashed>>

\* The time of a batch: the buffer goes into the store.
Flush ==
    /\ up /\ buffer /= <<>>
    /\ stored' = stored \cup {buffer[i] : i \in 1..Len(buffer)}
    /\ buffer' = <<>>
    /\ UNCHANGED <<up, last, named, made, crashed>>

\* The VM stops: the memory and the buffer are lost.
Crash ==
    /\ up /\ crashed < Crashes
    /\ up' = FALSE
    /\ buffer' = <<>>
    /\ crashed' = crashed + 1
    /\ UNCHANGED <<last, stored, named, made>>

\* A new log starts from the last id of the store, plus Gap. With Mark,
\* it puts its first id into the store before any other event (the event
\* "started"), so the next new log starts after it.
Restart ==
    /\ ~up
    /\ up' = TRUE
    /\ last' = Max(stored) + Gap
    /\ stored' = IF Mark THEN stored \cup {Max(stored) + Gap} ELSE stored
    /\ UNCHANGED <<buffer, named, made, crashed>>

\* Each event is made and in the store: no deadlock at the end.
Over == made = N /\ up /\ buffer = <<>> /\ UNCHANGED vars

Next == Publish \/ Flush \/ Crash \/ Restart \/ Over

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* --- Invariants --------------------------------------------------------

\* An id names one event only.
OneName == \A p, q \in named : p[1] = q[1] => p[2] = q[2]

\* The buffer is never full: it goes into the store at Batch events, so a
\* stop of the VM loses fewer than Batch ids.
SmallBuffer == Len(buffer) < Batch

\* The ids of the log go up: each new id is over each id of the store.
UpOnly == \A id \in stored : id <= last
====
