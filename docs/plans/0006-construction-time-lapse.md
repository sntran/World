# 0006 The world on one clock, the hill of Núi Nhỏ, and the time lapse of a construction

| Field | Value |
|---|---|
| Status | In progress (the owner approved it on 2026-11-10: "Rewrite plan 0006 and proceed") |
| Depends on | Plan 0001 (the people build on demand), plan 0002 (the yard, the places, the trucks), plan 0005 (the statue on Núi Nhỏ from its measures). |
| Changes | The clock of the world; the terrain of a place (`priv/terrain/`, from the Vũng Tàu game); the places of the yard; the methods of a site and the history of the statue (`priv/history/`); a change that takes down what it drops; a site that gets old in a pause; the stages of a construction as parts of the model; the work of the people; the page of the world (`review/world.html`) and a video script. |

## 1. Goal

World is a small world of people and construction sites: the page of
the world (`review/world.html`) shows the places of the yard, the people
of the census that walk to the lots and work, the trucks that bring the
materials, and each construction on its lot as its parts arrive. The
statue on Núi Nhỏ is one of those constructions (the owner, 2026-11-10).

At the end:

- **One clock for the world.** Each construction of the world takes the
  days of a real site, and the clock of the world runs those days. A
  person on a task is busy for the days of the task.
- **A real hill.** Núi Nhỏ is a place of the world with the true ground
  of the hill, from the Vũng Tàu game (the Copernicus DEM, in the frame
  of the game). The statue stands on its top, at its place in the game,
  so a model that World builds on the hill goes back into the game.
- **Two methods of a site** for the statue: the site of today, and the
  true history from 1972 to 1994 (with the first statue at the cape of
  Nghinh Phong, which a change of the order takes down, and a pause of
  17 years when the rough statue gets old).
- **The construction seen as on a site:** the scaffold, the formwork,
  each pour, the rough concrete and the finish are parts that come and
  go, and the people work at their trades.
- **The time lapse is the page of the world** that follows one
  construction at a faster clock, with a camera that the viewer sets; a
  script makes a video of it.

## 2. What the owner asked

On 2026-11-10:

1. "I was hoping for the construction be like a time lapse of the
   building of the model." The prototype of a time lapse (a page that
   cuts the finished model at a rising height) showed the look.
2. "If we can show the people at work too, that would be more real."
3. "Make the camera configurable in the preview."
4. "The history you found maybe a good test to actually have a
   blueprint with many different methods of building. Let's see if we
   can support both old and modern methods of building based on the
   statue's history. Store the facts that you found in the repo."
5. "Use the right amount of time for each step, relative to each other,
   so the length of the film is the total time it takes those steps."
   And for the pause of 17 years: the statue that gets old. "Let do the
   actual time lapse of building the statue, including the demolishing
   of the first version. That shows a request for change."
6. "We are building the world at https://world.mkfifo.com. It's a mini
   world of the people and the construction sites. This build is one of
   those constructions."
7. "If you can bring the hill terrain from Vung_Tau then let do it.
   Build a real hill there, so we can reuse it back in Vung_Tau. Single
   clock for the world."

## 3. The two methods of the statue

- **Today** (the default): a tower crane lifts the loads, a pump gives
  the concrete, the scaffold is of steel and the formwork of plywood.
  The trucks of the yard drive up the road of the hill. The days come
  from the rates of the trades of today.
- **1974**: the true history. No machines: the trucks stop at the foot
  of the hill, the people carry the materials up the path, mix the
  concrete on the site and pour it by hand, on a scaffold that is hard
  to set up. Its stages:
  1. The first statue, 10 m on a base of 5 m, at the cape of Nghinh
     Phong (1972 to 17 January 1973).
  2. A pause: the land is claimed by Buddhists; the part that is built
     stands (to 16 February 1974).
  3. **A change of the order:** the agreement of 16 February 1974 moves
     the site to the top of Núi Nhỏ and makes the statue 32 m. The first
     statue is taken down.
  4. The rough structure on Núi Nhỏ (18 March 1974 to 30 April 1975).
  5. A pause of 17 years: the rough statue gets old, weeds cover the
     site, the copper cable of the lightning rod is stolen.
  6. The finish (28 January 1992 to 1 December 1994): the repair, the
     render, the reliefs, the rail.

