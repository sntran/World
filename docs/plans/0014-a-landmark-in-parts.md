# Plan 0014: a landmark in parts, as a site builds it

Status: Done (2026-11-13), but for the face as a copy and the budgets
of the basket boat. Section 10 has the measure. (The owner,
2026-11-13: "So far we have only built small to medium models, but what
about buildings, landmarks? Can we build the 'Tượng Chúa giang tay' in
Vũng Tàu? Do deep research for specs as I don't have them. Make sure
the statue match real life. And if there are ways to split the work,
like a real construction site works, or Dreams has great approach,
learn from them to apply the BEAM.")

Depends on: plan 0013 (long shapes), plan 0012 (the crews, the
surfaces, the outlines), plan 0005 (the measures of the statue from a
drone video), plan 0004 (the earlier statue).

## 1. Goal

World builds a landmark from edits: the statue of Christ the King on
Núi Nhỏ, Vũng Tàu, with the sizes of its sources and the forms of its
photos. The work is split as a real site and Dreams split it: the
model is parts, each part is a sculpture of its own, and the parts are
made at the same time.

## 2. What the owner asked

1. A landmark, not only small and medium models: the statue of Vũng Tàu.
2. Research for its specifications.
3. The statue as in real life.
4. Ways to split the work, from a real site and from Dreams, for the BEAM.

## 3. The research

### 3.1 The sizes of the statue

The most important finding: **the 32 m of the sources is the whole
monument, not the figure.** The site of the pilgrimage centre
(kitovungtau.com, the history page) gives the parts:

| Part | Size | Source |
|---|---|---|
| Base (from the ground to the foot of the rail) | 6 m | kitovungtau.com |
| Dome under the feet | 3 m | kitovungtau.com |
| Figure, from its soles to the top of its halo | 22 m | kitovungtau.com |
| Lightning rod over the halo | 1 m | kitovungtau.com |
| From fingertip to fingertip | 18.4 m | kitovungtau.com, and most sources (en.wikipedia: 18.3 m) |
| A hand; the middle finger; the width of the feet | 2.2 m; 1.1 m; 1.1 m | kitovungtau.com |
| Steps inside | 133 | kitovungtau.com, vi.wikipedia (two sources: 130) |
| Rays of the halo (the lightning protection) | 9 | kitovungtau.com |
| Ground under the base | 136 to 138 m over the sea | SRTM, OpenStreetMap |
| The direction that the statue looks | about 167 degrees (south-south-east) | OpenStreetMap (the last stair), two photos with GPS |

Other values of the sources: "a statue of 32 m" with no parts
(vi.wikipedia, most travel sites), "32 m on a platform of 4 m"
(en.wikipedia), "the statue alone 25 m, the base 7 m, measured by the
building crew" (a magazine article of 2008: this is 22 + 3 and 6 + 1).

Two checks agree with the parts of the pilgrimage centre:

- On a front photo with a long lens (Wikimedia Commons, by trungydang,
  CC BY 3.0), with the three windows for its perspective and 18.4 m for
  its scale, the figure is 22 m (+/- 1 m) from its soles to the top of
  its halo.
- The measures of plan 0005 (one drone video, COLMAP) have the same
  form. Plan 0005 took 18.4 m for the distance from cuff to cuff. With
  18.4 m from fingertip to fingertip, each of its heights is 0.78 times
  as large, and then they agree with the photo in 0.5 m: the crown at
  20.5 m (the photo: 20.8 m), the top of the halo at 21.5 m (22.0 m),
  a hand of 2.0 to 2.1 m (the source: 2.2 m), the dome 2.9 m (3 m).

So the earlier model `tuong_chua_kito_vua` (plans 0004 and 0005) is
about 28% too large. This plan does not change it (section 9).

The heights and the widths between the sizes of the sources are
measured on that front photo, each in about 0.2 m (m over the soles):
the top of the head 20.8, the eyes 19.3, the tip of the beard 17.5, the
shoulders 17.1, the cuffs 16.4 to 18.6, the heart 15.0 to 16.1, the
belt 13.4, the ends of the cape 13.1, the windows 11.4, 9.3 and 7.2,
the ends of the mantle 2.7, the band of the hem 1.0 to 1.6; from cuff
to cuff 14.15, the halo 4.6 across, the cape 5.6 wide, the body 5.0
under the cape and 3.5 at the hem.

No source gives: the depths (one side photo from below), the size of
the head, the walls, the lifts of the concrete, a drawing, a scan.

### 3.2 How it was made

Reinforced concrete, hollow, cast in place in a scaffold in 1974 and
1975 by about 50 workers, with no machines; the surface ground from
the top down as the scaffold came down; finished in 1992 to 1994. The
model and the four reliefs: the sculptor Văn Nhân. The concrete: the
engineer Nguyễn Quảng Đức. The robe and the hair are washed stone
(river pebbles of 3 mm); the face, the hands, the feet and the heart
are white ground stone with marble chips (kitovungtau.com;
vi.wikipedia; a magazine article that quotes the booklet of the parish
of 1994).

### 3.3 How a large work is split

| From | What it does | In World |
|---|---|---|
| Dreams: a scene is many sculpts, and each sculpt has its own grid and its own detail (Evans, SIGGRAPH 2015; the docs of Dreams: Adjust Detail) | The cost is the surface times the detail, so a creator cuts a large thing into sculpts | D1: the model is parts, each a sculpture with its cells |
| Dreams evaluates one sculpt at a time on the GPU | | D2: World makes the parts at the same time, each with its crew |
| Rio, 1922 to 1931: the head and the hands were made at full size in a workshop, in pieces, away from the body | A fine part is made alone | D1: the head and the hands have cells of 2 cm, the robe 5 cm |
| A site: the largest part first has the crane; each lift has an inspection before the pour | Order by size; a gate for what cannot be seen later | D2 (the largest first), D5 (a test of the sizes) |
| Nanite and meshoptimizer: clusters with locked borders are simplified at the same time, and the groups change at each level | No serial pass | Not done: section 9 |
| Textures: an image for each part (UDIM) | Texels where the eye looks | D3: an image and a role for each part |

## 4. Out of scope

- The inside of the statue (the stair of 133 steps, the rooms of the
  base): the earlier model has them.
- The figures of the four reliefs of the base (panels of the color of
  gold with no figures here).
- The hill, the stairs, the cannons, the Pietà.
- A change of the earlier model and of its time lapse.
- The collapse with no serial pass, a cache of each part, a part on
  another node (section 9).

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | The statue is eight parts, each a node with a sculpture of its own: the base, the dome, the robe, the cape, the sleeves, the hands, the head, the halo. The parts do not blend; each goes into the next one at a line of the statue (the hem, the cuff, the collar). | The elements of Dreams; the workshop of a site. Cells of 2 cm for the face and the hands and of 5 to 7 cm for the large planes: one sculpture with cells of 2 cm would have about 16 times the cells. |
| D2 | `World.Drawing.build/2` makes the sculptures of a drawing at the same time: each in a process of its own (a site with its crew), the largest first. The gate of the node says how many work at one time. A model with one sculpture is made as before. | The actor model of the BEAM: a part is a process, a crew is its streams of tasks. The parts of one sculpture that work in one process (the serial parts) now work at the same time as those of the other parts. |
| D3 | Each part has a role of the palette of its own (`part_01` to `part_16`), so it has its own images. | A material has one set of images; a part has its own texel size. |
| D4 | The sizes: first the sizes of the pilgrimage centre, then the measures on the photo, then the measures of plan 0005 at the right scale, then a guess. The drawing says which is which. | Section 3.1. |
| D5 | A test builds the far level and checks the sizes of the parts against the sources (the height, the span, the base, the dome, the head, the cuffs, the halo). | The inspection of a site: a fault of a size is found in the part. |
| D6 | The mirror copy of an outline has its points across its x, and the mirror copy of a prism with an odd count of sides has its y the other way. | A fault: the copy of an outline was not a mirror, so the second sleeve was not there. |
| D7 | The distance to a side of an outline is from the cross product next to the side: it is 0 to the last bit at a point of a level or an upright side. | A fault: a point of a flat face of a `revolve` on a plane of the grid was 1e-16 over or under 0, the mesh had two sheets there, and the collapse did not reach its budget (the dome: 11,400 triangles for 4,000; the basket boat of plan 0012 at mid and far). |
| D8 | The occlusion of a texel is the change of the field from the place of the texel, not the field with 0 at the place. | A fault: a place on a triangle a little under the surface was dark, as a crease. |
| D9 | When no scale of the charts fits the image, each chart is one texel (the bake does not stop). | A fault: a division by a scale of 0 for a part with many small charts in a small image. |
| D10 | The new model has a new name, `tuong_chua_giang_tay` (the name that the people of Vũng Tàu use). | The earlier model has the tests, the measures and the time lapse of plans 0004 to 0006. |
| D11 | The halo goes round the head and leans to the front by 30 degrees: its top is over the front of the crown, its sides pass the sides of the hair, its lower part goes down behind the neck, and the arms of its cross join the hair. | The owner (2026-11-13): "the halo is not behind the head". The close photos show it, and the measure of plan 0005 gave the lean (the top 1.5 m in front of the middle, at its scale). D6 of plan 0004 (the halo behind the head) was wrong, and the first model of this plan had it wrong too. |

## 6. Requirements

| # | Requirement |
|---|---|
| R1 | The statue is in the catalog, from edits only, with its sources. |
| R2 | Its sizes are those of section 3.1: the test of D5 passes. |
| R3 | Its forms are those of the photos: shots next to the front photo. |
| R4 | The parts are made at the same time; a test with a model in two parts. |
| R5 | The faults D6 to D9 have tests, and each sculpture of the catalog meets its budget. |
| R6 | The time of the build is measured. |
| R7 | The full check passes. |

## 7. Steps

1. The research (section 3).
2. A model in parts: D2, D3.
3. The statue with the sizes of plan 0005; then, after the research,
   with the true sizes.
4. The faults that the statue showed: D6 to D9.
5. The documents, the measure, the full check.

## 8. Acceptance criteria

- R1 to R7, with the numbers of section 10.
- `mix precommit`, `mix world.build --check` and `npm test` pass.

## 9. Open questions

- **The earlier model `tuong_chua_kito_vua` is about 28% too large**
  (section 3.1). Its sizes, its tests and its time lapse use 18.4 m
  from cuff to cuff. The owner decides: give it the true scale, or put
  the new model in its place.
- **The face is a face, not the face of the statue.** It has the form
  of the photos (a long face, a moustache, a short beard, the hair as a
  veil), but it is not a copy. A scan or a set of close photos from each
  side makes it true.
- **The inside** (the stair, the windows that light it, the balconies
  as rooms) and **the figures of the reliefs**.
- **The surface of round edits that blend.** A relief of a surface
  (`plaster`) on many round edits that blend (the hair) made rough
  marks; the hair has no relief now.
- **The serial pass of the collapse** (plan 0013) and the three
  proposals of the research that are not done: a collapse in rounds
  with regions that move (as Nanite), a cache of each part by its hash
  (a change of the face then builds only the head), and a part that
  goes to another node as a whole.
- **The far level** is 810 triangles in eight parts with eight small
  images. One part and one image for the far level are better for a
  skyline.

## 10. The measure

One machine with 4 schedulers (the gate lets 2 sculptures work at one
time).

### The statue (R1, R2, R6)

| Part | Edits (with copies of a repeat as one) | Cells: near, mid, far | Triangles: near, mid, far | Image: near, mid, far |
|---|---|---|---|---|
| `de`, the base, with its rail as a detail | 13 and 11 | 7, 12, 25 cm (the rail: 3 cm) | 16,000; 1,500; 260 | 1024, 512, 128 |
| `vom`, the dome with its stair | 5 and 4 | 5, 10, 20 cm | 4,600; 700; 60 | 512, 256, 64 |
| `ao`, the robe with the mantle and the feet | 67 | 5, 8, 16 cm | 14,000; 2,500; 140 | 2048, 1024, 256 |
| `ao_choang`, the cape with the heart | 21 | 4, 8, 16 cm | 8,000; 1,500; 70 | 1024, 512, 128 |
| `tay_ao`, the sleeves | 13 | 4, 8, 16 cm | 9,000; 1,600; 80 | 1024, 512, 128 |
| `ban_tay`, the hands (a group, two times) | 12 in the group | 2, 4, 8 cm | 9,000; 1,200; 180 | 1024, 256, 128 |
| `dau`, the head (a group) | 26 in the group | 2, 4, 8 cm | 18,000; 2,500; 110 | 2048, 512, 128 |
| `hao_quang`, the halo, with its rods as a detail | 4 and 10 | 3, 6, 6 cm (the rods: 1.5 cm) | 7,500; 1,300; 240 | 1024, 256, 128 |
| All | | | 86,100; 12,800; 1,140 | |

| | Near | Mid | Far |
|---|---|---|---|
| The file | 22.5 MB | 4.1 MB | 0.36 MB |

- The near level builds in 150 s; the three levels and the files with
  `mix world.build` in 3 min 29 s. The far level alone (the test of the
  sizes) builds in 6.5 s.
- The test of D5 at the far level: the top of the halo at 31.0 m over
  the ground (in 0.3 m), 18.4 m from fingertip to fingertip (in 0.6 m),
  the base 6 m, the dome 3 m, the top of the head at 20.8 m, 14.15 m
  from cuff to cuff, the halo 4.6 m across.
- The time of the parts one after the other is not measured (the
  parts at the same time are the only path now).

### The faults (R5)

| Fault | Before | After |
|---|---|---|
| A cone as a `revolve`, 7.8 m across, cells of 5 cm, a budget of 4,000 | 155,788 faces before the collapse, 1,596 edges in four faces, 21,732 triangles after | 125,820 faces (as the native cone), each edge in two faces, 4,000 triangles |
| The dome of the statue, a budget of 4,000 | 11,400 triangles | 4,000 |
| The mirror copy of an outline | The same outline at the other side: the second sleeve was not there | A mirror |
| Gray marks on the flat faces (the occlusion) | In each large flat face | Only next to some sharp edges |

The basket boat of plan 0012 (`thung_chai_edits`) still does not meet
its budgets at mid and far (6,850 for 4,000; 1,740 for 600): its wall
of 3.5 cm is thinner than two cells there. It needs the same cells at
each level (the rule of plan 0013).

The files of the 17 sculptures of the catalog before this plan are
built again: the exact distance of an outline, the occlusion and the
mirror change their bytes (the Toyota Vios had the pillars of its
right side as copies with no mirror).

### The requirements

| # | Result |
|---|---|
| R1 | Met. |
| R2 | Met: the test of the sizes passes. |
| R3 | Met for the form of each part (shots next to the front photo of Wikimedia Commons). The face is not a copy of the face of the statue (section 9). |
| R4 | Met: a model in two parts, each with its role and its image, and the same bytes each time. |
| R5 | Met for the four faults; not for the budgets of the basket boat (a thin wall). |
| R6 | Met. |
| R7 | Met: the full check passed on the tip before the push. |
