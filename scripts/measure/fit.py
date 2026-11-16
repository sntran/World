"""The error of each feature of a model in metres (plan 0005, R3, D4).

    python3 scripts/measure/fit.py POINTS FEATURES POSE

FEATURES is {"FEATURE": [x, y, z]}: the same features on the model, in
metres and in the axes of World (x right, y front, z up). A similarity
transform puts the model on the measured points (Umeyama); the script
prints the error of each feature in the axes of the model, and writes
POSE: {"s", "R", "t"} (from the model to the units of the cameras), for
outline.py.

The frames of one shot see the model from one side, so the error in
depth (y for a shot from the front) can be some metres (D7 of the
plan): read the errors across (x) and up (z).
"""

import argparse
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from common import load, point, save, umeyama  # noqa: E402


def main():
    a = argparse.ArgumentParser()
    a.add_argument("points")
    a.add_argument("features")
    a.add_argument("pose")
    o = a.parse_args()

    pts, feats = load(o.points), load(o.features)
    names = [n for n in feats if all(p in pts for p in n.split("+"))]
    if len(names) < 3:
        sys.exit("fewer than three features in both files")
    A = np.array([feats[n] for n in names], float)
    B = np.array([point(pts, n) for n in names])
    s, R, t = umeyama(A, B)
    errors = []
    print(f"scale {s:.4f} units for one metre")
    for n, m, b in zip(names, A, B):
        e = R.T @ (b - (s * R @ m + t)) / s
        errors.append(e)
        print(f"  {n:16s} x {e[0]:+6.2f}  y {e[1]:+6.2f}  z {e[2]:+6.2f}  m")
    e = np.array(errors)
    print(f"rms across and up: {np.sqrt(np.mean(e[:, 0] ** 2 + e[:, 2] ** 2)):.2f} m; in depth: {np.sqrt(np.mean(e[:, 1] ** 2)):.2f} m")
    save(o.pose, {"s": s, "R": R.tolist(), "t": t.tolist()})


if __name__ == "__main__":
    main()
