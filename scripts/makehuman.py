"""Make priv/makehuman/ from the CC0 data of MakeHuman.

    python3 scripts/makehuman.py MPFB_DATA PACKS_DIR
    python3 scripts/makehuman.py MPFB_DATA PACKS_DIR KIND...
    python3 scripts/makehuman.py MPFB_DATA --expressions

MPFB_DATA is src/mpfb/data of makehumancommunity/mpfb2 at the commit in
priv/makehuman/README.md. PACKS_DIR has the asset packs of the release
people-packs-1 of sntran/Vung_Tau, each unzipped in a folder with the name
of the pack (makehuman_system_assets/, shirts01/, pants01/). The script
needs Pillow.

The script writes:
- base.obj.gz, rig.json.gz, weights.json.gz: the base mesh, the skeleton
  "game_engine" and its weights.
- targets.bin.gz: the targets of the body of an adult, in a small binary
  format (see World.People.Data).
- expressions.bin.gz: the units of the expressions of the mouth, for
  each of the three origins (the targets of targets/expression/units),
  in the same format. With --expressions, the script writes only this
  file (no packs).
- one folder for each kind of asset: the mesh (.obj.gz), its fit to the
  body (.mhclo.gz or .proxy.gz), and its texture, smaller. The texture
  of a hair is gray (bright_gray), so the hair can have any color.
- assets.json: the list of the assets.

With KIND... (for example teeth tongue), the script writes only the
assets of these kinds, and puts them in assets.json with the others.
"""
import gzip
import json
import os
import shutil
import struct
import sys

from PIL import Image

MPFB, PACKS = sys.argv[1], sys.argv[2]

# The units of the expressions of the mouth (the visemes of
# World.People.Face mix them).
MOUTH = ["compression", "corner-puller", "depression", "depression-retraction", "elevation", "eversion", "open",
         "parling", "part-later", "protusion", "pursing", "retraction", "upward-retraction"]
OUT = os.path.join(os.path.dirname(__file__), "..", "priv", "makehuman")

# The skeleton and the targets of an adult (young to old), with no
# proportions targets.
RACES = ["african", "asian", "caucasian"]
GENDERS = ["female", "male"]
AGES = ["young", "old"]
LEVELS = {"muscle": ["minmuscle", "averagemuscle", "maxmuscle"], "weight": ["minweight", "averageweight", "maxweight"]}

# The assets: kind, name, pack, folder in the pack, the size of the texture.
ASSETS = [
    ("skins", name, "makehuman_system_assets", f"skins/{name}", 1024)
    for name in [
        f"{age}_{origin}_{gender}"
        for age in ["young", "middleage", "old"]
        for origin in ["african", "asian", "caucasian"]
        for gender in ["male", "female"]
    ]
] + [
    ("eyes", "high-poly", "makehuman_system_assets", "eyes/high-poly", None),
    ("eyes", "low-poly", "makehuman_system_assets", "eyes/low-poly", None),
] + [
    ("eye_materials", name, "makehuman_system_assets", "eyes/materials", 256)
    for name in ["blue", "bluegreen", "brown", "brownlight", "deepblue", "green", "grey", "ice", "lightblue"]
] + [
    ("eyebrows", f"eyebrow{n:03}", "makehuman_system_assets", f"eyebrows/eyebrow{n:03}", 256) for n in range(1, 13)
] + [
    ("eyelashes", "eyelashes01", "makehuman_system_assets", "eyelashes/eyelashes01", 256),
] + [
    # The first four hairs have a texture of 1024 pixels; the hairs after
    # them have 512, so the release stays small for the edge.
    ("hair", name, "makehuman_system_assets", f"hair/{name}", 1024 if name in ["short02", "short04", "ponytail01", "bob01"] else 512)
    for name in ["afro01", "bob01", "bob02", "braid01", "long01", "ponytail01", "short01", "short02", "short03", "short04"]
] + [
    ("clothes", name, "makehuman_system_assets", f"clothes/{name}", size)
    for name, size in [
        ("male_casualsuit01", 1024), ("female_casualsuit01", 1024), ("male_worksuit01", 1024),
        ("shoes01", 512), ("shoes02", 512),
        ("male_casualsuit02", 512), ("male_casualsuit03", 512), ("male_casualsuit04", 512),
        ("male_casualsuit05", 512), ("male_casualsuit06", 512), ("male_elegantsuit01", 512),
        ("female_casualsuit02", 512), ("female_elegantsuit01", 512), ("female_sportsuit01", 512),
        ("shoes03", 256), ("shoes04", 256), ("shoes05", 256), ("shoes06", 256), ("fedora01", 256),
    ]
] + [
    ("clothes", "elvs_crude_t-shirt_male", "shirts01", "clothes/elvs_crude_t-shirt_male", 1024),
    ("clothes", "joepal_crude_t-shirt_female", "shirts01", "clothes/joepal_crude_t-shirt_female", 1024),
    ("clothes", "cortu_cargo_pants", "pants01", "clothes/cortu_cargo_pants", 1024),
    ("proxies", "proxy741", "makehuman_system_assets", "proxymeshes/proxy741", None),
    ("proxies", "male1591", "makehuman_system_assets", "proxymeshes/male1591", None),
    ("proxies", "female1605", "makehuman_system_assets", "proxymeshes/female1605", None),
    # The teeth (with the gums) and the tongue: they fit to the helper
    # meshes of the mouth of the base mesh, which the targets of the mouth
    # move.
    ("teeth", "teeth_base", "makehuman_system_assets", "teeth/teeth_base", 256),
    ("tongue", "tongue01", "makehuman_system_assets", "tongue/tongue01", 256),
]