The facts, each with its sources, are in
`priv/history/tuong_chua_kito_vua.json`: 13 facts from 6 sources (read
on 2026-11-10), the six stages and the change. What the facts do not say
is marked there as an estimate.

The same blueprint and the same model at the end, two sites: this tests
that a blueprint keeps what it builds apart from how it is built.

## 4. Out of scope

- Weather other than the sun (rain, clouds).
- The terrain of the other places of the yard: they stay flat.
- Methods for the other blueprints (a house, a vehicle): later, on the
  same model of a method.

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **One clock for the world, in days of a site.** The clock of the world runs at a scale (the seconds of the world in one second of the wall; one day a second by default). Each task of each construction takes its days on the site: its work (from the data of its skill: a volume of concrete, an area of formwork, a count of steps) over the rate of its crew (`priv/standards/`, each rate with its source, or an estimate), and a wait after it (a cure). The people do the work of the computer at once, and the task ends at its day on the clock. The log keeps the time of the world (`at`) and the wall time (`wall`). | The owner: a single clock for the world. Today the time of a task in the world is the time of its calculation. |
| D2 | **The order of a real site.** A band of a cast waits for the cure of the band under it; the scaffold of a band goes up before its formwork; the formwork comes off after the cure. | Concrete stands on cured concrete. |
| D3 | **The hill from the Vũng Tàu game.** `priv/terrain/nui_nho/` has the height tiles of the game round Núi Nhỏ and the cape of Nghinh Phong, in the format of the game: 16-bit PNG tiles of 256 m, one sample each 2 m, the height `offset + value * step`, in the frame of the game (X east, Z south, the origin at Bãi Trước). A copy, with no change, from `data/geo/build/height/` of sntran/Vung_Tau, with its notices (the Copernicus DEM GLO-30, and the OpenStreetMap data of the roads and the coast in the build). `World.Terrain` reads them, gives the height at a point, and makes the mesh of the ground. | The owner: a real hill, and the hill back in the game. The same files and the same frame make that a copy, not a conversion. |
| D4 | **A place can have a terrain and lots on it.** The place `nui_nho` of the yard has the terrain `nui_nho` and two lots in the frame of the game: the top (the statue of the game, landmark `chua_kito_vua`, at X 1159.87, Z 1893.39, 138.3 m) and the cape of Nghinh Phong (landmark `mui_nghinh_phong`). The statues go to it; the other buildings stay on the flat site. | The two sites of the history are at the two places of the real hill. |
| D5 | **A model on a terrain has its place in the game.** Its extras have `"geo"`: the frame (`vung_tau_game`), the point of its origin (X, height, Z) and its turn round the vertical. The game puts it on its ground with no more data. | The owner: reuse it back in Vũng Tàu. |
| D6 | **The method of a site is an option of an order** (`method`: `today` or `1974` for the statue). A method gives the machines, the scaffold, how the concrete comes to the form, the rates of the crews, the most people on the site, and the stages with their dates. The model at the end is the same. `1974` takes its stages from `priv/history/`. | The owner: both old and modern methods, from the history of the statue. |
| D7 | **A change takes down what it drops.** A change of an order (`World.Construction.change/2`, plan 0001, D32) now has a cost on the site: each built element that the change does not keep is taken down by people (a new action of a task, `remove`), the last one built first, with its days. The lot is an option of an order: a change of the lot drops each element. | The first statue at Nghinh Phong was taken down when the order changed: "that shows a request for change". |
| D8 | **A site gets old in a pause.** In a pause the built model gets old with the days: the concrete gets darker, weeds grow on the base and the plinth, a part can go (the copper cable of the lightning rod). The repair at the end of the pause makes it clean. The rate is an estimate. | The facts of the pause of 1975 to 1992; the owner chose the statue that gets old. |
| D9 | **The stages of a construction are parts of the model.** The replay model (`replay.glb`) has a node for each state that a person sees on the site: the scaffold of each band, the formwork of each band, each poured band in rough grey concrete, the render of washed stone over it, the reliefs. Each node has the task that puts it up and the task that takes it down (`"from"`, `"to"`). | A prototype that cuts the finished model at a height cannot show a formwork that comes off, or the grey concrete before the render. |
| D10 | **The people at work.** Each person that a construction hires walks from the census to the lot (on the path of the hill when the method has no machine) and works at the place of its task with the work of its trade: carry a load, set a panel, pour, trowel, hammer, climb the scaffold, guide a load of the crane. New animations of `World.People.Pose` and new props (a hard hat, a bucket, a trowel, a hammer). At most 50 people on a site (the 50 skilled workers of 1974; an estimate for today). | The owner: the people at work. |
| D11 | **The time lapse is the page of the world.** `review/world.html` can follow one construction: its camera turns with the mouse or a finger, has places to choose (three quarters, the front, the side, the back, the base, above), a slow turn round the lot, and takes `cam`, `target` and `fov` from the URL. Its clock runs faster (the days of the world in one second of the page), the same for each step and each pause, so the length of a film is the days of the site over that scale. `scripts/timelapse.mjs` makes a video of a construction with the camera of the URL. | The owner: the time lapse as one construction of the world, the camera that the viewer sets, the right time for each step. |

