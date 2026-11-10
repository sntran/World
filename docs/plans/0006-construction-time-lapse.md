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
- The times are the days of a real site, from the sources where there
  are sources and from standards of the trades where there are not.
- A page plays it, and a script makes a video of it.

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

## 2. What the sources say about the construction

From the web on 2026-11-10 (each fact with its source; the sources do
not agree on all the dates):

| Fact | Source |
|---|---|
| A first statue (10 m on a base of 5 m) was started in 1972 at Nghinh Phong and stopped on 17 January 1973; it was taken down on 16 February 1974. | vi.wikipedia, Tượng Chúa Kitô Vua (Vũng Tàu); vietcatholic.net, "Thăm tượng đài Kitô Vua trên đỉnh Tao Phùng" |
| The permit for Núi Nhỏ (Tao Phùng) is of 18 March 1974, and the work started after it. | vi.wikipedia |
| The concrete was the work of the engineer Nguyễn Quảng Đức; the sculpture of the sculptor Văn Nhân with about 50 skilled workers ("50 thợ lành nghề"). | vi.wikipedia; vietcatholic.net |
| The foundation was to be 6 m deep; at about 3 m the workers found the hard concrete of tunnels of the French time. | vi.wikipedia; vietcatholic.net |
| Thousands of tonnes of materials went up the hill ("hàng ngàn tấn vật liệu"), on a steep narrow path, with no machines. | vietcatholic.net; grandart.vn |
| Sand and gravel from the Đồng Nai river, marble from Non Nước (Đà Nẵng), white cement from abroad. | vietcatholic.net |
| The rough structure ("phần thô") was done when the work stopped on 30 April 1975. | vietcatholic.net; vi.wikipedia |
| From 1975 the site was left for about 17 years: weeds, and the copper cable of the lightning rod was stolen. | vietcatholic.net |
| The permit to repair and finish the statue (with no change of its design) is of 28 January 1992; the work took about two years. | vi.wikipedia; vietcatholic.net |
| In 1992 to 1994: the four reliefs of the base (Văn Nhân, too old to climb, directed his students from the foot of the hill), a Pietà in front, trees, power and water, a path of about 800 stone steps. | vi.wikipedia; vietcatholic.net |
| The inauguration: 1 December 1994 (vi.wikipedia; en.wikipedia gives 2 December 1994; some pages give 1993 or 1995). | vi.wikipedia; en.wikipedia, Christ of Vũng Tàu |

So the time lapse has three stages: the rough structure (March 1974 to
April 1975, about 13 months), the pause (1975 to 1992), and the finish
(1992 to December 1994). The order and the days of the work inside a
stage have no source: they come from the standards of the trades and are
estimates.

## 3. Out of scope

- A schedule that is a true record of the statue: no source gives it.
  The days in a stage are estimates, each marked so.
- Machines on the site (cranes, trucks on the hill): the sources say
  that there were none.
- Weather other than the sun (rain, clouds).
- The other blueprints. The schedule and the stages are general, but
  only the statue gets its stages in this plan; a house and a vehicle
  come later.

## 4. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **A site schedule in days, apart from the wall time.** Each task of a construction gets a duration in days of a site: its work (from the data of its skill: a volume of concrete, an area of formwork, a count of steps) over the rate of its crew (`priv/standards/`: each rate with its source), and a wait after it (a cure). The log keeps both times: `at` stays the time of the computer, and a new `day` is the time of the site. | The time lapse must show the days of a real site, and the order of the work must not depend on how fast the computer is. |
| D2 | **The order of a real site.** A band of a cast waits for the cure of the band under it; the scaffold of a band goes up before its formwork; the formwork comes off after the cure. The people of the computer can still work at the same time (the build stays fast); the schedule gives each task its days on the site. | On a real site, concrete stands on cured concrete. |
| D3 | **The stages of a site from the sources.** A drawing can give its stages with dates and sources (`"stages"`: the rough structure, a pause, the finish). The tasks of each stage go in its dates; the pause is a part of the film with no work, in fast forward. | The statue took 20 years with a pause of 17; the time lapse must not hide this. |
| D4 | **The steps of the construction are parts of the model.** The replay model (`replay.glb`) gets a node for each state that a person sees on the site: the scaffold of each band, the formwork of each band, each poured band in rough grey concrete, the render of washed stone over it in the finish, the reliefs. Each node has the task that puts it up and the task that takes it down (`"from"`, `"to"`). | The prototype cut the finished model at a height: it cannot show a formwork that comes off, or the grey concrete before the render. |
| D5 | **The people at work.** Each person of the log goes on the site when a task starts, at the place of the task (the foot of the band, the face of the base), with the work of its trade: carry a load up the path, set a panel, pour, trowel, hammer, climb the scaffold. These are new animations of `World.People.Pose`, with new props (a bucket, a sack, a trowel, a hammer) next to the `non_la` that World has. At most 50 people on the site (the 50 skilled workers of the sources), at mid level. | The owner: "show the people at work too, that would be more real". |
| D6 | **The time lapse is a page and a video.** `review/timelapse.html` plays the log of an order with its replay model: one camera, the sun of each day, the people. `scripts/timelapse.mjs` makes a video of it (ffmpeg). The page reads only the files of an order. | Anyone can watch it in a browser, and the owner can send the video. |

## 5. Requirements

- R1. The schedule: each task of a construction has its first and last
  day on the site; a band of a cast starts after the cure of the band
  under it; each rate and each cure has a source, or is an estimate.
- R2. The log of a construction has the day of the site of each event,
  and its head has the start date of the site.
- R3. A drawing can give its stages (dates and sources); the drawing
  `tuong_chua_kito_vua` has the three stages of section 2.
- R4. The replay model has the scaffold, the formwork, the rough bands
  and the finish of the statue as nodes, each with `from` and `to`; the
  check of a model (`Check.model`) passes.
- R5. The people: the animations of the work and their props; each
  person of the log on the site in the days of its tasks.
- R6. `review/timelapse.html` draws the site at each day; a test of
  `test/js/` loads it and sees the model, the scaffold and some people
  at the day of a pour.
- R7. `scripts/timelapse.mjs` makes a video of an order.

## 6. Steps

1. This plan.
2. The schedule and the days in the log (R1, R2), with the rates of the
   trades in `priv/standards/`.
3. The stages of a drawing, and the stages of the statue (R3).
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

- The pause of 17 years: show it in some seconds with a title, or also
  show the rough statue age (darker concrete, weeds)?
- The camera: one place for the whole film (a true time lapse), or some
  cuts (the base close, then the statue far)?
- The length of the film: 30 s, 60 s, or longer?
