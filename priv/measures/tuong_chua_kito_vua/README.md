# The measures of the statue on Núi Nhỏ (plan 0005)

The measures of the statue of Christ on Núi Nhỏ, Vũng Tàu, from one
drone video, with the tools of `scripts/measure/`. No image of the
video is in the repository: only the pixels of the marks and the
cameras that COLMAP solved.

## Source

- The video: YouTube `8ShbTdMaE4g` (2 min 28 s), a copy of 1280 x 720
  that the owner sent on 2026-11-08. The black bands are cut off: each
  frame is 1280 x 544 (`crop=1280:544:0:88`), 4 frames a second.
- `front/`: the shot from 0:23 to 0:35 (frame `NNN.jpg` at 23 s +
  (NNN - 1) / 4 s). The drone is in front of the statue and over it,
  and moves a little: good across and up, bad in depth.
- `back/`: the shot from 1:45 to 1:57 (frame `NNN.jpg` at 105 s +
  (NNN - 1) / 4 s). The drone goes round the statue from its back to its
  side: good in depth.

Each folder has `marks.json` (the features in the frames), `cameras.json`
(the cameras of the marked frames, from `sfm.py`) and `points.json`
(from `tri.py`). The two folders have their own axes and units.

The names of the features go by the side of the statue: `_l` is its
right hand side (+x of World), on the left of a frame from the front
and on the right of a frame from the back.

## Results (2026-11-09)

The scale: 18.4 m from cuff to cuff (vi.wikipedia, Tượng Chúa Kitô Vua
(Vũng Tàu)).

From `front/` (`sizes.py --scale cuff_l_top+cuff_l_bottom
cuff_r_top+cuff_r_bottom 18.4 --axis window_3 window_1 --origin hem`),
metres over the hem:

| Feature | Height |
|---|---|
| Foot of the plinth | -3.70 |
| Windows | 8.16, 10.65, 13.82 |
| Middle of the lower edge of the cape | 15.92 |
| Heart | 19.08 |
| Bottoms of the cuffs | 20.61, 21.31 |
| Tip of the beard | 22.03 |
| Tops of the cuffs | 22.89, 23.25 |
| Widest points of the halo | 25.04, 25.08 |
| Crown | 26.20 |
| Top of the halo | 27.49 |

The check: from the foot of the plinth to the top of the halo, 31.20 m;
the sources give 32 m (-2.5%).

From `back/`:

- The halo is a circle: 3.10 m from its middle to its sides, 2.99 m to
  its top. It leans to the front by 30 degrees: its top is 1.48 m in
  front of its middle (over the head).
- From the tip of one hand to the tip of the other: 23.5 m; each hand
  2.5 to 2.7 m from the top of its cuff.
- The back of the cape (its lowest point at the back) is 4.0 m behind
  the line of the cuffs.

## Limits

- The focal length of each shot comes from the shot (`front/`: 825 px,
  `back/`: 745 px). With the focal length held from 825 to 1500 px, the
  heights of `front/` change by up to 1.2 m (plan 0005, section 8).
- The corners of the cape are not a measure: the cape goes on under the
  sleeves, and a corner is not one point in each frame.
