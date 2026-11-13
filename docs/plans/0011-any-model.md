# Plan 0011: World builds any model, on each core

Status: In progress (the owner, 2026-11-13: "You could get the project
`World` to the finish line, that can build any models in parallel, the
way Dreams project did for Sony. Get it done! Not just build a model or
two, but any model!").

Depends on: plan 0010 (the maps, the words of an edit, the body plans),
plan 0007 (the measure of each build).

## 1. Goal

A client gives the edits of a model, of any kind, and World builds it:
with no code for that model, with each core of the computer at work in
each stage, and with other models at the same time.

At the end:

- **Any list of edits builds.** No valid list of edits stops a build or
  gives a broken mesh, broken maps or a file that an app refuses. A
  test makes random sculptures and proves it.
- **Each stage of a build uses each core.** The tree and the bricks do
  (3.98 of 4 cores). The collapse (1.63), the charts and the bake
  (1.96) do not: a model from edits uses 2.2 to 2.4 of 4 cores.
- **Many kinds of models are in the catalog, each from edits only:**
  animals on two and on four legs, a bird, a fish, a vehicle, a
  building, a plant, a piece of furniture, a vessel, a tool. Each has
  its levels, its maps and, where it moves, its bones.
- **Many models build at the same time,** with each core in use and a
  limit of the memory.

## 2. What the owner asked

2026-11-13, after plan 0010 (a carp and a robot from edits): "May I
wasn't clear. You are the top frontier, you could get the project
`World` to the finish line, that can build any models in parallel, the
way Dreams project did for Sony. Get it done! Not just build a model or
two, but any model!"

## 3. The state before this plan

The build of the robot at near (12,000 triangles, an image of 1,024
texels), stage by stage, on 4 schedulers (a spin test gives 4 real
cores: 12.1 units of work in a second with 4 processes, 3.5 with 1):

| Stage | Time | Cores at work |
|---|---|---|
| The tree and the bricks | 0.71 s | 3.98 |
| The collapse to the budget | 2.53 s | 1.63 |
| The finish | 0.13 s | 1.46 |
| The charts and the bake | 3.9 s to 4.9 s | 1.96 |
| The PNG files | 0.15 s | 0.98 |
| The scene and the GLB | 0.13 s | 0.66 |
| All of the skill | 7.2 s | 2.41 |

The catalog has two models from edits (the carp, the robot) and three
body plans for a sculpture (`fish`, `bird`, `biped`). No test builds a
random list of edits through the whole skill.

## 4. Out of scope

- An editor for a person (a screen with tools). The edits come as data
  (a drawing, the MCP tools, the live sculpture).
- A GPU. The plan uses the cores of the BEAM.
- The models of the catalog that are not from edits stay as they are.

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **A measure of each stage first,** with the cores at work (`:scheduler_wall_time`), on the robot and on the carp. A stage is done when it uses at least 3 of 4 cores, or when it takes less than 5% of the build. | A change is better only if the numbers say so (plan 0007, D1). |
| D2 | **The collapse works in regions that do not wait for one process.** The measure of the collapse decides the way: more of the work in the regions, or a last pass in parts. | 2.5 s of the 7.2 s of the robot are in a stage with 1.63 cores at work. |
| D3 | **The charts are made for each region of the mesh in its own process,** and the bake sends each process only what it needs. | The charts are made in one process (0.76 s), and the bake uses half of the cores. |
| D4 | **A property test builds random sculptures** through the skill: each shape, each mode, each blend, a finish, copies, a budget, maps. It checks the mesh (each edge in two faces, the budget), the maps (each triangle has texels) and the file (the validator of glTF). | "Any model" needs a proof over many lists of edits, not two models. |
| D5 | **A body on four legs is a body plan of a sculpture** (the bones of a four-legged animal of World, with its walk). | Most animals walk on four legs. |
| D6 | **A gallery in the catalog:** each kind of model from edits only, small (10 to 40 edits), with its levels and its maps, and a line in its sources that it is not a copy of a real thing. The bench builds each one. | The proof that a kind of model needs no code of its own. |
| D7 | **Many models at once share the cores:** the work of each model goes to the same schedulers, and a build waits when the memory of the node has no room. | A node gets many orders at the same time. |

## 6. Requirements

- **R1.** The build of a model from edits at near uses at least 3.2 of 4
  cores on average, and the robot at near takes less than 4.5 s (it
  takes 7.2 s).
- **R2.** 200 random sculptures build with no error; each mesh is
  closed and in its budget; each triangle with an area has a texel in
  the maps; the GLB of each passes the validator.
- **R3.** A sculpture with the bones of an animal on four legs walks:
  its four feet move in the order of a walk, and a foot on the ground
  does not slide.
- **R4.** The catalog has at least 10 kinds of models from edits, and
  the bench builds each at each level.
- **R5.** 8 models from edits built at the same time take less time
  than the 8 one after the other, with at least 3.2 of 4 cores at work.

## 7. Steps

1. **Each stage on each core** (D1 to D3; R1).
2. **Any list of edits builds** (D4; R2).
3. **Four legs, and the gallery** (D5, D6; R3, R4).
4. **Many models at once, the measure and the documents** (D7; R5).

## 8. Acceptance criteria

- The tests of R2 and R3.
- The tables of R1, R4 and R5 in this plan.
- The full check passes on the tip of each push.

## 9. Open questions

(none yet)

## 10. The measure

(the steps write here)