def gz(src, dest):
    with open(src, "rb") as f, gzip.GzipFile(dest, "wb", mtime=0) as g:
        g.write(f.read())


def minify_json(src, dest):
    data = json.load(open(src))
    with gzip.GzipFile(dest, "wb", mtime=0) as g:
        g.write(json.dumps(data, sort_keys=True, separators=(",", ":")).encode())


def target_names():
    names = []
    for r in RACES:
        for g in GENDERS:
            for a in AGES:
                names.append(f"{r}-{g}-{a}")
    for g in GENDERS:
        for a in AGES:
            for m in LEVELS["muscle"]:
                for w in LEVELS["weight"]:
                    names.append(f"universal-{g}-{a}-{m}-{w}")
                    for h in ["minheight", "maxheight"]:
                        names.append(f"height/{g}-{a}-{m}-{w}-{h}")
    return names


def write_targets(dest, folder="macrodetails", names=None):
    """The binary format "XTG2", little-endian: the count of targets; for
    each target the name (u16 length, UTF-8), the count of points n, then
    n indices of points (u16, each the difference from the index before),
    n dx, n dy and n dz (i16, in steps of 0.0025 units of MakeHuman: 0.25
    mm). The columns make the gzip smaller."""
    out = [b"XTG2"]
    names = names or target_names()
    out.append(struct.pack("<I", len(names)))
    for name in names:
        path = os.path.join(MPFB, "targets", folder, name + ".target.gz")
        points = []
        for line in gzip.open(path, "rt"):
            parts = line.split()
            if len(parts) == 4 and not line.startswith("#"):
                points.append((int(parts[0]), *[round(float(v) / 0.0025) for v in parts[1:]]))
        points.sort()
        b = name.encode()
        n = len(points)
        out.append(struct.pack("<H", len(b)) + b + struct.pack("<I", n))
        last = 0
        deltas = []
        for p in points:
            deltas.append(p[0] - last)
            last = p[0]
        out.append(struct.pack(f"<{n}H", *deltas))
        for k in (1, 2, 3):
            out.append(struct.pack(f"<{n}h", *[p[k] for p in points]))
    with gzip.GzipFile(dest, "wb", mtime=0) as g:
        g.write(b"".join(out))


def texture(src, dest_base, size, gray=False):
    im = Image.open(src)
    # glTF wants images with no color profile.
    im.info.pop("icc_profile", None)
    if im.size[0] > size:
        im = im.resize((size, size), Image.LANCZOS)
    if gray:
        im = bright_gray(im)
    if im.mode == "RGBA":
        dest = dest_base + ".png"
        im.save(dest, optimize=True)
    else:
        dest = dest_base + ".jpg"
        im.convert("RGB").save(dest, quality=85, optimize=True)
    return os.path.basename(dest)


