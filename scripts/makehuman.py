"""Make priv/makehuman/ from the CC0 data of MakeHuman.

    python3 scripts/makehuman.py MPFB_DATA PACKS_DIR

MPFB_DATA is src/mpfb/data of makehumancommunity/mpfb2 at the commit in
priv/makehuman/README.md. PACKS_DIR has the asset packs of the release
people-packs-1 of sntran/Vung_Tau, each unzipped in a folder with the name
of the pack (makehuman_system_assets/, shirts01/, pants01/). The script
needs Pillow.

The script writes:
- base.obj.gz, rig.json.gz, weights.json.gz: the base mesh, the skeleton
  "game_engine" and its weights.
- targets.bin.gz: the targets of the body of an adult, in a small binary
  format (see Xuong.Human.Targets).
- one folder for each kind of asset: the mesh (.obj.gz), its fit to the
  body (.mhclo.gz or .proxy.gz), and its texture, smaller.
- assets.json: the list of the assets.
"""
import gzip
import json
import os
import shutil
import struct
import sys

from PIL import Image

MPFB, PACKS = sys.argv[1], sys.argv[2]
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
        "young_asian_male", "young_asian_female", "middleage_asian_male", "middleage_asian_female",
        "old_asian_male", "old_asian_female", "young_caucasian_male", "young_caucasian_female",
        "young_african_male", "young_african_female",
    ]
] + [
    ("eyes", "high-poly", "makehuman_system_assets", "eyes/high-poly", None),
    ("eyes", "low-poly", "makehuman_system_assets", "eyes/low-poly", None),
    ("eye_materials", "brown", "makehuman_system_assets", "eyes/materials", 256),
    ("eyebrows", "eyebrow001", "makehuman_system_assets", "eyebrows/eyebrow001", 256),
    ("eyebrows", "eyebrow010", "makehuman_system_assets", "eyebrows/eyebrow010", 256),
    ("eyelashes", "eyelashes01", "makehuman_system_assets", "eyelashes/eyelashes01", 256),
    ("hair", "short02", "makehuman_system_assets", "hair/short02", 1024),
    ("hair", "short04", "makehuman_system_assets", "hair/short04", 1024),
    ("hair", "ponytail01", "makehuman_system_assets", "hair/ponytail01", 1024),
    ("hair", "bob01", "makehuman_system_assets", "hair/bob01", 1024),
    ("clothes", "male_casualsuit01", "makehuman_system_assets", "clothes/male_casualsuit01", 1024),
    ("clothes", "female_casualsuit01", "makehuman_system_assets", "clothes/female_casualsuit01", 1024),
    ("clothes", "male_worksuit01", "makehuman_system_assets", "clothes/male_worksuit01", 1024),
    ("clothes", "shoes01", "makehuman_system_assets", "clothes/shoes01", 512),
    ("clothes", "shoes02", "makehuman_system_assets", "clothes/shoes02", 512),
    ("clothes", "elvs_crude_t-shirt_male", "shirts01", "clothes/elvs_crude_t-shirt_male", 1024),
    ("clothes", "joepal_crude_t-shirt_female", "shirts01", "clothes/joepal_crude_t-shirt_female", 1024),
    ("clothes", "cortu_cargo_pants", "pants01", "clothes/cortu_cargo_pants", 1024),
    ("proxies", "proxy741", "makehuman_system_assets", "proxymeshes/proxy741", None),
    ("proxies", "male1591", "makehuman_system_assets", "proxymeshes/male1591", None),
    ("proxies", "female1605", "makehuman_system_assets", "proxymeshes/female1605", None),
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


def write_targets(dest):
    """The binary format "XTG2", little-endian: the count of targets; for
    each target the name (u16 length, UTF-8), the count of points n, then
    n indices of points (u16, each the difference from the index before),
    n dx, n dy and n dz (i16, in steps of 0.0025 units of MakeHuman: 0.25
    mm). The columns make the gzip smaller."""
    out = [b"XTG2"]
    names = target_names()
    out.append(struct.pack("<I", len(names)))
    for name in names:
        path = os.path.join(MPFB, "targets", "macrodetails", name + ".target.gz")
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


def texture(src, dest_base, size):
    im = Image.open(src)
    # glTF wants images with no color profile.
    im.info.pop("icc_profile", None)
    if im.size[0] > size:
        im = im.resize((size, size), Image.LANCZOS)
    if im.mode == "RGBA":
        dest = dest_base + ".png"
        im.save(dest, optimize=True)
    else:
        dest = dest_base + ".jpg"
        im.convert("RGB").save(dest, quality=85, optimize=True)
    return os.path.basename(dest)


def mean_color(path):
    """The mean color of the parts of a texture that are not transparent."""
    im = Image.open(path).convert("RGBA").resize((64, 64))
    px = [p for p in im.getdata() if p[3] > 128]
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

    manifest = {}
    for kind, name, pack, folder, size in ASSETS:
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
                entry["texture"] = texture(tex, os.path.join(dest, name), size)
                entry["color"] = mean_color(tex)
            entry["transparent"] = props.get("transparent", "False") == "True"
        manifest.setdefault(kind, {})[name] = entry

    with open(os.path.join(OUT, "assets.json"), "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")


main()
