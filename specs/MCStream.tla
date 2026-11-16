---- MODULE MCStream ----
(***************************************************************************)
(* A small model of Stream: the log publishes 4 events, and a stream      *)
(* starts after the event 1. MCStream.cfg checks the stream as World does *)
(* it: it watches first, reads the past from the memory and the store,    *)
(* and sends each id once. The fault models must fail: MCStreamLate.cfg   *)
(* (it reads the past, then watches: a gap), MCStreamTwice.cfg (no check *)
(* of the id: an event comes twice) and MCStreamMemory.cfg (a memory of   *)
(* 1 event and no store: the older events are not there).                 *)
(***************************************************************************)
EXTENDS Stream, TLC
====
