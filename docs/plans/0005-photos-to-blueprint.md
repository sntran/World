# 0005 From photos to a blueprint: measure, then fit

| Field | Value |
|---|---|
| Status | Approved (the owner, 2026-11-08) |
| Depends on | Plan 0004 (the statue of Vũng Tàu looks like the real one). |
| Changes | A new folder `scripts/measure/` (the measure tools, out of the checks of CI); the measures of a model in `priv/measures/`; the drawing `tuong_chua_kito_vua`. |

## 1. Goal

A blueprint of a real thing gets its sizes from photos and videos by
measure, not by eye. At the end:

- The cameras of the photos or the frames of a video are solved, so
  each pixel of a frame is a ray in 3D.
- A size of a model is the distance between two points in 3D,
  triangulated from three or more frames, with its error in metres.
- The fit of a model to its photos is a number: the overlap of its
  outline with the real outline in each frame, and the error of each
  marked feature.
- Each size in a drawing names its source: the video or the photo, its
  frames, and the measure.

The statue of Vũng Tàu is the first model. On 2026-11-08 a test with
one drone video of the owner gave these results:

- the cameras of 38 frames, with a mean error of 0.5 px;
- 18 features, each within 1 to 4 px in three frames;
- the two numbers of the sources agree: at 18.4 m from cuff to cuff,
  the statue is 31.2 m from the foot of the plinth to the top of the
  halo (32 m in the sources, 2.6% less).

The eye on single photos gave 1.14 to 1.4 for the ratio of the figure
(hem to halo top) to the span of the cuffs; the measure gives 1.495.

## 2. Out of scope

- Dense reconstruction. Dense matching in COLMAP needs a GPU, and the
  container of the work has none.
- Models and weights with a license for non-commercial use only:
  MASt3R, DUSt3R, SMPL-X, FLAME, and the first checkpoint of VGGT.
- A photo or a video in the repository with no license. The inputs stay
  out of the repository; only the measures (numbers) go in.
- A new body model for the people of World (MakeHuman to Anny). That is
  a later plan (see section 8).

## 3. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **Measure, do not estimate.** COLMAP (BSD license, `pycolmap`) solves the cameras of the frames of a video, or of a set of photos with overlap. | A model of AI that looks at a photo cannot give the right sizes: the photos disagree because of perspective. The cameras remove the perspective. |
| D2 | **The builder marks features; the geometry gives the sizes.** The builder (a person or a model of AI) marks the pixel of each feature (the top of the halo, a cuff, a window) in three or more frames, on ruled crops. Triangulation gives the point in 3D and its error in pixels. A mark with an error over 4 px is marked again. | To say which pixel is a feature is easy to check. To say how many metres a thing has is not. |
| D3 | **One number of a source sets the scale; a second number checks it.** For the statue: 18.4 m from cuff to cuff sets the scale, and 32 m from the foot of the plinth to the top of the halo checks it. | A video has no scale. A second number finds a wrong reading of a source. |
| D4 | **The fit is two numbers.** A similarity transform (Umeyama) puts the model on the measured points: the error of each feature in metres. The outline of the model, drawn with the camera of each frame, overlaps the white of the statue: the overlap (IoU) of each frame. | The owner and the tests see the same numbers, and a change of the model shows its effect. |
| D5 | **The inputs stay out; the measures go in.** The frames and the photos stay in a folder out of the repository. `priv/measures/<model>/` keeps the marks (`marks.json`: frame, pixel), the solved cameras of the marked frames (`cameras.json`), the points in 3D (`points.json`), and a `README.md` with the source of the video or the photos. | The measures can be checked and done again; no file with no license goes into the repository. |
| D6 | **The tools are Python, out of the checks of CI.** `scripts/measure/` has the tools (`sfm.py`, `ruled.py`, `tri.py`, `fit.py`, `outline.py`) and a `requirements.txt` (`pycolmap`, `numpy`, `scipy`, `trimesh`, `pillow`). World reads only the JSON files. | COLMAP has no Elixir binding. The build of World must not need Python. |
| D7 | **Depth needs a side view.** The frames of one shot see the model from one side, so the depth (front to back) has an error of metres. A size in depth comes from a shot from the side, or else from the photos, marked as "by eye". | The test of 2026-11-08: across and up within 0.3 m; in depth, up to 7 m. |

## 4. Requirements

- R1. `scripts/measure/` solves the cameras of the frames of a video and
  writes the cameras of the marked frames to `cameras.json`.
- R2. From `marks.json`, `scripts/measure/tri.py` gives each feature in
  3D with its error in pixels; it stops with an error for a mark over
  4 px.
- R3. `scripts/measure/fit.py` gives the error of each feature of a
  model in metres, and `outline.py` gives the overlap of each frame.
- R4. `priv/measures/tuong_chua_kito_vua/` has the marks, the cameras,
  the points and the source of the video.
- R5. The drawing `tuong_chua_kito_vua` takes its sizes from the
  measures, each with its source ("measured: video, frames 009, 027,
  046").
- R6. A test of World reads `points.json` and checks the built statue:
  each feature across and up within 0.5 m of its measure.

## 5. Steps

1. This plan.
2. The tools of `scripts/measure/` and their README (R1 to R3).
3. The measures of the statue from the drone video: more features
   (the cape, the sleeves, the hands, the plinth, the base), and the
   back of the statue from the second shot of the video (R4).
4. The sizes of the drawing and the shapes of plan 0004 from the
   measures (R5), and the test of R6.
5. The shots of the statue built over MCP, with its outline on the
   frames of the video, next to the photos.

## 6. Acceptance criteria

- Each requirement has its test or its check, and the checks of D9 of
  plan 0004 pass.
- Each feature of the statue across and up is within 0.5 m of its
  measure.
- The overlap of the outline of the statue is in each marked frame
  over a value that the owner sets after step 3.
- The owner says that the statue looks like the statue of the photos.

## 7. The measures of 2026-11-08

Metres over the hem, at 18.4 m from cuff to cuff (frames 009, 027 and
046 of the close shot of the video; the axis: the line of the three
windows):

| Feature | Measure |
|---|---|
| Foot of the plinth | -3.73 |
| Windows | 8.17, 10.66, 13.83 |
| Lower corners of the cape | 14.20, 14.92 |
| Heart | 19.09 |
| Bottoms of the cuffs | 20.62, 21.32 |
| Tip of the beard | 22.04 |
| Tops of the cuffs | 22.90, 23.26 |
| Widest points of the halo | 25.26, 25.31 |
| Crown | 26.21 |
| Top of the halo | 27.51 |

Widths: the cape 8.49 m; the halo 6.04 m; a hand (from the top of its
cuff to the tip) 2.94 m.

## 8. Open questions

- The halo: the measure gives its widest points at 25.3 m and its top
  at 27.5 m, so 2.2 m over its middle, but its half width is 3.0 m. Is
  the ring a circle that leans back, or is a mark wrong? A mark in more
  frames will tell.
- The people of World: Anny (NAVER LABS, 2025: Apache 2.0 for the code,
  CC0 for the assets of MakeHuman) can fit a pose and a shape to a
  photo. Does the owner want a plan for it after this one?
- A side view for the depth: the video has none. Is there one in other
  videos or photos with a license?
