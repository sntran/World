# The format of a model

This file tells how World describes a part, an assembly and a voxel
model, and how it writes them as files. It is a plan: the code comes in
the steps of `README.md`.

## The units and the axes

- The unit of length is the meter. An angle is in degrees.
- The axes have the right hand:
  - x goes to the right side of the model (the right of a rider),
  - y goes to its front,
  - z goes up.
- **A part** has its own origin, at a point that its standard gives: a
  bolt has its origin at the center of the bottom of its head, with its
  shank along -z.
- **A model** (the top assembly) has its origin on the ground, at the
  center of its box in x and y. A vehicle stands with its wheels on
  z = 0, with its front to +y.

## A part

```elixir
%World.Part{
  name: "bolt_m8x60",
  kind: :bolt,
  params: %{thread: "M8", length: 0.060},
  sources: ["ISO 4017: the head is 13 mm across the flats and 5.3 mm high."],
  ports: [...],
  shapes: [...],
  detail: :fastener,
  print: :keep
}
```

- `name`: the key of the part, in lower case with `_`.
- `kind`: the family of the part: `:bolt`, `:nut`, `:washer`,
  `:bearing`, `:tube`, `:sheet`, `:lumber`, `:extrusion`, `:rim`,
  `:tire`, `:shaped`, and more.
- `params`: the numbers that make the part. The same params give the
  same part, byte by byte.
- `sources`: where each size comes from, in words: a standard, a data
  sheet, or a measurement. A size that is a guess says so.
- `ports`: the places where the part connects to another part (below).
- `shapes`: the meshes of the part, each with its material role. The
  core of Wings makes them (`World.Mesh`).
- `detail`: the class of the part for the levels of detail (below).
- `print`: `:keep`, `:skip` (not in the STL: too thin) or `:only` (only
  in the STL: a thicker stand-in).

A **standard part** is a function: `World.Materials.Fasteners.bolt("M8", 0.060)`.
Its tests compare its sizes with the tables of its standard.

A **shaped part** is a `.wings` file and a small module next to it. The
module gives the name, the sources and the ports, and reads the file
(`World.Wings.read/1`). When the Wings plugin of step 6 exists, the
ports can also come from the file.

## A port

A port is a frame on a part: a point and two directions.

```elixir
%World.Port{name: "hub", at: {0.0, 0.0, 0.0}, axis: {1.0, 0.0, 0.0}, up: {0.0, 0.0, 1.0}}
```

- `at`: the point, in the axes of the part.
- `axis`: the main direction: the axis of a hole, of a shaft, of a
  thread.
- `up`: a second direction at a right angle to `axis`. It fixes the
  turn around the axis.

Examples: a bolt has the ports `head` (under the head) and `tip` (the
end of the thread). A wheel has `hub`. A fork has `axle_left` and
`axle_right`. A hinge has `leaf_a` and `leaf_b` on one axis.

A port of a figure can be on a bone (`bone`): its point and its
directions are in the axes of the bone. A thing on such a port goes in
the node of the bone in the GLB, so it follows the bone in each pose
and each animation.

## An assembly

An assembly is a tree. The root is a part or an assembly. Each child
connects to its parent with one connection:

```elixir
%World.Connection{
  child: "rear_wheel",
  child_port: "hub",
  parent_port: "rear_axle",
  kind: :hinge,
  offset: 0.0,
  turn: 0.0,
  limits: nil
}
```

The build puts the child so that its port is on the port of its parent:
the two points are at the same place, the two axes are the same, and the
two `up` directions are the same. Then it moves the child by `offset`
along the axis and turns it by `turn` around the axis.

The kinds of a connection:

| Kind | The child can | `limits` |
|---|---|---|
| `:fixed` | not move (a bolt in a hole, a panel on a frame) | `nil` |
| `:hinge` | turn around the axis (a wheel, a door, the bars, a knee) | `nil` for a wheel, else `[min, max]` in degrees |
| `:slide` | move along the axis (a drawer, a fork tube in a shock) | `[min, max]` in meters |

Each connection that is not `:fixed` is a **joint**. A joint has a
`role` that tells an app what to do with it:

- `wheel`: it turns with the speed.
- `steer`: the bars and the front wheel, around the steering axis.
- `suspension`: a fork or a shock, a small move along its axis.
- `door`, `lid`, `drawer`: a part that opens.
- `recline`: the back of a seat that turns to the rear.
- `handle`: a handle that slides out (the trolley of a power station).
- `spin`: a part that turns when the item runs (a fan, the drum of a
  washer, a turntable).
- `knob`: a knob or a dial, and a faucet that swivels.
- `vane`: a vane that turns the flow of air (a mini split).
- `slide`: a part that a person moves along a track and locks (a
  fitting in an L-track).
- `limb`: a part of a person or of an animal.

A model has no joint for the lean of a vehicle with two wheels. An app
turns the whole model around the line on the ground under its wheels.

A **pose** is the value of each joint, by its name:
`%{"rear_wheel" => 45, "steer" => -10}`. A value out of the limits
stops at the nearest limit, as a real joint stops.

`World.Joint` is the one model of a joint, for a door on a van and for
an elbow of a person: its `name`, its `kind` (`:hinge`, `:slide`, or
`:ball` with the three values `flex`, `spread` and `twist`), its
`limits`, its `role`, and for a person the `bone` that turns. The
extras of a joint node come from it.

A loop of connections (a frame with two struts to one part) is not a
tree. The build refuses it in step 3. `TODO.md` has the idea of a loop
that closes with a fixed connection.

## The levels of detail

The build writes three levels of each model:

| Level | Parts that stay | Smooth of a shaped part | Use |
|---|---|---|---|
| near | all | the level of the part (most often 2) | close views, the sheet of a vehicle |
| mid | the parts of 2 cm or more, not `inside` | one level less | a model in a scene |
| far | the parts of 10 cm or more, not `inside` | none | small or far models, the bar of Phượt |

- The size of a part is the longest side of its box.
- A part with `inside: true` (a bolt in a body, a bearing in a hub) is
  only in the near level.
- `detail` can move a part up or down a level: a light of a vehicle
  stays in the far level, because the eye looks for it.
- A model is made again for each level (`World.Detail`): at the mid
  level a round shape has half of its sides and one smooth step less,
  and the sections of a body are two times farther apart; at the far
  level, a quarter of the sides, no smooth step, and four times farther.
- The root part of a model stays at each level: a small model (a switch
  of 7 cm) keeps its body at far.
- A part with `detail: :low` is only in the mid and far levels: it
  stands in for many small parts (a solid wall for its bricks, a solid
  roof for its tiles). It is not in the list of the parts.
- The triangles of a vehicle or an item are 50,000 or fewer in the near
  level, 12,000 or fewer in the mid level, and 5,000 or fewer in the far
  level. A house can have 300,000 in the near level (one part for each
  brick and tile), 20,000 in the mid level and 12,000 in the far level.
  A test of each model checks it.

## A house

A house is an assembly of its materials (`World.Buildings`):

- **A wall of masonry**: units (`World.Materials.Construction`: the brick of
  Việt Nam, TCVN 1451, 220 by 105 by 60 mm; the modular brick, ASTM
  C216; the hollow concrete block of 8 in, ASTM C90) in running bond,
  with joints of mortar of 10 mm, one or two wythes. At the end of a
  course and at an opening a unit is cut: a cut unit has the name of the
  whole unit, so the list counts the units to buy. A lintel of concrete
  goes over each opening; a gable narrows to its ridge.
- **A wall of wood studs**: 2x4 at 16 in, a bottom plate (cut at each
  door), a double top plate, a king stud, a jack stud and a header of two
  2x8 at each opening, a sill and cripples under a window; OSB of 7/16 in
  (its params count the sheets of 4 by 8 ft) and lap siding.
- **A gable roof**: rafters of 2x6 at 24 in, a ridge board of 2x8, OSB,
  fascia, and clay tiles (10 to the square meter) or metal panels (PBR,
  36 in of cover; the last panel is cut to the width).
- **Doors and windows**: a prehung door (jambs, a slab on three hinges, a
  knob) that opens to the inside; a casement window that opens out, or a
  fixed window.

The axes of a wall: along x from 0 to its length, its outside face at
y = 0, z up. An opening is `{kind, x, width, z, height}` in the axes of
the wall: the rough opening.

## The materials

A material is a role, not a color:

