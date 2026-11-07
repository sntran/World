---- MODULE MCPlaces ----
(***************************************************************************)
(* A small model of Places: the gate and the site are open; the warehouse *)
(* and the factory of the vehicles have a building. A truck (a van) and a *)
(* scooter are at the factory of the vehicles, a house at the site.         *)
(* MCPlaces.cfg checks the first start as World makes it. MCPlacesLost.cfg *)
(* is the fault model where the plan of the first start has no factory of  *)
(* the vehicles: the checker must find that the truck waits forever.       *)
(* MCPlacesEarly.cfg is the fault model where a construction does not      *)
(* wait for its place: the checker must find AtOpen violated.              *)
(***************************************************************************)
EXTENDS Places, TLC

MCPlaces == {"gate", "warehouse", "vehicles", "site"}
MCBuilt == {"warehouse", "vehicles"}
MCBuilds == {"truck", "scooter", "house"}
MCAt == ("truck" :> "vehicles") @@ ("scooter" :> "vehicles") @@ ("house" :> "site")
====
