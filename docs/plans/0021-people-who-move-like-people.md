# 0021 People who move like people

Status: Approved (2026-11-25).

## 1. Goal

A person of World walks, stands, and exercises as a real person does. The feet stay on the ground. The whole body moves, not only the legs. A project knows the speed of each walk, so that the feet of a person who moves do not slide.

## 2. What I saw (the game Vũng Tàu, 2026-11-23)

- The walk (lib/world/people/pose.ex, walk_turns): the upper arms are held 38° away from the body, and the lower arms do not move. The hips, the spine, the head, and the feet do not move. The knee bends to 45° as half a wave. The feet are in the air for a part of the step. The clip has 12 steps in 1.1 s.
- The clip does not give its speed. Its legs fit about 0.65 m/s. The walkers of the game move at 0.9 m/s to 1.3 m/s, so they glide.
- A person who stops has no clip to stand in: the walk stops in the middle of a step.
- Aerobics (routine("aerobics")): the hips go down 2 cm to 6 cm only, and the feet move by their own values. In the game the feet float about 20 cm over the ground in the low moves. The trunk and the head are stiff.

## 3. Out of scope

- How a project moves many people (the ways, the turns, a group that follows its leader). Each project does that.
- The animals.
- The face and the lips.

## 4. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | The walk comes from the measures of a real walk. The stance is 60 % of the cycle and the swing 40 %. The hip is bent about 30° at the contact of the heel and straight to about 15° behind the body at the toe-off. The knee bends 5° to 15° when the leg takes the weight, and to about 60° at the start of the swing. The foot rolls: heel, flat, heel off, toe off. The middle of the body goes up and down about 5 cm, two times in a cycle, and from side to side about 4 cm, one time in a cycle. The pelvis turns about 4° to each side, and the chest turns against it. The arms hang at the sides and swing against the legs (about 20° to the front, 10° to the back), with the elbow bent a little more in front. The head stays level. | These are the values of the books of gait ([University of Missouri, Normal Gait](https://medicine.missouri.edu/sites/default/files/pm-r/Normal_Gait.pdf); [OUHSC, Kinematic analyses of gait](https://ouhsc.edu/bserdac/dthompso/web/gait/knmatics/gait.htm)). |
| D2 | The feet lead the legs. In the stance, a foot stays at its place on the ground while the hips go over it; the angles of the hip and the knee come from that. | Angles alone make the feet slide and float. |
| D3 | Two walks and one clip to stand: "stroll" (about 0.8 m/s), "walk" (about 1.2 m/s), and "idle" (a loop of 4 s to 6 s: the weight goes from one leg to the other, the chest moves with the breath, the head turns a little). A walk is a clip in place: the root does not go forward. The cadence is 80 to 110 steps each minute, and the length of the step comes from the legs of the person. | A comfortable walk is 60 m to 80 m each minute. A person who stops needs a clip. |
| D4 | Each walk gives its numbers in the extras of its animation in the GLB: the speed in m/s, the length of the stride in m, and the times of the contact of each foot. A project moves the person at that speed, or plays the clip faster or slower by the ratio of the speeds. The same in parts.json. | The game cannot measure a clip. |
| D5 | People do not all walk the same way. The age and the seed of a person change the cadence, the length of the step, the swing of the arms, and the bend of the back, in small limits. An old person takes shorter steps. | A street where each person has the same step looks like a parade. |
| D6 | Aerobics, tai chi, and yoga keep their moves and their beat, with the feet as in D2: in a low move the hips go down as far as the bend of the knees gives, with the feet flat on the ground. In a jump both feet leave the ground and come back to it. The trunk leans and turns with the arms, and the head follows the move. The extras give the times of the beats, so that a project can put a group on one beat. | The same fault as the walk. |
| D7 | A clip has enough keys for a smooth move (for example 24 each second, or a cubic curve). The builder measures the bytes of each choice in a GLB of a person and takes the smallest that looks smooth. | 12 keys with straight lines show as steps. |
| D8 | A test measures each clip of each kind of person: in the stance the foot is within 1 cm of the ground and does not move more than 1 cm; the height of the hips, the angles of the hip and the knee, and the swing of the arms are in the limits of D1; the first and the last key of a loop are the same. | A fault of this kind must not come back. |

## 5. Requirements

- R1. The checks of D8 first, on the clips as they are now. The list of what fails is the base line.
- R2. The walk, the stroll, and the idle clip (D1 to D5, D7), for a man, a woman, an old person, and a child of the rules.
- R3. The numbers of D4 in the GLB and in parts.json, with their names in docs/format.md.
- R4. The three routines with the feet on the ground (D6).
- R5. The names: "walk" stays the name of the walk of 1.2 m/s, so that an order of a project does not break.
- R6. A sheet of pictures of each clip for my look: 12 frames of one cycle from the side and from the front, on a ground line, with the old clip next to the new clip. And one short film of each clip (a GIF or an MP4) from the review page.
- R7. The measure of a person for the projects: the bytes of one person at mid and at far by part (the mesh, the pictures, the clips), before and after, and what one atlas for a set of people (plan 0020, step 4) saves. Vũng Tàu has 93 MB of people in its web build. Measure only; do not change the pictures of the people.

## 6. Steps

1. R1.
2. R2, R3, R5, and the sheet of R6 for the walks and the idle clip.
3. R4, and the sheet of R6 for the routines.
4. R7.

## 7. Questions

