# 0021 People who move like people

Status: Done (2026-11-26). R1 to R7 are done, with their tests, in #101. The look of the walk (the step width, the arms, the hands, the trunk), the trousers at mid and far, and the three changes of the size of R7 are done in #102 (section 7, "The look of the walk"). The sheets and the films of R6 are on the pages of my reports (the repository keeps no pictures).

## 1. Goal

A person of World walks, stands, and exercises as a real person does. The feet stay on the ground. The whole body moves, not only the legs. A project knows the speed of each walk, so that the feet of a person who moves do not slide.

## 2. What I saw (the game Vũng Tàu, 2026-11-23)

- The walk (lib/world/people/pose.ex, walk_turns): the arms hang 3.5° to 5° out from the sides, and the lower arms do not move. (I first wrote that the upper arms are held 38° away from the body: 38° is the turn of the pose "stand" from the rest pose of MakeHuman, not the angle from the body.) The hips, the spine, the head, and the feet do not move. The knee bends to 45° as half a wave. The feet are in the air for a part of the step. The clip has 12 steps in 1.1 s.
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
| D1 | The walk comes from the measures of a real walk. The stance is 60 % of the cycle and the swing 40 %. The hip is bent about 30° at the contact of the heel and straight to about 15° behind the body at the toe-off. The knee bends 5° to 15° when the leg takes the weight, and to about 60° at the start of the swing. The foot rolls: heel, flat, heel off, toe off. The middle of the body goes up and down about 5 cm, two times in a cycle, and from side to side about 4 cm, one time in a cycle. The pelvis turns about 4° to each side, and the chest turns against it. The middles of the heels are 6 cm to 13 cm apart (the step width), less at a higher speed, and the feet point a little out (about 5° to 10°). The arms hang at the sides and swing against the legs: the line from the shoulder to the hand goes 15° to 25° to the front and 8° to 20° to the back in the walk, less in the stroll and for an old person, with the elbow bent a little more in front. The hands are relaxed: the fingers half bent and together, the palms to the thighs. The line from the pelvis to the head leans at most 4° to the front in the walk and 3° in the stroll: a person who walks at a comfortable speed is almost upright. The head stays level. | These are the values of the books of gait ([University of Missouri, Normal Gait](https://medicine.missouri.edu/sites/default/files/pm-r/Normal_Gait.pdf); [OUHSC, Kinematic analyses of gait](https://ouhsc.edu/bserdac/dthompso/web/gait/knmatics/gait.htm); the step width: [Physiopedia, Gait Definitions](https://www.physio-pedia.com/Gait_Definitions)). |
| D2 | The feet lead the legs. In the stance, a foot stays at its place on the ground while the hips go over it; the angles of the hip and the knee come from that. | Angles alone make the feet slide and float. |
| D3 | Two walks and one clip to stand: "stroll" (about 0.8 m/s), "walk" (about 1.2 m/s), and "idle" (a loop of 4 s to 6 s: the weight goes from one leg to the other, the chest moves with the breath, the head turns a little). A walk is a clip in place: the root does not go forward. The cadence is 80 to 110 steps each minute, and the length of the step comes from the legs of the person. | A comfortable walk is 60 m to 80 m each minute. A person who stops needs a clip. |
| D4 | Each walk gives its numbers in the extras of its animation in the GLB: the speed in m/s, the length of the stride in m, and the times of the contact of each foot. A project moves the person at that speed, or plays the clip faster or slower by the ratio of the speeds. The same in parts.json. | The game cannot measure a clip. |
| D5 | People do not all walk the same way. The age and the seed of a person change the cadence, the length of the step, the swing of the arms, and the bend of the back, in small limits. An old person takes shorter steps. | A street where each person has the same step looks like a parade. |
| D6 | Aerobics, tai chi, and yoga keep their moves and their beat, with the feet as in D2: in a low move the hips go down as far as the bend of the knees gives, with the feet flat on the ground. In a jump both feet leave the ground and come back to it. The trunk leans and turns with the arms, and the head follows the move. The extras give the times of the beats, so that a project can put a group on one beat. | The same fault as the walk. |
| D7 | A clip has enough keys for a smooth move (for example 24 each second, or a cubic curve). The builder measures the bytes of each choice in a GLB of a person and takes the smallest that looks smooth. | 12 keys with straight lines show as steps. |
| D8 | A test measures each clip of each kind of person: in the stance the foot is within 1 cm of the ground and does not move more than 1 cm; the height of the hips, the angles of the hip and the knee, the swing of the arms, the step width, the turn of the feet out, the hands, and the lean of the trunk are in the limits of D1; in the clip to stand the heels are 12 cm to 20 cm apart (so that a person who starts to walk does not jump to the side), with the feet, the hands and the trunk as in D1; the first and the last key of a loop are the same. | A fault of this kind must not come back. |

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
  - The angle of the hip is from its angle in the pose "stand" (0° in the stand; to the front for more than 0). The arm is the line from the joint of the shoulder to the joint of the hand (the wrist), from straight down (in #101 it was the upper arm, from its angle in the stand).
  - The limits of a walk: the hips go up and down 3 cm to 7 cm and to the sides 2 cm to 6 cm; the hip bends 20° to 40° to the front and goes 8° to 22° back; the knee bends 3° to 25° with the heel on the ground and 50° to 70° in the swing; the line from the shoulder to the hand goes 15° to 25° to the front and 8° to 20° to the back, and the upper arm is at most 15° out from the side; the head turns at most 5°. The look: the middles of the heels (the heel points of the check, 6 cm behind the ankles) are 6 cm to 13 cm apart, the line from the heel to the ball of each foot on the ground points 5° to 10° out, the line from the joint of the pelvis to the joint of the head leans 0° to 4° to the front, and the hands are relaxed: the three joints of each finger bend 60° to 150° in all, the first bones of two fingers side by side are at most 5° apart across the palm, and the palm is at most 40° from the direction to the middle of the body.
  - The limits of a stroll are the same, but the hips go up and down 1.5 cm to 7 cm and the hip goes back 5° to 22°: its steps are shorter, so a real person goes up and down less (2.7 cm at 0.7 m/s, Orendurff and others, 2004). The line of the arm goes 8° to 25° to the front and 4° to 20° to the back, and the trunk leans 0° to 3°. A walk under 1 m/s (a child, an old man) has these limits too, so the test also checks the walk of each person under 60 against the arms of a walk, and that the stroll and an old man swing the arms less.
  - The limits of the clip to stand: the heels 12 cm to 20 cm apart, and the feet, the trunk and the hands as in a walk.
- The walks (R2, `World.People.Gait`):
  - The roll of the foot: the heel touches with the toes 12° up; the foot is flat from 10 % to 35 % of the cycle; it turns round its ball to 30° at 50 %, then round the tip of its toes to 50° at the toe-off (60 %). The toes stay on the ground. Without the turn round the tip of the toes, the hip of a short step does not go back.
  - The hips: while the heel of a foot is on the ground, its leg carries the hips with the knee at 4°, and at 16° when the leg takes the weight (12 % of the cycle). The hips go up and down as much as these legs give: 6.6 cm in the walk of a man of the rules, 3.1 cm in his stroll, 1.9 cm in the stroll of an old man. Where a leg on the ground cannot reach its foot, the hips go down more. The hips go 2 cm to each side and turn 4° to each side; the chest turns 7° against them.
  - The step: 0.76 of the height of the hip in a walk and 0.64 in a stroll; 105 and 86 steps a minute for a hip of 0.9 m, and more for shorter legs (as a pendulum: one over the root of the height of the hip), from 80 to 110. The heel touches 0.44 of a step in front of the hip in a walk and 0.36 in a stroll.
  - The speed of "walk" comes from the legs, as D3 asks: 1.21 m/s for a man of the rules (height 0.55), 1.23 m/s for the traveler of the catalog, 1.05 m/s for a woman (her cadence is at the top of 110), 0.92 m/s for an old man of 75, 0.82 m/s for a child of 8. The stroll: 0.84, 0.78, 0.64 and 0.69 m/s. A project reads the speed of each person in the extras (D4).
  - The age: from 60 years, the step is 1 % shorter for each year (at most 25 %), the cadence 0.5 % slower, the swing of the arms 1.6 % smaller, and the upper back bends 0.5° more (at most 10°; in #101 the back bent 0.08° more for each year, as a lean of the whole trunk).
  - The seed: the step changes by at most 2 %, the cadence by 3 %, the swing of the arms by 15 %, the lean of the trunk by 0.5°, the bend of the upper back from 0° to 2° (in #101 the back bent 0° to 4°), the step width by 0.4 cm, and the turn of the feet out by 1.5°. A step that changes by 4 % moves the hip back by up to 4° more, past the limit. With no seed, the seed of a person comes from the numbers of its body (the order of a person has no option seed).
  - The limits of D8 for each walk come from its speed: a walk of 1 m/s or more has the limits of a walk, a slower walk (each stroll, and the walk of a woman, an old man, and a child) has the limits of a stroll. A slow walk with the limits of a walk fails: the hips of the stroll of an old man go up and down 1.9 cm, and his hip goes back 7.5° to 8.1°.
  - The clip to stand ("idle"): 6 s, 12 keys each second (in #101: 24). The hips go 3 cm to each side (one time), the chest bends 0.8° with the breath (two times), and the head turns about 6° to each side.
- The keys (D7): the walk of a man in his GLB is 12.9 KB at 12 keys each second, 17.8 KB at 24, and 20.4 KB at 30 (straight lines). A cubic curve keeps two tangents with each value: about 1.4 times the data of straight lines at the same keys, so a cubic curve at 12 keys each second has more data than straight lines at 24, and it goes past the contacts of the feet. I took 24 keys each second with straight lines. In #101 each channel had its own times in the GLB; now the channels of a clip share one list of times (R7, section 9).
- The numbers (R3): the extras of the animation of a walk have `speed` (m/s), `stride` (m), `cadence` (steps a minute), and `contacts`: for `l` and `r`, the times in the cycle (s) of `heel` (the contact of the heel) and of `toe_off`. `NAME.parts.json` has the same numbers in `animations`, with the name of each clip.
- The names (R5): "walk" stays the name of the walk, and "stroll" and "idle" are new names of the order of a person.
- The routines (R4):
  - The feet: when the two feet go to new places, one foot moves in the first 45 % of the move and the other in the last 45 %; the foot that is up comes down first (the march), else the left foot goes first (the step to warrior II). A foot that lifts moves over the ground and turns only from 15 % to 85 % of its move, and changes from flat to not flat at the middle. The hips go down as far as each leg must reach its foot with the knee bent 3°. The work of a site (plan 0006) keeps its moves: the climb of a scaffold has its feet on the rungs.
  - The jumps: the jumping jacks are four jumps. The hips go up 8 cm on an arc; the feet leave the ground when the hips are 2 cm up (the push of the legs), and move and turn only in the air. A jump is a pose with `jump: true`; `Pose.air/1` gives the times in the air, for the test.
  - The low moves: the step to the side of aerobics goes into a lunge (the hips 13 cm down, the foot 34 cm out), and the jacks land wide with the hips 9 cm down. Tai chi (14 cm) and warrior II of yoga (18 cm) were low already.
  - The trunk and the head: in aerobics the chest turns 6° in the march, 16° in the step to the side and 18° from a punch, and leans 5° to the side of the step; the head looks up 22° at the top of a jack, down 35° at a knee lift, and to the hands in the clap. In the opening of tai chi the head looks a little up as the arms rise and down as they sink.
  - The beats: `beats` is the times of the poses of the routine (16 in aerobics, 7 in tai chi, 11 in yoga), and `bpm` is there when the poses are evenly apart (aerobics: 120). A person late by a delay has the same beats.
- The look of the walk (2026-11-26, after the audit of #101):
  - The audit measured the walk of the traveler of the catalog: the feet 36 cm apart, the line from the shoulder to the hand 26° to the front and 5° to the back, the hands open with the fingers apart, and the trunk 7° to the front. The causes: each ankle stayed at its place in the rest pose of MakeHuman (36 cm apart for a man, whose hips are 21 cm apart); the pose "stand" has the forearm 46° to the front (the elbow of the rest pose of MakeHuman), so the line from the shoulder to the hand is 23° to the front before the swing; the rest pose of MakeHuman leans 4.3° to 4.7°, and the bend of the back of #101 (2° to 4° by the seed) was a lean of the whole trunk.
  - The step width: 3.5 cm and 0.25 of the width of the hips (from the joint of one hip to the other), 1 cm more in a stroll, up to 1 cm more for an old person, and 0.4 cm more or less by the seed. Each ankle goes in x so that the middle of its heel is at half of the step width from the middle of the body. The man of the rules: 8.5 cm in the walk and 9.5 cm in the stroll; a child 6.6 cm and 8.0 cm; an old man 9.5 cm and 10.9 cm.
  - The feet out: 7° and 1.5° more or less by the seed, with the key `toe` of the targets of the feet (the feet of the rest pose of MakeHuman point 1.6° to 4° out).
  - The arms: the walk sets the line from the shoulder to the wrist itself (the aim of an arm, `{:aim, side}` of `World.People.Skeleton`), 6° out from the side, with the elbow to the back. The middle of the swing is 3.5° to the front (3° in a stroll), and the swing goes 16.5° to each side of it (11° in a stroll), 1.6 % less for each year over 60, and 15 % more or less by the seed. The elbow bends 16° at the back of the swing and 0.5° more for each degree to the front.
  - The hands: a new shape of a hand, `"hang"`: the three joints of each finger bend 30°, 35° and 20°, the thumb 20° and 15°, and the first joints of the index, the ring and the pinky turn 12°, 9° and 12° to the middle finger. The palm is then to the thigh (the forearm of MakeHuman has the palm to the body). A hand that holds a prop keeps its shape. The fingers are 28 more channels in a walk; each has one key in the GLB (R7, section 9).
  - The trunk: the lower back (`spine_01`) turns back so that the line from the pelvis to the head leans 2° in the walk, 1° in the stroll and 1.5° in the clip to stand (0.5° more or less by the seed). The upper back (`spine_03`) bends 0° to 2° by the seed, and 0.5° more for each year over 60, at most 10°. In #101 the back of an old man of 75 bent 1.2° more than the back of a young man; now 7.5° more, so that the bend of the spine shows.
  - The pose "stand" did not change. The clip to stand has its own feet (the heels 8 cm and 0.4 of the width of the hips apart: 16.5 cm for a man, 13.5 cm for a child), arms, hands and trunk. If the pose "stand" changes to the same look, these change too: each person of the catalog that stands with no clip (`man`, `woman`, `traveler` and the people of the drawings), the start and the end of `wave` and `point`, each pose of the routines and of the work of a site (they are on the pose "stand"), and the arms of the pose "sit".
- The trousers at mid and far (the dark pieces at the knees and at the ankles in the film of the walk of the traveler):
  - The cause: at mid and far an item of clothing is a color on the low-poly body, and each loose part of it (2.5 cm or more out of the body) is a mesh of its own; the faces of the body under a loose part go. The cargo pants of the traveler had small loose parts: a patch of two triangles at the front of each knee (3.0 cm to 3.6 cm out of the body) and a ring at each ankle (the wide hem, 2.6 cm to 6.7 cm out). The body round them stayed on the skin, so each patch and each ring was 2.6 cm to 3.4 cm out of the rest of the trousers, with a gap: from the side, dark pieces float beside the leg. The weights were not the cause: in the walk the patches stay within 0.3 cm of their places on the trousers.
  - It was there before plan 0021: the loose parts came on 2026-11-17 (7f561fb), and the traveler of 2026-11-25 (before #101) has the same patches and rings. The walk of #101 bends the knee to 60° and the film shows the legs from the side, so they show more.
  - The correction (`World.People.Human`, `loose/6`): a point of a loose part on an edge where the item goes on as a close part (a cut, not a hem) goes in along its line from the body, to 0.6 of the mean distance of its close neighbors, and gives its move to the body under it; an island of a loose part with no free edge (a patch at a knee) does not hang, and is a part of the color of the item on the body. Each island of a loose part of the traveler, of a person in wool pants and ankle boots, and of a person in an áo dài is now within 0.7 cm of its item (it was up to 3.4 cm).

## 8. The base line (R1, 2026-11-25)

The checks of D8 on the clips of main, for a man (35 years, height 0.55), a woman (30), an old man (75), and a child (8). The walk is measured at 0.65 m/s, the speed that its legs fit.

| Clip | What fails |
|---|---|
| walk | The feet are 1.2 cm (the child) to 3.6 cm (the old man) over the ground at a key where no foot is on it. A foot on the ground moves 43 cm to 56 cm. The hips do not move: 0 cm up and down, 0 cm to the sides. The hip goes 24° back (more than 22°). |
| aerobics | The feet are 14.4 cm to 16.5 cm over the ground. For the man and the old man, a foot on the ground moves 1.4 cm. |
| yoga | The feet are 12.0 cm over the ground. A foot on the ground moves 2.4 cm to 4.3 cm. |
| tai chi | Nothing fails. |

In the walk the knee bends 6.7° with the heel on the ground and 51° in the swing, and the arms swing 13° to each side. The arms hang 3.5° to 5° out from the sides: in these measures they are not 38° away from the body (section 2).

## 9. The measure of a person (R7, 2026-11-26)

`scripts/people_bytes.exs` measures a man of 35 (height 0.55), ordered as a project orders him, before (main) and after this plan. Each buffer view counts in the first part that uses it. The clip `blink` is in each person (0.1 KB).

| Level | Clips | Before (KB) | After (KB) | JSON | Mesh | Skin | Clips | Pictures |
|---|---|---|---|---|---|---|---|---|
| mid | none | 1344.9 | 1344.9 | 25.4 | 315.6 | 3.3 | 0.1 | 1000.2 (4 pictures) |
| mid | walk | 1349.9 | 1362.3 | 28.3 → 32.5 | 315.6 | 3.3 | 2.1 → 10.3 | 1000.2 |
| mid | walk, stroll, idle | (no such clips) | 1419.7 | 43.9 | 315.6 | 3.3 | 56.2 | 1000.2 |
| mid | tai chi, yoga, aerobics | 1879.6 | 1893.4 | 75.7 → 77.7 | 315.6 | 3.3 | 484.4 → 496.2 | 1000.2 |
| far | none | 259.6 | 259.6 | 24.5 | 85.1 | 3.3 | 0.1 | 146.5 (2 pictures) |
| far | walk | 264.6 | 277.0 | 27.4 → 31.5 | 85.1 | 3.3 | 2.1 → 10.3 | 146.5 |
| far | walk, stroll, idle | (no such clips) | 334.4 | 43.0 | 85.1 | 3.3 | 56.2 | 146.5 |
| far | tai chi, yoga, aerobics | 794.3 | 808.1 | 74.8 → 76.8 | 85.1 | 3.3 | 484.4 → 496.2 | 146.5 |

- The pictures are 74 % of a person at mid and 56 % at far. The new walk adds 12.4 KB (24 keys each second, D7): 0.9 % at mid, 4.7 % at far.
- The clips of the three routines are 496 KB: more than the mesh. Each has about 49 channels (with the fingers) at 10 to 15 keys each second. The clip to stand is 33 KB of the 56 KB of the three walks (6 s at 24 keys each second).
- A set of six people with a walk (three men and three women of 19 to 70 years), each GLB alone and with one atlas of their pictures (plan 0020, step 4):

| Level | Alone | With one atlas | Saves |
|---|---|---|---|
| mid | 8199.8 KB (6000.9 KB of pictures) | 3478.2 KB (the GLB files 2750.9 KB, the atlas 727.3 KB) | 4721.6 KB (58 %) |
| far | 1651.2 KB (879.1 KB of pictures) | 1434.9 KB (the GLB files 1325.6 KB, the atlas 109.3 KB) | 216.3 KB (13 %) |

  The people of a set share most of their pictures (the skin, the eyes, the clothes): in one atlas each picture is there one time. Before this plan the same set was 8126.8 KB alone and 3405.2 KB with one atlas (the walk of 12 keys).
- What I did not change in #101, and proposed: (1) one list of times for all the channels of a clip; (2) the clip to stand at 12 keys each second; (3) a project of many people orders them as a set with one atlas. The owner approved the three (2026-11-26). They are done in #102, with the look of the walk and the trousers:
  - (1) `World.GLB`: the channels of a clip with the same times share one accessor of the times, and a channel whose value does not change has one key (the 28 channels of the fingers that hang in a walk).
  - (2) The clip to stand has 12 keys each second: at each key of a clip of 48 keys each second, each bone of the clip of 12 keys with straight lines is within 1 mm (the test).
  - (3) `docs/requests.md`, "Many people": a set with `"atlas": true`. The picture of the skin is a JPEG, and the atlas takes PNG pictures only: it stays in the GLB of each person (92 KB at mid and at far).
- The man of 35 after these changes (`scripts/people_bytes.exs`; before: main after #101):

| Level | Clips | Before (KB) | After (KB) | JSON | Mesh | Clips |
|---|---|---|---|---|---|---|
| mid | none | 1344.9 | 1338.3 | 25.4 → 24.1 | 315.6 → 310.2 | 0.1 |
| mid | walk | 1362.3 | 1357.5 | 32.5 → 34.6 | 315.6 → 310.2 | 10.3 → 8.8 |
| mid | walk, stroll, idle | 1419.7 | 1404.7 | 43.9 → 54.9 | 315.6 → 310.2 | 56.2 → 35.8 |
| mid | tai chi, yoga, aerobics | 1893.4 | 1769.2 | 77.7 → 56.5 | 315.6 → 310.2 | 496.2 → 398.6 |
| far | none | 259.6 | 254.8 | 24.5 → 23.3 | 85.1 → 81.4 | 0.1 |
| far | walk | 277.0 | 273.9 | 31.5 → 33.6 | 85.1 → 81.4 | 10.3 → 8.8 |
| far | walk, stroll, idle | 334.4 | 321.2 | 43.0 → 53.9 | 85.1 → 81.4 | 56.2 → 35.8 |
| far | tai chi, yoga, aerobics | 808.1 | 685.7 | 76.8 → 55.6 | 85.1 → 81.4 | 496.2 → 398.6 |

  - The clips of the routines are 97.6 KB smaller, and their JSON 21.2 KB (one accessor of the times in place of 49). The walk has 28 more channels (the fingers), so its JSON is 2.1 KB larger and its data 1.5 KB smaller. The mesh is smaller because the islands of the clothes with no free edge are now on the body (the trousers, above).
- A set of 12 people (six men and six women of 8 to 75 years) with `walk` and `idle`, each GLB alone and with one atlas:

| Level | Alone, before (KB) | Alone, after (KB) | One atlas, before (KB) | One atlas, after (KB) |
|---|---|---|---|---|
| mid | 16845.8 (11995.6 of pictures) | 16556.0 | 6675.2 (the GLB files 5947.9, the atlas 727.3) | 6385.5 (the GLB files 5658.1, the atlas 727.3) |
| far | 3750.0 (1751.9 of pictures) | 3524.4 | 3208.1 (the GLB files 3098.8, the atlas 109.3) | 2982.4 (the GLB files 2873.1, the atlas 109.3) |

  With one atlas a set of 12 is 61 % smaller at mid and 15 % at far. Of the GLB files of the set at each level, 1100.4 KB are the 12 pictures of the skin (92 KB each), and the 12 people have only 2 different skins (178.1 KB). What I propose, not done: the GLB files of a set refer to each picture of the skin by its URL, one file for each different skin of the set: 922 KB less at each level (31 % of the set at far).
