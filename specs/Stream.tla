---- MODULE Stream ----
(***************************************************************************)
(* A stream of events to one client (World.Stream, World.Log.Server). The *)
(* log of the node publishes the events 1, 2, 3 ... in order, and sends   *)
(* each one to the mailbox of each process that watches. A stream starts  *)
(* after the id Start (Last-Event-ID): it watches, then it sends the      *)
(* events of the past (the history: the memory of the log, and the store  *)
(* for the older ones), then each event of its mailbox with an id over    *)
(* the last id that it sent. The client must get each event after Start  *)
(* one time, in order, with no gap.                                       *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANTS
    N,          \* the events that the log publishes: the ids 1 to N
    Start,      \* the stream starts after this id
    Keep,       \* the events that the memory of the log keeps
    Store,      \* TRUE: the store has each event that the memory does not keep
    WatchFirst, \* FALSE: the fault model where the stream reads the past, then watches
    Dedupe      \* FALSE: the fault model where the stream sends each event of its mailbox

VARIABLES
    last,       \* the id of the last event that the log published
    mailbox,    \* the ids in the mailbox of the stream, in order
    phase,      \* "start", "watching", "read" (the past is read), "live"
    past,       \* the ids of the past that the stream read
    sent,       \* the ids that the client got, in order
    seen        \* the last id that the stream sent

vars == <<last, mailbox, phase, past, sent, seen>>

\* The ids from a to b, in order.
Ids(a, b) == [i \in 1..(IF b >= a THEN b - a + 1 ELSE 0) |-> a + i - 1]

\* The events of the past after Start that the log has now: the memory
\* keeps the last Keep events, and the store has the older ones.
History == LET oldest == IF Store THEN 1 ELSE IF last > Keep THEN last - Keep + 1 ELSE 1
           IN Ids(IF Start + 1 > oldest THEN Start + 1 ELSE oldest, last)

Watching == phase \in {"watching", "live"}

Init ==
    /\ last = 0
    /\ mailbox = <<>>
    /\ phase = "start"
    /\ past = <<>>
    /\ sent = <<>>
    /\ seen = Start

\* The log publishes the next event, to the mailbox of a stream that watches.
Publish ==
    /\ last < N
    /\ last' = last + 1
    /\ mailbox' = IF Watching THEN Append(mailbox, last + 1) ELSE mailbox
    /\ UNCHANGED <<phase, past, sent, seen>>

\* The stream starts to watch (in the fault model: after it reads the past).
Watch ==
    /\ \/ WatchFirst /\ phase = "start"
       \/ ~WatchFirst /\ phase = "read"
    /\ phase' = IF WatchFirst THEN "watching" ELSE "live"
    /\ UNCHANGED <<last, mailbox, past, sent, seen>>

\* The stream reads the events of the past (in the fault model: first).
Read ==
    /\ \/ WatchFirst /\ phase = "watching"
       \/ ~WatchFirst /\ phase = "start"
    /\ past' = History
    /\ phase' = IF WatchFirst THEN "live" ELSE "read"
    /\ UNCHANGED <<last, mailbox, sent, seen>>

\* The stream sends the next event of the past.
SendPast ==
    /\ phase = "live" /\ past /= <<>>
    /\ sent' = Append(sent, Head(past))
    /\ seen' = Head(past)
    /\ past' = Tail(past)
    /\ UNCHANGED <<last, mailbox, phase>>

\* The stream takes the next event of its mailbox, and sends it when its
\* id is over the last id that it sent.
Take ==
    /\ phase = "live" /\ past = <<>> /\ mailbox /= <<>>
    /\ LET id == Head(mailbox) IN
         IF id > seen \/ ~Dedupe
         THEN sent' = Append(sent, id) /\ seen' = id
         ELSE UNCHANGED <<sent, seen>>
    /\ mailbox' = Tail(mailbox)
    /\ UNCHANGED <<last, phase, past>>

\* Each event is published, and the stream sent each one that it has.
Over == last = N /\ phase = "live" /\ past = <<>> /\ mailbox = <<>> /\ UNCHANGED vars

Next == Publish \/ Watch \/ Read \/ SendPast \/ Take \/ Over

Spec == Init /\ [][Next]_vars /\ WF_vars(Next)

\* --- Invariants --------------------------------------------------------

\* The client gets the events in the order of their ids, each one time.
InOrder == \A i \in 1..Len(sent) : \A j \in 1..Len(sent) : i < j => sent[i] < sent[j]

\* Each event that the client gets is after Start.
AfterStart == \A i \in 1..Len(sent) : sent[i] > Start

\* At the end, the client got each event after Start: no gap.
NoGap == (last = N /\ phase = "live" /\ past = <<>> /\ mailbox = <<>>) => sent = Ids(Start + 1, N)

\* --- Liveness ----------------------------------------------------------

\* In the end, the stream sent each event after Start.
AllSent == <>(sent = Ids(Start + 1, N))
====
