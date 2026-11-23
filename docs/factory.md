# The factory

World is a factory for 3D models. A project sends an order, and the
factory builds the model from its parts and gives the files. The
projects (Phượt, DIY, Vũng Tàu) are on Cloudflare, so the factory is a
web service: <https://world.mkfifo.com>. A model has a URL. When World
corrects a part, each model that uses the part changes at the same URL,
and the projects do not deploy again.

A person or an agent of another project starts with `docs/requests.md`:
how to write a request, check it and build it.

## The words

| Word | What it is |
|---|---|
| **Warehouse** | The parts that World keeps: the standard parts (bolts, nuts, extrusions, strut channel, lumber, bricks, wheels and tires), the shapes (a box, a cylinder, a lathe, a loft, a sweep, a prism), and the materials (the roles of `priv/palette.json`). |
| **Blueprint** | A family of models with options: `van`, `person`, `house`, `power_station`. Each option has a name, a type, a default, a unit and a range or a list. The data of a blueprint (the sizes of each make, the traces of a body) is in `priv/data`, not in the code. |
| **Order** | A JSON document: a blueprint and its options, or a drawing, and the parts to fit into its slots. |
| **Drawing** | The design of a model that World has no blueprint for: its parts (shapes, standard parts, orders of blueprints, supplied parts) and its nodes (the JSON form of `World.Assembly`). |
| **Supplied part** | A mesh that the order gives (GLB, OBJ or `.wings`), with its ports. |
| **Slot** | A port of a blueprint where another order fits: the engine bay of a van, its roof, the seat of a scooter for a rider. |
| **Receipt** | What the factory gives with the files: the full order with each default, the version of World, the sources of each part, where each part comes from (blueprint, drawing, supplied), and the hash of the order. |

## The four kinds of work

| A real factory | World | When |
|---|---|---|
| Products of the catalog | An order of a blueprint | The common models, with sources and tests. |
| Build to print | An order with a drawing | A model that World has no blueprint for. No pull request is necessary. |
| Parts of the customer | Supplied parts in a drawing | A shape that the warehouse cannot make. |
| The engineering department | A pull request to World | A drawing that many orders use becomes a blueprint, with its sources and tests. |

An order is data, never code. World runs no code from an order.

## The URLs

| URL | What |
|---|---|
| `/` | The world page: the map of the yard (its places and their states, each construction on a lot at its place, the trucks on their drives), the people of the node, each construction with its elements as they come, and a form that orders a build (`review/world.html`, below, "The constructions"). |
| `/review.html` | The review page: each model of the catalog, its levels, its joints and its parts. |
| `/replay.html?order=HASH` | The replay of an order: what each person does, and the model that grows when each task ends (`docs/world.md`). |
| `/models/list.json` | The names of the models of the catalog. |
| `/models/NAME.glb`, `NAME.mid.glb`, `NAME.far.glb` | A model of the catalog at each level. |
| `/models/NAME.parts.json` | The list of its parts. |
| `/palette.json` | The default color of each material role. |
| `/version.json` | The commit of World that the site has. |
| `/blueprints` | Each blueprint with its options: the type, the default, the unit, the range or the values. |
| `POST /blueprints` | A blueprint in data of a project (`docs/skills.md`): 201 with its `hash` (an order gives `{"blueprint": {"hash": HASH}}`), or 422 with the errors, each with its path. |
| `POST /orders` | An order in JSON. The answer gives its hash, the full order (with each default), the URLs of its files, and the URL of its replay page; or 422 with the errors. It also gives, with no build, `warnings` (each edit of a sculpture that is thinner than two cells of a level, with its path, its level and a message: it can go or tear there; the order is still good) and `faces` (the estimate of the faces of each sculpture at each level, by the name of its node, as `tile.faces` of the parts list). |
| `POST /orders/HASH/edits` | Small changes to an order of `POST /orders`, in JSON: `{"edits": [...]}` ("An edit of an order"). The answer is as the answer of `POST /orders` for the new order, with `parent` (the hash of the order before) and `history` (each order from the first one to this one, with the edits that made it); 422 with the errors (the path `edits.N` for an edit that is not possible, else the paths of the check of the new order); 404 for a hash that the store does not have. |
| `/o/HASH.glb`, `.mid.glb`, `.far.glb`, `.parts.json`, `.receipt.json` | The files of an order of `POST /orders`. The people of the node build the GLB at each level (`World.Construction`). For a model of the catalog with no change (the blueprint `catalog` with only `name`, no colors and no pose), the Worker gives the GLB of `priv/models` at each level from the static files of the site, with no build (`handler.js`, `catalogPath`); `mix world.build` checks that each one is the build of its order. |
| `/o/HASH.drawing.json` | The drawing of the model, with the options of the order in it: each part with its shapes or its skill, the nodes, the joints. It is the drawing that the edit `free` of an order puts in the order ("An edit of an order"). A model that the code of a rule makes as a mesh (a plant, a person, an animal) is the one node `model` of its drawing: an item of its blueprint. |
| `/o/HASH.flat.glb`, `.mid.flat.glb`, `.far.flat.glb` | The model at a level with the flat look (`World.Flat`, plan 0019), for a project that draws many small things with no image: one node with one mesh, each face with its own three points, its normal and one color at each point (`COLOR_0`), a white material, no image, no skin. The points are at their places in the axes of the model. A drawing from edits is built with the look `flat` (the color of a face is the color of its edits); another model has the color of each of its roles. The colors have no alpha, and the mesh has no `_FINISH` (plan 0020, R8). With `?triangles=N` (12 to 200,000), the mesh has at most N faces, or as few as the collapse can make. With `?wrap=1`, the mesh is one closed skin round the whole model (a cast of the model in a grid of 48 cells along its longest side, `World.Cast`), with the color of the nearest face of the model: for a model of many thin parts in a small budget. A part that is thinner than a cell is not in the skin. |
| `/o/HASH.light.glb`, `.mid.light.glb`, `.far.light.glb` | The model at a level with the light look (`World.Flat`, `roles: true`), for a project that gives each role its own material: one node with one mesh, a primitive for each role of the model, flat faces, the material of each role with its color (the mean of the colors at the points of a role that has them: a sculpture, the clothes of a person at mid and far) and no image, no skin. It takes `?triangles=N` and `?wrap=1` as the flat look: a budget keeps the border of two roles. A scooter at the far level: 4,120 triangles, and 500 with `?triangles=500&wrap=1` (50 KB, 15 KB in gzip, in 1.7 s). A coconut palm at the far level: 308 triangles, and 204 with `?triangles=204`. |
| `/o/HASH.solids.json` | The simple solids of the model (`World.Solids`, plan 0019), for a project that draws boxes or SVG and cannot draw a GLB. For a drawing from edits: each edit with its copies as one solid (its `shape` and `size` as in the data of an edit, its place `at` and its axes `x`, `y`, `z` in the axes of the model, its `mode`, its `color` and its `role`), in the parts of the drawing, with no build (milliseconds). For another model: one box for each node and each material. The lengths are in meters, z is up, and the front is to +y. |
| `/o/HASH.log.json`, `/o/HASH.replay.glb` | The log of the construction that built the near level (`World.Log`: one line for the clock, then one line for each event), and the model with each part in a node of its own, with the id of its task (extras `task`), for the replay. The replay of a drawing has its temporary nodes too, each with the task that puts it up and the task that takes it down (extras `from`, `to`; plan 0006, D9): the scaffold and the forms of each band, each band in rough concrete. |
| `/o/HASH.elements.json`, `.mid.elements.json`, `.far.elements.json` | The parts list of the model at a level (below, "The parts of a model"): each part with its key, its URL, its node, its place and its roles, and the joints, the ports and the collision boxes of the model. The factory does not join the parts: a project puts them together. |
| `/p/KEY.glb` | A part by its key: the same key is the same file, for ever (`cache-control: immutable`). From R2 with no VM, else the edge builds it from its recipe and keeps it, for each caller, when it fits the edge: a part of a sculpture whose estimate of memory (`memory` of its recipe, `World.Skills.Sculpt.memory/3`) is at most 20 MB (`World.Labour.edge_memory/0`: in practice a sculpture with no maps and few faces) and whose estimate of faces (`tile.faces` of the parts list) is at most 150,000 (`World.Labour.edge_faces/0`, `World.Labour.fits?/1`). A person of a group goes to a shift at each level. A part whose build at the edge ended the VM (its mark `parts/KEY.edge` and no GLB) does not fit from then on. A construction shift builds a part of a project that does not fit ("Construction shifts"): a project (a request with its token) that asks for all the parts of a list at one time gets them built at the same time. A large part that takes more than 45 s gives 202 with `retry-after`: ask again. A part of a public order that does not fit the edge gives 422, and its message tells the caller to ask for the whole file of the order, or to ask from a job of GitHub Actions of a repository of my account. |
| `GET /bucket/list`, `GET /bucket/object?key=KEY`, `POST /bucket/quarantine?key=KEY` | The check of the bucket after the fault of the listeners (below, "The check of the bucket"): only the job of `bucket-check.yml` on `main`, else 403. |
| `POST /builds` | A build that anyone can watch: an order with a `level` and a `budget` (below, "The constructions"). With `accept: text/event-stream`, the answer is the stream of its events; else 202 with its id and the URL of its events; or 422 with the errors. The caller that opens the construction gets its control key: `control` in the JSON, or the first event `control` of the stream (below, "The control key"). |
| `/builds/ID` | The state of a build from its events: `building`, `done`, `stopped` or `failed`, its level, its tasks and its elements. |
| `/builds/ID/events` | The events of one build as a stream (`text/event-stream`), from `Last-Event-ID` or `?after=N`. |
| `POST /builds/ID/pause`, `/resume`, `/cancel` | A pause (the people end the tasks in hand, and no task starts), a resume, or a cancel (the event `stopped` with the reason `cancelled`): 202, or 404. With the control key of the build or `WORLD_TOKEN`, else 403. |
| `POST /builds/ID/change` | In a pause, a new order of the same blueprint in data (the same nodes): each node whose data is the same stays made, and the people make the others again at the resume (the event `changed`, with `redo` and `keep`). 200, 409 when the build is not in a pause or has other nodes, 422, or 404. With the control key of the build or `WORLD_TOKEN`, else 403. |
| `/builds/ID/elements/KEY.glb` | The GLB of one element of a build, while the build goes on and for 5 minutes after its end. |
| `/events` | The events of the whole node as a stream: each construction, each hire, each element. |
| `/census` | The people of the node by trade, free and busy, and the constructions that wait for a person. And the crews (`crews`): the workers of the node, the nodes that share their workers, and the count of the sites with a stream of tasks now (`World.Crew`). And the memory of the VM (`memory`, `World.memory_report/2`): the size of its memory of WebAssembly and the part that it uses, the processes, the binaries, the tables of ETS, the persistent terms, and the biggest processes and tables. `node scripts/memory-record.mjs BASE SECONDS MINUTES OUT.csv` records it. |
| `/sculptures/ID/events` | The stream of a live sculpture (`text/event-stream`, `World.Sculpt.Web`): a `piece` for each brick of its surface now (its brick and the mesh of each material), its `state`, then each `piece`, `gone`, `done` or `failed` after each change, and `closed` at its end. With `?until=V`, the stream ends after the `done` of the version `V`. |
| `/sculptures/ID.glb` | The GLB of the surface of a live sculpture now. |
| `/places` | The places of the yard (`World.Places`): each with its kind, its point, the kinds of the models that it makes, and its building; a place with a terrain has its lots (the game point, the height of the ground, the point on the yard, the turn) and the path of its ground; the speed limit of the yard. |
| `/places/NAME/ground.glb` | The ground of a place with a terrain (`World.Places.ground/1`): the mesh of the height tiles of the Vũng Tàu game in the box of the place, flat on each lot, in the frame of World from the point of the place at the height of the sea. |
| `/m/BLUEPRINT.glb?OPTION=VALUE` (and the other files) | An order in the URL: `color.ROLE=%23rrggbb` gives a color, `joint.NAME=50` a joint, `target.LIMB=X,Y,Z` the end of a limb, `A,B` a list, and `OPTION.FIELD=VALUE` a field of an object (`origin.asian=1`: give each field, because a field that is not in the URL has its default). |
| `POST /sets` | A set of orders in JSON (`World.Orders.Set`): a list of orders (`"orders"`), or one order with `"count"` (1 to 64), `"seed"` and `"vary"` (an option to a list of its values). Each variant has the options of the order, a value of each list, and its own `seed` (`seed * 1000 + i`). The answer gives the hash of the set and each variant: its hash, its full order, the URLs of its files and its `lot` (`width` and `depth`), so a game makes a library from the set and picks a variant by the size of a lot (W19); or 422 with the errors (the path of each starts with `variants.N` or `orders.N`). |
| `POST /earth/heights` | The heights of the real Earth (`World.Earth`, plan 0019): the body is `{"points": [[latitude, longitude], ...]}` in degrees (at most 200,000 points, and 1 MB), and the answer is `{"heights": [...], "unit": "m", "source": ...}`: one whole number of meters for each point, over the level of the sea (less than 0 under it). The data is ETOPO1 of NOAA at a quarter of a degree. For the planet of a game: the game sends the middle of each cell of its grid. |
| `POST /mcp` | The MCP server: the same orders, as the tools of the Model Context Protocol (below, "The MCP server"). |
| `/v/VERSION/...` | A copy that never changes, for a release of a game (later). |

An order:

```json
{
  "blueprint": "catalog",
  "options": {"name": "ford_transit_148_camper"},
  "colors": {"paint": "#1d3b5a"},
  "joints": {"hood": 50}
}
```

An error tells the path of the wrong value and the rule:
`{"errors": [{"path": "options.length", "message": "must be from 0.05 to 6.1 m"}]}`.

