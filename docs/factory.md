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
| `POST /orders` | An order in JSON. The answer gives its hash, the full order (with each default), the URLs of its files, and the URL of its replay page; or 422 with the errors. |
| `POST /orders/HASH/edits` | Small changes to an order of `POST /orders`, in JSON: `{"edits": [...]}` ("An edit of an order"). The answer is as the answer of `POST /orders` for the new order, with `parent` (the hash of the order before) and `history` (each order from the first one to this one, with the edits that made it); 422 with the errors (the path `edits.N` for an edit that is not possible, else the paths of the check of the new order); 404 for a hash that the store does not have. |
| `/o/HASH.glb`, `.mid.glb`, `.far.glb`, `.parts.json`, `.receipt.json` | The files of an order of `POST /orders`. The people of the node build the GLB at each level (`World.Construction`). |
| `/o/HASH.drawing.json` | The drawing of the model, with the options of the order in it: each part with its shapes or its skill, the nodes, the joints. It is the drawing that the edit `free` of an order puts in the order ("An edit of an order"). A model that the code of a rule makes as a mesh (a plant, a person, an animal) is the one node `model` of its drawing: an item of its blueprint. |
| `/o/HASH.flat.glb`, `.mid.flat.glb`, `.far.flat.glb` | The model at a level with the flat look (`World.Flat`, plan 0019), for a project that draws many small things with no image: one node with one mesh, each face with its own three points, its normal and one color at each point (`COLOR_0`), a white material, no image, no skin. The points are at their places in the axes of the model. A drawing from edits is built with the look `flat` (the color of a face is the color of its edits); another model has the color of each of its roles. With `?triangles=N` (12 to 200,000), the mesh has at most N faces, or as few as the collapse can make. With `?wrap=1`, the mesh is one closed skin round the whole model (a cast of the model in a grid of 48 cells along its longest side, `World.Cast`), with the color of the nearest face of the model: for a model of many thin parts in a small budget. A part that is thinner than a cell is not in the skin. |
| `/o/HASH.light.glb`, `.mid.light.glb`, `.far.light.glb` | The model at a level with the light look (`World.Flat`, `roles: true`), for a project that gives each role its own material: one node with one mesh, a primitive for each role of the model, flat faces, the material of each role with its color (the mean of the colors at the points of a role that has them: a sculpture, the clothes of a person at mid and far) and no image, no skin. It takes `?triangles=N` and `?wrap=1` as the flat look: a budget keeps the border of two roles. A scooter at the far level: 4,120 triangles, and 500 with `?triangles=500&wrap=1` (50 KB, 15 KB in gzip, in 1.7 s). A coconut palm at the far level: 308 triangles, and 204 with `?triangles=204`. |
| `/o/HASH.solids.json` | The simple solids of the model (`World.Solids`, plan 0019), for a project that draws boxes or SVG and cannot draw a GLB. For a drawing from edits: each edit with its copies as one solid (its `shape` and `size` as in the data of an edit, its place `at` and its axes `x`, `y`, `z` in the axes of the model, its `mode`, its `color` and its `role`), in the parts of the drawing, with no build (milliseconds). For another model: one box for each node and each material. The lengths are in meters, z is up, and the front is to +y. |
| `/o/HASH.log.json`, `/o/HASH.replay.glb` | The log of the construction that built the near level (`World.Log`: one line for the clock, then one line for each event), and the model with each part in a node of its own, with the id of its task (extras `task`), for the replay. The replay of a drawing has its temporary nodes too, each with the task that puts it up and the task that takes it down (extras `from`, `to`; plan 0006, D9): the scaffold and the forms of each band, each band in rough concrete. |
| `/o/HASH.elements.json`, `.mid.elements.json`, `.far.elements.json` | The parts list of the model at a level (below, "The parts of a model"): each part with its key, its URL, its node, its place and its roles, and the joints, the ports and the collision boxes of the model. The factory does not join the parts: a project puts them together. |
| `/p/KEY.glb` | A part by its key: the same key is the same file, for ever (`cache-control: immutable`). From R2 with no VM, else the edge builds it from its recipe and keeps it, or, for a part that does not fit the edge, a construction shift builds it ("Construction shifts"): a project (a request with its token) that asks for all the parts of a list at one time gets them built at the same time. A large part that takes more than 45 s gives 202 with `retry-after`: ask again. A part of a public order that does not fit the edge gives 422. |
| `POST /builds` | A build that anyone can watch: an order with a `level` and a `budget` (below, "The constructions"). With `accept: text/event-stream`, the answer is the stream of its events; else 202 with its id and the URL of its events; or 422 with the errors. |
| `/builds/ID` | The state of a build from its events: `building`, `done`, `stopped` or `failed`, its level, its tasks and its elements. |
| `/builds/ID/events` | The events of one build as a stream (`text/event-stream`), from `Last-Event-ID` or `?after=N`. |
| `POST /builds/ID/pause`, `/resume`, `/cancel` | A pause (the people end the tasks in hand, and no task starts), a resume, or a cancel (the event `stopped` with the reason `cancelled`): 202, or 404. |
| `POST /builds/ID/change` | In a pause, a new order of the same blueprint in data (the same nodes): each node whose data is the same stays made, and the people make the others again at the resume (the event `changed`, with `redo` and `keep`). 200, 409 when the build is not in a pause or has other nodes, 422, or 404. |
| `/builds/ID/elements/KEY.glb` | The GLB of one element of a build, while the build goes on and for 5 minutes after its end. |
| `/events` | The events of the whole node as a stream: each construction, each hire, each element. |
| `/census` | The people of the node by trade, free and busy, and the constructions that wait for a person. And the crews (`crews`): the workers of the node, the nodes that share their workers, and the count of the sites with a stream of tasks now (`World.Crew`). |
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
| `check_order` | Checks an `order` and does not keep it: the hash and the full order, or the errors. |
| `edit_order` | Makes the `edits` on the order of a `hash` and keeps the new order, as `POST /orders/HASH/edits`. |
| `place_order` | Checks an `order` and keeps it, as `POST /orders`: the hash, the full order, the URLs of its files and of its replay page, or the errors. |
| `check_drawing`, `propose_drawing` | For an engineer: the review of a new `drawing`, and a proposal for the owner. |
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
  (`part`, or `figure` for a person with its props) and, for a part of
  a large sculpture, its `tile`. The list has the `joints`, `limbs`,
  `ports` and `collision` of the model. `review/parts.html?list=URL`
  puts the parts together as a project does.
