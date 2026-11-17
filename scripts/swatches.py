"""Make the swatch of the texture of each item of clothes of MakeHuman.

    python3 scripts/swatches.py

A swatch is the texture at 64 by 64 texels (the mean of the texels of
each square), as a PNG file of red, green and blue, next to the texture:
priv/makehuman/clothes/NAME.swatch.png. At the levels mid and far a
person has no texture on its clothes: each point under an item takes the
color of the swatch at the place of the item over it (World.People.Human).
World cannot read a JPEG file, and a swatch is small.

The garments of World (World.Sewing) have no swatch: each one is of one
fabric, with one color.

It needs Pillow. Run it again when the textures of the clothes change.
"""

import json
import os

from PIL import Image

SIDE = 64
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "priv", "makehuman")


def main():
    with open(os.path.join(ROOT, "assets.json")) as f:
        clothes = json.load(f)["clothes"]

    folder = os.path.join(ROOT, "clothes")
    count = 0

    for name, entry in sorted(clothes.items()):
        if not entry.get("texture"):
            continue

        image = Image.open(os.path.join(folder, entry["texture"])).convert("RGBA")
        # (An RGBA image goes smaller with its alpha: a texel with no alpha
        # does not make its square darker.)
        small = image.resize((SIDE, SIDE), Image.Resampling.BOX).convert("RGB")
        small.save(os.path.join(folder, name + ".swatch.png"), optimize=False, compress_level=9)
        count += 1

    print("Wrote %d swatches." % count)


if __name__ == "__main__":
    main()
