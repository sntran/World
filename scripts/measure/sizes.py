"""The sizes in metres from points.json (plan 0005, D3).

    python3 scripts/measure/sizes.py POINTS --scale A B METRES
        --axis LOW HIGH --origin O [--check A B METRES]

A video has no scale: the distance across the axis from the feature A
to the feature B is METRES (one number of a source). The axis is the
line from the feature LOW to the feature HIGH (a line that is vertical
on the model). The script prints the height of each feature over the
feature O along the axis, and with --check, the distance along the axis
from A to B against METRES (a second number of a source). A name
"A+B" is the mean of the features A and B.
"""

import argparse
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from common import load, point  # noqa: E402


def across(v, up):
    return v - v.dot(up) * up


def main():
    a = argparse.ArgumentParser()
    a.add_argument("points")
    a.add_argument("--scale", nargs=3, required=True, metavar=("A", "B", "METRES"))
    a.add_argument("--axis", nargs=2, required=True, metavar=("LOW", "HIGH"))
    a.add_argument("--origin", required=True)
    a.add_argument("--check", nargs=3, action="append", default=[], metavar=("A", "B", "METRES"))
    o = a.parse_args()

    pts = load(o.points)
    up = point(pts, o.axis[1]) - point(pts, o.axis[0])
    up /= np.linalg.norm(up)
    sa, sb, metres = o.scale[0], o.scale[1], float(o.scale[2])
    s = metres / np.linalg.norm(across(point(pts, sa) - point(pts, sb), up))
    origin = point(pts, o.origin)
    print(f"scale: {s:.4f} m for one unit ({sa} to {sb}: {metres} m across the axis)")
    print(f"heights over {o.origin} (m):")
    for name in sorted(pts, key=lambda n: (point(pts, n) - origin).dot(up)):
        print(f"  {name:16s} {(point(pts, name) - origin).dot(up) * s:7.2f}")
    for ca, cb, cm in o.check:
        d = abs((point(pts, cb) - point(pts, ca)).dot(up)) * s
        print(f"check: {ca} to {cb} along the axis {d:.2f} m; the source {float(cm):.2f} m ({(d / float(cm) - 1) * 100:+.1f}%)")


if __name__ == "__main__":
    main()
