---- MODULE MCOrder ----
(***************************************************************************)
(* A small model of Order: a body, two doors, and a wheel of a rim and a  *)
(* tire (a smaller assembly), with two workers, a truck of two items, and  *)
(* a warehouse of 6 bytes. MCOrder.cfg checks it; MCOrderFault.cfg checks *)
(* the fault model, where the checker must find two workers on one task.   *)
(***************************************************************************)
EXTENDS Order, TLC

MCItems == {"body", "door", "rim", "tire"}
MCSize == ("body" :> 3) @@ ("door" :> 1) @@ ("rim" :> 1) @@ ("tire" :> 1)
MCNeed == ("body" :> 1) @@ ("door" :> 2) @@ ("rim" :> 1) @@ ("tire" :> 1)
MCTasks == {"body", "door_left", "door_right", "wheel/rim", "wheel/tire", "wheel/order", "wheel"}
MCWaits ==
    ("body" :> {}) @@ ("door_left" :> {"body"}) @@ ("door_right" :> {"body"})
    @@ ("wheel/rim" :> {}) @@ ("wheel/tire" :> {"wheel/rim"})
    @@ ("wheel/order" :> {"wheel/rim", "wheel/tire"}) @@ ("wheel" :> {"body", "wheel/order"})
MCUses ==
    ("body" :> "body") @@ ("door_left" :> "door") @@ ("door_right" :> "door")
    @@ ("wheel/rim" :> "rim") @@ ("wheel/tire" :> "tire")
    @@ ("wheel/order" :> "") @@ ("wheel" :> "")
MCWorkers == {"dung", "em"}
====
