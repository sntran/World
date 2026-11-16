"""A test of the measure tools with no video (plan 0005).

    python3 scripts/measure/selftest.py

Five cameras of a known model look at a box of known points; the marks
are their pixels with a little noise. The triangulation must find the
points, the similarity transform must find the model, and the sizes
must come back. It prints "ok", or stops with an error.
"""

import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from common import Camera, point, triangulate, umeyama  # noqa: E402


def look_at(c, target):
    z = target - c
    z /= np.linalg.norm(z)
    x = np.cross(z, [0.0, 0.0, 1.0])
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    R = np.stack([x, y, z])
    return R, -R @ c


def main():
    rng = np.random.default_rng(7)
    feats = {f"p{i}": rng.uniform([-9, -2, 0], [9, 2, 28]) for i in range(12)}
    cams = {}
    for k in range(5):
        c = np.array([-6.0 + 3 * k, 60.0, 30.0])
        R, t = look_at(c, np.array([0.0, 0.0, 14.0]))
        cams[f"{k:03d}.jpg"] = Camera(
            {"width": 1280, "height": 544, "model": "SIMPLE_RADIAL", "params": [820.0, 640.0, 272.0, 0.01], "rotation": R.tolist(), "translation": t.tolist()}
        )
    marks = {}
    for n, X in feats.items():
        marks[n] = {}
        for name, cam in cams.items():
            uv = cam.project(X)[0][0] + rng.normal(0, 0.3, 2)
            marks[n][name] = uv.tolist()

    points = {}
    for n, obs in marks.items():
        X, err = triangulate(cams, obs)
        assert err < 1.5, (n, err)
        assert np.linalg.norm(X - feats[n]) < 0.5, (n, X, feats[n])
        points[n] = {"xyz": X.tolist()}

    # The same points in other units, turned and moved: Umeyama finds it.
    turn = np.array([[0.0, -1.0, 0.0], [1.0, 0.0, 0.0], [0.0, 0.0, 1.0]])
    A = np.array([feats[n] for n in feats])
    B = 0.7 * A @ turn.T + np.array([3.0, -1.0, 2.0])
    s, R, t = umeyama(A, B)
    assert abs(s - 0.7) < 1e-9 and np.allclose(R, turn) and np.allclose(t, [3.0, -1.0, 2.0])

    d = np.linalg.norm(point(points, "p0") - point(points, "p1"))
    assert abs(d - np.linalg.norm(feats["p0"] - feats["p1"])) < 0.5
    m = point(points, "p0+p1")
    assert np.allclose(m, (point(points, "p0") + point(points, "p1")) / 2)
    print("ok")


if __name__ == "__main__":
    main()
