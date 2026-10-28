# The factory

Xưởng is a factory for 3D models. A project sends an order, and the
factory builds the model from its parts and gives the files. The
projects (Phượt, DIY, Vũng Tàu) are on Cloudflare, so the factory is a
web service: <https://3d.mkfifo.com>. A model has a URL. When Xưởng
corrects a part, each model that uses the part changes at the same URL,
and the projects do not deploy again.

## The words

| Word | What it is |
|---|---|
| **Warehouse** | The parts that Xưởng keeps: the standard parts (bolts, nuts, extrusions, strut channel, lumber, bricks, wheels and tires), the shapes (a box, a cylinder, a lathe, a loft, a sweep, a prism), and the materials (the roles of `priv/palette.json`). |
| **Blueprint** | A family of models with options: `van`, `person`, `house`, `power_station`. Each option has a name, a type, a default, a unit and a range or a list. The data of a blueprint (the sizes of each make, the traces of a body) is in `priv/data`, not in the code. |
| **Order** | A JSON document: a blueprint and its options, or a drawing, and the parts to fit into its slots. |
| **Drawing** | The design of a model that Xưởng has no blueprint for: its parts (shapes, standard parts, orders of blueprints, supplied parts) and its nodes (the JSON form of `Xuong.Assembly`). |
| **Supplied part** | A mesh that the order gives (GLB, OBJ or `.wings`), with its ports. |
| **Slot** | A port of a blueprint where another order fits: the engine bay of a van, its roof, the seat of a scooter for a rider. |
| **Receipt** | What the factory gives with the files: the full order with each default, the version of Xưởng, the sources of each part, where each part comes from (blueprint, drawing, supplied), and the hash of the order. |

## The four kinds of work

| A real factory | Xưởng | When |
|---|---|---|
| Products of the catalog | An order of a blueprint | The common models, with sources and tests. |
| Build to print | An order with a drawing | A model that Xưởng has no blueprint for. No pull request is necessary. |
| Parts of the customer | Supplied parts in a drawing | A shape that the warehouse cannot make. |
| The engineering department | A pull request to Xưởng | A drawing that many orders use becomes a blueprint, with its sources and tests. |

An order is data, never code. Xưởng runs no code from an order.

## The URLs

| URL | What |
|---|---|
| `/` | The review page: each model of the catalog, its levels, its joints and its parts. |
| `/models/list.json` | The names of the models of the catalog. |
| `/models/NAME.glb`, `NAME.mid.glb`, `NAME.far.glb` | A model of the catalog at each level. |
| `/models/NAME.parts.json` | The list of its parts. |
| `/palette.json` | The default color of each material role. |
| `/version.json` | The commit of Xưởng that the site has. |
| `/blueprints` | Each blueprint with its options: the type, the default, the unit, the range or the values. |
| `POST /orders` | An order in JSON. The answer gives its hash, the full order (with each default), and the URLs of its files; or 422 with the errors. |
| `/o/HASH.glb`, `.mid.glb`, `.far.glb`, `.parts.json`, `.receipt.json` | The files of an order of `POST /orders`. |
| `/m/BLUEPRINT.glb?OPTION=VALUE` (and the other files) | An order in the URL: `color.ROLE=%23rrggbb` gives a color, `joint.NAME=50` a joint, and `A,B` a list. |
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
and joints), `person`, `house`, `extrusion`, `strut` and `l_track`.

Each file has `Access-Control-Allow-Origin: *`, an `ETag`, and
`Cache-Control: public, max-age=300, stale-while-revalidate=86400`. So a
project gets a correction at most 5 minutes after the deploy of Xưởng,
and it can use a copy in its cache while it gets the new file.

## The contract

The other projects use the names of the options, the slots, the joints,
the ports and the parts. A correction can change a shape, a size or a
color, but not these names. A test keeps a copy of the names of each
model of the catalog and compares them. A change of a name makes a new
version of the blueprint (`van@2`): the old version stays.

## Where the builds run

