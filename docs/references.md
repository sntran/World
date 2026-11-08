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
| `honda_vision_standard` | The Honda Vision 110 of Việt Nam, the standard version: the page of Honda Việt Nam. | The length, the width, the height, the wheelbase, the seat height, the ground clearance, the curb mass. | Each in its tolerance. To agree with the sheet, the seat and the back of the body went down by 6 cm (the seat height: 758 mm, the sheet 761 mm), and the folded stand and the engine case went up (the ground clearance: 152 mm). The curb mass is 87 kg, the sheet 94 kg: the tolerance is 10%, because the parts that the drawing does not show have masses by estimate. |
| `honda_vision_sport` | The Sport version of the same scooter: the page of Honda Việt Nam. | The same. | Each in its tolerance, with its own blueprint (`scooter_sport.json`): the standard version on a front wheel of 16 in, 24 mm higher, its front axle 22 mm to the front, and a front fender 25 mm larger. The curb mass is 88 kg, the sheet 97 kg (10%). |
| `royal_enfield_himalayan_411` | The Royal Enfield Himalayan 411 with ABS: the sheets of dealers (the page of the maker is gone). | The length, the width, the height, the wheelbase, the seat height, the ground clearance, the curb mass. | Each in its tolerance. To agree with the sheets, the rear fender and the plate went 8 cm back (the length), the bars and the grips went in (the width), the mirrors went down (the height), the seat of the rider and the frame under it went down by 6 cm (the seat height), the monoshock turns up from the swing arm, and the chain is a part of its own (it turns with the rear wheel, so it is not in the ground clearance). The curb mass is 182 kg, the sheets 182 to 199 kg (10% of 199 kg). |
| `chevrolet_bolt_ev_2022` | The Chevrolet Bolt EV of 2022: the specifications of Chevrolet, and the curb weight of a database of electric cars. | The length, the width, the height, the wheelbase, the tracks (SAE J1100), the curb mass. | Each in its tolerance. The mirrors and the license plates are nodes of their own, so the width has no mirrors and the length no plates (4167 mm with the bumpers). The curb mass is 1520 kg, the sheet 1628 kg (10%): the battery pack has the mass of GM (435 kg); the structure inside the skin, the inside and the suspension are estimates. No source of Chevrolet gives the ground clearance, so the reference has none. |