GRAY_MEAN = 200


def bright_gray(im):
    """The texture of a hair in gray, with the mean of the parts that are
    not transparent at GRAY_MEAN: the color of the hair is the factor of
    its material, so a hair can have any color (World.People.Human)."""
    im = im.convert("RGBA")
    alpha = im.getchannel("A")
    gray = im.convert("L")
    px = [g for g, a in zip(gray.get_flattened_data(), alpha.get_flattened_data()) if a > 128]
    mean = sum(px) / len(px) if px else 128
    gray = gray.point(lambda g: min(255, round(g * GRAY_MEAN / max(mean, 1))))
    return Image.merge("RGBA", (gray, gray, gray, alpha))


def mean_color(path):
    """The mean color of the parts of a texture that are not transparent."""
    im = Image.open(path).convert("RGBA").resize((64, 64))
    px = [p for p in im.get_flattened_data() if p[3] > 128]
    return [round(sum(p[k] for p in px) / len(px)) for k in range(3)] if px else [128, 128, 128]


def mhmat(folder):
    files = [f for f in os.listdir(folder) if f.endswith(".mhmat")]
    props = {}
    for f in files:
        for line in open(os.path.join(folder, f), encoding="utf-8", errors="replace"):
            parts = line.split(None, 1)
            if len(parts) == 2 and not line.startswith(("#", "//")):
                props.setdefault(parts[0], parts[1].strip())
    return props


def expressions():
    names = [f"units/{race}/mouth-{unit}" for race in RACES for unit in MOUTH]
    write_targets(os.path.join(OUT, "expressions.bin.gz"), "expression", names)


def main():
    if os.path.exists(OUT):
        for entry in os.listdir(OUT):
            if entry != "README.md":
                p = os.path.join(OUT, entry)
                shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
    os.makedirs(OUT, exist_ok=True)
    gz(os.path.join(MPFB, "3dobjs", "base.obj"), os.path.join(OUT, "base.obj.gz"))
    minify_json(os.path.join(MPFB, "rigs", "standard", "rig.game_engine.json"), os.path.join(OUT, "rig.json.gz"))
    minify_json(os.path.join(MPFB, "rigs", "standard", "weights.game_engine.json"), os.path.join(OUT, "weights.json.gz"))
    write_targets(os.path.join(OUT, "targets.bin.gz"))
    expressions()
    assets({}, ASSETS)


def assets(manifest, chosen):
    for kind, name, pack, folder, size in chosen:
        src = os.path.join(PACKS, pack, folder)
        dest = os.path.join(OUT, kind)
        os.makedirs(dest, exist_ok=True)
        entry = {"pack": pack, "license": "CC0"}
        if kind == "eye_materials":
            entry["texture"] = texture(os.path.join(src, f"{name}_eye.png"), os.path.join(dest, name), size)
        else:
            props = mhmat(src)
            for f in sorted(os.listdir(src)):
                if f.endswith(".obj"):
                    gz(os.path.join(src, f), os.path.join(dest, name + ".obj.gz"))
                    entry["obj"] = name + ".obj.gz"
                elif f.endswith((".mhclo", ".proxy")):
                    ext = os.path.splitext(f)[1]
                    gz(os.path.join(src, f), os.path.join(dest, name + ext + ".gz"))
                    entry["fit"] = name + ext + ".gz"
            if size and "diffuseTexture" in props:
                tex = os.path.join(src, os.path.basename(props["diffuseTexture"]))
                entry["texture"] = texture(tex, os.path.join(dest, name), size, gray=kind == "hair")
                entry["color"] = mean_color(tex)
                if kind == "hair":
                    entry["gray"] = GRAY_MEAN
            entry["transparent"] = props.get("transparent", "False") == "True"
        manifest.setdefault(kind, {})[name] = entry

    with open(os.path.join(OUT, "assets.json"), "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")


if PACKS == "--expressions":
    expressions()
elif len(sys.argv) > 3:
    kinds = sys.argv[3:]
    assets(json.load(open(os.path.join(OUT, "assets.json"))), [a for a in ASSETS if a[0] in kinds])
else:
    main()
