"""Make priv/makehuman/ from the CC0 data of MakeHuman.

    python3 scripts/makehuman.py MPFB_DATA PACKS_DIR
    python3 scripts/makehuman.py MPFB_DATA PACKS_DIR KIND...
    python3 scripts/makehuman.py MPFB_DATA --expressions
    python3 scripts/makehuman.py MPFB_DATA --targets

MPFB_DATA is src/mpfb/data of makehumancommunity/mpfb2 at the commit in
priv/makehuman/README.md. PACKS_DIR has the asset packs of the release
people-packs-1 of sntran/Vung_Tau, each unzipped in a folder with the name
of the pack (makehuman_system_assets/, shirts01/, pants01/). The script
needs Pillow.

The script writes:
- base.obj.gz, rig.json.gz, weights.json.gz: the base mesh, the skeleton
  "game_engine" and its weights.
- targets.bin.gz: the targets of the body of an adult, the two
  targets of the chest that World.People.Human gives to the body under
  the clothes (no nipples show through), the breasts of a woman, and the
  targets of each slider of MakeHuman, in a small binary format (see
  World.People.Data). With --targets, the script writes only this file
  and sliders.json (no packs).
- sliders.json: the sliders of MakeHuman (targets/target.json), the
  options of the shape of World.People.Human.
- expressions.bin.gz: the units of the expressions of the face (the
  mouth, the eyes, the brows, the nose), for each of the three origins
  (the targets of targets/expression/units), in the same format. With --expressions, the script writes only this
  file (no packs).
- one folder for each kind of asset: the mesh (.obj.gz), its fit to the
  body (.mhclo.gz or .proxy.gz), and its texture, smaller. The texture
  of a hair is gray (bright_gray), so the hair can have any color.
- assets.json: the list of the assets.

With KIND... (for example teeth tongue), the script writes only the
assets of these kinds (or with these names), and puts them in
assets.json with the others.
"""
import colorsys
import gzip
import json
import os
import shutil
import struct
import sys

from PIL import Image, ImageFile, PngImagePlugin, UnidentifiedImageError

MPFB, PACKS = sys.argv[1], sys.argv[2]

# The units of the expressions of the face (the visemes and the face
# shapes of World.People.Face mix them): the mouth, the eyes, the brows
# and the nose.
UNITS = [f"mouth-{u}" for u in ["compression", "corner-puller", "depression", "depression-retraction", "elevation",
                                "eversion", "open", "parling", "part-later", "protusion", "pursing", "retraction",
                                "upward-retraction"]] + \
    [f"eye-{side}-{u}" for side in ["left", "right"] for u in ["closure", "opened-up", "slit"]] + \
    [f"eyebrows-{side}-{u}" for side in ["left", "right"] for u in ["down", "extern-up", "inner-up", "up"]] + \
    ["nose-compression", "nose-depression"] + \
    [f"nose-{side}-{u}" for side in ["left", "right"] for u in ["dilatation", "elevation"]]
OUT = os.path.join(os.path.dirname(__file__), "..", "priv", "makehuman")

# The skeleton and the targets of an adult (young to old), with no
# proportions targets.
RACES = ["african", "asian", "caucasian"]
# The targets that make the nipples small: the clothes fit to the body
# with them (World.People.Human), so no nipples show through.
CHEST = ["breast/nipple-point-decr", "breast/nipple-size-decr"]
# The cup and the firmness of the breasts of a woman of each age, muscle
# and weight (World.People.Human: the options bust and firmness; the mean
# cup and firmness is the base mesh, with no file).
def breasts():
    return [f"breast/female-{a}-{m}-{w}-{c}-{f}"
            for a in AGES for m in LEVELS["muscle"] for w in LEVELS["weight"]
            for c in ["mincup", "averagecup", "maxcup"] for f in ["minfirmness", "averagefirmness", "maxfirmness"]
            if (c, f) != ("averagecup", "averagefirmness")]


def sliders():
    """The sliders of MakeHuman (targets/target.json): each group has its
    categories, and each category has its targets."""
    return json.load(open(os.path.join(MPFB, "targets", "target.json")))


def shape_targets():
    """The targets of the shape: the breasts, then each target of each
    slider (GROUP/NAME), with no target twice."""
    names = CHEST + breasts()
    for group, entry in sorted(sliders().items()):
        for category in entry["categories"]:
            for target in category["targets"]:
                name = f"{group}/{target}"
                if name not in names:
                    names.append(name)
    return names[len(CHEST):]


