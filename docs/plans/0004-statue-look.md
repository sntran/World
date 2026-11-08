# 0004 The statue of Vũng Tàu looks like the real one

| Field | Value |
|---|---|
| Status | In progress |
| Depends on | Plan 0002 (the statue as a blueprint in data, built by the trades), plan 0003 (a blueprint comes from the outside). |
| Changes | The review pages (light and shadow); a texture of a role of the palette; the shell of a cast (relaxed); the skills `figure`, `robe`, `halo`, `cast_field`, `shell`, `base`; a new skill `carve`; the files of `tuong_chua_kito_vua`. |

## 1. Goal

The owner (2026-11-08) saw the statue of Christ on Núi Nhỏ that the
people of World built from its blueprint, sent over MCP as a project
sends it, and said that the pictures do not look good. The sizes are
right (32 m, a span of 18.4 m, 133 steps inside); the look is wrong:

- the face is a lump with no eyes, nose or mouth;
- the hands are lumps;
- the robe has none of the marks of the real one;
- all of it is flat white with no shadow.

The goal: from the front, from three quarters and close to the head,
the model is the statue of the photos. The people still build it as on
a site (the base, the cast in bands, the hollow with its stair), and its
sizes and sources stay.

What the photo of the statue shows (Wikimedia Commons,
`Statue_of_Jesus_in_Vung_Tau.jpg`, the photo that the drawing cites):

- **The robe** is a straight column of flat planes with sharp edges, in
  the style of the 1970s, not a cloth with soft folds:
  - a front panel with three square marks;
  - side panels;
  - a short cape from the shoulders;
  - the Sacred Heart on the chest.
- **The sleeves** are wide and square, with a band of Greek key at the
  cuffs. The hem has the same band.
- **The hands** are open and flat.
- **The head** has long hair to the shoulders. The halo is a ring with
  its cross behind the head, with rays and rods on its top.
- **The plinth:** the statue stands on a low dome.
- **The base** has a curved front with a bronze relief of the Last
  Supper, and a rail with round medallions.

## 2. Out of scope

- The color of the statue in the game (the game has its own shader for
  `weathering`).
- A new level of detail. Mid and far keep their forms; far keeps its
  bytes.

## 3. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **The photos are the reference.** The CC photos of Wikimedia Commons (Category:Christ of Vung Tau) are fetched to a folder out of the repository. A photo goes into the repository only with its license in `CREDITS.md`. Each commit of a shape has shots at the angles of three photos (front, three quarters, the head). | The owner judges by the look; the photos are what the statue looks like. |
| D2 | **The budget of the statue (the owner):** fewer than 100,000 triangles at near; mid at most 12,000; far at most 300. `docs/format.md` has a row for a monument. | The detail goes where it is seen up close; the game and the far views pay nothing. |
| D3 | **The large forms stay cast** (the robe, the body, the hollow, the stair, the windows: concrete in forms, poured in bands). The shell is relaxed with Taubin smoothing, which keeps the volume and the sharp edges of the planes, so the steps of the grid go away. | The cast is how the real statue was built, and the hollow and the stair need its field. |
| D4 | **The fine parts are carved, not cast:** the head (the face and the hair), the hands and the feet. They come from the full MakeHuman base mesh at near (`Human.near/5`, with eyes, nose and lips), posed and scaled as the figure. A new skill `carve` (trade sculptor) makes them, the cast field leaves their places out, and each overlaps the shell by a collar at the neck, the wrists and the ankles. Mid and far keep the cast. | A face cannot be cast in cells of 0.32 m; a sculptor makes the head and the hands of a real statue. |
| D5 | **The robe as the photo shows it:** flat planes with sharp edges; the front panel with its three square marks; the side panels; the cape to the waist; the Sacred Heart; wide square sleeves; the band of Greek key at the cuffs and at the hem. The feet show under the hem, on a low dome. | These are the marks that make the statue the statue of Vũng Tàu. |
| D6 | **The halo is behind the head.** Its center comes from the skull, not from the hair. Its cross is in the ring behind the head, and no part of the halo is in front of the face. | The halo is the lightning rod of the statue (the travel guides), and the photo shows it behind the head. |
| D7 | **Washed stone and light.** A role of the palette can have a texture that World makes (`World.PNG`): small changes of color (the pebbles of đá rửa) and a normal texture of grain, tiled in metres on the UVs that the statue already has (`World.Surface`). The color of `stone_wash` comes from the photos. The review pages share one scene module: tone mapping, a sun with soft shadows fitted to the model, a ground that takes the shadow, and `READY` after the first frame. | The same GLB looks like stone in any app; the review page shows the model as a person sees it. |
| D8 | **Far keeps its bytes.** The tests that compare the far file with its bytes stay as they are; near and mid change, and their files are built again. | Far is the level of the skyline of the game. |
| D9 | **The checks (the owner):** quick checks on each commit (the format, the compile with warnings as errors, the tests of what the commit changes), and the full checks on the tip before each push. | The container of the work restarts often, and a full check takes half an hour. |

## 4. Requirements

- R1. `review/index.html`, `world.html` and `replay.html` use one scene
  module (`review/scene.js`) with tone mapping, soft shadows and a
  ground that takes them. A test of `test/js/` loads a model on the
  review page and sees it drawn with its shadows.
- R2. A role of the palette can name a texture of World. `stone_wash`
  has the texture of washed stone, and the GLB passes the validator of
  Khronos.
- R3. The shell of a cast can be relaxed (`World.Cast`): its volume stays
  within 2%, and each edge is still in two faces.
- R4. The halo of the statue has no point in front of the plane of the
  face, and its cross is outside the outline of the head.
- R5. The robe has the marks of D5. The span stays 18.4 m, and the
  hollow, the stair and the windows are inside the shell.
- R6. The head, the hands and the feet are carved parts at near, with
  the eyes, the nose and the mouth of the face. `Check.model` passes.
- R7. Near has fewer than 100,000 triangles; mid at most 12,000; far at
  most 300 and the same bytes.
- R8. The statue built over MCP (`check_blueprint`, then `build`) has
  the look of the photos at three angles.

## 5. Steps

1. This plan; the photos; shots of the statue of today at their angles.
2. The light and the shadow of the review pages (R1).
3. The texture of a role (R2).
4. The relaxed shell, and the budget of D2 (R3, R7).
5. The halo (R4).
6. The robe, the sleeves, the bands, the dome (R5).
7. The carved head, hands and feet (R6).
8. The files of the statue built again, the docs, the shots next to the
   photos (R7, R8).

## 6. Acceptance criteria

- Each requirement has its test, and the checks of D9 pass.
- The shots of the statue built over MCP, next to the photos, at three
  angles: the owner says that they look like the statue.

## 7. Open questions

None now.