## 6. Requirements

- R1. The clock: each task has its first and last day; the world clock
  runs at its scale; a task ends at its day; a band of a cast starts
  after the cure of the band under it; each rate and each cure has a
  source or is an estimate.
- R2. The terrain: `World.Terrain` reads the tiles of `priv/terrain/`,
  gives the same heights as the game at the same points (a test against
  the values of the PNG files), and makes a mesh of the ground;
  `CREDITS.md` has the notices.
- R3. The place `nui_nho` with its terrain and its two lots; a statue
  goes to it, stands on its ground, and has `"geo"` in its extras.
- R4. The methods: an order of the statue with `method` `today` or
  `1974` gives the same final model and two schedules; `1974` has its
  six stages, the change of 16 February 1974, and its two pauses. A test
  reads `priv/history/tuong_chua_kito_vua.json`: each fact names a source
  of the file and each stage names facts of the file.
- R5. A change that drops built elements gives a `remove` task for each,
  in the reverse order of their build; a change of the lot drops each
  element; the log has the events of the taking down.
- R6. In a pause the model gets old with the days, and a repair makes it
  clean.
- R7. The replay model has the scaffold, the formwork, the rough bands
  and the finish as nodes with `from` and `to`; `Check.model` passes.
- R8. The people: the animations of the work and their props; each
  person of a construction on its lot in the days of its tasks.
- R9. The page of the world follows a construction with the camera of
  D11 and the faster clock; a test of `test/js/` loads it and sees the
  hill, the model, the scaffold and some people at the day of a pour;
  the length of a film is the days over the scale.
- R10. `scripts/timelapse.mjs` makes a video of a construction.

## 7. Steps

1. This plan.
2. The hill: the tiles of the game in `priv/terrain/nui_nho/`,
   `World.Terrain`, the place `nui_nho` and its lots, the ground on the
   page of the world, `"geo"` (R2, R3).
3. One clock for the world in days of a site, and the order of a real
   site (R1).
4. The methods and the history of the statue (R4).
5. A change that takes down what it drops (R5).
6. The site that gets old in a pause (R6).
7. The stages of a construction as parts of the replay model (R7).
8. The work of the people (R8).
9. The page of the world as a time lapse, its test, and the video
   script; the two time lapses of the statue for the owner (R9, R10).

