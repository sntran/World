---- MODULE MCHaul ----
(***************************************************************************)
(* A small model of Haul: two tasks (a band of bricks of two loads, and a *)
(* slab of one load) and two trucks of 1,500 kg. MCHaul.cfg checks the     *)
(* haul as World makes it. MCHaulTwo.cfg is the fault model where a truck *)
(* takes a second load: the checker must find InLoad violated.             *)
(* MCHaulEarly.cfg is the fault model where the haul tells a task at its  *)
(* first load: the checker must find PartsFirst violated.                 *)
(***************************************************************************)
EXTENDS Haul, TLC

MCTasks == {"wall", "slab"}
MCLoads == {"w1", "w2", "s1"}
MCOf == ("w1" :> "wall") @@ ("w2" :> "wall") @@ ("s1" :> "slab")
MCMass == ("w1" :> 1499) @@ ("w2" :> 101) @@ ("s1" :> 1200)
MCTrucks == {"t1", "t2"}
====