- **The key of a part** is a hash of its data and of the version of its
  rule: the code of the rule and of each module of World that it calls
  (`World.Elements.version/1`). A part that is made (a node of shapes, a
  person, a vehicle) has its content as its data, with its level, its
  maps and the colors of the order: a wall of 1,000 bricks of one shape
  is one file. A part of a sculpture has its data: the edits near it,
  its box, its share of the faces and the other data of the sculpture.
  So an edit of an order changes the keys of the parts that it changes,
  and the factory builds only those (W27). The same keys are in the
  events `element` of `POST /builds` (W28), and the GLB of each element
  goes into the store of the parts.
- **A part fits the memory of the edge** (W26). A sculpture that has
  more than 20,000 faces at its cells (an estimate) is cut into parts,
  each with a budget of 4,000 triangles or more, and each part is made
  in steps of at most 20,000 faces, each step in a process of its own.
  The cuts are planes between bricks, where the fewest soft blends of
  the edits cross. Two parts next to each other meet with no gap: the
  points at their border are the same points, and no collapse moves
  them.
- **The guard of the memory.** A build runs in a process of its own,
  and `World.Guard` stops it when the memory of the VM goes over
  `WORLD_MEMORY_MB` (118 MB at the edge, "The guard and the memory of
  WebAssembly"): the order gets an error, and
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

So the edge builds only the parts that fit it with room (a person at
mid or far), and a construction shift builds the others (below). These
times are of `wrangler dev` on a shared core; the times at the edge
need a deploy (the next measure on world.mkfifo.com).

### Construction shifts

A construction shift builds the parts that the edge cannot build: a
workflow of this repository (`.github/workflows/shift.yml`) on a runner
of GitHub Actions, for the projects of the owner only. It is like the
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
  once only for an issue of a member; another issue waits until the
  owner adds the label again. The job puts no text of the issue in a
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
| A start that GitHub does not take | no answer, 429 or 5xx (a cause that goes away): the start of the day goes back, and the next start can come after 1 minute. 401, 403, 404, 422 or another answer (the token, the workflow or its inputs): the start stays used, with the wait of 20 minutes, until the owner corrects the cause | `shift.js` |
| No work | the shift goes home after 60 minutes (a request can set a shorter shift: `hours`, or the input `idle`) | `World.Shift` |
| A part in the queue | 6 hours at most, then an error | `World.Labour` |
| A part that fails | 3 tries on nodes of shifts, then an error | `World.Labour` |
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
(`WORLD_LABOUR=parts`): it builds only a person at mid or far.

**Whole parts, not small jobs.** The edge gives the shift a whole part
by its key (`World.Labour`). The node builds it, puts the GLB in R2
through the store of the Worker (`/store/KEY`, with the pass of its
shift, `scripts/order-store.mjs`), and gives back only the key. The
Worker writes R2 with its binding. It takes a key with a pass only when
the edge gave that part to that shift (the GLB to write; the GLB, the
recipe and the order of the part to read, and the blueprints in data),
else 403. No GLB goes over the link. A part in R2 does
not build again. A part whose node goes away goes back to the queue. An
issue gets its comment (the parts lists and their URLs) when its parts
are built, and closes: the job of the request closes it at once, else
the shift does (`scripts/shift-issues.mjs check`, each 5 minutes and at
its end).

**The length of a shift.** A shift stays until its end, and waits for
the next part between parts. It goes home early after 60 minutes with
no work. It stops 15 minutes before the end of the time of its job, and
its parts that are not done go back to the queue of the edge. It writes
a summary in the summary of the job: each part, its time, the peak
memory of the VM while it built, its result, and the failures and the
stops.

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
and `WORLD_PROJECT`) measures the time from an edit of an order to its
whole new level, as a project gets it: the edit, the parts list, then
all its parts at one time.

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
- The time at world.mkfifo.com needs the deploy, the secrets, and a
  shift on a runner of GitHub.

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
- `WORLD_TOKEN`: one token for the projects of the owner, for a caller
  that is not a job of GitHub Actions (for example the workspace of the
  builder of Vũng Tàu).

