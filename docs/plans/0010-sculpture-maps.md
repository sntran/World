# Plan 0010: The detail of a sculpture in maps, in parts, and at once

Status: In progress (the owner, 2026-11-13: "You make decisions and
proceed all the way to achieve that level of Sony Dreams!").

Depends on: plan 0009 (a sculpture with a fine finish, a rich
vocabulary, and motion).

## 1. Goal

At the end, the detail of a model from edits does not depend on the size
of its cells or on the count of its triangles:

- **The maps have the detail.** A sculpture of few triangles has a color
  map and a normal map, made from the field of its edits at each texel:
  a scale of a fish, a ray of a fin and the border of a pupil are as
  sharp as the texels, at each level of detail.
- **A small part has small cells.** A sculpture can have details:
  sculptures of their own, with their own cells, on the same bones.
- **A change shows at once.** A live sculpture gives a coarse piece of a
  change first, then the fine piece.
- **More bodies move.** A sculpture with the bones of another body plan
  has its clips.

## 2. What the owner asked

The message of the status line, after the report of plan 0009. That
report named the limits: cells of one size, one body plan with clips,
and R5 of plan 0009. The builder decides the order and each decision
here; the owner can change each one.

## 3. The state before this plan

- The color of a sculpture is the color of each point of its mesh, and
  its normal is the normal of each point. A detail smaller than about
  three cells is not in the model: the pupil of the carp needs cells of
  2.5 mm, and the near level needs 30,000 triangles for its scales.
- At mid and far a pattern of colors is its mean color.
- A sculpture has cells of one size.
- A change of one edit of a live sculpture of 1,000 edits shows its
  first new piece after 0.10 s to 0.18 s, and its last after 0.41 s to
  0.53 s.
- Only the body plan of a fish gives clips to a sculpture.

## 4. Out of scope

- A renderer, and a tool with a screen to sculpt by hand (plan 0009).
- Code that is not Elixir or Erlang for the field (a NIF, a GPU).

## 5. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **Maps from the field.** With `bake` in its data (the side of the image at a level, in texels), a sculpture has a color map and a normal map. Each texel is a place on a triangle of the mesh; its color is the color of the edits there, and its normal comes from the gradient of the field there. The mesh has no color for each point then. | This is how a model of a game gets its detail: a fine surface is baked on a mesh of few triangles. World has the fine surface as a function, so the bake needs no fine mesh. Dreams draws its field as points; a GLB for any app needs maps. |
| D2 | **A chart for each triangle.** Each triangle has its own right triangle of texels, two in a square, with a border of one texel that has the values of the field past the edge. The size of a square follows the area of its triangle. The squares go into the image in rows, the largest first. The sampler of the image has no smaller copies (no mipmaps): a level of detail has its own image. | A chart for each triangle needs no cut of the mesh into flat pieces, and has no stretch that the user must repair. The border keeps a texel of one chart out of the next one. |
| D3 | **The gradient at a texel from its neighbors.** The texels of a chart are on the plane of its triangle. The change of the field from a texel to the next gives the gradient in the plane, and one more value off the plane gives the rest. The edits of a triangle are the edits of its brick that reach its ball. | Two values of the field for each texel, each with a short list: the bake of an image of 512 texels must take about one second. |
| D4 | **The normal map is in the tangent space of glTF**, with the tangents that `World.GLB` gives to a primitive with a normal map. The bake uses the same rule for the tangent of each corner. | A skinned mesh turns its tangents with its bones; each app reads the same map. |
| D5 | **Details** (`details` in the data of the skill): each one is a sculpture of its own (its edits, its cells, its budget, a mirror), built with its own tree, and its meshes are in the same part or figure. | Dreams makes a figure from many sculptures, each with its own detail. A barbel of 3 mm needs cells of 1 mm only in its own small box. |
| D6 | **A live sculpture gives a coarse piece first.** A change walks the tree at cells of 4 times the size first (1/16 of the work), sends those pieces with their level, then the fine pieces. | The eye needs an answer in less than 0.1 s; the fine surface can come later. |
| D7 | **The body plan of a bird** for a sculpture with bones, with its clips (`walk`, `idle`, `peck`, `flap`): its animations need no clips of a template. | A second body plan proves that the bones of a sculpture are general. |

## 6. Requirements

- **R1.** The color of a baked sculpture at a place of its surface (the
  texel of its image there) is the color of the edits at that place,
  within 8 of 255, where the color changes over more than one texel; a
  sharp border of two colors is at most one texel wide.
- **R2.** The normal of a baked ball of 200 triangles, from its normal
  map and its tangents, is within 2 degrees of the normal of the ball at
  each texel of a chart. A relief smaller than a triangle (a bump of
  1/10 of a cell) is in the normal map.
- **R3.** The charts of two triangles share no texel; the values of a
  chart go one texel past its edges.
- **R4.** The bake of an image of 512 texels for the carp at mid takes
  less than 1.5 s, and of 1,024 texels at near less than 5 s (4
  schedulers).
- **R5.** The GLB of a baked sculpture, with bones or with none, passes
  the validator of glTF; its materials have the two maps.
- **R6.** A detail with cells of 1 mm on a sculpture with cells of
  2.5 mm adds less than 0.5 s to the build of the carp.
- **R7.** A change of one edit of a live sculpture of 1,000 edits shows
  its first coarse piece in less than 60 ms.
- **R8.** A sculpture with the bones of a bird has its four clips, and
  its `flap` moves its wings.
- **R9.** The carp of the catalog shows the maps and a detail, with
  shots at each level next to the carp of plan 0009, and its times.

## 7. Steps

1. **The maps** (D1 to D4; R1 to R5): `World.Sculpt.Bake`, the UVs of a
   mesh, the sampler, the data `bake` of the skill.
2. **The carp with maps** (R9, first part): relief for its scales and
   the rays of its fins, shots, times.
3. **Details** (D5; R6): the barbels of the carp.
4. **The coarse piece first** (D6; R7).
5. **The body plan of a bird** (D7; R8).
6. **The measure and the documents** (R9).

## 8. Acceptance criteria

- The tests of R1 to R8.
- The shots and the times of R9.
- The full check passes on the tip of each push.

## 9. Open questions

- **R5 of plan 0009** (a change in less than 7% of the whole): the field
  of each eighth of a brick in the cache. It is not in this plan; D6
  gives the answer that the eye needs.
- **A map of the roughness** (an edit with its own roughness).

## 10. The measure

(Each step adds its measure here.)