The blueprints now: `catalog` (each model of the catalog, with colors
and joints), `drawing`, `person`, `traveler`, `exercise`, `animal`, `plant`, `house`,
`lot_house` (a whole house on a lot of Vũng Tàu, `docs/format.md`, "A
house on a lot"), `van`, `extrusion`, `strut` and `l_track`.

The joints of a person are in the order too: `"joints": {"elbow_r":
120, "shoulder_r.spread": 80}` for a person, `"traveler/elbow_r"` for
the person of a traveler. `docs/format.md`, "The joints of a person in
an order", has the names and the limits.

The ends of the limbs are in the order too: `"targets": {"arm_r": [0.3,
0.4, 1.3]}` puts the wrist at that point (`docs/format.md`, "The
limbs"). In a URL: `target.arm_r=0.3,0.4,1.3`. An order with no target
has no key `"targets"`, so its hash stays the same as before. The
receipt lists the limbs of the model.

A `traveler` is a traveler of Phượt: a person (the options of `person`,
with the colors of the hair and of the clothes, and `head`, the size of
the head: 1 is the size of the body, up to 2 for the bigger head of a
game) and a vehicle of Phượt (`vehicle`: `car`, `camper`, `motorcycle`,
`motorbike`, `bicycle`, `foot`), in a `scene`:

- `ride` (the position of the traveler on a map): the person on the
  vehicle, in the pose of the vehicle. On two wheels the rider has a
  helmet (`helmet_color`, else a light gray). In the car and the van, the
  person sits in the seat of the driver (the left side), and the glass is
  clear. The driver of the van shows in the window of the door at the near
  level only: at mid and far, the window is a panel on the body.
- `parked` (the avatar of the traveler): the person stands next to the
  parked vehicle, on its right side, and looks to the right (+x). The
  person has no helmet. The model has two animations to play once (2.6
  s each): `wave` (the right hand waves to the viewer) and `point` (an excited
  point: the left arm goes up to the front of the vehicle, +y, with one
  finger out, and jabs three times; the body leans there and the head
  looks there).

The camper is a van of the line: the option `van` (a model of the
blueprint `van`; `transit_148` by default, the Ford Transit of DIY with
the items in its engine bay). The other vehicles do not use it. The
driver sits in the seat of that van: the hips 0.18 m in front of the
mount of the seat (at the front of its track) and 0.55 m over the floor
of the cab, so the head is in the window of the door. Parked, the person
stands 0.52 m from the right side of the van. These sizes are by eye,
from the renders of the Transit.

A person on a moving vehicle is always in a safe pose: the eyes on the
road, the hands on the bars or on the wheel. The vehicle goes to the
front: seen from its right side, it goes to the right of the screen. At
the far level the file is about 300 KB.

A `drawing` is a model in the data of the order: its parts from
shapes, its nodes with their joints, the items of other blueprints (a
person, an animal, a model of the catalog), and the clips of its joints
(`docs/format.md`, "A drawing"). An app or another project can order a
thing that World has no blueprint for, and get the same files: the GLB
with its joints and clips, the list of the parts, the log. Each error
has its path.

A `plant` is a plant of the nursery, from the rules of its species:
`species` (`coconut`, `areca`, `banana`, `bamboo`, `frangipani`,
`araucaria`), `height` (m;
the common height of the species by default), `seed` (the small changes
from plant to plant), `month` (the flowers of a frangipani) and
`numbers`: the numbers of the plant over the numbers of its species
(`priv/plants/species.json`), each from a quarter to four times the
number of the species. A palm has `trunk` (its width, m), `base`,
`lean` (degrees), `fronds` (their count), `frond` (its length),
`leaflet`, `nuts`, `nut` and, for an areca palm, `crownshaft`. So a
project asks for the palm that it wants, and corrects a number after it
looks at the model.

An `araucaria` is the Norfolk Island pine (Araucaria heterophylla,
bách tán): a straight trunk to the top, and level tiers of branches in
whorls on it. Each branch has two rows of branchlets with small leaves.
The low branches are level, the high ones point up, and the crown is a
narrow cone. Its numbers: `trunk` (its width at the chest, m), `clear`
(the height of the lowest tier, m), `tiers` (their count, from `clear`
to the top), `whorl` (the branches in a tier), `crown` (the width of the
crown at the lowest tier, m) and `branchlet` (the length of a branchlet,
m). The numbers do not change with the `height`: give them for the tree
that you want. At near each branchlet is a thin tube of leaves; at mid
the branchlets of a branch are one card; at far half the tiers have a
card of each branch. A tree of 18 m has about 48,000 triangles at near,
3,200 at mid and 1,100 at far.

## An edit of an order

World does not have a rule for each fault that a project can find in a
model. A project asks for a model, looks at the files, and says what to
change: `POST /orders/HASH/edits` (or the MCP tool `edit_order`) with a
list of edits. World makes them on the full order (each option with its
default), in their order, checks the new order as each order, and keeps
it with its history. The new order has its own hash and its own files;
the order before stays.

| Edit | What it does |
|---|---|
| `{"set": PATH, "to": VALUE}` | The value at the path. In an object, a new key is possible. In a list, the index of the count of its items adds the value at the end. |
| `{"remove": PATH}` | No key of an object, or no item of a list, at the path. |
| `{"insert": PATH, "value": VALUE}` | A new item of a list before the item at the path. |
| `{"free": true}` | The order becomes an order of its drawing (the blueprint `drawing`), with its colors and its joints: the model is the same, and each shape that its rule drew is then in the order. The edits after it change any of them: a number that is fixed in the code of the rule. A model that the code of a rule makes as a mesh (a plant, a person, an animal, a van) becomes the node `model` of the drawing: edits add parts to it (a part from edits at a port of the model), and change the options of its item (`options.drawing.nodes.model.item.options.age`); its joints get the name of the node before them (`model/elbow_r`). The options of the rule are not options of the new order. |

A path is as the path of an error of a check: the keys from the order
down, with a point between them. An item of a list is its index (from
0), or its name when the items have names.

```text
POST /orders/3c3b21e548bad02796afb318900d876d/edits
{"edits": [
  {"set": "options.numbers.fronds", "to": 32},
  {"set": "options.numbers.lean", "to": 7},
  {"remove": "options.numbers.trunk"},
  {"set": "colors.leaf", "to": "#5c9440"}]}
```

For a model from edits (the blueprint `drawing`), each shape of each
part is in the order, so an edit can change a size
(`options.drawing.nodes.chum_than.skill.sculpt.edits.0.size`), add a
shape (`insert`), take one away (`remove`) or paint a part of the
model. An edit that the rules refuse gives the errors of the check with
their paths, and changes nothing.

An `animal` is an animal of a species, from its bones: `species`
(`street_dog`, `cat`, `wolf`, `fox`, `deer`, `goat`, `pig`, `horse`,
`donkey`, `cow`, `water_buffalo`, `buffalo_calf`, `sheep`, `alpaca`, `husky`,
`red_deer`, `hyena`, `macaque`, `rhesus_macaque`,
`pig_tailed_macaque`, `douc`, `gibbon`, `carp`, `tilapia`, `chicken`,
`duck`), `coat` (a
color; the color of the species by default), `size` (0.6 to 1.4: a
scale of the animal), `shape` (numbers of the
shape over the numbers of the species, as `{"leg_length": 1.2,
"ear_droop": 30}`), `markings` (a region of the
coat to its color, as `{"socks": "#ffffff"}`), `space` (the
coefficients of the shape space of the template, for the `wolf`: the
space lists the numbers and the coefficients of the horse, the cow, the
deer and more, so a wolf with the `shape` and the `space` of the horse
has the shape of a horse; `docs/format.md`, "The shape space") and `animations` (the
animations of its body plan: `walk`, `run`, `idle`, `idle_low`, `eat`,
`attack`, `kick` (only the animals with hooves), `jump`, `jump_stop`,
`hit_l`, `hit_r`, `death` and `wag` for four legs, `walk` (on four
limbs, or on two legs for the gibbon), `sit`, `climb`, `hang` and
`jump` for the primates, `swim` and `idle` for the fish, `walk`, `idle`, `peck` and `flap`
for the birds; the walk, the run and the jump are in
place, and the parts list gives their speeds, `walk_speed`, `run_speed`,
`jump_speed` and `swim_speed`, in m/s). Its joints and the ends of its limbs
are in the order too (`"joints": {"tail.spread": 20}`, `"targets":
{"front_r": [0.07, 0.3, 0.15]}`). A species is data of a body plan
(`docs/format.md`, "An animal"): an app can order a four-legged animal
that World has no species for, with numbers only.

An `exercise` is a group at a morning of exercise, as on the beach of
Vũng Tàu: `routine` (`tai_chi`, `yoga` or `aerobics`), `count` (1 to 12
people, 6 by default) and `seed`. A leader at the origin faces the group
(+y) and does the routine as in a mirror; the people stand in rows of
three in front of the leader and face the leader (-y). Each person is
different (the age of the routine: 55 to 75 for tai chi, 25 to 50 for
yoga, 35 to 65 for aerobics; the body, the hair, the clothes and the
color of the shirt), from the seed, and starts the routine up to 0.35 s
late. The routine is one animation of the model, in a loop (16 s, 24 s
and 8 s). A person (`person`) can also have a routine as its animation:
an app can place each person and start the loop at its own time. A group
of 7 people is about 1.5 MB at the far level and 4.8 MB at the mid level. With
`fans` (true), each person holds an open tai chi fan in the right hand,
and the leader in the left hand.

A `person` can hold a prop in each hand (`right_hand`, `left_hand`:
`fan`, `bottle`, `bucket`, `trowel` or `hammer`) and wear a hat (`hat`:
`non_la` or `hard_hat`), with up to 8 animations (the walk, the
routines, the work of a site). The props follow
the hands in the pose and in the animations, and they are in the list of
the parts.
At the edge, a group of more than 3 people needs more memory than the
VM has (`AGENTS.md`, "Known problems"): order each person, or build
the group with `mix world.order`.

An order of a van:

```json
{
  "blueprint": "van",
  "options": {
    "model": "transit_148_medium",
    "windows": "passenger",
    "engine_bay": ["dc_charger"],
    "roof": [{"kind": "solar", "at": 3.8}, {"kind": "fan", "at": 5.2}],
    "size": {"height": 2.6}
  },
  "colors": {"paint": "#1d3b5a"}
}
```

The windows of a van are a list, or the name of a preset: `cargo` (no
window behind the cab, the default), `crew` (the window of the second
row at the left, the window of the sliding door and those of the rear
doors), `passenger` (the windows all around). Each window of a list has
its place (`at`: `left` or `right` in a side of the body, `slider` in
the sliding door, `rear_doors` in the rear doors; one window at a
place) and its numbers (`from` and `to` behind the front axle, `bottom`
and `top` over the ground, in meters); a number that the window does not
give is that of the model. The doors have numbers too (`doors`: `front`
`back` and `top`, `sliding` `from`, `to` and `top`, `rear` `height`),
and `rows` is the count of the rows of seats behind the front seats (by
default from the preset). A crew van with a longer window at the left
and a wider sliding door:

```json
{
  "blueprint": "van",
  "options": {
    "model": "transit_148",
    "windows": [{"at": "left", "to": 3.5}, {"at": "slider"}, {"at": "rear_doors"}],
    "doors": {"sliding": {"to": 2.9}},
    "rows": 1
  }
}
```

In the world, the openings factory makes each door and each window to
its numbers, and its truck brings them to the line of the van
(`docs/world.md`, "The factories").

The sizes of a van (`size`: `length`, `width`, `height`, in meters) are
those of the US market by default: the sizes that the maker gives for
the US. An order for another market gives its sizes (the Sprinter of
Mercedes-Benz Australia: `"height": 2.331` with a standard roof, 2.62
with a high roof). The height goes up 0.3 m and down to the height of
the traces of the roof; the length and the width go 0.05 m each way.
The check of a van refuses a size, a door or a window out of the limits
of the model (a door stays in the body, a window in its side or its
door), two windows at one place, and more rows of seats than the body
has room for; it puts each item of the roof on the flat part of the
roof, and two items do not touch.

Each file has `Access-Control-Allow-Origin: *`, an `ETag`, and
`Cache-Control: public, max-age=300, stale-while-revalidate=86400`. So a
project gets a correction at most 5 minutes after the deploy of World,
and it can use a copy in its cache while it gets the new file.

## The MCP server

`/mcp` is a server of the [Model Context
Protocol](https://modelcontextprotocol.io) (MCP), so an MCP client of
another project can find the blueprints and order a model. The
transport is Streamable HTTP with no state: each `POST` is one JSON-RPC
message, and the answer is one JSON message. There is no event stream
and no session (`GET` and `DELETE` give 405), and no sign-in, as for
`POST /orders`. The server knows the versions `2025-11-25`,
`2025-06-18`, `2025-03-26` and `2024-11-05` of the protocol.

| Tool | What it does |
|---|---|
| `list_blueprints` | The name and the description of each blueprint. |
| `get_blueprint` | The options of one blueprint (`name`), as `GET /blueprints` gives them. |
| `check_order` | Checks an `order` and does not keep it: the hash and the full order, with the `warnings` and the `faces` of its sculptures (as `POST /orders`), or the errors. `check_drawing` gives them too. |
| `edit_order` | Makes the `edits` on the order of a `hash` and keeps the new order, as `POST /orders/HASH/edits`. |
| `place_order` | Checks an `order` and keeps it, as `POST /orders`: the hash, the full order, the URLs of its files and of its replay page, or the errors. |
| `check_drawing`, `propose_drawing` | For an engineer: the review of a new `drawing`, and a proposal for me. |
| `request_tool` | A project asks for a tool that World does not have (`docs/requests.md`, "When a tool is missing"): its `project`, what the `tool` does in general, the smallest `order` or `drawing` that needs it, and the `gap` (the error or the result). The factory checks the example and keeps the request (`requests/HASH.json`): its hash and the check. |
| `plan_build` | The plan of the people for an `order` at a `level`, with no build: each task with its trade and its waits, the tasks of each trade, and the estimate of the triangles. |
| `build` | Keeps an `order` and starts its construction in its `budget`, as `POST /builds`: the id of the build, the URL of the stream of its events, and the URLs of its files. |
| `open_sculpture` | Opens a live sculpture from its `edits` (the skill `sculpt`, `docs/format.md`, "A sculpture") at a `level`, with a `name` or the hash of its edits: its id, its version, and the URLs of its stream and of its GLB. The node has at most 8 at one time. |
| `edit_sculpture` | Changes the `edit` at an `index` of a live sculpture (null takes it away; the count of the edits adds one at the end): its new version. The stream gives the new pieces. |
| `close_sculpture` | Stops a live sculpture. |

The result of a tool has the data as JSON text and as structured
content. A wrong order is a result with `isError` and the errors, each
with its path and its rule, so that the client can correct the order
and try again. A store of the orders that fails is a result with
`isError` too. The factory builds each file at its first `GET`, as for
`POST /orders`.

To add the server to an MCP client, give it the URL
`https://world.mkfifo.com/mcp` with the transport "HTTP" (or
"Streamable HTTP"). For example, in a JSON file of servers:

```json
{"mcpServers": {"world": {"type": "http", "url": "https://world.mkfifo.com/mcp"}}}
```

The server is `World.MCP` in the VM, at `POST /mcp` of `World.Service`.
The Worker sends each request of `/mcp` to the VM with no change, and
gives it the start of the URLs (the header `x-world-origin`).

## The kit of a person

A viewer that changes a person often (the profile page of Phượt) asks
for no build: it joins the parts of the kit of a person, which are
static files at `/kit/` (`World.People.Kit`, in `priv/kit`; `mix
world.build` writes them with the catalog, and CI checks them). The
kit is the parked traveler of the blueprint `traveler` at mid:

| File | What it has |
|---|---|
| `kit.json` | The names of the other files (`vehicles`: the file of each vehicle, and of each van of the camper), the clothes, the credits of the clothes of the MakeHuman community (`credits`: the `author` and the `license` of each item; an app that shows an item with the license CC-BY names its author), the targets of each short name of the shape (`shapes`: the targets `decr` under 0.5 and `incr` over 0.5; a viewer computes their weights with no copy of the table), the layer of each item of the clothes (`layers`: 0 next to the skin to 3 a jacket; a face of the body takes the color of the outer item, then of the item that covers the most of it), the shape that an item gives to the body (`wear`: `[[target, weight]]`, the cups of the bra `world_bra`; a viewer adds these weights when the item is worn), and the place of a parked person (a translation and a rotation in the axes of glTF) next to each vehicle and each van of the camper. |
| `person/woman.glb`, `person/man.glb` | The body of each sex: all its faces in one primitive (the material `skin`), the eyes, the eyebrows, the mouth closed behind, the skeleton in the pose "stand", and the animations "wave", "point" and "blink". The shape targets of the body are morph targets (`World.People.Human.kit/3`). |
| `person/SEX-hair-NAME.glb` | Each hair, with the same skeleton and the same targets. |
| `skins/NAME.jpg`, `eyes/NAME.png` | The textures of the skins and the eyes. |
| `vehicles/NAME.glb`, `vehicles/camper-VAN.glb` | Each vehicle alone, parked: the same file as the URL `/m/traveler.mid.glb?vehicle=NAME&scene=parked&part=vehicle` (with `&van=VAN` for the camper). The cache of the URLs is for each version of World (`urls/COMMIT/...`), so after a new version the first view of a URL is a build of some seconds; the file of the kit is always ready. |

The extras `kit` of the mesh of a body have the data of the viewer:

- `targets`: the morph targets, each a group of targets of MakeHuman
  with the same moves. The weight of a group is the sum of the weights
  of its targets for the numbers of the person (sex, age, weight,
  height, origin, and the options of the shape with a short name: bust,
  firmness, waist, hips, buttocks, stomach, torso, shoulders, arms, legs,
  neck; `World.People.Human.target_weights/1` with the mean muscle). The
  other sliders of MakeHuman (the option `shape`) are only in an order:
  each target makes the body of the kit bigger.
- `bones`: the move of the head of each bone for each target (glTF
  axes). The viewer moves the bones by the weights; a morph target has
  only the rest of the move of a point (the move less the moves of its
  bones), so the mesh follows the bones.
- `ground`: the lowest point under each pair of shoes (and with no
  shoes), and its move for each target. The viewer puts the person down
  by it.
- `covers` and `colors`: the faces of the body that each item of clothes
  covers (as triangles `[first, count, n]`) and the color of the item.
  At mid, the clothes are colors on the body: a triangle has the color
  of the worn item with the most points of the body under it (`n`), as
  `World.People.Human.person/2`.

Joined for the numbers of a person, the kit is the person of World
within 1 mm (the body) and 3 mm (the hair) at rest
(`test/world/kit_test.exs`).

## The line of a van

A van of the blueprint `van` is built as the maker builds it, station
after station (`World.Vehicles.Van`):

| Station | What it adds |
|---|---|
| The body shop | The body of sheets on the hull, 3 cm thick, with the openings cut: the windshield, the front doors, the sliding door, the rear doors, the windows of the body, the arches of the wheels. Inside: the floors, the wells of the wheels, the pillar behind the front door, and the mounting points of the seats (the ports `seat_driver`, `seat_passenger`, `row_2` and more, from the seats of the make in `priv/data/vans.json`). |
| The closures | The hood, the front doors with their windows and mirrors, the sliding door, the rear doors: each in its opening, on its hinges or its rail. |
| The paint | The role `paint` of the body and the doors. |
| The trim | The glass in the openings, the black plastic, the lamps, the grille, the small parts, the dash, and the seats (`World.Furniture.Seats`) on their mounting points: the two front seats on their tracks, with backs that recline, and the benches of the rows of the crew van and the passenger van. |
| The chassis | The engine bay and the wheels. |
| The upfit | The items of DIY on the roof and in the engine bay. |

Each part has its station in its `params` (the list of the parts is
the build sheet). The near level is the van of the line: the doors open
on the inside of the van. The mid level has a closed body with the doors
on it, and the far level the closed body only.

## The contract

The other projects use the names of the options, the slots, the joints,
the ports and the parts. A correction can change a shape, a size or a
color, but not these names. A test keeps a copy of the names of each
model of the catalog and compares them. A change of a name makes a new
version of the blueprint (`van@2`): the old version stays.

## Where the builds run

| Order | Where |
|---|---|
| A model of the catalog | `mix world.build` builds it natively, and the files are in the repository. CI checks at each commit that they are the build of the code. The Worker serves them as static files: no build at a request. |
| An order at a request | The VM of World (beam.com, WebAssembly) in the Durable Object `world` of the Worker builds it (`worker.js`, `handler.js`, `World.Service`): one object is the node, with one census of its people. A large part of a parts list of a project builds in a construction shift ("Construction shifts"). The file goes into R2 with a key of the commit of the deploy and the hash of the order, so the next request reads it from R2, and a new deploy builds it again. |

## The server on a computer

World also runs as one native server, with no Worker: on a computer
with more memory than the edge (plan 0019). `World.Service` has each
route of the table above:

```sh
sh scripts/site.sh                 # the pages, the catalog and the kit, in site/
WORLD_SERVER=true PORT=4000 \
WORLD_SITE=site \
WORLD_FILES=/var/lib/world/files \
WORLD_ORDER_DIR=/var/lib/world/orders \
WORLD_BUILDS=4 \
mix.com run --no-halt
```

A tunnel (for example `cloudflared`) gives the port to
`https://world.mkfifo.com`.

- **The files stay** (`World.Files`, the folder `WORLD_FILES`): a file
  of an order at a level is built one time, with a copy in gzip and an
  ETag. Its key is the hash of the order, the level and the file, not
  the commit of World.
- **After a deploy**, a file from the older code is stale: the server
  gives it at once (the header `x-world-stale`), and builds it again
  one time in the back. So a deploy costs no wait, and a correction of
  a rule is in the file after the next request.
- **The line** (`World.Line`, `WORLD_BUILDS` builds at one time): a
  build that a person waits for goes before a build of a batch
  (`?class=batch`, or the header `x-world-class: batch`: the tool of a
  project that gets all its files).
- **Each answer** has the headers of CORS; a client that takes gzip
  gets gzip.

Measured on four cores (2026-11-15): a van at the mid level, 6.2 s for
the first request and 0.18 s after it; the file is 232 KB, and 75 KB in
gzip. A traveler on a motorbike at the far level: 3.7 s, then 0.2 s.

The VM has the orders: their check, their store and the MCP server
(`World.Service`, `World.Orders.place/2`, `World.MCP`). `POST /orders`
and the tool `place_order` keep the full order in R2 as
`orders/HASH.json`, through a port of the VM (`/env/ORDER_STORE`,
`order_store.js`, `World.Orders.Store`). On this computer and in the
tests, `scripts/order-store.mjs` runs the same code with a folder
(`WORLD_ORDER_DIR`, `tmp/orders` by default).

The Worker (`handler.js`) keeps the files that the VM built
(`builds/COMMIT/HASH.LEVEL.FILE` in R2): a file that R2 has goes out
with no request to the VM, so a cold VM, or a VM that builds a big
order, does not stop it. For a file that R2 does not have, the Worker
asks the VM to build it: `POST /build?hash=HASH` for an order of
`POST /orders` (the VM reads the order from its store), or the order in
the body for `/m/`.

A URL of `/m/` needs the VM for the check of its order (about 2 s at
the edge, also for a file that R2 has). So the Worker keeps the hash of
the order of each URL that the VM checked (`urls/COMMIT/SHA` in R2, SHA:
the SHA-256 of the path and the query of the URL). The next request of
the same URL reads the hash and the file from R2, with no VM. A new
deploy checks each URL again.

The VM at the edge, measured with Node.js 25 and the runtime of
beam.com 0.1.0-rc.6 (the time of one build, and the peak of the memory
of the VM):

| Model | Level | Native | WebAssembly | Peak |
|---|---|---|---|---|
| `redarc_bcdc1250d` | near | 7 ms | 80 ms | 55 MB |
| `ford_transit_148_camper` | far | 86 ms | 234 ms | 68 MB |
| `ford_transit_148_camper` | mid | 133 ms | 332 ms | 92 MB |
| `ford_transit_148_camper` | near | 2.0 s | 3.3 s | 298 MB |
| `house_brick_vn` | mid | 147 ms | 404 ms | 88 MB |
| `house_brick_vn` | near | 4.3 s | 6.7 s | 847 MB |

At the edge (the deploy of 05ec8c6, 2026-10-28; the
time of the first request, with the check and the build):

| Order | Level | Time | File | Result |
|---|---|---|---|---|
| `strut`, 0.5 m | far | 2.2 s (0.3 s from R2) | 11 KB | Built |
| `ford_transit_148_camper` | far | 3.1 s | 169 KB | Built |
| `ford_transit_148_camper` | mid | 2.6 s | 301 KB | Built |
| `ford_transit_148_camper` | near | 5.7 s | 1.1 MB | Built |
| `person` (the defaults) | near | 6.9 s | | The VM stopped (error 1101). The next request started it again (2.8 s). |

The time is not a problem. The memory is: a Worker has 128 MB. The mid
and far levels and the small items fit; the near level of a large model
does not. In `wrangler dev`, the near level of a person (3 MB) took
0.9 s and 124 MB, and a small house took 0.2 s. Step F4 makes the build use less memory. If that is not
sufficient, a builder with more memory (a Cloudflare Container with
the native beam.com) builds the large orders.

F4, part 1 (2026-10-31). The peak of `:erlang.memory(:total)` over the
VM at rest, natively, in one process that builds the GLB of a person
(the data of MakeHuman already loaded; with it not loaded, add about
60 MB):

| Person | Before | After |
|---|---|---|
| The defaults, near | 132 MB | 90 MB |
| With `speech` and `expressions`, near | 431 MB (not loaded) | 131 MB |
| The defaults, mid | 64 MB | 35 MB |

- After a garbage collection only 5 to 17 MB of a build is live. The
  collector keeps the garbage in the old heap until a full sweep, and a
  full sweep copies the live data to a new heap: the peak was some
  times the live data. A full collection after each big step
  (`World.Detail.collect/1`: after each mesh of a person and each
  primitive of the GLB) keeps it low. A full sweep at each collection
  (`fullsweep_after: 0`) is worse: each one copies the whole heap.
- A morph target can be a map of the points that move
  (`World.Scene.Primitive`): a shape of the face moves few of the
  points of the body, and 45 dense targets were 75 MB of tuples.
- The GLB writer puts the points into the binary with no list of them
  in the axes of glTF, and takes their bounds from the binary.

F4, part 2 (2026-10-31). Two causes of the peak of a build, and the
load of the data. The files are the same, byte for byte.

- `World.Build` placed the corners of all the parts of a model before
  it made one primitive for each material, and it kept the triangles of
  each mesh in the dictionary of the process for all the later builds of
  that process (a worker, a foreman). Now it makes one material at a
  time, keeps the triangles of the meshes of that material only, and
  collects the garbage after each primitive.
- The data of MakeHuman: a short process parses each file and puts it
  in `:persistent_term`, so the garbage of the parse and a second copy
  of the data are not in the process of the build.

The peak of `:erlang.memory(:total)` over the VM at rest, natively, for
an order through the world (`World.Orders.build/3`, GLB at near):

| Order | Before | After |
|---|---|---|
| The camper van | +185 MB | +71 MB |
| A parked traveler on the motorbike, first order of the VM | +200 MB | +159 MB |
| A parked traveler on the motorbike, data loaded | +162 MB | +109 MB |
| A person (the defaults), first order of the VM | +159 MB | +115 MB |
| The scene of the motorbike alone (Honda Vision, near) | +82 MB | +33 MB |

The memory of the VM in `wrangler dev` (the host, all of the heap of
WebAssembly), one order alone:

| Order | Before | After |
|---|---|---|
| The camper van, near | 182 MB | 95 MB |
| A parked traveler on the motorbike, near | 230 MB | 172 MB |
| A person (the defaults), near | 149 MB | 157 MB (no change: the person is the next step) |

At the edge (the deploy of 8d59a75, the first request of each order),
the near level now builds: a parked traveler on the motorbike (GLB,
18.0 s), the log of a traveler on the motorbike (13.0 s, a run of
7.3 s), a person with the defaults (GLB, 10.8 s), and a traveler in
the car (GLB, 19.8 s). Before F4, part 2, the log of a traveler stopped
the VM (503).

The heap of the build of a person peaks near 38 MB, and the person (the
item) is 12 MB of terms: lists of tuples of floats for each point. Less
needs a packed format for the meshes (binaries of floats), a larger
change.

F4, part 3 (2026-11-17). At `8fbf36c` the factory gave 503 for the mid
and the near level of a person, and for its receipt and its list of the
parts (they come from the near level); Vũng Tàu found it. The causes:

- A construction that was done kept its plan for its 5 minutes after the
  end, and the plan had the item: a person is 13 MB of terms, and with
  its garbage the process kept 28 MB. Its reply copied the item too.
  Now the plan keeps its tasks with no items when the joiner starts, and
  a full collection runs after that state is in place.
- The targets of the body stayed in memory: 21 MB for those of an
  adult (more than before: the sliders and the breasts), and 13 MB more
  for those of a child, read for each person. Now they are one pack
  (`priv/makehuman/targets.pack`): an index of the names, then each
  target compressed alone, so a person reads only its targets.
- The list of the assets made the cut of all 12 garments of the sewing
  shop (8 MB kept, and its garbage) to find the points that drape. Now
  those points are a file of each garment (`NAME.drape.json`).
- The fit of the clothes wrote each moved point into the tuple of all
  the points (19,000) with `put_elem`: one copy of the tuple for each
  point and each step, about 5,000 copies for the nipples. Now the moved
  points go in with one copy, and the near level makes the body of the
  clothes one time, not one time for each item.
- The faces round each point of the body (4.7 MB) stayed after the
  refinement of the body at mid. Now they go after it.

The linear memory of the VM in `wrangler dev` (it never shrinks: its
peak), each level of a person (the defaults) in a new VM, after
`POST /orders` in its own VM:

| Step | `8d59a75` (built at the edge) | `8fbf36c` (503 at the edge) | Now |
|---|---|---|---|
| `POST /orders` | 40 MB | 148 MB | 84 MB |
| far | 93 MB | 153 MB | 83 MB |
| mid | 98 MB | 153 MB | 89 MB |
| near | 131 MB | 184 MB | 122 MB |

A child of 9 years in the clothes of a village: near 120 MB, its
receipt 122 MB. (`POST /orders` of `8d59a75` did not build the item;
now the check of a true model builds it at far.)

F4, part 4 (2026-11-17). Vũng Tàu found that a person in four items
(`world_t_shirt`, `world_rain_shell`, `mindfront_female_trousers_1`,
`elvs_caesar_sandals1`) stopped the builder at the edge (503), also with
the fixes of part 3. The cause is one asset: the sandals have 91,704
triangles and 47,344 points (the next largest item has 30,768
triangles). Their load alone took 94 MB at the peak, and the data of the
asset (34 MB of terms) stays in `:persistent_term`. The number of items
is not the cause. Now each asset has at most 17,000 triangles
(`World.People.Thin`, `scripts/thin.exs`): the sandals load in 25 MB.

The peak of `:erlang.memory(:total)` over the VM at rest, natively, for
`World.Orders.build/3` (GLB; the data of MakeHuman loaded, not the
sandals):

| Order | Before | After |
|---|---|---|
| The four items, far | +164 MB | +69 MB |
| The four items, mid | +164 MB | +87 MB |
| The four items, near | +453 MB | +167 MB |
| The same with no T-shirt, far | +163 MB | |
| The sandals alone, far | +157 MB | |
| The defaults, far, mid, near | +54, +57, +108 MB | |

Still to do: a packed format for the meshes of a person (the item is
13 MB of terms), and the peak at the end of a build, where the person,
the scene and the buffer of the GLB are all live.

F4, part 5 (2026-11-17): a group of people. The check of the order
`exercise` with `fans` (a build of the group at far) took 272 MB at
the edge, and the VM stopped. Two causes: the group made all its people
in one process, so the garbage of each person stayed to the end; and
the cache of the targets kept each target decoded (1.7 MB of terms each,
47 targets for a group of different people: 79.5 MB). Now each person
of a group is made in a process of its own (`World.Detail.apart/2`),
and the cache keeps the packed targets (107 kB each). The check of an
order builds its model only for the data of a project (a drawing) or
for a pose (`joints`): a rule in code with no pose is checked by the
tests of its rule. The parts list gives each person as a part of its
own (the blueprint gives its `pieces`), made alone at its first
request, at its place in the group. And no order stops the VM now:
`World.Guard` stops a build that goes over `WORLD_MEMORY_MB`, and the
order gets an error (below, "The parts of a model").

The order `exercise` with `fans` (7 people) at the local edge, each
request in a new VM:

| Request | far | mid | near |
|---|---|---|---|
| `POST /orders` | 52 MB (before: 272 MB, the VM stopped) | | |
| The parts list | 53 MB, 10 s | 53 MB, 11 s | 53 MB, 10 s |
| A person | 88 to 99 MB, 8 to 10 s | 99 to 113 MB, 10 to 12 s | 112 to 142 MB, 8 to 9 s |

Two of the seven people at near go over about 128 MB: the memory of
one person at near is still the open fault of F4, part 3.

F4, part 6 (2026-11-17): the people at near, again. At the local edge,
each person in a new VM (the VM is ready at 42 MB):

- The seven people at near: 116 to 145 MB. One person changes by up to
  18 MB from one run to the next (the leader: 128, 142 and 145 MB).
- The make of the figure holds the peak, not its GLB: the leader with
  no GLB takes 136 MB (142 MB with it), and person_5 105 MB (114 MB).
- The live data of the make is the same for each person: at most 28 MB
  on a computer (64-bit words), while it poses the figure, and the
  figure is 13 MB. At the edge the VM grows by 60 to 100 MB for it. So
  most of the growth is not the data: it is the copying collector (an
  old and a new heap at one time) and the gaps between the blocks of
  the C allocator, in a linear memory that never gets smaller. The gaps
  change with the order of the blocks, so the peak changes from one run
  to the next.
- Each of these was worse: the make in a process of its own (145 MB),
  each mesh of the person in a process of its own (+25% on a computer),
  a first heap of 16 or 32 MB for the build (176 and 167 MB), and a full
  sweep at each collection (148 MB).

This fault is still open. The next steps: the size and the used part of the memory of
WebAssembly ("The guard and the memory of WebAssembly") at each step,
to see the gaps; the data of
the people (the base mesh, the targets, the items) in the snapshot of
the VM, so that it is low in the memory before a build; and a packed
form (binaries) of a skinned mesh, so that a figure at near is about 3
MB and not 13 MB.

## The parts of a model

World works as Dreams (W24 to W28 of `TODO.md`, plan 0027 of Vũng
Tàu): World gives the tools, the parts and the labour, and a project
does the construction. The factory does not join the parts of a model
into one model, and it does not keep a whole model in its memory
(`World.Elements`).

- **The parts list** (`/o/HASH.elements.json`, and `.mid.` and `.far.`;
  `mix world.order` writes them too, with the GLB of each part in
  `p/KEY.glb`). Each part has its `key`, its `url`, its `node` (the id
  of its node in the plan), its `part`, its `matrix` (16 numbers by
  columns: its place in the axes of the model, Y up as in glTF), its
  `roles`, its `joint` (the joint that moves it, or null), its `kind`
  (`part`, or `figure` for a person with its props), for a part of a
  large sculpture, its `tile` and, for a part of a copy (plan 0020: a
  node with a `tint`, a `scale` or `share`), its `tint` (`#rrggbb`, or
  null) and its `scale` (the matrix has the scale in it too); a copy has
  the key of its part. The list has the `joints`, `limbs`,
  `ports` and `collision` of the model, and `rates` (the turns in each
  second of each joint of the role `spin` with a `rate`) for a model
  with such a joint. `review/parts.html?list=URL`
  puts the parts together as a project does.
- **The key of a part** is a hash of its data and of the version of its
  rule (`World.Elements.version/1`): the source of the rule and of each
  module of World that it calls, with the data files that they read
  (below, "One key in each folder"). A part that is made (a node of shapes, a
  person, a vehicle) has its content as its data, with its level, its
  maps and the colors of the order: a wall of 1,000 bricks of one shape
  is one file. A part of a sculpture has its data: the edits near it,
  its box, its share of the faces and the other data of the sculpture,
  but not the place of its node and not its tint and its scale (plan
  0020): a copy of a sculpture at another place has its key.
  So an edit of an order changes the keys of the parts that it changes,
  and the factory builds only those (W27). The same keys are in the
  events `element` of `POST /builds` (W28), and the GLB of each element
  goes into the store of the parts.
- **One key in each folder.** The version of a rule is a hash of its
  source, not of its compiled modules (`World.Elements.Source`): the
  file of each module that the rule calls, again and again, each with
  its path from the root of the project and its MD5; the data files of
  `priv` that those modules read; the files of `wings` and their
  `-include`; and the versions of Elixir and Erlang/OTP. There is no
  absolute path in it, and the order of the compile has no effect.
  - A module depends on another when it calls a function of it (in a
    function, or in the body of the module, which runs at the compile),
    uses its struct, or takes it with `require`, `import` or `use`. A
    module that is only a value (an entry of the list of the skills) is
    not a part of the rule. The modules of the service (the orders, the
    store, the line, the gate of the memory, the module `World`) are not
    followed.
  - A key changes when the source or the data of its rule changes, and
    only then: a new drawing of the catalog (`World.Drawing.Catalog`) does
    not change the key of a part of a sculpture, and a new height of the
    van `transit_148` (`priv/data/vans.json`) changes only keys of the van.
  - The hash of the data of a part (`term_to_binary/2` with
    `:deterministic`) writes the keys of a map in order. With no option,
    a map of more than 32 keys (the full order of Hải Âu) can give
    another key at each start of the VM.
  - So a build of one commit gives the same keys in each folder: the
    factory (the folder of Workers Builds), a construction shift, a job
    of CI, and a clone on a computer (`mix world.order`). The job `keys`
    of `ci.yml` checks it at each push: the commit in two folders gives
    the same keys for the parts of five orders
    (`test/fixtures/keys/orders.json`: Hải Âu at mid, a village house,
    the fire truck of `mini` at far, a drawing with two sculptures, and
    a van), and a third folder with another height of the van gives other
    keys for the van and the same keys for the others.
    `scripts/keys.exs` gives the keys of a set of orders.
  - **Each part got a new key one time** with this change (the deploy of
    `main` after pull request #67). A key of a part made before that
    deploy is a key of a build in one folder only. A lock of a project
    must not take such a key: build the parts list again from the
    factory, after that deploy, and lock the keys that it gives.
- **A part fits the memory of the edge** (W26). A sculpture that has
  more than 12,000 faces at its cells (an estimate, `World.Elements.most/0`)
  is cut into parts, each with a budget of 1,500 triangles or more, and
  each part is made in steps of at most 12,000 faces, each step in a
  process of its own. The edge builds such a part, for each caller, when
  the estimate of the memory of its build is 20 MB or less
  (`World.Labour.fits?/1`, "Three orders at one time, with the record");
  a construction shift builds the others.
  The cuts are planes between bricks, where the fewest soft blends of
  the edits cross. Two parts next to each other meet with no gap: the
  points at their border are the same points, and no collapse moves
  them.
- **The guard of the memory.** A build runs in a process of its own,
  and `World.Guard` stops it when the memory of the VM goes over
  `WORLD_MEMORY_MB` (60 MB at the edge since 2026-11-22, "The guard and
  the memory of WebAssembly" and "Three orders at one time, with the
  record"): the order gets an error, and
  the VM and the other orders go on. The check of an order with a large
  sculpture does not build it at far.

### The CPU limit of the edge

A request to a Durable Object has 30 s of CPU time by default, and 5
minutes at most (`limits.cpu_ms`). `wrangler.jsonc` sets 5 minutes. A
part takes about its time of build in CPU time (one VM is one thread),
and `wrangler dev` does not apply the limit, so the times of the local
edge (below, "Hải Âu") tell which parts the edge cannot finish:

- With 30 s (no `limits.cpu_ms`): no part of the main node of Hải Âu at
  any level (far 122 s; mid 111 to 336 s; near up to 221 s), the base at
  mid and near (37 and 44 s), and the parts lists of mid and near (25
  and 67 to 96 s). Only the people of a group (8 to 12 s), the sign at
  far (7 s) and the base at far (21 s) fit.
- With 5 minutes: the edge cannot finish the largest part of the main
  node at mid (336 s), and a part takes about 5 minutes or more at a
  busy core. The rest fits, but each part takes some minutes, one after
  the other in one VM.

So the edge builds only the parts that fit it with room, and a
construction shift builds the others (below). These times are of
`wrangler dev` on a shared core; the times at the edge need a deploy
(the next measure on world.mkfifo.com). Since the change of issue #42 the rule has
the estimate of the faces of a part at its cells (`World.Labour.fits?/1`),
which goes with its CPU time: 150,000 faces or fewer
(`World.Labour.edge_faces/0`; above: 51,264 faces took 20 s, 106,510
faces 37 s, and the parts of 216,190 faces or more 111 s or more).
Since 2026-11-22 it also has the estimate of the memory of the build,
20 MB or less (`World.Labour.edge_memory/0`), because the maps of a
part of few faces can end the VM ("Three orders at one time, with the
record"). A part that the guard of the memory stops, or whose build at
the edge ended the VM, waits for a shift (a project) or gets 422 (a
public request).

### Construction shifts

A construction shift builds the parts that the edge cannot build: a
workflow of this repository (`.github/workflows/shift.yml`) on a runner
of GitHub Actions, for my projects only. It is like the
custom builds of BEAM.com (an issue form, and `workflow_dispatch`). A
shift starts on a request and ends. It is not a server that stays up,
and it does not take the public orders.

**A request** starts a shift, or joins the shift that runs:

- Most requests come through the API of the factory: an order of a
  project (below, "The secrets": how a project proves who it is). A part
  that the edge cannot build (its memory, or its CPU limit) waits in the
  queue of the edge (`World.Labour`). A part of a public order that the
  edge cannot build gets 422.
- An issue of the form "A construction shift" (label `shift`), for a
  request by hand: the project, its orders (one link to its
  `orders.json` at a commit, or the hashes of orders), the levels, and
  the hours. The job `.github/workflows/shift-request.yml` starts at
  once only for an issue of a member; another issue waits until I add
  the label again. The job puts no text of the issue in a
  shell command: the text goes to `scripts/shift-issues.mjs` in the
  environment, and only checked values go on (`scripts/shift-form.mjs`).
  The job gets the parts lists with its ID token, for the project of the
  form, and asks once for each part.

When a shift runs, the edge gives it the new parts at once. When no
shift runs, the edge keeps the parts in its queue and starts a shift:
the VM marks the answer 202 of a part with `x-world-shift: wanted`
(`World.Shift.wanted?/1`), and the Worker starts the workflow
(`shift.js`, `workflow_dispatch` with the commit of the deploy). Only a
request of a project starts a shift (its ID token of GitHub Actions or
`WORLD_TOKEN`): a request with no token gets the same answer, and does
not use the starts of the day. When
the shift has less than 15 minutes left, the edge starts the next shift
for the new parts; it waits for the end of the shift that runs.

**The limits:**

| Limit | Value | Where |
|---|---|---|
| Shifts at one time | 1 (one more waits) | `concurrency` of `shift.yml` |
| The time of a shift | 5.5 hours at most (`timeout-minutes: 330`); the shift stops 15 minutes before | `shift.yml`, `World.Shift` |
| Shifts that the edge starts each day (UTC) | 6 (`WORLD_SHIFTS_A_DAY`) | `shift.js` |
| A second start | not in the 20 minutes after a start (the runner, the cache and the start of the node) | `shift.js` |
| A start that GitHub does not take | no answer, 429 or 5xx (a cause that goes away): GitHub can still start the workflow, so after 5 s the Worker looks at the runs of `shift.yml` (`workflow_dispatch`, since a minute before the start, with the commit in the name). A run is there, or the runs do not answer: the start stays used. No run: the start of the day goes back, and the next start can come after 1 minute. GitHub can make its run some seconds later, so the next start looks at the runs again first: a run is there (or the runs do not answer), and that start is used again, with the wait of 20 minutes from its time; no second shift starts. 401, 403, 404, 422 or another answer (the token, the workflow or its inputs): the start stays used, with the wait of 20 minutes, until I correct the cause | `shift.js` |
| No work | the shift goes home after 60 minutes (a request can set a shorter shift: `hours`, or the input `idle`) | `World.Shift` |
| A part in the queue | 6 hours at most, then an error | `World.Labour` |
| The queue after a start of the VM | kept in the SQLite of the object; a new VM reads it in 10 s at most; a part in work waits 2.5 minutes for its node, then goes back to the queue | `World.Labour.Store`, `World.Labour.Restore` |
| A part that fails | 3 tries on nodes of shifts, then an error | `World.Labour` |
| Parts in work on a node | one for each core of the node (`World.Crew` gives 2 workers for each core), at least one; the parts take the free cores in the order that they came to the queue | `World.Labour` |
| WebSockets on `/.tcp/` | 4 open at most (`BEAM_MAX_WEBSOCKETS`) | `wrangler.jsonc` |

**The node of the shift** joins the node of the edge
(`scripts/shift.sh`):

1. The job asks GitHub for its ID token (`id-token: write`, the audience
   `https://world.mkfifo.com`) and sends it to `POST /shift/join`
   (`scripts/shift-join.mjs`). The Worker checks the token (`oidc.js`,
   "The secrets").
2. The edge (`World.Shift.Passes`) gives the runner a name for its node
   (each runner its own), a cookie of 32 random bytes for that node only
   (`:erlang.set_cookie/2`), the name of the node of the edge, and the
   pass of the shift for the store of the Worker.
3. The runner sets that cookie, dials out through the `tcp-proxy.mjs` of
   beam.com to `wss://world.mkfifo.workers.dev/.tcp/4370` (below, "The
   address of the jobs"), and connects. The
   edge (`DIST_NAME`, `DIST_LISTEN=true`) has a cookie of its own that
   nobody knows: random, made at the start of its distribution. So only
   the node of a join connects, with the cookie of its join.
4. The edge keeps each pass in the SQLite of its Durable Object
   (`World.Shift.Store`, `shift_store.js`). The VM of the edge can start
   again (a deploy, the limit of its memory). The runtime starts each
   new VM from a memory image of the first VM of its deploy, so
   `World.Shift.Passes` reads the store each 10 seconds and takes each
   pass that it does not have, with the cookie of its node. The node of
   a shift that runs connects again (`World.Crew` tries each 3 s); in a
   test, about 10 s after the start of a new VM.
5. A node that goes away (the end of its shift, or a break of its
   connection) keeps its pass and its cookie for 10 minutes. Then the
   edge forgets them.
6. A node with no connection to the edge for 2 minutes stops with the
   exit status 75 (`World.Shift`), and `scripts/shift.sh` joins again:
   a new ID token, name, cookie and pass. The parts in work go back to
   the queue of the edge.

The runner checks out the commit that the edge runs (the crews refuse
other code), with the deps and the build in the cache. The crews compare
a hash of the source (`World.Crew.Source`), not of the compiled modules:
the edge is built in Workers Builds and the shift on a runner, in two
folders, and the code of some modules has the path of the folder of the
build. The edge starts the
distribution after the application, so `World.Crew` watches the nodes
from its start (`:net_kernel.monitor_nodes/2` with `node_type: :all`: a
node that only connects is hidden). The edge gives work and takes none
(`WORLD_LABOUR=parts`): it builds the parts that fit it (`World.Labour.fits?/1`: a part of a sculpture with an estimate of memory of 20 MB or less and of 150,000 faces or fewer), and gives the others to a shift.

**Whole parts, not small jobs.** The edge gives the shift a whole part
by its key (`World.Labour`). The node builds it, puts the GLB in R2
through the store of the Worker (`/store/KEY`, with the pass of its
shift, `scripts/order-store.mjs`), and gives back only the key. The
Worker writes R2 with its binding. It takes a key with a pass only when
the edge gave that part to that shift (the GLB to write; the GLB, the
recipe and the order of the part to read, and the blueprints in data),
else 403. The Worker sends the VM only the SHA-256 of the pass (the
header `x-world-shift-pass-hash` of `/shift/allowed`), and the VM keeps
only that hash: the pass is not in the Workers Logs. No GLB goes over the link. A part in R2 does
not build again, and a node that builds a part already does not build it
a second time when the edge gives it again (a VM of the edge that starts
again asks again). When the store does not take the GLB of a part (the
edge did not answer in time, or a new VM of the edge did not read its
queue yet), the GLB stays on the node, and the node puts it at the next
make of its key, with no new build. A part whose node goes away goes
back to the queue, at its place. An
issue gets its comment (the parts lists and their URLs) when its parts
are built, and closes: the job of the request closes it at once, else
the shift does (`scripts/shift-issues.mjs check`, each 5 minutes and at
its end).

**The queue after a start of the VM.** The edge keeps its queue in the
SQLite of its Durable Object too (`World.Labour.Store`,
`labour_store.js`): each part that waits, with its ticket (its place in
the queue: the time of the clock when it came), and the node of each
part in work. A new VM of the edge (a deploy, the limit of its memory)
reads the store each 10 seconds (`World.Labour.Restore`, as the passes
above), and each part with no process goes back to the queue at its
place, so the order stays: the parts of the first order before the
parts of the second.

- A part in work on a node is in the work of that node again at once,
  so the store of the Worker takes its GLB (`/shift/allowed`). Before
  the new VM reads its store, `/shift/allowed` also takes each part that
  the store of the queue gives to that node: in the first second of a
  new VM, the node of a shift can read its recipes and put its GLBs
  (2026-11-20: 4 makes of a shift ended with "no recipe" in that time).
- When that node connects again, the edge gives it the part again: the
  node waits for the build that runs, or puts the GLB that it kept,
  with no new build.
- When that node does not come back in 2.5 minutes (a node with no
  connection for 2 minutes joins again with a new name), the part goes
  back to the queue at its place.
- A part that R2 has is done, and leaves the store.

**The length of a shift.** A shift stays until its end, and waits for
the next part between parts. It goes home early after 60 minutes with
no work. It stops 15 minutes before the end of the time of its job, and
its parts that are not done go back to the queue of the edge. It writes
a summary in the summary of the job: the parts of each project (their
count, how many are stored, and their time; a part that two projects
asked for counts for each), then each part with its projects, its time,
the peak memory of the VM while it built, and its result, and the
failures and the stops.

**Several projects in one shift.** The parts of all the projects go to
the one shift, in the order of their first request: a part keeps its
place in the queue, whatever project asks for it again. The edge keeps
the projects that asked for each part that waits (`World.Labour.asked/2`,
the header `x-world-project`), with the queue in the SQLite of the
Durable Object, and gives them to the node with the part.
`GET /census` gives the starts of the shifts of the day for all the
projects (`shifts`: the day, the starts, the limit and the time of the
last start).

**SSH into a shift**, as `remote-ssh.yml` of BEAM.com: the input
`ssh_key` of `shift.yml` (one line `ssh-ed25519 ...`) starts the SSH
server of Erlang `:ssh` behind a quick tunnel of Cloudflare
(`scripts/shift-ssh.sh`). The URL and the fingerprint of the host key
are in the log and in the summary of the job. Then, with the private
key: `beam.com -a ssh remote_ssh.erl -- exec wss://HOST/ KEY FINGERPRINT
'tail -n 50 /home/runner/work/_temp/tcp-proxy.log'`.

**A shift on this computer** (a test, with no GitHub):
`wrangler dev` with `--var WORLD_SHIFT_API:http://127.0.0.1:PORT` (a
local server in the place of the API of GitHub, which runs
`scripts/shift.sh` for each start, `scripts/shift-local.mjs`), `--var
WORLD_STORE_TOKEN:TOKEN` (with no ID token, the node joins with it, and
it takes each key of the store of the local Worker), and the two secrets
as `--var`. The site has no `WORLD_STORE_TOKEN`.
`node scripts/edit-time.mjs BASE HASH LEVEL EDITS` (with `WORLD_TOKEN`
and `WORLD_PROJECT`, or in a job of a repository of my account with its
ID token) measures the time from an edit of an order to its
whole new level, as a project gets it: the edit, the parts list, then
all its parts at one time.

#### Hải Âu in a shift at world.mkfifo.com

The measure (2026-11-19, `main` at 456c42c): the edge at
world.mkfifo.com and one shift on a runner of GitHub. I started
the shift by hand (`shift.yml`, 1.5 hours). Its node joined the edge 71
s after the start: the queue of the runner, the checkout, the cache and
the start of the node. The order is Hải Âu at mid (7 parts: the sign,
the base, and the 5 parts of the main node).

Each request is an issue of the form "A construction shift" (a project
with no token), for an order that an edit made before the issue
(`POST /orders/HASH/edits`). Each time of B, C and D is from the issue.
The time of A is from the new label of issue 6, not from the issue: I
opened issue 6 on 2026-11-18, and it got the label `shift` again for
this measure. A script looked at the parts with no token:

| Request | Parts list | Sign and base | Main parts | Whole mid level |
|---|---|---|---|---|
| A: a storey of 4.2 (a new order) | 35.8 s | 65.7 and 117.8 s (built) | 116.8 to 203.1 s | 203.1 s |
| B: one front (`options.fronts.0.bays` to 6) | 37.2 s | 39.6 and 39.8 s (R2) | 75.1 to 185.5 s | 185.5 s |
| C: the height of a storey (`options.storey` to 3.4) | 48.4 s | 54.0 and 54.3 s (R2) | 309.2 to 375.4 s | 375.4 s |
| D: a second order (`options.storey` to 3.6), 20 s after C | 57.9 s | 67.2 and 67.5 s (R2) | 387.1 to 510.2 s | 510.2 s |

- One order in the shift (A, B) takes 185 to 203 s. This is less than
  the target of 5 minutes.
- The issue adds time before the parts list: the workflow "Shift
  request" starts, then it sends the request to the edge (36 to 58 s).
  Each issue started two runs of "Shift request" (the issue opens and
  gets its label), and the second run stopped the first. Since 1398b04,
  the workflow starts on the label only: one run for each issue.
- The issues did not start a second shift: the edge sent the parts of
  B, C and D to the shift that ran.
- An edit keeps the keys of the sign and the base, so they come from R2
  at once. An edit of one front or of a storey changes all 5 parts of
  the main node.
- Two orders at one time (C and D, 10 parts) take more than 5 minutes.
  The main parts of C came first (309 to 375 s), then those of D (387
  to 510 s from D, 407 to 530 s from C). The first main part of C came
  at 309 s, and that of B at 75 s. Thus the parts of C waited for the
  node much longer than one order waits. The cause is not measured
  yet: the summary of the shift gives the time of each part.

What this measure does not show:

- **The start of a shift by the edge on the site.** I started
  the shift by hand before the requests, so each request found a shift
  that ran. The time from a request to the start of the workflow
  (`shift.js`) and to the join of its node is not measured on the site.
- **A request of a project with its ID token.** Each request came
  through an issue (the job of `shift-request.yml`). A job of a project
  that asks for `/p/KEY.glb` with its own ID token is not measured.

Both are measured later: see "The start of a shift by the edge, and a
request with an ID token".

#### Two orders at one time, after the limit of the parts

The summary of the shift of A to D (run 44599229778) shows the cause of
the slow C and D only in part: 27 parts in 48 minutes. The 10 main parts
of C and D took 67 to 263 s each, and each ended later than the one
before (they built at one time on the node). 5 keys built two times, and
the node joined the edge again at 19:43:12, 19:44:20 and 20:02:52.

The corrections: a node builds one part for each of its cores at a time,
first come first served (4ba9ad4), a node does not build a key two times
(f7c2cb3), and a node keeps the GLB that the store did not take (01362aa).
The same measure again, each time with a shift started by hand, and two
new orders 20 s apart (each with 7 new parts: a deploy gives new keys to
all the parts, also the sign and the base):

| Measure | Commit | Parts list | First part | Whole mid level |
|---|---|---|---|---|
| C2: a storey of 3.45 | a9b781f | 39.2 s | 376.2 s | 535.2 s |
| D2: a storey of 3.65, 20 s after C2 | a9b781f | 51.6 s | 342.7 s | not done: 5 main parts did not come in 20 minutes |
| C3: a storey of 3.42 | 01362aa | 39.6 s | 434.5 s | 723.7 s |
| D3: a storey of 3.62, 20 s after C3 | 01362aa | 92.2 s | 348.7 s | 664.7 s |

**These four values do not count.** The deploys of the corrections came
during the shifts, and each deploy starts the Durable Object and its VM
again, about 5 minutes after the deploy. The events `started` of
`/events` and the times of the deploys (the checks "Workers Builds" and
`/version.json`):

| Start of the VM | The deploy before it |
|---|---|
| 21:07:57 | f7c2cb3 at 21:03:03 (4 minutes 54 s before) |
| 21:09:21 | a9b781f at 21:04:50 (4 minutes 31 s before) |
| 21:45:50 | 01362aa at 21:40:51 (4 minutes 59 s before) |
| 21:47:13 | none |
| 00:29:57 (2026-11-20, during the measure of a request with an ID token) | none |

So the VM started again two times during C2 and D2, and one time just
after the start of the shift of C3 and D3. A new VM has no queue and does
not know the parts in work. The store then refuses the GLB of a part in
work, and a part waits until a request asks for it again: the job of an
issue asks one time, and the shift asks each 5 minutes
(`shift-issues.mjs check`). That is the wait of about 5 minutes before
the first part. The rule since then: no deploy of the site from the start
of a shift to its end, while a measure runs (a branch and a pull request,
merged between the measures).

Two starts had no deploy (21:47:13, during the parts list of D3, and
00:29:57). Also with no start of the VM, at 21:53:45 the store refused
the GLBs of 8 parts at one time, and the node joined the edge again at
21:53:50, 21:54:36 and 22:12:50: most likely the VM did not answer the
check of the store (`/shift/allowed`) in time, and the distribution
broke. The logs of the Worker give the cause.

- The summary of the second shift (run 44615136474): 22 parts in 26
  minutes, 8 keys built two times, 2 parts with no recipe at first. The
  store did not take the GLBs of the 5 main parts of D2, so they never
  came.
- The summary of the third shift (run 44621247964): 29 parts in 31
  minutes, 13 makes that the store refused. Each GLB that the store
  refused went to the store at a later make of its key in 1.1 to 3.3 s,
  with no new build.
- The order of the queue held only in one VM: after a start of the VM,
  the parts of D3 came before those of C3. (Now the queue is in the
  SQLite of the object: "The queue after a start of the VM".)
- The time from the start of a shift by hand to the join of its node:
  71 s at 456c42c (the build in the cache), 3 minutes 7 s at a9b781f and
  4 minutes 43 s at 01362aa (a new commit: the node compiles at its
  start).

#### Two orders at one time, with no deploy

The same measure (2026-11-20, `main` at 34118e0), with no deploy from the
start of the shift to its end: a shift started by hand at 01:19:04 (run
44652694952, its node joined at 01:19:58), and two new orders 20 s
apart, each with 7 new parts:

| Measure | Parts list | First part | Whole mid level |
|---|---|---|---|
| C: a storey of 3.38 (issue #24, 01:20:09) | 36.8 s | 71.7 s | 432.8 s |
| D: a storey of 3.58, 20 s after C (issue #25) | 55.3 s | 68.4 s | 398.9 s |

- No event `started` during the measure (the last one before it is at
  00:48:30, a deploy). This does not show that the VM did not start
  again: a VM that starts from its memory image (a reset for the memory
  limit) writes no event `started` ("Two orders at one time, with a
  deploy during the shift").
- The target is not met, and D ended before C. The distribution broke
  with no start of the VM: at 01:22:31 the store refused 4 parts in work
  (the edge lost them when the node went away), and the node lost its
  connection at 01:23:23 and 01:24:30 and joined again at 01:23:28 and
  01:24:38. These breaks come while the edge builds the parts lists of
  the two orders and answers the requests of their 14 parts. Most likely
  each was a reset of the isolate for its memory limit (seen in the logs
  of the Worker in the next measure).
- The summary of the shift: 16 parts in 22 minutes. The 4 parts that
  the store refused went to the store at the next make of their key in
  1.0 to 1.5 s, with no new build (01362aa).

#### Two orders at one time, with a deploy during the shift

The measure of the queue in the SQLite of the object (`World.Labour.Store`,
"The queue after a start of the VM"): as the measure before, with one
deploy during the shift, so that the VM of the edge starts again while
the parts of the two orders wait or are in work.

1. A shift started by hand, at the commit that the edge runs.
2. When the node of the shift joined: the merge of a change of the
   documents only (this text), so the source and the build of the node
   stay the same.
3. About 2 minutes after that deploy is live: two new orders 20 s apart
   (C, then D), each with 7 new parts, by issues of the form. An active
   Durable Object keeps its code until it hibernates, or for 300 s after
   the deploy at most (the deferred code update of Cloudflare, since
   2026-10-30); an object with no work takes the new code at its next
   request. So the new VM starts while the parts of C and D wait or are
   in work.
4. A record of `/events` with the clock of the computer that measures: a
   start of the VM breaks the stream. The logs of the Worker give each
   start (`beam: ready in ...`) and each reset for the memory limit.
5. After: the times of each order, the starts of the VM, the order of
   the parts (the parts of C before the parts of D), and the summary of
   the shift (each part stored, the GLBs that the store refused).

**The first run (2026-11-20, `main` at 4032e09, the deploy of d8da052).**
A shift started by hand at 18:11:36 (run 44790421771, its node joined at
18:12:51); the deploy was live at 18:15:11:

| Measure | Parts list | First part | Whole mid level |
|---|---|---|---|
| C: a storey of 3.36 (issue #29, 18:17:18) | 37.5 s | 192.3 s (the sign, the same part as in D); the first main part 384.9 s | 543.0 s |
| D: a storey of 3.56, 20 s after C (issue #30) | 43.3 s | 95.8 s | 250.3 s |

- The new VM started at 18:18:28.8 (the code update: `beam: ready in 26
  ms`, and the event `started`). The isolate of the old VM ended the
  requests that it had open, and gave "exceeded its memory limit" at
  18:19:00.
- The 7 part requests of the job of C never reached the Worker (the logs
  of the Worker have only its parts list, at 18:18:06.9). The job counted
  them as parts that wait, so C was in no queue: its main parts came only
  at the next check of the shift (18:22:43). This run does not test the
  order of C and D. Now the job asks again for a request that does not
  reach the edge, and writes each answer (`scripts/shift-issues.mjs`).
- The parts of D were in work on the node at the start of the new VM,
  and the new VM took them back: all were stored. In its first 1.5 s,
  before it read its queue, it refused the store reads of the node
  (`/shift/allowed` 403), and 4 makes ended with "no recipe". Now
  `/shift/allowed` also takes the parts that the store of the queue gives
  to the node.
- At 18:36:08 the isolate went over its memory limit and the VM started
  again from its memory image, with no event `started`: a VM from the
  memory image does not run the `init` of the log of the node. So the
  events `started` do not give each start of the VM. The breaks of the
  distribution of the measure before ("Two orders at one time, with no
  deploy") were most likely such resets.
- The summary of the shift: 16 parts in 28 minutes, the 4 makes with "no
  recipe", and no failure after them.

**The second run (2026-11-20, `main` at c78f091, with #31 and #32; the
deploy of cffda79).** A shift started by hand at 23:48:04 (run
44839411281, its node joined at 23:49:18); the deploy was live at
23:50:55:

| Measure | Parts list | First part | Whole mid level |
|---|---|---|---|
| C: a storey of 3.34 (issue #34, 23:53:04) | 34.4 s | 65.1 s (the sign, the same part as in D); the first main part 107.5 s | 198.7 s |
| D: a storey of 3.54, 20 s after C (issue #35) | 39.3 s | 46.5 s (the sign); the first main part 157.0 s | 272.6 s |

- The job of C wrote each of its 7 part requests: each waited 10 s at
  the edge, so each was in the queue.
- The new VM started at about 23:53:55 (the event `started`), while the
  parts of C waited or were in work. No part went, and the order of the
  queue stayed: the 5 main parts of C started on the node from 23:53:59
  to 23:54:45, and the first main part of D at about 23:54:57 (from the
  time of each part and its time on the node).
- The summary of the shift: 13 parts in 23 minutes, each stored. The
  store refused the sign one time during the start of the new VM; the
  next make put the GLB that the node kept, in 1.3 s, with no new build.
- C took 198.7 s, the best time of these measures, also with a start of
  the VM during it.

**One run for each issue (1398b04).** Before, each issue started two runs
of "Shift request", and the time from the issue to the parts list was
35.8 to 57.9 s (A to D). After, one run for each issue, and the time was
39.2 to 92.2 s (C2 to D3): no gain that a measure can see. The run that
the second one stopped cost about 3 s, and the parts list itself (a build
at the edge) takes most of the time.

#### The start of a shift by the edge, and a request with an ID token

The measure (2026-11-20, `main` at cbbd7e2): no shift ran before each
request, so the edge started the shift. The order is a new edit of Hải
Âu at mid (7 new parts), and the request asks for a shift of 0.5 hours.
Each time is from the request: the issue, or the start of the request
in the job (the job started 19 s after the push of its branch):

| Request | Parts list | Start of `shift.yml` | Join of the node | First part | Whole mid level |
|---|---|---|---|---|---|
| An issue of the form (the job of `shift-request.yml`, with its ID token) | 38.2 s | 44 s | 109 s | 141.0 s | 279.2 s |
| A job of `sntran/Vung_Tau` with its own ID token (`world-request.yml`, `scripts/edit-time.mjs`) | 36.2 s | 39 s | 103 s | 131.9 s | 306.5 s |

- The edge starts the workflow some seconds after the parts list: at the
  first request of a part that waits (`x-world-shift: wanted`).
- The node joins about 65 s after the start of the workflow, when the
  build of its commit is in the cache (the source did not change since
  51a4525). A new source adds the compile at the start of the node (3 to
  5 minutes in the measures of the evening before).
- One new order of 7 parts takes about 5 minutes from the request, with
  a shift that the request starts.
- A job of a repository of my account gets its parts with its own ID
  token and no secret: the project is the name of its repository.
- The summary of the shift of the issue (run 44643134162): 7 parts, 16.4
  to 130.8 s each, all stored, no failures. The summary of the shift of
  the job (run 44646094215): 7 parts, 20.9 to 175.5 s each, all stored,
  no failures. During the measure of the job, the VM of the edge started
  again at 00:29:57 with no deploy (an event `started`), and all 7 parts
  still came.

#### Hải Âu in a shift on this computer

The measure (2026-11-18): the local edge (`wrangler dev`, with
`WORLD_SHIFTS=true` and the token of a project), the local GitHub
(`scripts/shift-local.mjs`), which runs `scripts/shift.sh` for each
start, and one node of a shift, all on one computer with 4 cores. The
order is Hải Âu at mid (7 parts: the sign, the base, and the 5 parts of
the main node), with the token of the project, and each time is from
the edit (`scripts/edit-time.mjs`):

| Request | Parts list | First part of the shift | Whole mid level |
|---|---|---|---|
| A storey of 4.0, no shift running (the edge starts one) | 29.2 s | 104.4 s | 224.5 s |
| One front, the shift runs | 29.3 s | 89.4 s | 220.8 s |
| A storey of 3.4, the shift runs | 34.6 s | 68.5 s | 215.3 s |
| A second order, 20 s after the storey of 3.4, the shift runs | 43.9 s | 224.0 s | 344.2 s |

- The edge started the shift at the first request of a part that needs
  one (29.3 s after the edit). The node of the shift joined in some
  seconds: here the build of the node was ready. On a runner of GitHub,
  add the queue of the runner, the checkout and the cache (about 1 to 3
  minutes, not measured).
- The sign and the base of an edit keep their keys, so they come from
  R2 at once.
- A second order joins the shift that runs: its parts wait in the
  queue, and the node builds them after the parts of the first order.
  With 10 parts at one time on 4 cores, the second order took 344 s.
- A shift of 0.5 hours ended at its time (15 minutes), wrote its
  summary (5 parts, 39 to 185 s each, a peak of 199 to 215 MB of the
  VM), and left the edge.
- For the time at world.mkfifo.com, with a shift on a runner of
  GitHub, see "Hải Âu in a shift at world.mkfifo.com".

#### Hải Âu with two nodes on one computer

The first measure of the labour of the parts, before the shifts: the
local edge (`wrangler dev`) and two native nodes (`a4372`, `a4373`)
that joined it, all on one computer with 4 cores. The order
is Hải Âu, and the level is mid (7 parts: the sign, the base, and the 5
parts of the main node). Each time is from the edit to the last part:

| Edit | Parts list | Sign and base | Main parts | Whole mid level |
|---|---|---|---|---|
| None (the first order, cold) | 24.8 s | 20.9 s (built) | 81 to 120 s | 145.0 s |
| One front (`options.fronts.0.bays` to 6) | 26.4 s | 0.1 s (R2) | 37 to 122 s | 148.7 s |
| The height of a storey (`options.storey` to 3.4) | 26.4 s | 0.1 s (R2) | 41 to 120 s | 146.6 s |
| A storey of 3.5, with `a4373` stopped 30 s after the list | 26.2 s | 0.1 s (R2) | 36 to 185 s | 210.9 s |

- Each time is less than the target of 5 minutes.
- An edit keeps the keys of the sign and the base, so they come from R2.
  It changes all 5 parts of the main node.
- When `a4373` stopped, its parts built again on `a4372`. All 7 parts
  came, and the time went up by about 60 s.
- The parts list stays at the edge (about 26 s of CPU time). This is
  less than 5 minutes, but more than 30 s.
- On computers with more cores, or with more nodes, the main parts
  build with less waiting.

### The secrets

The factory has two secrets, both of the Worker. The repository has no
secret.

```sh
npx wrangler secret put WORLD_SHIFT_TOKEN  # fine-grained token of GitHub: actions: write on sntran/World only
npx wrangler secret put WORLD_TOKEN        # 32 characters or more, for a project outside of GitHub Actions
```

- `WORLD_SHIFT_TOKEN`: the Worker starts the workflow `shift.yml` with
  it (`workflow_dispatch`, `shift.js`).
- `WORLD_TOKEN`: one token for my projects, for a caller
  that is not a job of GitHub Actions (for example the workspace of the
  builder of Vũng Tàu).

A caller proves who it is in `authorization: Bearer ...` (`callerOf` of
`handler.js`):

| Caller | Token | The project |
|---|---|---|
| A job of a repository of my account (GitHub Actions) | its ID token: `permissions: id-token: write`, the audience `https://world.mkfifo.com` | the name of its repository, in small letters |
| Another place (a workspace, a computer) | `WORLD_TOKEN` | the header `x-world-project` (letters a to z, digits, `_`, `.` and `-`) |
| The job of an issue (`shift-request.yml`) | its ID token | the header `x-world-project` (the project of the form) |
| A shift (`shift.yml`) | its ID token, to `POST /shift/join` | (the pass of its shift for the store) |

The Worker checks an ID token (`oidc.js`): its signature (RS256) against
the keys of GitHub (`https://token.actions.githubusercontent.com/.well-known/jwks`,
kept for an hour), `iss`, `aud`, `exp` and `nbf`, and the claims. A shift
has `repository` `sntran/World` and the `job_workflow_ref`
`sntran/World/.github/workflows/shift.yml@refs/heads/main` (the whole
text: a branch `main-test` is not `main`); the job of an issue the same
with `shift-request.yml`. A project is a job of a
repository whose `repository_owner_id` is the number of my account
(`WORLD_OWNER_ID` of `wrangler.jsonc`), not only its name.

**The address of the jobs.** The zone mkfifo.com gives the addresses of
the runners of GitHub a challenge of Cloudflare (403, `cf-mitigated:
challenge`, with each User-Agent), and a job cannot answer a challenge.
So the jobs of GitHub Actions (the shifts, the job of an issue, and the
jobs of the projects) ask the same Worker at its address on workers.dev,
`https://world.mkfifo.workers.dev`, which is not in the zone
(`workers_dev` of `wrangler.jsonc`). The audience of their ID tokens
stays `https://world.mkfifo.com`, and the URLs in the comments of the
issues are of world.mkfifo.com.

`docs/projects.md` is the guide for a new project. A project of GitHub Actions asks with no secret:

```yaml
permissions:
  id-token: write
steps:
  - run: |
      token=$(curl -sS -H "authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
        "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=https://world.mkfifo.com" | jq -r .value)
      curl -sS -H "authorization: Bearer $token" https://world.mkfifo.workers.dev/p/KEY.glb
```

### The listeners of the VM (a fault, closed on 2026-11-19)

**The fault.** Until 629aea8, `handler.js` sent each path that starts
with `/.tcp/` to the VM. BEAM.com connects a WebSocket on `/.tcp/PORT`
to the listener of that port in the VM (its `docs/WORKERS.md`, "Incoming
TCP and distributed Erlang": anyone who can reach the Worker can reach
its listeners). The VM has two listeners: the HTTP server of
`World.Service` (port 4000) and the distribution (port 4370). So a
WebSocket to `/.tcp/4000` was a direct connection to `World.Service`,
and no check of the Worker applied to it:

- `POST /shift/join` with any `x-world-shift-run` gave a node name, a
  cookie and a pass, with no ID token;
- with that cookie, a node connected on `/.tcp/4370` and could run code
  in the VM of the edge;
- the text bindings of the Worker are the environment of the VM, so that
  code could read `WORLD_SHIFT_TOKEN` and `WORLD_TOKEN`, and use the
  store of the orders (R2).

A test with the local edge (`wrangler dev`) showed each step before the
correction: `/.tcp/4000` gave 101, an HTTP request over it reached
`World.Service`, and a node that joined read the three secrets in the
environment of the VM.

**The corrections** (on the site on 2026-11-19 at 20:34:38 UTC):

- 3b3c009: only a WebSocket on `/.tcp/4370` (or `DIST_PORT`) goes to the
  VM. Each other `/.tcp/` path, and a request that is not a WebSocket,
  gets 404 at the Worker.
- 629aea8: the class `Beam` gives the VM the env of the Worker with no
  `WORLD_SHIFT_TOKEN`, `WORLD_TOKEN` or `WORLD_STORE_TOKEN` (`vm_env.js`).
- 82d433e: the object of the VM also refuses each other `/.tcp/` path,
  whatever version of the Worker sends the request.
- On 2026-11-21 I made new values for the three secrets
  (`WORLD_SHIFT_TOKEN`, `WORLD_TOKEN` and `WORLD_STORE_TOKEN`). A test
  order started `shift.yml` with the new `WORLD_SHIFT_TOKEN`.

**The other ways in.**

- A scan of all the ports of the local edge (`/.tcp/1` to
  `/.tcp/65535`) found two listeners only: 4000 and 4370.
- The Preview of each branch runs the code of that branch, with the
  bucket of the site (`previews.r2_buckets` of `wrangler.jsonc`). The
  branches with shift code got `main`, so their Previews have the
  correction. A Deployment URL of a Preview
  (`DEPLOYMENT-world.mkfifo.workers.dev`) keeps the code of its deploy.
  On 2026-11-21 I deleted all the Previews
  (`npx wrangler preview delete --name NAME`): each branch URL gives
  404. Two Deployment URLs still answer; both are deploys of after the
  correction (`/.tcp/4000` gives 404). A new Preview does not build:
  its bucket `world-previews` does not exist, on purpose.
- The routes of the Worker that send a path of the client to the VM go
  through `forward()`, which keeps 4 headers only. The headers that the
  VM trusts (`x-world-shift-run`, `x-world-shift-pass-hash`, `x-world-project`,
  `x-world-origin`) come only from the Worker.

**The logs.** I read the Workers Logs of all requests, from
2026-11-13 06:00 UTC (the oldest that Cloudflare kept) to the
correction. The hole was open from 2026-11-18 20:10 UTC.

- Only one WebSocket to a `/.tcp/` path other than `/.tcp/4370`
  reached the VM: `/.tcp/4000` on `world.mkfifo.workers.dev` at
  2026-11-19 20:32:26 UTC. It was the check of the fault before the
  correction: a WebSocket upgrade, then no data. Four more
  (`/.tcp/4000`, `/.tcp/1`, `/.tcp/4370x` and `/.tcp/04370` on
  `world.mkfifo.com`, from 20:34:55) were the checks after the
  correction, and got 404. The six rows have the same headers and the
  same TLS fingerprint as that check.
- So no other caller used `World.Service` with no check of the Worker,
  and no node joined through `/.tcp/4000`.
- Each `POST /shift/join` got 200 and was a run of `shift.yml` on
  `main`, that I started: the runs 2, 4, 6, 7, 8, 9, 10, 11 and
  12 (the run id in `x-world-shift-run` is that of GitHub). No join got
  401 or 403.
- The rows of `/.tcp/4370` are the nodes of the shifts. A node with a
  wrong cookie was refused (`Invalid challenge reply`).
- The requests of the Previews are not in the Workers Logs:
  `observability` of `wrangler.jsonc` does not apply to a Preview, and a
  check of `/.tcp/4000` on a Preview at 2026-11-19 20:32:19 UTC is not
  in the logs. So the logs cannot show who used the hole of a Preview.
  The Previews are deleted, and the three secrets are new.
- The edge sent the pass of a shift to the VM in the header
  `x-world-shift-pass` of `/shift/allowed`, and the Workers Logs keep
  that header. A pass works only while its node is in the shift, and
  for 10 minutes after (6 hours at most). Since 2026-11-21 the edge
  sends only the SHA-256 of the pass (`x-world-shift-pass-hash`), and
  the VM keeps only that hash.

### The check of the bucket

From 2026-11-18 20:10 UTC to the delete of the Previews (I said at
00:54:35 UTC on 2026-11-21 that I had deleted them), an old Preview
could write to the bucket of the site, and no log of a Preview exists.
A part is used again by its key, so a part written in that time can go
to each project that asks for the same key. This check finds each
object of that window, with no token of Cloudflare:

- The workflow `.github/workflows/bucket-check.yml` (`workflow_dispatch`,
  on `main` only) asks GitHub for its ID token. The routes `/bucket/` of
  the Worker (`handler.js`) take only that token: `oidc.js` compares the
  whole `job_workflow_ref`
  (`sntran/World/.github/workflows/bucket-check.yml@refs/heads/main`),
  as for `shift.yml`. Each other caller gets 403.
- `GET /bucket/list` gives the objects of the bucket `world` (the R2
  binding of the Worker) whose upload time is in the window
  (`WINDOW` of `handler.js`). `GET /bucket/object?key=KEY` gives the
  bytes of an object of any time. `POST /bucket/quarantine?key=KEY`
  moves an object of the window to `quarantine/KEY`, with its type and
  its upload time. No route of the site gives `quarantine/`. Nothing is
  deleted.
- `scripts/bucket-check.mjs fetch DIR` (in each job) gets each object of
  the window, and each order, recipe and blueprint that it names. The
  summary of the job gives the count of each kind. The artifacts have
  the keys, the sizes, the upload times, the ETags and the verdicts, but
  no content.

The check of each kind:

- World builds a part (`parts/KEY.glb`), the recipe of a part
  (`parts/KEY.json`) and a file of an order at a level
  (`builds/COMMIT/HASH.LEVEL.FILE`). The check builds each one again
  from its recipe at the same commit and compares the bytes: World
  builds give the same bytes each time. A log of a construction
  (`.log`) has times, process ids and measures of the run; the check
  compares its events with these left out.
- `scripts/bucket-check.mjs plan` puts the commits of `main` that the
  site ran in the window (the commit of `main` at its start, and each
  commit after it) in groups with the same code (`lib`, `priv`, `wings`,
  `mix.exs`, `mix.lock`). A file of an order goes to the group of its
  commit. A part or a recipe goes to the group of the commit that the
  site ran at its upload time, and also to the group of the commit before
  when the time is less than 10 minutes after a deploy.
- A job for each group checks out the commit of the group, and
  `scripts/bucket-rebuild.exs` builds there, with a store of its own
  (the orders, the blueprints in data, and the recipes of the site; no
  part): each file of its commits, the parts list of the order and the
  level of each recipe (for a part with no recipe, also the parts lists
  of its time, and of each file of its commits: the site makes the list of
  an order for each of its files), and each part from the recipe of the
  site, two at a time. A part agrees when the part from its recipe has the
  same bytes. A part with no recipe (a part of a rule in code or of a
  drawing: its key is a hash of its content and of the version of
  `World.Build`, so it depends on the folder of the build too) agrees when
  the rebuild made a part with the same bytes. A recipe
  agrees when the rebuild makes a recipe with the same JSON values at its
  key, or when the two differ only in the order (two orders with the same
  part) and the part from the recipe of the site agrees. The
  last job joins the verdicts of the groups: for each object, the best
  verdict of a group.
- An order and a blueprint in data have a key that is the hash of their
  content (`World.Orders.hash/1`). The check builds the hash again from
  the content: the object agrees when its content gives its key (an
  object with that key is that order, from any writer), and it differs
  when not. So an order needs no request in the Workers Logs.
- For a recipe that does not agree, the note gives the order and the
  level of the recipe, and says when the site has no part for its key.
- **In the window, the keys of the parts depended on the folder of the
  build.** The key of a part had the version of its rule
  (`World.Elements.version/1`), then the MD5 of the compiled code of the
  rule and of each module of World that it calls, and some modules keep
  the absolute path of the folder of their build in their code
  (`World.Drawing`, `World.Standards`, `World.Textures`,
  `World.Terrain`, `World.Animals`, `World.References`, a `__DIR__` in a
  module attribute). So a build of the same commit in another folder
  gave other keys: the site (the folder of Workers Builds), this
  computer and the jobs of CI each had their own keys, and the GLB of
  each part was the same. (Since pull request #67, the version comes
  from the source, and each folder gives the same keys: "The parts of a
  model", "One key in each folder".)
- So the check does not make the keys again. Only the Worker of the site
  writes `builds/` under a commit of `main` (a Preview writes under the
  commit of its branch, and the store of the VM takes no key of
  `builds/`), so the parts lists of the site
  (`builds/COMMIT/HASH.LEVEL.elements`) give the true key of each part of
  an order at a level. The fetch also gets the list of the site for the
  order and the level of each recipe of the window, and for each order
  of the window at each level, at each commit that the site ran. The job
  of a group makes each list of its commits again; when the two lists
  are the same with no keys, the recipe and the GLB of each part here
  have the key of the site at the same place of the list, and the check
  compares their bytes. A parts list of the site agrees when it is the
  same list with no keys.
- The report gives a note for each object that does not agree: for a
  JSON object that differs, the first paths that differ, with the value
  of the site and the value of the rebuild; for a part, a part of the
  rebuild with the same bytes under another key, if there is one, else
  the first paths where its GLB data (with no buffers) differs from a part
  of the rebuild with the same name and level.
- World does not build an order, a blueprint in data, an entry of the
  history of the edits, the hash of the order of a URL (`urls/`), the
  hash of a control key (`controls/`) or the state of the shifts. For
  each one, the check finds the request of the site that wrote it in the
  Workers Logs. An object with no such request came from a Preview.
- Each object that does not agree, and each object with no request,
  goes to `quarantine/`.
- With the input `held`, the check reads the objects of `quarantine/`
  again (`/bucket/list?held=1` and `/bucket/object?key=KEY&held=1`: read
  only, each with its key and its upload time from before the move) and
  makes the same rebuild and the same notes for them: so the cause of an
  object that went to `quarantine/` can be found after the move.

**The result (2026-11-21).** Run 44924224179 of `bucket-check.yml`, at
`main` 7512a47, after the changes of #61 to #65. The window has 741
objects. 13 groups of commits; each file of a commit is from a commit of
`main` (no file of a commit of a Preview).

| Kind | Objects | Agree | Differ | No rebuild | Need a request |
|---|---|---|---|---|---|
| A file of an order (`builds/`) | 156 | 149 | 0 | 7 | – |
| A part (`parts/KEY.glb`) | 380 | 288 | 0 | 92 | – |
| A recipe (`parts/KEY.json`) | 138 | 126 | 2 | 10 | – |
| An order (`orders/`) | 40 | – | – | – | 40 |
| An entry of the history of the edits | 16 | – | – | – | 16 |
| The hash of the order of a URL (`urls/`) | 7 | – | – | – | 7 |
| The hash of a control key | 2 | – | – | – | 2 |
| A request of a part (`requests/`) | 2 | – | – | – | 2 |

- The files: 128 have the same bytes, and the 21 parts lists are the same
  lists with the keys of the build of the site.
- The parts: 82 agree by their key (the part from the recipe of the
  site, or the part at the same place of the parts list of the site),
  and 206 parts of rules in code have the same bytes as a part of the
  rebuild.
- The recipes: 111 have the same JSON values with other bytes, and 15
  name another order with the same part, and the part from the recipe
  agrees.
- Each order of the window gives its hash again from its content.
- The 7 files and the 92 parts with no rebuild are all of the same 4
  URLs of `/m/` (cars), at the commits 57e7eee and aa922fb. The site does
  not keep the order of a URL in `orders/`, only its hash in `urls/`, so
  the rebuild has no order for them. The URL of the request in the
  Workers Logs gives that order.
- 10 recipes have no part of a parts list of the site at their place,
  and 2 recipes name another order and the part from them does not have
  the bytes of the site.
- An object that the site wrote again after the window has a new upload
  time, so it is not in the list (an order: 41 in run 4, 40 in run 9).
  The key of an order is the hash of its content, so it is the same
  order.

**The quarantine.** The 111 objects that World builds and that do not
agree (the 7 files, the 92 parts and the 12 recipes) went to
`quarantine/` in run 44928698402 (111 answers 200). The site builds a
part, a recipe or a file again when a request asks for it.

**The check is done (2026-11-21).**

- **The orders.** The key of an order is the hash of its content, so an
  object whose content gives its key is that order, from any writer. Run
  44951873153 (at 107cac8, after #69) gave each of the 40 orders of the
  window the verdict `agrees` by its content: they need no log.
- **The objects that stay.** In the same run, the window has 630
  objects (the 741 of run 9 less the 111 in `quarantine/`): the 40
  orders, 149 files, 288 parts and 126 recipes agree, and the 27 objects
  below need a request.
- **The 27 objects that need a request** went to `quarantine/` in run
  44955757970 (27 answers 200): the 7 hashes of the order of a URL
  (`urls/`), the 2 hashes of a control key (`controls/`), the 2 requests
  of a part (`requests/`) and the 16 entries of the history of the edits
  (`history/`). The site makes the hash of the order of a URL again at
  the next request of that URL. A control key of the window no longer
  controls its construction, and an edit of the window has no entry in
  the history of its order.
- **My Workers Logs** keep 7 days, so the first hours of the window go
  on 2026-11-25 at 20:10 UTC. If I send the logs before then, each entry
  of the history that a request of the site wrote goes back. Else the 16
  entries stay in `quarantine/`.
- **The 12 recipes in `quarantine/`.** Run 44958553191 (at 871ae04,
  with the input `held`, #70) checked the 138 objects of `quarantine/`
  again and gave the order and the level of each recipe:
  - **The 2 recipes that differed** (`ae043ff7…` and `ae7c94f6…`,
    2026-11-19 21:02:40 and 21:02:41): the site wrote them from the parts
    list at mid of the order `b4a4e642…`, an edit of Hải Âu. The order of
    Hải Âu itself (`42bab18a…`) has the same two parts (the parts that the
    edit does not change), and run 9 made its list first, so its recipe
    named `42bab18a…`: the same part, with another order in the recipe.
    With the list of `b4a4e642…`, the held run gives the same JSON values
    (`agrees`). The bucket has no GLB of these two parts from the window
    (no request asked for them), so no part bytes differ.
  - **The 10 recipes with no part at their place**: 5 of the order
    `e539db47…` (2026-11-19 21:09:13 to 21:09:15) and 5 of the order
    `aabcb17f…` (21:47:05 to 21:47:06), each at mid. The two orders are
    edits of Hải Âu (their entries of the history are at 21:03:58 and
    21:39:28): the rebuild makes 7 parts of mid for each, and 5 of them
    are new. The site wrote the recipes of the 5 new parts, and the bucket
    has no parts list of the site for these two orders at any commit of
    the window: each list stopped after its recipes and before its file.
    The parts list of Hải Âu at mid needs about 85 MB and 25 to 35 s at
    the local edge (below, "Hải Âu"), so the likely cause is an end of
    the VM in the list; the record of that time has no cause (the record
    of the ends of the VM came later). With no list, no part has the key
    of these recipes, and their keys were keys of the folder of the build
    of that time, which no build gives again.
  - No recipe came from a build that gives other bytes at each run, so
    there is nothing to correct in the builds. The 12 recipes stay in
    `quarantine/`: the site makes a recipe again when a request asks for
    the parts list of its order.
- **In all:** of the 741 objects of the window, 603 agree and stay, and
  138 are in `quarantine/`: the 111 that did not agree, and the 27 that
  need a request.
- **The routes `/bucket/`** answer 404 since this change, unless the
  variable `WORLD_BUCKET_CHECK` of `wrangler.jsonc` is `"true"` (`"false"`
  by default). `quarantine/` and the workflow stay: to run the check
  again, set the variable to `"true"`, deploy, run the workflow, and set
  it back.

### The memory of the VM (2026-11-21)

`GET /census` gives the memory of the VM (`memory`), and
`node scripts/memory-record.mjs BASE SECONDS MINUTES OUT.csv` records it.
The size of the memory of WebAssembly is what the isolate counts: it is
the peak of what the VM used, with the work of its builds, and it never
gets smaller in one VM.

**An hour with no request of mine** (`main` at ee61761, a look each
30 s from 07:29 to 08:29 UTC):

| Time (UTC) | Event | Size (MB) | Used (MB) | Processes | Their bytes (MB) |
|---|---|---|---|---|---|
| 07:29 | a new VM after the deploy | 30.6 | 27.6 | 146 | 1.0 |
| 07:34:59 | my request of one small parts list (`mini`, far) | 55.4 | 42.3 | 146 | 1.0 |
| 07:35 to 08:21 | no request | 55.4 | 42.4 | 146 | 1.0 |
| 08:21:38 | a new VM, with no deploy | 30.6 | 27.7 | 148 | 1.1 |
| 08:22 to 08:29 | the requests of another caller (a construction) | 70.5 | 36.2 to 38.3 | 152 to 161 | 1.2 to 2.3 |

- With no request, nothing grows: from 07:35 to 08:21 the VM used
  42.4 MB the whole time.
- The processes (1 to 2.3 MB), the tables of ETS (0.5 MB at most), the
  binaries (1.2 MB at most) and the persistent terms (0.1 MB) stay small.
- What grows is the memory that the VM uses outside its processes: about
  15 MB at the first build of a VM, and it stays. Most likely it is the
  code of the modules that the build loads. Each new VM starts from the
  memory image of the first VM of its deploy, with 27 MB used, and loads
  that code again at its first build.

**2026-11-20 near 18:50.** The three VMs in 5 minutes (18:49:28,
18:50:18, 18:54:24) each built whole models one after the other: an
order, then its GLB at near, mid and far, its parts and its receipt.
Their peaks were 46 then 97 MB, 49 MB, and 62 MB. The near GLB of a
whole model is the largest of these builds. The isolate also holds
`edge.com` (50 MB) and the memory image of the VM (19 MB), so the VM
stops before the guard of `WORLD_MEMORY_MB` (118 MB) stops a build.

**Three orders of three projects in one shift** (2026-11-21, `main` at
ee61761): a job of each repository with its own ID token (branch
`ci/world-three-projects`), 20 s apart. Each job placed its order (the
edit of Hải Âu: its edits), got its parts list at mid, and asked for all
its parts at one time. The edge started shift 19 at 08:33:47, and its
node built the 14 parts (each stored).

| Project | Start (UTC) | Order | Parts list | Last part |
|---|---|---|---|---|
| vung_tau (an edit of Hải Âu, 7 parts) | 08:33:00 | 3.1 s | 35.7 s | 330.8 s |
| tre (a village house, 6 parts) | 08:33:20 | 23.8 s | 41.6 s | 328.6 s |
| diy (a fridge, 1 part) | 08:33:40 | 10.7 s | 25.8 s | 310.6 s |

The memory of the VM (a look each 10 s):

| Time (UTC) | Event | Size (MB) | Used (MB) |
|---|---|---|---|
| 08:30 | before the measure (left from 08:22) | 70.5 | 36.3 |
| 08:33:35 | the three orders | 70.5 | 53.7 (the peak) |
| 08:33:46 | a new VM | 50.1 | 40.3 |
| 08:34:06 | the parts lists | 62.5 | 42.8 |
| 08:35:59 | a new VM | 30.8 | 28.0 |
| 08:36 to 08:42 | the parts in the shift | 31.0 | 27.6 to 28.1 |

- The peak of the size was 70.5 MB, under 80 MB, but the VM still
  started again two times. So 80 MB of memory of WebAssembly is not
  under the limit of the isolate with `edge.com` and its memory image in
  it. The node of the shift joined again each time (08:35:56, and also at
  08:42:16), and no part went.
- The first new VM came while the edge checked the three orders at the
  same time: an order and its edits do not go through the line of the
  builds (`World.Line`), so they add up.
- The Workers Logs give the cause of the end of an isolate (`outcome`);
  I did not read them for this measure. Since then the Worker keeps its
  own record of the ends (below, "The record of the starts and the ends
  of the VM").
- The next changes to keep the peak low: the orders and their edits
  through the line of the builds; a guard (`WORLD_MEMORY_MB`) at the room
  that the isolate really has; and the code of World loaded before the
  memory image, so that a build does not load it again in each new VM.
  On 2026-11-22 I made the first two, and not the third: it makes a new
  VM need more memory at its start ("Three orders at one time, with the
  record").

### The record of the starts and the ends of the VM

The Worker keeps the time and the cause of each end of the isolate of
the VM, with no dashboard (`isolates.js`). Each event is a key of R2
with no content:

- `isolates/TIME.start.COMMIT`: a new VM (the constructor of the Durable
  Object `Beam`, `worker.js`), with the commit of its Worker;
- `isolates/TIME.end.CAUSE`: a request to the VM that failed because its
  isolate ended (`handler.js`), with one word for the cause from the
  message of the runtime: `memory`, `cpu`, `deploy`, `reset`,
  `connection` or `other`;
- `isolates/TIME.end.stopped`: a request to the VM that got the answer
  of beam.com for a VM that stopped itself (503, "The app stopped. Try
  again."; since 2026-11-22). beam.com gives that answer, with no error,
  to each open request when the VM stops (most often an allocation that
  failed in the memory of WebAssembly), and to each request while its
  object starts again. Before, such an end had no failed request, and
  the census gave it as `idle`.

`GET /census` gives `isolates`: the starts of the last 7 days, and for
each start after the first, the end of the VM before it with its cause:
the cause of the last failed request between the two starts; else
`deploy` when the commit changed; else `idle` (the isolate ended with no
request in flight). `failed` has the failed requests after the last
start. No header, no body, no IP address and no token goes into the
record.

### Three orders at one time, with the record (2026-11-22)

**Before the changes** (`main` at b186451, with the record and with the
parts that fit the edge, #74): three jobs of Vũng Tàu with their ID
tokens, 20 s apart from 01:52:00 UTC (run 44972379940 of Vũng Tàu), as
the three projects of 2026-11-21: the edit of Hải Âu (7 parts at mid), a
village house (`village_house`, 6 parts) and a fridge (`appliance`, 1
part). Each job placed its order, got its parts list at mid, and asked
for all its parts at one time, again on each 202 and 503.

| Order | Order (s) | Parts list (s) | Last part (s) |
|---|---|---|---|
| The edit of Hải Âu | 5.1 | 76.2 | 458.2 |
| A village house | 36.5 | 53.4 | 636.8 |
| A fridge | 17.5 | 40.0 | 739.2 |

The record of the VM (`GET /census`, `isolates`): 15 new VMs from
01:53:32 to 02:04:58, 8 ends with the cause `memory` and 7 with no
failed request (the VM stopped itself; the census of then gave them as
`idle`). The memory of WebAssembly (a look each 10 s, in MB of 10^6
bytes):

| Time (UTC) | Event | Size (MB) | Used (MB) |
|---|---|---|---|
| 01:51:05 | before the orders | 31.5 | 28.1 |
| 01:52:32 | the three orders and their checks at one time | 86.9 | 62.1 (the peak) |
| 01:53:32 | a new VM (the VM stopped itself) | 31.0 | 28.3 |
| 01:54 to 02:03 | 8 more new VMs: each one ended after a look at 50 to 78 MB | | 36 to 56 |
| 02:03:22 to 02:04:58 | 6 more new VMs, each 18 s after the one before: the build of the part of the fridge at the edge, from 31 MB | | |

- An order and its edits did not go through the line of the builds, so
  the three checks added up: 86.9 MB in 30 s. The VM went on at that
  size for one minute, then it stopped.
- Since #74 the edge builds each part of 150,000 faces or fewer itself.
  The guard of 118 MB never stopped a build, because the VM ended before
  its memory was at 118 MB. The part of the fridge ended six VMs in a
  row; each job asked again on each 503.
- The census shows the ends of the VM, but a look each 10 s does not see
  the size at the end itself.

**The changes** (the pull request after #75):

- `POST /orders`, `POST /orders/HASH/edits`, `POST /sets`, and the MCP
  tools `place_order`, `check_order` and `edit_order` go through the line
  of the builds (`World.Line`): one check at a time, as a build.
- `WORLD_MEMORY_MB` is 60 (was 118). The parts list of the edit of Hải
  Âu alone used 51 MB at most (the census of 2026-11-22 01:18), so it
  still fits. A part that the guard stops waits for a shift (a project),
  or gives the error of the guard (a public caller).
- The record has the cause `stopped` (above, "The record of the starts
  and the ends of the VM").
- I did not load the code of World before the memory image. beam.com
  makes the image of a VM with no SQLite of its own (World) at the first
  request of the first VM of a deploy, after its server listens: so the
  code that `World.Application` loads at its start would be in it. But
  the image is the pages of the VM that are not zero, and beam.com has a
  copy of them and the memory of the VM at one time: when it makes the
  image, and when a new VM restores it. The isolate also holds
  `edge.com` (50 MB). Today that is about 27 MB of image, 31 MB of
  memory and 50 MB. The code of World is about 16 MB more
  (`Code.ensure_all_loaded/1` of its 315 modules on a computer: 11 MB
  more of code, 16 MB more in all), in the image and in the VM: about
  32 MB more at that moment. The
  first VM of a deploy could then end when it makes its image, and each
  next VM would boot again and end the same way. When a build loads the
  code, the copy of the image is gone.

**After the changes** (`main` at d97237f, #76): the same three jobs from
03:40:00 UTC (run 44980547384 of Vũng Tàu), with a look at the census
each 2 s.

| Order | Order (s) | Parts list (s) | Last part (s) |
|---|---|---|---|
| The edit of Hải Âu | 3.4 | 31.9 | 243.0 |
| A village house | 30.3 | 48.4 | none at 03:49:41 |
| A fridge | 15.2 | 33.6 | none at 03:49:41 |

- The goal was no new VM in the measure. It was not met: from 03:41:22
  to 03:49:00 the VM started again 8 times, about each minute. 2 ends
  had the cause `memory`; the others had no failed request: the VM
  ended in a build of a part that the edge builds after its answer
  (202), when no request is in flight. I stopped the run at 03:49:41,
  because each next VM got the same builds, and each other caller of
  the site got 503 in that time.
- The checks of the orders went one at a time: the edit of Hải Âu got
  its parts list at 31.9 s, and its parts (the sign and the base were
  in the store, and shift 23 built the body) at 243.0 s, against 458.2 s
  before the change.
- The parts of the village house and of the fridge fit the edge (#74),
  and the edge built them itself. Each VM ended after a look at 73 to
  83 MB of size, with 39 to 58 MB used: under the guard of 60 MB, which
  looks at the use. One allocation can grow the size by 10 to 20 MB at
  one time.
- The first VM of a deploy restores no image, and it went on at more:
  101 MB at 03:35 (a request of another caller), and 87 MB at 01:18
  (the parts list of Hải Âu). Each VM that restored the image ended at
  70 to 80 MB. The difference is about the size of the image (27 MB):
  the bytes of the image that the VM restored can stay in the isolate
  until the garbage collector frees them, and a module of the Worker
  (`edge.com`, 50 MB) stays in it all the time (beam.com,
  `runtime/worker.js`).

**Each VM with no memory image** (#77, `BEAM_SNAPSHOT` `"off"`, `main`
at 44f2bcb; the same three jobs from 04:45:00 UTC, run 44985489627 of
Vũng Tàu, a look at the census each 2 s):

| Order | Order (s) | Parts list (s) | Last part (s) |
|---|---|---|---|
| The edit of Hải Âu | 3.0 | 35.1 | 261.6 |
| A village house | 43.0 | 62.2 | 462.8 |
| A fridge | 28.1 | 47.2 | none at 04:56:19 |

- It was worse: 13 new VMs from 04:46:32 to 04:55:54 (8 ends with the
  cause `memory`, 5 with no failed request), and some VMs ended after a
  look at only 49 to 51 MB. So a VM that boots with no image has no
  more room than a VM that restores it, and my reason for #77 was
  wrong. I stopped the run at 04:56:19, and the next pull request puts
  the image back (`BEAM_SNAPSHOT` is not set).
- From 04:49 to 04:56 the build of the part of the fridge at the edge
  ended each new VM, as in the first measure: the job asked again on
  each 503, and each new VM built the part again.

**Where this leaves the goal.** With the three orders, the VM still
starts again. The cause that I can see in the three measures is the
build at the edge of a part that fits by its faces (#74) but needs more
memory than the VM has: the part of the fridge, and the parts of the
village house. Its memory grows faster than the guard looks (each
25 ms), so the guard does not stop it. The next changes that I see:

- a part whose build at the edge ended the VM goes to a shift at its
  next request: a mark in the store before the build, taken away after
  it, so a new VM sees a build that did not end;
- a limit of the edge for a part from its estimate of memory, not only
  from its faces;
- the guard of the binaries of the process of a build too
  (`max_heap_size` with `include_shared_binaries`), not only of its
  heap.

**The memory of each part** (the local edge, `wrangler dev` with the
`edge.com` of 11973fb and no guard; the memory of WebAssembly in use,
over about 45 MB at rest):

| Part (mid) | Faces | Maps | Added |
|---|---|---|---|
| The body of the fridge (one part) | 3,323 | 512 | 54.5 MB |
| The roof of the village house | 76,836 | 512 | 31 MB |
| The frame of the village house (3 tiles) | 17,000 to 34,000 | 256 (a tile) | 15 to 16 MB |
| The gable of the village house | 62,988 | 256 | 14 MB |
| The base of the village house | 18,420 | 128 | 14 MB |
| The sign and the base of Hải Âu | 51,392 and 106,510 | | 15 MB each |
| A tile of the body of Hải Âu | 332,528 | | 24.5 MB (308 s) |
| A person at mid; at far | | | 15 to 27 MB; 11 to 13 MB |

On a computer the body of the fridge took 241 MB with its maps of 512,
63 MB with maps of 256, and 28 MB with no maps: the maps take the most
(the bake keeps each texel of its charts as a term). After the people,
about 14 MB more stayed in use in the VM (their data).

**The changes** (the pull request after #81):

- A part of a sculpture fits the edge only when the estimate of the
  memory of its build (`World.Skills.Sculpt.memory/3`, in its recipe:
  15 MB, 160 MB for each million texels of its maps, 0.15 MB for each
  thousand faces) is 20 MB or less (`World.Labour.edge_memory/0`). No
  part of the table is over its estimate. With 20 MB, a part with maps
  goes to a shift, and the edge builds a sculpture with no maps and few
  faces. The limit of 150,000 faces of #74 stays, for the CPU time.
- The edge writes the mark `parts/KEY.edge` before it builds a part. A
  part with the mark and no GLB is a build that did not end: from then on
  it waits for a shift (a project), or gets 422 (a public request).
- The guard limits the heap of the process of a build with its binaries
  (`include_shared_binaries`).

**After the changes** (`main` at 6691ac2, #82): the same three jobs
from 17:40:00 UTC (run 45050329486 of Vũng Tàu), with a look at the
census each 2 s as another caller:

| Order | Order (s) | Parts list (s) | Last part (s) |
|---|---|---|---|
| The edit of Hải Âu (7 parts at mid) | 4.1 | 34.4 | 448.0 |
| A village house (6 parts) | 422 at 19.5 | none | none |
| A fridge (1 part) | 4.6 | 13.3 | 409.3 |

- No part was built at the edge. Each part of the two orders waited for
  the shift (run 25 of `shift.yml`, on its runner from 17:43:19), and
  the shift built all 8 of them by 17:47:28.
- **The goal (no new VM) was not met:** 2 new VMs, at 17:43:19 and
  17:43:36, each with the cause `idle` (no request failed), and no end
  with the cause `memory`. Each of the 189 looks at the census from
  17:40:00 to 17:47:30 got 200 (and each of the 1,236 looks from
  17:35:47 to 18:24:19): no 503 for me as another caller.
- The checks and the parts lists took the size of the memory from
  31.5 MB to 75.8 MB in 40 s (the parts list of Hải Âu alone from 49.9
  to 75.2 MB). Then the VM was at rest, at 44 MB in use (the code of the
  builds), for 2.5 minutes until its end.
- I cannot see the cause of the two ends in the record, because no
  request failed. At that time no work of the three orders was at the
  edge. My push of the branch of the measure also started the workflow
  `Test` of Vũng Tàu (run 371), whose R4 test asks for three models of
  the catalog at each level as a public caller: before #83, builds at
  the edge. At 18:08:41, with no measure, the VM ended in the same way
  after a push to another branch of Vũng Tàu (run 372 of `Test`): the
  size went from 32.8 to 56.0 MB in 5 s, and a new VM started. Since
  #83 these files come with no build. That next VM went to a size of
  71.5 MB, was at rest from 18:10 (36.5 MB in use, no work), and ended
  at 18:21:12 with no failed request: a VM whose size went past about
  70 MB can end later with no work.
- The guard stopped the check of the village house (422): the VM used
  44 MB at rest, and the check needed more than the 16 MB that was left.

**The memory at the local edge** (`wrangler dev`, the `edge.com` of
6691ac2, the guard of 60 MB, from a fresh VM, one step after the other;
a look at the census each 100 ms):

| Step | In use at most | Size after |
|---|---|---|
| The check of the edit of Hải Âu | 39.4 MB | 49.2 MB |
| The parts list of Hải Âu | 53.9 MB | 83.3 MB |
| The check of the village house | 58.2 MB (422) | 83.3 MB |
| The check of the fridge, then its parts list | 54.4 MB | 83.3 MB |

The check of the village house alone, from a fresh VM, used 52.0 MB at
most, and the size went from 31.0 MB to 70.5 MB (74.8 MB in a second
try). So one check or one parts list of a large model takes the size
near the 73 to 83 MB after which the VMs of the site ended, also when
the memory in use stays under the guard: the size never gets smaller,
and the gaps between the blocks of the C allocator stay. At rest after
these steps, the processes, the binaries and the tables held about 2 MB;
the rest of the 44 MB in use was the code. A brick cache of 4 MB (in
place of 32 MB) and the load of all of the code of World before the
first build did not make the size smaller.

**The change after this measure** (#84): the check of an order with no
pose keeps the check of its data when the guard stops the build of its
model at far. The order is good, as a large model, and its parts list
and its parts give the errors of its build. An order with a pose still
gets the error of the memory: the check of its joints needs the model.

**After #85, with no shift** (`main` at c687282; the 6 shifts of
2026-11-22 were used): the same three jobs from 20:05:00 UTC (run
45063883775 of Vũng Tàu). The edge did its work for the three orders,
and the parts waited in the queue:

| Order | Order (s) | Parts list (s) | Last part (s) |
|---|---|---|---|
| The edit of Hải Âu (7 parts at mid) | 4.0 | 35.9 | none (no shift) |
| A village house (6 parts) | 38.4 | 60.9 | none (no shift) |
| A fridge (1 part) | 24.1 | 46.4 | none (no shift) |

- Each of the 1,153 looks at the census from 20:05:00 to 20:50:30 got
  200, and the check of the village house passed (#84).
- 6 new VMs, each with the cause `idle` (no request failed):
  - 20:11:21 and 20:16:53: the VM was at rest, a few minutes after its
    size had gone to 81.8 MB (the checks and the parts lists of the
    three orders) and to 70.8 MB (a build for another caller);
  - 20:20:46: a construction of a file for another caller went over the
    guard (82.1 MB in use), because the guard did not stop it (#89);
  - 20:29:08, 20:37:16 and 20:46:53: the VM was at rest at 30.7 MB of
    size, about each 8 to 9 minutes, while the jobs asked for their
    parts each 15 s. I do not see their cause. After the jobs ended
    (20:50), the next VM lived 13.5 minutes, until a deploy.
- The changes after this measure: a person of a group goes to a shift
  at each level (#88), and the guard stops the construction of a file
  when it stops its build (#89).

**After #89, with a shift** (`main` at 81c46f3): the same three jobs
from 00:10:00 UTC on 2026-11-23 (run 45086665981 of Vũng Tàu), with a
look at the census each 2 s as another caller:

| Order | Order (s) | Parts list (s) | Last part (s) |
|---|---|---|---|
| The edit of Hải Âu (7 parts at mid) | 3.4 | 43.8 | 483.1 |
| A village house (6 parts) | 47.4 | 68.9 | 445.7 |
| A fridge (1 part) | 33.2 | 53.9 | 388.7 |

- One shift (its start at 00:10:45) built the parts that do not fit the
  edge. All 14 parts came; two parts of Hải Âu were in the store from a
  measure before (44 s).
- **No 503 for another caller:** each of the 212 looks at the census
  from 00:10:00 to 00:18:30 got 200 (and each of the 615 looks from
  00:05:07 to 00:29:30).
- **1 new VM**, at 00:15:13, with the cause `idle` (no request failed),
  and no end with the cause `memory`. The checks and the parts lists of
  the three orders took the size from 30.7 MB to 81.5 MB by 00:10:32
  (59.3 MB in use at most at a look); then the VM was at rest, and it
  ended 4.5 minutes later.
- The measures before: 15 new VMs after #75, 8 after #76, 13 after #77,
  2 after #82.

**Where this leaves the goal.** The goal (no new VM) is not met yet. The
cause that I see is the work of the edge for the orders themselves: the
check of a model with sculptures (its build at far) and the parts list
of a large sculpture (the estimate of its tiles) take the size of the
memory of WebAssembly to 70 to 83 MB, also when the memory in use stays
under the guard, and the size never gets smaller. A VM at that size
ended a few minutes later at rest, four times in these measures. The
next change that I see: the parts list of a large sculpture, and the
build at far of the check of a model with maps, go to a shift for a
project, as its parts do.

### The guard and the memory of WebAssembly

The edge stops a VM on the size of its memory of WebAssembly (the log
line `beam: memory N MB` of beam.com), in the 128 MB of its isolate.
That size never gets smaller, and it has more than the memory of the
processes: the code, the atoms, the ETS tables, the persistent terms,
and the free blocks and the gaps of the C allocator. Since BEAM.com
0.1.0-rc.7 the runtime gives it to the VM (BEAM.com `docs/WORKERS.md`):
`wasm_host:memory(size)`, the size, and `wasm_host:memory(used)`, the
bytes that the VM uses now (`malloc()`), which go down when the VM
frees memory. `World.wasm_memory/1` reads both, and `World.Guard` uses
them in WebAssembly in place of the memory of the processes: it stops a
build when the VM uses more than `WORLD_MEMORY_MB`, or when the size is
more than `WORLD_MEMORY_MB` and less than 8 MB of it is free (the next
growth would go over the limit). On a native VM it reads
`:erlang.memory/1`.

The build of a whole file (`/o/HASH.glb`) opens a construction
(`World.build/1`), whose processes are not linked to the build. Before
2026-11-22 the guard stopped only the build, and the construction went
on: at 20:19 UTC the memory in use went to 82.1 MB (the size to
105.1 MB), over the guard of 60 MB, and the VM ended. That was a file of
an order of Vũng Tàu (its workflows `Test` and `Export` ask for the
files of their orders, and each deploy of World gives new keys to the
whole files). Now a build gives the guard the stop of the work that it
started (`World.Guard.on_stop/1`): the build of a file gives the cancel
of its construction (`World.cancel/1`), and the guard runs it when it
stops the build.

### The files of MakeHuman at the edge (2026-11-22)

The Worker imports `edge.com` as bytes (`worker.js`), and beam.com reads
each file of the release from those bytes: so all of `edge.com` stays in
the isolate of 128 MB, next to the memory of WebAssembly of the VM. Of
its 50 MB, 34.6 MB were the data of MakeHuman (`priv/makehuman`: the
clothes 18 MB, the targets of the body 6.7 MB, the hair 5.5 MB, the
skins 1.8 MB). On 2026-11-22 a VM of the site ended at rest, with no
work and no failed request, after its size had gone to 71.5 MB (from
18:10 to 18:21 UTC); 71.5 MB and 50 MB are near the 128 MB of the
isolate.

So the release of the edge has no `priv/makehuman` (`mix.exs`), and
`scripts/site.sh` puts the folder in the static files of the site
(`/makehuman/`; the data is CC0, as in this repository). A build at the
edge reads each file that it needs, when it needs it, through the port
`ASSET_STORE` of the object of the VM (`asset_store.js`, with the binding
`ASSETS`; `World.People.Files`): the whole file, a part of
`targets.pack` for each target of a person (a range of the static
files), or a look for a swatch. `edge.com` is then 15.5 MB. A node
that has the folder (a computer, the node of a shift, the tests) reads
it as before.

The version of a rule comes from the source of its modules
(`World.Elements.Source`), so this change gives a new key to each part
of a person, one time: the bytes are the same (the leader of a group of
two at mid at the local edge: 897,760 bytes, the same with the release
of `main`). A person at mid now goes to a shift too
(`World.Labour.fits?/1`): it took 15 to 27 MB at the local edge, more
than the 20 MB of `World.Labour.edge_memory/0`, and one took the size of
the memory to 82 MB before the guard stopped it. After the deploy, a
person at far on the site went over the guard too (56.5 MB in use at a
look) and took the size to 85.7 MB: so a person at each level now goes
to a shift (a project), or gets 422 (a public caller), with no build at
the edge.

### Hải Âu

The order `khach_san_hai_au` of Vũng Tàu (`data/world/orders.json`; a
hotel of the blueprint `building`: a sculpture of 755 edits, its sign
and its base), at the local edge (`wrangler dev`, the linear memory of
the VM, each request in a new VM; the VM starts at 25 MB, and the edge
stops a VM at about 134 MB):

| Request | far | mid | near |
|---|---|---|---|
| `POST /orders` (no build of the model for its check) | 52 MB | | |
| The parts list | 71 MB, 21 s: 3 parts | 85 MB, 25 s: 7 parts | 79 MB, 96 s (202, then the list): 33 parts |
| The main node | 1 part, 1,200 triangles: 91 MB, 122 s | 5 parts: 86 to 113 MB, 111 to 336 s | 31 parts; the largest: 92 MB, 221 s, and 80 MB, 176 s |
| The sign | 69 MB, 7 s | 76 MB, 20 s | |
| The base, before (a slab of 0.3 m in cells of 0.06, 0.12 and 0.3 m) | 52 MB, 5 s (empty) | 82 MB, 241 s | 99 MB, 1,326 s (266 steps) |
| The base now (1 m deep, in cells of 0.25, 0.3 and 0.4 m) | 61 MB, 21 s: 150 triangles | 67 MB, 37 s: 700 triangles | 90 MB, 44 s: 2,500 triangles |

Each part fits: the highest peak is 113 MB (a part of the main node at
mid). The parts of the main node take 1 to 6 minutes each. The times
are of one core shared with other work; an edit of an order builds only
the parts that it changes.

Before W26, the whole far level of Hải Âu took 210 MB at its check (the
VM stopped), and its whole near level could not build at the edge.

The base was a fault of the rule `building` (`World.Town.Building`),
not of the data of the order: the order gives only `apron: 0.6`, and
the rule made the ground (the part `_nen`) a slab of 0.3 m in cells of
0.3 m at far, so its far part had no surface, and gave a flat slab the
cells of 6 cm of a small part at near (2 million faces, 266 steps, 22
minutes). Now the slab goes 1 m down from the ground (the part under the
ground is not seen), deeper than the cells of each level, and a flat
ground has cells of 25 cm at near, 30 cm at mid and 40 cm at far: its
look (the concrete, the dirt) is in its maps. The edits of an order on
the ground (`more.nen`: a step, a kerb) keep the cells of a small part.

### Two questions of plan 0027 of Vũng Tàu

**Q1. A blend stays inside one part: is that enough for the buildings
and the statues?** Yes, and it is not needed for a closed surface. Each
part is made from the field of all the edits near it, so the field at
the border of two parts is the same field on the two sides, also in a
blend; the points at the border are the same points, and no collapse
moves them. So a blend that crosses two parts has no gap and no step.
World still cuts where the fewest soft blends cross (each plane between
the bricks of the estimate, 1 to 4 m apart): in a building the blends are
small (the round edges of a slab or of a column), and most cuts miss
them. In a statue a blend can be larger than the space between two
planes (a body of large soft blends); then the cut crosses it, and the
surface is still closed. What a cut can change is the maps: each part
has its own maps, so the color and the normal of a texel at the border
can differ a little on the two sides. The game can hide it with the same
material for the parts of one role (plan 0027, D3).

**Q2. For the far level, is one small part for the whole model better
than many parts?** Yes. Hải Âu at far: one part of 1,200 triangles for
the main node (plus 100 for the sign) is 2 draw calls and 1,300
triangles. Cut into 15 parts of about 15,000 faces each (the steps), the
same model was 16 draw calls and 2,025 triangles, and it had a bad
shape: a part of 80 triangles has most of its points at its borders,
and its collapse made spikes. So a part has a budget of 1,500 triangles
or more, and World makes a small far level as one part, in steps that
fit the memory (`World.Sculpt.model_in_steps/2`). The game can also join
the parts of one material (plan 0027, D3).

## Realism

Phượt and Vũng Tàu need models that look like the real things. So each
part, shape and model has two kinds of source, never a memory:

- **The sizes**: a standard, a data sheet, a drawing, or a trace of a
  drawing.
- **The photos**: photos of the real thing (from the maker, a dealer, a
  press kit, or my own). Before a commit, a render of the model and a
  photo from the same view are compared side by side.

The sources of a part give both, with the URL of each photo. The
repository keeps the URLs, not the photos.

## Other work: Cube of Roblox

"Cube: A Roblox View of 3D Intelligence" (arXiv 2503.15475, 2025; code
and weights at github.com/Roblox/cube) makes shapes with a neural
network:

- A shape tokenizer: points on the surface of a mesh become 512 to 1,024
  tokens; a decoder gives an occupancy field, and marching cubes gives
  the mesh. Text-to-shape writes the tokens from a text; shape-to-text
  writes a caption of a shape.
- Text-to-scene: a language model writes a scene as JSON (each object
  with its category, its caption, its place, its turn about the up axis
  and its box), then text-to-shape makes each object.
- For later, the paper names what World has now: shapes from parts,
  people with a skeleton and layers of clothes, and joints (a steering
  wheel that turns the wheels, a door that slides).

What it means for World:

| Topic | Cube | World |
|---|---|---|
| The source of a shape | Learned from about 1.5 million assets (Objaverse and Roblox). | Standards, data sheets, drawings and photos. |
| Sizes | A box from the scene; the shape inside it is learned. | The real sizes of each part. |
| Parts, joints, the list of the parts | Not yet ("future work"). | Yes. |
| Shapes that are not made from parts (a rock, a tree, a statue, a dog) | Yes. | No. |
| Where it runs | A GPU. | The VM at the edge. |

So the two agree in two ways:

1. **The order is the scene graph.** The JSON scene of Cube and an order
   of World have the same idea: a language model writes the layout, and
   a builder makes each object. An order of World gives more (options
   with ranges, slots, joints), and the check gives each error back to
   the model (step F7).
2. **Cube can supply parts.** A shape that the warehouse cannot make can
   come from Cube, made one time on a GPU, cleaned
   (`World.Mesh.clean/1`), and kept as a supplied part (step F6) with its
   text as its source. It is not a measured shape: the receipt says so.
   Read the license of the weights before a use.

## The constructions

A build of `POST /builds` is a construction of the node
(`World.Construction`, `docs/world.md`): the people of the node build
each element of the model at the same time, and each act is an event
that a client can watch. The body is an order (`blueprint` and
`options`, or `drawing`), with:

| Field | What |
|---|---|
| `level` | `near` (the default), `mid` or `far`. |
| `budget.workers` | The most people that the construction holds at one time: 1 to 64, 4 by default. |
| `budget.seconds` | The deadline: after it, the construction stops (the event `stopped`) and keeps nothing. No deadline by default. |
| `budget.triangles` | The most triangles of the model: the construction takes the most detailed level that fits (from `level` down), or stops (the event `stopped`, with the reason `triangles`). 1 to 10,000,000. |
| `budget.memory_mb` | The memory of the people: each person has its part for the heap of a task (`max_heap_size`, with the binaries that it holds). A task over it fails (the event `failed`, the message `memory`). 1 to 4,096. |
| `budget.clock` | `world` (the default): each person is busy for the days of its task on the world clock. `fast`: the log keeps the same days, but the people do not wait for them; the construction takes the results in the order of the ends of their tasks (plan 0007, D4). The stages of a site (plan 0006) go to their days at once: each stage starts at its date, and each year of a pause comes with no wait. While a hire waits for its person, the time of the site stays: the task of the person starts at the time of the hire, so a slow computer gives the same days. A hire that waits for a person of another construction (the census says `queued`) does not stop the time. A site with trucks keeps the world clock. |

Each event of the stream is `id: N` and `data: JSON`, with the fields
`id`, `kind`, `order` (the id of the build), `who` (the PID of the
person), `at` (the milliseconds from the start of the build), `wall`
and `data`. The kinds: `requested`, `plan_made` (the tasks, each with
its trade and the tasks that it waits for), `hired`, `task_started`,
`task_done`, `element` (the part of a task: its node, its GLB key and
its matrix), `released`, `paused`, `resumed`, `changed` (the tasks
made again, the nodes kept, the tasks that take down what it drops,
the new lot), `element_removed` (a part that people took down),
`stage_started` and `stage_done` (a stage of the method of the site:
its name, its work, its days and its fit, its tasks), `aged` (a pause
of a site: its days, the dirt, the weeds, the parts that go),
`repaired`,
`task_dropped`,
`done` (the model is complete), `stopped`, `failed` and `run_done` (the
time and the memory). A comment line
(`: ping`) comes each 15 s when there is no event.

### The control key

Anyone can watch a construction, but only its caller can change it. A
pause, a resume, a cancel and a change need the control key of the
construction, or `WORLD_TOKEN` (my key), in `authorization: Bearer
...`. Each other caller gets 403, and the request does not go to the
VM.

- `POST /builds` gives the control key to the caller that opens the
  construction, in the body of the answer, with `cache-control:
  no-store`: `control` in the JSON of the 202, or, with `accept:
  text/event-stream`, a first event `event: control` with `data:
  {"build", "control"}` (no `id`), before the events of the
  construction. No header has the key, so no log of the requests has
  it. The key is 32 random bytes in hex (256 bits).
- A caller that sends the order of a construction that runs (the same
  order at the same level: the same id) joins it, and gets no key. When
  the construction ends, the next caller of that order opens a new
  construction and gets a new key; the old key stops.
- The Worker keeps only the SHA-256 of the key, in R2 at
  `controls/ID`. The store of the orders and the store of the shifts
  cannot read or write these keys (`KEY` of `order_store.js`).
- The key does not go to the VM (the Worker sends no `authorization` to
  the VM), so it is not in `/events`, `/census`, `GET /builds/ID`, or
  the log of the node. The logs of the Worker hide the header
  `authorization`.
- When R2 does not keep the hash, the construction opens with no key:
  only `WORLD_TOKEN` controls it. A construction of the MCP tool `build`
  has no key either.

The construction keeps the model and the elements of its tasks; the
people make the shapes; a joiner (a process of its own) joins the model
at the end, and its memory goes back to the node when it ends. The most
memory of a build is in the join: `house_brick_vn` at near (7,594 tasks)
needs about 680 MB at the peak, and `mix world.bench` gives the peak of
each model (plan 0007, section 10).

A game shows the elements as they come (the GLB of each key once, and
an instance of it for each `element` event), then at `done` reads the
model of the order (`/o/HASH.glb`) in their place. A client that comes
late, or that loses its connection, sends `Last-Event-ID`: it gets the
events after that id from the store of the log (the SQLite of the
Durable Object, through the port `/env/LOG_STORE`), then the new
events. `specs/Stream.tla` proves that it gets each event one time, in
order, with no gap (`docs/specs.md`).

```sh
curl -N -H 'accept: text/event-stream' \
  -d '{"blueprint": "catalog", "options": {"name": "house_brick_vn"}, "level": "far", "budget": {"workers": 8}}' \
  https://world.mkfifo.com/builds
```

## The steps

| Step | What |
|---|---|
| F1 | This file. The Worker at `world.mkfifo.com` serves the catalog and the review page. Done. |
| F2 | Blueprints, orders and the receipt (`World.Orders`), `mix world.order`, the builder in the VM, the cache in R2. People, houses and framing are the first blueprints: they have options already. Done. |
| F3 | The van blueprint, from the traces of DIY and from photos: the Ford Transit (high roof, medium roof, extended; cargo, crew and passenger windows), with the engine bay and the roof. Done. The Sprinter and the ProMaster come after their photos. |
| F4 | People in the release (the data of MakeHuman in `priv/`), and less memory for the near level. |
| F5 | Drawings. |
| F6 | Supplied parts (with the reader of `.wings` of step 5 of `README.md`). |
| F7 | Orders from text: a language model writes an order or a scene from `/blueprints`, and the errors of the check go back to it until the order is correct. |
| F8 | Scenes: a list of orders, each with its place and its turn, and joins at slots. |

## The setup on Cloudflare

I do this one time:

1. In the dashboard of Cloudflare, Workers and Pages, make a Worker from
   the repository `sntran/World` (Workers Builds). The build command is
   `npm run build`, the deploy command is `npx wrangler deploy`. A push
   to another branch (a pull request) runs `npm run build` and then
   `npx wrangler preview`: a Preview of the branch at its own URL, with
   the settings of the block `previews` of `wrangler.jsonc` (a Preview
   does not take the settings of the site).
2. `wrangler.jsonc` has the custom domain `world.mkfifo.com`: the deploy
   makes its DNS record and its certificate in the zone `mkfifo.com`.
3. Make the R2 bucket of the orders before the first deploy:
   `npx wrangler r2 bucket create world`. It needs no public access:
   the Worker reads it.
4. The Previews. A Preview uses the bucket `world-previews`, not the
   bucket of the site, so a Preview cannot change the orders and the
   parts of the site. The site has no such bucket now: on purpose, each
   Preview build fails, so no Preview runs. To have Previews again, make
   the bucket: `npx wrangler r2 bucket create world-previews`.
   A Preview has no secret of the site: do not put `WORLD_SHIFT_TOKEN`,
   `WORLD_TOKEN` or `WORLD_STORE_TOKEN` in the Base configuration of the
   Previews (`npx wrangler preview base-config secret ...`) or in a
   Preview. With no secret, a Preview starts no shift and takes no
   project token. A Preview keeps the code of its branch: delete the
   Preview of a branch that the site does not need any more (`npx
   wrangler preview delete --name NAME`, the name of the branch with
   `-` in place of `/` and `.`).
5. The Worker needs the Workers Paid plan: `edge.com` is about 44 MB (with no files of the catalog and of the kit: the site serves them), and
   a build takes more CPU time than the Free plan gives. Cloudflare
   refuses a Worker of more than 64 MiB (before compression), and then
   the deploy does not reach the site with no error in CI:
   `scripts/edge.sh` stops when `edge.com` is more than 60 MiB.

To try it on this computer: `npm install && npm run build && npx
wrangler dev` (Wrangler makes a local R2). `BEAM_COM=PATH` uses a
`beam.com` of the computer in place of `npx beam.com`.