A caller proves who it is in `authorization: Bearer ...` (`callerOf` of
`handler.js`):

| Caller | Token | The project |
|---|---|---|
| A job of a repository of the owner (GitHub Actions) | its ID token: `permissions: id-token: write`, the audience `https://world.mkfifo.com` | the name of its repository, in small letters |
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
repository whose `repository_owner_id` is the number of the account of
the owner (`WORLD_OWNER_ID` of `wrangler.jsonc`), not only its name.

**The address of the jobs.** The zone mkfifo.com gives the addresses of
the runners of GitHub a challenge of Cloudflare (403, `cf-mitigated:
challenge`, with each User-Agent), and a job cannot answer a challenge.
So the jobs of GitHub Actions (the shifts, the job of an issue, and the
jobs of the projects) ask the same Worker at its address on workers.dev,
`https://world.mkfifo.workers.dev`, which is not in the zone
(`workers_dev` of `wrangler.jsonc`). The audience of their ID tokens
stays `https://world.mkfifo.com`, and the URLs in the comments of the
issues are of world.mkfifo.com.

A project of GitHub Actions asks with no secret:

```yaml
permissions:
  id-token: write
steps:
  - run: |
      token=$(curl -sS -H "authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
        "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=https://world.mkfifo.com" | jq -r .value)
      curl -sS -H "authorization: Bearer $token" https://world.mkfifo.workers.dev/p/KEY.glb
```

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
  press kit, the owner). Before a commit, a render of the model and a
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
| `budget.clock` | `world` (the default): each person is busy for the days of its task on the world clock. `fast`: the log keeps the same days, but the people do not wait for them; the construction takes the results in the order of the ends of their tasks (plan 0007, D4). A site with stages or trucks keeps the world clock. |

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

The owner does this one time:

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
   the Worker reads it. A Preview uses the same bucket (the key of an
   order is the hash of its text).
4. The Worker needs the Workers Paid plan: `edge.com` is about 44 MB (with no files of the catalog and of the kit: the site serves them), and
   a build takes more CPU time than the Free plan gives. Cloudflare
   refuses a Worker of more than 64 MiB (before compression), and then
   the deploy does not reach the site with no error in CI:
   `scripts/edge.sh` stops when `edge.com` is more than 60 MiB.

To try it on this computer: `npm install && npm run build && npx
wrangler dev` (Wrangler makes a local R2). `BEAM_COM=PATH` uses a
`beam.com` of the computer in place of `npx beam.com`.
