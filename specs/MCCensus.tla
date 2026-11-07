---- MODULE MCCensus ----
(***************************************************************************)
(* A small model of Census: two constructions and a node of two people.   *)
(* The house needs a mason, then a steelworker; the shed a steelworker,   *)
(* then a mason. MCCensus.cfg checks the census as World makes it.         *)
(* MCCensusKeep.cfg is the fault model where a construction keeps its     *)
(* free people: each holds one and waits for the other, so the checker    *)
(* must find the dead end. MCCensusSteal.cfg is the fault model where the  *)
(* census gives a person that works: the checker must find it.            *)
(***************************************************************************)
EXTENDS Census, TLC

MCBuilds == {"house", "shed"}
MCPersons == {"p1", "p2"}
MCWork == ("house" :> <<"mason", "steel">>) @@ ("shed" :> <<"steel", "mason">>)
====