def write_sliders():
    """sliders.json: target.json of MakeHuman, with no spaces."""
    with open(os.path.join(OUT, "sliders.json"), "w") as f:
        json.dump(sliders(), f, sort_keys=True, separators=(",", ":"))
        f.write("\n")
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
    for name in ["blue", "bluegreen", "brown", "brownlight", "darkbrown", "deepblue", "green", "grey", "ice", "lightblue"]
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
] + [
    # The clothes for travelers, from the asset packs of the community
    # site (static.makehumancommunity.org/assets/assetpacks.html): CC0
    # (shoes01, shirts01, pants01, hats01, gloves01) and CC-BY 4.0
    # (shoes02, shoes03, shirts02, pants02, pants03). CREDITS has the
    # author and the license of each item.
    ("clothes", name, pack, f"clothes/{name}", size)
    for pack, names, size in [
        ("shoes01", ["culturalibre_male_boots", "toigo_ankle_boots_male", "toigo_ankle_boots_female",
                     "scailman_semitransparent_water_boots"], 512),
        ("shoes02", ["punkduck_running_shoes_01", "culturalibre_sneakers", "punkduck_comfortable_sneakers",
                     "punkduck_cycling_shoes", "elvs_caesar_sandals1", "elvs_male_flip_flop_sandals1"], 512),
        ("shoes03", ["punkduck_winter_boots", "mindfront_shoes_biker_boots_male",
                     "mindfront_shoes_biker_boots_female", "maciekg_leather_boots"], 512),
        ("shirts01", ["toigo_fisherman_sweater", "namuhekam_male_polo_shirt", "toigo_basic_tucked_t-shirt"], 512),
        ("shirts02", ["elvs_hooded_sweat_jacket1", "mindfront_knitted_sweater_01", "elvs_male_shirt_untucked_bd1"], 512),
        ("pants01", ["cortu_jeans_shorts", "toigo_wool_pants"], 512),
        ("pants02", ["elvs_jeans_straight_leg", "mindfront_male_trousers_1", "mindfront_female_trousers_1",
                     "punkduck_female_tight_jeans"], 512),
        ("pants03", ["elvs_male_trouser_short_1", "punkduck_female_short_jeans"], 512),
        ("hats01", ["jujube_newsboy_cap"], 256),
        ("gloves01", ["toigo_gloves_short"], 256),
    ]
    for name in names
] + [
    ("proxies", "proxy741", "makehuman_system_assets", "proxymeshes/proxy741", None),
    ("proxies", "male1591", "makehuman_system_assets", "proxymeshes/male1591", None),
    ("proxies", "female1605", "makehuman_system_assets", "proxymeshes/female1605", None),
    # The teeth (with the gums) and the tongue: they fit to the helper
    # meshes of the mouth of the base mesh, which the targets of the mouth
    # move.
    ("teeth", "teeth_base", "makehuman_system_assets", "teeth/teeth_base", 256),
    ("tongue", "tongue01", "makehuman_system_assets", "tongue/tongue01", 256),
]


# The author and the license of each item of the asset packs of the
# community, from the table of its pack page (not from the head of its
# .mhclo file: some heads have the default text of MakeClothes, AGPL3).
# The other assets are CC0, with no author to name.
CREDITS = {
    "toigo_gloves_short": ("MargaretToigo", "CC0"),
    "jujube_newsboy_cap": ("jujube", "CC0"),
    "cortu_jeans_shorts": ("Cortu", "CC0"),
    "toigo_wool_pants": ("MargaretToigo", "CC0"),
    "elvs_jeans_straight_leg": ("Elvaerwyn", "CC-BY"),
    "mindfront_female_trousers_1": ("Mindfront", "CC-BY"),
    "mindfront_male_trousers_1": ("Mindfront", "CC-BY"),
    "punkduck_female_tight_jeans": ("punkduck", "CC-BY"),
    "elvs_male_trouser_short_1": ("Elvaerwyn", "CC-BY"),
    "punkduck_female_short_jeans": ("punkduck", "CC-BY"),
    "namuhekam_male_polo_shirt": ("namuhekam", "CC0"),
    "toigo_basic_tucked_t-shirt": ("MargaretToigo", "CC0"),
    "toigo_fisherman_sweater": ("MargaretToigo", "CC0"),
    "elvs_hooded_sweat_jacket1": ("Elvaerwyn", "CC-BY"),
    "elvs_male_shirt_untucked_bd1": ("Elvaerwyn", "CC-BY"),
    "mindfront_knitted_sweater_01": ("Mindfront", "CC-BY"),
    "culturalibre_male_boots": ("culturalibre", "CC0"),
    "scailman_semitransparent_water_boots": ("scailman", "CC0"),
    "toigo_ankle_boots_female": ("MargaretToigo", "CC0"),
    "toigo_ankle_boots_male": ("MargaretToigo", "CC0"),
    "culturalibre_sneakers": ("culturalibre", "CC-BY"),
    "elvs_caesar_sandals1": ("Elvaerwyn", "CC-BY"),
    "elvs_male_flip_flop_sandals1": ("Elvaerwyn", "CC-BY"),
    "punkduck_comfortable_sneakers": ("punkduck", "CC-BY"),
    "punkduck_cycling_shoes": ("punkduck", "CC-BY"),
    "punkduck_running_shoes_01": ("punkduck", "CC-BY"),
    "maciekg_leather_boots": ("MaciekG", "CC-BY"),
    "mindfront_shoes_biker_boots_female": ("Mindfront", "CC-BY"),
    "mindfront_shoes_biker_boots_male": ("Mindfront", "CC-BY"),
    "punkduck_winter_boots": ("punkduck", "CC-BY"),
}


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


