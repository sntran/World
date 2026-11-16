---- MODULE MCBuild ----
(***************************************************************************)
(* A small model of Build: two constructions that share three people of   *)
(* two trades. The house has a wall of a mason, then a rail of a           *)
(* steelworker on the wall; the shed has two walls of a mason. The house  *)
(* holds two people at most, the shed one. MCBuild.cfg checks it;          *)
(* Each construction can pause once. MCBuildFault.cfg checks the fault     *)
(* model where a task starts again, MCBuildHire.cfg where a busy person is *)
(* hired, MCBuildPause.cfg where a task starts in a pause, and             *)
(* MCBuildKeep.cfg where a change forgets a task that it keeps. The rail   *)
(* has a takeoff: the trucks bring its steel first. MCBuildParts.cfg is   *)
(* the fault model where a task starts before its materials.              *)
(***************************************************************************)
EXTENDS Build, TLC

MCBuilds == {"house", "shed"}
MCTasks == {"wall", "rail", "left", "right"}
MCBuildOf == ("wall" :> "house") @@ ("rail" :> "house") @@ ("left" :> "shed") @@ ("right" :> "shed")
MCWaits == ("wall" :> {}) @@ ("rail" :> {"wall"}) @@ ("left" :> {}) @@ ("right" :> {})
MCTrade == ("wall" :> "mason") @@ ("rail" :> "steel") @@ ("left" :> "mason") @@ ("right" :> "mason")
MCPeople == {"p1", "p2", "p3"}
MCSkill == ("p1" :> "mason") @@ ("p2" :> "mason") @@ ("p3" :> "steel")
MCBudget == ("house" :> 2) @@ ("shed" :> 1)
MCHauled == {"rail"}
====
