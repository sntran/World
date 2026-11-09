"""The overlap of the outline of a model with the frames (plan 0005, R3).

    python3 scripts/measure/outline.py MODEL CAMERAS FRAMES POSE OUT
        [--above Z] [--draw A,B,C]

MODEL is a GLB file of World. POSE (from fit.py) puts it in the units of
the cameras. For each frame of CAMERAS, the script draws the outline of
the model with the camera of the frame, and compares it with the white
of the frame near it: the white pixels that touch the outline (the
model is of a white stone). It prints the overlap (intersection over
union) of each frame and their mean, and with --draw, writes the frames
A, B, C to OUT with the outline in red. With --above, only the part of
the model over z = Z (m) counts (for example the figure, not its base).

The overlap is good to compare two forms of a model on the same frames.
A shadow side of the stone is not white, and a white wall behind the
model is: the overlap of a true model is less than 1.
"""

import argparse
import pathlib
import sys

import numpy as np
import trimesh
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from common import cameras, load, save  # noqa: E402


def model_points(path, n=200000, above=None):
    """Points on the surface of the model, in the axes of World."""
    g = trimesh.load(path).to_geometry()
    v = np.asarray(g.vertices)
    # glTF has y up; World has z up and y to the front.
    mesh = trimesh.Trimesh(np.stack([-v[:, 0], v[:, 2], v[:, 1]], 1), g.faces, process=False)
    pts, _ = trimesh.sample.sample_surface(mesh, n, seed=1)
    return pts if above is None else pts[pts[:, 2] > above]


def silhouette(cam, X, shape):
    uv, front = cam.project(X)
    uv = uv[front]
    u, v = np.round(uv[:, 0]).astype(int), np.round(uv[:, 1]).astype(int)
    ok = (u >= 0) & (u < shape[1]) & (v >= 0) & (v < shape[0])
    m = np.zeros(shape, bool)
    m[v[ok], u[ok]] = True
    return ndimage.binary_closing(m, iterations=2)


def white(a):
    return (a.min(2) > 150) & (a.max(2) - a.min(2) < 50)


def overlap(sil, frame):
    ys, xs = np.nonzero(sil)
    if len(ys) == 0:
        return 0.0
    box = np.zeros_like(sil)
    box[max(ys.min() - 15, 0) : ys.max() + 1, max(xs.min() - 15, 0) : xs.max() + 16] = True
    lab, n = ndimage.label(white(frame) & box)
    hit = np.bincount(lab[sil], minlength=n + 1)
    hit[0] = 0
    real = np.isin(lab, np.nonzero(hit > 0.02 * max(hit.sum(), 1))[0])
    return float((sil & real).sum() / max((sil | real).sum(), 1))


def main():
    a = argparse.ArgumentParser()
    a.add_argument("model")
    a.add_argument("cameras")
    a.add_argument("frames")
    a.add_argument("pose")
    a.add_argument("out")
    a.add_argument("--above", type=float)
    a.add_argument("--draw", default="")
    o = a.parse_args()

    cams, pose = cameras(o.cameras), load(o.pose)
    X = pose["s"] * model_points(o.model, above=o.above) @ np.array(pose["R"]).T + np.array(pose["t"])
    out = pathlib.Path(o.out)
    out.mkdir(parents=True, exist_ok=True)
    draw, result = set(filter(None, o.draw.split(","))), {}
    for name, cam in cams.items():
        frame = np.asarray(Image.open(pathlib.Path(o.frames) / name).convert("RGB")).copy()
        sil = silhouette(cam, X, frame.shape[:2])
        result[name] = round(overlap(sil, frame.astype(int)), 3)
        print(f"  {name:12s} overlap {result[name]:.3f}")
        if name in draw:
            frame[sil ^ ndimage.binary_erosion(sil)] = [255, 0, 0]
            Image.fromarray(frame).save(out / f"outline_{name}")
    mean = float(np.mean(list(result.values())))
    print(f"mean overlap {mean:.3f} over {len(result)} frames")
    save(out / "overlap.json", {"frames": result, "mean": round(mean, 3)})


if __name__ == "__main__":
    main()
