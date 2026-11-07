---- MODULE MCLogStore ----
(***************************************************************************)
(* A small model of LogStore: 5 events, a batch of 3, and two stops of    *)
(* the VM. MCLogStore.cfg checks the log as World makes it: a new log     *)
(* leaves Batch ids after the last id of the store. MCLogStoreReuse.cfg   *)
(* is the fault model where a new log goes on from the last id of the     *)
(* store, and MCLogStoreTwice.cfg the one where a new log leaves Batch     *)
(* ids but does not put its first id into the store: the checker must     *)
(* find an id that names two events in each.                              *)
(***************************************************************************)
EXTENDS LogStore, TLC
====
