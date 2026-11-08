# The references

A reference is a real thing with its published numbers (plan 0003):
the spec sheet of a vehicle, a house of an engineer in IFC, a standard
house of Việt Nam, an open source house. World builds its order with the
people of the node, measures the model as the standard of each number
defines it (`World.Measure`), and compares. Each number must be in its
tolerance: a number out of it is a bug of World (plan 0003, D3).

```sh
mix.com world.references          # build each reference and print each number
mix.com world.references NAME ... # some references
```

## The format

`priv/references/NAME.json`:

| Key | What it holds |
|---|---|
| `name`, `title` | The name of the reference and the real thing. |
| `sources` | Each document: its `name`, its `url`, and its `license` (`facts`: the numbers of a document that is not in the repository). |
| `order` | The order that builds it in World. |
| `level` | The level of the model (`near` by default). |
| `numbers` | Each published number: `name`, `value`, `unit`, `tolerance` (a part of the value, 0.01 by default; or `{"abs": t}` in the unit of the value), `source` (the index of its document), `standard`, and `measure`. |

The measures (`World.References.value/3`):

| Measure | What it measures | Its standard |
|---|---|---|
| `{"size": "length" \| "width" \| "height", "without": [nodes]}` | The box of the model, with some nodes left out. | SAE J1100: the overall length, the width with no mirrors, the height at curb mass. |
| `{"wheelbase": true}` | From the front axle to the rear axle. | SAE J1100, L101. |
| `{"track": "front" \| "rear"}` | From the center of one wheel to the other. | SAE J1100, W101 and W102. |
| `{"ground_clearance": {"without": [nodes]}}` | The lowest face between the axles, with no wheel. | The ground clearance of a maker. |
| `{"top": node, "span": [y0, y1]}` | The top of a node (over a span of y, if given). | The top of a screen or a roof. |
| `{"seat": node, "span": [y0, y1]}` | The lowest point of the top of a node over a span of y. | The seat height of a two-wheeler: the rider sits in the low part of the seat. |
| `{"along": axis, "from": [node, port], "to": [node, port]}` | The distance between two ports along an axis. | The stack and the reach of a bicycle frame. |
| `{"distance": [[node, port], [node, port]]}` | The distance between two ports. | The chainstay of a bicycle frame. |
| `{"angle": [node, port]}` | The angle of the axis of a port from the ground. | The head angle of a bicycle frame. |
| `{"mass": true}` | The curb mass (`World.Mass`). | The curb mass of a maker. |
| `{"takeoff": material}` | The count of a material of the bill of quantities. | The bill of quantities of a design. |

## The references now

| Reference | The real thing | Its numbers | The result |
|---|---|---|---|
| `surly_long_haul_trucker_700c_58` | The Surly Long Haul Trucker, 700c, 58 cm: the geometry chart of Surly. | Stack, reach, the head and the seat tube angles, the chainstay, the bottom bracket drop, the wheelbase, the head and the seat tube lengths. | Each in its tolerance. The wheelbase is a result of the other numbers (the front axle at the rake in front of the steering axis): 1066.6 mm, the chart 1066.7 mm. |
| `surly_long_haul_trucker_26_54` | The same bicycle, 26 in, 54 cm. | The same. | Each in its tolerance; the wheelbase 1064.1 mm, the chart 1064.0 mm. |
