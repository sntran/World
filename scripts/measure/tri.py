"""The features of marks.json in 3D (plan 0005, R2).

    python3 scripts/measure/tri.py CAMERAS MARKS POINTS [--max-error 4]

Each feature with marks in two or more frames is triangulated from the
cameras. The script writes POINTS (points.json) and prints the error of
each feature: the largest distance in pixels from a mark to the point
seen by the camera of its frame. A feature with an error over the
largest error (4 px) stops the script with an error: mark it again.
"""

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from common import cameras, load, save, triangulate  # noqa: E402


def main():
    a = argparse.ArgumentParser()
    a.add_argument("cameras")
    a.add_argument("marks")
    a.add_argument("points")
    a.add_argument("--max-error", type=float, default=4.0)
    o = a.parse_args()

    cams, marks = cameras(o.cameras), load(o.marks)
    points, bad = {}, []
    for name, obs in marks.items():
        missing = [f for f in obs if f not in cams]
        if missing:
            sys.exit(f"{name}: no camera for the frames {missing}")
        if len(obs) < 2:
            print(f"{name:16s} one frame only: not in 3D")
            continue
        X, err = triangulate(cams, obs)
        points[name] = {"xyz": [round(float(v), 6) for v in X], "frames": len(obs), "error_px": round(err, 2)}
        flag = "" if err <= o.max_error else "  <- mark again"
        print(f"{name:16s} frames {len(obs)}  error {err:5.2f} px{flag}")
        if err > o.max_error:
            bad.append(name)
    save(o.points, points)
    if bad:
        sys.exit(f"errors over {o.max_error} px: {', '.join(bad)}")


if __name__ == "__main__":
    main()
