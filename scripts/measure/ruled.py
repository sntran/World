"""A crop of a frame, larger, with a ruler of its pixels (plan 0005, D2).

    python3 scripts/measure/ruled.py FRAME X0 Y0 X1 Y1 K OUT

The crop is from (X0, Y0) to (X1, Y1), K times larger. A red mark is at
each 10 pixels of the frame on the four sides, a longer mark and the
number at each 50. A feature is at the pixel X0 + x / K, Y0 + y / K of
the frame, for the pixel (x, y) of the crop.
"""

import sys

from PIL import Image, ImageDraw


def ruled(src, x0, y0, x1, y1, k, out):
    im = Image.open(src).convert("RGB").crop((x0, y0, x1, y1))
    im = im.resize((im.width * k, im.height * k), Image.LANCZOS)
    d = ImageDraw.Draw(im)
    for x in range(x0 - x0 % 10 + 10, x1, 10):
        X, n = (x - x0) * k, 30 if x % 50 == 0 else 14
        d.line([(X, 0), (X, n)], fill="red")
        d.line([(X, im.height - n), (X, im.height)], fill="red")
        if x % 50 == 0:
            d.text((X + 2, 30), str(x), fill="red")
    for y in range(y0 - y0 % 10 + 10, y1, 10):
        Y, n = (y - y0) * k, 30 if y % 50 == 0 else 14
        d.line([(0, Y), (n, Y)], fill="red")
        d.line([(im.width - n, Y), (im.width, Y)], fill="red")
        if y % 50 == 0:
            d.text((32, Y + 2), str(y), fill="red")
    im.save(out)


if __name__ == "__main__":
    src, x0, y0, x1, y1, k, out = sys.argv[1:8]
    ruled(src, int(x0), int(y0), int(x1), int(y1), int(k), out)