| Order | Where |
|---|---|
| A model of the catalog | CI builds it natively (`mix xuong.build --check`), and the files are in the repository. The Worker serves them as static files: no build at a request. |
| An order at a request | The VM of Xưởng (beam.com, WebAssembly) in a Durable Object of the Worker builds it (`worker.js`, `handler.js`, `Xuong.Service`). The file goes into R2 with a key of the commit of the deploy and the hash of the order, so the next request reads it from R2, and a new deploy builds it again. |

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

The time is not a problem. The memory is: a Worker has 128 MB. The mid
and far levels and the small items fit; the near level of a large model
does not. In `wrangler dev`, the near level of a person (3 MB) took
0.9 s and 124 MB, and a small house took 0.2 s. Step F4 makes the build use less memory. If that is not
sufficient, a builder with more memory (a Cloudflare Container with
the native beam.com) builds the large orders.

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
- For later, the paper names what Xưởng has now: shapes from parts,
  people with a skeleton and layers of clothes, and joints (a steering
  wheel that turns the wheels, a door that slides).

What it means for Xưởng:

| Topic | Cube | Xưởng |
|---|---|---|
| The source of a shape | Learned from about 1.5 million assets (Objaverse and Roblox). | Standards, data sheets, drawings and photos. |
| Sizes | A box from the scene; the shape inside it is learned. | The real sizes of each part. |
| Parts, joints, the list of the parts | Not yet ("future work"). | Yes. |
| Shapes that are not made from parts (a rock, a tree, a statue, a dog) | Yes. | No. |
| Where it runs | A GPU. | The VM at the edge. |

So the two agree in two ways:

1. **The order is the scene graph.** The JSON scene of Cube and an order
   of Xưởng have the same idea: a language model writes the layout, and
   a builder makes each object. An order of Xưởng gives more (options
   with ranges, slots, joints), and the check gives each error back to
   the model (step F7).
2. **Cube can supply parts.** A shape that the warehouse cannot make can
   come from Cube, made one time on a GPU, cleaned
   (`Xuong.Mesh.clean/1`), and kept as a supplied part (step F6) with its
   text as its source. It is not a measured shape: the receipt says so.
   Read the license of the weights before a use.

## The steps

| Step | What |
|---|---|
| F1 | This file. The Worker at `3d.mkfifo.com` serves the catalog and the review page. Done. |
| F2 | Blueprints, orders and the receipt (`Xuong.Factory`), `mix xuong.order`, the builder in the VM, the cache in R2. People, houses and framing are the first blueprints: they have options already. Done. |
| F3 | The van blueprint, from the traces of DIY and from photos: the Ford Transit, the Mercedes-Benz Sprinter and the Ram ProMaster, with their slots. |
| F4 | People in the release (the data of MakeHuman in `priv/`), and less memory for the near level. |
| F5 | Drawings. |
| F6 | Supplied parts (with the reader of `.wings` of step 5 of `README.md`). |
| F7 | Orders from text: a language model writes an order or a scene from `/blueprints`, and the errors of the check go back to it until the order is correct. |
| F8 | Scenes: a list of orders, each with its place and its turn, and joins at slots. |

## The setup on Cloudflare

The owner does this one time:

1. In the dashboard of Cloudflare, Workers and Pages, make a Worker from
   the repository `sntran/xuong` (Workers Builds). The build command is
   `npm run build`, the deploy command is `npx wrangler deploy`.
2. `wrangler.jsonc` has the custom domain `3d.mkfifo.com`: the deploy
   makes its DNS record and its certificate in the zone `mkfifo.com`.
3. Make the R2 bucket of the orders before the first deploy:
   `npx wrangler r2 bucket create xuong-orders`. It needs no public
   access: the Worker reads it.
4. The Worker needs the Workers Paid plan: `edge.com` is about 45 MB, and
   a build takes more CPU time than the Free plan gives.

To try it on this computer: `npm install && npm run build && npx
wrangler dev` (Wrangler makes a local R2). `BEAM_COM=PATH` uses a
`beam.com` of the computer in place of `npx beam.com`.