def write_targets(dest, folder="macrodetails", names=None, extra=()):
    """The binary format "XTG2", little-endian: the count of targets; for
    each target the name (u16 length, UTF-8), the count of points n, then
    n indices of points (u16, each the difference from the index before),
    n dx, n dy and n dz (i16, in steps of 0.0025 units of MakeHuman: 0.25
    mm). The columns make the gzip smaller."""
    out = [b"XTG2"]
    paths = [(name, os.path.join(folder, name)) for name in names or target_names()]
    paths += [(name, name) for name in extra]
    out.append(struct.pack("<I", len(paths)))
    for name, rel in paths:
        path = os.path.join(MPFB, "targets", rel + ".target.gz")
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


def open_image(src):
    """The image of a file. A PNG file with a bad checksum in its color
    profile (sandaltex.png of elvs_caesar_sandals1) is not an image for
    Image.open; the PNG reader reads it when it skips the checksums. The
    script drops the color profile anyway."""
    try:
        return Image.open(src)
    except UnidentifiedImageError:
        ImageFile.LOAD_TRUNCATED_IMAGES = True
        try:
            im = PngImagePlugin.PngImageFile(src)
            im.load()
            return im
        finally:
            ImageFile.LOAD_TRUNCATED_IMAGES = False


def texture(src, dest_base, size, gray=False, recolor=None):
    im = open_image(src)
    if recolor:
        im = recolor(im)
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


def dark_iris(im):
    """The iris of "brown" (red-brown) as a dark brown, the usual color of
    the eyes in Viet Nam: a pixel with a saturation of 0.3 or more (the
    iris, not the white of the eye) goes to a hue of 27 degrees, with 0.55
    of its saturation and 0.5 of its value (fully at a saturation of 0.5)."""
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, a = px[x, y]
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if s > 0.3:
                k = min((s - 0.3) / 0.2, 1.0)
                h, s, v = h + (0.075 - h) * k, s + (s * 0.55 - s) * k, v + (v * 0.5 - v) * k
                px[x, y] = tuple(round(c * 255) for c in colorsys.hsv_to_rgb(h, s, v)) + (a,)
    return im


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
    im = open_image(path).convert("RGBA").resize((64, 64))
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
    names = [f"units/{race}/{unit}" for race in RACES for unit in UNITS]
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
    write_targets(os.path.join(OUT, "targets.bin.gz"), extra=CHEST + shape_targets())
    write_sliders()
    expressions()
    assets({}, ASSETS)


def assets(manifest, chosen):
    for kind, name, pack, folder, size in chosen:
        src = os.path.join(PACKS, pack, folder)
        dest = os.path.join(OUT, kind)
        os.makedirs(dest, exist_ok=True)
        author, license = CREDITS.get(name, (None, "CC0"))
        entry = {"pack": pack, "license": license, **({"author": author} if author else {})}
        if kind == "eye_materials" and name == "darkbrown":
            entry["texture"] = texture(os.path.join(src, "brown_eye.png"), os.path.join(dest, name), size, recolor=dark_iris)
        elif kind == "eye_materials":
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
elif PACKS == "--targets":
    write_targets(os.path.join(OUT, "targets.bin.gz"), extra=CHEST + shape_targets())
    write_sliders()
elif len(sys.argv) > 3:
    kinds = sys.argv[3:]
    assets(json.load(open(os.path.join(OUT, "assets.json"))), [a for a in ASSETS if a[0] in kinds or a[1] in kinds])
else:
    main()
