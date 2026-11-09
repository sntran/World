"""The parts that the measure tools share (plan 0005).

The files of a measure:

- cameras.json: {"FRAME": {"width", "height", "model", "params",
  "rotation" (3 x 3, camera from world), "translation" (3)}}. The model
  of a camera is a model of COLMAP: SIMPLE_PINHOLE, PINHOLE,
  SIMPLE_RADIAL or RADIAL.
- marks.json: {"FEATURE": {"FRAME": [u, v]}}, in pixels of the frame.
- points.json: {"FEATURE": {"xyz": [x, y, z], "frames": n,
  "error_px": e}}, in the units of the cameras.
"""

import json

import numpy as np


def load(path):
    with open(path) as f:
        return json.load(f)


def save(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")


class Camera:
    """A camera of cameras.json: from a point of the world to a pixel."""

    def __init__(self, c):
        self.width, self.height = c["width"], c["height"]
        self.model, self.params = c["model"], list(c["params"])
        self.R = np.array(c["rotation"], float)
        self.t = np.array(c["translation"], float)

    def intrinsics(self):
        p = self.params
        if self.model in ("SIMPLE_PINHOLE", "SIMPLE_RADIAL", "RADIAL"):
            f, cx, cy = p[0], p[1], p[2]
            return f, f, cx, cy
        if self.model == "PINHOLE":
            return p[0], p[1], p[2], p[3]
        raise ValueError(f"no camera model {self.model}")

    def distort(self, x, y):
        r2 = x * x + y * y
        if self.model == "SIMPLE_RADIAL":
            k = 1 + self.params[3] * r2
        elif self.model == "RADIAL":
            k = 1 + self.params[3] * r2 + self.params[4] * r2 * r2
        else:
            k = 1.0
        return x * k, y * k

    def project(self, X):
        """The pixels of the points X (n x 3), and which are in front."""
        Y = np.atleast_2d(X) @ self.R.T + self.t
        front = Y[:, 2] > 1e-9
        z = np.where(front, Y[:, 2], 1.0)
        x, y = self.distort(Y[:, 0] / z, Y[:, 1] / z)
        fx, fy, cx, cy = self.intrinsics()
        return np.stack([fx * x + cx, fy * y + cy], 1), front

    def undistort(self, uv):
        """The normalized point (no distortion) of a pixel."""
        fx, fy, cx, cy = self.intrinsics()
        xd, yd = (uv[0] - cx) / fx, (uv[1] - cy) / fy
        x, y = xd, yd
        for _ in range(20):
            xx, yy = self.distort(x, y)
            x, y = x + (xd - xx), y + (yd - yy)
        return x, y

    def center(self):
        return -self.R.T @ self.t


def cameras(path):
    return {name: Camera(c) for name, c in load(path).items()}


def triangulate(cams, obs):
    """The point in 3D of the pixels obs {FRAME: [u, v]} (least squares on
    the rays, with no distortion), and the largest error in pixels."""
    rows = []
    for name, uv in obs.items():
        cam = cams[name]
        x, y = cam.undistort(uv)
        P = np.hstack([cam.R, cam.t[:, None]])
        rows += [x * P[2] - P[0], y * P[2] - P[1]]
    X = np.linalg.svd(np.array(rows))[2][-1]
    X = X[:3] / X[3]
    err = max(float(np.linalg.norm(cams[n].project(X)[0][0] - np.array(uv))) for n, uv in obs.items())
    return X, err


def umeyama(A, B):
    """The scale s, the rotation R and the move t that put the points A on
    the points B (s R a + t = b), in the least squares."""
    A, B = np.asarray(A, float), np.asarray(B, float)
    ma, mb = A.mean(0), B.mean(0)
    A0, B0 = A - ma, B - mb
    U, S, Vt = np.linalg.svd(B0.T @ A0 / len(A))
    D = np.eye(3)
    D[2, 2] = np.sign(np.linalg.det(U @ Vt))
    R = U @ D @ Vt
    s = float((S * np.diag(D)).sum() / ((A0**2).sum() / len(A)))
    return s, R, mb - s * R @ ma


def point(points, name):
    """A point of points.json, or the mean of points with "A+B"."""
    names = name.split("+")
    return np.mean([np.array(points[n]["xyz"], float) for n in names], 0)