`paint` (the color of the thing), `trim` (black plastic and rubber
strips), `glass`, `glass_dark`, `tire`, `rim`, `chrome`, `metal`,
`steel`, `aluminum`, `light_front`, `light_back`, `seat`, `plastic`,
`wood`, `fabric`, `skin`, `hair`, `cloth`, `white`, `dark`, `black`,
`gray`, `rubber`, `copper`, `stainless`, `screen`, `blue`, `orange`,
`red`, `plywood`, `solar_cell`. A person
has more roles with their textures: `eyes`, `eyebrows`, `eyelashes`,
`clothes_NAME`, and `color_NAME` (the mean color of an asset at mid and
far).

`priv/palette.json` gives each role a color, a roughness and a
metalness. Glass also has an alpha (0.35 for `glass`, 0.85 for
`glass_dark`): its glTF material has the alpha mode `BLEND`. An app can give its own palette (the woodblock tones of Tre),
and it can change the `paint` of a model (the color of the car of a
person). In a `.wings` file, the name of a material is its role.

## A person

A person (`World.People.Human.person/2`) is a `World.Figure`: a set of nodes
that is ready, from the data of MakeHuman (`priv/makehuman/`). An
assembly holds a figure as a part, at one of its two ports:

- `ground`: on the ground, between the feet, with z up;
- `hips`: at the head of the bone `pelvis`, with z up (the seat of a
  rider).

The GLB of a person has:

- a root node, then a node for each of the 53 bones of the skeleton
  `game_engine` (parents first), with the frames of the pose;
- one mesh node with a skin. It is a root node of the scene: glTF does
  not use the frame of a skinned mesh, and the bones place it;
- 4 joints and 4 weights for each point, with the sum 1;
- textures in the GLB (the skin, the eyes, the hair, the clothes). Hair,
  eyebrows and eyelashes have the alpha mode `MASK`;
- the animations by name (`walk`: a loop of 1.1 s; `wave` and `point`:
  2.6 s, to play once, from the pose "stand" back to it). The channels
  of a clip are the bones that move in it.

### The skeleton and the poses

`World.People.Skeleton` turns the joints of the skeleton. Each bone has
its own axes, from the roll of the rig: y goes from its head to its
tail, x is the hinge of its joint (z for the thumb). The bones of the
right side are the mirrors of the bones of the left side. A pose is a
map:

| Key | Value | What it does |
|---|---|---|
| a bone | a list of turns, in order | `{:flex, deg}` bends the joint around its hinge, `{:spread, deg}` turns it to the side, `{:twist, deg}` turns it around the bone. `{{x, y, z}, deg}` turns it around an axis of World of the person at rest (the old form: the poses "sit", "ride" and "drive" use it). |
| `{:aim, :l}`, `{:aim, :r}` | `%{to: dir, pole: dir, end: :wrist}` | The shoulder turns so that the wrist (or the elbow, `end: :elbow`) is in the direction `to`, and the elbow (or the wrist) goes to the side of `pole`. The collarbone lifts a little with an arm over the horizon. |
| `:look` | a direction | The neck (two parts of five) and the head turn so that the face looks there. |
| `{:hand, :l}`, `{:hand, :r}` | `"relaxed"`, `"open"`, `"fist"`, `"point"`, `"thumbs_up"` | The shape of the hand (`World.People.Pose`). |
| `:spine` | `[flex: deg, spread: deg, twist: deg]` | A bend to the front, a bend to the right side, a turn to the left side: a third on each bone of the spine. |
| `:hips` | `%{at: move, turn: [flex:, spread:, twist:]}` | The hips (and all the body) move and turn. The feet stay on the ground. |
| `{:reach, :l}`, `{:reach, :r}` | `%{by: move}` (from the shoulder at rest) or `%{at: point}`, and `pole` | The wrist goes to the point; the elbow bends as much as it must, to the side of `pole` (down and back by default). The other turns of the forearm stay (a twist turns the palm: +70 down, -60 to the other hand). |
| `{:foot, :l}`, `{:foot, :r}` | `%{by: move}` (from the ankle at rest) or `%{at: point}`, and `pole`, `flat` (true), `toe` (degrees out) | The ankle goes to the point, the knee to the side of `pole` (the front by default), and a flat foot keeps its sole level. `:free`: no target. |

The arm (`reach`) and the leg (`foot`) are chains of two bones: the law
of cosines gives the bend of the middle joint, a few steps of Newton
correct the small angle out of the plane of the hinge, then the first
bone turns to the target and around the line to the pole.

### The routines

A routine (`World.People.Pose.routine/1`) is a list of poses at their
times, in a loop. Each bone moves on the shortest arc from one pose to
the next, with a smooth start and stop. During each move the feet stay
on their targets; a foot that goes to a new place lifts on an arc (at
most 12 cm). The hips move: the animation has a channel of translation
for the bone `pelvis`. An option `delay` starts a person late, and
`mirror` makes the routine of a leader who faces the group.

| Routine | Length | What it shows |
|---|---|---|
| `tai_chi` | 16 s | The opening: the arms rise with the palms down and sink on bent knees; "wave hands like clouds" to the left and to the right, with the weight from one leg to the other and the waist turning. |
| `yoga` | 24 s | Mountain with the palms together at the chest, the arms up, a forward fold, the tree on the left leg (the right foot at the left knee, the hands together over the head), warrior II to the left. |
| `aerobics` | 8 s | At 120 beats a minute: a march with the knees up and the arms pumping, jumping jacks, steps to the side with punches, knee lifts with a clap. |


The flex of a hinge (the elbow, the wrist, the knee, the joints of the
fingers and the two last joints of the thumb) is the angle from
straight, in the plane of the hinge, in its limits:

| Hinge | Limits (degrees) | At rest |
|---|---|---|
| Elbow (`lowerarm`) | 0 to 150 | 46 |
| Wrist (`hand`) | -70 to 80 | 13 |
| Knee (`calf`) | 0 to 150 | 6 |
| Finger, first joint (`index_01` and the others) | -15 to 90 | 10 to 17 |
| Finger, second joint | 0 to 110 | about 12 |
| Finger, last joint | 0 to 80 | about 8 |
| Thumb, second joint | -20 to 60 | 21 |
| Thumb, last joint | -10 to 80 | 5 |

### The ports and the props of a person

A person has these ports:

| Port | On | Where | `axis` | `up` |
|---|---|---|---|---|
| `ground` | (at rest) | On the ground, between the feet. | Up | To the front |
| `hips` | (at rest) | At the head of the bone `pelvis`. | Up | To the front |
| `grip_l`, `grip_r` | `hand_l`, `hand_r` | In the palm, where a closed hand holds a handle. | Along the handle, to the side of the thumb | Out of the palm |
| `crown` | `head` | On the top of the head. | Up | To the front |
| `back` | `spine_03` | On the back, between the shoulder blades. | To the back | Up |
| `sole_l`, `sole_r` | `foot_l`, `foot_r` | On the ground under the middle of the foot. | Down | To the toes |

A prop (`World.People.Props`) is a part with a port of the same name
with no side (`grip` for `grip_r`): `World.Figure.hold/4` puts it on a
port of the figure, and the option `hold` of `Human.person/2` gives a
list of them. A hand that holds a prop closes on it (the shape `grip`),
in the pose and in each animation. The props now:

| Prop | Port | The thing |
|---|---|---|
| `fan` | `grip` | An open tai chi fan: ribs of bamboo of about 33 cm, a leaf of red silk, open to 160 degrees. |
| `bottle` | `grip` | A bottle of water of 500 ml (65 by 205 mm), held at its side. |
| `non_la` | `crown` | A nón lá: a cone of palm leaves of about 41 cm across and 19 cm high. |

A node of an assembly can also connect to a port on a bone (`at:
"grip_r"`): it goes in the node of the bone too.

### The joints of a person in an order

An order gives the values of the joints of a person in `"joints"`
(`World.People.Joints`). Each joint of a limb has a side: `_l` or `_r`.
The two sides are mirrors: a value has the same meaning on the two
sides. A ball has three values, `NAME.flex`, `NAME.spread` and
`NAME.twist`. A person in a scene (a traveler, a group) has the path of
its node in front: `traveler/elbow_r`, `p3/knee_l`. The receipt lists
the names of all the joints of the model.

