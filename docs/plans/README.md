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
| 0006 | [The world on one clock, the hill of Núi Nhỏ, and the time lapse of a construction](0006-construction-time-lapse.md) | In progress |