## 8. Acceptance criteria

- Each requirement has its test, and the checks of D9 of plan 0004 pass.
- The two time lapses of the statue (`today` and `1974`), each from its
  order over MCP, on the hill: the owner says that they look like the
  building of the statue.
- The model of the statue on the hill goes into the Vũng Tàu game at its
  place with no change of its data.

## 9. Open questions

None now.

## 10. State (2026-11-10)

Each step is done, on the branch `feat/0006-hill`:

| Step | Commit | What is there |
|---|---|---|
| 2 | `feat(places): the hill of Núi Nhỏ from the Vũng Tàu game` | The 55 tiles of the game, `World.Terrain`, the place `nui_nho` and its lots, `"geo"`, the ground on the page. |
| 3 | `feat(site): one clock for the world, in days of a site` | `World.Clock.world/0`, `priv/standards/site.json`, `World.Site`; the statue takes 355 days with the machines of today. |
| 5 | `feat(construction): a change takes down what it drops` | The tasks `remove/NODE`, `element_removed`, the change of the lot. |
| 4, 6 | `feat(site): the methods of a site, and the history of the statue` | `World.Method`, the six stages of 1974 with their dates and their fit, the old statue in a pause and its repair. |
| 7 | `feat(statue): the stages of a site as parts of the model` | The scaffold, the forms and the rough bands as nodes that come and go (`down`), the replay with `from` and `to`. |
| 8, 9 | `feat(world): the people at work, and the time lapse of a construction` | The work of the trades and the props of a site; the world page as a time lapse; `scripts/timelapse_log.exs` and `scripts/timelapse.mjs`. |

What is not as the plan says:

- The rates of the crews are estimates, each with its reason: the
  chapters of the norms of Việt Nam on the concrete, the masonry and the
  finish (Thông tư 12/2021/TT-BXD, Phụ lục II) were not found. The waits
  of the forms cite ACI 347R-14.
- The means of each stage (the owner, 2026-11-10: "show whatever
  methods the people were using at the time to build"): the crane only
  where the history allows it (today); in 1974 and 1992 to 1994 the
  carriers of the path, the mixing by hand and a pulley. The sources say
  that there was no machine in 1992 to 1994 (grandart.vn); for 1974 they
  say only that the carry was the biggest difficulty, so the rest is an
  estimate.
- The film (the owner, 2026-11-10: the pauses too long, the work too
  fast, few people, no weeds): the work at one speed (5 days in a
  second) and a pause faster (a year in a second), each part that grows
  over its task, the crew of each task, the grass of a pause. The
  scaffold goes in the first year of the pause and comes back for the
  repair of 1992 (no source: an estimate).
- The people of the film (the owner, 2026-11-10: "they do not move";
  "when construction pauses, they just disappear. They should leave
  instead"): each person moves all the time round the place of its task
  and works at each stop; the crew stays with its person from task to
  task; a free person waits round the lot; at the end of a stage the
  people walk out on the way to the lot (the path of the hill) and the
  carriers walk down the path while the day waits 4 s at the start of
  the pause.
- The people at work (the owner, 2026-11-11: "they came after the base
  already had some layers", "They should be climbing up stairs, do
  something on the construction, not moving around"): the day waits 4 s
  at the start of each stage while its people walk in; each person of a
  crew has its own place at the work and works there; they climb onto
  the base and up a ladder at the corner of the scaffold to the deck of
  the band (the scaffold of the model has no ladder: the page puts one
  at the corner to the side of the path); the free helpers mix at the
  heap of the materials.
- The reliefs are a part of the base, not a stage of their own.
- A person is a task: the crews of the rates are in the days of a task,
  and the page shows one person for each task.
- The far level has no cast, so no bands, forms or scaffold: a time lapse
  is at the level mid or near.
- The logs of the films come from `scripts/timelapse_log.exs` (the job of
  the order, as the MCP tool `build` makes it), not from a call over MCP.
