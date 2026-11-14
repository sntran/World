# Plan 0018: the street Quang Trung of Vũng Tàu as it is

Status: In progress. The survey is made, and the south block is in the
catalog: the office of the port at number 2, and the row of the
numbers 4 to 26. The south wing of the Grand Hotel is the first part
of step 3. (The owner, 2026-11-14: "Let's
build Quang Trung street".)

Depends on: plan 0016 (a house and a street from rules), plan 0014 (a
model in parts), plan 0012 (the models of Vũng Tàu).

## 1. Goal

A person who knows the street of the Front Beach (Bãi Trước) sees it in
World: each building in its place, with its storeys, its colors and its
use, on its sidewalk, with the park and the sea across the road.

## 2. What the owner asked

"Let's build Quang Trung street": the real street, after the rules of
plan 0016 made a street that is no real street.

## 3. The survey

The data is `priv/surveys/quang_trung.json` (2026-11-14): 27 rows, 23
on the side of the town and 4 on the side of the sea, from the south
end to the north end. Each value has a mark that says where it comes
from: OpenStreetMap, the Microsoft building footprints, a photo, a web
page, or a guess. The photos are not in the repository (33 are from
Wikimedia Commons with open licenses; 6 have all rights reserved and
were only read).

### 3.1 The street

- **1,136 m**, from Trương Công Định and Hạ Long (south) to Trần Phú
  (north-west). Its cross streets from the south: Nguyễn Trãi (126 m),
  Nguyễn Du (242 m), Thống Nhất (375 m), Lê Lợi (421 m and 464 m), Ba
  Cu (689 m), Lê Quý Đôn (777 m), Hoàng Diệu (869 m), Lê Ngọc Hân
  (968 m).
- **Only the side of the town has buildings**, with the even numbers 2
  to 40. The side of the sea is the park Bãi Trước, walks and the sea
  wall.
- **The north part (609 m)** is one road of 4 lanes, 17 m to 19 m wide.
  **The south part (527 m)** is two roads of about 10 m, one for each
  direction, with a median of about 3 m (a hedge, a row of Araucaria,
  lamps).
- **The sidewalk of the side of the town** is about 5.5 m, with tiles.
- **Trees:** old Terminalia catappa (bàng) on the sidewalk of the park
  and in front of the Grand Hotel, Araucaria on the median and on the
  side of the sea, casuarina at number 40, coconut palms in the park.

### 3.2 The lots of the side of the town

It is not a street of row houses: 21 buildings, one park of 225 m and
one empty lot of 98 m. Only one block is a row of narrow houses.

| Rows | From the south (m) | What | Storeys | Type |
|---|---|---|---|---|
| T01 | 12 to 40 | Number 2: the office of the port (Cảng vụ Hàng hải), white and light blue, a porch at the corner | 5 | `office_block` |
| T02 to T11 | 40 to 110 | Numbers 4 to 26: a row of bars, restaurants and shops; the corner house is white | 2 (a guess), 3 at the corner | The types of plan 0016 |
| T12, T13 | 137 to 226 | The Grand Hotel: a south wing with galleries, a fore court, a main block with a roof of yellow tiles | 3 | `hotel_gallery`, `colonial_villa` |
| T14 | 242 to 325 | The House of Children: cream and teal, wide stairs, a tower, a yard with a gate | 3 | `civic_hall` |
| T15, T16 | 325 to 421 | A long low block, and an office | 2, 3 (guesses) | `pavilion`, `office_block` |
| T17 | 421 to 464 | A yellow villa with a roof of red tiles in a yard (OSC Việt Nam) | 2 | `colonial_villa` |
| T18, T19 | 464 to 777 | The park Tam Giác, and a villa in its park (the house of the traditions of the revolution) | 2 | `colonial_villa` |
| T20, T21 | 777 to 861 | The Rex Hotel behind its garden, and the Royal Hotel (number 36) | 9, 3 | `hotel_slab`, `hotel_gallery` |
| T22, T23 | 870 to 1,122 | Empty land, and a hotel in construction at number 40 | 14 so far | `hotel_slab` |

### 3.3 What the survey does not know

- **The lots of the row 4 to 26.** Its length (70 m) and its depth are
  measured, and 5 of its 12 numbers have an address. The limits, the
  width, the storeys, the roof and the colors of each lot are not seen
  in a photo.
- **Three buildings** are not seen in a photo from the street (T15,
  T16, and a low building next to the Royal Hotel).
- **Most photos are from 2014 and 2015.** No service of photos from the
  street could be read.
- **The widths of the road, of the sidewalks and of the median** are
  from the scale of photos, not from a record.

## 4. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | The survey is data of the repository, with the mark of each value and its sources. | A model of a real place must say what is measured and what is a guess. |
| D2 | The plan of a street takes the lots of a survey (`lots`): what is known stays, and the seed makes each other choice. One building on two lots is two lots with the same choices (`same`). | The rules of plan 0016 made each choice from the seed. A real street knows some of them. |
| D3 | A house has a use. With the use `bar` (a bar, a restaurant or a shop), its ground storey is an open front with a counter and a shelf of light, and it has a sign and an awning. On a sidewalk of 4.5 m or more, a parasol with a table stands in front of it. | The row 4 to 26 is all bars, restaurants and shops with open fronts and tables on the sidewalk. |
| D4 | A long row is some drawings of 5 lots at the most (the option `only`), each about its own middle. | A drawing has 16 parts with an image at the most. |
| D5 | The street is built block by block, from the south. Each block is a commit with its shots. | The street has six types of building that the rules do not have. Each is a model from photos, as the statue was. |

## 5. Steps

1. **The survey, the plan from its lots, the use `bar`, and the block
   of the numbers 4 to 26** (three models: `quang_trung_4_10`,
   `quang_trung_12_18`, `quang_trung_20_26`). Done: section 7.
2. The office of the port at number 2 (`cang_vu_vung_tau`), from its
   footprint and two photos. Done: section 8.
3. The Grand Hotel: its south wing (`khach_san_grand_canh_nam`, done:
   section 9), then its fore court and its main block.
4. The House of Children, the low block, the office, the villa of OSC.
5. The villa in its park, the Rex Hotel, the Royal Hotel.
6. The ground: the roads with the median, the sidewalks, the park Bãi
   Trước, the park Tam Giác, the sea wall, the trees and the lamps,
   from the tile of OpenStreetMap.
7. The place `quang_trung`: each model at its place on the ground.

## 6. Open questions for the owner

- **Photos of the row 4 to 26, and of the buildings that the survey
  did not see.** One photo of each front from the street makes each lot
  true.
- **The year of the model.** The hotel at number 40 is in construction
  (2024). The villas that stood there in 2017 are gone.
- **How near.** The whole street at the near level is many large
  files. A block at near and the others at mid is the usual way.

## 7. The measure of step 1

One machine with 4 schedulers.

| Model | Lots | Long (m) | Triangles (near, mid, far) | Files (near, mid, far) |
|---|---|---|---|---|
| `quang_trung_4_10` | 4, 6, 8-10 | 23.3 | 117,000 / 18,600 / 3,934 | 10.9 / 2.0 / 0.45 MB |
| `quang_trung_12_18` | 12, 14, 16, 18 | 23.2 | 117,000 / 18,600 / 4,160 | 10.5 / 1.9 / 0.46 MB |
| `quang_trung_20_26` | 20, 22, 24-26 | 23.3 | 117,000 / 18,600 / 4,092 | 11.4 / 2.0 / 0.49 MB |

- Each model builds in about 5 min at its three levels (13 min while
  the full check runs on the same machine).
- A parasol has a pole of 7 cm and a table of 4 cm: with cells of 2 cm
  the pole was a spike and the table was lost. The things on the
  sidewalk have cells of 12 mm at near and at mid, and they are not
  there at far.

What this block is not:

- **Not the true fronts.** The order, the numbers and the uses of the
  lots are true. The corner house has its storeys and its color. Each
  other choice is from the seed.
- **The signs have no words.**
- **The corner house is two houses of the rules** with the same
  choices: it has no front on Nguyễn Trãi.

## 8. The measure of step 2: the office of the port

`cang_vu_vung_tau` is a drawing from edits, as the statue is: not from
rules.

| What | From |
|---|---|
| The plan: 9 corners, 21.3 m on Quang Trung, a corner cut in three faces | The footprint of OpenStreetMap (way 259732719) |
| 5 storeys; the corner tower one storey higher; white with light blue parts; glass with a blue tint | Two photos of 2014 (Wikimedia Commons, CC BY 3.0) |
| The front on Quang Trung: a blue part with wide windows, two parts with loggias, the bay of the stair in glass under the sign of the shipping agency | The photo from the park |
| The corner: the tower of glass between bands of grey washed stone, a white pier at each side, the porch on two round columns with the blue board | The photo from the junction |
| The south front: four windows at each storey on blue ledges | The photo from the junction |
| The heights (4.4 m, then 3.2 m for each storey), the sizes of the windows | The scale of the photo from the junction: a guess |
| The back and the east walls, the roof behind the parapet, the two masts | A guess: no photo |

| Level | Triangles | File |
|---|---|---|
| near | 39,000 | 4.8 MB |
| mid | 6,200 | 1.3 MB |
| far | 800 | 0.19 MB |

- 382 edits in the body, 11 on the roof, and 17 for the two masts (a
  detail of the near level). The three levels build in about 3 min.
- A paint is in the order of the edits: the blue of a wall must be
  before its windows. The first build had blank windows on two piers.

What it is not:

- **The boards have no words**, but for the four letters on the roof.
- **The Araucaria trees in front of it** come with the ground (step 6).
- **The paint is that of 2014.** In 2021 the blue parts were bands.

## 9. The measure of step 3, first part: the south wing of the Grand Hotel

`khach_san_grand_canh_nam` is a drawing from edits. One function makes
a front of equal bays on a wall, so the same function can make the
Royal Hotel (step 5).

| What | From |
|---|---|
| The plan: 39.7 m on Quang Trung, 20.3 m deep | The footprint of OpenStreetMap (way 118946705) |
| 3 storeys: a low ground storey between piers, a brown band, two storeys of loggias between orange pilasters, rails of iron, pale yellow walls, a cornice | A photo of 2015 (Wikimedia Commons, CC BY 3.0) |
| A low roof of yellow tiles behind the cornice | Two photos from far |
| The bed behind a low wall of stone, and the stone with the name | The same photo |
| The heights (12 m to the top of the cornice), 9 bays on Quang Trung | The scale of the photo: a guess |
| The front on Nguyễn Trãi (4 bays), the north end, the back, the pattern of the rails | A guess |

| Level | Triangles | File |
|---|---|---|
| near | 68,500 | 8.4 MB |
| mid | 8,300 | 1.1 MB |
| far | 1,100 | 0.21 MB |

- 372 edits in the body, and 390 tubes for the rails of the 26
  loggias (a detail of the near level: 24,000 triangles). The three
  levels build in 10 min while the full check runs on the same
  machine; the rails are the largest part.

What it is not:

- **No plants.** The cycads of the bed and the trees of the sidewalk
  come with the ground (step 6).
- **The stone has no name on it.**
- **At mid and far the loggias have no rails.**
