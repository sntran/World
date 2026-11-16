"""The textures of a flat panel in relief from a photo of it (plan 0005).

    python3 scripts/measure/panel.py PHOTO EDGES OUT [--size 1536x240]
        [--mirror] [--strength 3.0]

EDGES is {"top": [[x, y], ...], "bottom": [[x, y], ...]}: points along
the top edge and the bottom edge of the panel in the photo, in pixels,
each from its left end to its right end. The panel can be curved in the
photo (a curved wall, the lens): each column of the texture goes from a
point of the top edge to the point of the bottom edge at the same part of
their length.

The tool writes two files of the size of the texture:

- OUT.jpg: the detail of the relief, grey: the light of the photo over
  its mean light in the area round it (the shade of the sun across the
  panel goes away), with more contrast. The color of the material
  (bronze) multiplies it.
- OUT_normal.jpg: a normal texture of glTF from the same light, taken as
  a height (the parts in the sun stand out).

The rows go from the bottom of the panel to its top, so that the
texture has v up, as the UVs of World have z up (World.Surface). With
--mirror the columns go from the right end to the left end: for a face
whose UV u goes to the left of a person who looks at it (the front of a
statue that looks to +y, and its side at -x).
"""

import argparse

import numpy as np
from PIL import Image
from scipy import ndimage


def along(points, n):
    """n points at equal parts of the length of a line of points."""
    p = np.array(points, float)
    d = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(p, axis=0), axis=1))])
    t = np.linspace(0.0, d[-1], n)
    return np.stack([np.interp(t, d, p[:, 0]), np.interp(t, d, p[:, 1])], 1)


def rectify(photo, top, bottom, w, h):
    a = np.asarray(photo.convert("RGB")).astype(float)
    t, b = along(top, w), along(bottom, w)
    f = np.linspace(0.0, 1.0, h)[:, None, None]
    xy = t[None, :, :] * (1 - f) + b[None, :, :] * f
    out = np.stack([ndimage.map_coordinates(a[:, :, c], [xy[:, :, 1], xy[:, :, 0]], order=1, mode="nearest") for c in range(3)], 2)
    return out


def textures(rgb, strength):
    light = rgb.mean(2)
    mean = ndimage.gaussian_filter(light, 40) + 1.0
    detail = np.clip(0.8 * (light / mean) ** 1.8, 0.0, 1.0)
    height = ndimage.gaussian_filter(light, 1.2) - ndimage.gaussian_filter(light, 30)
    height = height / (np.abs(height).max() + 1e-9) * strength
    # The rows of the texture go up: green (the y of the normal) is up in
    # the image of glTF, so to row 0 (World.Textures, washed stone).
    gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) / 2
    gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) / 2
    n = np.stack([-gx, gy, np.ones_like(height)], 2)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return detail, (n + 1) / 2


def main():
    a = argparse.ArgumentParser()
    a.add_argument("photo")
    a.add_argument("edges")
    a.add_argument("out")
    a.add_argument("--size", default="1536x240")
    a.add_argument("--mirror", action="store_true")
    a.add_argument("--strength", type=float, default=3.0)
    o = a.parse_args()

    import json

    edges = json.load(open(o.edges))
    w, h = map(int, o.size.split("x"))
    rgb = rectify(Image.open(o.photo), edges["top"], edges["bottom"], w, h)
    # Row 0 at the bottom of the panel; with --mirror, column 0 at its
    # right. The normals come from the turned image, in its own axes.
    rgb = rgb[::-1, ::-1] if o.mirror else rgb[::-1]
    detail, normal = textures(rgb, o.strength)
    Image.fromarray((detail * 255).round().astype(np.uint8), "L").save(o.out + ".jpg", quality=88)
    Image.fromarray((normal * 255).round().astype(np.uint8), "RGB").save(o.out + "_normal.jpg", quality=92)
    print(f"{o.out}.jpg and {o.out}_normal.jpg: {w} x {h}")


if __name__ == "__main__":
    main()