| Joint | Kind | Value | Limits (degrees) |
|---|---|---|---|
| `elbow_l`, `elbow_r` | hinge | The angle from straight. | 0 to 150 |
| `wrist_l`, `wrist_r` | hinge | The angle from straight; more bends the palm in. | -70 to 80 |
| `knee_l`, `knee_r` | hinge | The angle from straight. | 0 to 150 |
| `ankle_l`, `ankle_r` | hinge | From the rest; more points the toes down. | -20 to 50 |
| `thumb_l`, `index_l`, `middle_l`, `ring_l`, `pinky_l` (and `_r`) | hinge | The curl: the three joints of the finger together (1, 1.1 and 0.8 of the value; 0.6 and 0.8 on the two last joints of the thumb). | 0 to 90 |
| `shoulder_l`, `shoulder_r` | ball | `flex` to the front, `spread` out to the side, `twist` around the arm. | flex -60 to 180, spread -45 to 135, twist -90 to 90 |
| `hip_l`, `hip_r` | ball | `flex` to the front, `spread` out to the side, `twist` around the leg. | flex -30 to 120, spread -20 to 45, twist -45 to 45 |
| `neck` | ball | `flex` to the front, `spread` to the right side, `twist` to the left side. | flex -50 to 60, spread -45 to 45, twist -70 to 70 |
| `spine` | ball | The same as the neck, a third on each bone of the spine. | flex -30 to 80, spread -35 to 35, twist -40 to 40 |

