# Plan 0017: people: the body of MakeHuman with parts from edits

Status: In progress. The first parts are made (2026-11-14, section 8;
the owner: "Let's build the parts first."), and the hair has strands
(section 9). The plan is the answer to
a question of the owner, from research, and the steps that it
proposes. (The owner, 2026-11-13: "What's about people? Can we use the
Dream's way to build realistic people, better than MakeHuman?")

Depends on: plan 0010 (a sculpture with bones, the maps), plan 0014 (a
model in parts), the people of `World.People`.

## 1. The answer

**Not as Dreams does it, and not for the body and the face at the near
level. Yes for hair, hats, helmets, shoes, thick clothes and the things
that a person carries, and for the mid and far levels. The best person
is the two together.**

## 2. The evidence

### 2.1 What Dreams does

- A puppet of Dreams is a set of rigid sculptures, one for each part of
  the body, on ball joints and bolts. It has no skin weights and no
  blend between two sculptures (the documents of Dreams for puppets,
  indreams.me).
- The makers left deformation out of the edits on purpose: the edits
  are a simple list with no change of the space (Alex Evans, "Learning
  from Failure", SIGGRAPH 2015, the notes to slide 23).
- A joint is hidden by a ball of the same place in the two parts, by
  overlap, by clothes and by the soft look of the renderer. A face
  moves by keyframes that move, show and hide rigid pieces.
- The people of Dreams that look real are still heads. The puppets
  that move are stylised.

### 2.2 What World does today

- **A sculpture with bones is one skinned mesh** (plans 0009 and 0010):
  linear blend, 4 bones for a point at the most, weights from the
  bones of the edit that makes the surface. The body plan `biped` has
  16 bones and the clips `walk`, `run` and `idle`. So World is past
  Dreams here already.
- **A person** is the base mesh of MakeHuman (CC0): 13,380 points at
  near, 856 targets, 53 bones with the weights of MakeHuman, 33 units
  of the face, a blink, 15 visemes, the poses `stand`, `sit`, `ride`
  and `drive`. Its weak points are in the code: clothes that need holes
  in the body under them, hair as cards with two passes of alpha, and
  at mid and far the clothes only as colors.
- **The one human form from edits** is the head of the statue (plans
  0014 and 0015): it took close photos and many tries to make a face
  of stone that reads right, with cells of 2 cm for a head of 3 m. A
  living face needs cells of 1 mm, and it must blink and speak.

### 2.3 What a small open project can use by law

| Model | License | Use |
|---|---|---|
| MakeHuman and MPFB2 | CC0 (some clothes CC BY) | In use: stays the base. |
| Anny (NAVER LABS Europe, 2025), on the data of MakeHuman | Apache-2.0, data CC0 | Its fit of ages to the statistics of the WHO can be added. |
| FLAME 2023 Open (a head from scans) | CC BY 4.0 for this version only | A head with a real identity, later, with a credit. |
| SMPL, SMPL-X, STAR, SUPR, THuman | Not for commercial use | Not usable. |
| MetaHuman, Daz, Human Generator | Not open | Not usable as data of World. |
| MB-Lab | AGPL-3 for the models that it makes | Not usable. |

Each realistic body that the law lets World use is a mesh with data in
it. The realistic bodies as fields are networks from scans, with
licenses for research. No one makes a realistic person from a list of
200 simple shapes: such a list makes a mannequin.

The sizes of people of Việt Nam that are public: the mean heights of
the national survey of 2019 and 2020 (men 168.1 cm, women 156.2 cm),
and papers on the face (Le, Farkas and others, 2002). A full table of
the body is not public.

## 3. The proposal

| # | Decision | Why |
|---|---|---|
| D1 | The body, the skeleton, the weights and the face of MakeHuman stay. | Section 2: nothing that World can use is better for a person who walks, sits, rides and speaks. |
| D2 | A person can have parts from edits: hair as masses, a nón lá, a helmet, flip-flops, a mask, a bag, and thick clothes (a jacket, a rain cape). The edits are in the axes of a bone or of the body. | The field is strong where the people of today are weak: no holes, no cards, true forms at each level. |
| D3 | The body is in the field as one edit (the distance to the body at rest), so that a part can grow from it (`grow` by a distance) and be cut by an outline. A part takes its weights from the nearest points of the body; a rigid part names one bone. | A hat fits the head of each person, and a garment follows the body with no gap. |
| D4 | At mid and far, the body and its parts are one surface with a bake, in the place of the body with the colors of its clothes. | The outline of a person in a crowd is true: a hat is a hat. |
| D5 | Thin cloth that moves stays sewn (the áo dài of today). | A sheet thinner than two cells is not a field. |
| D6 | Before any model: tools that measure a person (the outline from the front and the side, lengths and girths, a joint at 90 degrees, the places of the marks of a face). | "Better" needs numbers and a blind test by the owner, not an opinion. |

## 4. The steps that this plan proposes

1. **The tools of D6**, run on the person of today: the reference.
2. **A short proof with one person from edits only** (a standing adult
   of 168.1 cm or 156.2 cm, `biped`, 150 to 250 edits, three levels of
   30,000, 4,000 and 700 triangles). It gives true numbers for the
   questions that the research can only estimate: how real it looks at
   each level, what a joint does at 90 degrees, what it costs. It is
   also the far and mid person of a crowd.
3. **The parts on a person** (D2 to D4): first a nón lá, a helmet,
   flip-flops and three masses of hair.
4. **Only if step 2 passes:** better joints (helper bones, shapes that
   correct a bend), and a face from edits that blinks.
5. **Later, for real faces:** a head from FLAME 2023 Open, and the ages
   of Anny.

## 5. How to know that it is better

- The outline of the person from edits and of the person of today, from
  the front and the side: the area in the two over the area in one of
  them is 0.97 at near, 0.95 at mid and 0.90 at far, or more.
- Each length in 1.5% and each girth in 2% of the reference.
- An elbow, a knee, a shoulder and a hip at 90 degrees: no face turned
  over, and the volume round the joint changes by less than 10%.
- 20 marks of the face in 1.5 mm in the mean.
- A blind test: the owner sees pairs of shots at each level, and picks
  the person that looks more real. The person from edits passes a
  level when the owner picks it in half of the pairs or more.
- A person with a hat and hair from edits builds in the time of today
  and 5 s more at the most.

## 6. Risks

- **The face from edits at near does not look alive.** The proposal
  keeps the face of MakeHuman; the blind test decides.
- **The cost.** An estimate for a whole person from edits at near: 40
  to 50 s on 4 schedulers, against 7 to 11 s today. Small parts cost 2
  to 6 s, and the cache keeps them.
- **Webs** in the armpit and between the fingers from the smooth
  blend, and **the weights** at the shoulder and the hip.
- **No full table of the body sizes of people of Việt Nam** is public.

## 7. Open questions for the owner

- Is the proof of step 2 wanted first, or the parts of step 3 (which
  are of use at once in a street: helmets, nón lá, hair)?
- Which persons count the most: a rider on a motorbike, a seller on
  the sidewalk, a pilgrim on the stair of the statue?

## 8. The first parts (2026-11-14)

The owner chose the parts before the proof. What is made:

| # | Decision | Why |
|---|---|---|
| D7 | A part is a drawing of the kind `prop` with one sculpture and the port `crown` at the top of the head. A person wears it by the option `wear`: it is a prop on the bone of the head. | The props of a person and the drawings from edits were there: no new kind of model. |
| D8 | A part that fits the head is drawn on one head (the woman of the catalog), and it grows from its port by the mean of the two ratios of the head of its person (the width and the length of the skin on the bone of the head). | The head of the man is 7% wider and 17% longer. A hat of one size (the nón lá) does not grow. This is in the place of D3 for now: the body is not an edit of the field yet. |
| D9 | Each part has its own role, and the color of the role of a mass of hair is the color of the hair (its image is light). | A person wears a hat on hair, each with its image; one drawing of hair is the hair of each color. |
| D10 | `World.Build` takes the materials of a prop into the model. | Before, the image of a prop from edits was not in the file of the person. |
| D11 | A prop does not need to stand (`World.Check`). | A hat is worn. |

The measure (one machine with 4 schedulers), with the strands of
section 9:

| Part | Edits | Triangles (near, mid, far) | Image | File at near |
|---|---|---|---|---|
| `non_la_edits` | 20 | 4,000 / 1,200 / 200 | 1024 | 1.5 MB |
| `mu_bao_hiem_edits` | 11 | 5,000 / 1,200 / 250 | 512 | 0.5 MB |
| `toc_ngan_edits` | 6 | 12,000 / 1,600 / 150 | 1024 | 3.2 MB |
| `toc_bui_edits` | 6 | 14,000 / 1,800 / 150 | 1024 | 3.4 MB |
| `toc_dai_edits` | 13 | 20,000 / 2,400 / 220 | 1024 | 2.9 MB |

- The five parts and the two people who wear them (`woman_non_la`,
  `man_helmet`) build in 63 s, three levels each (51 s before the
  strands).
- A person with two parts builds in about 5 s more than a person with
  none at near (the first time: the sculptures are made; the nón lá
  has small cells for its thin shell and is the slowest, 8 s).
- At far, the hat and the helmet are in the outline of the person:
  before, a person at far had the colors of its clothes only.

What these parts are not:

- **Long hair does not bend**, and the straps grow with the head.
- **No flip-flops, no clothes, no mask yet.** They need the foot and
  the body in the field (D3).
- **The tools that measure a person (D6) are not made.**

## 9. Hair that looks as hair (2026-11-14)

The owner, after the first parts: "Make the hair look like real hair,
not clay. The nón lá and helmet should match too." The first hair was a
smooth mass with painted lines: its outline was the outline of a ball
of clay.

| # | Decision | Why |
|---|---|---|
| D12 | A surface `hair` (`World.Sculpt.Texture`): strands that go out and down from the z of the edit, in locks, with single strands that catch the light. | Strands along the z of the edit made a top and a back as rough leather. Hair goes out from the top of a head. |
| D13 | The key `strands` of a sculpture. The color image has an alpha, the cover of each place: half with the lowest strand, all with the highest. The material is cut at half of the alpha. Shapes of `thin` take the low strands away first. | The line of the hair on the brow and the tips are single strands, not the edge of a mass. No new mesh: the image has them. |
| D14 | Shells: copies of the mesh out along its normals, with less alpha at their points. A shell shows only the strands that are higher than its part of the way out. Three at near, one at mid, none at far. | The outline of the head has single strands. It is the way of the fur of the animals of World, with the heights of the strands in the image and not in a shader. |
| D15 | A primitive with an alpha in one color has an alpha in each color (`World.Scene`). | The mass and its shells are one primitive: the points of the mass are whole. |
| D16 | A surface `palm`: 40 blades round the z of the edit, each with its tone and its fibers. The rings of the nón lá are thin lines over the blades. | The first nón lá had wide rings and no leaf. A mark of 1 mm was smaller than a texel and did not show: the scale of the fibers is 3 mm. |
| D17 | The shell of the helmet is 3.8 cm over the top of the head. It has a pad of cloth and a buckle. | Hair of 3 cm with its strands came through a shell of 3 cm. |

What it costs:

- The files of the hair at near are 2.9 MB to 3.4 MB (0.5 MB before):
  an image of 1024 with an alpha, and four times the triangles.
- A person with hair and a hat: 6.7 MB to 6.9 MB at near, 0.9 MB at
  mid, 0.33 MB at far.

What it is not:

- **Not single hairs.** A strand of the image is 1 mm to 2 mm wide: a
  lock of some hairs. From nearer than about 0.5 m the shells show as
  layers.
- **The cut is hard** (the alpha mode `MASK`): the borders of the
  strands have steps at mid, where the image is 512.
- **The blind test of section 5 is not done.** The hair of MakeHuman
  (cards) is still there for a person with no part.