- The builder writes here each choice that the plan does not give.
- The checks of D8 (`World.People.Motion`):
  - Three points of each foot touch the ground: the heel (6 cm behind the ankle), the ball (under the joint of the toes), and the tip of the toes. A foot is on the ground when its lowest point is within 1 cm of it.
  - "The knee when the leg takes the weight" is the knee while the heel of its foot is on the ground. At the toe-off a real knee bends to about 40°, so the whole stance cannot be in 5° to 15°.
  - The angles of the hip and of the arm are from their angles in the pose "stand" (0° in the stand; to the front for more than 0).
  - The limits of a walk: the hips go up and down 3 cm to 7 cm and to the sides 2 cm to 6 cm; the hip bends 20° to 40° to the front and goes 8° to 22° back; the knee bends 3° to 25° with the heel on the ground and 50° to 70° in the swing; the arm swings 10° to 30° to the front and 3° to 18° to the back, at most 15° out from the side; the head turns at most 5°.
  - The limits of a stroll are the same, but the hips go up and down 1.5 cm to 7 cm and the hip goes back 5° to 22°: its steps are shorter, so a real person goes up and down less (2.7 cm at 0.7 m/s, Orendurff and others, 2004).
- The walks (R2, `World.People.Gait`):
  - The roll of the foot: the heel touches with the toes 12° up; the foot is flat from 10 % to 35 % of the cycle; it turns round its ball to 30° at 50 %, then round the tip of its toes to 50° at the toe-off (60 %). The toes stay on the ground. Without the turn round the tip of the toes, the hip of a short step does not go back.
  - The hips: while the heel of a foot is on the ground, its leg carries the hips with the knee at 4°, and at 16° when the leg takes the weight (12 % of the cycle). The hips go up and down as much as these legs give: 6.6 cm in the walk of a man of the rules, 3.1 cm in his stroll, 1.9 cm in the stroll of an old man. Where a leg on the ground cannot reach its foot, the hips go down more. The hips go 2 cm to each side and turn 4° to each side; the chest turns 7° against them.
  - The step: 0.76 of the height of the hip in a walk and 0.64 in a stroll; 105 and 86 steps a minute for a hip of 0.9 m, and more for shorter legs (as a pendulum: one over the root of the height of the hip), from 80 to 110. The heel touches 0.44 of a step in front of the hip in a walk and 0.36 in a stroll.
  - The speed of "walk" comes from the legs, as D3 asks: 1.21 m/s for a man of the rules (height 0.55), 1.23 m/s for the traveler of the catalog, 1.05 m/s for a woman (her cadence is at the top of 110), 0.92 m/s for an old man of 75, 0.82 m/s for a child of 8. The stroll: 0.84, 0.78, 0.64 and 0.69 m/s. A project reads the speed of each person in the extras (D4).
  - The age: from 60 years, the step is 1 % shorter for each year (at most 25 %), the cadence 0.5 % slower, and the back bends 0.08° more.
  - The seed: the step changes by at most 2 %, the cadence by 3 %, the swing of the arms by 15 %, and the bend of the back from 0° to 4°. A step that changes by 4 % moves the hip back by up to 4° more, past the limit. With no seed, the seed of a person comes from the numbers of its body (the order of a person has no option seed).
  - The limits of D8 for each walk come from its speed: a walk of 1 m/s or more has the limits of a walk, a slower walk (each stroll, and the walk of a woman, an old man, and a child) has the limits of a stroll. A slow walk with the limits of a walk fails: the hips of the stroll of an old man go up and down 1.9 cm, and his hip goes back 7.5° to 8.1°.
  - The clip to stand ("idle"): 6 s. The hips go 3 cm to each side (one time), the chest bends 0.8° with the breath (two times), and the head turns about 6° to each side.
- The keys (D7): the walk of a man in his GLB is 12.9 KB at 12 keys each second, 17.8 KB at 24, and 20.4 KB at 30 (straight lines). A cubic curve keeps two tangents with each value: about 1.4 times the data of straight lines at the same keys, so a cubic curve at 12 keys each second has more data than straight lines at 24, and it goes past the contacts of the feet. I took 24 keys each second with straight lines. Each channel has its own times in the GLB; one list of times for all the channels of a clip saves about 4.7 KB of the 17.8 KB. I did not do it, because it changes each animated model of the catalog.
- The numbers (R3): the extras of the animation of a walk have `speed` (m/s), `stride` (m), `cadence` (steps a minute), and `contacts`: for `l` and `r`, the times in the cycle (s) of `heel` (the contact of the heel) and of `toe_off`. `NAME.parts.json` has the same numbers in `animations`, with the name of each clip.
- The names (R5): "walk" stays the name of the walk, and "stroll" and "idle" are new names of the order of a person.

## 8. The base line (R1, 2026-11-25)

The checks of D8 on the clips of main, for a man (35 years, height 0.55), a woman (30), an old man (75), and a child (8). The walk is measured at 0.65 m/s, the speed that its legs fit.

| Clip | What fails |
|---|---|
| walk | The feet are 1.2 cm (the child) to 3.6 cm (the old man) over the ground at a key where no foot is on it. A foot on the ground moves 43 cm to 56 cm. The hips do not move: 0 cm up and down, 0 cm to the sides. The hip goes 24° back (more than 22°). |
| aerobics | The feet are 14.4 cm to 16.5 cm over the ground. For the man and the old man, a foot on the ground moves 1.4 cm. |
| yoga | The feet are 12.0 cm over the ground. A foot on the ground moves 2.4 cm to 4.3 cm. |
| tai chi | Nothing fails. |

In the walk the knee bends 6.7° with the heel on the ground and 51° in the swing, and the arms swing 13° to each side. The arms hang 3.5° to 5° out from the sides: in these measures they are not 38° away from the body (section 2).