The value of a hinge replaces the flex of the pose. The values of a
ball turn the joint in the axes of the body, before the turns of the
pose. An arm with `aim` or `reach`, and a leg with a foot on a point,
ignore the joints that the inverse kinematics sets. The limits of the
balls are the normal ranges of motion of the AAOS tables (American
Academy of Orthopaedic Surgeons, "Joint Motion: Method of Measuring and
Recording", 1965), from the A pose of the skeleton at rest.

```json
{
  "blueprint": "person",
  "options": {"pose": "stand"},
  "joints": {"elbow_r": 120, "shoulder_r.spread": 80, "index_r": 0, "middle_r": 90}
}
```

### The limbs

A limb (`World.Limb`) is a named chain of bones, and the way to put its
end at a point (inverse kinematics). Its end is the tail of its last
bone. A pose puts the end of a limb at a point with `{:limb, name} =>
%{at: point}`, and an order with `"targets"`.

| Limb | Bones | End | Solver |
|---|---|---|---|
| `arm_l`, `arm_r` | the upper arm, the forearm | The wrist. The elbow goes down and back. | Two bones: exact. |
| `leg_l`, `leg_r` | the thigh, the calf | The ankle. The knee goes to the front. | Two bones: exact. |
| `spine` | `spine_01` to `spine_03` | The base of the neck. | A chain. |
| `thumb_l`, `index_l`, `middle_l`, `ring_l`, `pinky_l` (and `_r`) | the three bones of the finger | The tip of the finger. | A chain. |

Two bones: the hinge bends as much as it must (the law of cosines), the
first bone turns to the point, and the hinge goes to the side of the
pole. A chain: each bone turns in turn, from the end to the root, so
that the end goes to the point (cyclic coordinate descent, 48 times); it
stops a few millimeters from a point that it can reach, and as near as
it can to a point out of its reach. A chain has no limits yet.

```json
{
  "blueprint": "person",
  "targets": {"arm_r": [0.3, 0.4, 1.3], "index_r": [0.32, 0.45, 1.28]}
}
```

The points are in meters, in the axes of the figure (x to the right
side, y to the front, z up, the ground at z = 0). A person in a scene has
the path of its node in front: `traveler/arm_r`.

A straight elbow keeps its small angle out of the plane of the hinge
(about 4 degrees), as a real arm. `spread` and `twist` have the same
meaning on the two sides, so `Pose.mirror/1` makes the pose of the other
side. The directions are in the axes of World of the person at rest (x
to the right side, y to the front, z up).

The levels: near is the full body with the clothes and the hair; mid is
a body of about 1,600 faces with the hair; far is a body of 730 faces.
At mid and far, the faces under clothes have the mean color of the
clothes, and at far the scalp has the color of the hair.

The colors of a person (`hair_color`, `clothes_colors`):

- The texture of a hair is gray, with a mean of 200 (of 255). The
  factor of its material is the color of the hair: the color of the
  order, or the mean color of the texture before it became gray. A color
  lighter than 200 in a channel stays at 200 in that channel.
- At mid and far, an item of the clothes has the color of the order in
  place of its mean color.
- At near, the color of an item is a tint of its texture: the factor is
  the color of the order over the mean color of the texture, at most 1.
  A tint can only make a texture darker.

A pose turns bones around their heads: a map of a bone to a list of
`{axis, degrees}`, with the axes of World when the person stands at
rest (`World.People.Pose`).

## An animal

An animal is a figure from bones (`World.Rig`): the data of the rig in,
a figure out. A bone of a rig has its `name`, its `parent`, its `head`
and its `tail` (points in the axes of the figure at rest), its hinge
`x`, the half sizes of the body around it at its head and at its tail
(`radius`), its `material`, its `group`, and its `skin`.

The skin is one of three:

- A base mesh (`mesh`): the points of a mesh at rest, its faces, and
  the weights of each bone on its points. Each smooth step (Catmull and
  Clark, `World.Subdivision`) makes each face into faces of 4 sides and
  moves each point to a mean of the points near it; the weights go with
  the points, so the weights of a point stay a sum of 1. A point on a
  border stays where it is. The steps are `smooth` at near, one less at
  mid, two less at far (not less than none).
- A smooth skin (`blend`, `World.Blob`). Each bone has a round body: a
  cone with round ends. The bodies of a group (the bones of the back,
  the bones of one leg) join with no blend; the groups join with a
  smooth union of the width `blend`, so a thigh grows out of the hips
  as a muscle does, with no seam. The mesh comes from the field of
  distances on a grid (surface nets), with the step `step` at near,
  longer at mid and far. Each point follows the bones near it, more the
  nearer one. A thin bone (an ear) has `skin: :tube`: a tube of its own.
- With no mesh and no blend, a tube around each bone with a body.

A small sphere (an eye, a nose) can sit on the skin: its center is on a
ray from a point inside, a third of its radius in the skin.

A limb can keep the bone after its end flat on the ground (`flat: true`
in the pose): a paw on the ground in a step.

### Species and body plans

An animal is a species of a body plan (`World.Animals`). The body plan
is code: it gives the bones of World, the joints, the limbs, the ports,
the pose and the gaits. The species is data: a template is one mesh for
a body plan (`priv/animals/templates/NAME.json`), and the species is
only numbers (`World.Animals.Shape`): its shape, the colors of its coat,
its height and its gait. A new species is one small file, and an order
can change the numbers. A species starts from the template with the
nearest body, and its numbers change the rest.

- The templates of four legs are the eleven animals of the Ultimate
  Animated Animal Pack of Quaternius (CC0), on one rig: `shiba_inu`,
  `wolf`, `fox`, `deer`, `horse`, `donkey`, `cow`, `bull`, `alpaca`,
  `husky`, `stag` (the stag has no bones of the ears, and its antlers
  are a mesh on the head with the role `horn`); and the `pig` and the
  `sheep` of the Farm Animals Pack of Quaternius (CC0), from its FBX
  files (`scripts/fbx_gltf.exs` makes a glTF file of the mesh, the
  bones and the skin). The farm rig has no bones of the ears or the
  tail, and its files have no walk: the pig has the clips of the cow,
  the sheep the clips of the deer (`clips`).
- The template of primates, `primate`, is the low-poly mesh of a rhesus
  macaque of BigMaQ (MIT; the mesh came from MPI-IS, see `CREDITS.md`),
  on the bones of a person, with eyes that World adds
  (`scripts/primate_template.exs`, below). Its numbers change it to the
  other primates.

The species is `priv/animals/species/NAME.json`:

| Key of a species | What it is |
|---|---|
| `name`, `about`, `sources` | The name (a to z, 0 to 9 and _), one sentence about the animal, and where its sizes come from. |
| `plan` | `quadruped` (four legs, and a tail when the template has one) or `primate` (two arms with hands, two legs and a tail). |
| `template` | The name of the template. |
| `shape` | The numbers of the shape (below); a number not given is its default (the template as it is). |
| `colors`, `markings` | `colors`: a role to its color (`fur` is the base color of the coat; `marking` the light parts of the template; `eye`, `iris`, `nose`, `muzzle`, `hoof`, `horn`, `mane`). With no color, a role keeps the color of the material of the template. `markings`: a region of the coat to its color; they paint the faces of `fur` and `marking`. The option `coat` of the order is the color of `fur`. |
| `without` | The roles whose faces go (`["horn"]`: the bull with no horns of the file, for horns of World). |
| `height` | In meters: at the withers (the highest point of `spine_01`) for a quadruped; the length of the head and the body (from the top of the head to the lowest point of the pelvis, when it stands) for a primate. The option `size` of the order scales it. |
| `space` | The coefficients of the shape space of the template (below), for a species on a template with a space. The option `space` of the order is over it. |
| `fur` | The length of the fur, in meters: `coat` for all the coat, and a region of the coat to its length (`"face": 0` for a bare face), mixed as the colors of `markings`. The option `size` of the order scales it. With no `fur`, the GLB has no `_FUR`. |
| `gait` | The numbers of the gaits of the body plan that are code: for four legs, `wag` (the time of a wag, s); for a primate, `period` (the time of a step, s), `stride` and `lift` (parts of the length of the animal). |

The keys of a template:

| Key of a template | What it is |
|---|---|
| `mesh`, `bones`, `materials`, `smooth` | The name of the file in `meshes/`; a bone of World to the bone of the mesh, or to a list of bones of the mesh (a bone of the mesh with no bone of World gives its weights to the nearest bone above it: the fingers go to the hand); a material of the mesh to a role (`fur`, `marking`, `skin`, `eye`, `iris`, `nose`, `muzzle`, `hoof`, `horn`, `mane`, `dark`, `white`, `fin`, `beak`, `comb`); the smooth steps of the mesh at near (2 for a mesh of a few hundred faces, 0 for a mesh of thousands). |

| `parents` | A bone of World to its parent, when the rig of the file has another parent: the paw of the Ultimate rig is a target of inverse kinematics, and World puts it under the forearm. |
| `clips` | The template whose clips it takes (its own file has none for a walk). The moves of the pelvis, the heights of the paws and the speeds go to the units of its mesh, by the heights of the two hips (the head of `hind_upper_l`). |
| `muzzle` | The part of the bone of the head, from its head, where the muzzle starts (a primate: the distance to the front, in lengths of the bone of the head). |
| `brow` | A template of an upright head (the primates): the height of the brow over the head of the bone of the head, in lengths of that bone. The muzzle is then the front of the face under the eyes, and the skull over the brow goes down by `cranium`. A longer muzzle moves the front of the face to the front as a block, so the nose and the lips keep their depth. |

 The end of a bone of World is the head of the next bone of the
body plan; else the end of the bone of the file; else the head of a
bone of the file under it that is part of the same bone of World; else
the farthest point of its skin.

The numbers of a shape change the bones at rest and the skin around
them. A bone has a scale along it (its length) and across it (its
girth); each point of the skin moves with the bones that move it, by
its weights, so the skin stays smooth at the joints. Some numbers
change one part: the muzzle, the ears, the tail, the paws. After the
change, the lowest point of the paws is on the ground, and the height
scales the animal. The length of each leg is `leg_length`, then a
little more or less, so that the lowest points of all the paws move up
or down by one height (the mean of their moves): the body does not tilt
when the front legs and the hind legs are not the same length.

| Number | Range | What it changes |
|---|---|---|
| `body_length` | 0.6 to 1.8 | The length of the back. |
| `body_width`, `body_depth` | 0.6 to 1.8 | The width and the depth of the body (of a primate, its collarbones too). |
| `leg_length`, `leg_girth` | 0.5 to 1.6, 0.5 to 1.8 | The legs. |
| `arm_length`, `arm_girth` | 0.5 to 1.8 | The arms and the hands of a primate. |
| `hand_width` | 0.5 to 1.5 | The width of the hands of a primate (the fingers nearer together). |
| `neck_length`, `neck_girth` | 0.4 to 1.8 | The neck. |
| `head_size` | 0.6 to 1.6 | All the head. |
| `muzzle_length`, `muzzle_width` | 0.3 to 1.8, 0.6 to 1.8 | The front of the head, from the eyes to the nose (a primate: the front of the face under the eyes). |
| `cranium` | 0.5 to 1.2 | A primate: the height of the skull over the brow. |
| `beak_length`, `beak_width` | 0.5 to 2.5 | A bird: the length and the width of the beak (the bone `beak`); its depth stays. |
| `ear_size`, `ear_width` | 0.5 to 2.0 | The length and the width of the ears. |
| `ear_droop` | -40 to 120 | Degrees: more turns the ears down and to their sides (0: as the template). |
| `tail_length`, `tail_girth` | 0.1 to 2.0, 0.2 to 3.0 | The tail. |
| `tail_down` | -60 to 150 | Degrees: more turns the tail down (0: as the template). |
| `neck_up` | -45 to 60 | Degrees: more turns the neck and the head up, around the joint of the neck and the body (0: as the template). |
| `head_down` | -45 to 90 | Degrees: more turns the head down, around the joint of the head and the neck (0: as the template). |
| `horns` | 0 to 1.5 | Horns of World, in lengths of the head (0: no horns of World; the horns of a template are part of its mesh). |
| `horn_spread` | 0 to 1 | 0: the horns go up and to the back (the goat); 1: out to the sides and up (the buffalo). |

The coat is a base color and a color for each region, with soft edges
(the colors of the points: `COLOR_0` in the GLB). The regions paint in
this order, a later one over an earlier one: `back`, `belly`, `mane`
(the top of the neck), `legs`, `socks` (the paws, the hands and the
feet, and the low part of the legs), `head`, `face` (the muzzle; the
face of a primate under the brow), `cheeks` (the sides of the head
behind the face; of a primate: from the outer corners of the eyes to
the sides, from the temples down to the jaw), `lids` (the upper lids: over each
eye, in front of it, as wide as the eye, from the faces of the role
`eye`), `ears`, `tail` (all the tail), `tail_tip`.

#### The shape space

A shape space (`priv/animals/spaces/MESH.json`, `World.Animals.Space`)
holds the shape changes of other templates that the numbers do not
give, as SMAL does for animals: a move of each point of the template,
in the axes of the bone that moves the point most (in the units of the
template; `World.Animals.Shape` scales it as that bone, before the turns
of the tail, the neck and the head). The file has the `mean` of the
moves, the principal components (`components`: each with its `sigma`,
its standard deviation, and its `vectors`, a move of each point), and,
for each template that it comes from, its numbers (`shape`) and its
coefficients (`space`). The coefficients `c` of an animal give the moves
`mean + c1 × sigma1 × vectors1 + c2 × sigma2 × vectors2 + ...`; with no
`space`, the template has no move.

Now the template `wolf` has a space, from the eleven templates of four
legs on the rig of the Ultimate pack (the wolf too): 10 components. The
pig and the sheep of the farm pack are not in it: their rig has other
bones in the legs, and the rays meet other parts of the body. The
species `hyena` comes from the space: its numbers, and 0.4 of the
coefficients of the bull for a heavy front. The numbers and the coefficients of
the horse on the wolf make a wolf with the shape of the horse (its
outline, not its hooves or its mane, and the colors of the wolf), and a
part of the way between two sets of numbers and coefficients is an
animal between the two.

`scripts/shape_space.exs` makes a space:

    mix run scripts/shape_space.exs wolf priv/animals/spaces/wolf.json shiba_inu fox deer horse donkey cow bull alpaca husky stag

For each template:

1. Its size: the length of its back (the bones `pelvis` and `spine_01`)
   is the length of the back of the base.
2. Its numbers: the lengths of the legs, the neck, the tail and the ears
   from the lengths of its bones; the girths and the size of the head
   from the root mean square of the distance of the points of each bone
   to its axis; the length of the muzzle from the point of the head
   farthest along its bone; `neck_up`, `head_down` and `tail_down` from
   the angles of the neck, of the line from the head to the tip of the
   nose, and of all the tail. Each number in its range. The base after
   these numbers is the fit.
3. The rest of its shape: for each point of the fit, a ray from the
   nearest point of its bone to the point (in the axes of the bone; for
   the head, y goes from the joint of the neck to the tip of the nose)
   starts at the same place of the same bone of the template (along the
   tail as one chain, for a tail with another number of bones; the head,
   for an ear of a template with no bones of the ears). The move of the
   point is along the ray, to the face that the ray meets nearest to the
   length of the fit (0.4 to 2.5 times it, on the same bone or a bone
   next to it; only the head and the ears for the head). A ray that
   meets no face goes to the point of those faces nearest to its end,
   when that point is nearer than the length of the fit. A point with no
   move then (0.5 % to 5 % of the points) takes the mean of the moves of
   the points next to it.

So a space holds shape, not pose: the moves are in the axes of the
bones, and the angles are numbers.

#### The UVs and the fur

Each template has UV coordinates (`TEXCOORD_0`), from
`World.Animals.UV`, for a texture that repeats (the noise of fur), not
for a painted texture. Each face goes to the bone that moves it most;
each bone has six charts, the sides of a box around it (its axes x and
z, and its two ends), and a face goes to the chart of the axis nearest
to its normal. So no face turns over, and a length on the skin is at
most 1.73 times its length in UV, in one direction. One scale for all
the charts: `uv_size` in the `params` of the parts list is the length of
one unit of UV on the skin, in meters (about 1.3 for the macaque, 3 for
the wolf, 4 for the horse). On the four sides of a bone, +v goes along
the bone: to the back on the body, the neck and the head; away from the
body on the legs, the tail and the ears. So +v is the direction in
which the fur lies. A point on a seam of the UVs is two vertices with
one normal.

`_FUR` (an attribute of the application, a float for each vertex) is
the length of the fur at the point, in meters, from the `fur` of the
species, on the materials `fur`, `marking`, `mane` (the mesh of the
mane and the tail of a horse: the fur is the strands on it) and `dark`
(the dark legs of a fox; its nose is in the region `face`).
`_FUR_DIR` (three floats for each vertex) is the direction in which the
hair lies, at rest, in the axes of glTF: a unit vector along the skin.
On the body, the neck and the head it goes to the back (from the head
to the root of each bone); on the legs, the arms, the ears and the tail
to the end of each bone; the mean of the bones of the point by their
weights, without its part along the normal (the normal, where the bones
point across the skin). The joints turn it as they turn the normal. An
app can draw the fur as shells: copies of the skin, each out along the
normal by a part of `_FUR`, that keep the strands of a noise in UV (a
strand of 1.5 mm is `uv_size / 0.0015` cells for each unit of UV); the
outer shells lean along `_FUR_DIR`. The review page does this with its
switch "Fur" (`&fur=1`).

The species now:

| Species | Plan | The animal | Shape |
|---|---|---|---|
| `street_dog` | quadruped | A street dog of Việt Nam (chó cỏ): about 50 cm at the shoulder, a short tan coat, ears up, a tail that curls up. | The template `shiba_inu`, with a tan coat. |
| `cat` | quadruped | A cat of Việt Nam (mèo ta): about 25 cm at the shoulder, gray with a white chest and white paws. | Numbers on the template `fox`. |
| `wolf` | quadruped | A gray wolf: about 80 cm at the shoulder. | The template `wolf`. |
| `fox` | quadruped | A red fox: about 40 cm at the shoulder. | The template `fox`. |
| `deer` | quadruped | A deer: about 90 cm at the shoulder. | The template `deer`. |
| `goat` | quadruped | A goat of Việt Nam (dê cỏ): about 55 cm at the shoulder, small horns, ears to the sides. | Numbers and horns of World on the template `deer`. |
| `horse` | quadruped | A horse of Việt Nam (ngựa): about 1.35 m at the withers. | The template `horse`. |
| `donkey` | quadruped | A donkey (lừa): about 1.1 m at the withers. | The template `donkey`. |
| `cow` | quadruped | A cow of Việt Nam (bò vàng): about 1.1 m at the withers, yellow-brown. | The template `cow`, with a yellow-brown coat. |
| `water_buffalo` | quadruped | A water buffalo of Việt Nam (trâu): about 1.3 m at the withers, dark gray, wide horns. | Numbers on the template `bull`, with wide horns of World in place of the horns of the file. |
| `pig` | quadruped | A pig of Việt Nam (lợn Móng Cái): about 60 cm at the shoulder, a black head and back, a white belly and white legs. | The template `pig`, with shorter legs and a deeper body. |
| `hyena` | quadruped | A spotted hyena: about 80 cm at the shoulder, a wide head with a blunt muzzle, round ears, a strong neck and forequarters, a short tail, a pale grey-brown coat. | Numbers and the shape space on the template `wolf` (0.4 of the coefficients of the bull). No spots: the coat has no region for spots. |
| `sheep` | quadruped | A Suffolk sheep: about 74 cm at the withers, white wool, a black face and black legs. | The template `sheep`. |
| `alpaca` | quadruped | An alpaca: about 90 cm at the shoulder, a long neck, thick wool. | The template `alpaca`. |
| `husky` | quadruped | A Siberian husky: about 55 cm at the withers, gray and white. | The template `husky`. |
| `red_deer` | quadruped | A red deer stag: about 1.22 m at the shoulder, reddish-brown, large antlers. | The template `stag`. |
| `macaque` | primate | A long-tailed macaque (khỉ đuôi dài, Macaca fascicularis): about 50 cm long without the tail, a tail of about 55 cm, a gray-brown coat with a lighter belly, a bare pink-brown face, pale upper lids, dark hands and feet, on four limbs. | Numbers on the template `primate` (a rhesus macaque): the arms 1.06 times longer (the intermembral index of 93 of this species, 88 for the template), a body 0.9 as wide, thinner limbs (guesses from photos), a tail as long as the body (2.0, the most of the number; the tail of the template is 0.47 of the head and the body). The colors from photos: a golden olive back, gray limbs, a pale belly, pale lids. |
| `rhesus_macaque` | primate | A rhesus macaque (khỉ vàng, Macaca mulatta): about 53 cm long without the tail, a tail of about 22 cm, a brown or gray coat with a more orange back and hips, a bare pink face, on four limbs. | The template `primate` (the mesh is a rhesus macaque of BigMaQ), with a tail 0.9 as long (22 cm of 53 cm); the regions `back` and `legs` for the orange back and hips. |
| `pig_tailed_macaque` | primate | A northern pig-tailed macaque (khỉ đuôi lợn, Macaca leonina): about 55 cm long without the tail, a short thin tail of about 20 cm that curves up, a brown coat with a dark crown and a dark tail, on four limbs. | Numbers on the template `primate`, with a short tail that goes up (`tail_length` 0.78 for 20 cm of 55 cm, `tail_down` -40), arms 1.1 times longer (the intermembral index of 98 of M. nemestrina), a muzzle 1.15 times longer and a lower crown (guesses from photos); the regions `head` and `tail`. |
| `douc` | primate | A red-shanked douc (voọc chà vá chân nâu, Pygathrix nemaeus): about 62 cm long without the tail, a white tail as long as the body, a silver-gray coat, black thighs, red lower legs, a yellow-brown face, on four limbs. | Numbers on the template `primate`, with arms 1.15 and legs 1.08 (the intermembral index of 94), a flat face (the muzzle 0.55) and a narrower body (guesses from photos), a tail as long as the body (2.0, the most of the number); the regions `legs`, `socks`, `face` and `tail`. The socks also color the hands: the hands are red, not black, and the white forearms are not there. |
| `chicken` | bird | A hen of Việt Nam (gà ta): about 45 cm high at the top of the comb, red-brown feathers, a dark tail, a small red comb and wattles, yellow legs. | The template `bird`. |
| `duck` | bird | A white domestic duck (vịt, a Pekin duck): about 50 cm high, creamy white feathers, a long wide yellow-orange bill, short yellow-orange legs. | The template `bird` with no comb (`without`), a beak 1.7 times longer and 2 times wider, shorter legs, a longer neck, a larger head. The body is more level than the 40º of a Pekin duck, the feet have no webs, and the eyes are a little large. |
| `carp` | fish | A common carp (cá chép, Cyprinus carpio): about 50 cm long, a robust body, a long dorsal fin, a forked tail fin, dark gold with a darker back and a pale belly, bronze fins. | The template `fish`, a little slimmer (`body_depth` 0.9). No barbels. |
| `tilapia` | fish | A Nile tilapia (cá rô phi, Oreochromis niloticus): about 30 cm long, a deep body, gray with a darker back and a pale belly. | The template `fish`, deeper (`body_depth` 1.4). The tail fin of the template is forked, the tail fin of a tilapia is not; no bands. |
| `gibbon` | primate | A northern white-cheeked gibbon (vượn đen má trắng, Nomascus leucogenys), a male: about 55 cm long, no tail, black with white cheeks, very long arms. On the ground it walks on two legs with its arms up (`"upright": true` in its gait). | Numbers on the template `primate`: the arms 1.3 and the legs 0.88, so the arms are 1.3 times the legs (0.88 on the template); a slim body, a round head and a flat face (the muzzle 0.45, guesses from photos), a black face and white `cheeks`. The template has a tail: the gibbon has the shortest, thin. |

The numbers of the presets are a guess from the sizes in their
`sources` and from photos, not measurements of the shape.

A quadruped (`World.Animals.Quadruped`):

- Joints: the hinges `elbow_l`, `wrist_l`, `knee_l`, `hock_l` (and
  `_r`): the value adds to the rest; more bends the elbow and the knee,
  and swings the paw to the front at the wrist and at the hock. The
  balls `shoulder_l`, `hip_l` (and `_r`), `neck`, `spine`, and `tail`
  (`flex` lifts the tail, `spread` wags it to the right side).
- Limbs: `front_l`, `front_r` (two bones, the end is the wrist),
  `hind_l`, `hind_r` (the end is the hock): the elbow goes to the
  back, the knee to the front. `tail` and `head` are chains.
- Ports: `ground`, `collar` (on the neck), `back` (on the spine, for a
  bag), `mouth` (on the muzzle, for a stick).
- Animations: `walk`, `run` (a gallop), `idle`, `idle_low` (at rest
  with the head low), `eat` (the head down to the ground), `attack` (a
  bite, or a butt with the head for an animal with hooves), `kick` (the
  hind legs kick to the back: only an animal with hooves, the files of
  the dogs have no kick), `jump` (a jump in a gallop), `jump_stop` (a
  jump up, and a stop), `hit_l` and `hit_r` (a hit on the left side:
  the body moves to the right; and on the right side) and `death` (the
  animal falls on its side and stays there) are the clips of the
  template, on the bones of the shape (below); `wag` (the tail wags
  twice) is code. A species has a clip only when the clips of its
  template have it (`World.Animals.animations/1`). The clips are in place:
  an app moves the animal at the speed of the clip (`walk_speed`,
  `run_speed` and `jump_speed` in the `params` of the parts list, in
  m/s), so the paws do not slide. The death, the kick and the jump to a
  stop play once; the other clips loop.

The clips of a template are in `priv/animals/clips/NAME.json` (from
`scripts/gltf_clips.exs`, below): for each clip its `length` and
`times` (s), the turn of each bone of World at each time (a quaternion
in the axes of World, from the pose at rest), the move of the pelvis
(in the units of the mesh), the `speed` (in the units of the mesh for
each second), `loop` (true when the last time is the first), `ground`
(`feet` or `body`, below) and `feet`: for each foot, the height of its
paw in the file over its height at rest at each time (in the units of
the mesh; the paw is the IK bone of the file, the place that the artist
gave to the paw), or, with `"feet_from": "ground"`, over the ground (the
clips of the primates: at rest a primate stands with its hands up). An
animal that plays a clip has the source and the license of the clips in
its sources. On an animal (`World.Animals.retarget/5`), each bone turns
from its rest by the turn of the clip, the pelvis moves by the move of
the clip times the scale of the animal, and the other bones keep their
place on their parent: the bones keep the lengths of the shape. The
legs of a shape are not the legs of the file, so the feet go into the
ground or above it. In the death (`"ground": "body"`), the animal falls:
all the animal goes up or down so that the lowest point of its skin is
on the ground at each time. In the other clips (`"ground": "feet"`),
the paws carry the animal:

1. A foot is on the ground at the times when its paw in the file is
   less than 1% of the height of the pelvis above its rest.
2. The body goes down by the mean height of the feet on the ground over
   their paws (the lowest point of the skin of a foot, over that point
   at rest). At a time with no foot on the ground (in a gallop), this
   move changes linearly in time (in a clip that does not loop, the
   first and the last moves stay at the ends). When a leg on the ground is too short
   for its place, the body goes down more, until the leg is straight.
3. Each foot goes to the height of its paw (at the scale of the
   animal, never below the ground): the upper and the lower bone of the
   leg turn (two-bone inverse kinematics, with the knee in the plane of
   its bend), and the foot keeps its turn.

A primate (`World.Animals.Primate`): its bones have the names of the
bones of a person (`pelvis`, `spine_01` to `spine_03`, `neck_01`,
`head`, `clavicle_l`, `upperarm_l`, `lowerarm_l`, `hand_l`, `thigh_l`,
`calf_l`, `foot_l`, `ball_l`, the fingers `thumb_01_l` to
`pinky_03_l` and `_r`, and the tail `tail_01` ...), so the hips, the
feet, the reach of an arm, the shapes of a hand (`"grip"`) and the look
of a person (`World.People.Skeleton`) work on it.

- Joints: the hinges `elbow_l`, `wrist_l`, `knee_l`, `ankle_l` (and
  `_r`), the balls `shoulder_l`, `hip_l` (and `_r`), `neck`, `spine`
  and `tail`.
- Limbs: `arm_l`, `arm_r` (the end is the wrist, the elbow goes to the
  back), `leg_l`, `leg_r` (the end is the ankle, the knee goes to the
  front), `tail` and `head` (chains).
- Ports: `ground`, `grip_l`, `grip_r` (in the hands), `back` (a bag).
- The pose: on four limbs, as in photos of a macaque that walks. The
  hips go down to 0.88 of the length of the legs (the knees a little
  bent) and turn to the front, so the shoulders are at 0.93 of the
  length of the arms (the arms near straight); the ankles stay under
  the hips, the wrists go to the ground under the shoulders, the hands
  lie flat with the fingers to the front (`lay` of a limb,
  `World.People.Skeleton`), the neck goes up so the head is in line
  with the back, the face looks to the front, and the tail goes up
  from its root and then down in a curve. A species with
  `"upright": true` in its gait (the gibbon) stands on two legs, with
  the arms up and out and the hands open.
- Animations: `walk` (on four limbs: the clip of a real rhesus macaque
  of BigMaQ, `priv/animals/clips/primate.json`, a cycle of 0.65 s, the
  hands and the feet in the order of a primate: hind left, front right,
  hind right, front left; the speed is in `walk_speed` of the parts
  list) and `sit` (on the seat,
  the back bent to the front, the feet near the seat, the knees up and
  out, the hands together in front of the feet, the tail on the
  ground; the head turns to look around, in 4 s), `climb` (up a
  vertical trunk in front of the animal: the body upright, a hand and
  the other foot move together, the hands grip, in one step), `hang`
  (from a branch over the head by the two hands that grip, the body
  swings and the head turns, in 3 s) and `jump` (a crouch, a flight of
  0.5 of the length of the legs up with all the limbs off the ground,
  and a landing, in 1.4 s, in place). With `"upright": true` (the gibbon),
  a species takes no clip of its template, and `walk` is on the two
  legs, with the arms up. The climb, the hang and the jump
  are in place: the parts list has no speed for them.

A fish (`World.Animals.Fish`): its bones, from the front to the back,
are `head`, `spine_01`, `pelvis` (the root, the middle of the body),
`tail_01` to `tail_03` (the back of the body and the stalk of the tail)
and `tail_04` (the tail fin). The size of a fish (its `height`) is its
length, from the snout to the end of the tail fin; its belly is on the
ground.

- Joints: the balls `spine` and `tail`.
- Limbs: `body` (a chain from the pelvis to the head) and `tail` (a
  chain from `tail_01` to the tail fin).
- Ports: `ground`, `mouth`.
- Animations: `swim` (a wave goes along the body to the tail, larger at
  the back; each bone turns to the side an eighth of the period after
  the bone in front of it; the speed is in `swim_speed` of the parts
  list, from `period` and `stride` of the gait) and `idle` (smaller and
  slower waves of the tail, in place).

A bird (`World.Animals.Bird`): its bones are `pelvis` (the root, the
back of the body), `spine_01` (the breast), `neck_01`, `head`, `beak`,
`tail_01`, and for each side the wing (`upperarm_l`, `lowerarm_l`,
`hand_l`: folded along the body, to the back) and the leg (`thigh_l` in
the body, `calf_l`: the drumstick, `foot_l`: the bare shank, `ball_l`:
the toes). The size of a bird (its `height`) is the height of its
highest point (the top of the head, or of the comb).

- Joints: the balls `neck`, `tail`, `shoulder_l`, `shoulder_r` (spread
  opens the wing), `hip_l`, `hip_r`, and the hinges `hock_l`, `hock_r`
  (between the drumstick and the shank).
- Limbs: `leg_l`, `leg_r` (the drumstick and the shank: the end is the
  root of the toes, the hock goes to the back), `head` (a chain).
- Ports: `ground`, `beak` (at the tip of the beak), `back`.
- Animations: `walk` (the feet in turn, each on the ground for 0.6 of
  the step; the head stays and then goes to the front, as a chicken
  walks; the speed is in `walk_speed`), `idle` (the head turns to look,
  in short jerks, in 3 s), `peck` (the neck goes down to the ground
  twice, the body leans a little) and `flap` (the wings open, beat three
  times and fold, in 1.2 s). In each, the feet stay on the ground.

A new species: write `priv/animals/species/NAME.json` with the
template of the nearest body, the numbers of its shape, its colors,
its height, from the sizes of the animal and from photos.
Build it (`mix world.build`), and look at it next to photos, at rest
and in each animation, and with its fur (`scripts/shot.mjs` with
`FUR=1`). Add a model to the catalog (`World.Catalog`)
and a test. An order can do the same with no file: the options `shape`,
`markings` and `space` over a species.

A new template of four legs: find a model with bones and a skin, with a
license that lets World give it again (CC0, CC-BY), and add a row to
`CREDITS.md`. Make its mesh with `scripts/gltf_figure.exs` (below), and
write `priv/animals/templates/NAME.json`: a bone of World to the bones
of the mesh, the materials and their roles. Look at the bones and the
materials of the mesh in its JSON.

A new body plan (a snake, a bird that flies) is a module with the
functions of `World.Animals.Quadruped`: `bones/0`, `next/1`, `hinge/2`,
`height/2`, `animations/0`, `limbs/1`, `joints/1`, `ports/1`, `stance/2`
(the pose at rest, from the skeleton and the gait),
`speeds/2` and `animation/4` (and `feet/0` for a plan with clips), and
its name in `World.Animals`.

### A base mesh from a file

The data of a mesh is JSON: the points of the mesh at rest (in the axes
of World, the ground at z = 0), its faces, its materials (`name`,
`color`) and the material of each face, its bones (`name`, `parent`,
`head`, and `tail` when the file has it), the weights of each bone (a
list of `[point, weight]`), its `source` and its `license`. A bone with
no weights and no bone with weights under it (a target of inverse
kinematics of the file) stays out.

`scripts/gltf_figure.exs` reads a glTF file with one mesh and one skin
(the buffers in the file or next to it) and writes this JSON:

    mix run scripts/gltf_figure.exs IN.gltf OUT.json "SOURCE" "LICENSE" [FRONT]

FRONT is `z` by default (the front of glTF); up is `+y`. A bone is at
the inverse of its inverse bind matrix. The same point in two
primitives is one point. A material has the base color of the file.
The templates of four legs come from the glTF files of the Ultimate
Animated Animal Pack with this script.

`scripts/gltf_clips.exs` makes the clips of a template from the
animations of its glTF file:

    mix run scripts/gltf_clips.exs IN.gltf TEMPLATE.json OUT.json "SOURCE" "LICENSE" [FRONT]

It reads the clips `Walk` (`walk`), `Gallop` (`run`), `Idle` (`idle`),
`Idle_2_HeadLow` or `Idle_Headlow` (`idle_low`), `Eating` (`eat`),
`Attack` or `Attack_Headbutt` (`attack`), `Attack_Kick` (`kick`),
`Gallop_Jump` (`jump`), `Jump_ToIdle` or `Jump_toIdle` (`jump_stop`),
`Idle_HitReact1` and `Idle_HitReact2` (`hit_l`, `hit_r`) and `Death`
(`death`); a clip of more than 2 s keeps every second key.
The turn of a bone of World is the mean turn of the bones of the file
that give it their weights (each by its weights, from the mesh of the
template); a bone with no weights has the turn of its own bone of the
file. The paw of a foot is the IK bone of the file in its list of bones
(`IKFrontLeg.L`, `IKBackLeg.L`, ...), or its first bone. The speed (of
the walk, the run and the jump) is the middle value of the speeds to the
back of the paws on the ground (less than 2% of the height of the
pelvis above their height at rest). In the walk of the file the hind
paws move faster than the front paws, so no speed stops all the paws:
the middle value is between the two.

`scripts/bigmaq_clips.exs` makes the clips of the template of primates
from the pose reconstructions of BigMaQ (real rhesus macaques, CC BY
4.0, https://zenodo.org/records/20663410):

    mix run scripts/bigmaq_clips.exs reconstructions.zip macaque_LOWPOLY.json priv/animals/clips/primate.json

- The files of the poses are files of PyTorch (a pickle and the data of
  its tensors). A small reader takes only the tensors and the
  dictionaries, and stops at any other thing: a pickle can run code.
- The poses: at 40 frames each second, the turn of 27 bones of the file
  (each after the turn of its parent, as SMPL), and the turn and the
  move of all the body, in meters. The room has z up; the clip turns
  around z so the animal walks to y.
- The turn of a bone of World: the turn of its bone of the file, from
  the pose at rest of the template (`scripts/primate_template.exs`
  writes the turn of each bone from the file to the rest, in `file` of
  the mesh). The pelvis has its move from its place at rest, with the
  move to the front at the speed of the clip taken away.
- BigMaQ does not turn the fingers and the toes: they go on along the
  hand and the foot, down to the ground. All the fingers of a hand (the
  toes of a foot) turn at their roots so the middle finger (the toes)
  is level.
- A clip that loops: its last pose goes to its first, linearly over the
  clip. The feet: the height of the root of the middle finger or toe
  over its ground (the height under which it is for 0.3 of the clip: a
  paw is on the ground for more than half of a step, and rolls on it);
  the clip has `"feet_from": "ground"`.
- The walk: action 458, individual G, frames 157 to 183 (0.65 s): the
  cleanest straight step of a walk in the file (all four paws on the
  ground for 0.58 to 0.77 of the step, 0.39 m/s for a macaque of
  0.67 m).

`scripts/primate_template.exs` makes the mesh of the template of
primates from the low-poly template mesh of BigMaQ (a rhesus macaque,
`pose_reconstruction/data/Mesh/macaque_LOWPOLY.json` of
https://github.com/martinivis/BigMaQ, commit a92d2d0):

    mix run scripts/primate_template.exs macaque_LOWPOLY.json priv/animals/meshes/primate.json

- The axes: the file has y up and z to the front; World has z up, y to
  the front, and the left side at -x.
- The bones: the 115 bones of the file go to the bones of
  `World.Animals.Primate` (the bones of a person: `Hips` to `pelvis`,
  `Spine1` and `Spine2` to `spine_02`, `LeftArm` to `upperarm_l`, the
  first three bones of each finger to `thumb_01_l` ...). A bone of the
  file with no bone of World (the eyes, the nose, the last bone of a
  finger, the toes, the last bone of the tail, which has almost no
  weights) gives its weights to the bone of World above it.
- The pose at rest: the file is on four limbs, and the body plan needs a
  body that stands as a person. The pelvis turns the body up by 90º, the
  legs and the arms turn back down by 90º, the neck turns to the front
  by 20º and the head by 40º (the face looks to the front: in the file
  it looks 30º down), and each hand turns down along the arm with the
  palm to the body, as the hands of a person.
- The points at rest: each point is where the skin of World (linear
  blend skinning) must start, so that the same turns back give the
  point of the file (the inverse of the blend of the turns of its
  bones). So the animal on four limbs has the shape of the file, with
  no thin joints.
- The eyes (the material `eye`): the lids of the file are closed. A
  sphere at the center of each eye of the file, 1.1 times the distance
  to the nearest point of the skin, moves to the front until it goes out
  of the skin by 0.35 of its radius.
- The size: the head and the body 0.5 m long, on the ground.

`scripts/fish_template.exs` makes the mesh of the template of fish
from the bones of World, with no file from outside:

    mix run scripts/fish_template.exs priv/animals/meshes/fish.json

The fish is 1 m long, with the body of a carp: a smooth skin
(`World.Blob`) around the chain of bones, all in one group (no bumps
at the joints), the deepest part 0.27 of the length. The fins are plates
4 mm thick: a dorsal fin (high at its front, then long and low), a
forked tail fin, an anal fin, and a pair of pectoral and of pelvic fins;
each point of a fin follows the two bones nearest to it along the body.
The eyes are spheres on the bone `head`. The materials: `body` (the
role `fur`, with the colors of the coat), `fins` (the role `fin`) and
`eye`.

`scripts/bird_template.exs` makes the mesh of the template of birds
from the bones of World, with no file from outside:

    mix run scripts/bird_template.exs priv/animals/meshes/bird.json

The bird has the body of a hen, about 0.45 m high at the top of the
comb. The smooth skin (`World.Blob`) has groups: the body, the neck and
the head, the tail, each wing (flat bodies on the sides of the body),
each leg (the thigh in the body, the drumstick), with a blend of 2 cm
between them; the shanks are a skin of their own. The beak is a wedge,
wider than deep, to a blunt tip, on the bone `beak`; the comb and the
wattles are plates on the head; the tail is a fan of feathers, up and
to the back; the toes are three to the front and one to the back. The
materials: `feathers` (the role `fur`), `legs` (`skin`), `beak`,
`comb` and `eye`.

## A drawing

A drawing is a model in the data of an order (the blueprint `drawing`,
`World.Drawing`): for a thing that has no blueprint of its own. It has
the same parts as a model in code: parts with shapes and ports, an
assembly of nodes with their joints, items of other blueprints, and the
clips of its joints. `priv/drawings/banh_mi_cart.json` is an example (in
the catalog: `banh_mi_cart`).

| Key | What it is |
|---|---|
| `name`, `kind`, `sources` | The name of the model (a to z, 0 to 9 and _), its kind (`appliance`, `building`, `electrical`, `furniture`, `item`, `prop`, `vehicle`; `item` by default), and where its data comes from. |
| `materials` | A role of the palette to its `color`, `roughness` and `metalness` in this model. A drawing makes no new role. |
| `parts` | A name to a part: its `shapes`, its `ports` (a name to `at`, `axis`, `up`), its `sources`. |
| `nodes` | The tree of the model, the root first. |
| `clips` | The animations of the joints. |

A shape has one of these keys, with its `material` (a role of the
palette, `gray` by default) and its frame: `at` (its origin), `axis`
(its z), `up` (its y).

| Shape | Its data |
|---|---|
| `box` | `from` and `to`: two corners. |
| `cylinder` | `radius`, and `length` along z from 0. |
| `sphere` | `radius`. |
| `prism` | `loop` (points `[x, y]`) and `length` along z from 0. |
| `lathe` | `profile` (points `[r, z]`): it turns around z. |
| `tube` | `line` (points `[x, y, z]`) and `radius`. |

A node has a `name` and holds a part (`part`) or an item of another
blueprint (`item`: an order with only `blueprint` and `options`: a model
of the catalog, a person, an animal, a drawing). Each node but the root
connects its port `port` to the port `at` of the node `to`, which comes
before it. A port is the name of a port of the part or of the item (a
person has `grip_r` and the others: a node can be in a hand), or a port
in the data (`at`, `axis`, `up`); the origin by default. A node can have
a `turn` (degrees) and an `offset` (meters), and be a `joint`: `kind`
(`hinge` or `slide`), `role` (`crank`, `door`, `drawer`, `handle`,
`knob`, `lid`, `pedal`, `recline`, `slide`, `spin`, `stand`, `steer`,
`suspension`, `vane`, `wheel`) and `limits`.

A clip has a `name`, a `length` in seconds and `keys`: each a time `t`
and the values of some `joints` of the drawing. Between two keys a value
goes in a line; a hinge turns at most 179 degrees between two keys (the
shortest turn). The times of the keys go up.

```json
{
  "blueprint": "drawing",
  "options": {
    "drawing": {
      "name": "lamp",
      "parts": {
        "base": {
          "shapes": [{"cylinder": {"radius": 0.08, "length": 0.02}, "material": "metal"},
                     {"tube": {"line": [[0, 0, 0], [0, 0, 0.4]], "radius": 0.008}, "material": "metal"}],
          "ports": {"top": {"at": [0, 0, 0.4], "axis": [1, 0, 0]}}
        },
        "shade": {
          "shapes": [{"lathe": {"profile": [[0.03, 0], [0.1, -0.12], [0.098, -0.12], [0.028, 0]]}, "material": "white"}],
          "ports": {"pin": {"at": [0, 0, 0], "axis": [1, 0, 0]}}
        }
      },
      "nodes": [
        {"name": "base", "part": "base"},
        {"name": "shade", "part": "shade", "to": "base", "at": "top", "port": "pin",
         "joint": {"kind": "hinge", "role": "knob", "limits": [-45, 45]}}
      ],
      "clips": [{"name": "nod", "length": 2, "keys": [{"t": 0, "joints": {"shade": -30}}, {"t": 1, "joints": {"shade": 30}}, {"t": 2, "joints": {"shade": -30}}]}]
    }
  }
}
```

The check gives each error with its path
(`options.drawing.nodes.2.at`: "is not a port of the part"). The limits
keep a drawing small for the builder at the edge: 64 parts, 256 shapes
in all, 128 nodes, 64 points in a list, 8 clips of 64 keys, points
within 50 m, and 3 drawings one in the other.

## The files of a model

The build (`mix world.build`) writes:

| File | Content |
|---|---|
| `priv/models/NAME.glb` | the near level |
| `priv/models/NAME.mid.glb` | the mid level |
| `priv/models/NAME.far.glb` | the far level |
| `priv/models/NAME.parts.json` | the list of the parts |
| `priv/models/NAME.stl` | the print (step 9) |
| `priv/models/NAME.vox` | the voxel version, when the model asks for one (step 8) |

The build gives the same bytes for the same model.
`mix world.build --check` builds again and compares; CI runs it.

## GLB

- **The axes.** glTF has +Y up and the front of a model to +Z, with the
  right hand. The writer takes a point (x, y, z) of World to
  (-x, z, y) of glTF. This is a turn, not a mirror, so the order of the
  corners of each triangle stays.
- **The nodes.** The root node has the name of the model. Each joint is a
  node, a child of the node of its parent joint, with the point of its
  port as its translation. Its parts have points relative to that point.
  `extras` of a joint node gives `role`, `axis`, `kind` and `limits`.
  An engine turns or moves the node along `extras.axis`.
- **The meshes.** One mesh for each node, with one primitive for each
  material. The writer takes only the visible faces of a Wings mesh: the
  core of Wings closes an open shape with hidden faces (holes). A flat
  face (a hard edge) has the normal of its face; a smooth part has the
  normal of each vertex.
- **The materials.** One glTF material for each role, with the values of
  the palette. Its name is its role.
- **`extras` of the root.** `name`, `kind`, `size` (the box), `sources`,
  `level` (`near`, `mid` or `far`).
- **The check.** The Khronos glTF validator checks each file in CI: no
  error and no warning.

## The list of the parts

`NAME.parts.json` lists each part once, with its count, its kind, its
params and its sources, in a fixed order:

```json
{
  "name": "honda_vision_110",
  "parts": [
    {"name": "bolt_m10x180", "kind": "bolt", "count": 1, "params": {"thread": "M10", "length": 0.18}, "sources": ["ISO 4014"]},
    {"name": "tire_80_90_14", "kind": "tire", "count": 1, "params": {"code": "80/90-14"}, "sources": ["ETRTO"]}
  ]
}
```

## Wings files

- A shaped part is one `.wings` file. Each object of the file is a shape
  of the part. The name of each material is its role.
- `World.Wings.read/1` is strict: a file from a person is data, never
  code. It decodes the term with `binary_to_term(Bin, [:safe])`, after it
  loads the names that a valid file can have (the atoms of Wings and of
  `wpc_world`). It refuses a file with any other name, a file larger
  than its limit, and a term that is not a Wings file.
- `World.Wings.write/2` writes a part as a `.wings` file that Wings 3D
  opens.
- Before a mesh goes into the core of Wings, `World.Mesh.clean/1`:
  - merges the points at the same place,
  - removes the faces with no area,
  - gives the faces of each connected piece the same order of corners,
  - splits a point where two fans of faces meet at that point only,
  - splits an edge that has more than two faces.

  The core of Wings cannot hold the last two: without the clean-up, a
  mesh becomes many small objects.

## Voxel models

A voxel model is a grid of blocks, for Tre. It is a separate kind of
model, because the winged-edge mesh of Wings cannot hold two blocks that
touch only at an edge or a corner.

- The file is MagicaVoxel `.vox`: a grid of up to 256 blocks on each
  side, and a palette of 255 colors. [Goxel](https://goxel.xyz/) (free,
  open source) and MagicaVoxel open it.
- A voxel model gives a material role to each color of its palette, in
  `NAME.vox.json`. Tre maps each role to a color of its own palette.
- **The voxel maker** (`World.Voxel.from_model/2`) makes the voxel
  version of a model at a size of a block. A block is full when its
  center is in a closed part, or when a thin part (a sheet, a leaf)
  goes through it. The block takes the role of the part that fills the
  most of it.
- **The stamp of Tre** (in Tre, step 8) writes a `.vox` model into the
  fine grid of Tre at a place and a turn of 90°.
