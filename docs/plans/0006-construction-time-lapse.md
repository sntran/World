# 0006 The construction of a model as a time lapse

| Field | Value |
|---|---|
| Status | Draft |
| Depends on | Plan 0001 (the people build on demand), plan 0005 (the statue on Núi Nhỏ from its measures). |
| Changes | A site schedule in days (a new module and a table of standards); the stages of a construction as parts of the model (the scaffold, the formwork, each pour, the rough concrete); the skills of a statue; the work of the people (`World.People.Pose`, `World.People.Props`); a time-lapse page and a script that makes its video. |

## 1. Goal

The owner (2026-11-10) saw the replay of the construction of the statue
on Núi Nhỏ and a prototype of a time lapse, and chose the time lapse:
"the construction like a time lapse of the building of the model", with
the people at work, "more real".

At the end, World gives the time lapse of the construction of a model
from its order:

- One camera on the site, and the sun across the sky each day.
- The model goes up as on a real site: the foundation, the base, the
  plinth, then the statue band by band, each with its scaffold and its
  formwork, the concrete that cures, the formwork that comes off.
- The people of the construction at work, each with the work of its
  trade: they carry loads up the hill, set the formwork, pour, and
  finish the surface.
- The times are the days of a real site of today, from the standards of
  the trades: the owner (2026-11-10) wants the statue built as if it is
  built again today, not with the dates of its history.
- A page plays it, with a camera that the viewer sets, and a script
  makes a video of it.

The prototype of 2026-11-10 (a page that cuts the finished model at a
rising height and draws a scaffold) showed the look. It also showed two
things that World does not do as a real site does:

- The times of the log of a construction are the times of the computer
  (the wall time) multiplied by a scale, not days of work: the task
  `field` takes 12 hours in the log only because its calculation is
  slow.
- The people pour the bands of the statue at the same time (four
  casters, the bands 1 to 4). On a real site a band stands on the band
  under it after that band cures.

## 2. The site of today

The owner (2026-11-10): "We don't need to build the statue with the
exact timeline. We just need a time lapse of the building, as if the
statue is rebuilt today."

So the site is a site of today, with the methods of today: a steel
scaffold, formwork of plywood, concrete from a pump, a tower crane for
the loads, and the people of each trade. The history of the statue
(started in 1974, stopped in 1975, finished in 1994; the sources are in
the history of this plan) is not a part of the film. The days of the
work come from the rates of the trades of today, each with its source or
marked as an estimate.

## 3. Out of scope

- The history of the statue (1974 to 1994, a pause of 17 years): the
  owner wants a site of today.
- Weather other than the sun (rain, clouds).
- The other blueprints. The schedule and the stages are general, but
  only the statue gets its stages in this plan; a house and a vehicle
  come later.

## 4. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **A site schedule in days, apart from the wall time.** Each task of a construction gets a duration in days of a site: its work (from the data of its skill: a volume of concrete, an area of formwork, a count of steps) over the rate of its crew (`priv/standards/`: each rate with its source), and a wait after it (a cure). The log keeps both times: `at` stays the time of the computer, and a new `day` is the time of the site. | The time lapse must show the days of a real site, and the order of the work must not depend on how fast the computer is. |
| D2 | **The order of a real site.** A band of a cast waits for the cure of the band under it; the scaffold of a band goes up before its formwork; the formwork comes off after the cure. The people of the computer can still work at the same time (the build stays fast); the schedule gives each task its days on the site. | On a real site, concrete stands on cured concrete. |
| D3 | **The site of today.** A tower crane lifts the loads, a pump gives the concrete, the scaffold is of steel and the formwork of plywood; the crane goes up first and comes down last. The rates of the trades are of today. | The owner: the statue as if it is built again today. |
| D4 | **The steps of the construction are parts of the model.** The replay model (`replay.glb`) gets a node for each state that a person sees on the site: the scaffold of each band, the formwork of each band, each poured band in rough grey concrete, the render of washed stone over it in the finish, the reliefs. Each node has the task that puts it up and the task that takes it down (`"from"`, `"to"`). | The prototype cut the finished model at a height: it cannot show a formwork that comes off, or the grey concrete before the render. |
| D5 | **The people at work.** Each person of the log goes on the site when a task starts, at the place of the task (the foot of the band, the face of the base), with the work of its trade: carry a load, set a panel, guide the hose of the pump, trowel, hammer, climb the scaffold, guide a load of the crane. These are new animations of `World.People.Pose`, with new props (a hard hat, a bucket, a trowel, a hammer) next to the props that World has. At most 50 people on the site (an estimate), at mid level. | The owner: "show the people at work too, that would be more real". |
| D6 | **The time lapse is a page and a video, with a camera that the viewer sets.** `review/timelapse.html` plays the log of an order with its replay model: the sun of each day and the people. Its camera: a turn with the mouse or a finger, places to choose (the front, three quarters, the side, the back, close to the base, over the site), a slow turn round the site, and the camera in the URL (`cam`, `target`, `fov`), so a view can be shared. `scripts/timelapse.mjs` makes a video of it (ffmpeg) with the same camera. The page reads only the files of an order. | The owner (2026-11-10): "Make the camera configurable in the preview." |

## 5. Requirements

- R1. The schedule: each task of a construction has its first and last
  day on the site; a band of a cast starts after the cure of the band
  under it; each rate and each cure has a source, or is an estimate.
- R2. The log of a construction has the day of the site of each event,
  and its head has the start date of the site.
- R3. The site of today: the crane, the pump, the scaffold and the
  formwork have their parts and their tasks, and the statue uses them.
- R4. The replay model has the scaffold, the formwork, the rough bands
  and the finish of the statue as nodes, each with `from` and `to`; the
  check of a model (`Check.model`) passes.
- R5. The people: the animations of the work and their props; each
  person of the log on the site in the days of its tasks.
- R6. `review/timelapse.html` draws the site at each day; its camera
  turns with the mouse, has the places of D6, and takes `cam`, `target`
  and `fov` from the URL; a test of `test/js/` loads it and sees the
  model, the scaffold and some people at the day of a pour.
- R7. `scripts/timelapse.mjs` makes a video of an order, with the camera
  of the URL.

## 6. Steps

1. This plan.
2. The schedule and the days in the log (R1, R2), with the rates of the
   trades in `priv/standards/`.
3. The site of today: the crane, the pump, the scaffold, the formwork
   (R3).
4. The steps of the construction as parts of the replay model: the
   scaffold, the formwork, the rough bands, the finish (R4).
5. The work of the people: the animations and the props (R5).
6. The time-lapse page and its test (R6).
7. The video script, and the time lapse of the statue for the owner
   (R7).

## 7. Acceptance criteria

- Each requirement has its test, and the checks of D9 of plan 0004 pass.
- The time lapse of the statue on Núi Nhỏ, made from its order over
  MCP: the owner says that it looks like the building of the statue.

## 8. Open questions

- The length of the film: 30 s, 60 s, or longer?
- The hill: the site on a flat ground, or on the top of Núi Nhỏ with its
  path (the terrain of the game of Vũng Tàu)?
