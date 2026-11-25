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
