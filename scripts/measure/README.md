# Measure a real thing from a video (plan 0005)

These tools give the sizes of a real thing from the frames of a video,
by measure and not by eye: COLMAP solves the cameras, a builder marks
the features, and the geometry gives each feature in 3D with its
error. They are out of the checks of CI; World reads only their JSON
files (`priv/measures/`).

## Set up

    python3 -m venv .venv && .venv/bin/pip install -r scripts/measure/requirements.txt
    .venv/bin/python scripts/measure/selftest.py      # prints ok

The tools run on a CPU. The frames, the photos and the database of
COLMAP stay out of the repository.

## Steps

1. **The frames of a shot.** Find the black bands, then take 4 frames
   a second of one shot (a few seconds of one camera move round the
   thing):

       ffmpeg -ss 25 -t 2 -i VIDEO -vf cropdetect -f null -
       ffmpeg -ss START -t SECONDS -i VIDEO -vf "fps=4,crop=W:H:X:Y" -q:v 2 FRAMES/%03d.jpg

2. **The cameras.** `sfm.py FRAMES OUT --frames A,B,C` solves the
   cameras and writes `OUT/cameras.json` for the frames that you mark.
   A shot that breaks into parts gives the largest part.
3. **The marks.** `ruled.py FRAME X0 Y0 X1 Y1 K OUT` makes a larger
   crop with a ruler of the pixels. Write the pixel of each feature in
   three or more frames, far apart in the shot, to `marks.json`:
   `{"FEATURE": {"FRAME": [u, v]}}`. Mark a point that you can find
   again in each frame (the top of a ring, the middle of an edge, a
   window), not a corner that a part hides.
4. **The points.** `tri.py CAMERAS MARKS POINTS` gives each feature in
   3D and its error. A feature with an error over 4 px stops the tool:
   mark it again.
5. **The sizes.** `sizes.py POINTS --scale A B METRES --axis LOW HIGH
   --origin O --check A B METRES` gives the height of each feature in
   metres. One number of a source sets the scale; a second one checks
   it. A name `A+B` is the mean of two features.
6. **The fit of a model.** `fit.py POINTS FEATURES POSE` puts a model on
   the points (the same features on the model, in metres, in the axes
   of World) and gives the error of each feature. `outline.py MODEL
   CAMERAS FRAMES POSE OUT` gives the overlap of the outline of the model
   in each frame, and draws it.

7. **A panel in relief.** `panel.py PHOTO EDGES OUT` makes the textures
   of a flat panel from a photo of it (the points of its top and bottom
   edges), for a role of a drawing with a `panel` (`docs/format.md`).

## What a measure can and cannot give

- The frames of one shot see the thing from one side: the sizes across
  and up are good (some tenths of a metre), the depth is not (metres).
  Depth needs a shot from the side.
- The focal length of a video comes from the video. A shot with little
  move of the camera gives a focal length that can be wrong by 10%,
  and the heights change with it: the check with a second number of a
  source shows it. `sfm.py --focal F` holds the focal length.
- The overlap of `outline.py` counts the white of the frame: a shadow
  side is not white and a white wall behind is. Use it to compare two
  forms of a model, not as a true value.
