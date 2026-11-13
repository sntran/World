# Plans

A plan describes one block of work on World. The owner reads it,
changes it, and approves it. The work of a plan comes after its
approval, as small commits on `main` (`AGENTS.md`).

## Status values

| Status | Meaning |
|---|---|
| Draft | The plan is written. Do not build it. |
| Approved | The owner approved it. The work can start. |
| In progress | The work is in progress. |
| Done | Each step of the plan is done, with its tests and its pictures. |

## Plan file format

Each plan has these sections:

1. Status and dependencies.
2. Goal: what World has at the end.
3. Out of scope.
4. Decisions, with the reason for each decision.
5. Requirements, numbered `R1`, `R2`, and so on.
6. Steps.
7. Acceptance criteria.
8. Open questions.

The builder writes questions and answers under "Open questions". The
builder does not change the requirements: the owner does.

## List of plans

| Number | Name | Status |
|---|---|---|
| 0001 | [The people build on demand](0001-people-build-on-demand.md) | Done (its steps 4 and 5 moved to 0002) |
| 0002 | [The people build any blueprint, as on a real site](0002-build-any-blueprint.md) | In progress |
| 0003 | [World builds real blueprints, and the tests compare them](0003-real-blueprints.md) | In progress |
| 0004 | [The statue of Vũng Tàu looks like the real one](0004-statue-look.md) | In progress |
| 0005 | [From photos to a blueprint: measure, then fit](0005-photos-to-blueprint.md) | In progress |
| 0006 | [The world on one clock, the hill of Núi Nhỏ, and the time lapse of a construction](0006-construction-time-lapse.md) | In progress: each step done; the owner looks at the two time lapses. |
| 0007 | [The people build each model as actors: faster, better, as on a real site](0007-actors-build-faster.md) | In progress |
| 0008 | [A model from edits, made by many hands at once](0008-model-from-edits.md) | In progress |
| 0009 | [A sculpture with a fine finish, a rich vocabulary, and motion](0009-sculpture-finish.md) | Done, but for R5 |
| 0010 | [The detail of a sculpture in maps, in parts, and at once](0010-sculpture-maps.md) | Done, but for R7 |
| 0011 | [World builds any model, on each core](0011-any-model.md) | Done, but for R1 |
| 0012 | [A world of sites, with models that look real](0012-a-world-of-sites.md) | Done, but for a part of R8 |
| 0013 | [Real things from their sources, and long shapes at the cost of their near parts](0013-real-things.md) | Done |
| 0014 | [A landmark in parts, as a site builds it](0014-a-landmark-in-parts.md) | Done, but for the face as a copy |
